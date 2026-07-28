import SwiftUI
import UIKit
import WebKit

struct WebHubScreen: View {
    let title: String
    let rootPath: String
    let tab: HubTab
    let baseURL: URL
    @ObservedObject var router: HubRouter
    let showSettings: () -> Void

    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var reloadToken = 0

    var body: some View {
        ZStack {
            HubWebView(
                baseURL: baseURL,
                rootPath: rootPath,
                selectedTab: router.selectedTab,
                route: { router.selectedTab = $0 },
                isLoading: $isLoading,
                errorMessage: $errorMessage,
                reloadToken: reloadToken
            )

            if isLoading && errorMessage == nil {
                ProgressView("Loading Home Hub…")
                    .padding(18)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            if let errorMessage {
                connectionError(errorMessage)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    errorMessage = nil
                    reloadToken += 1
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Reload \(title)")

                Button(action: showSettings) {
                    Image(systemName: "gearshape.fill")
                }
                .accessibilityLabel("Home Hub settings")
            }
        }
        .onChange(of: router.selectedTab) { selectedTab in
            if selectedTab == tab {
                errorMessage = nil
                reloadToken += 1
            }
        }
    }

    private func connectionError(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            Text("Home Hub is unavailable")
                .font(.title2.bold())
            Text(message)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            HStack {
                Button("Server settings", action: showSettings)
                    .buttonStyle(.bordered)
                Button("Try again") {
                    errorMessage = nil
                    reloadToken += 1
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(maxWidth: 440)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding()
    }
}

private struct HubWebView: UIViewRepresentable {
    let baseURL: URL
    let rootPath: String
    let selectedTab: HubTab
    let route: (HubTab) -> Void
    @Binding var isLoading: Bool
    @Binding var errorMessage: String?
    let reloadToken: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.applicationNameForUserAgent = "HomeHub-iPad/1.0"

        let hideWebDock = """
        (function () {
          var style = document.createElement('style');
          style.textContent = '.dock{display:none!important}.stage{padding-bottom:max(24px,env(safe-area-inset-bottom))!important}';
          document.head.appendChild(style);
        })();
        """
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: hideWebDock,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        context.coordinator.webView = webView
        context.coordinator.lastReloadToken = reloadToken
        context.coordinator.loadRoot()
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        guard reloadToken != context.coordinator.lastReloadToken else { return }
        context.coordinator.lastReloadToken = reloadToken
        context.coordinator.loadRoot()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: HubWebView
        weak var webView: WKWebView?
        var lastReloadToken = 0

        init(parent: HubWebView) {
            self.parent = parent
        }

        func loadRoot() {
            guard let webView else { return }
            let url = HubAddress.endpoint(parent.rootPath, relativeTo: parent.baseURL)
            var request = URLRequest(
                url: url,
                cachePolicy: .reloadRevalidatingCacheData,
                timeoutInterval: 15
            )
            request.setValue("HomeHub-iPad/1.0", forHTTPHeaderField: "X-HomeHub-Client")
            DispatchQueue.main.async {
                self.parent.errorMessage = nil
                self.parent.isLoading = true
            }
            webView.load(request)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.targetFrame?.isMainFrame != false,
                  let url = navigationAction.request.url
            else {
                decisionHandler(.allow)
                return
            }

            guard isSameOrigin(url, parent.baseURL) else {
                if url.scheme == "http" || url.scheme == "https" {
                    UIApplication.shared.open(url)
                }
                decisionHandler(.cancel)
                return
            }

            if let tab = HubTab.route(for: url.path), tab != parent.selectedTab {
                parent.route(tab)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            parent.errorMessage = nil
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            show(error)
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            show(error)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            loadRoot()
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        func webView(
            _ webView: WKWebView,
            runJavaScriptConfirmPanelWithMessage message: String,
            initiatedByFrame frame: WKFrameInfo,
            completionHandler: @escaping (Bool) -> Void
        ) {
            guard let presenter = webView.window?.rootViewController else {
                completionHandler(false)
                return
            }
            let alert = UIAlertController(
                title: "Home Hub",
                message: message,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                completionHandler(false)
            })
            alert.addAction(UIAlertAction(title: "Continue", style: .destructive) { _ in
                completionHandler(true)
            })
            topViewController(from: presenter).present(alert, animated: true)
        }

        @available(iOS 15.0, *)
        func webView(
            _ webView: WKWebView,
            requestMediaCapturePermissionFor origin: WKSecurityOrigin,
            initiatedByFrame frame: WKFrameInfo,
            type: WKMediaCaptureType,
            decisionHandler: @escaping (WKPermissionDecision) -> Void
        ) {
            // Scan and Guard use AVFoundation instead of insecure web camera access.
            decisionHandler(.deny)
        }

        private func show(_ error: Error) {
            let nsError = error as NSError
            guard nsError.code != NSURLErrorCancelled else { return }
            parent.isLoading = false
            parent.errorMessage = error.localizedDescription
        }

        private func topViewController(from root: UIViewController) -> UIViewController {
            if let presented = root.presentedViewController {
                return topViewController(from: presented)
            }
            if let navigation = root as? UINavigationController,
               let visible = navigation.visibleViewController
            {
                return topViewController(from: visible)
            }
            if let tab = root as? UITabBarController,
               let selected = tab.selectedViewController
            {
                return topViewController(from: selected)
            }
            return root
        }

        private func isSameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
            lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
                && lhs.host?.lowercased() == rhs.host?.lowercased()
                && effectivePort(lhs) == effectivePort(rhs)
        }

        private func effectivePort(_ url: URL) -> Int? {
            if let port = url.port {
                return port
            }
            return url.scheme?.lowercased() == "https" ? 443 : 80
        }
    }
}
