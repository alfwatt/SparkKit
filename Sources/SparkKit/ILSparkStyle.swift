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

// MARK: Constants

public let ILSparkStyleFill = "Fill"
public let ILSparkStyleStroke = "Stroke"
public let ILSparkStyleBackground = "Background"
public let ILSparkStyleBorder = "Border"
public let ILSparkStyleGradient = "Gradient"
public let ILSparkStyleIsFilled = "IsFilled"
public let ILSparkStyleIsBordered = "IsBordered"
public let ILSparkStyleWidth = "Width"
public let ILSparkStyleHints = "Hints"

// MARK: - Line Widths

public let ILHairlineWidth: CGFloat = 0.25
public let ILFinelineWidth: CGFloat = 0.5
public let ILPathlineWidth: CGFloat = 1
public let ILBoldlineWidth: CGFloat = 2

// MARK: - Log Scale

/// style hint, a log scale for values between 0 and 1, the strength of the curve k, each value v is shown as log(1 + k·v) / log(1 + k),
/// which spreads out the low values and gives a waterfall more contrast, e.g. 10 is gentle and 100 strong, without it values are linear
public let ILSparkLogScaleHint = "ILSparkLogScaleHint"

// MARK: - Fill Direction

/// style hint, the direction the views fill in, an ILSparkFillDirection, each view has its own default
public let ILSparkFillDirectionHint = "ILSparkFillDirectionHint"

/// the direction a view fills in: from an edge, or for square and circle styles inward from the edges or outward from the center
@objc public enum ILSparkFillDirection: Int {
    case fromTop
    case fromBottom
    case fromLeft
    case fromRight
    case inward
    case outward

    /// from the left or right, the values run along the y axis
    var isHorizontal: Bool { self == .fromLeft || self == .fromRight }

    /// from one of the edges
    var isEdge: Bool { self != .inward && self != .outward }
}

extension CGRect {
    /// the band of the rect between the fractions of its length, measured from the edge the direction names
    func band(from direction: ILSparkFillDirection, _ start: CGFloat, _ end: CGFloat) -> CGRect {
        switch direction {
        case .fromTop, .inward, .outward: return CGRect(x: minX, y: minY + (height * start), width: width, height: height * (end - start))
        case .fromBottom: return CGRect(x: minX, y: maxY - (height * end), width: width, height: height * (end - start))
        case .fromLeft: return CGRect(x: minX + (width * start), y: minY, width: width * (end - start), height: height)
        case .fromRight: return CGRect(x: maxX - (width * end), y: minY, width: width * (end - start), height: height)
        }
    }
}

// MARK: -

/// encapsulates style information for an ILSparkView or ILSparkCell
@objc(ILSparkStyle)
open class ILSparkStyle: NSObject, NSCopying {

    /// fill color
    @objc public var fill: ILColor?

    /// stroke color
    @objc public var stroke: ILColor?

    /// background color
    @objc public var background: ILColor?

    /// border color
    @objc public var border: ILColor?

    /// gradient for color values
    #if os(macOS)
    @objc public var gradient: ILGradient?
    #else
    @objc public var gradient: NSObject? // not ILGradient, KitBridge defines it as NSObject, which Swift finds ambiguous
    #endif

    /// font used to render labels
    @objc public var font: ILFont?

    /// color used to render labels, defaults to the stroke color
    @objc public var fontColor: ILColor? {
        get { fontColorStorage ?? stroke }
        set { fontColorStorage = newValue }
    }
    private var fontColorStorage: ILColor?

    /// is the area filled?
    @objc public var filled = false

    /// is the view outlined?
    @objc public var bordered = false

    /// stroke width
    @objc public var width: CGFloat = 0

    /// hints for subclasses
    @objc public var hints: [String: Any] = [:]

    /// L10N bundle, for localizing strings
    @objc(L10Nbundle) public var l10Nbundle: Bundle?

    // MARK: -

    /// default style given to ILSparkViews when initilized
    @objc public static let defaultStyle: ILSparkStyle = {
        let style = ILSparkStyle()
        style.fill = .gray
        style.stroke = .darkGray
        style.border = .lightGray
        style.background = .clear
        style.filled = false
        style.bordered = true
        style.width = ILPathlineWidth
        style.font = ILFont(name: "Helvetica", size: 12)
        return style
    }()

    // MARK: -

    /// add provided hints to hints dictionary
    @objc public func addHints(_ additionalHints: [String: Any]) {
        hints.merge(additionalHints) { _, additional in additional }
    }

    /// copy the style and apply the provided hints
    @objc public func copy(withHints styleHints: [String: Any]) -> ILSparkStyle {
        let copy = self.copy() as! ILSparkStyle
        copy.addHints(styleHints)
        return copy
    }

    /// the direction hint, nil if there's none and the view uses its default
    public var fillDirection: ILSparkFillDirection? {
        numberHint(ILSparkFillDirectionHint).flatMap { ILSparkFillDirection(rawValue: $0.intValue) }
    }

    /// the direction hint if it's an edge, otherwise the view's default
    func edgeDirection(default defaultDirection: ILSparkFillDirection) -> ILSparkFillDirection {
        fillDirection.flatMap { $0.isEdge ? $0 : nil } ?? defaultDirection
    }

    /// the hint as a number, which may be an NSNumber or a Swift number
    func numberHint(_ key: String) -> NSNumber? {
        hints[key] as? NSNumber
    }

    /// the value, between 0 and 1, on the log scale the hint sets, or as it is without one
    public func scaled(_ value: CGFloat) -> CGFloat {
        let clamped = min(max(value, 0), 1)
        guard let strength = numberHint(ILSparkLogScaleHint).map({ CGFloat($0.doubleValue) }), strength > 0 else { return clamped }
        return log1p(strength * clamped) / log1p(strength)
    }

    // MARK: - NSObject

    open override var description: String {
        "<\(type(of: self)): \(Unmanaged.passUnretained(self).toOpaque()) fill=\(String(describing: fill)) stroke=\(String(describing: stroke)) "
            + "background=\(String(describing: background)) gradient=\(String(describing: gradient)) filled=\(filled) bordered=\(bordered) width=\(width)>"
    }

    // MARK: - NSCopying

    open func copy(with zone: NSZone? = nil) -> Any {
        let style = ILSparkStyle()
        style.fill = fill
        style.stroke = stroke
        style.border = border
        style.background = background
        style.gradient = gradient
        style.filled = filled
        style.bordered = bordered
        style.width = width
        style.font = font
        style.fontColorStorage = fontColorStorage
        style.hints = hints
        style.l10Nbundle = l10Nbundle
        return style
    }
}

/* Copyright © 2016-2026, Alf Watt (alf@istumbler.net) Avaliale under MIT Style license in README.md */
