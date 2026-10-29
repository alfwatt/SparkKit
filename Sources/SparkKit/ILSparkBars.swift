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
            // the bars grow from the edge the style names, from the left or right the buckets run down the view
            let direction = style.edgeDirection(default: .fromBottom)
            let bucketCount = dataSource.buckets.count
            let insetRect = borderInset
            let bucketWidth = (direction.isHorizontal ? frame.size.height : frame.size.width) / CGFloat(bucketCount)

            if bucketWidth < 1.0 { // we got problems, deal with it later
                NSLog("invalid bucket width: %f view width: %f bucket count: %lu", bucketWidth, frame.size.width, bucketCount)
            }

            for bucketIndex in 0..<bucketCount {
                let bucketValue = dataSource.bucketValue(bucketIndex)
                guard bucketValue > 0.0 else { continue } // skip empty buckets
                let gap = min(max(barGap, 0), bucketWidth / 2) // half on each side, so the outer bars line up with the edges
                let leading = bucketIndex > 0 ? gap / 2 : 0
                let trailing = bucketIndex < bucketCount - 1 ? gap / 2 : 0
                let bucketStart = (bucketWidth * CGFloat(bucketIndex)) + leading
                let slot = direction.isHorizontal
                    ? CGRect(x: insetRect.minX, y: insetRect.minY + bucketStart, width: insetRect.width, height: bucketWidth - leading - trailing)
                    : CGRect(x: insetRect.minX + bucketStart, y: insetRect.minY, width: bucketWidth - leading - trailing, height: insetRect.height)
                let bucketRect = slot.band(from: direction, 0, bucketValue)
                let bucketLayer = CAShapeLayer()
                bucketLayer.path = CGPath(rect: bucketRect, transform: nil)
                bucketLayer.fillColor = style.fill?.cgColor
                bucketLayer.strokeColor = style.stroke?.cgColor
                barsLayer.addSublayer(bucketLayer)
            }
        }
        else {
            NSLog("no bucket data")
        }

        super.updateView()
        CATransaction.commit()
    }

    // MARK: - ILBucketDataDelegate

    open func bucketDataDidUpdate(_ data: ILBucketData) {
        OperationQueue.main.addOperation { [weak self] in
            self?.updateView()
        }
    }
}

/* Copyright © 2016-2026, Alf Watt (alf@istumbler.net) Avaliale under MIT Style license in README.md */
