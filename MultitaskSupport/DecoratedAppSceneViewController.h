#import "FoundationPrivate.h"
#import "DecoratedFloatingView.h"
#import "AppSceneViewController.h"

API_AVAILABLE(ios(16.0))
@interface DecoratedAppSceneViewController : UIViewController<AppSceneViewControllerDelegate>
@property(nonatomic) BOOL isMaximized;
@property(nonatomic) CGFloat scaleRatio;
- (instancetype)initWindowName:(NSString*)windowName bundleId:(NSString*)bundleId dataUUID:(NSString*)dataUUID;
@end

