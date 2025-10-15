import Combine
import Foundation

final class SearchContext: ObservableObject {
    @Published var query: String = ""
    @Published var debouncedQuery: String = ""
    @Published var isTyping: Bool = false

    private var cancellables = Set<AnyCancellable>()

    init(debounceInterval: DispatchQueue.SchedulerTimeType.Stride = .seconds(0.2)) {
        $query
            .debounce(for: debounceInterval, scheduler: DispatchQueue.main)
            .sink { [weak self] value in
                self?.isTyping = true
                self?.debouncedQuery = value
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    self?.isTyping = false
                }
            }
            .store(in: &cancellables)
    }
}

@MainActor
final class AppListViewModel: ObservableObject {
    @Published var searchContext = SearchContext()

    func filteredApps(from apps: [LCAppModel]) -> [LCAppModel] {
        guard !searchContext.debouncedQuery.isEmpty else {
            return apps
        }
        return apps.filter { app in
            guard let bundleIdentifier = app.appInfo.bundleIdentifier() else { return false }
            let displayName = app.appInfo.displayName()
            return displayName.localizedCaseInsensitiveContains(searchContext.debouncedQuery) ||
            bundleIdentifier.localizedCaseInsensitiveContains(searchContext.debouncedQuery)
        }
    }

    func filteredHiddenApps(from apps: [LCAppModel], isHiddenUnlocked: Bool) -> [LCAppModel] {
        if searchContext.debouncedQuery.isEmpty || !isHiddenUnlocked {
            return apps
        }

        return apps.filter { app in
            guard let bundleIdentifier = app.appInfo.bundleIdentifier() else { return false }
            let displayName = app.appInfo.displayName()
            return displayName.localizedCaseInsensitiveContains(searchContext.debouncedQuery) ||
            bundleIdentifier.localizedCaseInsensitiveContains(searchContext.debouncedQuery)
        }
    }
}
