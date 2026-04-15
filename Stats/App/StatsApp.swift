import SwiftUI

/// SwiftUI entry point used to bootstrap the menu bar app lifecycle.
@main
struct StatsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
