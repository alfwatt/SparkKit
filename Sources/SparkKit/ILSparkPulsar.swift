import Foundation
import QuartzCore
import KitBridge
#if SWIFT_PACKAGE
import KitBridgeSwift
#endif
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// a label across the top of a pulsar plot, spanning the segments which hold its values
public struct ILSparkPulsarSpan {
    public let title: String
    public let values: ClosedRange<Int>

    public init(title: String, values: ClosedRange<Int>) {
        self.title = title
        self.values = values
    }
}

/// a label along the bottom of a pulsar plot, at a value index, which can be between values
public struct ILSparkPulsarMark {
    public let title: String
    public let position: Double

    public init(title: String, position: Double) {
        self.title = title
        self.position = position
    }
}

/// Draws a series of spectra as curves stacked up the view, the newest at the bottom,
/// like the pulsar plot on the cover of Unknown Pleasures
///
/// the values of each spectrum are split into segments of contiguous values, each segment gets its own smooth curve and the
/// segments are drawn with gaps between them, the outer segments run flat to the edges, each curve hides the curves behind it
///
/// the style's background is the plot, which should be opaque so each curve hides the ones behind it, the older curves are
/// in the stroke color and the newest in the fill color, the older lines are the style's width and the newest half again as wide
@objc(ILSparkPulsar)
@objcMembers
open class ILSparkPulsar: ILSparkView, ILStreamDataDelegate {
    private let plotLayer = CALayer()

    /// the style pulsar plots start with, white lines on black with the newest in orange, without a border
    public static let defaultPulsarStyle: ILSparkStyle = {
        let style = ILSparkStyle()
        style.background = .black
        style.stroke = .white
        style.fill = .systemOrange
        style.bordered = false
        style.width = ILPathlineWidth
        return style
    }()

    /// a stream of spectra, each record is a spectrum, its values as fractions of the stream's value range are scaled to the
    /// maximum value, the newest records are drawn and each record appended is added as the newest curve
    public var stream: ILStreamData? {
        didSet {
            oldValue?.removeObserver(self)
            stream?.addObserver(self)
            OperationQueue.main.addOperation { [weak self] in
                self?.reloadStream()
            }
        }
    }

    /// the curves of the stream's newest records
    private func reloadStream() {
        guard let stream else { return }
        if segments.isEmpty {
            valueCount = stream.columns
        }
        curves = stream.newestRecords(maximumCurves).map { curves(of: spectrum(of: $0, in: stream)) }
    }

    /// the record's values scaled to the maximum value
    private func spectrum(of record: Data, in stream: ILStreamData) -> [Double] {
        stream.percents(of: record).map { Double($0) * maximumValue }
    }

    /// the curves of each spectrum, oldest first, one for each segment, from `curves(of:)`
    public var curves: [[[Double]]] = [] {
        didSet {
            if !isAppending { cacheIsValid = false }
            redisplay()
        }
    }

    /// the runs of contiguous values, by index in the spectrum, an empty list is one segment of `valueCount` values
    public var segments: [Range<Int>] = [] {
        didSet { invalidate() }
    }

    /// the number of values in each spectrum, used when there are no segments
    public var valueCount = 0 {
        didSet { invalidate() }
    }

    /// labels across the top
    public var spans: [ILSparkPulsarSpan] = [] {
        didSet { redisplay() }
    }

    /// labels along the bottom
    public var marks: [ILSparkPulsarMark] = [] {
        didSet { redisplay() }
    }

    /// the value at the top of the scale
    public var maximumValue: Double = 100 {
        didSet { invalidate() }
    }

    /// the most curves drawn, the newest ones
    public var maximumCurves = 48 {
        didSet { invalidate() }
    }

    /// the points in each curve for each value
    public var pointsPerValue = 8

    /// the empty values added to each end of a segment, so its curve falls to the baseline at the edges
    public var paddingValues = 2

    /// the space between segments
    public var gapWidth: CGFloat = 16

    /// the flat line at each side of the values, as a fraction of the width
    public var edgeFraction: CGFloat = 0.06

    /// the space between the ends of the lines and the sides of the view, the plot is full width on iOS
    #if os(macOS)
    public var sideMargin: CGFloat = 16
    #else
    public var sideMargin: CGFloat = 0
    #endif

    /// how high a curve at the top of the scale rises, in rows
    public var amplitudeRows: CGFloat = 6

    /// shown when there are no curves
    public var message = Bundle(for: ILSparkPulsar.self).localizedString(forKey: "Waiting for Samples", value: nil, table: nil)

    /// the shortest time between redraws, spectra appended between them are drawn together
    public var redrawInterval: TimeInterval = 1.0 / 15

    private var redrawScheduled = false
    private var lastDrawn = Date.distantPast

    private func redisplay() {
        guard !redrawScheduled else { return }
        let wait = redrawInterval - Date().timeIntervalSince(lastDrawn)
        guard wait > 0 else {
            updateView()
            return
        }
        redrawScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            self?.redrawScheduled = false
            self?.updateView()
        }
    }

    /// redraw all of the curves
    private func invalidate() {
        cacheIsValid = false
        redisplay()
    }

    private var activeSegments: [Range<Int>] {
        segments.isEmpty ? (valueCount > 0 ? [0..<valueCount] : []) : segments
    }

    /// @returns the curves of a spectrum, a smooth curve for each segment, padded with empty values at each end
    public func curves(of spectrum: [Double]) -> [[Double]] {
        let padding = [Double](repeating: 0, count: paddingValues)
        let segments = segments.isEmpty ? [0..<spectrum.count] : segments
        return segments.map { segment in
            let values = segment.compactMap { $0 < spectrum.count ? spectrum[$0] : nil }
            return ILSparkCurve.curve(padding + values + padding, factor: pointsPerValue)
        }
    }

    /// add the curves of a spectrum as the newest, dropping the oldest beyond the most drawn
    public func append(_ spectrum: [Double]) {
        var updated = curves
        updated.append(curves(of: spectrum))
        if updated.count > maximumCurves {
            updated.removeFirst(updated.count - maximumCurves)
        }
        isAppending = true
        curves = updated
        isAppending = false
        appendedCurves += 1
    }

    // MARK: - Colors

    private var plotColor: ILColor { style.background ?? .black }
    private var lineColor: ILColor { style.stroke ?? .white }
    private var newestColor: ILColor { style.fill ?? lineColor }
    private var lineWidth: CGFloat { style.width > 0 ? style.width : ILPathlineWidth }

    // MARK: - Row Cache

    /// the older curves are drawn into the cache, when a curve is appended the cache is moved up a row and the curve
    /// which was the newest is drawn into it, so each redraw draws the cache and the newest curve, not every curve
    private var rowCache: CGContext?
    private var cacheIsValid = false
    private var cacheSize = CGSize.zero
    private var cacheScale: CGFloat = 0
    private var isAppending = false
    private var appendedCurves = 0 // since the cache was drawn

    /// the cache, the newest curve and the labels are drawn into the frame, which is the plot layer's contents
    private var frameContext: CGContext?
    private var frameSize = CGSize.zero
    private var frameScale: CGFloat = 0

    /// the color space of the window, so the cache is drawn without converting its colors
    private var displayColorSpace: CGColorSpace {
        #if os(macOS)
        return window?.colorSpace?.cgColorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        #else
        return CGColorSpace(name: traitCollection.displayGamut == .P3 ? CGColorSpace.displayP3 : CGColorSpace.sRGB)!
        #endif
    }

    private var backingScale: CGFloat {
        #if os(macOS)
        return window?.backingScaleFactor ?? ILMainScreenScale
        #else
        return traitCollection.displayScale > 0 ? traitCollection.displayScale : ILMainScreenScale
        #endif
    }

    /// @returns a bitmap context the size of the view, in its coordinates, with the origin at the top left
    private func makeContext(size: CGSize, scale: CGFloat, space: CGColorSpace) -> CGContext? {
        let width = Int((size.width * scale).rounded(.up)), height = Int((size.height * scale).rounded(.up))
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        context.interpolationQuality = .none
        return context
    }

    /// draw an image filling the rect, in a context with the origin at the top left
    private func drawFlipped(_ image: CGImage, in context: CGContext, rect: CGRect) {
        context.saveGState()
        context.translateBy(x: 0, y: rect.maxY + rect.minY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: rect)
        context.restoreGState()
    }

    /// make the context current for drawing text, with the origin at the top left
    private func drawing(in context: CGContext, _ draw: () -> Void) {
        #if os(macOS)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        draw()
        NSGraphicsContext.restoreGraphicsState()
        #else
        UIGraphicsPushContext(context)
        draw()
        UIGraphicsPopContext()
        #endif
    }

    // MARK: - Layout

    /// the slots in a segment, the spaces between its values and its padding
    private func slots(_ segment: Range<Int>) -> CGFloat {
        CGFloat(segment.count - 1 + 2 * paddingValues)
    }

    /// the width of a slot, so the segments and the gaps between them fill the plot
    private func slotWidth(in plotArea: CGRect) -> CGFloat {
        let segments = activeSegments
        let totalSlots = segments.reduce(0) { $0 + slots($1) }
        let gaps = gapWidth * CGFloat(max(segments.count - 1, 0))
        return totalSlots > 0 ? max(plotArea.width - gaps, 0) / totalSlots : 0
    }

    /// @returns the horizontal extent of the segment, including its padding
    private func extent(ofSegment index: Int, in plotArea: CGRect) -> (minX: CGFloat, maxX: CGFloat) {
        let segments = activeSegments
        let slot = slotWidth(in: plotArea)
        var minX = plotArea.minX
        for segment in segments.prefix(index) {
            minX += slots(segment) * slot + gapWidth
        }
        return (minX, minX + slots(segments[index]) * slot)
    }

    /// @returns the x position of a value index, which can be between values
    private func x(ofValue position: Double, in plotArea: CGRect) -> CGFloat? {
        let segments = activeSegments
        guard let segmentIndex = segments.firstIndex(where: { position >= Double($0.lowerBound) && position <= Double($0.upperBound - 1) }) else {
            return nil
        }
        let segment = segments[segmentIndex]
        return extent(ofSegment: segmentIndex, in: plotArea).minX
             + CGFloat(position - Double(segment.lowerBound) + Double(paddingValues)) * slotWidth(in: plotArea)
    }

    private static let labelFontSize: CGFloat = 11
    private let labelHeight: CGFloat = 16
    /// the space above the plot, 1em, the space below it is half that
    private var inset: CGFloat {
        #if os(macOS)
        NSFont.systemFontSize
        #else
        UIFont.preferredFont(forTextStyle: .body).pointSize
        #endif
    }

    #if !os(macOS)
    /// redrawn inside its new safe area
    open override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        invalidate()
    }
    #endif

    /// the area inside the safe area, so the labels clear the status and tab bars
    private var plotBounds: CGRect {
        #if os(macOS)
        return bounds
        #else
        var insets = safeAreaInsets
        #if os(iOS)
        if insets.top > 0 { // just below the status bar, rather than the safe area's margin under it
            let statusBar = window?.windowScene?.statusBarManager?.statusBarFrame.maxY ?? insets.top
            let viewTop = convert(CGPoint.zero, to: nil).y
            insets.top = max(min(statusBar - viewTop, insets.top), 0) // the plot 1em below it
        }
        #endif
        return bounds.inset(by: insets)
        #endif
    }

    // MARK: - ILSparkView

    /// a new style redraws all of the curves in its colors
    open override var style: ILSparkStyle {
        didSet { invalidate() }
    }

    open override func initView() {
        super.initView()
        style = ILSparkPulsar.defaultPulsarStyle
        plotLayer.contentsGravity = .resize
        plotLayer.magnificationFilter = .nearest
        addContent(plotLayer)
    }

    open override func updateView() {
        super.updateView()
        CATransaction.begin()
        CATransaction.setDisableActions(true) // a new frame each update, fading between them flickers
        plotLayer.frame = bounds
        plotLayer.contentsScale = backingScale
        plotLayer.contents = drawFrame()
        CATransaction.commit()
    }

    #if os(macOS)
    open override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateView()
    }
    #else
    open override func didMoveToWindow() {
        super.didMoveToWindow()
        updateView()
    }
    #endif

    // MARK: - Drawing

    /// @returns an image of the plot: the older curves from the cache, the newest curve over them and the labels
    private func drawFrame() -> CGImage? {
        lastDrawn = Date()
        let size = bounds.size, scale = backingScale, space = displayColorSpace
        if frameContext == nil || size != frameSize || scale != frameScale || space != frameContext?.colorSpace {
            frameContext = makeContext(size: size, scale: scale, space: space)
            frameSize = size
            frameScale = scale
        }
        guard let context = frameContext else { return nil }

        let shown = Array(curves.suffix(maximumCurves))
        let area = plotBounds // 1em above the plot, half that below it
        let plot = CGRect(x: area.minX + sideMargin, y: area.minY + inset,
                          width: area.width - 2 * sideMargin, height: area.height - inset * 1.5)
        let lineArea = CGRect(x: plot.minX, y: plot.minY + labelHeight, width: plot.width, height: plot.height - 2 * labelHeight)
        let edge = lineArea.width * edgeFraction // the lines run flat to the margins, the values are in the middle
        let plotArea = lineArea.insetBy(dx: edge, dy: 0)
        let segments = activeSegments

        guard !shown.isEmpty, !segments.isEmpty, plotArea.width > 0, plotArea.height > 0 else {
            rowCache = nil
            context.setFillColor(plotColor.cgColor)
            context.fill(CGRect(origin: .zero, size: size))
            drawing(in: context) {
                drawMessage(message, color: lineColor.withAlphaComponent(0.5))
            }
            return context.makeImage()
        }

        // the newest spectrum is at the bottom, older ones step up the view a row at a time
        let rowStep = max((lineArea.height / (CGFloat(maximumCurves - 1) + amplitudeRows) * scale).rounded(.down), 1) / scale
        let amplitude = amplitudeRows * rowStep
        let extents = segments.indices.map { extent(ofSegment: $0, in: plotArea) }

        let geometry = RowGeometry(lineArea: lineArea, extents: extents, amplitude: amplitude,
                                   scale: amplitude / CGFloat(maximumValue))
        updateCache(shown, rowStep: rowStep, geometry: geometry)
        if let image = rowCache?.makeImage() { // opaque, it covers the view
            drawFlipped(image, in: context, rect: CGRect(origin: .zero, size: cacheSize))
        }
        else {
            context.setFillColor(plotColor.cgColor)
            context.fill(CGRect(origin: .zero, size: size))
        }
        if let newest = shown.last {
            drawRow(newest, baseline: lineArea.maxY, color: newestColor, width: lineWidth * 1.5, geometry: geometry, in: context)
        }

        drawing(in: context) {
            drawSpans(in: CGRect(x: plot.minX, y: plot.minY, width: plot.width, height: labelHeight), plotArea: plotArea,
                      color: lineColor.withAlphaComponent(0.8), context: context)
            drawMarks(in: CGRect(x: plot.minX, y: lineArea.maxY, width: plot.width, height: labelHeight), plotArea: plotArea,
                      color: lineColor.withAlphaComponent(0.6))
        }
        return context.makeImage()
    }

    private struct RowGeometry {
        let lineArea: CGRect
        let extents: [(minX: CGFloat, maxX: CGFloat)]
        let amplitude: CGFloat
        let scale: CGFloat // points for each value
    }

    /// bring the cache up to date with the curves older than the newest, moving it up for the curves appended since
    /// it was drawn, or drawing it again
    private func updateCache(_ shown: [[[Double]]], rowStep: CGFloat, geometry: RowGeometry) {
        let size = bounds.size, scale = backingScale, space = displayColorSpace
        let appended = appendedCurves
        appendedCurves = 0

        if rowCache == nil || !cacheIsValid || size != cacheSize || scale != cacheScale || space != rowCache?.colorSpace
            || appended >= shown.count - 1 {
            rowCache = makeContext(size: size, scale: scale, space: space)
            cacheSize = size
            cacheScale = scale
            cacheIsValid = true
            guard let rowCache else { return }
            rowCache.setFillColor(plotColor.cgColor)
            rowCache.fill(CGRect(origin: .zero, size: size))
            for age in stride(from: shown.count - 1, through: 1, by: -1) { // oldest first, newer lines hide the ones behind them
                drawRow(shown[shown.count - 1 - age], baseline: geometry.lineArea.maxY - CGFloat(age) * rowStep,
                        color: lineColor, width: lineWidth, geometry: geometry, in: rowCache)
            }
            return
        }

        guard appended > 0, let rowCache, let image = rowCache.makeImage() else { return }

        // move the older curves up a row for each curve appended, then draw the curves which were newest in front of them
        rowCache.setFillColor(plotColor.cgColor)
        rowCache.fill(CGRect(origin: .zero, size: size))
        drawFlipped(image, in: rowCache, rect: CGRect(x: 0, y: -CGFloat(appended) * rowStep, width: size.width, height: size.height))
        for age in stride(from: appended, through: 1, by: -1) {
            drawRow(shown[shown.count - 1 - age], baseline: geometry.lineArea.maxY - CGFloat(age) * rowStep,
                    color: lineColor, width: lineWidth, geometry: geometry, in: rowCache)
        }

        // the curves which were dropped are above the oldest curve's baseline, clear the band above it and draw the curves
        // which reach into it again, oldest first, the curves below the band can't reach it
        if shown.count == maximumCurves {
            let oldestBaseline = geometry.lineArea.maxY - CGFloat(shown.count - 1) * rowStep
            let band = CGRect(x: 0, y: 0, width: size.width, height: oldestBaseline + 2) // and the oldest line's width
            let reaching = Int((geometry.amplitude + 4) / rowStep) + 1 // rows below the oldest which can rise into the band
            rowCache.saveGState()
            rowCache.clip(to: band)
            rowCache.setFillColor(plotColor.cgColor)
            rowCache.fill(band)
            for age in stride(from: shown.count - 1, through: max(shown.count - 1 - reaching, 1), by: -1) {
                drawRow(shown[shown.count - 1 - age], baseline: geometry.lineArea.maxY - CGFloat(age) * rowStep,
                        color: lineColor, width: lineWidth, geometry: geometry, in: rowCache)
            }
            rowCache.restoreGState()
        }
    }

    /// @returns the line through the curve of each segment of a row, with its ends
    private func rowPaths(_ rowCurves: [[Double]], baseline: CGFloat, geometry: RowGeometry) -> [(line: CGMutablePath, startX: CGFloat, endX: CGFloat)] {
        let lineArea = geometry.lineArea
        let lastSegment = min(rowCurves.count, geometry.extents.count) - 1
        var paths: [(line: CGMutablePath, startX: CGFloat, endX: CGFloat)] = []
        var points: [CGPoint] = []
        for segmentIndex in 0..<max(lastSegment + 1, 0) where rowCurves[segmentIndex].count > 1 {
            let (minX, maxX) = geometry.extents[segmentIndex]
            let startX = (segmentIndex == 0 ? lineArea.minX : minX) // the outer segments run flat to the edges
            let endX = (segmentIndex == lastSegment ? lineArea.maxX : maxX)

            rowCurves[segmentIndex].withUnsafeBufferPointer { curve in
                let xStep = (maxX - minX) / CGFloat(curve.count - 1)
                points.removeAll(keepingCapacity: true)
                points.append(CGPoint(x: startX, y: baseline))
                var index = 0
                while index < curve.count { // not a range, which is slow to iterate in debug builds
                    let raw = CGFloat(curve[index]) * geometry.scale
                    let rise = raw.isFinite ? min(raw, geometry.amplitude) : 0 // a NaN or infinite level would put a point off the path, which Metal's validation aborts on
                    points.append(CGPoint(x: minX + CGFloat(index) * xStep, y: baseline - rise))
                    index += 1
                }
                points.append(CGPoint(x: endX, y: baseline))
            }
            let line = CGMutablePath()
            line.addLines(between: points)
            paths.append((line, startX, endX))
        }
        return paths
    }

    /// draw a line through the curve of each segment of the row, filled below to hide the lines behind it
    private func drawRow(_ rowCurves: [[Double]], baseline: CGFloat, color: ILColor, width: CGFloat, geometry: RowGeometry,
                         in context: CGContext) {
        for path in rowPaths(rowCurves, baseline: baseline, geometry: geometry) {
            fillBelow(path, geometry: geometry, in: context)
            context.addPath(path.line)
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(width)
            context.setLineJoin(.round)
            context.strokePath()
        }
    }

    /// fill below the line to hide the lines behind it
    private func fillBelow(_ path: (line: CGMutablePath, startX: CGFloat, endX: CGFloat), geometry: RowGeometry, in context: CGContext) {
        let fill = path.line.mutableCopy()!
        fill.addLine(to: CGPoint(x: path.endX, y: geometry.lineArea.maxY))
        fill.addLine(to: CGPoint(x: path.startX, y: geometry.lineArea.maxY))
        fill.closeSubpath()
        context.addPath(fill)
        context.setFillColor(plotColor.cgColor)
        context.setShouldAntialias(false) // the fill only hides the lines behind, its edge is under the line
        context.fillPath()
        context.setShouldAntialias(true)
    }

    /// title each span across the top, centered over its segments, with a rule under the title spanning them
    private func drawSpans(in rect: CGRect, plotArea: CGRect, color: ILColor, context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: ILFont.systemFont(ofSize: ILSparkPulsar.labelFontSize, weight: .medium),
            .foregroundColor: color
        ]
        let segments = activeSegments
        for span in spans where !span.title.isEmpty {
            guard let firstSegment = segments.firstIndex(where: { $0.contains(span.values.lowerBound) }),
                  let lastSegment = segments.firstIndex(where: { $0.contains(span.values.upperBound) }) else { continue }
            let minX = extent(ofSegment: firstSegment, in: plotArea).minX
            let maxX = extent(ofSegment: lastSegment, in: plotArea).maxX
            let label = NSAttributedString(string: span.title, attributes: attributes)
            let size = label.size()
            if size.width < maxX - minX {
                label.draw(at: CGPoint(x: (minX + maxX - size.width) / 2, y: rect.minY))
            }
            context.setStrokeColor(color.withAlphaComponent(0.3).cgColor)
            context.setLineWidth(1)
            context.move(to: CGPoint(x: minX + 2, y: rect.maxY - 1.5))
            context.addLine(to: CGPoint(x: maxX - 2, y: rect.maxY - 1.5))
            context.strokePath()
        }
    }

    /// label the marks along the bottom, skipping labels which would overlap
    private func drawMarks(in rect: CGRect, plotArea: CGRect, color: ILColor) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: ILFont.monospacedDigitSystemFont(ofSize: ILSparkPulsar.labelFontSize, weight: .regular),
            .foregroundColor: color
        ]
        var lastMaxX = -CGFloat.greatestFiniteMagnitude
        for mark in marks {
            guard let center = x(ofValue: mark.position, in: plotArea) else { continue }
            let label = NSAttributedString(string: mark.title, attributes: attributes)
            let size = label.size()
            let x = center - size.width / 2
            guard x > lastMaxX + 6 else { continue }
            label.draw(at: CGPoint(x: x, y: rect.minY + (rect.height - size.height) / 2))
            lastMaxX = x + size.width
        }
    }

    private func drawMessage(_ message: String, color: ILColor) {
        #if os(tvOS)
        let fontSize = ILFont.preferredFont(forTextStyle: .body).pointSize // tvOS has no system font size
        #else
        let fontSize = ILFont.systemFontSize
        #endif
        let attributes: [NSAttributedString.Key: Any] = [.font: ILFont.systemFont(ofSize: fontSize), .foregroundColor: color]
        let label = NSAttributedString(string: message, attributes: attributes)
        let size = label.size()
        label.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2))
    }

    // MARK: - ILStreamDataDelegate

    /// records come in on the stream's thread, each is appended on the main queue, the redraws are throttled
    open func stream(_ stream: ILStreamData, didAppendRecord record: Data) {
        OperationQueue.main.addOperation { [weak self] in
            guard let self, stream === self.stream else { return }
            append(spectrum(of: record, in: stream))
        }
    }
}

/* Copyright © 2016-2026, Alf Watt (alf@istumbler.net) Avaliale under MIT Style license in README.md */
