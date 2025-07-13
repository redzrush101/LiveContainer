#import "DecoratedAppSceneViewController.h"
#import "ResizeHandleView.h"
#import "LiveContainerSwiftUI-Swift.h"
#import "AppSceneViewController.h"
#import "UIKitPrivate+MultitaskSupport.h"
#import "PiPManager.h"
#import "../LiveContainer/Localization.h"
#import "utils.h"

@implementation RBSTarget(hook)
+ (instancetype)hook_targetWithPid:(pid_t)pid environmentIdentifier:(NSString *)environmentIdentifier {
    if([environmentIdentifier containsString:@"LiveProcess"]) {
        environmentIdentifier = [NSString stringWithFormat:@"LiveProcess:%d", pid];
    }
    return [self hook_targetWithPid:pid environmentIdentifier:environmentIdentifier];
}
@end
static int hook_return_2(void) {
    return 2;
}
__attribute__((constructor))
void UIKitFixesInit(void) {
    // Fix _UIPrototypingMenuSlider not continually updating its value on iOS 17+
    Class _UIFluidSliderInteraction = objc_getClass("_UIFluidSliderInteraction");
    if(_UIFluidSliderInteraction) {
        method_setImplementation(class_getInstanceMethod(_UIFluidSliderInteraction, @selector(_state)), (IMP)hook_return_2);
    }
    // Fix physical keyboard focus on iOS 17+
    if(@available(iOS 17.0, *)) {
        method_exchangeImplementations(class_getClassMethod(RBSTarget.class, @selector(targetWithPid:environmentIdentifier:)), class_getClassMethod(RBSTarget.class, @selector(hook_targetWithPid:environmentIdentifier:)));
    }
}

@interface DecoratedAppSceneViewController()
@property(nonatomic) DecoratedFloatingView* rootView;
@property(nonatomic) AppSceneViewController* appSceneVC;
@property(nonatomic) ResizeHandleView* resizeHandle;
@property(nonatomic) NSArray* activatedVerticalConstraints;
@property(nonatomic) NSString *sceneID;
@property(nonatomic) NSString* dataUUID;
@property(nonatomic) NSString* windowName;
@property(nonatomic) int pid;
@property(nonatomic) CGRect originalFrame;
@property(nonatomic) UIBarButtonItem *maximizeButton;
@property(nonatomic) bool isAppTerminationRequested;
@end

@implementation DecoratedAppSceneViewController
- (instancetype)initWindowName:(NSString*)windowName bundleId:(NSString*)bundleId dataUUID:(NSString*)dataUUID error:(NSError**)error {
    self = [super initWithNibName:nil bundle:nil];
    
    if(UIInterfaceOrientationIsLandscape(UIApplication.sharedApplication.statusBarOrientation)) {
        _rootView = [[DecoratedFloatingView alloc] initWithFrame:CGRectMake(50, 150, 480, 320 + 44)];
    } else {
        _rootView = [[DecoratedFloatingView alloc] initWithFrame:CGRectMake(50, 150, 320, 480 + 44)];
    }
    
    _rootView.axis = UILayoutConstraintAxisVertical;
    _rootView.backgroundColor = UIColor.systemBackgroundColor;
    _rootView.layer.cornerRadius = 10;
    _rootView.layer.masksToBounds = YES;
    
    
    _appSceneVC = [[AppSceneViewController alloc] initWithBundleId:bundleId dataUUID:dataUUID delegate:self error:error];
    
    if(*error) {
        return nil;
    }
    MultitaskDockManager *dock = [MultitaskDockManager shared];
    [dock addRunningApp:windowName appUUID:dataUUID view:_rootView];
    
    self.dataUUID = dataUUID;
    self.scaleRatio = 1.0;
    self.isMaximized = NO;
    self.originalFrame = CGRectZero;
    self.pid = _appSceneVC.pid;
    
    NSArray *menuItems = @[
        [UIAction actionWithTitle:@"lc.multitask.copyPid".loc image:[UIImage systemImageNamed:@"doc.on.doc"] identifier:nil handler:^(UIAction * _Nonnull action) {
            UIPasteboard.generalPasteboard.string = @(self.appSceneVC.pid).stringValue;
        }],
        [UIAction actionWithTitle:@"lc.multitask.enablePip".loc image:[UIImage systemImageNamed:@"pip.enter"] identifier:nil handler:^(UIAction * _Nonnull action) {
            if ([PiPManager.shared isPiPWithVC:self.appSceneVC]) {
                [PiPManager.shared stopPiP];
            } else {
                [PiPManager.shared startPiPWithVC:self.appSceneVC];
            }
        }],
        [UICustomViewMenuElement elementWithViewProvider:^UIView *(UICustomViewMenuElement *element) {
            return [self scaleSliderViewWithTitle:@"lc.multitask.scale".loc min:0.5 max:2.0 value:self.scaleRatio stepInterval:0.01];
        }]
    ];
    
    NSString *pidText = [NSString stringWithFormat:@"PID: %d", _pid];
    __weak typeof(self) weakSelf = self;
    [_rootView.navigationItem setTitleMenuProvider:^UIMenu *(NSArray<UIMenuElement *> *suggestedActions){
        if(!weakSelf.appSceneVC.isAppRunning) {
            return [UIMenu menuWithTitle:NSLocalizedString(@"lc.multitaskAppWindow.appTerminated", nil) children:@[]];
        } else {
            return [UIMenu menuWithTitle:pidText children:menuItems];
        }
    }];
    
    UIImage *minimizeImage = [UIImage systemImageNamed:@"minus.circle"];
    UIImageConfiguration *minimizeConfig = [UIImageSymbolConfiguration configurationWithPointSize:16.0 weight:UIImageSymbolWeightMedium];
    minimizeImage = [minimizeImage imageWithConfiguration:minimizeConfig];
    UIBarButtonItem *minimizeButton = [[UIBarButtonItem alloc] initWithImage:minimizeImage style:UIBarButtonItemStylePlain target:self action:@selector(minimizeWindow)];
    minimizeButton.tintColor = [UIColor systemYellowColor];
    
    UIImage *maximizeImage = [UIImage systemImageNamed:@"arrow.up.left.and.arrow.down.right.circle"];
    UIImageConfiguration *maximizeConfig = [UIImageSymbolConfiguration configurationWithPointSize:16.0 weight:UIImageSymbolWeightMedium];
    maximizeImage = [maximizeImage imageWithConfiguration:maximizeConfig];
    self.maximizeButton = [[UIBarButtonItem alloc] initWithImage:maximizeImage style:UIBarButtonItemStylePlain target:self action:@selector(maximizeWindow)];
    self.maximizeButton.tintColor = [UIColor systemGreenColor];
    
    UIImage *closeImage = [UIImage systemImageNamed:@"xmark.circle"];
    UIImageConfiguration *closeConfig = [UIImageSymbolConfiguration configurationWithPointSize:16.0 weight:UIImageSymbolWeightMedium];
    closeImage = [closeImage imageWithConfiguration:closeConfig];
    UIBarButtonItem *closeButton = [[UIBarButtonItem alloc] initWithImage:closeImage style:UIBarButtonItemStylePlain target:self action:@selector(closeWindow)];
    closeButton.tintColor = [UIColor systemRedColor];
    
    NSArray *barButtonItems = @[closeButton, self.maximizeButton, minimizeButton];
    if([NSUserDefaults.lcSharedDefaults boolForKey:@"LCMultitaskBottomWindowBar"]) {
        // resize handle overlaps the close button, so put the buttons on the left
        _rootView.navigationItem.leftBarButtonItems = barButtonItems;
    } else {
        _rootView.navigationItem.rightBarButtonItems = barButtonItems;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self adjustNavigationBarButtonSpacingWithNegativeSpacing:-8.0 rightMargin:-4.0];
    });
    
    self.windowName = windowName;
    _rootView.navigationItem.title = windowName;

    return self;
}

- (void) loadView {
    self.view = _rootView;

    [self addChildViewController:_appSceneVC];

    [self.view insertSubview:_appSceneVC.view atIndex:0];
    _appSceneVC.view.translatesAutoresizingMaskIntoConstraints = NO;
    
    
    
    if([NSUserDefaults.lcSharedDefaults boolForKey:@"LCMultitaskBottomWindowBar"]) {
        _activatedVerticalConstraints = @[
            [_appSceneVC.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
            [_appSceneVC.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-44],
        ];
    } else {
        _activatedVerticalConstraints = @[
            [_appSceneVC.view.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:44],
            [_appSceneVC.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        ];
    }
    [NSLayoutConstraint activateConstraints:_activatedVerticalConstraints];
    [NSLayoutConstraint activateConstraints:@[
        [_appSceneVC.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_appSceneVC.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]
    ]];
    
    
    NSUserDefaults *defaults = NSUserDefaults.lcSharedDefaults;

    [defaults addObserver:self forKeyPath:@"LCMultitaskBottomWindowBar" options:NSKeyValueObservingOptionNew context:NULL];
    
}


// Stolen from UIKitester
- (UIView *)scaleSliderViewWithTitle:(NSString *)title min:(CGFloat)minValue max:(CGFloat)maxValue value:(CGFloat)initialValue stepInterval:(CGFloat)step {
    UIView *containerView = [[UIView alloc] init];
    containerView.translatesAutoresizingMaskIntoConstraints = NO;
    containerView.exclusiveTouch = YES;

    UIStackView *stackView = [[UIStackView alloc] init];
    stackView.axis = UILayoutConstraintAxisVertical;
    stackView.spacing = 0.0;
    stackView.translatesAutoresizingMaskIntoConstraints = NO;
    [containerView addSubview:stackView];
    
    [NSLayoutConstraint activateConstraints:@[
        [stackView.topAnchor constraintEqualToAnchor:containerView.topAnchor constant:10.0],
        [stackView.bottomAnchor constraintEqualToAnchor:containerView.bottomAnchor constant:-8.0],
        [stackView.leadingAnchor constraintEqualToAnchor:containerView.leadingAnchor constant:16.0],
        [stackView.trailingAnchor constraintEqualToAnchor:containerView.trailingAnchor constant:-16.0]
    ]];
    
    UILabel *label = [[UILabel alloc] init];
    label.text = title;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [UIFont boldSystemFontOfSize:12.0];
    [stackView addArrangedSubview:label];
    
    _UIPrototypingMenuSlider *slider = [[_UIPrototypingMenuSlider alloc] init];
    slider.minimumValue = minValue;
    slider.maximumValue = maxValue;
    slider.value = initialValue;
    slider.stepSize = step;
    
    NSLayoutConstraint *sliderHeight = [slider.heightAnchor constraintEqualToConstant:40.0];
    sliderHeight.active = YES;
    
    [stackView addArrangedSubview:slider];
    
    [slider addTarget:self action:@selector(scaleSliderChanged:) forControlEvents:UIControlEventValueChanged];
    
    return containerView;
}

- (void)scaleSliderChanged:(_UIPrototypingMenuSlider *)slider {
    self.scaleRatio = slider.value;
    [_appSceneVC setScale:slider.value];
}

- (void)closeWindow {
    _isAppTerminationRequested = true;
    if([_appSceneVC isAppRunning]) {
        [_appSceneVC terminate];
    } else {
        [self appDidExit];
    }
}

- (void)minimizeWindow {
    [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        self.view.alpha = 0;
        self.view.transform = CGAffineTransformMakeScale(0.1, 0.1);
    } completion:^(BOOL finished) {
        self.view.hidden = YES;
        self.view.transform = CGAffineTransformIdentity;
    }];
}

- (void)maximizeWindow {
    UIEdgeInsets safeAreaInsets = self.view.window.safeAreaInsets;
    CGRect maxFrame = UIEdgeInsetsInsetRect(self.view.window.frame, safeAreaInsets);
    
    if (self.isMaximized) {
        CGRect newFrame = CGRectMake(self.originalFrame.origin.x * maxFrame.size.width, self.originalFrame.origin.y * maxFrame.size.height, self.originalFrame.size.width, self.originalFrame.size.height);
        [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
            self.view.frame = newFrame;
        } completion:^(BOOL finished) {
            self.isMaximized = NO;
            UIImage *maximizeImage = [UIImage systemImageNamed:@"arrow.up.left.and.arrow.down.right.circle"];
            UIImageConfiguration *maximizeConfig = [UIImageSymbolConfiguration configurationWithPointSize:16.0 weight:UIImageSymbolWeightMedium];
            self.maximizeButton.image = [maximizeImage imageWithConfiguration:maximizeConfig];
            self.view.frame = newFrame;
        }];
    } else {
        // save origin as normalized coordinates
        self.originalFrame = CGRectMake(self.view.frame.origin.x / maxFrame.size.width, self.view.frame.origin.y / maxFrame.size.height, self.view.frame.size.width, self.view.frame.size.height);
        [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
            self.view.frame = maxFrame;
        } completion:^(BOOL finished) {
            self.isMaximized = YES;
            UIImage *restoreImage = [UIImage systemImageNamed:@"arrow.down.right.and.arrow.up.left.circle"];
            UIImageConfiguration *restoreConfig = [UIImageSymbolConfiguration configurationWithPointSize:16.0 weight:UIImageSymbolWeightMedium];
            self.maximizeButton.image = [restoreImage imageWithConfiguration:restoreConfig];
            //                             [self.appSceneView resizeWindowWithFrame:CGRectMake(0, 0, size.width / self.scaleRatio, size.height / self.scaleRatio)];
            self.view.frame = maxFrame;
        }];
    }
}

- (void)appDidExit {
    if(_isAppTerminationRequested) {
        
        MultitaskDockManager *dock = [MultitaskDockManager shared];
        [dock removeRunningApp:self.dataUUID];
        
        self.view.layer.masksToBounds = NO;
        [UIView transitionWithView:self.view duration:0.4 options:UIViewAnimationOptionTransitionCurlUp animations:^{
            self.view.hidden = YES;
        } completion:^(BOOL b){
            [self.view removeFromSuperview];
        }];
    } else {
        UILabel *label = [[UILabel alloc] initWithFrame:self.view.bounds];
        label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        label.lineBreakMode = NSLineBreakByWordWrapping;
        label.numberOfLines = 0;
        label.text = NSLocalizedString(@"lc.multitaskAppWindow.appTerminated", @"");
        label.textAlignment = NSTextAlignmentCenter;
        [self.appSceneVC.view addSubview:label];
    }
}

- (void)adjustNavigationBarButtonSpacingWithNegativeSpacing:(CGFloat)spacing rightMargin:(CGFloat)margin {
    if (![(DecoratedFloatingView*)self.view navigationBar]) return;
    
    [self findAndAdjustButtonBarStackView:[(DecoratedFloatingView*)self.view navigationBar] withSpacing:spacing rightMargin:margin];
}

- (void)findAndAdjustButtonBarStackView:(UIView *)view withSpacing:(CGFloat)spacing rightMargin:(CGFloat)margin {
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:NSClassFromString(@"_UIButtonBarStackView")]) {
            if ([subview respondsToSelector:@selector(setSpacing:)]) {
                [(_UIButtonBarStackView *)subview setSpacing:spacing];
            }
            
            if (subview.superview) {
                for (NSLayoutConstraint *constraint in subview.superview.constraints) {
                    if ((constraint.firstItem == subview && constraint.firstAttribute == NSLayoutAttributeTrailing) ||
                        (constraint.secondItem == subview && constraint.secondAttribute == NSLayoutAttributeTrailing)) {
                        constraint.constant = (constraint.firstItem == subview) ? -margin : margin;
                        break;
                    }
                }
                
                [subview setNeedsLayout];
                [subview.superview setNeedsLayout];
            }
            
            return;
        }
        
        [self findAndAdjustButtonBarStackView:subview withSpacing:spacing rightMargin:margin];
    }
}


- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    BOOL bottomWindowBar = [change[NSKeyValueChangeNewKey] boolValue];
    [UIView animateWithDuration:0.3 animations:^{
        DecoratedFloatingView* rootView = (DecoratedFloatingView*)self.view;
        if(bottomWindowBar) {
            rootView.navigationItem.leftBarButtonItems = rootView.navigationItem.rightBarButtonItems;
            rootView.navigationItem.rightBarButtonItems = nil;
            [rootView addArrangedSubview:rootView.navigationBar];
        } else {
            rootView.navigationItem.rightBarButtonItems = rootView.navigationItem.leftBarButtonItems;
            rootView.navigationItem.leftBarButtonItems = nil;
            [rootView insertArrangedSubview:rootView.navigationBar atIndex:0];
        }
        
        [NSLayoutConstraint deactivateConstraints:self.activatedVerticalConstraints];
        if(bottomWindowBar) {
            self.activatedVerticalConstraints = @[
                [self.appSceneVC.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
                [self.appSceneVC.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-44],
            ];
        } else {
            self.activatedVerticalConstraints = @[
                [self.appSceneVC.view.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:44],
                [self.appSceneVC.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
            ];
        }
        [NSLayoutConstraint activateConstraints:self.activatedVerticalConstraints];
        
        [self adjustNavigationBarButtonSpacingWithNegativeSpacing:-8.0 rightMargin:-4.0];
    }];
}

- (void)moveWindow:(UIPanGestureRecognizer*)sender {
    CGPoint point = [sender translationInView:self.view];
    [sender setTranslation:CGPointZero inView:self.view];

    self.view.center = CGPointMake(self.view.center.x + point.x, self.view.center.y + point.y);
}

- (void)resizeWindow:(UIPanGestureRecognizer*)sender {
    CGPoint point = [sender translationInView:self.view];
    [sender setTranslation:CGPointZero inView:self.view];

    CGRect frame = self.view.frame;
    frame.size.width = MAX(50, frame.size.width + point.x);
    frame.size.height = MAX(50, frame.size.height + point.y);
    self.view.frame = frame;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    // FIXME: how to bring view to front when touching the passthrough view?
    [self.view.superview bringSubviewToFront:self.view];
}

@end
