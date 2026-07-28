import SwiftUI

enum HubTab: Int, CaseIterable {
    case home
    case board
    case pantry
    case scan
    case guard

    static func route(for path: String) -> HubTab? {
        let normalized = path.count > 1 && path.hasSuffix("/")
            ? String(path.dropLast())
            : path
        switch normalized {
        case "/":
            return .home
        case "/tasks":
            return .board
        case "/pantry":
            return .pantry
        case "/scan":
            return .scan
        case "/security":
            return .guard
        default:
            return nil
        }
    }
}

@MainActor
final class HubRouter: ObservableObject {
    @Published var selectedTab: HubTab = .home
}

struct RootView: View {
    @EnvironmentObject private var settings: HubSettings

    var body: some View {
        Group {
            if let serverURL = settings.serverURL {
                HubTabs(settings: settings, serverURL: serverURL)
                    .id(serverURL.absoluteString)
            } else {
                SetupView(settings: settings, allowsCancel: false)
            }
        }
    }
}

private struct HubTabs: View {
    @ObservedObject var settings: HubSettings
    let serverURL: URL

    @StateObject private var router = HubRouter()
    @State private var showsSettings = false

    var body: some View {
        TabView(selection: $router.selectedTab) {
            webTab(title: "Home", path: "/", tab: .home)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(HubTab.home)

            webTab(title: "Board", path: "/tasks", tab: .board)
                .tabItem {
                    Label("Board", systemImage: "checkmark.circle.fill")
                }
                .tag(HubTab.board)

            webTab(title: "Pantry", path: "/pantry", tab: .pantry)
                .tabItem {
                    Label("Pantry", systemImage: "shippingbox.fill")
                }
                .tag(HubTab.pantry)

            nativeTab(title: "Scan") {
                ScanView(baseURL: serverURL)
            }
            .tabItem {
                Label("Scan", systemImage: "camera.fill")
            }
            .tag(HubTab.scan)

            nativeTab(title: "Guard") {
                GuardView(baseURL: serverURL)
            }
            .tabItem {
                Label("Guard", systemImage: "shield.fill")
            }
            .tag(HubTab.guard)
        }
        .sheet(isPresented: $showsSettings) {
            SetupView(settings: settings, allowsCancel: true)
        }
    }

    private func webTab(title: String, path: String, tab: HubTab) -> some View {
        NavigationView {
            WebHubScreen(
                title: title,
                rootPath: path,
                tab: tab,
                baseURL: serverURL,
                router: router,
                showSettings: { showsSettings = true }
            )
        }
        .navigationViewStyle(.stack)
    }

    private func nativeTab<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationView {
            content()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showsSettings = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                        }
                        .accessibilityLabel("Home Hub settings")
                    }
                }
        }
        .navigationViewStyle(.stack)
    }
}
