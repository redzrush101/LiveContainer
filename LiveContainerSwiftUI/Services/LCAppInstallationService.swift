//
//  LCAppInstallationService.swift
//  LiveContainerSwiftUI
//
//  Created by factory-droid.
//

import Foundation

struct AppReplaceOption: Hashable {
    let isReplace: Bool
    let nameOfFolderToInstall: String
    let appToReplace: LCAppModel?
}

struct LCAppInstallationResult {
    let appInfo: LCAppInfo
    let replacedApp: LCAppModel?
    let signingError: LCAppError?
}

protocol LCAppInstallationServicing {
    typealias DuplicateAppsProvider = @Sendable (_ bundleIdentifier: String) async throws -> [LCAppModel]
    typealias ReplaceDecisionHandler = @Sendable (_ options: [AppReplaceOption]) async -> AppReplaceOption?
    typealias ProgressHandler = @Sendable (_ value: Double) -> Void
    typealias ShouldSkipSigningHandler = @Sendable (_ option: AppReplaceOption?) -> Bool

    func installIPA(from url: URL,
                    shouldDeleteSourceAfterInstall: Bool,
                    duplicatesProvider: @escaping DuplicateAppsProvider,
                    replacementDecider: @escaping ReplaceDecisionHandler,
                    shouldSkipSigning: @escaping ShouldSkipSigningHandler,
                    progressHandler: @escaping ProgressHandler) async throws -> LCAppInstallationResult
}

final class LCAppInstallationService: LCAppInstallationServicing {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func installIPA(from url: URL,
                    shouldDeleteSourceAfterInstall: Bool,
                    duplicatesProvider: @escaping DuplicateAppsProvider,
                    replacementDecider: @escaping ReplaceDecisionHandler,
                    shouldSkipSigning: @escaping ShouldSkipSigningHandler,
                    progressHandler: @escaping ProgressHandler) async throws -> LCAppInstallationResult {

        LCLogger.info(category: .installation, "Starting installation from: \(url.lastPathComponent)")

        let installProgress = Progress.discreteProgress(totalUnitCount: 100)
        let progressObservation = installProgress.observe(\.fractionCompleted, options: [.initial, .new]) { progress, _ in
            progressHandler(progress.fractionCompleted)
        }

        defer {
            progressObservation.invalidate()
            progressHandler(1.0)
        }

        let decompressProgress = Progress.discreteProgress(totalUnitCount: 100)
        installProgress.addChild(decompressProgress, withPendingUnitCount: 80)

        let payloadPath = fileManager.temporaryDirectory.appendingPathComponent("Payload")
        if fileManager.fileExists(atPath: payloadPath.path) {
            try? fileManager.removeItem(at: payloadPath)
        }

        defer {
            try? fileManager.removeItem(at: payloadPath)
        }

        try await decompressIPA(at: url.path, destination: fileManager.temporaryDirectory.path, progress: decompressProgress)

        let payloadContents = try fileManager.contentsOfDirectory(atPath: payloadPath.path)
        guard let appBundleName = payloadContents.first(where: { $0.hasSuffix(".app") }) else {
            LCLogger.error(category: .installation, "Bundle not found inside payload for: \(url.lastPathComponent)")
            throw LCAppError.bundleNotFound
        }

        let appFolderPath = payloadPath.appendingPathComponent(appBundleName)
        guard let newAppInfo = LCAppInfo(bundlePath: appFolderPath.path) else {
            LCLogger.error(category: .installation, "Unable to initialise LCAppInfo for: \(url.lastPathComponent)")
            throw LCAppError.appInfoInitFailed
        }

        let bundleIdentifier = newAppInfo.bundleIdentifier() ?? ""
        var appRelativePath = "\(bundleIdentifier).app"
        var outputFolder = LCPath.bundlePath.appendingPathComponent(appRelativePath)

        var appToReplace: LCAppModel?
        var chosenInstallOption: AppReplaceOption?

        let duplicates = try await duplicatesProvider(bundleIdentifier)

        if fileManager.fileExists(atPath: outputFolder.path) || !duplicates.isEmpty {
            appRelativePath = "\(bundleIdentifier)_\(Int(CFAbsoluteTimeGetCurrent())).app"

            var installOptions: [AppReplaceOption] = [
                AppReplaceOption(isReplace: false, nameOfFolderToInstall: appRelativePath, appToReplace: nil)
            ]

            for app in duplicates {
                installOptions.append(AppReplaceOption(isReplace: true,
                                                       nameOfFolderToInstall: app.appInfo.relativeBundlePath,
                                                       appToReplace: app))
            }

            guard let chosenOption = await replacementDecider(installOptions) else {
                LCLogger.info(category: .installation, "Installation cancelled by user for bundle: \(bundleIdentifier)")
                throw CancellationError()
            }

            chosenInstallOption = chosenOption
            appToReplace = chosenOption.appToReplace
            appRelativePath = chosenOption.nameOfFolderToInstall
            if chosenOption.isReplace {
                if let appToReplace, appToReplace.uiIsShared {
                    outputFolder = LCPath.lcGroupBundlePath.appendingPathComponent(appRelativePath)
                } else {
                    outputFolder = LCPath.bundlePath.appendingPathComponent(appRelativePath)
                }
                if fileManager.fileExists(atPath: outputFolder.path) {
                    try fileManager.removeItem(at: outputFolder)
                }
            } else {
                outputFolder = LCPath.bundlePath.appendingPathComponent(appRelativePath)
            }
        }

        try fileManager.moveItem(at: appFolderPath, to: outputFolder)

        guard let finalNewApp = LCAppInfo(bundlePath: outputFolder.path) else {
            LCLogger.error(category: .installation, "Failed to create LCAppInfo for moved app at: \(outputFolder.path)")
            throw LCAppError.appInfoInitFailed
        }
        finalNewApp.relativeBundlePath = appRelativePath

        if shouldSkipSigning(chosenInstallOption) {
            finalNewApp.dontSign = true
        }

        let signingResult = await performSigning(for: finalNewApp,
                                                 installProgress: installProgress)

        if let appToReplace {
            copyConfiguration(from: appToReplace.appInfo, to: finalNewApp)
        } else {
            finalNewApp.spoofSDKVersion = true
        }
        finalNewApp.installationDate = Date.now

        if shouldDeleteSourceAfterInstall {
            try? fileManager.removeItem(at: url)
        }

        LCLogger.info(category: .installation, "Installation finished for: \(finalNewApp.displayName())")

        return LCAppInstallationResult(appInfo: finalNewApp,
                                       replacedApp: appToReplace,
                                       signingError: signingResult)
    }

    private func performSigning(for appInfo: LCAppInfo,
                                installProgress: Progress) async -> LCAppError? {
        var signingError: LCAppError?

        await withCheckedContinuation { continuation in
            appInfo.patchExecAndSignIfNeed(completionHandler: { success, errorMessage in
                if !success {
                    if let errorMessage {
                        signingError = LCAppError.signingError(from: errorMessage)
                        LCLogger.error(category: .signing, "Signing failed: \(errorMessage)")
                    } else {
                        signingError = .signingFailed(reason: "Unknown signing error")
                        LCLogger.error(category: .signing, "Signing failed without error message")
                    }
                }
                continuation.resume()
            }, progressHandler: { signProgress in
                if let signProgress {
                    installProgress.addChild(signProgress, withPendingUnitCount: 20)
                }
            }, forceSign: false)
        }

        return signingError
    }

    private func copyConfiguration(from source: LCAppInfo, to destination: LCAppInfo) {
        destination.autoSaveDisabled = true
        destination.isLocked = source.isLocked
        destination.isHidden = source.isHidden
        destination.isJITNeeded = source.isJITNeeded
        destination.isShared = source.isShared
        destination.spoofSDKVersion = source.spoofSDKVersion
        destination.doSymlinkInbox = source.doSymlinkInbox
        destination.containerInfo = source.containerInfo
        destination.tweakFolder = source.tweakFolder
        destination.selectedLanguage = source.selectedLanguage
        destination.dataUUID = source.dataUUID
        destination.orientationLock = source.orientationLock
        destination.dontInjectTweakLoader = source.dontInjectTweakLoader
        destination.hideLiveContainer = source.hideLiveContainer
        destination.dontLoadTweakLoader = source.dontLoadTweakLoader
        destination.doUseLCBundleId = source.doUseLCBundleId
        destination.fixFilePickerNew = source.fixFilePickerNew
        destination.fixLocalNotification = source.fixLocalNotification
        destination.lastLaunched = source.lastLaunched
        destination.autoSaveDisabled = false
        destination.save()
    }

    private func decompressIPA(at path: String, destination: String, progress: Progress) async throws {
        try await Task.detached(priority: .utility) {
            let result = extract(path, destination, progress)
            if result != 0 {
                throw LCAppError.extractionFailed(underlyingError: nil)
            }
        }.value
    }
}
