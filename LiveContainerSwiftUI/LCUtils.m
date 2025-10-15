@import Darwin;
@import MachO;
@import UIKit;
@import UniformTypeIdentifiers;

#import "LCUtils.h"
#import "LCAppInfo.h"
#import "../MultitaskSupport/DecoratedAppSceneViewController.h"
#import "../ZSign/zsigner.h"
#import "LiveContainerSwiftUI-Swift.h"

Class LCSharedUtilsClass = nil;

static NSString *const LCMultitaskErrorDomain = @"com.kdt.livecontainer.multitask";

typedef NS_ENUM(NSInteger, LCMultitaskErrorCode) {
    LCMultitaskErrorCodeMissingExtension = 1,
    LCMultitaskErrorCodeMissingSelection = 2,
    LCMultitaskErrorCodeMissingContainer = 3,
    LCMultitaskErrorCodeNoActiveWindow = 4,
};

static NSError *LCMultitaskError(NSString *displayName, LCMultitaskErrorCode code, NSString *message) {
    NSMutableDictionary *userInfo = [@{NSLocalizedDescriptionKey : message ?: @"Unknown error"} mutableCopy];
    if (displayName) {
        userInfo[@"LCDisplayName"] = displayName;
    }
    return [NSError errorWithDomain:LCMultitaskErrorDomain code:code userInfo:userInfo];
}

static BOOL LCMultitaskFetchSelection(NSString *displayName, NSString **bundleId, NSString **dataUUID, NSError **error) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *selectedBundleId = [defaults stringForKey:@"selected"];
    NSString *selectedContainer = [defaults stringForKey:@"selectedContainer"];

    if (!selectedBundleId || !selectedContainer) {
        if (error) {
            NSString *message;
            if (!selectedBundleId && !selectedContainer) {
                message = NSLocalizedString(@"Unable to determine the selected app for multitasking. Please choose an app and try again.", nil);
            } else if (!selectedBundleId) {
                message = NSLocalizedString(@"Missing bundle identifier for the selected multitask app.", nil);
            } else {
                message = NSLocalizedString(@"Missing selected container for the multitask app.", nil);
            }
            *error = LCMultitaskError(displayName, !selectedBundleId ? LCMultitaskErrorCodeMissingSelection : LCMultitaskErrorCodeMissingContainer, message);
        }
        return NO;
    }

    if (bundleId) {
        *bundleId = selectedBundleId;
    }
    if (dataUUID) {
        *dataUUID = selectedContainer;
    }
    return YES;
}

static void LCMultitaskClearSelection(NSUserDefaults *defaults) {
    [defaults removeObjectForKey:@"selected"];
    [defaults removeObjectForKey:@"selectedContainer"];
}

static UIViewController *LCMultitaskRootViewController(void) {
    UIApplication *application = UIApplication.sharedApplication;

    for (UIScene *scene in application.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) {
            continue;
        }

        if (scene.activationState != UISceneActivationStateForegroundActive &&
            scene.activationState != UISceneActivationStateForegroundInactive) {
            continue;
        }

        UIWindowScene *windowScene = (UIWindowScene *)scene;
        for (UIWindow *window in windowScene.windows) {
            if (window.isHidden) {
                continue;
            }
            if (window.isKeyWindow && window.rootViewController) {
                return window.rootViewController;
            }
        }

        for (UIWindow *window in windowScene.windows) {
            if (!window.isHidden && window.rootViewController) {
                return window.rootViewController;
            }
        }
    }

    for (UIWindow *window in application.windows) {
        if (!window.isHidden && window.rootViewController) {
            return window.rootViewController;
        }
    }

    return nil;
}

// make SFSafariView happy and open data: URLs
@implementation NSURL(hack)
- (BOOL)safari_isHTTPFamilyURL {
    // Screw it, Apple
    return YES;
}
@end

@implementation LCUtils

+ (void)load {
    LCSharedUtilsClass = NSClassFromString(@"LCSharedUtils");
}

#pragma mark Certificate & password
+ (NSString *)teamIdentifier {
    return [LCSharedUtilsClass teamIdentifier];
}

+ (NSURL *)appGroupPath {
    return [LCSharedUtilsClass appGroupPath];
}

+ (NSData *)certificateData {
    NSUserDefaults* nud = [[NSUserDefaults alloc] initWithSuiteName:[self appGroupID]];
    if(!nud) {
        nud = NSUserDefaults.standardUserDefaults;
    }
    return [nud objectForKey:@"LCCertificateData"];
}

+ (NSString *)certificatePassword {
    return [LCSharedUtilsClass certificatePassword];
}

+ (void)setCertificatePassword:(NSString *)certPassword {
    [NSUserDefaults.standardUserDefaults setObject:certPassword forKey:@"LCCertificatePassword"];
    [[[NSUserDefaults alloc] initWithSuiteName:[self appGroupID]] setObject:certPassword forKey:@"LCCertificatePassword"];
}

+ (NSString *)appGroupID {
    return [LCSharedUtilsClass appGroupID];
}

#pragma mark LCSharedUtils wrappers
+ (BOOL)launchToGuestApp {
    return [LCSharedUtilsClass launchToGuestApp];
}

+ (BOOL)launchToGuestAppWithURL:(NSURL *)url {
    return [LCSharedUtilsClass launchToGuestAppWithURL:url];
}

+ (NSString*)getContainerUsingLCSchemeWithFolderName:(NSString*)folderName {
    return [LCSharedUtilsClass getContainerUsingLCSchemeWithFolderName:folderName];
}

#pragma mark Multitasking
+ (NSString *)liveProcessBundleIdentifier {
    // first check if we have LiveProcess extension in our own bundle
    NSBundle *liveProcessBundle = [NSBundle bundleWithPath:[NSBundle.mainBundle.builtInPlugInsPath stringByAppendingPathComponent:@"LiveProcess.appex"]];
    if(liveProcessBundle) {
        return liveProcessBundle.bundleIdentifier;
    }
    
    // in LC2, attempt to guess LC1's LiveProcess extension
    NSString *bundleID = [NSString stringWithFormat:@"com.kdt.livecontainer.%@.LiveProcess", self.teamIdentifier];
    if([NSExtension extensionWithIdentifier:bundleID error:nil]) {
        return bundleID;
    }
    
    return nil;
}

+ (void)launchMultitaskGuestApp:(NSString *)displayName completionHandler:(void (^)(NSError *error))completionHandler {
    NSString *liveProcessIdentifier = self.liveProcessBundleIdentifier;
    NSUserDefaults *lcUserDefaults = NSUserDefaults.standardUserDefaults;

    void (^finish)(NSError *) = ^(NSError *error) {
        if (!completionHandler) {
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            completionHandler(error);
        });
    };

    if (!liveProcessIdentifier) {
        NSError *error = LCMultitaskError(displayName, LCMultitaskErrorCodeMissingExtension, NSLocalizedString(@"LiveProcess extension not found. Please reinstall LiveContainer and select Keep Extensions", nil));
        finish(error);
        return;
    }

    NSString *bundleId = nil;
    NSString *dataUUID = nil;
    NSError *selectionError = nil;
    if (!LCMultitaskFetchSelection(displayName, &bundleId, &dataUUID, &selectionError)) {
        finish(selectionError);
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *rootVC = LCMultitaskRootViewController();
        if (!rootVC) {
            NSError *error = LCMultitaskError(displayName, LCMultitaskErrorCodeNoActiveWindow, NSLocalizedString(@"Unable to locate an active window to present multitasking content.", nil));
            finish(error);
            return;
        }

        if (@available(iOS 16.1, *)) {
            if (UIApplication.sharedApplication.supportsMultipleScenes && [NSUserDefaults.lcSharedDefaults integerForKey:@"LCMultitaskMode"] == 1) {
                [MultitaskWindowManager openAppWindowWithDisplayName:displayName dataUUID:dataUUID bundleId:bundleId];
                MultitaskDockManager *dock = [MultitaskDockManager shared];
                [dock addRunningApp:displayName appUUID:dataUUID view:nil];
                LCMultitaskClearSelection(lcUserDefaults);
                finish(nil);
                return;
            }
        }

        DecoratedAppSceneViewController *launcherView = [[DecoratedAppSceneViewController alloc] initWindowName:displayName bundleId:bundleId dataUUID:dataUUID rootVC:rootVC];
        launcherView.view.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleBottomMargin;
        LCMultitaskClearSelection(lcUserDefaults);
        finish(nil);
        (void)launcherView;
    });
}

+ (void)launchMultitaskGuestAppWithPIDCallback:(NSString *)displayName pidCompletionHandler:(void (^)(NSNumber *pid, NSError *error))completionHandler {
    NSString *liveProcessIdentifier = self.liveProcessBundleIdentifier;
    NSUserDefaults *lcUserDefaults = NSUserDefaults.standardUserDefaults;

    void (^finish)(NSNumber *, NSError *) = ^(NSNumber *pid, NSError *error) {
        if (!completionHandler) {
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            completionHandler(pid, error);
        });
    };

    if (!liveProcessIdentifier) {
        NSError *error = LCMultitaskError(displayName, LCMultitaskErrorCodeMissingExtension, NSLocalizedString(@"LiveProcess extension not found. Please reinstall LiveContainer and select Keep Extensions", nil));
        finish(nil, error);
        return;
    }

    NSString *bundleId = nil;
    NSString *dataUUID = nil;
    NSError *selectionError = nil;
    if (!LCMultitaskFetchSelection(displayName, &bundleId, &dataUUID, &selectionError)) {
        finish(nil, selectionError);
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *rootVC = LCMultitaskRootViewController();
        if (!rootVC) {
            NSError *error = LCMultitaskError(displayName, LCMultitaskErrorCodeNoActiveWindow, NSLocalizedString(@"Unable to locate an active window to present multitasking content.", nil));
            finish(nil, error);
            return;
        }

        __block BOOL callbackDispatched = NO;
        DecoratedAppSceneViewController *launcherView = [[DecoratedAppSceneViewController alloc] initWindowName:displayName bundleId:bundleId dataUUID:dataUUID rootVC:rootVC];
        launcherView.pidAvailableHandler = ^(NSNumber *pid, NSError *error) {
            if (callbackDispatched) {
                return;
            }
            callbackDispatched = YES;
            finish(pid, error);
        };
        launcherView.view.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleBottomMargin;
        launcherView.view.center = rootVC.view.center;
        [rootVC addChildViewController:launcherView];
        [rootVC.view addSubview:launcherView.view];
        LCMultitaskClearSelection(lcUserDefaults);
        (void)launcherView;
    });
}

#pragma mark Code signing


+ (void)loadStoreFrameworksWithError2:(NSError **)error {
    // too lazy to use dispatch_once
    static BOOL loaded = NO;
    if (loaded) return;

    void* handle = dlopen("@executable_path/Frameworks/ZSign.dylib", RTLD_GLOBAL);
    const char* dlerr = dlerror();
    if (!handle || (uint64_t)handle > 0xf00000000000) {
        if (dlerr) {
            *error = [NSError errorWithDomain:NSBundle.mainBundle.bundleIdentifier code:1 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to load ZSign: %s", dlerr]}];
        } else {
            *error = [NSError errorWithDomain:NSBundle.mainBundle.bundleIdentifier code:1 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to load ZSign: An unknown error occurred."]}];
        }
        NSLog(@"[LC] %s", dlerr);
        return;
    }
    
    loaded = YES;
}

+ (NSURL *)storeBundlePath {
    if ([self store] == SideStore) {
        return [self.appGroupPath URLByAppendingPathComponent:@"Apps/com.SideStore.SideStore/App.app"];
    } else {
        return [self.appGroupPath URLByAppendingPathComponent:@"Apps/com.rileytestut.AltStore/App.app"];
    }
}

+ (NSString *)storeInstallURLScheme {
    if ([self store] == SideStore) {
        return @"sidestore://install?url=%@";
    } else {
        return @"altstore://install?url=%@";
    }
}

+ (NSProgress *)signAppBundleWithZSign:(NSURL *)path completionHandler:(void (^)(BOOL success, NSError *error))completionHandler {
    NSError *error;

    // use zsign as our signer~
    NSURL *profilePath = [NSBundle.mainBundle URLForResource:@"embedded" withExtension:@"mobileprovision"];
    NSData *profileData = [NSData dataWithContentsOfURL:profilePath];
    // Load libraries from Documents, yeah
    [self loadStoreFrameworksWithError2:&error];

    if (error) {
        completionHandler(NO, error);
        return nil;
    }

    NSLog(@"[LC] starting signing...");
    
    NSProgress* ans = [NSClassFromString(@"ZSigner") signWithAppPath:[path path] prov:profileData key: self.certificateData pass:self.certificatePassword completionHandler:completionHandler];
    
    return ans;
}

+ (NSString*)getCertTeamIdWithKeyData:(NSData*)keyData password:(NSString*)password {
    NSError *error;
    NSURL *profilePath = [NSBundle.mainBundle URLForResource:@"embedded" withExtension:@"mobileprovision"];
    NSData *profileData = [NSData dataWithContentsOfURL:profilePath];
    [self loadStoreFrameworksWithError2:&error];
    if (error) {
        return nil;
    }
    NSString* ans = [NSClassFromString(@"ZSigner") getTeamIdWithProv:profileData key:keyData pass:password];
    return ans;
}

+ (int)validateCertificateWithCompletionHandler:(void(^)(int status, NSDate *expirationDate, NSString *error))completionHandler {
    NSError *error;
    NSURL *profilePath = [NSBundle.mainBundle URLForResource:@"embedded" withExtension:@"mobileprovision"];
    NSData *profileData = [NSData dataWithContentsOfURL:profilePath];
    NSData *certData = [LCUtils certificateData];
    if (error) {
        return -6;
    }
    [self loadStoreFrameworksWithError2:&error];
    int ans = [NSClassFromString(@"ZSigner") checkCertWithProv:profileData key:certData pass:[LCUtils certificatePassword] completionHandler:completionHandler];
    return ans;
}

#pragma mark Setup

+ (Store) store {
    static Store ans;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // use uttype to accurately detect store
        if([UTType typeWithIdentifier:[NSString stringWithFormat:@"io.sidestore.Installed.%@", NSBundle.mainBundle.bundleIdentifier]]) {
            ans = SideStore;
        } else if ([UTType typeWithIdentifier:[NSString stringWithFormat:@"io.altstore.Installed.%@", NSBundle.mainBundle.bundleIdentifier]]) {
            ans = AltStore;
        } else {
            ans = Unknown;
        }
        
        if(ans != Unknown) {
            return;
        }
        
        if([[self appGroupID] containsString:@"AltStore"] && ![[self appGroupID] isEqualToString:@"group.com.rileytestut.AltStore"]) {
            ans = AltStore;
        } else if ([[self appGroupID] containsString:@"SideStore"] && ![[self appGroupID] isEqualToString:@"group.com.SideStore.SideStore"]) {
            ans = SideStore;
        } else if (![[self appGroupID] containsString:@"Unknown"] ) {
            ans = ADP;
        } else {
            ans = Unknown;
        }
    });
    return ans;
}

+ (NSString *)appUrlScheme {
    return NSBundle.mainBundle.infoDictionary[@"CFBundleURLTypes"][0][@"CFBundleURLSchemes"][0];
}

+ (BOOL)isAppGroupAltStoreLike {
    return [self.appGroupID containsString:@"SideStore"] || [self.appGroupID containsString:@"AltStore"];
}

+ (void)changeMainExecutableTo:(NSString *)exec error:(NSError **)error {
    NSURL *infoPath = [self.appGroupPath URLByAppendingPathComponent:@"Apps/com.kdt.livecontainer/App.app/Info.plist"];
    NSMutableDictionary *infoDict = [NSMutableDictionary dictionaryWithContentsOfURL:infoPath];
    if (!infoDict) return;

    infoDict[@"CFBundleExecutable"] = exec;
    [infoDict writeToURL:infoPath error:error];
}

+ (void)validateJITLessSetupWithCompletionHandler:(void (^)(BOOL success, NSError *error))completionHandler {
    // Verify that the certificate is usable
    // Create a test app bundle
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"CertificateValidation.app"];
    [NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *tmpExecPath = [path stringByAppendingPathComponent:@"LiveContainer.tmp"];
    NSString *tmpLibPath = [path stringByAppendingPathComponent:@"TestJITLess.dylib"];
    NSString *tmpInfoPath = [path stringByAppendingPathComponent:@"Info.plist"];
    [NSFileManager.defaultManager copyItemAtPath:NSBundle.mainBundle.executablePath toPath:tmpExecPath error:nil];
    [NSFileManager.defaultManager copyItemAtPath:[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Frameworks/TestJITLess.dylib"] toPath:tmpLibPath error:nil];
    NSMutableDictionary *info = NSBundle.mainBundle.infoDictionary.mutableCopy;
    info[@"CFBundleExecutable"] = @"LiveContainer.tmp";
    [info writeBinToFile:tmpInfoPath atomically:YES];

    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    __block bool signSuccess = false;
    __block NSError* signError = nil;
    
    // Sign the test app bundle

    [LCUtils signAppBundleWithZSign:[NSURL fileURLWithPath:path]
                  completionHandler:^(BOOL success, NSError *_Nullable error) {
        signSuccess = success;
        signError = error;
        dispatch_semaphore_signal(sema);
    }];

    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if(!signSuccess) {
            completionHandler(NO, signError);
        } else if (checkCodeSignature([tmpLibPath UTF8String])) {
            completionHandler(YES, signError);
        } else {
            completionHandler(NO, [NSError errorWithDomain:NSBundle.mainBundle.bundleIdentifier code:2 userInfo:@{NSLocalizedDescriptionKey: @"lc.signer.latestCertificateInvalidErr"}]);
        }
        
    });
    

}

+ (NSURL *)archiveIPAWithBundleName:(NSString*)newBundleName excludingInfoPlistKeys:(NSArray *)keysToExclude error:(NSError **)error {
    if (*error) return nil;

    NSFileManager *manager = NSFileManager.defaultManager;
    NSURL *bundlePath = NSBundle.mainBundle.bundleURL;

    NSURL *tmpPath = manager.temporaryDirectory;

    NSURL *tmpPayloadPath = [tmpPath URLByAppendingPathComponent:@"LiveContainer2/Payload"];
    [manager removeItemAtURL:tmpPayloadPath error:nil];
    [manager createDirectoryAtURL:tmpPayloadPath withIntermediateDirectories:YES attributes:nil error:error];
    if (*error) return nil;
    
    NSURL *tmpIPAPath = [tmpPath URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.ipa", newBundleName]];
    

    [manager copyItemAtURL:bundlePath toURL:[tmpPayloadPath URLByAppendingPathComponent:@"App.app"] error:error];
    if (*error) return nil;
    
    NSURL *infoPath = [tmpPayloadPath URLByAppendingPathComponent:@"App.app/Info.plist"];
    NSMutableDictionary *infoDict = [NSMutableDictionary dictionaryWithContentsOfURL:infoPath];
    if (!infoDict) return nil;

    infoDict[@"CFBundleDisplayName"] = newBundleName;
    infoDict[@"CFBundleName"] = newBundleName;
    infoDict[@"CFBundleIdentifier"] = [NSString stringWithFormat:@"com.kdt.%@", newBundleName];
    infoDict[@"CFBundleURLTypes"][0][@"CFBundleURLSchemes"][0] = [newBundleName lowercaseString];
    while([infoDict[@"CFBundleURLTypes"] count] > 1) {
        [infoDict[@"CFBundleURLTypes"] removeLastObject];
    }
    [infoDict removeObjectForKey:@"UTExportedTypeDeclarations"];
    infoDict[@"CFBundleIconName"] = @"AppIconGrey";
    if (infoDict[@"CFBundleIcons"][@"CFBundlePrimaryIcon"][@"CFBundleIconName"]) {
        infoDict[@"CFBundleIcons"][@"CFBundlePrimaryIcon"][@"CFBundleIconName"] = @"AppIconGrey";
    }
    infoDict[@"CFBundleIcons"][@"CFBundlePrimaryIcon"][@"CFBundleIconFiles"][0] = @"AppIconGrey60x60";
    
    if (infoDict[@"CFBundleIcons~ipad"][@"CFBundlePrimaryIcon"][@"CFBundleIconName"]) {
        infoDict[@"CFBundleIcons~ipad"][@"CFBundlePrimaryIcon"][@"CFBundleIconName"] = @"AppIconGrey";
    }
    infoDict[@"CFBundleIcons~ipad"][@"CFBundlePrimaryIcon"][@"CFBundleIconFiles"][0] = @"AppIconGrey60x60";
    infoDict[@"CFBundleIcons~ipad"][@"CFBundlePrimaryIcon"][@"CFBundleIconFiles"][1] = @"AppIconGrey76x76";
    [infoDict removeObjectsForKeys:keysToExclude];
    
    // reset a executable name so they don't look the same on the log
    NSURL* appBundlePath = [tmpPayloadPath URLByAppendingPathComponent:@"App.app"];
    
    NSURL* execFromPath = [appBundlePath URLByAppendingPathComponent:infoDict[@"CFBundleExecutable"]];
    infoDict[@"CFBundleExecutable"] = newBundleName;
    NSURL* execToPath = [appBundlePath URLByAppendingPathComponent:infoDict[@"CFBundleExecutable"]];
    
    // MARK: patch main executable
    // we remove the teamId after app group id so it can be correctly signed by AltSign.
    NSString* entitlementXML = getLCEntitlementXML();
    NSData *plistData = [entitlementXML dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableDictionary *dict = [NSPropertyListSerialization propertyListWithData:plistData
                                                                          options:NSPropertyListMutableContainers
                                                                           format:nil
                                                                            error:error];
    if(*error) {
        return nil;
    }
    
    NSString* teamId = dict[@"com.apple.developer.team-identifier"];
    if(![teamId isKindOfClass:NSString.class]) {
        *error = [NSError errorWithDomain:@"archiveIPAWithBundleName" code:-1 userInfo:@{NSLocalizedDescriptionKey:@"com.apple.developer.team-identifier is not a string!"}];
        return nil;
    }
    infoDict[@"PrimaryLiveContainerTeamId"] = teamId;
    NSArray* appGroupsToFind = @[
        @"group.com.SideStore.SideStore",
        @"group.com.rileytestut.AltStore",
    ];
    
    // remove the team id prefix in app group id added by SideStore/AltStore
    for(NSString* appGroup in appGroupsToFind) {
        NSUInteger appGroupCount = [dict[@"com.apple.security.application-groups"] count];
        for(int i = 0; i < appGroupCount; ++i) {
            NSString* targetAppGroup = [NSString stringWithFormat:@"%@.%@", appGroup, teamId];
            if([dict[@"com.apple.security.application-groups"][i] isEqualToString:targetAppGroup]) {
                dict[@"com.apple.security.application-groups"][i] = appGroup;
            }
        }
    }
    
    // set correct application-identifier
    dict[@"application-identifier"] = [NSString stringWithFormat:@"%@.%@", teamId, infoDict[@"CFBundleIdentifier"]];
    
    // For TrollStore
    NSString* containerId = dict[@"com.apple.private.security.container-required"];
    if(containerId) {
        dict[@"com.apple.private.security.container-required"] = infoDict[@"CFBundleIdentifier"];
    }
    
    
    // We have to change executable's UUID so iOS won't consider 2 executables the same
    NSString* errorChangeUUID = LCParseMachO([execFromPath.path UTF8String], false, ^(const char *path, struct mach_header_64 *header, int fd, void* filePtr) {
        LCChangeMachOUUID(header);
    });
    if (errorChangeUUID) {
        NSMutableDictionary* details = [NSMutableDictionary dictionary];
        [details setValue:errorChangeUUID forKey:NSLocalizedDescriptionKey];
        // populate the error object with the details
        *error = [NSError errorWithDomain:@"world" code:200 userInfo:details];
        NSLog(@"[LC] %@", errorChangeUUID);
        return nil;
    }
    
    NSData* newEntitlementData = [NSPropertyListSerialization dataWithPropertyList:dict format:NSPropertyListXMLFormat_v1_0 options:0 error:error];
    [LCUtils loadStoreFrameworksWithError2:error];
    BOOL adhocSignSuccess = [NSClassFromString(@"ZSigner") adhocSignMachOAtPath:execFromPath.path bundleId:infoDict[@"CFBundleIdentifier"] entitlementData:newEntitlementData];
    if (!adhocSignSuccess) {
        *error = [NSError errorWithDomain:@"archiveIPAWithBundleName" code:-1 userInfo:@{NSLocalizedDescriptionKey:@"Failed to adhoc sign main executable!"}];
        return nil;
    }
    
    // MARK: archive bundle
    
    [manager moveItemAtURL:execFromPath toURL:execToPath error:error];
    if (*error) {
        NSLog(@"[LC] %@", *error);
        return nil;
    }
        
    // we remove the extension
    [manager removeItemAtURL:[appBundlePath URLByAppendingPathComponent:@"PlugIns"] error:error];
    // remove all sidestore stuff
    if([NSUserDefaults sideStoreExist]) {
        [manager removeItemAtURL:[appBundlePath URLByAppendingPathComponent:@"Frameworks/SideStore.framework"] error:error];
        [manager removeItemAtURL:[appBundlePath URLByAppendingPathComponent:@"Frameworks/SideStoreApp.framework"] error:error];
        [manager removeItemAtURL:[appBundlePath URLByAppendingPathComponent:@"Intents.intentdefinition"] error:error];
        [manager removeItemAtURL:[appBundlePath URLByAppendingPathComponent:@"ViewApp.intentdefinition"] error:error];
        [manager removeItemAtURL:[appBundlePath URLByAppendingPathComponent:@"Metadata.appintents"] error:error];
        [infoDict removeObjectForKey:@"INIntentsSupported"];
        [infoDict removeObjectForKey:@"NSUserActivityTypes"];
    }
    
    [infoDict writeToURL:infoPath error:error];
    
    dlopen("/System/Library/PrivateFrameworks/PassKitCore.framework/PassKitCore", RTLD_GLOBAL);
    NSData *zipData = [[NSClassFromString(@"PKZipArchiver") new] zippedDataForURL:tmpPayloadPath.URLByDeletingLastPathComponent];
    if (!zipData) return nil;

    [manager removeItemAtURL:tmpPayloadPath error:error];
    if (*error) return nil;
    
    if([manager fileExistsAtPath:tmpIPAPath.path]) {
        [manager removeItemAtURL:tmpIPAPath error:error];
        if (*error) return nil;
    }

    [zipData writeToURL:tmpIPAPath options:0 error:error];
    if (*error) return nil;

    return tmpIPAPath;
}

+ (NSString *)getVersionInfo {
    return [NSString stringWithFormat:@"Version %@-%@",
            NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"],
            NSBundle.mainBundle.infoDictionary[@"LCVersionInfo"]];
}

@end
