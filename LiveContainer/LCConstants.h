#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#if defined(LC_DEFINE_CONSTANTS)
#define LC_CONST_EXTERN FOUNDATION_EXPORT
#define LC_CONST_VALUE(value) = value
#else
#define LC_CONST_EXTERN FOUNDATION_EXPORT
#define LC_CONST_VALUE(value)
#endif

LC_CONST_EXTERN NSString *const LCUserDefaultSelectedAppKey LC_CONST_VALUE(@"selected");
LC_CONST_EXTERN NSString *const LCUserDefaultSelectedContainerKey LC_CONST_VALUE(@"selectedContainer");
LC_CONST_EXTERN NSString *const LCUserDefaultStrictHidingKey LC_CONST_VALUE(@"LCStrictHiding");
LC_CONST_EXTERN NSString *const LCUserDefaultMultitaskModeKey LC_CONST_VALUE(@"LCMultitaskMode");
LC_CONST_EXTERN NSString *const LCUserDefaultMultitaskBottomWindowBarKey LC_CONST_VALUE(@"LCMultitaskBottomWindowBar");
LC_CONST_EXTERN NSString *const LCUserDefaultLaunchMultitaskMaximizedKey LC_CONST_VALUE(@"LCLaunchMultitaskMaximized");
LC_CONST_EXTERN NSString *const LCUserDefaultLaunchInMultitaskModeKey LC_CONST_VALUE(@"LCLaunchInMultitaskMode");
LC_CONST_EXTERN NSString *const LCMultitaskDisplayNameUserInfoKey LC_CONST_VALUE(@"LCDisplayName");

#undef LC_CONST_EXTERN
#undef LC_CONST_VALUE

NS_ASSUME_NONNULL_END
