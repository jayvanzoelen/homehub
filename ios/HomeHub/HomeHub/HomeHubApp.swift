import SwiftUI
import UIKit

@main
struct HomeHubApp: App {
    @UIApplicationDelegateAdaptor(HomeHubAppDelegate.self) private var appDelegate
    @StateObject private var settings = HubSettings()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
        }
    }
}

final class HomeHubAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [
            UIApplication.LaunchOptionsKey: Any
        ]? = nil
    ) -> Bool {
        application.isIdleTimerDisabled = true
        return true
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        application.isIdleTimerDisabled = true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        application.isIdleTimerDisabled = false
    }
}
