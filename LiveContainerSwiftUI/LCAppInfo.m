@import CommonCrypto;
@import MachO;

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "LCAppInfo.h"
#import "LCUtils.h"
#import <LiveContainer/LCBundleTransaction.h>

uint32_t dyld_get_sdk_version(const struct mach_header* mh);

@interface LCAppInfo()
@property UIImage* cachedIcon;
@end

@implementation LCAppInfo

- (instancetype)initWithBundlePath:(NSString*)bundlePath {
    self = [super init];
    self.isShared = false;
	if(self) {
        _bundlePath = bundlePath;
        _infoPlist = [NSMutableDictionary dictionaryWithContentsOfFile:[NSString stringWithFormat:@"%@/Info.plist", bundlePath]];
        _info = [NSMutableDictionary dictionaryWithContentsOfFile:[NSString stringWithFormat:@"%@/LCAppInfo.plist", bundlePath]];
        if(!_info) {
            _info = [[NSMutableDictionary alloc] init];
        }
        if(!_infoPlist) {
            _infoPlist = [[NSMutableDictionary alloc] init];
        }
        
        // migrate old appInfo
        if(_infoPlist[@"LCPatchRevision"] && [_info count] == 0) {
            NSArray* lcAppInfoKeys = @[
                @"LCPatchRevision",
                @"LCOrignalBundleIdentifier",
                @"LCDataUUID",
                @"LCTweakFolder",
                @"LCJITLessSignID",
                @"LCSelectedLanguage",
                @"LCExpirationDate",
                @"LCTeamId",
                @"isJITNeeded",
                @"isLocked",
                @"isHidden",
                @"doUseLCBundleId",
                @"doSymlinkInbox",
                @"bypassAssertBarrierOnQueue",
                @"signer",
                @"LCOrientationLock",
                @"cachedColor",
                @"LCContainers",
                @"hideLiveContainer",
                @"jitLaunchScriptJs"
            ];
            for(NSString* key in lcAppInfoKeys) {
                _info[key] = _infoPlist[key];
                [_infoPlist removeObjectForKey:key];
            }
            [_infoPlist writeBinToFile:[NSString stringWithFormat:@"%@/Info.plist", bundlePath] atomically:YES];
            [self save];
        }
        
        // fix bundle id and execName if crash when signing
        if (_infoPlist[@"LCBundleIdentifier"]) {
            _infoPlist[@"CFBundleExecutable"] = _infoPlist[@"LCBundleExecutable"];
            _infoPlist[@"CFBundleIdentifier"] = _infoPlist[@"LCBundleIdentifier"];
            [_infoPlist removeObjectForKey:@"LCBundleExecutable"];
            [_infoPlist removeObjectForKey:@"LCBundleIdentifier"];
            [_infoPlist writeBinToFile:[NSString stringWithFormat:@"%@/Info.plist", bundlePath] atomically:YES];
        }

        _autoSaveDisabled = false;
    }
    return self;
}

- (void)setBundlePath:(NSString*)newBundlePath {
    _bundlePath = newBundlePath;
}

- (NSMutableArray*)urlSchemes {
    // find all url schemes
    NSMutableArray* urlSchemes = [[NSMutableArray alloc] init];
    int nowSchemeCount = 0;
    if (_infoPlist[@"CFBundleURLTypes"]) {
        NSMutableArray* urlTypes = _infoPlist[@"CFBundleURLTypes"];

        for(int i = 0; i < [urlTypes count]; ++i) {
            NSMutableDictionary* nowUrlType = [urlTypes objectAtIndex:i];
            if (!nowUrlType[@"CFBundleURLSchemes"]){
                continue;
            }
            NSMutableArray *schemes = nowUrlType[@"CFBundleURLSchemes"];
            for(int j = 0; j < [schemes count]; ++j) {
                [urlSchemes insertObject:[schemes objectAtIndex:j] atIndex:nowSchemeCount];
                ++nowSchemeCount;
            }
        }
    }
    
    return urlSchemes;
}

- (NSString*)displayName {
    if (_infoPlist[@"CFBundleDisplayName"]) {
        return _infoPlist[@"CFBundleDisplayName"];
    } else if (_infoPlist[@"CFBundleName"]) {
        return _infoPlist[@"CFBundleName"];
    } else if (_infoPlist[@"CFBundleExecutable"]) {
        return _infoPlist[@"CFBundleExecutable"];
    } else {
        return @"App Corrupted, Please Reinstall This App";
    }
}

- (NSString*)version {
    NSString* version = _infoPlist[@"CFBundleShortVersionString"];
    if (!version) {
        version = _infoPlist[@"CFBundleVersion"];
    }
    if(version) {
        return version;
    } else {
        return @"Unknown";
    }
}

- (NSString*)bundleIdentifier {
    NSString* ans = nil;
    if([self doUseLCBundleId]) {
        ans = _info[@"LCOrignalBundleIdentifier"];
    } else {
        ans = _infoPlist[@"CFBundleIdentifier"];
    }
    if(ans) {
        return ans;
    } else {
        return @"Unknown";
    }
}

- (NSString*)dataUUID {
    return _info[@"LCDataUUID"];
}

- (NSString*)tweakFolder {
    return _info[@"LCTweakFolder"];
}

- (void)setDataUUID:(NSString *)uuid {
    _info[@"LCDataUUID"] = uuid;
    [self save];
}

- (void)setTweakFolder:(NSString *)tweakFolder {
    _info[@"LCTweakFolder"] = tweakFolder;
    [self save];
}

- (NSString*)selectedLanguage {
    return _info[@"LCSelectedLanguage"];
}

- (void)setSelectedLanguage:(NSString *)selectedLanguage {
    if([selectedLanguage isEqualToString: @""]) {
        _info[@"LCSelectedLanguage"] = nil;
    } else {
        _info[@"LCSelectedLanguage"] = selectedLanguage;
    }
    
    [self save];
}

- (NSString*)bundlePath {
    return _bundlePath;
}

- (NSMutableDictionary*)info {
    return _info;
}

- (UIImage*)icon {
    if(_cachedIcon) {
        return _cachedIcon;
    }
    
    NSBundle* bundle = [[NSBundle alloc] initWithPath: _bundlePath];
    NSString* iconPath = nil;
    UIImage* icon = nil;

    @try {
        if((iconPath = [_infoPlist valueForKeyPath:@"CFBundleIcons.CFBundlePrimaryIcon.CFBundleIconFiles"][0]) &&
           (icon = [UIImage imageNamed:iconPath inBundle:bundle compatibleWithTraitCollection:nil])) {
            return icon;
        }
    }
    @catch (NSException *exception) {
        NSLog(@"Failed to get icon from info.plist: %@", exception.reason);
    }
    @try {
        if((iconPath = [_infoPlist valueForKeyPath:@"CFBundleIconFiles"][0]) &&
           (icon = [UIImage imageNamed:iconPath inBundle:bundle compatibleWithTraitCollection:nil])) {
            return icon;
        }
    }
    @catch (NSException *exception) {
        NSLog(@"Failed to get icon from info.plist: %@", exception.reason);
    }
    @try {
        if((iconPath = [_infoPlist valueForKeyPath:@"CFBundleIcons~ipad"][@"CFBundlePrimaryIcon"][@"CFBundleIconName"]) &&
           (icon = [UIImage imageNamed:iconPath inBundle:bundle compatibleWithTraitCollection:nil])) {
            return icon;
        }
    }
    @catch (NSException *exception) {
        NSLog(@"Failed to get icon from info.plist: %@", exception.reason);
    }
    
    @try {
        if((iconPath = [_infoPlist valueForKeyPath:@"CFBundleIcons"][@"CFBundlePrimaryIcon"]) && [iconPath isKindOfClass:NSString.class] &&
           (icon = [UIImage imageNamed:iconPath inBundle:bundle compatibleWithTraitCollection:nil])) {
            return icon;
        }
    }
    @catch (NSException *exception) {
        NSLog(@"Failed to get icon from info.plist: %@", exception.reason);
    }

    if(!icon) {
        icon = [UIImage imageNamed:@"DefaultIcon"];
    }
        
    _cachedIcon = icon;
    return icon;

}

- (UIImage *)generateLiveContainerWrappedIcon {
    UIImage *icon = self.icon;
    if (![NSUserDefaults.standardUserDefaults boolForKey:@"LCFrameShortcutIcons"]) {
        return icon;
    }

    UIImage *lcIcon = [UIImage imageNamed:@"AppIcon60x60@2x"];
    CGFloat iconXY = (lcIcon.size.width - 40) / 2;
    UIGraphicsBeginImageContextWithOptions(lcIcon.size, NO, 0.0);
    [lcIcon drawInRect:CGRectMake(0, 0, lcIcon.size.width, lcIcon.size.height)];
    CGRect rect = CGRectMake(iconXY, iconXY, 40, 40);
    [[UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:7] addClip];
    [icon drawInRect:rect];
    UIImage *newIcon = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return newIcon;
}

- (NSDictionary *)generateWebClipConfigWithContainerId:(NSString*)containerId {
    NSString* appClipUrl;
    if(containerId) {
        appClipUrl = [NSString stringWithFormat:@"livecontainer://livecontainer-launch?bundle-name=%@&container-folder-name=%@", self.bundlePath.lastPathComponent, containerId];
    } else {
        appClipUrl = [NSString stringWithFormat:@"livecontainer://livecontainer-launch?bundle-name=%@", self.bundlePath.lastPathComponent];
    }
    
    NSDictionary *payload = @{
        @"FullScreen": @YES,
        @"Icon": UIImagePNGRepresentation(self.generateLiveContainerWrappedIcon),
        @"IgnoreManifestScope": @YES,
        @"IsRemovable": @YES,
        @"Label": self.displayName,
        @"PayloadDescription": [NSString stringWithFormat:@"Web Clip for launching %@ (%@) in LiveContainer", self.displayName, self.bundlePath.lastPathComponent],
        @"PayloadDisplayName": self.displayName,
        @"PayloadIdentifier": self.bundleIdentifier,
        @"PayloadType": @"com.apple.webClip.managed",
        @"PayloadUUID": NSUUID.UUID.UUIDString,
        @"PayloadVersion": @(1),
        @"Precomposed": @NO,
        @"toPayloadOrganization": @"LiveContainer",
        @"URL": appClipUrl
    };
    return @{
        @"ConsentText": @{
            @"default": [NSString stringWithFormat:@"This profile installs a web clip which opens %@ (%@) in LiveContainer", self.displayName, self.bundlePath.lastPathComponent]
        },
        @"PayloadContent": @[payload],
        @"PayloadDescription": payload[@"PayloadDescription"],
        @"PayloadDisplayName": self.displayName,
        @"PayloadIdentifier": self.bundleIdentifier,
        @"PayloadOrganization": @"LiveContainer",
        @"PayloadRemovalDisallowed": @(NO),
        @"PayloadType": @"Configuration",
        @"PayloadUUID": @"345097fb-d4f7-4a34-ab90-2e3f1ad62eed",
        @"PayloadVersion": @(1),
    };
}

- (void)save {
    if(!_autoSaveDisabled) {
        [_info writeBinToFile:[NSString stringWithFormat:@"%@/LCAppInfo.plist", _bundlePath] atomically:YES];
    }

}

- (void)patchExecAndSignIfNeedWithCompletionHandler:(void(^)(bool success, NSString* errorInfo))completionHandler progressHandler:(void(^)(NSProgress* progress))progressHandler forceSign:(BOOL)forceSign {
    [NSUserDefaults.standardUserDefaults setObject:@(YES) forKey:@"SigningInProgress"];

    NSString *originalBundlePath = self.bundlePath;
    NSString *originalInfoPath = [originalBundlePath stringByAppendingPathComponent:@"Info.plist"];
    NSString *originalAppInfoPath = [originalBundlePath stringByAppendingPathComponent:@"LCAppInfo.plist"];

    NSMutableDictionary *info = _info;
    NSMutableDictionary *infoPlist = _infoPlist;
    if (!info) {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"SigningInProgress"];
        completionHandler(NO, @"Info.plist not found");
        return;
    }

    NSFileManager *fm = NSFileManager.defaultManager;
    NSError *transactionError = nil;
    __block LCBundleTransaction *transaction = [[LCBundleTransaction alloc] initWithBundlePath:originalBundlePath fileManager:fm];
    if (![transaction begin:&transactionError]) {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"SigningInProgress"];
        completionHandler(NO, transactionError.localizedDescription ?: @"Failed to prepare bundle transaction.");
        return;
    }

    [self setBundlePath:transaction.workingPath];
    NSString *appPath = transaction.workingPath;
    NSString *infoPath = [appPath stringByAppendingPathComponent:@"Info.plist"];
    NSString *execPath = [appPath stringByAppendingPathComponent:_infoPlist[@"CFBundleExecutable"]];

    __block BOOL transactionCommitted = NO;
    __block BOOL transactionCancelled = NO;

    void (^revertAndReload)(void) = ^{
        if (transaction && !transactionCommitted && !transactionCancelled) {
            [transaction cancel];
            transactionCancelled = YES;
        }
        transaction = nil;
        [self setBundlePath:originalBundlePath];
        NSMutableDictionary *reloadedInfo = [NSMutableDictionary dictionaryWithContentsOfFile:originalAppInfoPath];
        if (reloadedInfo) {
            self->_info = reloadedInfo;
        }
        NSMutableDictionary *reloadedInfoPlist = [NSMutableDictionary dictionaryWithContentsOfFile:originalInfoPath];
        if (reloadedInfoPlist) {
            self->_infoPlist = reloadedInfoPlist;
        }
    };

    void (^fail)(NSString *) = ^(NSString *message) {
        revertAndReload();
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"SigningInProgress"];
        completionHandler(NO, message ?: @"Unknown error");
    };

    int currentPatchRev = 7;
    bool needPatch = [info[@"LCPatchRevision"] intValue] < currentPatchRev;
    if (needPatch || forceSign) {
        NSString *backupPath = [NSString stringWithFormat:@"%@/%@_LiveContainerPatchBackUp", appPath, _infoPlist[@"CFBundleExecutable"]];
        NSError *err;
        [fm copyItemAtPath:execPath toPath:backupPath error:&err];
        [fm removeItemAtPath:execPath error:&err];
        [fm moveItemAtPath:backupPath toPath:execPath error:&err];
    }

    bool is32bit = false;
    if (needPatch) {
        __block bool has64bitSlice = NO;
        NSString *parseError = LCParseMachO(execPath.UTF8String, false, ^(const char *path, struct mach_header_64 *header, int fd, void *filePtr) {
            if(header->cputype == CPU_TYPE_ARM64) {
                has64bitSlice = YES;
                int patchResult = LCPatchExecSlice(path, header, ![self dontInjectTweakLoader]);
                if(patchResult & PATCH_EXEC_RESULT_NO_SPACE_FOR_TWEAKLOADER) {
                    info[@"LCTweakLoaderCantInject"] = @YES;
                    info[@"dontInjectTweakLoader"] = @YES;
                }
            }
        });
        is32bit = !has64bitSlice;
        LCPatchAppBundleFixupARM64eSlice([NSURL fileURLWithPath:appPath]);

        if (parseError) {
            fail(parseError);
            return;
        }
        info[@"LCPatchRevision"] = @(currentPatchRev);
        forceSign = true;
        [self save];
    }
#if !is32BitSupported
    if(is32bit) {
        fail(@"32-bit app is NOT supported!");
        return;
    }
#else
    self.is32Bit = is32bit;
#endif

    if (!LCUtils.certificatePassword || is32bit || self.dontSign) {
        NSError *commitErr = nil;
        if (![transaction commit:&commitErr]) {
            fail(commitErr.localizedDescription ?: @"Failed to finalize bundle transaction.");
            return;
        }
        transactionCommitted = YES;
        transaction = nil;
        [self setBundlePath:originalBundlePath];
        [self save];
        [infoPlist writeBinToFile:originalInfoPath atomically:YES];
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"SigningInProgress"];
        completionHandler(YES, nil);
        return;
    }

    NSString *workingExecutablePath = [appPath stringByAppendingPathComponent:infoPlist[@"CFBundleExecutable"]];
    if(!forceSign) {
        bool signatureValid = checkCodeSignature(workingExecutablePath.UTF8String);

        if(signatureValid) {
            [transaction cancel];
            transactionCancelled = YES;
            transaction = nil;
            [self setBundlePath:originalBundlePath];
            [NSUserDefaults.standardUserDefaults removeObjectForKey:@"SigningInProgress"];
            completionHandler(YES, nil);
            return;
        }
    }

    if (!LCUtils.certificateData) {
        fail(@"lc.signer.noCertificateFoundErr");
        return;
    }

    if(forceSign) {
        NSString* cachePath = [appPath stringByAppendingPathComponent:@"zsign_cache.json"];
        if([fm fileExistsAtPath:cachePath]) {
            NSError* err;
            [fm removeItemAtPath:cachePath error:&err];
        }
    }

    NSURL *appPathURL = [NSURL fileURLWithPath:appPath];
    NSString *tmpExecPath = [appPath stringByAppendingPathComponent:@"LiveContainer.tmp"];
    if (!info[@"LCBundleIdentifier"]) {
        [fm copyItemAtPath:NSBundle.mainBundle.executablePath toPath:tmpExecPath error:nil];

        infoPlist[@"LCBundleExecutable"] = infoPlist[@"CFBundleExecutable"];
        infoPlist[@"LCBundleIdentifier"] = infoPlist[@"CFBundleIdentifier"];
        infoPlist[@"CFBundleExecutable"] = tmpExecPath.lastPathComponent;
        infoPlist[@"CFBundleIdentifier"] = NSBundle.mainBundle.bundleIdentifier;
        [infoPlist writeBinToFile:infoPath atomically:YES];
    }
    infoPlist[@"CFBundleExecutable"] = infoPlist[@"LCBundleExecutable"];
    infoPlist[@"CFBundleIdentifier"] = infoPlist[@"LCBundleIdentifier"];
    [infoPlist removeObjectForKey:@"LCBundleExecutable"];
    [infoPlist removeObjectForKey:@"LCBundleIdentifier"];

    __block NSString *signMessage = nil;
    __weak typeof(self) weakSelf = self;

    void (^signCompletionHandler)(BOOL, NSError *) = ^(BOOL success, NSError *_Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [fm removeItemAtPath:tmpExecPath error:nil];
            signMessage = error.localizedDescription;

            if (!success) {
                fail(signMessage ?: @"Signing failed");
                return;
            }

            NSError *commitErr = nil;
            if (![transaction commit:&commitErr]) {
                fail(commitErr.localizedDescription ?: @"Failed to finalize bundle transaction.");
                return;
            }
            transactionCommitted = YES;
            transaction = nil;

            [strongSelf setBundlePath:originalBundlePath];
            NSString *finalInfoPath = [originalBundlePath stringByAppendingPathComponent:@"Info.plist"];
            [infoPlist writeBinToFile:finalInfoPath atomically:YES];
            [strongSelf save];
            [NSUserDefaults.standardUserDefaults removeObjectForKey:@"SigningInProgress"];

            NSString *finalExecutablePath = [originalBundlePath stringByAppendingPathComponent:infoPlist[@"CFBundleExecutable"]];
            bool signatureValid = checkCodeSignature(finalExecutablePath.UTF8String);
            if(signatureValid) {
                completionHandler(YES, signMessage);
            } else {
                completionHandler(NO, @"lc.signer.latestCertificateInvalidErr");
            }
        });
    };

    __block NSProgress *progress = [LCUtils signAppBundleWithZSign:appPathURL completionHandler:signCompletionHandler];

    if (progress) {
        progressHandler(progress);
    }

}

- (bool)isJITNeeded {
    if(_info[@"isJITNeeded"] != nil) {
        return [_info[@"isJITNeeded"] boolValue];
    } else {
        return NO;
    }
}
- (void)setIsJITNeeded:(bool)isJITNeeded {
    _info[@"isJITNeeded"] = [NSNumber numberWithBool:isJITNeeded];
    [self save];
    
}

- (bool)isLocked {
    if(_info[@"isLocked"] != nil) {
        return [_info[@"isLocked"] boolValue];
    } else {
        return NO;
    }
}
- (void)setIsLocked:(bool)isLocked {
    _info[@"isLocked"] = [NSNumber numberWithBool:isLocked];
    [self save];
    
}

- (bool)isHidden {
    if(_info[@"isHidden"] != nil) {
        return [_info[@"isHidden"] boolValue];
    } else {
        return NO;
    }
}
- (void)setIsHidden:(bool)isHidden {
    _info[@"isHidden"] = [NSNumber numberWithBool:isHidden];
    [self save];
    
}

- (bool)doSymlinkInbox {
    if(_info[@"doSymlinkInbox"] != nil) {
        return [_info[@"doSymlinkInbox"] boolValue];
    } else {
        return NO;
    }
}
- (void)setDoSymlinkInbox:(bool)doSymlinkInbox {
    _info[@"doSymlinkInbox"] = [NSNumber numberWithBool:doSymlinkInbox];
    [self save];
    
}

- (bool)hideLiveContainer {
    if(_info[@"hideLiveContainer"] != nil) {
        return [_info[@"hideLiveContainer"] boolValue];
    } else {
        return NO;
    }
}
- (void)setHideLiveContainer:(bool)hideLiveContainer {
    _info[@"hideLiveContainer"] = [NSNumber numberWithBool:hideLiveContainer];
    [self save];
}

- (bool)dontInjectTweakLoader {
    if(_info[@"dontInjectTweakLoader"] != nil) {
        return [_info[@"dontInjectTweakLoader"] boolValue];
    } else {
        return NO;
    }
}
- (void)setDontInjectTweakLoader:(bool)dontInjectTweakLoader {
    if([_info[@"dontInjectTweakLoader"] boolValue] == dontInjectTweakLoader) {
        return;
    }
    
    _info[@"dontInjectTweakLoader"] = [NSNumber numberWithBool:dontInjectTweakLoader];
    // we have to update patch to achieve this
    _info[@"LCPatchRevision"] = @(-1);
    [self save];
}

- (bool)dontLoadTweakLoader {
    if(_info[@"dontLoadTweakLoader"] != nil) {
        return [_info[@"dontLoadTweakLoader"] boolValue];
    } else {
        return NO;
    }
}
- (void)setDontLoadTweakLoader:(bool)dontLoadTweakLoader {
    _info[@"dontLoadTweakLoader"] = [NSNumber numberWithBool:dontLoadTweakLoader];
    [self save];
}

- (bool)doUseLCBundleId {
    if(_info[@"doUseLCBundleId"] != nil) {
        return [_info[@"doUseLCBundleId"] boolValue];
    } else {
        return NO;
    }
}
- (void)setDoUseLCBundleId:(bool)doUseLCBundleId {
    _info[@"doUseLCBundleId"] = [NSNumber numberWithBool:doUseLCBundleId];
    NSString *infoPath = [NSString stringWithFormat:@"%@/Info.plist", self.bundlePath];
    if(doUseLCBundleId) {
        _info[@"LCOrignalBundleIdentifier"] = _infoPlist[@"CFBundleIdentifier"];
        _infoPlist[@"CFBundleIdentifier"] = NSBundle.mainBundle.bundleIdentifier;
    } else if (_info[@"LCOrignalBundleIdentifier"]) {
        _infoPlist[@"CFBundleIdentifier"] = _info[@"LCOrignalBundleIdentifier"];
        [_info removeObjectForKey:@"LCOrignalBundleIdentifier"];
    }
    [_infoPlist writeBinToFile:infoPath atomically:YES];
    [self save];
}

- (bool)fixFilePickerNew {
    if(_info[@"fixFilePickerNew"] != nil) {
        return [_info[@"fixFilePickerNew"] boolValue];
    } else {
        return NO;
    }
}

- (void)setFixFilePickerNew:(bool)fixFilePickerNew {
    _info[@"fixFilePickerNew"] = @(fixFilePickerNew);
    [self save];
}

- (bool)fixLocalNotification {
    if(_info[@"fixLocalNotification"] != nil) {
        return [_info[@"fixLocalNotification"] boolValue];
    } else {
        return NO;
    }
}

- (void)setFixLocalNotification:(bool)fixLocalNotification {
    _info[@"fixLocalNotification"] = @(fixLocalNotification);
    [self save];
}

- (LCOrientationLock)orientationLock {
    return (LCOrientationLock) [((NSNumber*) _info[@"LCOrientationLock"]) intValue];

}
- (void)setOrientationLock:(LCOrientationLock)orientationLock {
    _info[@"LCOrientationLock"] = [NSNumber numberWithInt:(int) orientationLock];
    [self save];
    
}

- (UIColor*)cachedColor {
    if(_info[@"cachedColor"] != nil) {
        NSData *colorData = _info[@"cachedColor"];
        NSError* error;
        UIColor *color = [NSKeyedUnarchiver unarchivedObjectOfClass:UIColor.class fromData:colorData error:&error];
        if (!error) {
            return color;
        } else {
            NSLog(@"[LC] failed to get color %@", error);
            return nil;
        }
    } else {
        return nil;
    }
}

- (void)setCachedColor:(UIColor*) color {
    if(color == nil) {
        _info[@"cachedColor"] = nil;
    } else {
        NSError* error;
        NSData *colorData = [NSKeyedArchiver archivedDataWithRootObject:color requiringSecureCoding:YES error:&error];
        [_info setObject:colorData forKey:@"cachedColor"];
        if(error) {
            NSLog(@"[LC] failed to set color %@", error);
        }

    }
    [self save];
}

- (NSArray<NSDictionary*>* )containerInfo {
    return _info[@"LCContainers"];
}

- (void)setContainerInfo:(NSArray<NSDictionary *> *)containerInfo {
    _info[@"LCContainers"] = containerInfo;
    [self save];
}
#if is32BitSupported
- (bool)is32bit {
    if(_info[@"is32bit"] != nil) {
        return [_info[@"is32bit"] boolValue];
    } else {
        return NO;
    }
}
- (void)setIs32bit:(bool)is32bit {
    _info[@"is32bit"] = [NSNumber numberWithBool:is32bit];
    [self save];
    
}
#endif
- (bool)dontSign {
    if(_info[@"dontSign"] != nil) {
        return [_info[@"dontSign"] boolValue];
    } else {
        return NO;
    }
}
- (void)setDontSign:(bool)dontSign {
    _info[@"dontSign"] = [NSNumber numberWithBool:dontSign];
    [self save];
    
}

- (NSString *)jitLaunchScriptJs {
    return _info[@"jitLaunchScriptJs"];
}

- (void)setJitLaunchScriptJs:(NSString *)jitLaunchScriptJs {
    if (jitLaunchScriptJs.length > 0) {
        _info[@"jitLaunchScriptJs"] = jitLaunchScriptJs;
    } else {
        [_info removeObjectForKey:@"jitLaunchScriptJs"];
    }
    if (!_autoSaveDisabled) [self save];
}

- (bool)spoofSDKVersion {
    if(!_info[@"spoofSDKVersion"]) {
        return false;
    } else {
        return [_info[@"spoofSDKVersion"] unsignedIntValue] != 0;
    }
}

- (void)setSpoofSDKVersion:(bool)doSpoof {
    if(!doSpoof) {
        _info[@"spoofSDKVersion"] = 0;
    } else {
        NSString *execPath = [NSString stringWithFormat:@"%@/%@", _bundlePath, _infoPlist[@"CFBundleExecutable"]];
        __block uint32_t sdkVersion = 0;
        LCParseMachO(execPath.UTF8String, true, ^(const char *path, struct mach_header_64 *header, int fd, void *filePtr) {
            sdkVersion = dyld_get_sdk_version((const struct mach_header *)header);
        });
        NSLog(@"[LC] sdkversion = %8x", sdkVersion);
        _info[@"spoofSDKVersion"] = [NSNumber numberWithUnsignedInt:sdkVersion];
    }
    [self save];
}

- (NSDate*)lastLaunched {
    return _info[@"lastLaunched"];
}

- (void)setLastLaunched:(NSDate*)lastLaunched {
    _info[@"lastLaunched"] = lastLaunched;
    [self save];
}

- (NSDate*)installationDate {
    return _info[@"installationDate"];
}

- (void)setInstallationDate:(NSDate*)installationDate {
    _info[@"installationDate"] = installationDate;
    [self save];
}

@end
