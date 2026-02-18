# Copilot / AI Agent Instructions for ProdConnect

Purpose: Quickly orient an AI coding agent to be productive in this iOS SwiftUI codebase.

- **Project Type:** iOS SwiftUI app (single-target) using Firebase (Auth, Firestore, Storage), StoreKit 2 for IAP, and OneSignal push; Cloud Functions in `functions/` handle chat notifications.
- **Main App Entry:** `ProdConnectApp` in `ProdConnect/ProdConnect/ContentView.swift`.

Key Concepts & Architecture
- **Single shared store:** `ProdConnectStore.shared` (in `ContentView.swift`) is the app's central ObservableObject. It holds app state, Firestore references, snapshot listeners, and permission logic. Prefer updating state through this store rather than adding independent global state.
- **Firestore collections:** The app uses these collection names (exact strings used in queries): `users`, `gear`, `lessons`, `checklists`, `ideas`, `channels`, `patchsheet`, plus team subcollections `teams/{code}/locations` and `teams/{code}/rooms`. Use the same collection names and include a `teamCode` field on documents to ensure they are scoped correctly.
- **Team scoping:** Queries use `.whereField("teamCode", isEqualTo: teamCode)` — ensure any new records include `teamCode` or they won't appear for a team.
- **Models are in `ContentView.swift`:** Many Codable/Identifiable models (e.g., `UserProfile`, `TrainingLesson`, `GearItem`) are defined inside `ContentView.swift`. When changing fields, update the Firestore save/load logic and consider backwards compatibility (legacy key `name` vs `displayName` is handled there).
- **Permissions model:** `UserProfile` has boolean flags (`isAdmin`, `canEditTraining`, etc.). UI visibility and edit permissions derive from these flags and from `UserProfile.role`. Update both the model and Firestore `users` documents when changing permissions logic.
- **Role & tier logic:** `UserProfile.subscriptionTier` + `isAdmin` map to `UserProfile.Role` (free/basic/premium/admin). Free users are filtered to their own data in several queries.
- **Large data strategy:** Gear and patchsheet are intentionally lazy-loaded and paged (`gearPageSize`), with batch writes chunked to 250 docs to avoid Firestore 16MB limits; Firestore offline persistence is disabled in `ProdConnectStore.init()`.
- **Save/listen helpers:** Use `ProdConnectStore.save(_:collection:)` (setData merge) and the existing listen patterns (e.g., `listenToTeamData`, `listenCollection`) to keep real-time lists consistent.
- **IAP / Admin unlock:** `IAPManager` (in `ContentView.swift`) uses product IDs `Basic1` and `Premium1` (see `Products.storekit`). Purchases unlock admin/premium by setting `isAdmin`, `subscriptionTier`, and (if missing) generating a `teamCode` and saving to `users` + `teams`. To update product ids or entitlement logic, edit `IAPManager` here.
- **Video upload flow:** `AddTrainingLessonView.swift` uploads videos to Firebase Storage under path `trainingVideos/<uuid>.mov` and stores the download URL in `TrainingLesson.urlString`. The picker uses `PHPickerViewController` and copies temp files before upload — respect this flow when modifying uploads.
- **Auth & invites:** `AdminView.swift` uses `store.signUp(...)` to create invite users with a temporary password (`changeme123` in current code). After sign-up it writes `displayName` to Firestore. Creating users this way also triggers the store's listeners; be cautious when changing that flow.

Developer Workflows
- **Open & build:** Use Xcode. From repo root open `ProdConnect/ProdConnect.xcodeproj` or run `xed .` (device builds need signing).
- **Firebase config:** `GoogleService-Info.plist` is already in `ProdConnect/ProdConnect/`. Ensure the file exists and matches the Firebase project used for development; missing or incorrect plist will prevent Firebase from initializing.

Integration Points & External Dependencies
- **Firebase:** Auth, Firestore, Storage. Firestore document shapes should match Codable models in `ContentView.swift`.
- **OneSignal:** Initialized in `AppDelegate.swift`; login/logout uses `OneSignal.login(email)` / `OneSignal.logout()` in the store. Cloud Function `functions/index.js` sends chat notifications using OneSignal external user IDs (emails).
- **StoreKit / App Store:** Product IDs are `Basic1` and `Premium1` (see `Products.storekit`). Entitlement checking happens via `Transaction.currentEntitlements`.
- **Photos / Video:** PHPicker (PhotoKit) is used in `VideoPickerView.swift` and `AddTrainingLessonView.swift` — the app copies selected assets to a temp URL and then uploads.

Quick file references (examples)
- `ProdConnect/ProdConnect/ContentView.swift` — models, `ProdConnectStore`, `IAPManager`, app entry and main navigation.
- `ProdConnect/ProdConnect/AddTrainingLessonView.swift` + `ProdConnect/ProdConnect/VideoPickerView.swift` — video picker + Storage upload; creates `TrainingLesson.urlString`.
- `ProdConnect/ProdConnect/AdminView.swift` — invite flow and permission toggles; updates Firestore `users` documents directly.
- `ProdConnect/ProdConnect/AppDelegate.swift` — Firebase + OneSignal initialization.
- `functions/index.js` — Cloud Function that sends OneSignal chat notifications on channel updates.

If something is unclear or you want this guidance expanded (e.g., add recommended unit tests, CI commands, or a developer quick-start for Firebase project setup), tell me which section to expand or supply any missing credentials/notes and I'll iterate.
