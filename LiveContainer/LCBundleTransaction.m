#import "LCBundleTransaction.h"

NSString *const LCBundleTransactionErrorDomain = @"LCBundleTransaction";

@interface LCBundleTransaction ()

@property (nonatomic, readonly) NSFileManager *fileManager;
@property (nonatomic, readwrite, nullable) NSString *workingPath;
@property (nonatomic, readwrite) BOOL active;

@end

@implementation LCBundleTransaction

- (instancetype)initWithBundlePath:(NSString *)bundlePath fileManager:(NSFileManager *)fileManager {
    self = [super init];
    if (self) {
        _originalPath = [bundlePath copy];
        _fileManager = fileManager ?: NSFileManager.defaultManager;
    }
    return self;
}

- (BOOL)begin:(NSError **)error {
    if (self.active) {
        return YES;
    }

    NSString *uuid = [NSUUID UUID].UUIDString;
    NSString *tempRoot = NSTemporaryDirectory() ?: @"/tmp";
    NSString *workingPath = [tempRoot stringByAppendingPathComponent:[NSString stringWithFormat:@"LCBundleTransaction-%@", uuid]];

    if ([self.fileManager fileExistsAtPath:workingPath]) {
        [self.fileManager removeItemAtPath:workingPath error:nil];
    }

    if (![self.fileManager copyItemAtPath:self.originalPath toPath:workingPath error:error]) {
        return NO;
    }

    self.workingPath = workingPath;
    self.active = YES;
    return YES;
}

- (BOOL)commit:(NSError **)error {
    if (!self.active) {
        return YES;
    }

    NSString *backupPath = [self.originalPath stringByAppendingString:@".lctxn"];

    if (backupPath && [self.fileManager fileExistsAtPath:backupPath]) {
        [self.fileManager removeItemAtPath:backupPath error:nil];
    }

    NSError *moveError = nil;
    if ([self.fileManager fileExistsAtPath:self.originalPath]) {
        if (![self.fileManager moveItemAtPath:self.originalPath toPath:backupPath error:&moveError]) {
            if (error) {
                *error = moveError;
            }
            [self cancel];
            return NO;
        }
    }

    if (![self.fileManager moveItemAtPath:self.workingPath toPath:self.originalPath error:&moveError]) {
        if ([self.fileManager fileExistsAtPath:backupPath]) {
            [self.fileManager moveItemAtPath:backupPath toPath:self.originalPath error:nil];
        }
        if (error) {
            *error = moveError;
        }
        [self cancel];
        return NO;
    }

    if ([self.fileManager fileExistsAtPath:backupPath]) {
        [self.fileManager removeItemAtPath:backupPath error:nil];
    }

    self.active = NO;
    self.workingPath = nil;
    return YES;
}

- (void)cancel {
    if (self.workingPath && [self.fileManager fileExistsAtPath:self.workingPath]) {
        [self.fileManager removeItemAtPath:self.workingPath error:nil];
    }
    self.workingPath = nil;
    self.active = NO;
}

@end
