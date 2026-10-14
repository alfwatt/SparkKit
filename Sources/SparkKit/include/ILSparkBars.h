#if __has_include(<SparkKit/SparkKit.h>)
#import <SparkKit/ILSparkView.h>
#import <SparkKit/ILBucketData.h>
#else
#import "ILSparkView.h"
#import "ILBucketData.h"
#endif

/// ILSparkBuckegts is a view for showing ILBucketData
@interface ILSparkBars : ILSparkView <ILBucketDataDelegate>
@property(nonatomic,retain) ILBucketData* dataSource;

@end
