//
//  LCLoggerSwift.swift
//  LiveContainerSwiftUI
//
//  Swift-friendly wrappers for LCLogger
//

import Foundation

extension LCLogger {
    static func debug(category: LCLogCategory, _ message: String) {
        LCLogger.logLevel(.debug, category: category, string: message)
    }
    
    static func info(category: LCLogCategory, _ message: String) {
        LCLogger.logLevel(.info, category: category, string: message)
    }
    
    static func warning(category: LCLogCategory, _ message: String) {
        LCLogger.logLevel(.warning, category: category, string: message)
    }
    
    static func error(category: LCLogCategory, _ message: String) {
        LCLogger.logLevel(.error, category: category, string: message)
    }
}
