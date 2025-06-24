//
//  LCAppSortManager.swift
//  LiveContainer
//
//  Created by boa-z on 2025/6/22.
//

import Foundation
import SwiftUI
import Combine

/// Manages the state and logic for sorting the list of applications.
class LCAppSortManager: ObservableObject {

    @Published var apps: [LCAppModel] = []
    @Published var hiddenApps: [LCAppModel] = []
    
    @Published var appSortType: AppSortType {
        didSet {
            saveSortType()
            applySort()
        }
    }
    
    @Published private(set) var customSortOrder: [String] {
        didSet {
            saveCustomSortOrder()
        }
    }
    
    private let userDefaults = LCUtils.appGroupUserDefault

    // MARK: - Initialization
    
    init() {
        let savedSortTypeRaw = userDefaults.string(forKey: "LCAppSortType")
        self.appSortType = AppSortType(rawValue: savedSortTypeRaw ?? "") ?? .alphabetical
        
        self.customSortOrder = userDefaults.array(forKey: "LCCustomSortOrder") as? [String] ?? []
    }
    
    // MARK: - Public API for UI Interaction

    func setInitialApps(_ allApps: [LCAppModel]) {
        self.apps = allApps.filter { !$0.appInfo.isHidden }
        self.hiddenApps = allApps.filter { $0.appInfo.isHidden }
        self.cleanupCustomSortOrder()
        self.applySort()
    }

    func updateSortType(_ newType: AppSortType) {
        self.appSortType = newType
    }
    
    func addNewApp(_ app: LCAppModel) {
        if app.appInfo.isHidden {
            hiddenApps.append(app)
        } else {
            apps.append(app)
        }
        
        if let uniqueId = Self.getUniqueIdentifier(for: app), !customSortOrder.contains(uniqueId) {
            customSortOrder.append(uniqueId)
        }
        
        applySort()
    }

    func cleanupCustomSortOrder() {
        let cleanedOrder = Self.cleanupCustomSortOrder(
            self.customSortOrder,
            apps: self.apps,
            hiddenApps: self.hiddenApps
        )
        
        if cleanedOrder.count != self.customSortOrder.count {
            self.customSortOrder = cleanedOrder
        }
    }

        func updateCustomSortOrder(_ newOrder: [String]) {
        self.customSortOrder = newOrder
        applySort()
    }
    
    // MARK: - Internal Logic
    
    // private func applySort() {
    func applySort() {
        self.apps = Self.getSortedApps(self.apps, sortType: self.appSortType, customSortOrder: self.customSortOrder)
        self.hiddenApps = Self.getSortedApps(self.hiddenApps, sortType: self.appSortType, customSortOrder: self.customSortOrder)
    }

    private func saveSortType() {
        userDefaults.set(appSortType.rawValue, forKey: "LCAppSortType")
    }
    
    private func saveCustomSortOrder() {
        userDefaults.set(customSortOrder, forKey: "LCCustomSortOrder")
    }
    
    // MARK: - Core Logic (Stateless Static Functions)
    
    static func getUniqueIdentifier(for app: LCAppModel) -> String? {
        guard let bundleId = app.appInfo.bundleIdentifier(),
              let relativePath = app.appInfo.relativeBundlePath else {
            return nil
        }
        return "\(bundleId):\(relativePath)"
    }
    
    func getUniqueIdentifier(for app: LCAppModel) -> String? {
        return Self.getUniqueIdentifier(for: app)
    }
    
    static func matches(uniqueId: String, app: LCAppModel) -> Bool {
        guard let appUniqueId = getUniqueIdentifier(for: app) else {
            return false
        }
        return uniqueId == appUniqueId
    }
    
    static func getSortedApps(_ appList: [LCAppModel], sortType: AppSortType, customSortOrder: [String]) -> [LCAppModel] {
        switch sortType {
        case .alphabetical:
            return appList.sorted { $0.appInfo.displayName() < $1.appInfo.displayName() }
        case .reverseAlphabetical:
            return appList.sorted { $0.appInfo.displayName() > $1.appInfo.displayName() }
        case .custom:
            return sortByCustomOrder(appList, customSortOrder: customSortOrder)
        }
    }
    
    private static func sortByCustomOrder(_ appList: [LCAppModel], customSortOrder: [String]) -> [LCAppModel] {
        if customSortOrder.isEmpty {
            return appList.sorted { $0.appInfo.displayName() < $1.appInfo.displayName() }
        }
        
        var sortedApps: [LCAppModel] = []
        var remainingApps = appList
        
        for uniqueId in customSortOrder {
            if let index = remainingApps.firstIndex(where: { matches(uniqueId: uniqueId, app: $0) }) {
                sortedApps.append(remainingApps.remove(at: index))
            }
        }
        
        remainingApps.sort { $0.appInfo.displayName() < $1.appInfo.displayName() }
        sortedApps.append(contentsOf: remainingApps)
        
        return sortedApps
    }
    
    static func cleanupCustomSortOrder(_ currentCustomOrder: [String],
                                       apps: [LCAppModel],
                                       hiddenApps: [LCAppModel]) -> [String] {
        let allApps = apps + hiddenApps
        let validUniqueIds = Set(allApps.compactMap { getUniqueIdentifier(for: $0) })
        return currentCustomOrder.filter { validUniqueIds.contains($0) }
    }
}