//
//  SideStore.swift
//  SideStore
//
//  Created by s s on 2025/7/20.
//

import Foundation
import AppIntents

@available(iOS 17.0, *)
public struct RefreshAllAppsWidgetIntent: AppIntent, ProgressReportingIntent
{
    public static var title: LocalizedStringResource { "Refresh Apps via Widget" }
    public static var isDiscoverable: Bool { false } // Don't show in Shortcuts or Spotlight.
    
    public init() {}
    
    public func perform() async throws -> some IntentResult
    {
        await MainActor.run {
            RefreshHandler.shared.progress = progress
            progress.totalUnitCount = 100
        }
        try await RefreshHandler.shared.startRefresh()
        return .result()
    }
}

@available(iOS 17.0, *)
public struct RefreshAllAppsIntent: AppIntent, CustomIntentMigratedAppIntent, PredictableIntent, ProgressReportingIntent, ForegroundContinuableIntent
{
    public static let intentClassName = "RefreshAllIntent"
    
    public static var title: LocalizedStringResource = "Refresh All Apps"
    public static var description = IntentDescription("Refreshes your sideloaded apps to prevent them from expiring.")
    
    public init() {}
    
    public static var parameterSummary: some ParameterSummary {
        Summary("Refresh All Apps")
    }
    
    public static var predictionConfiguration: some IntentPredictionConfiguration {
        IntentPrediction {
            DisplayRepresentation(
                title: "Refresh All Apps",
                subtitle: ""
            )
        }
    }
    
    public func perform() async throws -> some IntentResult
    {
        await MainActor.run {
            RefreshHandler.shared.progress = progress
            progress.totalUnitCount = 100
        }
        try await RefreshHandler.shared.startRefresh()
        return .result(dialog: "All apps have been refreshed.")
    }
}
@MainActor
class RefreshHandler: NSObject, RefreshServer {
    private final class LaunchTimeoutToken: @unchecked Sendable {
        weak var handler: RefreshHandler?

        init(handler: RefreshHandler) {
            self.handler = handler
        }
    }
    var c: UnsafeContinuation<(), any Error>? = nil
    var launchContinuation: UnsafeContinuation<(), any Error>? = nil
    var progress: Progress? = nil
    var listener: NSXPCListener? = nil
    var sideStorePid: Int32 = 0
    var client: RefreshClient? = nil
    var ext: NSExtension? = nil
    
    private static var _shared: RefreshHandler? = nil
    static var shared: RefreshHandler {
        get {
            if let _shared {
                return _shared
            } else {
                _shared = RefreshHandler()
                return _shared!
            }
        }
    }
    
    
    func startRefresh() async throws {
        if sideStorePid <= 0 || getpgid(sideStorePid) <= 0, let c {
            c.resume(throwing: NSError(domain: "SideStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Built-in SideStore quit unexpectedly"]))
            self.c = nil
        }
        
        if c != nil {
            throw NSError(domain: "SideStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Another refresh task is in progress."])
        }
        
        if listener == nil {
            guard let listener = startAnonymousListener(self) else {
                return
            }
            self.listener = listener
        }
        guard let listener = self.listener else {
            return
        }

        // launch SideStore if it's not running
        if (sideStorePid <= 0 || getpgid(sideStorePid) <= 0) && launchContinuation == nil {
            let lcHome = String(cString:getenv("LC_HOME_PATH"))
            let sideStoreHomeURL = URL(fileURLWithPath: lcHome).appendingPathComponent("Documents/SideStore")
            let bookmarkData = bookmarkForURL(sideStoreHomeURL)!

            // start LiveProcess
            let extensionItem = NSExtensionItem()
            extensionItem.userInfo = [
                LCUserDefaultSelectedAppKey: "builtinSideStore",
                "bookmark": bookmarkData,
                "endpoint": listener.endpoint
            ]

            guard let liveProcessURL = UserDefaults.lcMainBundle().builtInPlugInsURL?.appendingPathComponent("LiveProcess.appex"),
                  let liveProcessBundle = Bundle(url: liveProcessURL)
            else {
                NSLog("Unable to locate LiveProcess bundle")
                return
            }
            
            var ext : NSExtension?
            do {
                ext = try NSExtension(identifier: liveProcessBundle.bundleIdentifier)
            } catch {
                NSLog("Failed to start extension \(error)")
            }
            guard let ext else {
                return
            }
            self.ext = ext
            
            ext.setRequestInterruptionBlock { uuid in
                self.c?.resume(throwing: NSError(domain: "SideStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Built-in SideStore quit unexpectedly"]))
                self.c = nil
                self.sideStorePid = 0
                self.launchContinuation = nil
            }
            
            let uuid = await ext.beginRequest(withInputItems: [extensionItem])
            sideStorePid = ext.pid(forRequestIdentifier: uuid)

            try await withUnsafeThrowingContinuation { (continuation: UnsafeContinuation<Void, any Error>) in
                self.launchContinuation = continuation
                let timeoutToken = LaunchTimeoutToken(handler: self)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    Task { @MainActor in
                        guard let handler = timeoutToken.handler else { return }
                        handler.handleLaunchTimeout()
                    }
                }
            }
        }
        self.client?.refreshAllApps()
        
        try await withUnsafeThrowingContinuation { c in
            self.c = c
        }
        
    }

    private func handleLaunchTimeout() {
        guard let pending = launchContinuation else { return }
        pending.resume(throwing: NSError(domain: "SideStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Built-in SideStore failed to start in reasonable time"]))
        launchContinuation = nil
        ext?._kill(9)
    }
    
    nonisolated func updateProgress(_ value: Double) {
        MainActor.assumeIsolated {
            progress?.completedUnitCount = Int64(value*100)
        }
    }
    
    nonisolated func finish(_ error: String?) {
        MainActor.assumeIsolated {
            if let error {
                c?.resume(throwing: NSError(domain: "SideStore", code: 1, userInfo: [NSLocalizedDescriptionKey: error]))
                c = nil
            } else {
                c?.resume()
                c = nil
            }
        }
    }
    
    nonisolated func onConnection(_ connection: NSXPCConnection!) {
        MainActor.assumeIsolated {
            connection.remoteObjectInterface = NSXPCInterface(with: RefreshClient.self)
            client = connection.remoteObjectProxy as? RefreshClient
        }
    }
    
    nonisolated func finishedLaunching() {
        MainActor.assumeIsolated {
            launchContinuation?.resume()
            launchContinuation = nil
        }
    }
    
}


