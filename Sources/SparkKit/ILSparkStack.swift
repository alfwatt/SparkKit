/* Copyright © 2016-2026, Alf Watt (alf@istumbler.net) Avaliale under MIT Style license in README.md */
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

/// style hint, an array of ILColors for the values in the stack
public let ILSparkStackColorsHint = "ILSparkStackColorsHint"

// MARK: -

/// data source protocol for ILSparkStack
@objc public protocol ILSparkStackDataSource: NSObjectProtocol {

    /// any number of numbers
    var data: [NSNumber] { get }
}

// MARK: -

/// ILSparkStack displays a meter with a stack of values, using a list of of colors provided as a style hint
@objc(ILSparkStack)
open class ILSparkStack: ILSparkView {
    private var stackLayer: CALayer?

    @objc open weak var stackDataSource: ILSparkStackDataSource?

    static let defaultStackColors: [ILColor] = [.red, .orange, .yellow, .green, .blue, .gray, .white, .clear, .black]

    static func sparkStack(data: [NSNumber]?, size: CGSize, sparkStyle: ILSparkStyle) -> CALayer {
        let stackLayer = CALayer()
        let insetRect = CGRect(origin: .zero, size: size)
        stackLayer.frame = insetRect

        guard let data else { return stackLayer }

        // sum the data, so we can compute percentages
        let dataTotal = data.reduce(CGFloat(0)) { $0 + CGFloat($1.doubleValue) }
        guard dataTotal > 0 else { return stackLayer }

        let stackColors = sparkStyle.stackColors
        var dataOffset: CGFloat = 0
        for (datumIndex, datum) in data.enumerated() {
            var filledPath: ILBezierPath?
            let datumPercentage = CGFloat(datum.doubleValue) / dataTotal
            let fillColor = stackColors.isEmpty ? nil : stackColors[datumIndex % stackColors.count]

            switch sparkStyle.meterStyle {
            case .textStyle: // all the lines at once, with the first datum
                if datumIndex == 0 {
                    let lines = data.enumerated().map { index, value in
                        (text: ILSparkMeter.percentString(CGFloat(value.doubleValue) / dataTotal),
                         color: stackColors.isEmpty ? sparkStyle.fill : stackColors[index % stackColors.count])
                    }
                    stackLayer.addSublayer(ILSparkMeter.textLayers(lines, size: insetRect.size, sparkStyle: sparkStyle))
                }
            case .verticalStyle:
                let indicatorHeight = insetRect.size.height * datumPercentage
                let indicatorOffset = (insetRect.origin.y + insetRect.size.height) - (dataOffset * insetRect.size.height) - indicatorHeight
                filledPath = ILBezierPath(rect: CGRect(x: insetRect.origin.x, y: indicatorOffset, width: insetRect.size.width, height: indicatorHeight))
            case .horizontalStyle:
                let indicatorWidth = insetRect.size.width * datumPercentage
                let indicatorOffset = insetRect.origin.x + (insetRect.size.width * dataOffset)
                filledPath = ILBezierPath(rect: CGRect(x: insetRect.origin.x + indicatorOffset, y: insetRect.origin.y, width: indicatorWidth, height: insetRect.size.height))
            case .squareStyle, .circleStyle:
                // concentric bands from the outside in, each covers the rest of the stack and the next is drawn over it,
                // the band's area is the datum's share of the whole
                let squareRect = ILRectSquareInRect(insetRect)
                let side = squareRect.size.width * sqrt(max(1 - dataOffset, 0))
                let bandRect = squareRect.insetBy(dx: (squareRect.size.width - side) / 2, dy: (squareRect.size.height - side) / 2)
                filledPath = sparkStyle.meterStyle == .squareStyle ? ILBezierPath(rect: bandRect) : ILBezierPath(ovalIn: bandRect)
            case .ringStyle:
                let squareRect = ILRectSquareInRect(insetRect)
                let radius = (squareRect.size.height / 2) - ILPathlineWidth
                let squareCenter = ILPointCenteredInRect(squareRect)
                let firstAngle = ILZeroAngleRadians + ILPercentToRadians(dataOffset)
                let secondAngle = firstAngle + ILPercentToRadians(datumPercentage)
                let path = ILBezierPath()
                path.addArc(withCenter: squareCenter, radius: radius, startAngle: firstAngle, endAngle: secondAngle, clockwise: true)
                let insetPoint = ILPointOnLineToPointAtDistance(path.currentPoint, squareCenter, sparkStyle.ringWidth)
                path.addLine(to: insetPoint)
                path.addArc(withCenter: squareCenter, radius: radius - sparkStyle.ringWidth, startAngle: secondAngle, endAngle: firstAngle, clockwise: false)
                path.close()
                filledPath = path
            case .pieStyle:
                let squareRect = ILRectSquareInRect(insetRect)
                let radius = (squareRect.size.height / 2) - ILPathlineWidth
                let squareCenter = ILPointCenteredInRect(squareRect)
                let firstAngle = ILZeroAngleRadians + ILPercentToRadians(dataOffset)
                let secondAngle = firstAngle + ILPercentToRadians(datumPercentage)
                let path = ILBezierPath()
                path.addArc(withCenter: squareCenter, radius: radius, startAngle: firstAngle, endAngle: secondAngle, clockwise: true)
                path.addLine(to: squareCenter)
                path.close()
                filledPath = path
            case .dialStyle:
                let squareRect = ILRectSquareInRect(insetRect)
                let radius = (squareRect.size.height / 2) - sparkStyle.dialWidth
                let squareCenter = ILPointCenteredInRect(squareRect)
                let indicatorAngle = ILZeroAngleRadians + ILPercentToRadians(datumPercentage)
                let path = ILBezierPath()
                path.addArc(withCenter: squareCenter, radius: radius, startAngle: indicatorAngle, endAngle: indicatorAngle, clockwise: true)
                path.addLine(to: squareCenter)
                filledPath = path
            }

            dataOffset += datumPercentage

            if let filledPath {
                let indicatorLayer = CAShapeLayer()
                indicatorLayer.path = filledPath.sparkPath
                indicatorLayer.fillColor = fillColor?.cgColor
                indicatorLayer.zPosition = CGFloat(datumIndex) // later bands over earlier ones
                if sparkStyle.meterStyle == .dialStyle {
                    indicatorLayer.strokeColor = fillColor?.cgColor
                    indicatorLayer.lineWidth = sparkStyle.dialWidth
                    indicatorLayer.lineCap = .round
                }
                else {
                    indicatorLayer.strokeColor = sparkStyle.stroke?.cgColor
                    indicatorLayer.lineWidth = 0
                }
                stackLayer.addSublayer(indicatorLayer)
                indicatorLayer.frame = stackLayer.bounds
            }
        }

        return stackLayer
    }

    // MARK: - ILSparkView

    open override func updateView() {
        CATransaction.begin()
        CATransaction.setDisableActions(true) // a new layer each update, fading between them flickers
        super.updateView()
        let stackLayer = ILSparkStack.sparkStack(data: stackDataSource?.data, size: frame.size, sparkStyle: style)
        replaceContent(self.stackLayer, with: stackLayer)
        self.stackLayer = stackLayer
        CATransaction.commit()
    }

    open override var isCircular: Bool {
        style.meterStyle.isCircular
    }
}

// MARK: -

/// ILSparkStyle hints for spark stacks
extension ILSparkStyle {
    @objc public var stackColors: [ILColor] {
        hints[ILSparkStackColorsHint] as? [ILColor] ?? ILSparkStack.defaultStackColors
    }
}

#if os(macOS)

// MARK: -

/// draws its represented object, an ILSparkStackDataSource, as a spark stack
@objc(ILSparkStackCell)
open class ILSparkStackCell: NSActionCell {

    /// style information
    @objc open var style = ILSparkStyle.defaultStyle

    // MARK: - NSCell

    open override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        guard let data = representedObject as? ILSparkStackDataSource else { return }
        let sparkStack = ILSparkStack.sparkStack(data: data.data, size: cellFrame.size, sparkStyle: style)
        controlView.layer?.addSublayer(sparkStack)
        sparkStack.frame = cellFrame
    }
}

#endif
