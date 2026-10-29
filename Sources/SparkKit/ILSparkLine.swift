/* Copyright © 2016-2026, Alf Watt (alf@istumbler.net) Avaliale under MIT Style license in README.md */
import Foundation
import QuartzCore
import KitBridge
#if SWIFT_PACKAGE
import KitBridgeSwift
#endif
#if os(macOS)
import AppKit
#endif

/// style hint, the seconds for each point of the line
public let ILSparkLineScaleFactor = "ILSparkLineScaleFactor"
/// style hint, the seconds between samples which leave a gap in the line
public let ILSparkLineFalloffInterval = "ILSparkLineFalloffTInterval"

// MARK: -

/// Data Source Protocol for ILSparkLine
@objc public protocol ILSparkLineDataSource: NSObjectProtocol {

    /// dates for which sample values are avaliable
    var sampleDates: [Date] { get }

    /// scaled sample value between 0.0 and 1.0 at the index in sampleDates
    @objc(sampleValueAtIndex:)
    func sampleValue(at index: Int) -> CGFloat

    /// the sample dates in the period, if the data source can find them faster than filtering sampleDates
    @objc optional func sampleDates(in period: DateInterval) -> [Date]
}

// MARK: -

extension ILSparkStyle {
    /// seconds for each point
    var scale: CGFloat {
        numberHint(ILSparkLineScaleFactor).map { CGFloat($0.doubleValue) } ?? 1.0
    }

    /// seconds between samples which leave a gap
    var falloff: TimeInterval {
        numberHint(ILSparkLineFalloffInterval)?.doubleValue ?? 0.0
    }
}

// MARK: -

/// ILSparkLine provides a time-series view for iOS and macOS
@objc(ILSparkLine)
open class ILSparkLine: ILSparkView {

    @objc open var dataSource: ILSparkLineDataSource?

    static func timeSeries(with data: ILSparkLineDataSource?, size: CGSize, style: ILSparkStyle) -> CALayer {
        let seriesLayer = CALayer()
        let startDate = Date()
        let path = CGMutablePath()
        let gaps = CGMutablePath()
        let visibleInterval = TimeInterval(size.width * style.scale)
        let falloff = style.falloff
        var lastDate: Date?
        var firstPoint = CGPoint.zero
        var lastPoint = CGPoint.zero
        var wasGap = false // true if the last segment was a gap

        let visiblePeriod = DateInterval(start: startDate.addingTimeInterval(-visibleInterval), duration: visibleInterval)
        let sampleDates = data?.sampleDates?(in: visiblePeriod) ?? data?.sampleDates ?? []

        for (sampleIndex, sampleDate) in sampleDates.enumerated() {
            let sampleInterval = abs(sampleDate.timeIntervalSince(startDate))
            let samplePercent = data?.sampleValue(at: sampleIndex) ?? 0
            let sampleX = size.width - CGFloat(sampleInterval) / style.scale
            let sampleY = size.height * samplePercent
            let thisPoint = CGPoint(x: min(sampleX, size.width), y: min(sampleY, size.height))

            if lastDate == nil {
                firstPoint = thisPoint
                if style.filled {
                    path.move(to: CGPoint(x: firstPoint.x, y: size.height)) // start at the baseline
                    path.addLine(to: thisPoint)
                }
                else {
                    path.move(to: thisPoint)
                }
            }

            if let lastDate, falloff > 0, abs(sampleDate.timeIntervalSince(lastDate)) > falloff { // samples further apart than the falloff leave a gap
                if style.filled {
                    path.addLine(to: CGPoint(x: lastPoint.x, y: size.height)) // drop it to the baseline
                    path.move(to: CGPoint(x: thisPoint.x, y: size.height)) // move along to the current point
                }
                else {
                    path.move(to: thisPoint)
                }
                // draw the gap segment
                gaps.move(to: lastPoint)
                gaps.addLine(to: thisPoint)
                wasGap = true
            }
            else {
                if wasGap && style.filled {
                    path.addLine(to: lastPoint)
                }
                path.addLine(to: thisPoint)
                wasGap = false
            }

            lastPoint = thisPoint
            lastDate = sampleDate

            // have we reached the edge of the view?
            if abs(sampleDate.timeIntervalSince(startDate)) > visibleInterval {
                if style.filled {
                    path.addLine(to: CGPoint(x: thisPoint.x, y: size.height)) // drop it to the baseline
                }
                break
            }
        }

        if style.filled { // bring the line back to the baseline
            path.addLine(to: CGPoint(x: lastPoint.x, y: size.height))
            path.addLine(to: CGPoint(x: firstPoint.x, y: size.height))
        }

        let pathLayer = CAShapeLayer()
        pathLayer.path = path
        pathLayer.strokeColor = style.stroke?.cgColor
        pathLayer.lineWidth = style.width
        pathLayer.fillColor = (style.filled ? style.fill : style.background)?.cgColor
        seriesLayer.addSublayer(pathLayer)

        if falloff > 0 {
            let gapsLayer = CAShapeLayer()
            gapsLayer.path = gaps
            gapsLayer.strokeColor = ILColor.gray.cgColor
            gapsLayer.lineWidth = style.width
            gapsLayer.lineDashPattern = [3, 2]
            gapsLayer.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
            seriesLayer.addSublayer(gapsLayer)
        }

        return seriesLayer
    }

    // MARK: - ILSparkView

    open override func updateView() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0) // TODO use the time between updates

        for layer in sparkLayer.sublayers ?? [] { // remove all sublayers
            layer.removeFromSuperlayer()
        }

        super.updateView()

        let insetRect = borderInset
        let sparkLine = ILSparkLine.timeSeries(with: dataSource, size: insetRect.size, style: style)
        sparkLayer.addSublayer(sparkLine)
        sparkLine.frame = insetRect
        CATransaction.commit()
    }
}

#if os(macOS)

// MARK: -

/// draws its represented object, an ILSparkLineDataSource, as a spark line
@objc(ILSparkLineCell)
open class ILSparkLineCell: NSCell {

    /// style information
    @objc open var style = ILSparkStyle.defaultStyle

    // MARK: - NSCell

    open override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        guard let data = representedObject as? ILSparkLineDataSource else { return }
        let sparkLine = ILSparkLine.timeSeries(with: data, size: cellFrame.size, style: style)
        controlView.layer?.addSublayer(sparkLine)
        sparkLine.frame = cellFrame
    }
}

#endif
