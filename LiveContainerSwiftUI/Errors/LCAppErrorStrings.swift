//
//  LCAppErrorStrings.swift
//  LiveContainerSwiftUI
//
//  Localization strings for LCAppError
//

import Foundation

// This file provides fallback English strings for all error messages
// These will be used if no localization is available for the user's language

extension String {
    static let errorStrings: [String: String] = [
        // Installation errors
        "lc.error.extractionFailed": "Failed to extract IPA archive",
        "lc.error.extractionFailed.reason": "The archive may be corrupted or use unsupported compression",
        "lc.error.invalidArchive": "Invalid or corrupted IPA file",
        "lc.error.invalidArchive.reason": "The file is not a valid iOS application archive",
        "lc.error.bundleNotFound": "App bundle not found in archive",
        "lc.error.infoPlistUnreadable": "Cannot read app Info.plist",
        "lc.error.appInfoInitFailed": "Failed to initialize app information",
        "lc.error.invalidURL": "Invalid URL",
        "lc.error.notAnIPA": "File is not an IPA",
        "lc.error.storageFull": "Insufficient storage space",
        "lc.error.storageFull.reason": "Not enough free space to install this app",
        "lc.error.storageFull.recovery": "Free up storage space by deleting unused apps or data, then try again",
        "lc.error.duplicateApp": "App is already installed",
        
        // Signing errors
        "lc.error.certificateExpired": "Signing certificate has expired",
        "lc.error.certificateExpired.reason": "Your development certificate is no longer valid",
        "lc.error.certificateNotFound": "No signing certificate found",
        "lc.error.certificateNotFound.reason": "Import a certificate from AltStore or SideStore to enable JIT-less mode",
        "lc.error.certificatePasswordMissing": "Certificate password not available",
        "lc.error.signingFailed": "Code signing failed",
        "lc.error.certificate.recovery": "Go to Settings → JIT-less Mode to import or refresh your certificate",
        "lc.error.32bitNotSupported": "32-bit apps are not supported",
        "lc.error.32bitNotSupported.reason": "This device or iOS version cannot run 32-bit applications",
        
        // Launch errors
        "lc.error.containerNotFound": "App data container not found",
        "lc.error.jitNotEnabled": "JIT is not enabled",
        "lc.error.jitNotEnabled.reason": "This app requires JIT compilation to run",
        "lc.error.jitEnablementFailed": "Failed to enable JIT",
        "lc.error.jit.recovery": "Go to Settings → JIT Enabler to configure JIT, or set up JIT-less mode instead",
        "lc.error.appAlreadyRunning": "App is already running",
        
        // Multitask errors
        "lc.error.multitaskNotAvailable": "Multitasking is not available",
        "lc.error.multitask.recovery": "Enable multitasking in Settings, or ensure you're on a compatible device",
        "lc.error.sharedAppRequired": "App must be in shared folder for multitasking",
        "lc.error.sharedApp.recovery": "Move this app to the shared folder to use multitasking features",
        
        // Recovery suggestions
        "lc.error.archive.recovery": "Try downloading the IPA again, or use a different source",
        "lc.error.corruptedApp.recovery": "The app may be corrupted. Try reinstalling it"
    ]
}
