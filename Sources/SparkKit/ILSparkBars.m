#import "ILSparkBars.h"
#import "ILBucketData.h"

@interface ILSparkBars ()
@property(nonatomic,retain) CALayer* barsLayer;
@end

// MARK: -

@implementation ILSparkBars

- (void) initView {
    [super initView];

    self.barsLayer = [CALayer new];
    [self.layer addSublayer:self.barsLayer];
    self.barsLayer.frame = self.layer.bounds;
    self.barsLayer.contentsGravity = kCAGravityResize;
}

- (void) updateView {
    [CATransaction begin];
    [CATransaction setValue:@(1 / 60) forKey:kCATransactionAnimationDuration]; // TODO use the time between updates
    // TODO a style preference and vertical buckets
    self.barsLayer.frame = self.layer.bounds;
    self.barsLayer.backgroundColor = self.style.background.CGColor;
    self.barsLayer.sublayers = nil;
    
    if (self.dataSource) {
        NSUInteger bucketCount = self.dataSource.buckets.count;
        NSUInteger bucketIndex = 0;
        CGRect insetRect = self.borderInset;
        CGFloat bucketWidth = self.frame.size.width / bucketCount;
        
        if (bucketWidth < 1.0) { // we got problems, deal with it later
            NSLog(@"invalid bucket width: %f view width: %f bucket count: %lu", bucketWidth, self.frame.size.width, (unsigned long)bucketCount);
        }
        
        while (bucketIndex < bucketCount) {
            CGFloat bucketHeight = [self.dataSource bucketValue:bucketIndex] * insetRect.size.height;
            if (bucketHeight > 0.0) { // draw it, otherwise just skip ahead
                CGFloat bucketXOffset = insetRect.origin.x + (bucketWidth * bucketIndex);
                CGFloat bucketYOffset = insetRect.origin.y + (insetRect.size.height - bucketHeight);
                CGFloat gap = MIN(MAX(self.barGap, 0), bucketWidth / 2); // half on each side, so the outer bars line up with the edges
                CGRect bucketRect = CGRectMake(bucketXOffset + (bucketIndex > 0 ? gap / 2 : 0), bucketYOffset,
                                               bucketWidth - (bucketIndex > 0 ? gap / 2 : 0) - (bucketIndex < bucketCount - 1 ? gap / 2 : 0), bucketHeight);
                CAShapeLayer* bucketLayer = [CAShapeLayer new];
                CGPathRef bucketPath = CGPathCreateWithRect(bucketRect, nil);
                bucketLayer.path = bucketPath;
                bucketLayer.fillColor = self.style.fill.CGColor;
                bucketLayer.strokeColor = self.style.stroke.CGColor;
                [self.barsLayer addSublayer:bucketLayer];
                CGPathRelease(bucketPath);
            }
            bucketIndex++;
        }
    }
    else {
        NSLog(@"no bucket data");
    }

    [super updateView];
    [CATransaction commit];
}

// MARK: - ILBucketDataDelegate

- (void) bucketDataDidUpdate:(ILBucketData*) data {
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [self updateView];
    }];
}

@end
