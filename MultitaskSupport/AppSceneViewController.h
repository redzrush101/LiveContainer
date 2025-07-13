//
//  AppSceneView.h
//  LiveContainer
//
//  Created by s s on 2025/5/17.
//
#import "UIKitPrivate+MultitaskSupport.h"
#import "FoundationPrivate.h"
@import UIKit;
@import Foundation;

@protocol AppSceneViewDelegate <NSObject>
- (void)appDidExit;
@end

API_AVAILABLE(ios(16.0))
@interface AppSceneViewController : UIViewController<_UISceneSettingsDiffAction>

@property(nonatomic) NSString* bundleId;
@property(nonatomic) NSString* dataUUID;
@property(nonatomic) int pid;
@property(nonatomic) id<AppSceneViewDelegate> delegate;
@property(nonatomic) BOOL isAppRunning;
@property(nonatomic) CGFloat scaleRatio;
@property(nonatomic) UIView* contentView;

- (instancetype)initWithBundleId:(NSString*)bundleId dataUUID:(NSString*)dataUUID delegate:(id<AppSceneViewDelegate>)delegate error:(NSError**)error;
- (void)setScale:(float)scale;
- (void)terminate;
- (void)setBackgroundNotificationEnabled:(bool)enabled;
@end

