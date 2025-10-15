import SwiftUI

struct AppListContentView<NavigationLinkView: View>: View {
    let navigationLink: NavigationLinkView
    let filteredApps: [LCAppModel]
    let filteredHiddenApps: [LCAppModel]
    let searchContext: SearchContext
    @Binding var appDataFolders: [String]
    @Binding var tweakFolders: [String]
    @ObservedObject var sharedModel: SharedModel
    let bannerDelegate: LCAppBannerDelegate
    let onAuthenticate: () async -> Void
    let onAppear: () -> Void

    private var appCount: Int {
        sharedModel.isHiddenAppUnlocked ? filteredApps.count + filteredHiddenApps.count : filteredApps.count
    }

    private var counterText: String {
        if appCount > 0 || !searchContext.debouncedQuery.isEmpty {
            return "lc.appList.appCounter %lld".localizeWithFormat(appCount)
        }
        return sharedModel.multiLCStatus == 2 ? "lc.appList.convertToSharedToShowInLC2".loc : "lc.appList.installTip".loc
    }

    var body: some View {
        ScrollView {
            navigationLink

            AppListSection(apps: filteredApps, animate: !searchContext.isTyping) { app in
                LCAppBanner(appModel: app,
                            delegate: bannerDelegate,
                            appDataFolders: $appDataFolders,
                            tweakFolders: $tweakFolders)
            }

            HiddenAppsSectionView(filteredHiddenApps: filteredHiddenApps,
                                  searchContext: searchContext,
                                  sharedModel: sharedModel,
                                  appDataFolders: $appDataFolders,
                                  tweakFolders: $tweakFolders,
                                  bannerDelegate: bannerDelegate,
                                  onAuthenticate: onAuthenticate)

            if sharedModel.multiLCStatus == 2 {
                Text("lc.appList.manageInPrimaryTip".loc)
                    .foregroundStyle(.gray)
                    .padding()
            }

            AppListFooterView(message: counterText) {
                Task { await onAuthenticate() }
            }
            .animation(searchContext.isTyping ? nil : .easeInOut, value: appCount)
        }
        .coordinateSpace(name: "scroll")
        .onAppear(perform: onAppear)
    }
}

private struct HiddenAppsSectionView: View {
    let filteredHiddenApps: [LCAppModel]
    let searchContext: SearchContext
    @ObservedObject var sharedModel: SharedModel
    @Binding var appDataFolders: [String]
    @Binding var tweakFolders: [String]
    let bannerDelegate: LCAppBannerDelegate
    let onAuthenticate: () async -> Void

    private var strictHidingEnabled: Bool {
        LCUtils.appGroupUserDefault.bool(forKey: LCUserDefaultStrictHidingKey)
    }

    var body: some View {
        VStack {
            if strictHidingEnabled {
                StrictHiddenAppsView(filteredHiddenApps: filteredHiddenApps,
                                     searchContext: searchContext,
                                     sharedModel: sharedModel,
                                     appDataFolders: $appDataFolders,
                                     tweakFolders: $tweakFolders,
                                     bannerDelegate: bannerDelegate)
            } else if !sharedModel.hiddenApps.isEmpty {
                NonStrictHiddenAppsView(filteredHiddenApps: filteredHiddenApps,
                                        searchContext: searchContext,
                                        sharedModel: sharedModel,
                                        appDataFolders: $appDataFolders,
                                        tweakFolders: $tweakFolders,
                                        bannerDelegate: bannerDelegate,
                                        onAuthenticate: onAuthenticate)
            }
        }
        .animation(searchContext.isTyping ? nil : .easeInOut, value: strictHidingEnabled)
    }
}

private struct StrictHiddenAppsView: View {
    let filteredHiddenApps: [LCAppModel]
    let searchContext: SearchContext
    @ObservedObject var sharedModel: SharedModel
    @Binding var appDataFolders: [String]
    @Binding var tweakFolders: [String]
    let bannerDelegate: LCAppBannerDelegate

    var body: some View {
        if sharedModel.isHiddenAppUnlocked {
            AppListSection(title: LocalizedStringKey("lc.appList.hiddenApps".loc),
                           apps: filteredHiddenApps,
                           animate: !searchContext.isTyping) { app in
                LCAppBanner(appModel: app,
                            delegate: bannerDelegate,
                            appDataFolders: $appDataFolders,
                            tweakFolders: $tweakFolders)
            }
            .transition(.opacity)

            if sharedModel.hiddenApps.isEmpty {
                Text("lc.appList.hideAppTip".loc)
                    .foregroundStyle(.gray)
            }
        }
    }
}

private struct NonStrictHiddenAppsView: View {
    let filteredHiddenApps: [LCAppModel]
    let searchContext: SearchContext
    @ObservedObject var sharedModel: SharedModel
    @Binding var appDataFolders: [String]
    @Binding var tweakFolders: [String]
    let bannerDelegate: LCAppBannerDelegate
    let onAuthenticate: () async -> Void

    var body: some View {
        AppListSection(title: LocalizedStringKey("lc.appList.hiddenApps".loc),
                       apps: filteredHiddenApps,
                       animate: !searchContext.isTyping) { app in
            Group {
                if sharedModel.isHiddenAppUnlocked {
                    LCAppBanner(appModel: app,
                                delegate: bannerDelegate,
                                appDataFolders: $appDataFolders,
                                tweakFolders: $tweakFolders)
                } else {
                    LCAppSkeletonBanner()
                }
            }
        }
        .animation(.easeInOut, value: sharedModel.isHiddenAppUnlocked)
        .onTapGesture {
            Task { await onAuthenticate() }
        }
    }
}
