import Foundation
import QuartzCore
import KitBridge
#if SWIFT_PACKAGE
import KitBridgeSwift
#endif

/// ILSparkBars is a view for showing ILBucketData
@objc(ILSparkBars)
open class ILSparkBars: ILSparkView, ILBucketDataDelegate {
    private let barsLayer = CALayer()

    @objc open var dataSource: ILBucketData?

    /// the space between the bars, in points, each bar is narrower by the gap, defaults to 0
    @objc open var barGap: CGFloat = 0

    // MARK: - ILSparkView

    open override func initView() {
        super.initView()
        addContent(barsLayer)
        barsLayer.frame = sparkLayer.bounds
        barsLayer.contentsGravity = .resize
    }

    open override func updateView() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0) // TODO use the time between updates
        barsLayer.frame = sparkLayer.bounds
        barsLayer.backgroundColor = style.background?.cgColor
        barsLayer.sublayers = nil

        if let dataSource {
            let values = (0..<dataSource.buckets.count).map { dataSource.bucketValue($0) }
            ILSparkBars.addBars(values, to: barsLayer, in: borderInset, viewSize: frame.size, style: style, barGap: barGap)
        }
        else {
            NSLog("no bucket data")
        }

        super.updateView()
        CATransaction.commit()
    }

    /// a bar for each value between 0 and 1, growing from the edge the style names, the bottom by default,
    /// from the left or right the bars run down the view
    static func addBars(_ values: [CGFloat], to barsLayer: CALayer, in insetRect: CGRect, viewSize: CGSize, style: ILSparkStyle, barGap: CGFloat) {
        let direction = style.edgeDirection(default: .fromBottom)
        let bucketCount = values.count
        let bucketWidth = (direction.isHorizontal ? viewSize.height : viewSize.width) / CGFloat(bucketCount) // can be under a point

        // one shape layer for all the bars, a layer for each is slow to update many times a second
        let barsPath = CGMutablePath()
        for (bucketIndex, bucketValue) in values.enumerated() {
            guard bucketValue > 0.0 else { continue } // skip empty buckets
            let gap = min(max(barGap, 0), bucketWidth / 2) // half on each side, so the outer bars line up with the edges
            let leading = bucketIndex > 0 ? gap / 2 : 0
            let trailing = bucketIndex < bucketCount - 1 ? gap / 2 : 0
            let bucketStart = (bucketWidth * CGFloat(bucketIndex)) + leading
            let slot = direction.isHorizontal
                ? CGRect(x: insetRect.minX, y: insetRect.minY + bucketStart, width: insetRect.width, height: bucketWidth - leading - trailing)
                : CGRect(x: insetRect.minX + bucketStart, y: insetRect.minY, width: bucketWidth - leading - trailing, height: insetRect.height)
            barsPath.addRect(slot.band(from: direction, 0, min(bucketValue, 1)))
        }
        let bucketsLayer = CAShapeLayer()
        bucketsLayer.path = barsPath
        bucketsLayer.fillColor = style.fill?.cgColor
        bucketsLayer.strokeColor = style.stroke?.cgColor
        barsLayer.addSublayer(bucketsLayer)
    }

    // MARK: - ILBucketDataDelegate

    open func bucketDataDidUpdate(_ data: ILBucketData) {
        OperationQueue.main.addOperation { [weak self] in
            self?.updateView()
        }
    }
}

/* Copyright © 2016-2026, Alf Watt (alf@istumbler.net) Avaliale under MIT Style license in README.md */
