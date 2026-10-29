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

private let labelRadius: CGFloat = 6
private let labelMargin: CGFloat = 9

/// the scale of the main screen, for text layers
var ILMainScreenScale: CGFloat {
    #if os(macOS)
    ILScreen.main?.scale ?? 1
    #else
    ILScreen.main.scale
    #endif
}

/// base class for all SparkKit views
@objc(ILSparkView)
open class ILSparkView: ILView, ILViewLifecycle {
    private var styleStorage: ILSparkStyle?
    private var borderStorage: CAShapeLayer? // the outline, over the content
    private var backgroundStorage: CAShapeLayer? // the background in the outline, behind the content
    private let labelLayer = CALayer()
    private var labelsNeedUpdate = false

    // MARK: - Style

    /// view style, the default style if none is set
    @objc open var style: ILSparkStyle {
        get { styleStorage ?? ILSparkStyle.defaultStyle }
        set { styleStorage = newValue }
    }

    /// the view's layer, which SparkKit views always have
    var sparkLayer: CALayer {
        #if os(macOS)
        layer! // set in initView
        #else
        layer
        #endif
    }

    /// the path of the border, inset so the whole stroke is in the view
    private var borderPath: CGPath {
        let inset = style.width / 2
        return isCircular ? CGPath(ellipseIn: ILRectSquareInRect(bounds).insetBy(dx: inset, dy: inset), transform: nil)
                          : CGPath(rect: bounds.insetBy(dx: inset, dy: inset), transform: nil)
    }

    /// border layer, the outline drawn over the content
    @objc open var border: CAShapeLayer {
        if let borderStorage {
            return borderStorage
        }
        let border = CAShapeLayer()
        border.path = borderPath
        borderStorage = border
        return border
    }

    /// the background inside the border, behind the content
    private var borderBackground: CAShapeLayer {
        if let backgroundStorage {
            return backgroundStorage
        }
        let background = CAShapeLayer()
        background.path = borderPath
        backgroundStorage = background
        return background
    }

    /// drop the border layers, they're redrawn at the new size
    private func resetBorder() {
        borderStorage?.removeFromSuperlayer()
        borderStorage = nil
        backgroundStorage?.removeFromSuperlayer()
        backgroundStorage = nil
    }

    /// is the border circular?
    @objc open var isCircular: Bool { false }

    /// inset of border rectangle, effective drawable area
    @objc open var borderInset: CGRect {
        guard style.bordered else { return bounds }
        let inset = style.width * 2
        return bounds.insetBy(dx: inset, dy: inset)
    }

    // MARK: - Labels

    @objc open var yAxisLabels: [Any]? { didSet { labelsNeedUpdate = true } }
    @objc open var yAxisUnits: String? { didSet { labelsNeedUpdate = true } }
    @objc open var yAxisLabelsCenteredOnRows = false
    @objc open var xAxisLabels: [Any]? { didSet { labelsNeedUpdate = true } }
    @objc open var xAxisUnits: String? { didSet { labelsNeedUpdate = true } }
    @objc open var xAxisLabelsCenteredOnColumns = false
    @objc open var errorString: String? {
        didSet {
            if errorString != oldValue { // only mark the view for updates if the error string changed
                labelsNeedUpdate = true
            }
        }
    }

    private func string(for value: Any, units: String?) -> String {
        guard let units else { return String(describing: value) }
        return "\(value) \(units)"
    }

    private func layer(forLabel label: String) -> CATextLayer {
        let textLayer = CATextLayer()
        textLayer.string = label
        textLayer.contentsGravity = .center
        textLayer.font = style.font?.fontName as CFTypeRef?
        textLayer.fontSize = style.font?.pointSize ?? 0
        textLayer.foregroundColor = style.fontColor?.cgColor
        textLayer.contentsScale = ILMainScreenScale
        #if os(macOS)
        textLayer.backgroundColor = ILColor(white: 1.0, alpha: 0.66).cgColor
        #else
        textLayer.backgroundColor = ILColor.white.cgColor
        #endif
        textLayer.allowsFontSubpixelQuantization = true
        textLayer.cornerRadius = labelRadius
        textLayer.alignmentMode = .center

        let attributes: [NSAttributedString.Key: Any] = style.font.map { [.font: $0] } ?? [:]
        let textSize = (label as NSString).size(withAttributes: attributes)
        textLayer.bounds = CGRect(x: 0, y: 0, width: textSize.width + labelMargin, height: textSize.height)
        labelLayer.addSublayer(textLayer)
        return textLayer
    }

    // MARK: - ILView

    public override init(frame: CGRect) {
        super.init(frame: frame)
        initView()
    }

    // MARK: - NSCoding

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        initView()
    }

    #if os(macOS)
    // MARK: - NSView

    open override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard layer != nil else { return } // not yet initialized
        resetBorder()
        labelsNeedUpdate = true
        updateView()
    }

    open override var isFlipped: Bool { true }
    #else
    // MARK: - UIView

    private var laidOutSize = CGSize.zero

    open override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != laidOutSize else { return }
        laidOutSize = bounds.size
        resetBorder()
        labelsNeedUpdate = true
        updateView()
    }
    #endif

    // MARK: - ILViewLifecycle

    @objc open func initView() {
        #if os(macOS)
        layer = CALayer()
        wantsLayer = true
        #endif

        style = ILSparkStyle.defaultStyle

        sparkLayer.addSublayer(labelLayer)
        labelLayer.frame = sparkLayer.bounds
    }

    @objc open func updateView() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.1) // TODO use the time between updates

        if labelsNeedUpdate {
            updateLabels()
            labelsNeedUpdate = false
        }

        // the background behind the content and the outline over it, in order because snapshots ignore the zPosition
        if style.bordered {
            let backgroundLayer = borderBackground
            backgroundLayer.fillColor = style.background?.cgColor
            backgroundLayer.zPosition = -1
            if backgroundLayer.superlayer !== sparkLayer {
                sparkLayer.insertSublayer(backgroundLayer, at: 0)
            }

            let borderLayer = border
            borderLayer.fillColor = nil
            borderLayer.lineWidth = style.width
            borderLayer.strokeColor = style.border?.cgColor
            borderLayer.zPosition = 0.5 // over the content, under the labels
            if borderLayer.superlayer !== sparkLayer {
                sparkLayer.insertSublayer(borderLayer, below: labelLayer)
            }
        }
        else {
            resetBorder()
        }

        CATransaction.commit()
    }

    /// add a content layer over the background, under the outline and labels
    func addContent(_ contentLayer: CALayer) {
        let above = borderStorage.flatMap { $0.superlayer === sparkLayer ? $0 : nil } ?? labelLayer
        sparkLayer.insertSublayer(contentLayer, below: above)
    }

    /// replace the old content layer with the new one, keeping the border and labels, without animating
    func replaceContent(_ oldLayer: CALayer?, with newLayer: CALayer) {
        newLayer.frame = bounds
        if let oldLayer, oldLayer.superlayer === sparkLayer {
            sparkLayer.replaceSublayer(oldLayer, with: newLayer)
        }
        else {
            addContent(newLayer)
        }
    }

    // MARK: - Label Layout

    private func updateLabels() {
        let bounds = sparkLayer.bounds
        labelLayer.frame = bounds
        labelLayer.sublayers = nil
        labelLayer.zPosition = 1.0 // frontmost

        if let errorString { // put it on a text layer in the middle
            let errorLayer = layer(forLabel: errorString)
            errorLayer.position = ILPointCenteredInRect(labelLayer.frame)
            return
        }

        if let yAxisLabels {
            layoutYAxisLabels(yAxisLabels, in: bounds)
        }
        if let xAxisLabels {
            layoutXAxisLabels(xAxisLabels, in: bounds)
        }
    }

    private func layoutYAxisLabels(_ yAxisLabels: [Any], in bounds: CGRect) {
        let yLabelCount = yAxisLabels.count
        let xLabelCount = xAxisLabels?.count ?? 0
        if yAxisLabelsCenteredOnRows { // centered over each row
            let labelGap = bounds.size.height / CGFloat(yLabelCount)
            let labelOffset = labelGap / 2
            for (labelIndex, yLabel) in yAxisLabels.enumerated() {
                let label = layer(forLabel: string(for: yLabel, units: yAxisUnits))
                let yPosition = (labelGap * CGFloat(labelIndex)) + labelOffset - (label.bounds.size.height / 2)
                label.frame = CGRect(x: labelMargin, y: yPosition, width: label.bounds.size.width, height: label.bounds.size.height)
                // check situations with too many labels
                if labelIndex == 0 && labelGap < (label.bounds.size.height * 1.5) { // too many vertical labels to print
                    // move it to the top-left position
                    label.frame = CGRect(x: labelMargin, y: labelMargin, width: label.bounds.size.width, height: label.bounds.size.height)
                    if let last = yAxisLabels.last {
                        addBottomLabel(last, in: bounds)
                    }
                    break // skip the rest
                }
                else if labelIndex == yLabelCount - 1 && xLabelCount >= 2 && labelGap < (label.frame.size.height * 4) {
                    label.removeFromSuperlayer() // yoink
                }
            }
        }
        else if yLabelCount > 0 { // top left
            let topLabel = layer(forLabel: string(for: yAxisLabels[0], units: yAxisUnits))
            topLabel.frame = CGRect(x: labelMargin, y: labelMargin, width: topLabel.bounds.size.width, height: topLabel.bounds.size.height)

            if yLabelCount >= 2 {
                let labelGap = bounds.size.height / CGFloat(yLabelCount - 1)
                if xLabelCount >= 2 { // deal with collisions
                    if !((xAxisLabels?[0] as AnyObject).isEqual(yAxisLabels[1])) // skip the duplicate case
                        && labelGap > (topLabel.bounds.size.height * 4) { // scoot up, if there is room
                        addBottomLabel(yAxisLabels[yLabelCount - 1], in: bounds)
                    }
                }
                else {
                    let bottomLabel = layer(forLabel: string(for: yAxisLabels[1], units: yAxisUnits))
                    bottomLabel.frame = CGRect(x: labelMargin, y: labelMargin, width: bottomLabel.bounds.size.width, height: bottomLabel.bounds.size.height)
                }

                if yLabelCount > 2 && labelGap > (topLabel.bounds.size.height * 1.1) { // add middle values if there's room
                    for labelIndex in 1..<(yLabelCount - 1) {
                        let middleLabel = layer(forLabel: string(for: yAxisLabels[labelIndex], units: yAxisUnits))
                        let yPosition = (labelGap * CGFloat(labelIndex)) - (middleLabel.bounds.size.height / 2)
                        middleLabel.frame = CGRect(x: labelMargin, y: yPosition, width: middleLabel.bounds.size.width, height: middleLabel.bounds.size.height)
                    }
                }
            }
        }
    }

    /// the last y axis label, offset above the x axis labels
    private func addBottomLabel(_ value: Any, in bounds: CGRect) {
        let bottomLabel = layer(forLabel: string(for: value, units: yAxisUnits))
        let bottomOffset = labelMargin * 3
        bottomLabel.frame = CGRect(x: labelMargin, y: bounds.size.height - bottomLabel.bounds.size.height - bottomOffset,
                                   width: bottomLabel.bounds.size.width, height: bottomLabel.bounds.size.height)
    }

    private func layoutXAxisLabels(_ xAxisLabels: [Any], in bounds: CGRect) {
        let xLabelCount = xAxisLabels.count
        if xAxisLabelsCenteredOnColumns { // centered over each column
            let labelGap = bounds.size.width / CGFloat(xLabelCount)
            let labelOffset = labelGap / 2
            for (labelIndex, xLabel) in xAxisLabels.enumerated() {
                let label = layer(forLabel: string(for: xLabel, units: xAxisUnits))
                let xPosition = (labelGap * CGFloat(labelIndex)) - (label.bounds.size.width / 2) + labelOffset
                let yPosition = bounds.size.height - label.bounds.size.height - (labelRadius / 2)
                label.frame = CGRect(x: xPosition, y: yPosition, width: label.bounds.size.width, height: label.bounds.size.height)

                // when the width isn't sufficent draw the first and last, then stop
                if labelIndex == 0 && labelGap < (label.bounds.size.width * 2) {
                    label.frame = CGRect(x: labelMargin, y: yPosition, width: label.bounds.size.width, height: label.bounds.size.height)
                    if let last = xAxisLabels.last {
                        let rightLabel = layer(forLabel: string(for: last, units: xAxisUnits))
                        let rightX = bounds.size.width - rightLabel.bounds.size.width - labelMargin
                        rightLabel.frame = CGRect(x: rightX, y: yPosition, width: rightLabel.bounds.size.width, height: rightLabel.bounds.size.height)
                    }
                    break
                }
            }
        }
        else if xLabelCount > 0 {
            let leftLabel = layer(forLabel: string(for: xAxisLabels[0], units: xAxisUnits))
            leftLabel.frame = CGRect(x: labelMargin, y: bounds.size.height - leftLabel.bounds.size.height - labelMargin,
                                     width: leftLabel.bounds.size.width, height: leftLabel.bounds.size.height)

            if xLabelCount >= 2 {
                let rightLabel = layer(forLabel: string(for: xAxisLabels[xLabelCount - 1], units: xAxisUnits))
                rightLabel.frame = CGRect(x: bounds.size.width - rightLabel.bounds.size.width - labelMargin,
                                          y: bounds.size.height - rightLabel.bounds.size.height - labelMargin,
                                          width: rightLabel.bounds.size.width, height: rightLabel.bounds.size.height)

                let labelGap = (bounds.size.width - leftLabel.bounds.size.width - rightLabel.bounds.size.width) / CGFloat(xLabelCount - 1) // fencepost
                if xLabelCount > 2 && labelGap > max(leftLabel.frame.size.width, rightLabel.frame.size.width) { // room for the in-between values
                    let labelOffset = leftLabel.bounds.size.width
                    for labelIndex in 1..<(xLabelCount - 1) { // skip the first and last
                        let middleLabel = layer(forLabel: string(for: xAxisLabels[labelIndex], units: xAxisUnits))
                        let xPosition = labelOffset + (labelGap * CGFloat(labelIndex)) - (middleLabel.bounds.size.width / 2)
                        let yPosition = bounds.size.height - middleLabel.bounds.size.height - labelMargin
                        middleLabel.frame = CGRect(x: xPosition, y: yPosition, width: middleLabel.bounds.size.width, height: middleLabel.bounds.size.height)
                    }
                }
            }
        }
    }
}

/* Copyright © 2016-2026, Alf Watt (alf@istumbler.net) Avaliale under MIT Style license in README.md */
