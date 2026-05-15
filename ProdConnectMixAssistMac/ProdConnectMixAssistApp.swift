import Darwin
import FirebaseCore
import FirebaseFirestore
import SwiftUI

private enum MixAssistFirebaseBootstrap {
    static var didConfigure = false
    static var didConfigureFirestore = false
    static var didConfigureSignals = false
}

private func configureMixAssistFirebaseIfNeeded() {
    guard !MixAssistFirebaseBootstrap.didConfigure else { return }

    let options = FirebaseOptions(
        googleAppID: "1:493345446115:ios:a505ac2fd1b65666500dd6",
        gcmSenderID: "493345446115"
    )
    options.apiKey = "AIzaSyD-tyZFKADFmXbZQf6bBiorqHuUgAwMIms"
    options.projectID = "prodconnect-1ea3a"
    options.bundleID = Bundle.main.bundleIdentifier ?? "Timer.ProdConnect.mixassist.mac"
    options.storageBucket = "prodconnect-1ea3a.firebasestorage.app"

    FirebaseApp.configure(options: options)
    configureMixAssistFirestoreIfNeeded()
    MixAssistFirebaseBootstrap.didConfigure = true
}

private func configureMixAssistProcessSignalsIfNeeded() {
    guard !MixAssistFirebaseBootstrap.didConfigureSignals else { return }
    signal(SIGPIPE, SIG_IGN)
    MixAssistFirebaseBootstrap.didConfigureSignals = true
}

private func configureMixAssistFirestoreIfNeeded() {
    guard !MixAssistFirebaseBootstrap.didConfigureFirestore else { return }
    let settings = FirestoreSettings()
    settings.cacheSettings = MemoryCacheSettings()
    Firestore.firestore().settings = settings
    MixAssistFirebaseBootstrap.didConfigureFirestore = true
}

@main
struct ProdConnectMixAssistApp: App {
    @StateObject private var store: ProdConnectStore

    init() {
        configureMixAssistProcessSignalsIfNeeded()
        configureMixAssistFirebaseIfNeeded()
        _store = StateObject(wrappedValue: ProdConnectStore.shared)
    }

    var body: some Scene {
        WindowGroup("ProdConnect Mix Assist") {
            MixAssistGatewayView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1440, minHeight: 880)
        }
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unifiedCompact)
    }
}

private struct MixAssistGatewayView: View {
    @EnvironmentObject private var store: ProdConnectStore

    var body: some View {
        Group {
            if store.user == nil {
                MixAssistSignInView()
            } else {
                MixAssistRootView()
            }
        }
    }
}

private struct MixAssistSignInView: View {
    @EnvironmentObject private var store: ProdConnectStore
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.06, blue: 0.09),
                    Color(red: 0.03, green: 0.11, blue: 0.16)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Text("ProdConnect Mix Assist")
                    .font(.system(size: 34, weight: .bold, design: .rounded))

                Text("Sign in with your ProdConnect account to load patchsheet and Run of Show context.")
                    .foregroundStyle(.secondary)

                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                Button(isWorking ? "Signing In..." : "Sign In") {
                    signIn()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isWorking || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
            }
            .padding(28)
            .frame(width: 420)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private func signIn() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !password.isEmpty else { return }

        isWorking = true
        errorMessage = nil
        store.signIn(email: trimmedEmail, password: password) { result in
            DispatchQueue.main.async {
                isWorking = false
                if case let .failure(error) = result {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
