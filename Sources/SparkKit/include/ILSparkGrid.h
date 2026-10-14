#import <QuartzCore/QuartzCore.h>


#if __has_include(<KitBridge/KitBridge.h>)
#import <KitBridge/KitBridge.h>
#else
@import SparkKit;
#endif

#if __has_include(<SparkKit/SparkKit.h>)
#import <SparkKit/ILGridData.h>
#import <SparkKit/ILSparkView.h>
#else
#import "ILGridData.h"
#import "ILSparkView.h"
#endif

@class ILSparkStyle;


@interface ILSparkGrid : ILSparkView <ILViewLifecycle, ILGridDataDelegate>

@property(nonatomic, retain) ILGridData* grid;
@property(nonatomic, assign) NSRange valueRange;

@end
