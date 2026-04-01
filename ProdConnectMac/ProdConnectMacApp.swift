import FirebaseCore
import SwiftUI

private enum MacFirebaseBootstrap {
    static var didConfigure = false
}

func configureMacFirebaseIfNeeded() {
    guard !MacFirebaseBootstrap.didConfigure else { return }

    let options = FirebaseOptions(
        googleAppID: "1:493345446115:ios:a505ac2fd1b65666500dd6",
        gcmSenderID: "493345446115"
    )
    options.apiKey = "AIzaSyD-tyZFKADFmXbZQf6bBiorqHuUgAwMIms"
    options.projectID = "prodconnect-1ea3a"
    options.bundleID = Bundle.main.bundleIdentifier ?? "Timer.ProdConnect.mac"
    options.storageBucket = "prodconnect-1ea3a.firebasestorage.app"

    FirebaseApp.configure(options: options)
    MacFirebaseBootstrap.didConfigure = true
}

@main
struct ProdConnectMacApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    @StateObject private var store: ProdConnectStore

    init() {
        configureMacFirebaseIfNeeded()
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
