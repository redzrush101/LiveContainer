import SwiftUI

struct AppListSection<Banner: View>: View {
    let title: LocalizedStringKey?
    let apps: [LCAppModel]
    let animate: Bool
    @ViewBuilder var banner: (LCAppModel) -> Banner

    init(title: LocalizedStringKey? = nil, apps: [LCAppModel], animate: Bool, @ViewBuilder banner: @escaping (LCAppModel) -> Banner) {
        self.title = title
        self.apps = apps
        self.animate = animate
        self.banner = banner
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack {
                    Text(title)
                        .font(.system(.title2).bold())
                    Spacer()
                }
            }

            ForEach(apps, id: \.self) { app in
                banner(app)
                    .transition(.scale)
            }
        }
        .padding()
        .animation(animate ? .easeInOut : nil, value: apps)
    }
}

struct AppListFooterView: View {
    let message: String
    let onTripleTap: () -> Void

    var body: some View {
        Text(message)
            .padding(.horizontal)
            .foregroundStyle(.gray)
            .onTapGesture(count: 3, perform: onTripleTap)
    }
}
