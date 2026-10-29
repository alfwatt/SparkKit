import Foundation
import QuartzCore
import KitBridge
#if SWIFT_PACKAGE
import KitBridgeSwift
#endif

// MARK: Hints

/// style hint, how a stream view draws its stream, an ILSparkStreamStyle, a grid by default
public let ILSparkStreamStyleHint = "ILSparkStreamStyleHint"

/// how a stream view draws its stream
@objc public enum ILSparkStreamStyle: Int {
    case gridStyle // the records as rows of a grid, the newest at the fill direction's edge, like ILSparkGrid
    case barsStyle // the newest record as bars, growing from the fill direction's edge, like ILSparkBars
    case lineStyle // the newest record as a line, rising from the fill direction's edge, filled if the style is
}

/// ILSparkStyle hints for stream views
extension ILSparkStyle {
    @objc public var streamStyle: ILSparkStreamStyle {
        numberHint(ILSparkStreamStyleHint).flatMap { ILSparkStreamStyle(rawValue: $0.intValue) } ?? .gridStyle
    }
}

// MARK: -

/// shows an ILStreamData as a grid of its records, or its newest record as bars or a line, as the style's stream style says,
/// updating as each record arrives
@objc(ILSparkStream)
open class ILSparkStream: ILSparkView, ILStreamDataDelegate {
    private let gridLayer = ILSparkGridLayer()
    private let barsLayer = CALayer()
    private var lineLayer: CALayer?

    @objc open var stream: ILStreamData? {
        didSet {
            oldValue?.removeObserver(self)
            stream?.addObserver(self)
            OperationQueue.main.addOperation { [weak self] in
                self?.updateView()
            }
        }
    }

    /// the space between the bars, in points
    @objc open var barGap: CGFloat = 0

    /// a line through the values, between 0 and 1, rising from the edge the style names, the bottom by default,
    /// from the left or right the values run up the view
    static func lineLayer(_ values: [CGFloat], size viewSize: CGSize, style: ILSparkStyle) -> CALayer {
        let direction = style.edgeDirection(default: .fromBottom)
        let size = direction.isHorizontal ? CGSize(width: viewSize.height, height: viewSize.width) : viewSize
        let path = CGMutablePath()
        let step = values.count > 1 ? size.width / CGFloat(values.count - 1) : 0
        let points = values.enumerated().map { index, value in
            CGPoint(x: CGFloat(index) * step, y: size.height * (1 - style.scaled(value)))
        }
        if let first = points.first, let last = points.last {
            if style.filled {
                path.move(to: CGPoint(x: first.x, y: size.height)) // from the baseline
                path.addLines(between: [CGPoint(x: first.x, y: size.height)] + points + [CGPoint(x: last.x, y: size.height)])
                path.closeSubpath()
            }
            else {
                path.addLines(between: points)
            }
        }

        // drawn rising from the bottom, then turned to rise from the edge the style names
        var turn: CGAffineTransform
        switch direction {
        case .fromTop: turn = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: viewSize.height)
        case .fromLeft: turn = CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: viewSize.width, ty: viewSize.height)
        case .fromRight: turn = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: viewSize.height)
        default: turn = .identity
        }

        let lineLayer = CAShapeLayer()
        lineLayer.path = path.copy(using: &turn)
        lineLayer.strokeColor = style.stroke?.cgColor
        lineLayer.lineWidth = style.width
        lineLayer.lineJoin = .round
        lineLayer.fillColor = style.filled ? style.fill?.cgColor : nil
        return lineLayer
    }

    // MARK: - ILSparkView

    open override func initView() {
        super.initView()
        addContent(gridLayer)
        addContent(barsLayer)
    }

    open override func updateView() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let streamStyle = style.streamStyle
        gridLayer.frame = sparkLayer.bounds
        gridLayer.sparkStyle = style
        gridLayer.isHidden = streamStyle != .gridStyle
        barsLayer.frame = sparkLayer.bounds
        barsLayer.backgroundColor = style.background?.cgColor
        barsLayer.isHidden = streamStyle != .barsStyle
        barsLayer.sublayers = nil

        if let stream, stream.count > 0, let newest = stream.newestRecord {
            errorString = nil
            switch streamStyle {
            case .gridStyle:
                gridLayer.columns = stream.columns
                gridLayer.totalRows = stream.count
                if let speed = style.gridScrollSpeed { // placed by time and moving smoothly, only the records which can be on the grid
                    let along = style.edgeDirection(default: .fromTop).isHorizontal ? bounds.width : bounds.height
                    let oldest = Date().addingTimeInterval(-(TimeInterval(along / speed) + (recordInterval * 4)))
                    gridLayer.drawTimed(stream.newestTimedRecords(stream.count).filter { $0.time >= oldest }
                                            .map { (time: $0.time, percents: stream.percents(of: $0.record)) },
                                        interval: recordInterval)
                }
                else {
                    gridLayer.draw(stream.newestRecords(gridLayer.visibleRows).map(stream.percents))
                }
            case .barsStyle:
                ILSparkBars.addBars(stream.percents(of: newest), to: barsLayer, in: borderInset, viewSize: frame.size, style: style, barGap: barGap)
            case .lineStyle:
                let insetRect = borderInset
                let newLineLayer = ILSparkStream.lineLayer(stream.percents(of: newest), size: insetRect.size, style: style)
                replaceContent(lineLayer, with: newLineLayer)
                newLineLayer.frame = insetRect
                lineLayer = newLineLayer
            }
        }
        else {
            errorString = style.l10Nbundle?.localizedString(forKey: "No Data", value: "No Data", table: nil) ?? "No Data"
            gridLayer.draw([])
        }
        if streamStyle != .lineStyle || errorString != nil {
            lineLayer?.removeFromSuperlayer()
            lineLayer = nil
        }
        CATransaction.commit()
        updateScrollTimer()
        super.updateView()
    }

    // MARK: - Scrolling

    private var scrollTimer: Timer?
    private var lastRecordTime: Date?

    /// the average time between records, without the gaps, measured from the first two records
    private var measuredInterval: TimeInterval?

    /// the average time between records, a tenth of a second until it's measured
    var recordInterval: TimeInterval { measuredInterval ?? 0.1 }

    private func timeRecord(_ time: Date) {
        defer { lastRecordTime = time }
        guard let lastRecordTime else { return }
        let interval = time.timeIntervalSince(lastRecordTime)
        // a pause of more than a few records is a gap in the stream, before there's an average, more than a few seconds
        let gap = measuredInterval.map { max($0 * 4, 1) } ?? 2.5
        guard interval > 0, interval < gap else { return }
        measuredInterval = measuredInterval.map { ($0 * 0.9) + (interval * 0.1) } ?? interval
    }

    /// move a timed grid every frame while it's in a window, stop otherwise
    private func updateScrollTimer() {
        let scrolls = window != nil && style.streamStyle == .gridStyle && style.gridScrollSpeed != nil && (stream?.count ?? 0) > 0
        if scrolls, scrollTimer == nil {
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                self?.gridLayer.tick()
            }
            RunLoop.main.add(timer, forMode: .common)
            scrollTimer = timer
        }
        else if !scrolls {
            scrollTimer?.invalidate()
            scrollTimer = nil
        }
    }

    #if os(macOS)
    open override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateScrollTimer()
    }
    #else
    open override func didMoveToWindow() {
        super.didMoveToWindow()
        updateScrollTimer()
    }
    #endif

    /// the labels and border, without redrawing the stream
    private func updateLabelsAndBorder() {
        super.updateView()
    }

    // MARK: - ILStreamDataDelegate

    /// records come in on the stream's thread, collect them and draw them together on the main queue,
    /// so a burst of records is drawn once
    open func stream(_ stream: ILStreamData, didAppendRecord record: Data) {
        pendingLock.lock()
        pendingRecords.append((time: Date(), record: record))
        let scheduled = drawScheduled
        drawScheduled = true
        pendingLock.unlock()
        guard !scheduled else { return }

        OperationQueue.main.addOperation { [weak self] in
            guard let self else { return }
            pendingLock.lock()
            let records = pendingRecords
            pendingRecords = []
            drawScheduled = false
            pendingLock.unlock()
            guard stream === self.stream, !records.isEmpty else { return }
            records.forEach { self.timeRecord($0.time) }

            if style.streamStyle == .gridStyle, style.gridScrollSpeed != nil, !gridLayer.isTimedEmpty { // add the timed rows
                gridLayer.appendTimed(records.map { (time: $0.time, percents: stream.percents(of: $0.record)) }, interval: recordInterval)
                updateLabelsAndBorder()
            }
            else if style.streamStyle == .gridStyle, style.gridScrollSpeed == nil, !gridLayer.isEmpty { // add the rows to the grid
                gridLayer.totalRows = stream.count
                gridLayer.append(records.suffix(gridLayer.visibleRows).map { stream.percents(of: $0.record) })
                updateLabelsAndBorder()
            }
            else {
                updateView()
            }
        }
    }

    private let pendingLock = NSLock()
    private var pendingRecords: [(time: Date, record: Data)] = [] // records waiting to be drawn, and when they arrived
    private var drawScheduled = false
}

/* Copyright © 2016-2026, Alf Watt (alf@istumbler.net) Avaliale under MIT Style license in README.md */
