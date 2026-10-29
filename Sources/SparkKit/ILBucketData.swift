import Foundation
import CoreGraphics

/// Data which can be divided into equal sized buckets,
/// either in time (e.g. one minute) or space (e.g. one mile) etc.
/// A bar chart with time buckets is a histogram
/// A bar chart with frequency buckets is a frequency analyzer
@objc(ILBucketData)
open class ILBucketData: NSObject {

    /// delegate for data update notifications
    @objc public weak var delegate: ILBucketDataDelegate?

    /// numbers representing each bucket
    @objc public var buckets: [NSNumber] = [] {
        didSet { delegate?.bucketDataDidUpdate?(self) }
    }

    @objc public func bucketValue(_ bucketIndex: Int) -> CGFloat {
        CGFloat(buckets[bucketIndex].doubleValue)
    }
}

// MARK: -

/// notifications for the view when the data is updated
@objc public protocol ILBucketDataDelegate: NSObjectProtocol {
    @objc optional func bucketDataDidUpdate(_ data: ILBucketData)
}

/* Copyright © 2016-2026, Alf Watt (alf@istumbler.net) Avaliale under MIT Style license in README.md */
