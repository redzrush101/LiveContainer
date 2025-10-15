//
//  LCLogger.m
//  LiveContainer
//
//  Structured logging implementation
//

#import "LCLogger.h"
#import <UIKit/UIKit.h>

static NSInteger const kMaxLogFileSizeBytes = 5 * 1024 * 1024; // 5MB
static NSInteger const kMaxArchivedLogs = 3;

@interface LCLogger ()
@property (nonatomic, strong) NSFileHandle *logFileHandle;
@property (nonatomic, strong) NSURL *logFileURL;
@property (nonatomic, strong) NSDateFormatter *dateFormatter;
@property (nonatomic, strong) dispatch_queue_t logQueue;
@property (nonatomic, assign) BOOL isEnabled;
@end

@implementation LCLogger

+ (instancetype)shared {
    static LCLogger *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[LCLogger alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _logQueue = dispatch_queue_create("com.livecontainer.logger", DISPATCH_QUEUE_SERIAL);
        _dateFormatter = [[NSDateFormatter alloc] init];
        _dateFormatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
        _isEnabled = YES;
        
        // Setup default log directory
        [self setupLogDirectory:nil];
        
        // Listen for app termination to close file handle
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationWillTerminate:)
                                                     name:UIApplicationWillTerminateNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [self closeLogFile];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

+ (void)configureWithLogDirectory:(NSURL *)logDirectory {
    [[self shared] setupLogDirectory:logDirectory];
}

- (void)setupLogDirectory:(NSURL *)customDirectory {
    dispatch_sync(self.logQueue, ^{
        [self closeLogFile];
        
        NSFileManager *fm = [NSFileManager defaultManager];
        NSURL *logDir;
        
        if (customDirectory) {
            logDir = customDirectory;
        } else {
            // Default to app group Documents/Logs
            NSURL *documentsDir = [[fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject];
            logDir = [documentsDir URLByAppendingPathComponent:@"Logs" isDirectory:YES];
        }
        
        // Create log directory if needed
        NSError *error = nil;
        if (![fm fileExistsAtPath:logDir.path]) {
            [fm createDirectoryAtURL:logDir withIntermediateDirectories:YES attributes:nil error:&error];
            if (error) {
                NSLog(@"[LCLogger] Failed to create log directory: %@", error);
                self.isEnabled = NO;
                return;
            }
        }
        
        // Rotate logs if needed
        [self rotateLogsInDirectory:logDir];
        
        // Create new log file
        NSString *timestamp = [[NSDateFormatter localizedStringFromDate:[NSDate date]
                                                              dateStyle:NSDateFormatterShortStyle
                                                              timeStyle:NSDateFormatterNoStyle] stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
        NSString *fileName = [NSString stringWithFormat:@"LiveContainer_%@.log", timestamp];
        self.logFileURL = [logDir URLByAppendingPathComponent:fileName];
        
        // Create file
        if (![fm fileExistsAtPath:self.logFileURL.path]) {
            [fm createFileAtPath:self.logFileURL.path contents:nil attributes:nil];
        }
        
        // Open file handle
        self.logFileHandle = [NSFileHandle fileHandleForWritingAtPath:self.logFileURL.path];
        if (!self.logFileHandle) {
            NSLog(@"[LCLogger] Failed to open log file for writing");
            self.isEnabled = NO;
            return;
        }
        
        [self.logFileHandle seekToEndOfFile];
        
        // Write header
        NSString *header = [NSString stringWithFormat:@"=== LiveContainer Log Session Started: %@ ===\n",
                           [self.dateFormatter stringFromDate:[NSDate date]]];
        [self writeToFile:header];
    });
}

- (void)rotateLogsInDirectory:(NSURL *)logDir {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;
    NSArray<NSURL *> *logFiles = [fm contentsOfDirectoryAtURL:logDir
                                    includingPropertiesForKeys:@[NSURLCreationDateKey, NSURLFileSizeKey]
                                                       options:NSDirectoryEnumerationSkipsHiddenFiles
                                                         error:&error];
    
    if (error) {
        NSLog(@"[LCLogger] Failed to enumerate log files: %@", error);
        return;
    }
    
    // Filter to .log files and sort by creation date
    NSArray<NSURL *> *sortedLogs = [[logFiles filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSURL *url, NSDictionary *bindings) {
        return [url.pathExtension isEqualToString:@"log"];
    }]] sortedArrayUsingComparator:^NSComparisonResult(NSURL *url1, NSURL *url2) {
        NSDate *date1, *date2;
        [url1 getResourceValue:&date1 forKey:NSURLCreationDateKey error:nil];
        [url2 getResourceValue:&date2 forKey:NSURLCreationDateKey error:nil];
        return [date2 compare:date1]; // Newest first
    }];
    
    // Remove old logs beyond limit
    for (NSInteger i = kMaxArchivedLogs; i < sortedLogs.count; i++) {
        [fm removeItemAtURL:sortedLogs[i] error:nil];
    }
}

- (void)closeLogFile {
    if (self.logFileHandle) {
        @try {
            [self.logFileHandle synchronizeFile];
            [self.logFileHandle closeFile];
        } @catch (NSException *exception) {
            NSLog(@"[LCLogger] Exception closing file: %@", exception);
        }
        self.logFileHandle = nil;
    }
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [self closeLogFile];
}

- (void)writeToFile:(NSString *)message {
    if (!self.logFileHandle || !self.isEnabled) {
        return;
    }
    
    NSData *data = [message dataUsingEncoding:NSUTF8StringEncoding];
    if (data) {
        @try {
            [self.logFileHandle writeData:data];
            
            // Check file size and rotate if needed
            unsigned long long fileSize = [self.logFileHandle offsetInFile];
            if (fileSize > kMaxLogFileSizeBytes) {
                NSURL *logDir = [self.logFileURL URLByDeletingLastPathComponent];
                [self setupLogDirectory:logDir];
            }
        } @catch (NSException *exception) {
            NSLog(@"[LCLogger] Exception writing to file: %@", exception);
        }
    }
}

+ (void)logWithLevel:(LCLogLevel)level category:(LCLogCategory)category message:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    LCLogger *logger = [self shared];
    NSString *timestamp = [logger.dateFormatter stringFromDate:[NSDate date]];
    NSString *levelStr = [self stringForLevel:level];
    NSString *categoryStr = [self stringForCategory:category];
    
    NSString *logLine = [NSString stringWithFormat:@"%@ [%@] [%@] %@\n",
                        timestamp, levelStr, categoryStr, message];
    
    // Write to file asynchronously
    dispatch_async(logger.logQueue, ^{
        [logger writeToFile:logLine];
    });
    
    // Also write to console
    NSLog(@"[%@] [%@] %@", levelStr, categoryStr, message);
}

+ (void)debugWithCategory:(LCLogCategory)category message:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [self logWithLevel:LCLogLevelDebug category:category message:@"%@", message];
}

+ (void)infoWithCategory:(LCLogCategory)category message:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [self logWithLevel:LCLogLevelInfo category:category message:@"%@", message];
}

+ (void)warningWithCategory:(LCLogCategory)category message:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [self logWithLevel:LCLogLevelWarning category:category message:@"%@", message];
}

+ (void)errorWithCategory:(LCLogCategory)category message:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [self logWithLevel:LCLogLevelError category:category message:@"%@", message];
}

+ (NSString *)redactSensitiveData:(NSString *)input {
    NSString *result = input;
    
    // Redact certificate passwords
    NSRegularExpression *passwordRegex = [NSRegularExpression
        regularExpressionWithPattern:@"password[\"']?\\s*[:=]\\s*[\"']?([^\"'\\s,}]+)"
        options:NSRegularExpressionCaseInsensitive
        error:nil];
    result = [passwordRegex stringByReplacingMatchesInString:result
                                                     options:0
                                                       range:NSMakeRange(0, result.length)
                                                withTemplate:@"password: [REDACTED]"];
    
    // Redact certificate data (base64)
    NSRegularExpression *certRegex = [NSRegularExpression
        regularExpressionWithPattern:@"cert(ificate)?[\"']?\\s*[:=]\\s*[\"']?([A-Za-z0-9+/=]{20,})"
        options:NSRegularExpressionCaseInsensitive
        error:nil];
    result = [certRegex stringByReplacingMatchesInString:result
                                                 options:0
                                                   range:NSMakeRange(0, result.length)
                                            withTemplate:@"certificate: [REDACTED]"];
    
    // Redact keychain access tokens
    NSRegularExpression *keychainRegex = [NSRegularExpression
        regularExpressionWithPattern:@"keychain[\"']?\\s*[:=]\\s*[\"']?([^\"'\\s,}]+)"
        options:NSRegularExpressionCaseInsensitive
        error:nil];
    result = [keychainRegex stringByReplacingMatchesInString:result
                                                     options:0
                                                       range:NSMakeRange(0, result.length)
                                                withTemplate:@"keychain: [REDACTED]"];
    
    return result;
}

+ (NSURL *)exportDiagnostics:(NSError **)error {
    LCLogger *logger = [self shared];
    
    // Flush current logs
    dispatch_sync(logger.logQueue, ^{
        [logger.logFileHandle synchronizeFile];
    });
    
    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *logDir = [logger.logFileURL URLByDeletingLastPathComponent];
    
    // Gather all log files
    NSArray<NSURL *> *logFiles = [fm contentsOfDirectoryAtURL:logDir
                                   includingPropertiesForKeys:@[NSURLCreationDateKey]
                                                      options:NSDirectoryEnumerationSkipsHiddenFiles
                                                        error:error];
    
    if (*error) {
        return nil;
    }
    
    // Sort by creation date
    NSArray<NSURL *> *sortedLogs = [[logFiles filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSURL *url, NSDictionary *bindings) {
        return [url.pathExtension isEqualToString:@"log"];
    }]] sortedArrayUsingComparator:^NSComparisonResult(NSURL *url1, NSURL *url2) {
        NSDate *date1, *date2;
        [url1 getResourceValue:&date1 forKey:NSURLCreationDateKey error:nil];
        [url2 getResourceValue:&date2 forKey:NSURLCreationDateKey error:nil];
        return [date1 compare:date2]; // Oldest first
    }];
    
    // Create diagnostics file
    NSString *timestamp = [[logger.dateFormatter stringFromDate:[NSDate date]] stringByReplacingOccurrencesOfString:@" " withString:@"_"];
    NSString *diagnosticsFileName = [NSString stringWithFormat:@"LiveContainer_Diagnostics_%@.txt", timestamp];
    NSURL *tempDir = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
    NSURL *diagnosticsURL = [tempDir URLByAppendingPathComponent:diagnosticsFileName];
    
    // Remove old file if exists
    if ([fm fileExistsAtPath:diagnosticsURL.path]) {
        [fm removeItemAtURL:diagnosticsURL error:nil];
    }
    
    // Create diagnostics file
    [fm createFileAtPath:diagnosticsURL.path contents:nil attributes:nil];
    NSFileHandle *outHandle = [NSFileHandle fileHandleForWritingAtPath:diagnosticsURL.path];
    if (!outHandle) {
        if (error) {
            *error = [NSError errorWithDomain:@"LCLogger" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Failed to create diagnostics file"}];
        }
        return nil;
    }
    
    // Write header
    NSString *header = [NSString stringWithFormat:@"LiveContainer Diagnostics Report\n"];
    header = [header stringByAppendingFormat:@"Generated: %@\n", [logger.dateFormatter stringFromDate:[NSDate date]]];
    header = [header stringByAppendingFormat:@"iOS Version: %@\n", [[UIDevice currentDevice] systemVersion]];
    header = [header stringByAppendingFormat:@"Device: %@\n", [[UIDevice currentDevice] model]];
    header = [header stringByAppendingString:@"\n=== BEGIN LOGS ===\n\n"];
    [outHandle writeData:[header dataUsingEncoding:NSUTF8StringEncoding]];
    
    // Concatenate all log files with redaction
    for (NSURL *logURL in sortedLogs) {
        NSString *logContent = [NSString stringWithContentsOfURL:logURL encoding:NSUTF8StringEncoding error:nil];
        if (logContent) {
            NSString *redacted = [self redactSensitiveData:logContent];
            [outHandle writeData:[redacted dataUsingEncoding:NSUTF8StringEncoding]];
            [outHandle writeData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
        }
    }
    
    // Write footer
    NSString *footer = @"\n=== END LOGS ===\n";
    [outHandle writeData:[footer dataUsingEncoding:NSUTF8StringEncoding]];
    [outHandle synchronizeFile];
    [outHandle closeFile];
    
    return diagnosticsURL;
}

+ (NSURL *)currentLogFileURL {
    return [self shared].logFileURL;
}

+ (void)clearLogs {
    LCLogger *logger = [self shared];
    dispatch_sync(logger.logQueue, ^{
        [logger closeLogFile];
        
        NSFileManager *fm = [NSFileManager defaultManager];
        NSURL *logDir = [logger.logFileURL URLByDeletingLastPathComponent];
        
        NSArray<NSURL *> *logFiles = [fm contentsOfDirectoryAtURL:logDir
                                       includingPropertiesForKeys:nil
                                                          options:NSDirectoryEnumerationSkipsHiddenFiles
                                                            error:nil];
        
        for (NSURL *url in logFiles) {
            if ([url.pathExtension isEqualToString:@"log"]) {
                [fm removeItemAtURL:url error:nil];
            }
        }
        
        [logger setupLogDirectory:logDir];
    });
}

+ (NSString *)stringForCategory:(LCLogCategory)category {
    switch (category) {
        case LCLogCategoryBootstrap: return @"BOOTSTRAP";
        case LCLogCategorySigning: return @"SIGNING";
        case LCLogCategoryInstallation: return @"INSTALL";
        case LCLogCategoryJIT: return @"JIT";
        case LCLogCategoryMultitask: return @"MULTITASK";
        case LCLogCategoryTweaks: return @"TWEAKS";
        case LCLogCategoryGeneral: return @"GENERAL";
    }
}

+ (NSString *)stringForLevel:(LCLogLevel)level {
    switch (level) {
        case LCLogLevelDebug: return @"DEBUG";
        case LCLogLevelInfo: return @"INFO";
        case LCLogLevelWarning: return @"WARNING";
        case LCLogLevelError: return @"ERROR";
    }
}

+ (void)logLevel:(LCLogLevel)level category:(LCLogCategory)category string:(NSString *)message {
    [self logWithLevel:level category:category message:@"%@", message];
}

@end
