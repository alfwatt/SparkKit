/* Copyright © 2016-2026, Alf Watt (alf@istumbler.net) Avaliale under MIT Style license in README.md */
import Foundation
import QuartzCore
import KitBridge
#if SWIFT_PACKAGE
import KitBridgeSwift
#endif

/// shows an ILGridData as rows of cells, shaded by their values in the value range, newest row at the bottom
@objc(ILSparkGrid)
open class ILSparkGrid: ILSparkView, ILGridDataDelegate {
    private let gridLayer = CALayer() // the grid data layer, a layer for each row

    @objc open var grid: ILGridData? {
        didSet {
            grid?.delegate = self
            OperationQueue.main.addOperation { [weak self] in
                self?.clearGrid()
                self?.updateView()
            }
        }
    }

    @objc open var valueRange = NSRange(location: 0, length: 0)

    // MARK: - Computed Properties

    private var rowHeight: CGFloat {
        let rows = CGFloat(grid?.rows ?? 0)
        return frame.size.height > rows ? (frame.size.height / rows) : 1.0
    }

    private var columnWidth: CGFloat {
        let columns = CGFloat(grid?.columns ?? 0)
        return frame.size.width > columns ? (frame.size.width / columns) : 1.0
    }

    private func rect(ofRow row: Int) -> CGRect {
        CGRect(x: 0, y: frame.size.height - (rowHeight * CGFloat(row + 1)), width: frame.size.width, height: rowHeight).integral
    }

    /// a layer for the row, shaded by the values
    private func layer(ofRow row: Int, in grid: ILGridData) -> CALayer {
        let rowLayer = CALayer()
        rowLayer.contents = grid.alphaBitmap(ofRow: row, with: valueRange)
        rowLayer.magnificationFilter = .nearest
        rowLayer.backgroundColor = style.background?.cgColor
        return rowLayer
    }

    // MARK: - ILSparkView

    open override func initView() {
        super.initView()

        grid = nil
        style = ILSparkStyle.defaultStyle

        sparkLayer.addSublayer(gridLayer)
        gridLayer.frame = sparkLayer.bounds
        gridLayer.contentsGravity = .resize
    }

    private func clearGrid() {
        gridLayer.sublayers = nil
        gridLayer.contents = nil
    }

    /// one shot, redraw the entire grid into the grid layer
    private func drawGrid(_ grid: ILGridData) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0) // TODO use the time between updates
        #if DEBUG
        let drawStart = Date.timeIntervalSinceReferenceDate
        #endif
        gridLayer.frame = sparkLayer.bounds
        gridLayer.sublayers = nil // TODO retain existing layers and only draw new ones
        gridLayer.backgroundColor = style.fill?.cgColor

        for row in 0..<grid.rows {
            let rowLayer = layer(ofRow: row, in: grid)
            gridLayer.addSublayer(rowLayer)
            rowLayer.frame = rect(ofRow: row)
        }

        #if DEBUG
        let drawTime = Date.timeIntervalSinceReferenceDate - drawStart
        if drawTime > (1.0 / 15) { // warn if we drop below 15 fps
            NSLog("%@ [%lu x %lu] %lu tiles in %0.6fs", self, grid.columns, grid.rows, grid.columns * grid.rows, drawTime)
        }
        #endif
        CATransaction.commit()
    }

    open override func updateView() {
        if let grid, grid.rows > 0, grid.columns > 0 {
            errorString = nil
            drawGrid(grid)
        }
        else {
            errorString = style.l10Nbundle?.localizedString(forKey: "No Data", value: "No Data", table: nil) ?? "No Data"
            clearGrid()
        }

        super.updateView()
    }

    // MARK: - ILGridDataDelegate

    open func grid(_ grid: ILGridData, didSetData data: Data, atRow row: Int) {
        // TODO update the grid layer
    }

    open func grid(_ grid: ILGridData, didAppendedData data: Data, asRow rowIndex: Int) {
        OperationQueue.main.addOperation { [weak self] in
            guard let self else { return }
            let rowLayer = layer(ofRow: rowIndex, in: grid)

            // move the existing rows down inside of an animation context, dropping the rows past the new one
            CATransaction.begin()
            var layerCount = gridLayer.sublayers?.count ?? 0
            var layerIndex = 0
            var oldLayers: [CALayer] = []
            for existingLayer in gridLayer.sublayers ?? [] {
                if layerCount > (rowIndex + 1) { // remove the layer
                    oldLayers.append(existingLayer)
                    layerCount -= 1
                }
                else { // move the layer into place
                    layerIndex += 1
                    existingLayer.frame = rect(ofRow: layerIndex)
                }
            }
            oldLayers.forEach { $0.removeFromSuperlayer() }

            // now add the new row
            gridLayer.addSublayer(rowLayer)
            rowLayer.frame = rect(ofRow: rowIndex)

            CATransaction.commit()
            updateLabelsAndBorder()
        }
    }

    /// the labels and border, without redrawing the grid
    private func updateLabelsAndBorder() {
        super.updateView()
    }

    open func grid(_ grid: ILGridData, willTrimToRangeOfRows rows: NSRange) {
        // TODO update the grid layer
    }
}
