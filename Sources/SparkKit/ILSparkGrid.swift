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

// MARK: Hints

/// style hint, the size of each row in points, 0 stretches the rows to fill the view, square cells by default
public let ILSparkGridRowSizeHint = "ILSparkGridRowSizeHint"

/// style hint, the ILColor of the grid where there's no data, a neutral gray by default
public let ILSparkGridEmptyColorHint = "ILSparkGridEmptyColorHint"

/// style hint, for a stream's grid, the points a second the rows move, each row is placed by when its record arrived and
/// the grid moves smoothly, gaps in the stream show as empty grid, without it the rows step along as records arrive
public let ILSparkGridScrollSpeedHint = "ILSparkGridScrollSpeedHint"

/// ILSparkStyle hints for spark grids
extension ILSparkStyle {
    /// the points a second a stream's grid moves, nil if its rows step along
    public var gridScrollSpeed: CGFloat? {
        numberHint(ILSparkGridScrollSpeedHint).map { CGFloat($0.doubleValue) }.flatMap { $0 > 0 ? $0 : nil }
    }

    /// the size of each row, nil for square cells, 0 to stretch the rows to fill the view
    public var gridRowSize: CGFloat? {
        numberHint(ILSparkGridRowSizeHint).map { CGFloat($0.doubleValue) }
    }

    @objc public var gridEmptyColor: ILColor {
        hints[ILSparkGridEmptyColorHint] as? ILColor ?? ILColor(white: 0.5, alpha: 0.15)
    }
}

// MARK: -

/// rows of cells, each blends from the style's background to its fill by its value, a value between 0 and 1,
/// the newest row is at the edge the style's fill direction names, the top by default, from the left or right the rows are columns
/// with the first value at the bottom, the cells are square unless the style sizes the rows, the empty grid is the style's empty color
final class ILSparkGridLayer: CALayer {
    private var rowLayers: [CALayer] = [] // the rows shown, oldest first

    var sparkStyle = ILSparkStyle.defaultStyle

    /// the number of values in each row
    var columns = 0

    /// all the rows there are, which stretched rows share the grid between
    var totalRows = 0

    override init() {
        super.init()
        masksToBounds = true
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    // MARK: - Geometry

    private var direction: ILSparkFillDirection { sparkStyle.edgeDirection(default: .fromTop) }

    /// the length of the rows, across the grid
    private var acrossLength: CGFloat { direction.isHorizontal ? bounds.height : bounds.width }

    /// the length the rows are stacked along
    private var alongLength: CGFloat { direction.isHorizontal ? bounds.width : bounds.height }

    /// the size of each row along the grid
    private var rowSize: CGFloat {
        guard let size = sparkStyle.gridRowSize else {
            return columns > 0 ? max(acrossLength / CGFloat(columns), 1) : alongLength
        }
        return size > 0 ? size : alongLength / CGFloat(max(totalRows, 1))
    }

    /// the number of rows that fit
    var visibleRows: Int {
        guard rowSize > 0 else { return 0 }
        return Int((alongLength / rowSize).rounded(.up))
    }

    /// the frame of the row, counted from the newest, its edges on whole points so the rows meet without seams
    private func rect(ofRowFromNewest age: Int) -> CGRect {
        let offset = (rowSize * CGFloat(age)).rounded()
        let size = (rowSize * CGFloat(age + 1)).rounded() - offset
        switch direction {
        case .fromBottom: return CGRect(x: 0, y: bounds.height - offset - size, width: bounds.width, height: size)
        case .fromLeft: return CGRect(x: offset, y: 0, width: size, height: bounds.height)
        case .fromRight: return CGRect(x: bounds.width - offset - size, y: 0, width: size, height: bounds.height)
        default: return CGRect(x: 0, y: offset, width: bounds.width, height: size) // from the top
        }
    }

    // MARK: - Rows

    private struct RGBA {
        var red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat

        init(_ color: ILColor?) {
            let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
            let components = color?.cgColor.converted(to: sRGB, intent: .defaultIntent, options: nil)?.components ?? []
            if components.count >= 4 {
                (red, green, blue, alpha) = (components[0], components[1], components[2], components[3])
            }
            else {
                (red, green, blue, alpha) = (0, 0, 0, 0)
            }
        }
    }

    /// an image of the row's values, from the background to the fill color, along the row
    private func image(of percents: [CGFloat]) -> CGImage? {
        guard !percents.isEmpty else { return nil }
        let low = RGBA(sparkStyle.background), high = RGBA(sparkStyle.fill)
        let vertical = direction.isHorizontal // rows from the side are columns
        var pixels = [UInt8](repeating: 0, count: percents.count * 4)
        for (column, percent) in percents.enumerated() {
            let value = sparkStyle.scaled(percent)
            let alpha = low.alpha + ((high.alpha - low.alpha) * value)
            func premultiplied(_ from: CGFloat, _ to: CGFloat) -> UInt8 {
                UInt8(min(max(((from * low.alpha) + (((to * high.alpha) - (from * low.alpha)) * value)) * 255, 0), 255).rounded())
            }
            let pixel = (vertical ? (percents.count - 1 - column) : column) * 4 // vertical rows have the first value at the bottom
            pixels[pixel] = premultiplied(low.red, high.red)
            pixels[pixel + 1] = premultiplied(low.green, high.green)
            pixels[pixel + 2] = premultiplied(low.blue, high.blue)
            pixels[pixel + 3] = UInt8((alpha * 255).rounded())
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: vertical ? 1 : percents.count, height: vertical ? percents.count : 1, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: (vertical ? 1 : percents.count) * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    private func rowLayer(_ percents: [CGFloat]) -> CALayer {
        let rowLayer = CALayer()
        rowLayer.contents = image(of: percents)
        rowLayer.contentsGravity = .resize
        rowLayer.magnificationFilter = .nearest
        return rowLayer
    }

    /// place the rows from the newest, without animating
    private func layoutRows() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backgroundColor = sparkStyle.gridEmptyColor.cgColor
        for (age, rowLayer) in rowLayers.reversed().enumerated() {
            rowLayer.frame = rect(ofRowFromNewest: age)
        }
        CATransaction.commit()
    }

    /// redraw the grid from the rows, oldest first
    func draw(_ rows: [[CGFloat]]) {
        clearTimed()
        rowLayers.forEach { $0.removeFromSuperlayer() }
        rowLayers = rows.suffix(visibleRows).map(rowLayer)
        rowLayers.forEach { addSublayer($0) }
        layoutRows()
    }

    /// add the newest rows, oldest first, and drop the oldest that no longer fit
    func append(_ rows: [[CGFloat]]) {
        for percents in rows {
            let rowLayer = rowLayer(percents)
            addSublayer(rowLayer)
            rowLayers.append(rowLayer)
        }
        let hidden = rowLayers.count - visibleRows
        if hidden > 0 {
            rowLayers.prefix(hidden).forEach { $0.removeFromSuperlayer() }
            rowLayers.removeFirst(hidden)
        }
        layoutRows()
    }

    var isEmpty: Bool { rowLayers.isEmpty }

    // MARK: - Timed Rows

    private let track = CALayer() // the timed rows, moved along as time passes
    private var timedRows: [(start: Date, end: Date, layer: CALayer)] = [] // oldest first
    private var epoch = Date() // when the track was last laid out, the newest edge is at the epoch's time

    var isTimedEmpty: Bool { timedRows.isEmpty }

    /// the frame of the part of the grid the distance along from the newest edge
    private func rect(along start: CGFloat, _ end: CGFloat) -> CGRect {
        let size = end - start
        switch direction {
        case .fromBottom: return CGRect(x: 0, y: bounds.height - end, width: bounds.width, height: size)
        case .fromLeft: return CGRect(x: start, y: 0, width: size, height: bounds.height)
        case .fromRight: return CGRect(x: bounds.width - end, y: 0, width: size, height: bounds.height)
        default: return CGRect(x: 0, y: start, width: bounds.width, height: size) // from the top
        }
    }

    /// the way the rows move as they age
    private var travel: CGPoint {
        switch direction {
        case .fromBottom: return CGPoint(x: 0, y: -1)
        case .fromLeft: return CGPoint(x: 1, y: 0)
        case .fromRight: return CGPoint(x: -1, y: 0)
        default: return CGPoint(x: 0, y: 1)
        }
    }

    /// the frame of the time span in the track, as it was at the epoch, a point longer on its older side so the rows meet
    private func trackRect(_ start: Date, _ end: Date, speed: CGFloat) -> CGRect {
        rect(along: CGFloat(epoch.timeIntervalSince(end)) * speed, CGFloat(epoch.timeIntervalSince(start)) * speed + 1)
    }

    private func clearTimed() {
        timedRows.forEach { $0.layer.removeFromSuperlayer() }
        timedRows = []
    }

    /// a pause between rows longer than this many intervals is a gap, the newest row lasts this long unless the next comes sooner
    private static let gapIntervals: TimeInterval = 3

    /// redraw the grid from the rows and when they arrived, oldest first, each row lasts until the next,
    /// gaps longer than a few intervals between the rows are left empty
    func drawTimed(_ rows: [(time: Date, percents: [CGFloat])], interval: TimeInterval, now: Date = Date()) {
        guard let speed = sparkStyle.gridScrollSpeed else { return }
        rowLayers.forEach { $0.removeFromSuperlayer() }
        rowLayers = []
        clearTimed()
        epoch = now
        if track.superlayer !== self {
            addSublayer(track)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        track.setAffineTransform(.identity)
        track.frame = bounds
        backgroundColor = sparkStyle.gridEmptyColor.cgColor
        let oldest = now.addingTimeInterval(-TimeInterval(alongLength / speed))
        for (index, row) in rows.enumerated() {
            let latest = row.time.addingTimeInterval(interval * ILSparkGridLayer.gapIntervals)
            let end = index + 1 < rows.count ? min(rows[index + 1].time, latest) : latest
            guard end > oldest else { continue } // off the grid
            addTimedRow(start: row.time, end: end, percents: row.percents, speed: speed)
        }
        CATransaction.commit()
        tick(now)
    }

    private func addTimedRow(start: Date, end: Date, percents: [CGFloat], speed: CGFloat) {
        let rowLayer = rowLayer(percents)
        rowLayer.frame = trackRect(start, end, speed: speed)
        track.addSublayer(rowLayer)
        timedRows.append((start: start, end: end, layer: rowLayer))
    }

    /// add the newest rows, oldest first, the row before each ends when it starts unless there was a gap,
    /// the newest reaches past the edge for a few intervals, so the edge stays filled until the next row or a gap
    func appendTimed(_ rows: [(time: Date, percents: [CGFloat])], interval: TimeInterval) {
        guard let speed = sparkStyle.gridScrollSpeed else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for row in rows {
            if let last = timedRows.last, row.time < last.end { // no gap, the last row lasts until this one
                timedRows[timedRows.count - 1].end = row.time
                last.layer.frame = trackRect(last.start, row.time, speed: speed)
            }
            addTimedRow(start: row.time, end: row.time.addingTimeInterval(interval * ILSparkGridLayer.gapIntervals),
                        percents: row.percents, speed: speed)
        }
        CATransaction.commit()
    }

    /// move the rows along to the time, and drop the ones which have moved off the grid
    func tick(_ now: Date = Date()) {
        guard let speed = sparkStyle.gridScrollSpeed else { return }
        let distance = CGFloat(now.timeIntervalSince(epoch)) * speed
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        track.setAffineTransform(CGAffineTransform(translationX: travel.x * distance, y: travel.y * distance))
        let oldest = now.addingTimeInterval(-TimeInterval(alongLength / speed))
        while let first = timedRows.first, first.end < oldest {
            first.layer.removeFromSuperlayer()
            timedRows.removeFirst()
        }
        CATransaction.commit()
    }
}

// MARK: -

/// shows an ILGridData as a grid of cells, each blends from the style's background to its fill by its value in the value range,
/// the newest row is at the edge the style's fill direction names, the top by default, from the left or right the rows are columns
/// with the first value at the bottom, the cells are square unless the style sizes the rows
@objc(ILSparkGrid)
open class ILSparkGrid: ILSparkView, ILGridDataDelegate {
    private let gridLayer = ILSparkGridLayer()

    @objc open var grid: ILGridData? {
        didSet {
            grid?.delegate = self
            OperationQueue.main.addOperation { [weak self] in
                self?.updateView()
            }
        }
    }

    @objc open var valueRange = NSRange(location: 0, length: 0)

    // MARK: - ILSparkView

    open override func initView() {
        super.initView()
        grid = nil
        style = ILSparkStyle.defaultStyle
        addContent(gridLayer)
    }

    open override func updateView() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gridLayer.frame = sparkLayer.bounds
        gridLayer.sparkStyle = style
        if let grid, grid.rows > 0, grid.columns > 0 {
            errorString = nil
            gridLayer.columns = grid.columns
            gridLayer.totalRows = grid.rows
            let rows = grid.rows
            gridLayer.draw((max(rows - gridLayer.visibleRows, 0)..<rows).map { grid.percents(ofRowData: grid.data(atRow: $0), in: valueRange) })
        }
        else {
            errorString = style.l10Nbundle?.localizedString(forKey: "No Data", value: "No Data", table: nil) ?? "No Data"
            gridLayer.draw([])
        }
        CATransaction.commit()
        super.updateView()
    }

    /// the labels and border, without redrawing the grid
    private func updateLabelsAndBorder() {
        super.updateView()
    }

    // MARK: - ILGridDataDelegate

    open func grid(_ grid: ILGridData, didAppendedData data: Data, asRow rowIndex: Int) {
        let rowSize = grid.sizeOfRow
        let slices = rowSize > 0 ? stride(from: 0, to: data.count, by: rowSize).map { data.subdata(in: $0..<min($0 + rowSize, data.count)) } : []
        OperationQueue.main.addOperation { [weak self] in
            guard let self, grid === self.grid else { return }
            if gridLayer.isEmpty { // the first rows, show the grid
                updateView()
                return
            }
            gridLayer.totalRows = grid.rows
            gridLayer.append(slices.map { grid.percents(ofRowData: $0, in: self.valueRange) })
            updateLabelsAndBorder()
        }
    }
}

/* Copyright © 2016-2026, Alf Watt (alf@istumbler.net) Avaliale under MIT Style license in README.md */
