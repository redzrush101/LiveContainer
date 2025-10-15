//
//  TabView.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/8/21.
//

import Foundation
import SwiftUI

struct LCTabView: View {
    @Binding var appDataFolderNames: [String]
    @Binding var tweakFolderNames: [String]
    
    @State var errorShow = false
    @State var errorInfo = ""
    
    @EnvironmentObject var sharedModel : SharedModel
    @EnvironmentObject var sceneDelegate: SceneDelegate
    @State var shouldToggleMainWindowOpen = false
    @Environment(\.scenePhase) var scenePhase
    let pub = NotificationCenter.default.publisher(for: UIScene.didDisconnectNotification)
    @StateObject private var searchContext = SearchContext()
    
    var body: some View {
        Group {
            if #available(iOS 19.0, *), SharedModel.isLiquidGlassSearchEnabled {
                TabView {
                    Tab("lc.tabView.apps".loc, systemImage: "square.stack.3d.up.fill") {
                        LCAppListView(appDataFolderNames: $appDataFolderNames, tweakFolderNames: $tweakFolderNames, searchContext: searchContext)
                    }
                    if DataManager.shared.model.multiLCStatus != 2 {
                        Tab("lc.tabView.tweaks".loc, systemImage: "wrench.and.screwdriver") {
                            LCTweaksView(tweakFolders: $tweakFolderNames)
                        }
                    }
                    Tab("lc.tabView.settings".loc, systemImage: "gearshape.fill") {
                        LCSettingsView(appDataFolderNames: $appDataFolderNames)
                    }
                    Tab("Search".loc, systemImage: "magnifyingglass", role: .search) {
                        LCAppListView(appDataFolderNames: $appDataFolderNames, tweakFolderNames: $tweakFolderNames, searchContext: searchContext)
                            .searchable(text: $searchContext.query)
                    }
                }
            } else {
                TabView {
                    LCAppListView(appDataFolderNames: $appDataFolderNames, tweakFolderNames: $tweakFolderNames, searchContext: searchContext)
                        .tabItem {
                            Label("lc.tabView.apps".loc, systemImage: "square.stack.3d.up.fill")
                        }
                    if DataManager.shared.model.multiLCStatus != 2 {
                        LCTweaksView(tweakFolders: $tweakFolderNames)
                            .tabItem{
                                Label("lc.tabView.tweaks".loc, systemImage: "wrench.and.screwdriver")
                            }
                    }
                    
                    LCSettingsView(appDataFolderNames: $appDataFolderNames)
                        .tabItem {
                            Label("lc.tabView.settings".loc, systemImage: "gearshape.fill")
                        }
                }
            }
        }
        .alert("lc.common.error".loc, isPresented: $errorShow){
            Button("lc.common.ok".loc, action: {
            })
            Button("lc.common.copy".loc, action: {
                copyError()
            })
        } message: {
            Text(errorInfo)
        }
        .onAppear() {
            closeDuplicatedWindow()
            checkLastLaunchError()
            checkTeamId()
            checkBundleId()
            checkGetTaskAllow()
        }
        .onReceive(pub) { out in
            if let scene1 = sceneDelegate.window?.windowScene, let scene2 = out.object as? UIWindowScene, scene1 == scene2 {
                if shouldToggleMainWindowOpen {
                    DataManager.shared.model.mainWindowOpened = false
                }
            }
        }
    }
    
    func closeDuplicatedWindow() {
        if let session = sceneDelegate.window?.windowScene?.session, DataManager.shared.model.mainWindowOpened {
            UIApplication.shared.requestSceneSessionDestruction(session, options: nil) { e in
                print(e)
            }
        } else {
            shouldToggleMainWindowOpen = true
        }
        DataManager.shared.model.mainWindowOpened = true
    }
    
    func checkLastLaunchError() {
        var errorStr = UserDefaults.standard.string(forKey: "error")
        
        if errorStr == nil && UserDefaults.standard.bool(forKey: "SigningInProgress") {
            errorStr = "lc.signer.crashDuringSignErr".loc
            UserDefaults.standard.removeObject(forKey: "SigningInProgress")
        }
        
        guard let errorStr else {
            return
        }
        UserDefaults.standard.removeObject(forKey: "error")
        errorInfo = errorStr
        errorShow = true
    }
    
    func copyError() {
        UIPasteboard.general.string = errorInfo
    }
    
    func checkTeamId() {
        if let certificateTeamId = UserDefaults.standard.string(forKey: "LCCertificateTeamId") {
            if DataManager.shared.model.multiLCStatus != 2 {
                return
            }
            
            guard let primaryLCTeamId = Bundle.main.infoDictionary?["PrimaryLiveContainerTeamId"] as? String else {
                print("Unable to find PrimaryLiveContainerTeamId")
                return
            }
            if certificateTeamId != primaryLCTeamId {
                errorInfo = "lc.settings.multiLC.teamIdMismatch".loc
                errorShow = true
                return
            }
            return
        }
        
        guard let currentTeamId = LCUtils.teamIdentifier() else {
            print("Failed to determine team id.")
            return
        }
        
        if DataManager.shared.model.multiLCStatus == 2 {
            guard let primaryLCTeamId = Bundle.main.infoDictionary?["PrimaryLiveContainerTeamId"] as? String else {
                print("Unable to find PrimaryLiveContainerTeamId")
                return
            }
            if currentTeamId != primaryLCTeamId {
                errorInfo = "lc.settings.multiLC.teamIdMismatch".loc
                errorShow = true
                return
            }
        }
        UserDefaults.standard.set(currentTeamId, forKey: "LCCertificateTeamId")
    }
    
    func checkBundleId() {
        if UserDefaults.standard.bool(forKey: "LCBundleIdChecked") {
            return
        }
        
        let task = SecTaskCreateFromSelf(nil)
        guard let value = SecTaskCopyValueForEntitlement(task, "application-identifier" as CFString, nil), let appIdentifier = value.takeRetainedValue() as? String else {
            errorInfo = "Unable to determine application-identifier"
            errorShow = true
            return
        }
        
        guard let bundleId = Bundle.main.bundleIdentifier else {
            return
        }
        
        var correctBundleId = ""
        if appIdentifier.count > 11 {
            let startIndex = appIdentifier.index(appIdentifier.startIndex, offsetBy: 11)
            correctBundleId = String(appIdentifier[startIndex...])
        }
        
        if(bundleId != correctBundleId) {
            errorInfo = "lc.settings.bundleIdMismatch %@ %@".localizeWithFormat(bundleId, correctBundleId)
            errorShow = true
        }
        UserDefaults.standard.set(true, forKey: "LCBundleIdChecked")
    }
    
    func checkGetTaskAllow() {
        let task = SecTaskCreateFromSelf(nil)
        guard let value = SecTaskCopyValueForEntitlement(task, "get-task-allow" as CFString, nil), (value.takeRetainedValue() as? NSNumber)?.boolValue ?? false else {
            errorInfo = "lc.settings.notDevCert".loc
            errorShow = true
            return
        }
    }
}
