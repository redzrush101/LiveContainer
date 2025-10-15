//
//  LCAppError.swift
//  LiveContainerSwiftUI
//
//  Created by factory-droid
//

import Foundation

enum LCAppError: LocalizedError {
    // Installation Errors
    case extractionFailed(underlyingError: Error?)
    case invalidArchive
    case bundleNotFound
    case infoPlistUnreadable
    case appInfoInitFailed
    case invalidURL
    case notAnIPA
    case storageFull
    case duplicateApp
    
    // Signing Errors
    case certificateExpired
    case certificateNotFound
    case certificatePasswordMissing
    case signingFailed(reason: String)
    case bit32NotSupported
    
    // Launch Errors
    case containerNotFound
    case jitNotEnabled
    case jitEnablementFailed
    case appAlreadyRunning
    
    // Multitask Errors
    case multitaskNotAvailable
    case sharedAppRequired
    
    // General Errors
    case unknown(message: String)
    
    var errorDescription: String? {
        switch self {
        // Installation Errors
        case .extractionFailed(let error):
            if let error = error {
                return "lc.error.extractionFailed".loc + "\n\n" + error.localizedDescription
            }
            return "lc.error.extractionFailed".loc
            
        case .invalidArchive:
            return "lc.error.invalidArchive".loc
            
        case .bundleNotFound:
            return "lc.error.bundleNotFound".loc
            
        case .infoPlistUnreadable:
            return "lc.error.infoPlistUnreadable".loc
            
        case .appInfoInitFailed:
            return "lc.error.appInfoInitFailed".loc
            
        case .invalidURL:
            return "lc.error.invalidURL".loc
            
        case .notAnIPA:
            return "lc.error.notAnIPA".loc
            
        case .storageFull:
            return "lc.error.storageFull".loc
            
        case .duplicateApp:
            return "lc.error.duplicateApp".loc
        
        // Signing Errors
        case .certificateExpired:
            return "lc.error.certificateExpired".loc
            
        case .certificateNotFound:
            return "lc.error.certificateNotFound".loc
            
        case .certificatePasswordMissing:
            return "lc.error.certificatePasswordMissing".loc
            
        case .signingFailed(let reason):
            return "lc.error.signingFailed".loc + "\n\n" + reason
            
        case .bit32NotSupported:
            return "lc.error.32bitNotSupported".loc
            
        // Launch Errors
        case .containerNotFound:
            return "lc.error.containerNotFound".loc
            
        case .jitNotEnabled:
            return "lc.error.jitNotEnabled".loc
            
        case .jitEnablementFailed:
            return "lc.error.jitEnablementFailed".loc
            
        case .appAlreadyRunning:
            return "lc.error.appAlreadyRunning".loc
            
        // Multitask Errors
        case .multitaskNotAvailable:
            return "lc.error.multitaskNotAvailable".loc
            
        case .sharedAppRequired:
            return "lc.error.sharedAppRequired".loc
            
        // General
        case .unknown(let message):
            return message
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .storageFull:
            return "lc.error.storageFull.recovery".loc
            
        case .certificateExpired, .certificateNotFound, .certificatePasswordMissing:
            return "lc.error.certificate.recovery".loc
            
        case .jitNotEnabled, .jitEnablementFailed:
            return "lc.error.jit.recovery".loc
            
        case .invalidArchive, .extractionFailed:
            return "lc.error.archive.recovery".loc
            
        case .infoPlistUnreadable, .bundleNotFound:
            return "lc.error.corruptedApp.recovery".loc
            
        case .multitaskNotAvailable:
            return "lc.error.multitask.recovery".loc
            
        case .sharedAppRequired:
            return "lc.error.sharedApp.recovery".loc
            
        default:
            return nil
        }
    }
    
    var failureReason: String? {
        switch self {
        case .extractionFailed:
            return "lc.error.extractionFailed.reason".loc
            
        case .invalidArchive:
            return "lc.error.invalidArchive.reason".loc
            
        case .storageFull:
            return "lc.error.storageFull.reason".loc
            
        case .certificateExpired:
            return "lc.error.certificateExpired.reason".loc
            
        case .certificateNotFound:
            return "lc.error.certificateNotFound.reason".loc
            
        case .jitNotEnabled:
            return "lc.error.jitNotEnabled.reason".loc
            
        case .bit32NotSupported:
            return "lc.error.32bitNotSupported.reason".loc
            
        default:
            return nil
        }
    }
    
    // Helper to convert existing string-based errors
    static func from(string: String) -> LCAppError {
        // Map common error strings to enum cases
        if string.contains("bundleNotFondError") || string.contains("bundle not found") {
            return .bundleNotFound
        } else if string.contains("infoPlistCannotReadError") {
            return .infoPlistUnreadable
        } else if string.contains("appInfoInitError") {
            return .appInfoInitFailed
        } else if string.contains("urlInvalidError") {
            return .invalidURL
        } else if string.contains("urlFileIsNotIpaError") {
            return .notAnIPA
        } else if string.contains("noCertificateFoundErr") {
            return .certificateNotFound
        } else if string.contains("32-bit app is NOT supported") {
            return .bit32NotSupported
        } else if string.contains("ipaExtractionFailed") {
            return .extractionFailed(underlyingError: nil)
        } else {
            return .unknown(message: string)
        }
    }
}

// Extension to convert NSError from Objective-C signing callbacks
extension LCAppError {
    static func signingError(from message: String?) -> LCAppError {
        guard let message = message else {
            return .signingFailed(reason: "Unknown signing error")
        }
        
        if message.contains("noCertificateFoundErr") {
            return .certificateNotFound
        } else if message.contains("certificate") && (message.contains("expired") || message.contains("invalid")) {
            return .certificateExpired
        } else if message.contains("32-bit") {
            return .bit32NotSupported
        } else {
            return .signingFailed(reason: message)
        }
    }
}
