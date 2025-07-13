//
//  AppSceneView.m
//  LiveContainer
//
//  Created by s s on 2025/5/17.
//
#import "AppSceneViewController.h"
#import "DecoratedAppSceneViewController.h"
#import "LiveContainerSwiftUI-Swift.h"
#import "../LiveContainerSwiftUI/LCUtils.h"
#import "PiPManager.h"

@interface AppSceneViewController()
@property int resizeDebounceToken;
@property CGRect currentFrame;
@property CGPoint normalizedOrigin;
@property bool isNativeWindow;
@property NSUUID* identifier;
@end

@interface AppSceneViewController()
@property(nonatomic) UIWindowScene *hostScene;
@property(nonatomic) _UIScenePresenter *presenter;
@property(nonatomic) UIMutableApplicationSceneSettings *settings;
@property(nonatomic) NSString *sceneID;
@property(nonatomic) NSExtension* extension;
@property(nonatomic) bool isAppTerminationCleanUpCalled;
@end

@implementation AppSceneViewController


- (instancetype)initWithBundleId:(NSString*)bundleId dataUUID:(NSString*)dataUUID delegate:(id<AppSceneViewDelegate>)delegate error:(NSError**)error {
    self = [super initWithNibName:nil bundle:nil];
    self.view = [[UIView alloc] init];
    self.contentView = [[UIView alloc] init];
    [self.view addSubview:_contentView];
    self.delegate = delegate;
    self.dataUUID = dataUUID;
    self.bundleId = bundleId;
    self.scaleRatio = 1.0;
    self.isAppTerminationCleanUpCalled = false;
    // init extension
    NSBundle *liveProcessBundle = [NSBundle bundleWithPath:[NSBundle.mainBundle.builtInPlugInsPath stringByAppendingPathComponent:@"LiveProcess.appex"]];
    if(!liveProcessBundle) {
        *error = [NSError errorWithDomain:@"LiveProcess" code:2 userInfo:@{NSLocalizedDescriptionKey: @"LiveProcess extension not found. Please reinstall LiveContainer and select Keep Extensions"}];
        return nil;
    }
    
    _extension = [NSExtension extensionWithIdentifier:liveProcessBundle.bundleIdentifier error:error];
    if(*error) {
        return nil;
    }

    NSExtensionItem *item = [NSExtensionItem new];
    item.userInfo = @{
        @"selected": _bundleId,
        @"selectedContainer": _dataUUID
    };
    
    dispatch_semaphore_t s = dispatch_semaphore_create(0);
    [_extension beginExtensionRequestWithInputItems:@[item] completion:^(NSUUID *identifier) {
        [MultitaskManager registerMultitaskContainerWithContainer:self.dataUUID];
        if(identifier) {
            self.identifier = identifier;
        } else {
            *error = [NSError errorWithDomain:@"LiveProcess" code:2 userInfo:@{NSLocalizedDescriptionKey: @"Failed to start app. Child process has unexpectedly crashed"}];
            dispatch_semaphore_signal(s);
            return;
        }
        
        dispatch_semaphore_signal(s);
    }];
    dispatch_semaphore_wait(s, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC));
    if(!self.identifier) {
        return nil;
    }
    self.pid = [self.extension pidForRequestIdentifier:self.identifier];
    _isNativeWindow = [[[NSUserDefaults alloc] initWithSuiteName:[LCUtils appGroupID]] integerForKey:@"LCMultitaskMode" ] == 1;

    return self;
}

- (void)viewWillAppear:(BOOL)animated {
    _currentFrame = self.view.frame;

    RBSProcessPredicate* predicate = [PrivClass(RBSProcessPredicate) predicateMatchingIdentifier:@(self.pid)];
    
    FBProcessManager *manager = [PrivClass(FBProcessManager) sharedInstance];
    // At this point, the process is spawned and we're ready to create a scene to render in our app
    RBSProcessHandle* processHandle = [PrivClass(RBSProcessHandle) handleForPredicate:predicate error:nil];
    [manager registerProcessForAuditToken:processHandle.auditToken];
    // NSString *identifier = [NSString stringWithFormat:@"sceneID:%@-%@", bundleID, @"default"];
    self.sceneID = [NSString stringWithFormat:@"sceneID:%@-%@", @"LiveProcess", NSUUID.UUID.UUIDString];
    
    FBSMutableSceneDefinition *definition = [PrivClass(FBSMutableSceneDefinition) definition];
    definition.identity = [PrivClass(FBSSceneIdentity) identityForIdentifier:self.sceneID];
    definition.clientIdentity = [PrivClass(FBSSceneClientIdentity) identityForProcessIdentity:processHandle.identity];
    definition.specification = [UIApplicationSceneSpecification specification];
    FBSMutableSceneParameters *parameters = [PrivClass(FBSMutableSceneParameters) parametersForSpecification:definition.specification];
    
    UIMutableApplicationSceneSettings *settings = [UIMutableApplicationSceneSettings new];
    settings.canShowAlerts = YES;
    settings.cornerRadiusConfiguration = [[PrivClass(BSCornerRadiusConfiguration) alloc] initWithTopLeft:self.view.layer.cornerRadius bottomLeft:self.view.layer.cornerRadius bottomRight:self.view.layer.cornerRadius topRight:self.view.layer.cornerRadius];
    settings.displayConfiguration = UIScreen.mainScreen.displayConfiguration;
    settings.foreground = YES;

    settings.deviceOrientation = UIDevice.currentDevice.orientation;
    settings.interfaceOrientation = UIApplication.sharedApplication.statusBarOrientation;
    if(UIInterfaceOrientationIsLandscape(settings.interfaceOrientation)) {
        settings.frame = CGRectMake(0, 0, self.view.frame.size.height, self.view.frame.size.width);
    } else {
        settings.frame = CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height);
    }
    //settings.interruptionPolicy = 2; // reconnect
    settings.level = 1;
    settings.persistenceIdentifier = NSUUID.UUID.UUIDString;
    if(self.isNativeWindow) {
        UIEdgeInsets defaultInsets = UIApplication.sharedApplication.keyWindow.safeAreaInsets;
        settings.peripheryInsets = defaultInsets;
        settings.safeAreaInsetsPortrait = defaultInsets;
    } else {
        // it seems some apps don't honor these settings so we don't cover the top of the app
        settings.peripheryInsets = UIEdgeInsetsMake(0, 0, 0, 0);
        settings.safeAreaInsetsPortrait = UIEdgeInsetsMake(0, 0, 0, 0);
    }


    settings.statusBarDisabled = !self.isNativeWindow;
    //settings.previewMaximumSize =
    //settings.deviceOrientationEventsEnabled = YES;
    self.settings = settings;
    parameters.settings = settings;
    
    UIMutableApplicationSceneClientSettings *clientSettings = [UIMutableApplicationSceneClientSettings new];
    clientSettings.interfaceOrientation = UIInterfaceOrientationPortrait;
    clientSettings.statusBarStyle = 0;
    parameters.clientSettings = clientSettings;
    
    FBScene *scene = [[PrivClass(FBSceneManager) sharedInstance] createSceneWithDefinition:definition initialParameters:parameters];
    
    self.presenter = [scene.uiPresentationManager createPresenterWithIdentifier:self.sceneID];
    [self.presenter modifyPresentationContext:^(UIMutableScenePresentationContext *context) {
        context.appearanceStyle = 2;
    }];
    [self.presenter activate];
    
    __weak typeof(self) weakSelf = self;
    [self.extension setRequestInterruptionBlock:^(NSUUID *uuid) {
        [weakSelf appTerminationCleanUp];
    }];
    
    [self.contentView addSubview:self.presenter.presentationView];
    self.contentView.layer.anchorPoint = CGPointMake(0, 0);
    self.contentView.layer.position = CGPointMake(0, 0);
    
    [self.view.window.windowScene _registerSettingsDiffActionArray:@[self] forKey:self.sceneID];
}

- (void)terminate {
    if(self.isAppRunning) {
        [self.extension _kill:SIGTERM];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.extension _kill:SIGKILL];
        });
    }    
}

- (void)setScale:(float)scale {
    self.scaleRatio = scale;
    self.contentView.layer.sublayerTransform = CATransform3DMakeScale(scale, scale, 1.0);
    [self viewWillLayoutSubviews];
}

- (void)_performActionsForUIScene:(UIScene *)scene withUpdatedFBSScene:(id)fbsScene settingsDiff:(FBSSceneSettingsDiff *)diff fromSettings:(UIApplicationSceneSettings *)settings transitionContext:(id)context lifecycleActionType:(uint32_t)actionType {
    if(!self.isAppRunning) {
        [self appTerminationCleanUp];
    }
    if(!diff) return;
    
    UIMutableApplicationSceneSettings *baseSettings = [diff settingsByApplyingToMutableCopyOfSettings:settings];
    UIApplicationSceneTransitionContext *newContext = [context copy];
    newContext.actions = nil;
    if(self.isNativeWindow) {
        // directly update the settings
        baseSettings.interruptionPolicy = 0;
        baseSettings.safeAreaInsetsPortrait = self.view.window.safeAreaInsets;
        baseSettings.peripheryInsets = self.view.window.safeAreaInsets;
        [self.presenter.scene updateSettings:baseSettings withTransitionContext:newContext completion:nil];
    } else {
        UIMutableApplicationSceneSettings *newSettings = [self.presenter.scene.settings mutableCopy];
        newSettings.userInterfaceStyle = baseSettings.userInterfaceStyle;
        newSettings.interfaceOrientation = baseSettings.interfaceOrientation;
        newSettings.deviceOrientation = baseSettings.deviceOrientation;
        newSettings.foreground = YES;
        
//        DecoratedAppSceneView *sceneView = (id)self.delegate;
//        UIEdgeInsets safeAreaInsets = self.view.window.safeAreaInsets;
//        CGRect maxFrame = UIEdgeInsetsInsetRect(self.view.window.frame, safeAreaInsets);
//        CGRect newFrame = self.currentFrame;
//        if(sceneView.isMaximized) {
//            sceneView.frame = maxFrame;
//        } else {
//            CGPoint center = sceneView.center;
//            CGRect frame = CGRectZero;
//            frame.size.width = MIN(self.currentFrame.size.width*sceneView.scaleRatio, maxFrame.size.width);
//            frame.size.height = MIN(self.currentFrame.size.height*sceneView.scaleRatio + sceneView.navigationBar.frame.size.height, maxFrame.size.height);
//            CGFloat oobOffset = MAX(30, frame.size.width - 30);
//            frame.origin.x = MAX(maxFrame.origin.x - oobOffset, MIN(CGRectGetMaxX(maxFrame) - frame.size.width + oobOffset, center.x - frame.size.width / 2));
//            frame.origin.y = MAX(maxFrame.origin.y, MIN(center.y - frame.size.height / 2, CGRectGetMaxY(maxFrame) - frame.size.height));
//            [UIView animateWithDuration:0.3 animations:^{
//                sceneView.frame = frame;
//            }];
//        }
//        newFrame = CGRectMake(0, 0, sceneView.frame.size.width/sceneView.scaleRatio, (sceneView.frame.size.height - sceneView.navigationBar.frame.size.height)/sceneView.scaleRatio);
//        
//        if(UIInterfaceOrientationIsLandscape(baseSettings.interfaceOrientation)) {
//            newSettings.frame = CGRectMake(0, 0, newFrame.size.height, newFrame.size.width);
//        } else {
//            newSettings.frame = CGRectMake(0, 0, newFrame.size.width, newFrame.size.height);
//        }
        [self.presenter.scene updateSettings:newSettings withTransitionContext:newContext completion:nil];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

}


- (void)viewWillLayoutSubviews {
    __block int currentDebounceToken = self.resizeDebounceToken + 1;
    _resizeDebounceToken = currentDebounceToken;
    dispatch_time_t delay = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC));
    dispatch_after(delay, dispatch_get_main_queue(), ^{
        if(currentDebounceToken != self.resizeDebounceToken) {
            return;
        }
        CGRect frame = CGRectMake(self.view.frame.origin.x, self.view.frame.origin.y, self.view.frame.size.width / self.scaleRatio, self.view.frame.size.height / self.scaleRatio);
        self.currentFrame = frame;
        [self.presenter.scene updateSettingsWithBlock:^(UIMutableApplicationSceneSettings *settings) {
            settings.deviceOrientation = UIDevice.currentDevice.orientation;
            settings.interfaceOrientation = self.view.window.windowScene.interfaceOrientation;
            if(UIInterfaceOrientationIsLandscape(settings.interfaceOrientation)) {
                CGRect frame2 = CGRectMake(frame.origin.x, frame.origin.y, frame.size.height, frame.size.width);
                settings.frame = frame2;
            } else {
                settings.frame = frame;
            }
        }];
    });
}

- (BOOL)isAppRunning {
    return _pid > 0 && getpgid(_pid) > 0;
}

- (void)appTerminationCleanUp {
    if(_isAppTerminationCleanUpCalled) {
        return;
    }
    _isAppTerminationCleanUpCalled = true;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.view.window.windowScene _unregisterSettingsDiffActionArrayForKey:self.sceneID];
        [[PrivClass(FBSceneManager) sharedInstance] destroyScene:self.sceneID withTransitionContext:nil];
        if(self.presenter){
            [self.presenter deactivate];
            [self.presenter invalidate];
            self.presenter = nil;
        }
        
        [self.delegate appDidExit];
        self.delegate = nil;
        [MultitaskManager unregisterMultitaskContainerWithContainer:self.dataUUID];
    });
}

- (void)setBackgroundNotificationEnabled:(bool)enabled {
    if(enabled) {
        // Re-add UIApplicationDidEnterBackgroundNotification
        [NSNotificationCenter.defaultCenter addObserver:self.extension selector:@selector(_hostDidEnterBackgroundNote:) name:UIApplicationDidEnterBackgroundNotification object:UIApplication.sharedApplication];
    } else {
        // Remove UIApplicationDidEnterBackgroundNotification so apps like YouTube can continue playing video
        [NSNotificationCenter.defaultCenter removeObserver:self.extension name:UIApplicationDidEnterBackgroundNotification object:UIApplication.sharedApplication];
    }
}

@end
 
