//
//  LCLogger.h
//  LiveContainer
//
//  Structured logging with categories and exportable diagnostics
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, LCLogLevel) {
    LCLogLevelDebug = 0,
    LCLogLevelInfo = 1,
    LCLogLevelWarning = 2,
    LCLogLevelError = 3
};

typedef NS_ENUM(NSInteger, LCLogCategory) {
    LCLogCategoryBootstrap,
    LCLogCategorySigning,
    LCLogCategoryInstallation,
    LCLogCategoryJIT,
    LCLogCategoryMultitask,
    LCLogCategoryTweaks,
    LCLogCategoryGeneral
};

@interface LCLogger : NSObject

/// Shared logger instance
+ (instancetype)shared;

/// Configure log file location (defaults to app group Documents/Logs)
+ (void)configureWithLogDirectory:(nullable NSURL *)logDirectory;

/// Log a message with category and level
+ (void)logWithLevel:(LCLogLevel)level
            category:(LCLogCategory)category
             message:(NSString *)format, ... NS_FORMAT_FUNCTION(3,4);

/// Convenience methods for different log levels
+ (void)debugWithCategory:(LCLogCategory)category message:(NSString *)format, ... NS_FORMAT_FUNCTION(2,3);
+ (void)infoWithCategory:(LCLogCategory)category message:(NSString *)format, ... NS_FORMAT_FUNCTION(2,3);
+ (void)warningWithCategory:(LCLogCategory)category message:(NSString *)format, ... NS_FORMAT_FUNCTION(2,3);
+ (void)errorWithCategory:(LCLogCategory)category message:(NSString *)format, ... NS_FORMAT_FUNCTION(2,3);

/// Export diagnostics as a redacted text file
+ (nullable NSURL *)exportDiagnostics:(NSError **)error NS_SWIFT_NAME(exportDiagnostics());

/// Get current log file URL
+ (nullable NSURL *)currentLogFileURL;

/// Clear all logs
+ (void)clearLogs;

/// Non-variadic wrapper for Swift (logs a single string message)
+ (void)logLevel:(LCLogLevel)level category:(LCLogCategory)category string:(NSString *)message;

/// String representation of category
+ (NSString *)stringForCategory:(LCLogCategory)category;

/// String representation of log level
+ (NSString *)stringForLevel:(LCLogLevel)level;

@end

NS_ASSUME_NONNULL_END
