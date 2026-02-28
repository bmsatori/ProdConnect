import FirebaseCore
import SwiftUI

@main
struct ProdConnectMacApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    @StateObject private var store: ProdConnectStore

    init() {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        _store = StateObject(wrappedValue: ProdConnectStore.shared)
    }

    var body: some Scene {
        WindowGroup("ProdConnect") {
            MacRootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1280, minHeight: 820)
        }
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unifiedCompact)
    }
}
