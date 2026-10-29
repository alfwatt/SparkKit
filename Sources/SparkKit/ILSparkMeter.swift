/* Copyright © 2016-2026, Alf Watt (alf@istumbler.net) Avaliale under MIT Style license in README.md */
import Foundation
import QuartzCore
import CoreText
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

/// Pie and Ring Drawing Hints
public let ILSparkMeterMinAngleHint = "ILSparkMeterMinAngleHint"
public let ILSparkMeterMaxAngleHint = "ILSparkMeterMaxAngleHint"
public let ILSparkMeterFillClockwiseHint = "ILSparkMeterFillClockwiseHint"
public let ILSparkMeterDialWidthHint = "ILSparkMeterDialWidthHint" // defaults to ILSparkMeterDefaultDialWidth
public let ILSparkMeterRingWidthHint = "ILSparkMeterRingWidthHint" // defaults to ILSparkMeterDefaultRingWidth

/// Defaults
public let ILSparkMeterDefaultDialWidth: CGFloat = 4
public let ILSparkMeterDefaultRingWidth: CGFloat = 8

/// Vertical and Horizontal Drawing Direction Hint, an ILSparkMeterFillDirection
public let ILSparkMeterFillDirectionHint = "ILSparkMeterFillDirectionHint"

/// Drawing Style Hint, an ILSparkMeterStyle
public let ILSparkMeterStyleHint = "ILSparkMeterStyleHint"

@objc public enum ILSparkMeterFillDirection: Int {
    case naturalFill // Use system text direction
    case leftToRightFill // Fixed Left to Right or Clockwise
    case rightToLeftFill // Fixed Right to Left or Anti-Clockwise
    case flippedFill // Reverse of System Text Direction
}

/// drawing style of the level indicator
@objc public enum ILSparkMeterStyle: Int {
    case textStyle // a textual description of the value
    case verticalStyle // a vertical indicator, like a thermometer
    case horizontalStyle // a horizontal indicator, like a thermometer, the default style
    case squareStyle // a scaled square centered inside of the border
    case circleStyle // a scaled circle centered inside of the border
    case ringStyle // a circular ring, with zero at the 12 o'clock position
    case pieStyle // a pie chart, with zero at the 12 o'clock position
    case dialStyle // a dial, with zero at the 12 o'clock position
    // TODO logStyle

    /// the circular styles have a circular border
    var isCircular: Bool {
        self == .circleStyle || self == .ringStyle || self == .pieStyle || self == .dialStyle
    }
}

// MARK: -

/// data source protocol for ILSparkMeter
@objc public protocol ILSparkMeterDataSource: NSObjectProtocol {

    /// instantaneous value between 0-1
    var datum: CGFloat { get }
}

// MARK: -

extension ILBezierPath {
    /// the path as a CGPath for a shape layer
    var sparkPath: CGPath {
        #if os(macOS)
        ilcgPath
        #else
        cgPath
        #endif
    }
}

// MARK: -

/// An indicator view which displays a single numeric value
@objc(ILSparkMeter)
open class ILSparkMeter: ILSparkView {
    private var indicatorLayer: CALayer?

    /// the data source for the indicator
    @objc open weak var dataSource: ILSparkMeterDataSource?

    /// a text layer for the meter's text style, with the value in the fill color
    /// the percentage, padded with figure spaces to the width of 100.0%, so with tabular digits the decimal point stays put
    static func percentString(_ fraction: CGFloat) -> String {
        let text = String(format: "%5.1f%%", fraction * 100)
        let padding = text.prefix { $0 == " " }.count
        return String(repeating: "\u{2007}", count: padding) + text.dropFirst(padding)
    }

    /// the height of a line of text in the font
    static func lineHeight(_ font: CTFont) -> CGFloat {
        ceil(CTFontGetAscent(font) + CTFontGetDescent(font))
    }

    /// the style's font with tabular digits, smaller if it needs to be for the lines of percentages to fit in the size
    static func textFont(_ sparkStyle: ILSparkStyle, lines: Int, in size: CGSize) -> CTFont {
        let base: CTFont = sparkStyle.font.map { $0 as CTFont } ?? CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        let tabular = CTFontDescriptorCreateWithAttributes([
            kCTFontFeatureSettingsAttribute as String: [[kCTFontOpenTypeFeatureTag as String: "tnum", kCTFontOpenTypeFeatureValue as String: 1]]
        ] as CFDictionary)
        let font = CTFontCreateCopyWithAttributes(base, CTFontGetSize(base), nil, tabular)
        let widest = CTLineCreateWithAttributedString(NSAttributedString(string: percentString(1),
                                                                         attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
        let width = CGFloat(CTLineGetTypographicBounds(widest, nil, nil, nil))
        let scale = min(1, size.width / max(width, 1), size.height / max(lineHeight(font) * CGFloat(max(lines, 1)), 1))
        return scale < 1 ? CTFontCreateCopyWithAttributes(font, floor(CTFontGetSize(font) * scale), nil, nil) : font
    }

    /// a centered line of text in the frame, in the color
    static func textLayer(_ text: String, frame textRect: CGRect, font: CTFont, color: ILColor?) -> CATextLayer {
        let indicatorText = CATextLayer()
        indicatorText.string = text
        indicatorText.alignmentMode = .center
        indicatorText.font = font
        indicatorText.fontSize = CTFontGetSize(font)
        indicatorText.frame = textRect
        indicatorText.zPosition = 1.0 // frontmost
        indicatorText.foregroundColor = color?.cgColor
        indicatorText.truncationMode = .end
        indicatorText.contentsScale = ILMainScreenScale
        return indicatorText
    }

    /// lines of text centered in the size, in their colors
    static func textLayers(_ lines: [(text: String, color: ILColor?)], size: CGSize, sparkStyle: ILSparkStyle) -> CALayer {
        let container = CALayer()
        container.frame = CGRect(origin: .zero, size: size)
        let font = textFont(sparkStyle, lines: lines.count, in: size)
        let lineHeight = lineHeight(font)
        let top = (size.height - (lineHeight * CGFloat(lines.count))) / 2
        for (index, line) in lines.enumerated() {
            let lineRect = CGRect(x: 0, y: top + (lineHeight * CGFloat(index)), width: size.width, height: lineHeight)
            container.addSublayer(textLayer(line.text, frame: lineRect, font: font, color: line.color))
        }
        return container
    }

    static func sparkMeter(datum: CGFloat, size: CGSize, sparkStyle: ILSparkStyle) -> CALayer {
        let insetRect = CGRect(origin: .zero, size: size)
        let filledPath: ILBezierPath

        switch sparkStyle.meterStyle {
        case .textStyle:
            return textLayers([(percentString(datum), sparkStyle.fill)], size: insetRect.size, sparkStyle: sparkStyle)
        case .verticalStyle:
            let indicatorPosition = insetRect.size.height - (insetRect.size.height * datum)
            filledPath = ILBezierPath(rect: CGRect(x: insetRect.origin.x, y: insetRect.origin.y + indicatorPosition,
                                                   width: insetRect.size.width, height: insetRect.size.height - indicatorPosition))
        case .horizontalStyle:
            filledPath = ILBezierPath(rect: CGRect(x: insetRect.origin.x, y: insetRect.origin.y,
                                                   width: insetRect.size.width * datum, height: insetRect.size.height))
        case .squareStyle:
            let squareRect = ILRectSquareInRect(insetRect)
            let indicatorInset = (squareRect.size.width - (squareRect.size.width * datum)) / 2 // ??? take the square root?
            filledPath = ILBezierPath(rect: squareRect.insetBy(dx: indicatorInset, dy: indicatorInset))
        case .circleStyle:
            let squareRect = ILRectSquareInRect(insetRect)
            let indicatorInset = (squareRect.size.width - (squareRect.size.width * datum)) / 2 // ??? equal area?
            filledPath = ILBezierPath(ovalIn: squareRect.insetBy(dx: indicatorInset, dy: indicatorInset))
        case .ringStyle:
            let squareRect = ILRectSquareInRect(insetRect)
            let radius = (squareRect.size.height / 2) - ILPathlineWidth
            let squareCenter = ILPointCenteredInRect(squareRect)
            let topDeadCenter = CGPoint(x: squareCenter.x, y: squareCenter.y - radius)
            let secondAngle = ILZeroAngleRadians + ILPercentToRadians(datum)
            filledPath = ILBezierPath()
            filledPath.addArc(withCenter: squareCenter, radius: radius, startAngle: ILZeroAngleRadians, endAngle: secondAngle, clockwise: true)
            let insetPoint = ILPointOnLineToPointAtDistance(filledPath.currentPoint, squareCenter, sparkStyle.ringWidth)
            filledPath.addLine(to: insetPoint)
            filledPath.addArc(withCenter: squareCenter, radius: radius - sparkStyle.ringWidth, startAngle: secondAngle, endAngle: ILZeroAngleRadians, clockwise: false)
            filledPath.addLine(to: topDeadCenter)
        case .pieStyle:
            let squareRect = ILRectSquareInRect(insetRect)
            let radius = (squareRect.size.height / 2) - ILPathlineWidth
            let squareCenter = ILPointCenteredInRect(squareRect)
            let topDeadCenter = CGPoint(x: squareCenter.x, y: squareCenter.y - radius)
            let firstAngle = -(CGFloat.pi / 2)
            let secondAngle = ((2 * CGFloat.pi) * datum) - (CGFloat.pi / 2)
            filledPath = ILBezierPath()
            filledPath.addArc(withCenter: squareCenter, radius: radius, startAngle: firstAngle, endAngle: secondAngle, clockwise: true)
            filledPath.addLine(to: squareCenter)
            filledPath.addLine(to: topDeadCenter)
        case .dialStyle:
            let squareRect = ILRectSquareInRect(insetRect)
            let radius = (squareRect.size.height / 2) - sparkStyle.dialWidth
            let squareCenter = ILPointCenteredInRect(squareRect)
            let indicatorAngle = ((2 * CGFloat.pi) * datum) - (CGFloat.pi / 2)
            filledPath = ILBezierPath()
            filledPath.addArc(withCenter: squareCenter, radius: radius, startAngle: indicatorAngle, endAngle: indicatorAngle, clockwise: true)
            filledPath.addLine(to: squareCenter)
        }

        let indicatorLayer = CAShapeLayer()
        indicatorLayer.path = filledPath.sparkPath
        indicatorLayer.fillColor = sparkStyle.fill?.cgColor
        if sparkStyle.meterStyle == .dialStyle {
            indicatorLayer.strokeColor = sparkStyle.fill?.cgColor
            indicatorLayer.lineWidth = sparkStyle.dialWidth
            indicatorLayer.lineCap = .round
        }
        else {
            indicatorLayer.strokeColor = sparkStyle.stroke?.cgColor
            indicatorLayer.lineWidth = sparkStyle.width
        }
        return indicatorLayer
    }

    #if !os(macOS)
    // MARK: - UIView

    open override func layoutSubviews() {
        super.layoutSubviews()
        indicatorLayer?.frame = bounds
    }
    #endif

    // MARK: - ILSparkView

    open override func updateView() {
        CATransaction.begin()
        CATransaction.setDisableActions(true) // a new layer each update, fading between them flickers
        super.updateView()
        let indicatorLayer = ILSparkMeter.sparkMeter(datum: dataSource?.datum ?? 0, size: frame.size, sparkStyle: style)
        replaceContent(self.indicatorLayer, with: indicatorLayer)
        self.indicatorLayer = indicatorLayer
        CATransaction.commit()
    }

    open override var isCircular: Bool {
        style.meterStyle.isCircular
    }
}

// MARK: -

/// ILSparkStyle hints for spark meters
extension ILSparkStyle {
    @objc public var meterStyle: ILSparkMeterStyle {
        numberHint(ILSparkMeterStyleHint).flatMap { ILSparkMeterStyle(rawValue: $0.intValue) } ?? .horizontalStyle
    }

    @objc public var fillDirection: ILSparkMeterFillDirection {
        numberHint(ILSparkMeterFillDirectionHint).flatMap { ILSparkMeterFillDirection(rawValue: $0.intValue) } ?? .naturalFill
    }

    @objc public var minAngle: CGFloat {
        numberHint(ILSparkMeterMinAngleHint).map { CGFloat($0.doubleValue) } ?? 0.0
    }

    @objc public var maxAngle: CGFloat {
        numberHint(ILSparkMeterMaxAngleHint).map { CGFloat($0.doubleValue) } ?? 1.0
    }

    @objc public var fillClockwise: Bool {
        numberHint(ILSparkMeterFillClockwiseHint)?.boolValue ?? true
    }

    @objc public var dialWidth: CGFloat {
        numberHint(ILSparkMeterDialWidthHint).map { CGFloat($0.doubleValue) } ?? ILSparkMeterDefaultDialWidth
    }

    @objc public var ringWidth: CGFloat {
        numberHint(ILSparkMeterRingWidthHint).map { CGFloat($0.doubleValue) } ?? ILSparkMeterDefaultRingWidth
    }
}

#if os(macOS)

// MARK: -

/// draws its represented object, an ILSparkMeterDataSource, as a spark meter
@objc(ILSparkMeterCell)
open class ILSparkMeterCell: NSActionCell {

    /// style information
    @objc open var style = ILSparkStyle.defaultStyle

    // MARK: - NSCell

    open override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        guard let data = representedObject as? ILSparkMeterDataSource else { return }
        let sparkMeter = ILSparkMeter.sparkMeter(datum: data.datum, size: cellFrame.size, sparkStyle: style)
        controlView.layer?.addSublayer(sparkMeter)
        sparkMeter.frame = cellFrame
    }
}

#endif
