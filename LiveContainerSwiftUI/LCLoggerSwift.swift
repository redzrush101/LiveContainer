//
//  LCLoggerSwift.swift
//  LiveContainerSwiftUI
//
//  Swift-friendly wrappers for LCLogger
//

import Foundation

extension LCLogger {
    static func debug(category: LCLogCategory, _ message: String) {
        LCLogger.log(withLevel: .debug, category: category, message: "%@", message)
    }
    
    static func info(category: LCLogCategory, _ message: String) {
        LCLogger.log(withLevel: .info, category: category, message: "%@", message)
    }
    
    static func warning(category: LCLogCategory, _ message: String) {
        LCLogger.log(withLevel: .warning, category: category, message: "%@", message)
    }
    
    static func error(category: LCLogCategory, _ message: String) {
        LCLogger.log(withLevel: .error, category: category, message: "%@", message)
    }
}
