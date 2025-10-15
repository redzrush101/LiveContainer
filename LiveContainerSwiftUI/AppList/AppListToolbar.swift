import SwiftUI
import UIKit

struct AppListToolbar: ToolbarContent {
    let multiLCStatus: Int
    @Binding var installProgressVisible: Bool
    @Binding var choosingIPA: Bool
    @Binding var customSortViewPresent: Bool
    @Binding var appSortType: AppSortType
    let isSideStoreAvailable: Bool
    let isLiquidGlassEnabled: Bool
    let onInstallFromUrl: () -> Void
    let onOpenLink: () -> Void
    let onHelp: () -> Void
    let onOpenSideStore: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if multiLCStatus != 2 {
                if installProgressVisible {
                    ProgressView().progressViewStyle(.circular).padding(.horizontal, 8)
                } else {
                    Menu {
                        Button("lc.appList.installFromIpa".loc, systemImage: "doc.badge.plus") {
                            choosingIPA = true
                        }
                        Button("lc.appList.installFromUrl".loc, systemImage: "link.badge.plus", action: onInstallFromUrl)
                    } label: {
                        Label("add", systemImage: "plus")
                    }
                }
            }
        }

        ToolbarItem(placement: .topBarLeading) {
            if isSideStoreAvailable {
                Button(action: onOpenSideStore) {
                    Image("SideStoreBadge")
                        .resizable()
                        .renderingMode(.template)
                        .foregroundColor(isLiquidGlassEnabled ? .primary : .accentColor)
                        .frame(width: UIFont.preferredFont(forTextStyle: .body).lineHeight,
                               height: UIFont.preferredFont(forTextStyle: .body).lineHeight)
                }
            } else {
                Button("Help", systemImage: "questionmark", action: onHelp)
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button("lc.appList.openLink".loc, systemImage: "link", action: onOpenLink)
        }

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Sort by", selection: $appSortType) {
                    ForEach(AppSortType.allCases, id: \.
self) { sortType in
                        Label(sortType.displayName, systemImage: sortType.systemImage)
                            .tag(sortType)
                    }
                }
                .onChange(of: appSortType) { newValue in
                    if newValue == .custom {
                        customSortViewPresent = true
                    }
                }

                if appSortType == .custom {
                    Divider()

                    Button {
                        customSortViewPresent = true
                    } label: {
                        Label("lc.appList.sort.customManage".loc, systemImage: "slider.horizontal.3")
                    }
                }
            } label: {
                Label("lc.appList.sort".loc, systemImage: "line.3.horizontal.decrease.circle")
            }
        }
    }
}
