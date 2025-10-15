#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXTERN NSString *const LCBundleTransactionErrorDomain;

@interface LCBundleTransaction : NSObject

- (instancetype)initWithBundlePath:(NSString *)bundlePath fileManager:(NSFileManager *)fileManager;

@property (nonatomic, readonly) NSString *originalPath;
@property (nonatomic, readonly, nullable) NSString *workingPath;

- (BOOL)begin:(NSError * _Nullable * _Nullable)error;
- (BOOL)commit:(NSError * _Nullable * _Nullable)error;
- (void)cancel;

@end

NS_ASSUME_NONNULL_END
