import Darwin
#if canImport(CoreMIDI)
import CoreMIDI
#endif
import FirebaseCore
import FirebaseFirestore
import SwiftUI

private enum MacFirebaseBootstrap {
    static var didConfigure = false
    static var didConfigureFirestore = false
    static var didConfigureSignals = false
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
    configureMacFirestoreIfNeeded()
    MacFirebaseBootstrap.didConfigure = true
}

func configureMacProcessSignalsIfNeeded() {
    guard !MacFirebaseBootstrap.didConfigureSignals else { return }
    signal(SIGPIPE, SIG_IGN)
    MacFirebaseBootstrap.didConfigureSignals = true
}

func configureMacFirestoreIfNeeded() {
    guard !MacFirebaseBootstrap.didConfigureFirestore else { return }

    let settings = FirestoreSettings()
    settings.cacheSettings = PersistentCacheSettings()
    Firestore.firestore().settings = settings

    MacFirebaseBootstrap.didConfigureFirestore = true
}

@main
struct ProdConnectMacApp: App {
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    @StateObject private var store: ProdConnectStore
    @StateObject private var ndiSettings: MacNDISettingsController
    @StateObject private var runOfShowControls: MacRunOfShowControlController

    init() {
        configureMacProcessSignalsIfNeeded()
        configureMacFirebaseIfNeeded()
        let sharedStore = ProdConnectStore.shared
        _store = StateObject(wrappedValue: sharedStore)
        _ndiSettings = StateObject(wrappedValue: MacNDISettingsController(store: sharedStore))
        _runOfShowControls = StateObject(wrappedValue: MacRunOfShowControlController(store: sharedStore))
    }

    var body: some Scene {
        WindowGroup("ProdConnect") {
            MacRootView()
                .environmentObject(store)
                .environmentObject(ndiSettings)
                .environmentObject(runOfShowControls)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1280, minHeight: 820)
        }
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unifiedCompact)

        Settings {
            MacSettingsView()
                .environmentObject(store)
                .environmentObject(ndiSettings)
                .environmentObject(runOfShowControls)
                .preferredColorScheme(.dark)
        }
    }
}
