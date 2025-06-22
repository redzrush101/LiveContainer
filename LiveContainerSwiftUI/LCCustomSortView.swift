//
//  LCCustomSortView.swift
//  LiveContainerSwiftUI
//
//  Created by boa-z on 2025/6/21.
//

import SwiftUI

struct LCCustomSortView: View {
    @EnvironmentObject private var sharedModel: SharedModel
    @Environment(\.presentationMode) var presentationMode
    
    @State private var apps: [LCAppModel] = []
    @State private var hiddenApps: [LCAppModel] = []
    
    var body: some View {
        NavigationView {
            Form {
                if !apps.isEmpty {
                    // Section("lc.appList.visibleApps".loc) {
                        ForEach(apps, id: \.self) { app in
                            HStack {
                                Image(uiImage: app.appInfo.icon())
                                    .resizable()
                                    .frame(width: 60, height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.appInfo.displayName())
                                        .font(.system(size: 16, weight: .bold))
                                        .lineLimit(1)
                                    Text("\(app.appInfo.version() ?? "?") - \(app.appInfo.bundleIdentifier() ?? "?")")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                    Text(app.uiSelectedContainer?.name ?? "lc.appBanner.noDataFolder".loc)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                        .onMove { source, destination in
                            apps.move(fromOffsets: source, toOffset: destination)
                            updateCustomSortOrder()
                        }
                    // }
                }
                
                if sharedModel.isHiddenAppUnlocked && !hiddenApps.isEmpty {
                    Section("lc.appList.hiddenApps".loc) {
                        ForEach(hiddenApps, id: \.self) { app in
                            HStack {
                                Image(uiImage: app.appInfo.icon())
                                    .resizable()
                                    .frame(width: 60, height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.appInfo.displayName())
                                        .font(.system(size: 16, weight: .bold))
                                        .lineLimit(1)
                                    Text("\(app.appInfo.version() ?? "?") - \(app.appInfo.bundleIdentifier() ?? "?")")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                    Text(app.uiSelectedContainer?.name ?? "lc.appBanner.noDataFolder".loc)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                        .onMove { source, destination in
                            hiddenApps.move(fromOffsets: source, toOffset: destination)
                            updateCustomSortOrder()
                        }
                    }
                }
                
                Section {
                    Button("lc.appList.sort.resetToAlphabetical".loc) {
                        resetToAlphabetical()
                    }
                    .foregroundColor(.orange)
                } footer: {
                    Text("lc.appList.sort.customSortTip".loc)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("lc.appList.sort.custom".loc)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("lc.common.cancel".loc) {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if #available(iOS 16.0, *) {
                        Button("lc.common.done".loc) {
                            presentationMode.wrappedValue.dismiss()
                        }
                        .font(.system(size: 17))
                        .fontWeight(.bold)
                    } else {
                        Button("lc.common.done".loc) {
                            presentationMode.wrappedValue.dismiss()
                        }
                        .font(.system(size: 17, weight: .bold))
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
        }
        .onAppear {
            loadApps()
        }
    }
    
    private func loadApps() {
        apps = getSortedByCustomOrder(sharedModel.apps)
        hiddenApps = getSortedByCustomOrder(sharedModel.hiddenApps)
    }
    
    private func getSortedByCustomOrder(_ appList: [LCAppModel]) -> [LCAppModel] {
        return LCAppSortManager.getSortedApps(appList, sortType: .custom, customSortOrder: sharedModel.customSortOrder)
    }
    
    private func updateCustomSortOrder() {
        var newOrder: [String] = []
        
        for app in apps {
            if let uniqueId = LCAppSortManager.getUniqueIdentifier(for: app) {
                newOrder.append(uniqueId)
            }
        }
        
        for app in hiddenApps {
            if let uniqueId = LCAppSortManager.getUniqueIdentifier(for: app) {
                newOrder.append(uniqueId)
            }
        }
        
        sharedModel.updateCustomSortOrder(newOrder)
    }
    
    private func resetToAlphabetical() {
        apps = sharedModel.apps.sorted { $0.appInfo.displayName() < $1.appInfo.displayName() }
        hiddenApps = sharedModel.hiddenApps.sorted { $0.appInfo.displayName() < $1.appInfo.displayName() }
        updateCustomSortOrder()
    }
}

#Preview {
    LCCustomSortView()
        .environmentObject(DataManager.shared.model)
}
