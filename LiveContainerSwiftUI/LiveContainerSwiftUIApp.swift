//
//  LiveContainerSwiftUIApp.swift
//  LiveContainer
//
//  Created by s s on 2025/5/16.
//
import SwiftUI

@main
struct LiveContainerSwiftUIApp : SwiftUI.App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    @State var appDataFolderNames: [String] = []
    @State var tweakFolderNames: [String] = []
    @State var isLoading = true
    
    init() {
        // Initialization is now minimal - actual loading happens asynchronously in body
    }
    
    @MainActor
    private func loadAppCatalog() async {
        // Perform heavy directory scanning off the main thread
        let result = await Task.detached(priority: .userInitiated) {
            let fm = FileManager()
            var tempAppDataFolderNames: [String] = []
            var tempTweakFolderNames: [String] = []
            var tempApps: [LCAppModel] = []
            var tempHiddenApps: [LCAppModel] = []
            
            do {
                // Load apps from local directory
                try fm.createDirectory(at: LCPath.bundlePath, withIntermediateDirectories: true)
                let appDirs = try fm.contentsOfDirectory(atPath: LCPath.bundlePath.path)
                for appDir in appDirs {
                    if !appDir.hasSuffix(".app") {
                        continue
                    }
                    guard let newApp = LCAppInfo(bundlePath: "\(LCPath.bundlePath.path)/\(appDir)") else {
                        continue
                    }
                    newApp.relativeBundlePath = appDir
                    newApp.isShared = false
                    if newApp.isHidden {
                        tempHiddenApps.append(LCAppModel(appInfo: newApp))
                    } else {
                        tempApps.append(LCAppModel(appInfo: newApp))
                    }
                }
                
                // Load apps from shared directory
                if LCPath.lcGroupDocPath != LCPath.docPath {
                    try fm.createDirectory(at: LCPath.lcGroupBundlePath, withIntermediateDirectories: true)
                    let appDirsShared = try fm.contentsOfDirectory(atPath: LCPath.lcGroupBundlePath.path)
                    for appDir in appDirsShared {
                        if !appDir.hasSuffix(".app") {
                            continue
                        }
                        guard let newApp = LCAppInfo(bundlePath: "\(LCPath.lcGroupBundlePath.path)/\(appDir)") else {
                            continue
                        }
                        newApp.relativeBundlePath = appDir
                        newApp.isShared = true
                        if newApp.isHidden {
                            tempHiddenApps.append(LCAppModel(appInfo: newApp))
                        } else {
                            tempApps.append(LCAppModel(appInfo: newApp))
                        }
                    }
                }
                
                // Load document folders
                try fm.createDirectory(at: LCPath.dataPath, withIntermediateDirectories: true)
                let dataDirs = try fm.contentsOfDirectory(atPath: LCPath.dataPath.path)
                for dataDir in dataDirs {
                    let dataDirUrl = LCPath.dataPath.appendingPathComponent(dataDir)
                    if !dataDirUrl.hasDirectoryPath {
                        continue
                    }
                    tempAppDataFolderNames.append(dataDir)
                }
                
                // Load tweak folders
                try fm.createDirectory(at: LCPath.tweakPath, withIntermediateDirectories: true)
                let tweakDirs = try fm.contentsOfDirectory(atPath: LCPath.tweakPath.path)
                for tweakDir in tweakDirs {
                    let tweakDirUrl = LCPath.tweakPath.appendingPathComponent(tweakDir)
                    if !tweakDirUrl.hasDirectoryPath {
                        continue
                    }
                    tempTweakFolderNames.append(tweakDir)
                }
            } catch {
                NSLog("[LC] error:\(error)")
            }
            
            return (tempApps, tempHiddenApps, tempAppDataFolderNames, tempTweakFolderNames)
        }.value
        
        // Update state on main actor
        DataManager.shared.model.apps = result.0
        DataManager.shared.model.hiddenApps = result.1
        appDataFolderNames = result.2
        tweakFolderNames = result.3
        isLoading = false
    }
    
    var body: some Scene {
        WindowGroup(id: "Main") {
            Group {
                if isLoading {
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("lc.app.loading".loc)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    LCTabView(appDataFolderNames: $appDataFolderNames, tweakFolderNames: $tweakFolderNames)
                        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
                        .environmentObject(DataManager.shared.model)
                        .environmentObject(LCAppSortManager.shared)
                        .environmentObject(SceneDelegate.shared ?? SceneDelegate())
                }
            }
            .task {
                if isLoading {
                    await loadAppCatalog()
                }
            }
        }
        
        if UIApplication.shared.supportsMultipleScenes, #available(iOS 16.1, *) {
            WindowGroup(id: "appView", for: String.self) { $id in
                if let id {
                    MultitaskAppWindow(id: id)
                        .environmentObject(SceneDelegate.shared ?? SceneDelegate())
                }
            }

        }
    }
    
}
