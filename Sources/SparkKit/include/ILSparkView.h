#if __has_include(<SparkKit/SparkKit.h>)
#import <SparkKit/ILSparkStyle.h>
#else
#import "ILSparkStyle.h"
#endif

/// base class for all SparkKit views
@interface ILSparkView : ILView <ILViewLifecycle, ILSparkStyle>

// MARK: - ILSparkStyle

/// view style
@property(nonatomic, retain) ILSparkStyle* style;

/// border layer
@property(nonatomic, readonly) CAShapeLayer* border;

/// is the bortder circular?
@property(nonatomic, readonly) BOOL isCircular;

/// inset of border rectangle, effective drawable area
@property(nonatomic, readonly) CGRect borderInset;

// MARK: - Labels

@property(nonatomic, retain) NSArray* yAxisLabels;
@property(nonatomic, retain) NSString* yAxisUnits;
@property(nonatomic, assign) BOOL yAxisLabelsCenteredOnRows;
@property(nonatomic, retain) NSArray* xAxisLabels;
@property(nonatomic, retain) NSString* xAxisUnits;
@property(nonatomic, assign) BOOL xAxisLabelsCenteredOnColumns;
@property(nonatomic, retain) NSString* errorString;

@end
