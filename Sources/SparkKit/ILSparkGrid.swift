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

/// ILSparkStyle hints for spark grids
extension ILSparkStyle {
    /// the size of each row, nil for square cells, 0 to stretch the rows to fill the view
    public var gridRowSize: CGFloat? {
        numberHint(ILSparkGridRowSizeHint).map { CGFloat($0.doubleValue) }
    }

    @objc public var gridEmptyColor: ILColor {
        hints[ILSparkGridEmptyColorHint] as? ILColor ?? ILColor(white: 0.5, alpha: 0.15)
    }
}

// MARK: -

/// shows an ILGridData as a grid of cells, each blends from the style's background to its fill by its value in the value range,
/// the newest row is at the edge the style's fill direction names, the top by default, from the left or right the rows are columns
/// with the first value at the bottom, the cells are square unless the style sizes the rows
@objc(ILSparkGrid)
open class ILSparkGrid: ILSparkView, ILGridDataDelegate {
    private let gridLayer = CALayer() // the empty grid, behind the rows
    private var rowLayers: [CALayer] = [] // the rows shown, oldest first

    @objc open var grid: ILGridData? {
        didSet {
            grid?.delegate = self
            OperationQueue.main.addOperation { [weak self] in
                self?.updateView()
            }
        }
    }

    @objc open var valueRange = NSRange(location: 0, length: 0)

    // MARK: - Geometry

    private var direction: ILSparkFillDirection { style.edgeDirection(default: .fromTop) }

    /// the length of the rows, across the grid
    private var acrossLength: CGFloat { direction.isHorizontal ? bounds.height : bounds.width }

    /// the length the rows are stacked along
    private var alongLength: CGFloat { direction.isHorizontal ? bounds.width : bounds.height }

    /// the size of each row along the grid
    private var rowSize: CGFloat {
        let columns = CGFloat(grid?.columns ?? 0)
        guard let size = style.gridRowSize else {
            return columns > 0 ? max(acrossLength / columns, 1) : alongLength
        }
        return size > 0 ? size : alongLength / CGFloat(max(grid?.rows ?? 0, 1))
    }

    /// the number of rows that fit in the view
    private var visibleRows: Int {
        Int((alongLength / rowSize).rounded(.up))
    }

    /// the frame of the row, counted from the newest, its edges on whole points so the rows meet without seams
    private func rect(ofRowFromNewest age: Int) -> CGRect {
        let start = (rowSize * CGFloat(age)).rounded()
        let offset = start
        let size = (rowSize * CGFloat(age + 1)).rounded() - start
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
        let low = RGBA(style.background), high = RGBA(style.fill)
        let vertical = direction.isHorizontal // rows from the side are columns
        var pixels = [UInt8](repeating: 0, count: percents.count * 4)
        for (column, percent) in percents.enumerated() {
            let value = min(max(percent, 0), 1)
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

    private func rowLayer(_ rowData: Data, in grid: ILGridData) -> CALayer {
        let rowLayer = CALayer()
        rowLayer.contents = image(of: grid.percents(ofRowData: rowData, in: valueRange))
        rowLayer.contentsGravity = .resize
        rowLayer.magnificationFilter = .nearest
        return rowLayer
    }

    /// place the rows from the newest, without animating
    private func layoutRows() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (age, rowLayer) in rowLayers.reversed().enumerated() {
            rowLayer.frame = rect(ofRowFromNewest: age)
        }
        CATransaction.commit()
    }

    /// drop the oldest rows that no longer fit
    private func dropHiddenRows() {
        let hidden = rowLayers.count - visibleRows
        if hidden > 0 {
            rowLayers.prefix(hidden).forEach { $0.removeFromSuperlayer() }
            rowLayers.removeFirst(hidden)
        }
    }

    /// redraw the rows that fit from the grid
    private func drawRows(_ grid: ILGridData) {
        rowLayers.forEach { $0.removeFromSuperlayer() }
        let rows = grid.rows
        rowLayers = (max(rows - visibleRows, 0)..<rows).map { rowLayer(grid.data(atRow: $0), in: grid) }
        rowLayers.forEach { gridLayer.addSublayer($0) }
        layoutRows()
    }

    // MARK: - ILSparkView

    open override func initView() {
        super.initView()
        grid = nil
        style = ILSparkStyle.defaultStyle
        addContent(gridLayer)
        gridLayer.masksToBounds = true
    }

    open override func updateView() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gridLayer.frame = sparkLayer.bounds
        gridLayer.backgroundColor = style.gridEmptyColor.cgColor
        if let grid, grid.rows > 0, grid.columns > 0 {
            errorString = nil
            drawRows(grid)
        }
        else {
            errorString = style.l10Nbundle?.localizedString(forKey: "No Data", value: "No Data", table: nil) ?? "No Data"
            rowLayers.forEach { $0.removeFromSuperlayer() }
            rowLayers = []
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
            if rowLayers.isEmpty { // the first rows, show the grid
                updateView()
                return
            }
            for slice in slices {
                let rowLayer = rowLayer(slice, in: grid)
                gridLayer.addSublayer(rowLayer)
                rowLayers.append(rowLayer)
            }
            dropHiddenRows()
            layoutRows()
            updateLabelsAndBorder()
        }
    }
}

/* Copyright © 2016-2026, Alf Watt (alf@istumbler.net) Avaliale under MIT Style license in README.md */
