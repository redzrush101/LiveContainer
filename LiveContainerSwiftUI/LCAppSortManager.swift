//
//  LCAppSortManager.swift
//  LiveContainer
//
//  Created by boa-z on 2025/6/22.
//

import Foundation
import SwiftUI

/// App sorting business logic manager
class LCAppSortManager {
    
    // MARK: - Unique Identifier Methods
    
    /// Generate unique identifier for app using bundleId:relativePath format
    static func getUniqueIdentifier(for app: LCAppModel) -> String? {
        guard let bundleId = app.appInfo.bundleIdentifier(),
              let relativePath = app.appInfo.relativeBundlePath else {
            return nil
        }
        return "\(bundleId):\(relativePath)"
    }
    
    /// Check if unique identifier matches the app
    static func matches(uniqueId: String, app: LCAppModel) -> Bool {
        guard let appUniqueId = getUniqueIdentifier(for: app) else {
            return false
        }
        return uniqueId == appUniqueId
    }
    
    // MARK: - Sorting Methods
    
    /// Sort app list by specified sort type
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
    
    /// Sort app list by custom order using unique identifiers
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
    
    // MARK: - Drag & Drop Methods
    
    /// Generate new sort order after drag and drop operation
    static func generateMoveOrder(for targetApps: [LCAppModel], 
                                  currentCustomOrder: [String], 
                                  from source: IndexSet, 
                                  to destination: Int) -> [String] {
        let uniqueIds = targetApps.compactMap { getUniqueIdentifier(for: $0) }
        
        var newOrder = currentCustomOrder.isEmpty ? uniqueIds : currentCustomOrder
        
        for uniqueId in uniqueIds {
            if !newOrder.contains(uniqueId) {
                newOrder.append(uniqueId)
            }
        }
        
        newOrder.move(fromOffsets: source, toOffset: destination)
        return newOrder
    }
    
    // MARK: - Cleanup Methods
    
    /// Remove invalid entries from custom sort order
    static func cleanupCustomSortOrder(_ currentCustomOrder: [String], 
                                       apps: [LCAppModel], 
                                       hiddenApps: [LCAppModel]) -> [String] {
        let allApps = apps + hiddenApps
        let validUniqueIds = Set(allApps.compactMap { getUniqueIdentifier(for: $0) })
        
        let cleanedOrder = currentCustomOrder.filter { validUniqueIds.contains($0) }
        return cleanedOrder
    }
    
    // MARK: - App Management Methods
    
    /// Prepare insertion info for new app without modifying arrays
    static func prepareAddOrder(for app: LCAppModel,
                                sortType: AppSortType,
                                apps: [LCAppModel],
                                hiddenApps: [LCAppModel],
                                currentCustomOrder: [String]) -> (insertToHidden: Bool, insertIndex: Int, newCustomOrder: [String]) {
        guard let uniqueId = getUniqueIdentifier(for: app) else {
            return (app.appInfo.isHidden, app.appInfo.isHidden ? hiddenApps.count : apps.count, currentCustomOrder)
        }
        
        let targetArray = app.appInfo.isHidden ? hiddenApps : apps
        let insertToHidden = app.appInfo.isHidden
        
        switch sortType {
        case .alphabetical:
            let insertIndex = targetArray.firstIndex { $0.appInfo.displayName() > app.appInfo.displayName() } ?? targetArray.count
            return (insertToHidden, insertIndex, currentCustomOrder)
            
        case .reverseAlphabetical:
            let insertIndex = targetArray.firstIndex { $0.appInfo.displayName() < app.appInfo.displayName() } ?? targetArray.count
            return (insertToHidden, insertIndex, currentCustomOrder)
            
        case .custom:
            var newOrder = currentCustomOrder
            if !newOrder.contains(uniqueId) {
                newOrder.append(uniqueId)
            }
            return (insertToHidden, targetArray.count, newOrder)
        }
    }
    
    // MARK: - Utility Methods
    
    /// Return updated custom order if cleanup is needed, otherwise nil
    static func getUpdatedCustomOrderIfNeeded(_ currentCustomOrder: [String], 
                                              apps: [LCAppModel], 
                                              hiddenApps: [LCAppModel]) -> [String]? {
        let cleanedOrder = cleanupCustomSortOrder(currentCustomOrder, apps: apps, hiddenApps: hiddenApps)
        return cleanedOrder.count != currentCustomOrder.count ? cleanedOrder : nil
    }
}