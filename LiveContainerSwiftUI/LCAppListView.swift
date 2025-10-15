//
//  ContentView.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/8/21.
//

import SwiftUI
import UniformTypeIdentifiers

struct LCAppListView : View, LCAppBannerDelegate, LCAppModelDelegate {
    @Binding var appDataFolderNames: [String]
    @Binding var tweakFolderNames: [String]
    @ObservedObject var searchContext: SearchContext
    
    @State var didAppear = false
    // ipa choosing stuff
    @State var choosingIPA = false
    @State var errorShow = false
    @State var errorInfo = ""
    
    // ipa installing stuff
    @State var installprogressVisible = false
    @State var installProgressPercentage : Float = 0.0
    
    @State var installOptions: [AppReplaceOption]
    @StateObject var installReplaceAlert = AlertHelper<AppReplaceOption>()
    
    @State var webViewOpened = false
    @State var webViewURL : URL = URL(string: "about:blank")!
    @StateObject private var webViewUrlInput = InputHelper()
    
    @ObservedObject var downloadHelper = DownloadHelper()
    @StateObject private var installUrlInput = InputHelper()
    
    @State private var jitLog = ""
    @StateObject private var jitAlert = YesNoHelper()
    
    @StateObject private var runWhenMultitaskAlert = YesNoHelper()
    
    @State var safariViewOpened = false
    @State var safariViewURL = URL(string: "https://google.com")!
    
    @State private var navigateTo : AnyView?
    @State private var isNavigationActive = false
    
    @State private var helpPresent = false
    
    @State private var customSortViewPresent = false
    
    @EnvironmentObject private var sharedModel : SharedModel
    @EnvironmentObject private var sharedAppSortManager : LCAppSortManager
    
    @StateObject private var viewModel = AppListViewModel()
    private let installationService: LCAppInstallationServicing
    
    @AppStorage(LCUserDefaultMultitaskModeKey, store: LCUtils.appGroupUserDefault) var multitaskMode: MultitaskMode = .virtualWindow
    @AppStorage(LCUserDefaultLaunchInMultitaskModeKey) var launchInMultitaskMode = false
    var sortedApps: [LCAppModel] {
        return sharedAppSortManager.sortedApps
    }
    
    var sortedHiddenApps: [LCAppModel] {
        return sharedAppSortManager.sortedHiddenApps
    }
    
    var filteredApps: [LCAppModel] {
        viewModel.filteredApps(from: sortedApps, searchContext: searchContext)
    }
    
    var filteredHiddenApps: [LCAppModel] {
        viewModel.filteredHiddenApps(from: sortedHiddenApps, isHiddenUnlocked: sharedModel.isHiddenAppUnlocked, searchContext: searchContext)
    }
    
    init(appDataFolderNames: Binding<[String]>,
         tweakFolderNames: Binding<[String]>,
         searchContext: SearchContext,
         installationService: LCAppInstallationServicing = LCAppInstallationService()) {
        _installOptions = State(initialValue: [])
        _appDataFolderNames = appDataFolderNames
        _tweakFolderNames = tweakFolderNames
        _searchContext = ObservedObject(wrappedValue: searchContext)
        self.installationService = installationService
    }
    
    var body: some View {
        navigationContainer
            .navigationViewStyle(StackNavigationViewStyle())
            .alert("lc.common.error".loc, isPresented: $errorShow){
            Button("lc.common.ok".loc, action: {
            })
            Button("lc.common.copy".loc, action: {
                copyError()
            })
        } message: {
            Text(errorInfo)
        }
        .betterFileImporter(isPresented: $choosingIPA, types: [.ipa, .tipa], multiple: false, callback: { fileUrls in
            Task { await startInstallApp(fileUrls[0]) }
        }, onDismiss: {
            choosingIPA = false
        })
        .alert("lc.appList.installation".loc, isPresented: $installReplaceAlert.show) {
            ForEach(installOptions, id: \.self) { installOption in
                Button(role: installOption.isReplace ? .destructive : nil, action: {
                    installReplaceAlert.close(result: installOption)
                }, label: {
                    Text(installOption.isReplace ? installOption.nameOfFolderToInstall : "lc.appList.installAsNew".loc)
                })

            }
            Button(role: .cancel, action: {
                installReplaceAlert.close(result: nil)
            }, label: {
                Text("lc.appList.abortInstallation".loc)
            })
        } message: {
            Text("lc.appList.installReplaceTip".loc)
        }
        .alert("lc.webView.runApp".loc, isPresented: $runWhenMultitaskAlert.show) {
            Button(role: .destructive) {
                runWhenMultitaskAlert.close(result: true)
            } label: {
                Text("lc.common.continue".loc)
            }
            Button("lc.common.cancel".loc, role: .cancel) {
                runWhenMultitaskAlert.close(result: false)
            }
        } message: {
            Text("lc.appBanner.confirmRunWhenMultitasking".loc)
        }
        .textFieldAlert(
            isPresented: $webViewUrlInput.show,
            title:  "lc.appList.enterUrlTip".loc,
            text: $webViewUrlInput.initVal,
            placeholder: "scheme://",
            action: { newText in
                webViewUrlInput.close(result: newText)
            },
            actionCancel: {_ in
                webViewUrlInput.close(result: nil)
            }
        )
        .textFieldAlert(
            isPresented: $installUrlInput.show,
            title:  "lc.appList.installUrlInputTip".loc,
            text: $installUrlInput.initVal,
            placeholder: "https://",
            action: { newText in
                installUrlInput.close(result: newText)
            },
            actionCancel: {_ in
                installUrlInput.close(result: nil)
            }
        )
        .downloadAlert(helper: downloadHelper)
        .sheet(isPresented: $jitAlert.show, onDismiss: {
            jitAlert.close(result: false)
        }) {
            JITEnablingModal
        }
        .onChange(of: jitAlert.show) { newValue in
            sharedModel.isJITModalOpen = newValue
        }
        .fullScreenCover(isPresented: $webViewOpened) {
            LCWebView(url: $webViewURL, isPresent: $webViewOpened)
        }
        .fullScreenCover(isPresented: $safariViewOpened) {
            SafariView(url: $safariViewURL)
        }
        .sheet(isPresented: $helpPresent) {
            LCHelpView(isPresent: $helpPresent)
        }
        .sheet(isPresented: $customSortViewPresent) {
            LCCustomSortView()
        }
        .onOpenURL { url in
            handleURL(url: url)
        }
        .apply {
            if #available(iOS 19.0, *), SharedModel.isLiquidGlassSearchEnabled {
                $0
            } else {
                $0.searchable(text: $searchContext.query)
            }
        }

    }

    @ViewBuilder
    private var navigationContainer: some View {
        NavigationView {
            AppListContentView(navigationLink: navigationLink,
                               filteredApps: filteredApps,
                               filteredHiddenApps: filteredHiddenApps,
                               searchContext: searchContext,
                               appDataFolders: $appDataFolderNames,
                               tweakFolders: $tweakFolderNames,
                               sharedModel: sharedModel,
                               bannerDelegate: self,
                               onAuthenticate: { await authenticateUser() },
                               onAppear: handleInitialAppear)
            .navigationBarProgressBar(show: $installprogressVisible, progress: $installProgressPercentage)
            .navigationTitle("lc.appList.myApps".loc)
            .toolbar {
                AppListToolbar(
                    multiLCStatus: sharedModel.multiLCStatus,
                    installProgressVisible: $installprogressVisible,
                    choosingIPA: $choosingIPA,
                    customSortViewPresent: $customSortViewPresent,
                    appSortType: $sharedAppSortManager.appSortType,
                    isSideStoreAvailable: UserDefaults.sideStoreExist(),
                    isLiquidGlassEnabled: SharedModel.isLiquidGlassEnabled,
                    onInstallFromUrl: { Task { await startInstallFromUrl() } },
                    onOpenLink: { Task { await onOpenWebViewTapped() } },
                    onHelp: { helpPresent = true },
                    onOpenSideStore: { LCUtils.openSideStore(delegate: self) }
                )
            }
        }
    }

    private var navigationLink: some View {
        NavigationLink(
            destination: navigateTo,
            isActive: $isNavigationActive,
            label: {
                EmptyView()
        })
        .hidden()
    }
    var JITEnablingModal : some View {
        NavigationView {
            ScrollViewReader { proxy in
                ScrollView {
                    Text("lc.appBanner.waitForJitMsg".loc)
                        .padding(.vertical)
                        .id(0)
                    
                    HStack {
                        Text(jitLog)
                            .font(.system(size: 12).monospaced())
                            .fixedSize(horizontal: false, vertical: false)
                            .textSelection(.enabled)
                        Spacer()
                    }
                    
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
                .onAppear {
                    proxy.scrollTo(0)
                }
            }
            .navigationTitle("lc.appBanner.waitForJitTitle".loc)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("lc.common.cancel".loc, role: .cancel) {
                        jitAlert.close(result: false)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        jitAlert.close(result: true)
                    } label: {
                        Text("lc.appBanner.jitLaunchNow".loc)
                    }
                }
            }
        }
    }
    
    func onOpenWebViewTapped() async {
        guard let urlToOpen = await webViewUrlInput.open(), urlToOpen != "" else {
            return
        }
        await openWebView(urlString: urlToOpen)
        
    }
    private func handleInitialAppear() {
        guard !didAppear else { return }
        configureDelegates()
        didAppear = true
    }

    private func configureDelegates() {
        for app in sharedModel.apps {
            app.delegate = self
        }
        for app in sharedModel.hiddenApps {
            app.delegate = self
        }
    }

    func openWebView(urlString: String) async {
        guard var urlToOpen = URLComponents(string: urlString), urlToOpen.url != nil else {
            errorInfo = LCAppError.invalidURL.localizedDescription
            errorShow = true
            return
        }
        if urlToOpen.scheme == nil || urlToOpen.scheme! == "" {
            urlToOpen.scheme = "https"
        }
        if urlToOpen.scheme != "https" && urlToOpen.scheme != "http" {
            var appToLaunch : LCAppModel? = nil
            var appListsToConsider = [sharedModel.apps]
            if sharedModel.isHiddenAppUnlocked || !LCUtils.appGroupUserDefault.bool(forKey: LCUserDefaultStrictHidingKey) {
                appListsToConsider.append(sharedModel.hiddenApps)
            }
            appLoop:
            for appList in appListsToConsider {
                for app in appList {
                    if let schemes = app.appInfo.urlSchemes() {
                        for scheme in schemes {
                            if let scheme = scheme as? String, scheme == urlToOpen.scheme {
                                appToLaunch = app
                                break appLoop
                            }
                        }
                    }
                }
            }


            guard let appToLaunch = appToLaunch else {
                errorInfo = "lc.appList.schemeCannotOpenError %@".localizeWithFormat(urlToOpen.scheme!)
                errorShow = true
                return
            }
            
            if appToLaunch.appInfo.isLocked && !sharedModel.isHiddenAppUnlocked {
                do {
                    if !(try await LCUtils.authenticateUser()) {
                        return
                    }
                } catch {
                    errorInfo = error.localizedDescription
                    errorShow = true
                    return
                }
            }
            
            UserDefaults.standard.setValue(appToLaunch.appInfo.relativeBundlePath!, forKey: LCUserDefaultSelectedAppKey)
            UserDefaults.standard.setValue(urlToOpen.url!.absoluteString, forKey: "launchAppUrlScheme")
            LCUtils.launchToGuestApp()
            
            return
        }
        webViewURL = urlToOpen.url!
        if webViewOpened {
            webViewOpened = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: {
                webViewOpened = true
            })
        } else {
            webViewOpened = true
        }
    }


    
    func startInstallApp(_ fileUrl: URL) async {
        await runInstallation(from: fileUrl, shouldDeleteSource: true)
    }

    @discardableResult
    private func runInstallation(from sourceURL: URL, shouldDeleteSource: Bool) async -> Bool {
        await MainActor.run {
            installprogressVisible = true
            installProgressPercentage = 0.0
        }

        do {
            let result = try await performInstallation(from: sourceURL, shouldDeleteSource: shouldDeleteSource)
            await MainActor.run {
                applyInstallationResult(result)
                installprogressVisible = false
            }
            LCLogger.info(category: .installation, "Installation completed successfully")
            return true
        } catch is CancellationError {
            LCLogger.info(category: .installation, "Installation cancelled by user")
            await MainActor.run {
                installprogressVisible = false
            }
            return false
        } catch {
            LCLogger.error(category: .installation, "Installation failed: \(error.localizedDescription)")
            await MainActor.run {
                errorInfo = error.localizedDescription
                errorShow = true
                installprogressVisible = false
            }
            return false
        }
    }

    private func performInstallation(from sourceURL: URL, shouldDeleteSource: Bool) async throws -> LCAppInstallationResult {
        try await installationService.installIPA(
            from: sourceURL,
            shouldDeleteSourceAfterInstall: shouldDeleteSource,
            duplicatesProvider: { bundleIdentifier in
                try await duplicates(for: bundleIdentifier)
            },
            replacementDecider: { options in
                await MainActor.run {
                    installOptions = options
                }
                return await installReplaceAlert.open()
            },
            shouldSkipSigning: { option in
                if LCUtils.appGroupUserDefault.bool(forKey: "LCDontSignApp") {
                    return true
                }
                return option?.appToReplace?.uiDontSign ?? false
            },
            progressHandler: { progress in
                Task { @MainActor in
                    self.installProgressPercentage = Float(progress)
                }
            }
        )
    }

    @MainActor
    private func duplicates(for bundleIdentifier: String) async throws -> [LCAppModel] {
        let matches = sharedModel.apps.filter { $0.appInfo.bundleIdentifier() == bundleIdentifier }
        var hiddenMatches = sharedModel.hiddenApps.filter { $0.appInfo.bundleIdentifier() == bundleIdentifier }

        if !hiddenMatches.isEmpty && !sharedModel.isHiddenAppUnlocked {
            let strictHidingEnabled = LCUtils.appGroupUserDefault.bool(forKey: LCUserDefaultStrictHidingKey)
            if strictHidingEnabled {
                hiddenMatches = []
            } else {
                do {
                    if try await LCUtils.authenticateUser() {
                        sharedModel.isHiddenAppUnlocked = true
                    } else {
                        hiddenMatches = []
                    }
                } catch {
                    throw error
                }
            }
        }

        return matches + hiddenMatches
    }

    private func applyInstallationResult(_ result: LCAppInstallationResult) {
        let finalNewApp = result.appInfo
        let newAppModel = LCAppModel(appInfo: finalNewApp, delegate: self)

        if let replacedApp = result.replacedApp {
            if replacedApp.uiIsHidden {
                sharedModel.hiddenApps.removeAll { $0 == replacedApp }
                sharedModel.hiddenApps.append(newAppModel)
            } else {
                sharedModel.apps.removeAll { $0 == replacedApp }
                sharedModel.apps.append(newAppModel)
            }
        } else {
            sharedModel.apps.append(newAppModel)
        }

        if let signingError = result.signingError {
            errorInfo = signingError.localizedDescription
            if let recovery = signingError.recoverySuggestion {
                errorInfo += "\n\n" + recovery
            }
            errorShow = true
        }
    }
    
    func startInstallFromUrl() async {
        guard let installUrlStr = await installUrlInput.open(), installUrlStr.count > 0 else {
            return
        }
        await installFromUrl(urlStr: installUrlStr)
    }
    
    func installFromUrl(urlStr: String) async {
        // ignore any install request if we are installing another app
        if self.installprogressVisible {
            return
        }
        
        if sharedModel.multiLCStatus == 2 {
            errorInfo = "lc.appList.manageInPrimaryTip".loc
            errorShow = true
            return
        }
        
        guard let installUrl = URL(string: urlStr) else {
            errorInfo = LCAppError.invalidURL.localizedDescription
            errorShow = true
            return
        }

        await MainActor.run {
            installprogressVisible = true
            installProgressPercentage = 0.0
        }
        defer {
            Task { @MainActor in
                installprogressVisible = false
            }
        }
        
        if installUrl.isFileURL {
            // install from local, we directly call local install method
            if !installUrl.lastPathComponent.hasSuffix(".ipa") && !installUrl.lastPathComponent.hasSuffix(".tipa") {
                errorInfo = LCAppError.notAnIPA.localizedDescription
                errorShow = true
                return
            }
            
            let fm = FileManager.default
            if !fm.isReadableFile(atPath: installUrl.path) && !installUrl.startAccessingSecurityScopedResource() {
                errorInfo = "lc.appList.ipaAccessError".loc
                errorShow = true
                return
            }
            
            defer {
                installUrl.stopAccessingSecurityScopedResource()
            }
            
            let success = await runInstallation(from: installUrl, shouldDeleteSource: false)

            if success {
                do {
                    // delete ipa if it's in inbox
                    var shouldDelete = false
                    if let documentsDirectory = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
                        let inboxURL = documentsDirectory.appendingPathComponent("Inbox")
                        let fileURL = inboxURL.appendingPathComponent(installUrl.lastPathComponent)

                        shouldDelete = fm.fileExists(atPath: fileURL.path)
                    }
                    if shouldDelete {
                        try fm.removeItem(at: installUrl)
                    }
                } catch {
                    errorInfo = error.localizedDescription
                    errorShow = true
                }
            }
            return
        }
        
        do {
            let fileManager = FileManager.default
            let destinationURL = fileManager.temporaryDirectory.appendingPathComponent(installUrl.lastPathComponent)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            
            try await downloadHelper.download(url: installUrl, to: destinationURL)
            if downloadHelper.cancelled {
                return
            }
            _ = await runInstallation(from: destinationURL, shouldDeleteSource: true)
        } catch {
            await MainActor.run {
                errorInfo = error.localizedDescription
                errorShow = true
            }
        }
        
    }
    
    func removeApp(app: LCAppModel) {
        DispatchQueue.main.async {
            sharedModel.apps.removeAll { now in
                return app == now
            }
            sharedModel.hiddenApps.removeAll { now in
                return app == now
            }
            
        }
    }
    
    func changeAppVisibility(app: LCAppModel) {
        DispatchQueue.main.async {
            if app.appInfo.isHidden {
                sharedModel.apps.removeAll { now in
                    return app == now
                }
                if !sharedModel.hiddenApps.contains(app) {
                    sharedModel.hiddenApps.append(app)
                }
            } else {
                sharedModel.hiddenApps.removeAll { now in
                    return app == now
                }
                if !sharedModel.apps.contains(app) {
                    sharedModel.apps.append(app)
                }
            }
            
        }
    }
    
    func launchAppWithBundleId(bundleId : String, container : String?) async {
        if bundleId == "" {
            return
        }
        var appFound : LCAppModel? = nil
        var isFoundAppLocked = false
        for app in sharedModel.apps {
            if app.appInfo.relativeBundlePath == bundleId {
                appFound = app
                if app.appInfo.isLocked {
                    isFoundAppLocked = true
                }
                break
            }
        }
        if appFound == nil && !LCUtils.appGroupUserDefault.bool(forKey: LCUserDefaultStrictHidingKey) {
            for app in sharedModel.hiddenApps {
                if app.appInfo.relativeBundlePath == bundleId {
                    appFound = app
                    isFoundAppLocked = true
                    break
                }
            }
        }
        
        if isFoundAppLocked && !sharedModel.isHiddenAppUnlocked {
            do {
                let result = try await LCUtils.authenticateUser()
                if !result {
                    return
                }
            } catch {
                errorInfo = error.localizedDescription
                errorShow = true
            }
        }
        
        guard let appFound else {
            errorInfo = "lc.appList.appNotFoundError".loc
            errorShow = true
            return
        }

        do {            
            if #available(iOS 16.0, *), launchInMultitaskMode && appFound.uiIsShared {
                try await appFound.runApp(multitask: true, containerFolderName: container)
            } else {
                try await appFound.runApp(multitask: false, containerFolderName: container)
            }
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
        
    }
    
    func authenticateUser() async {
        do {
            if !(try await LCUtils.authenticateUser()) {
                return
            }
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
            return
        }
    }
    
    func jitLaunch() async {
        await jitLaunch(withScript: "")
    }

    func jitLaunch(withScript script: String) async {
        await MainActor.run {
            jitLog = ""
        }
        let enableJITTask = Task {
            let _ = await LCUtils.askForJIT(withScript: script) { newMsg in
                Task { await MainActor.run {
                    self.jitLog += "\(newMsg)\n"
                }}
            }
            guard let _ = JITEnablerType(rawValue: LCUtils.appGroupUserDefault.integer(forKey: "LCJITEnablerType")) else {
                return
            }
        }
        guard let result = await jitAlert.open(), result else {
            UserDefaults.standard.removeObject(forKey: LCUserDefaultSelectedAppKey)
            enableJITTask.cancel()
            return
        }
        LCUtils.launchToGuestApp()

    }
    
    func jitLaunch(withPID pid: Int) async {
        await MainActor.run {
            if let url = URL(string: "stikjit://enable-jit?bundle-id=\(Bundle.main.bundleIdentifier!)&pid=\(pid)") {
                UIApplication.shared.open(url)
            }
        }
    }

    func jitLaunch(withPID pid: Int, withScript script: String) async {
        await MainActor.run {
            let encoded = script.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let url = URL(string: "stikjit://enable-jit?bundle-id=\(Bundle.main.bundleIdentifier!)&pid=\(pid)&script-data=\(encoded)") {
                UIApplication.shared.open(url)
            }
        }
    }

    func showRunWhenMultitaskAlert() async -> Bool? {
        return await runWhenMultitaskAlert.open()
    }
    
    func installMdm(data: Data) {
        safariViewURL = URL(string:"data:application/x-apple-aspen-config;base64,\(data.base64EncodedString())")!
        safariViewOpened = true
    }
    
    func openNavigationView(view: AnyView) {
        navigateTo = view
        isNavigationActive = true
    }
    
    func closeNavigationView() {
        isNavigationActive = false
        navigateTo = nil
    }
    
    func copyError() {
        UIPasteboard.general.string = errorInfo
    }
    
    func handleURL(url : URL) {
        if url.isFileURL {
            Task { await installFromUrl(urlStr: url.absoluteString) }
            return
        }
        
        if url.scheme == "sidestore" && UserDefaults.sideStoreExist() {
            UserDefaults.standard.setValue(url.absoluteString, forKey: "launchAppUrlScheme")
            LCUtils.openSideStore(delegate: self)
            return
        }
        
        if url.host == "open-web-page" || url.host == "open-url" {
            if let urlComponent = URLComponents(url: url, resolvingAgainstBaseURL: false), let queryItem = urlComponent.queryItems?.first {
                if queryItem.value?.isEmpty ?? true {
                    return
                }
                
                if let decodedData = Data(base64Encoded: queryItem.value ?? ""),
                   let decodedUrl = String(data: decodedData, encoding: .utf8) {
                    Task { await openWebView(urlString: decodedUrl) }
                }
            }
        } else if url.host == "livecontainer-launch" {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                var bundleId : String? = nil
                var containerName : String? = nil
                for queryItem in components.queryItems ?? [] {
                    if queryItem.name == "bundle-name", let bundleId1 = queryItem.value {
                        bundleId = bundleId1
                    } else if queryItem.name == "container-folder-name", let containerName1 = queryItem.value {
                        containerName = containerName1
                    }
                }
                if let bundleId, bundleId != "ui"{
                    Task { await launchAppWithBundleId(bundleId: bundleId, container: containerName) }
                }
            }
        } else if url.host == "install" {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                var installUrl : String? = nil
                for queryItem in components.queryItems ?? [] {
                    if queryItem.name == "url", let installUrl1 = queryItem.value {
                        installUrl = installUrl1
                    }
                }
                if let installUrl {
                    Task { await installFromUrl(urlStr: installUrl) }
                }
            }
        }
    }
    
}

extension View {
    func apply<V: View>(@ViewBuilder _ block: (Self) -> V) -> V { block(self) }
}
