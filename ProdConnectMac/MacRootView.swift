import AVKit
import AppKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import StoreKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

private enum MacFreshserviceAPI {
    private static func normalizedBaseURL(from apiUrl: String) -> URL? {
        let trimmed = apiUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard var components = URLComponents(string: withScheme),
              let host = components.host,
              !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        components.scheme = "https"
        components.user = nil
        components.password = nil
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private static func extractItems(from jsonObject: Any, preferredKeys: [String]) -> [[String: Any]]? {
        if let items = jsonObject as? [[String: Any]] {
            return items
        }
        guard let json = jsonObject as? [String: Any] else { return nil }
        for key in preferredKeys {
            if let items = json[key] as? [[String: Any]] {
                return items
            }
        }
        for (_, value) in json {
            if let items = value as? [[String: Any]] {
                return items
            }
        }
        return nil
    }

    private static func extractErrorMessage(from data: Data, response: HTTPURLResponse?) -> String {
        let fallback = "Freshservice request failed with status \(response?.statusCode ?? 0)."
        guard !data.isEmpty else { return fallback }
        if let jsonObject = try? JSONSerialization.jsonObject(with: data),
           let json = jsonObject as? [String: Any] {
            if let description = json["description"] as? String, !description.isEmpty { return description }
            if let message = json["message"] as? String, !message.isEmpty { return message }
        }
        if let body = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !body.isEmpty,
           !body.hasPrefix("<") {
            return body
        }
        return fallback
    }

    private static func performListRequest(
        apiKey: String,
        apiUrl: String,
        endpoint: String,
        queryItems: [URLQueryItem] = [],
        completion: @escaping (Result<[[String: Any]], Error>) -> Void
    ) {
        guard let baseURL = normalizedBaseURL(from: apiUrl) else {
            completion(.failure(NSError(
                domain: "Freshservice",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Invalid Freshservice URL. Enter only the base URL, like https://yourcompany.freshservice.com."]
            )))
            return
        }
        let normalizedEndpoint = endpoint.hasPrefix("/") ? String(endpoint.dropFirst()) : endpoint
        let urlString = baseURL.absoluteString.hasSuffix("/") ? "\(baseURL.absoluteString)\(normalizedEndpoint)" : "\(baseURL.absoluteString)/\(normalizedEndpoint)"
        guard var components = URLComponents(string: urlString) else {
            completion(.failure(NSError(domain: "Freshservice", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid Freshservice URL."])))
            return
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            completion(.failure(NSError(domain: "Freshservice", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid Freshservice URL."])))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let credentialData = "\(apiKey):X".data(using: .utf8) ?? Data()
        request.setValue("Basic \(credentialData.base64EncodedString())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse, let data else {
                completion(.failure(NSError(
                    domain: "Freshservice",
                    code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "Freshservice returned an invalid response."]
                )))
                return
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                completion(.failure(NSError(
                    domain: "Freshservice",
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: extractErrorMessage(from: data, response: httpResponse)]
                )))
                return
            }
            if data.isEmpty {
                completion(.success([]))
                return
            }
            do {
                let jsonObject = try JSONSerialization.jsonObject(with: data)
                let preferredKeys = endpoint.contains("tickets")
                    ? ["tickets", "results", "data"]
                    : ["assets", "config_items", "cis", "results", "data"]
                if let items = extractItems(from: jsonObject, preferredKeys: preferredKeys) {
                    completion(.success(items))
                } else {
                    completion(.failure(NSError(
                        domain: "Freshservice",
                        code: httpResponse.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: "Freshservice returned a response in an unsupported format."]
                    )))
                }
            } catch {
                completion(.failure(NSError(
                    domain: "Freshservice",
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "Freshservice returned non-JSON data."]
                )))
            }
        }.resume()
    }

    static func fetchAllAssetsWithAPIKey(
        apiKey: String,
        apiUrl: String,
        perPage: Int = 100,
        maxPages: Int = 200,
        completion: @escaping (Result<([[String: Any]], Bool), Error>) -> Void
    ) {
        func fetchPage(_ page: Int, collected: [[String: Any]]) {
            let queryItems = [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "per_page", value: String(perPage))
            ]
            performListRequest(apiKey: apiKey, apiUrl: apiUrl, endpoint: "api/v2/assets", queryItems: queryItems) { result in
                switch result {
                case .success(let items):
                    let merged = collected + items
                    let reachedCap = page >= maxPages && items.count >= perPage
                    let shouldContinue = !items.isEmpty && items.count >= perPage && page < maxPages
                    if shouldContinue {
                        fetchPage(page + 1, collected: merged)
                    } else {
                        completion(.success((merged, reachedCap)))
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
        fetchPage(1, collected: [])
    }

    static func fetchAllTicketsWithAPIKey(
        apiKey: String,
        apiUrl: String,
        perPage: Int = 100,
        maxPages: Int = 200,
        completion: @escaping (Result<([[String: Any]], Bool), Error>) -> Void
    ) {
        func fetchPage(_ page: Int, collected: [[String: Any]]) {
            let queryItems = [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "per_page", value: String(perPage))
            ]
            performListRequest(apiKey: apiKey, apiUrl: apiUrl, endpoint: "api/v2/tickets", queryItems: queryItems) { result in
                switch result {
                case .success(let items):
                    let merged = collected + items
                    let reachedCap = page >= maxPages && items.count >= perPage
                    let shouldContinue = !items.isEmpty && items.count >= perPage && page < maxPages
                    if shouldContinue {
                        fetchPage(page + 1, collected: merged)
                    } else {
                        completion(.success((merged, reachedCap)))
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
        fetchPage(1, collected: [])
    }
}

private enum MacRoute: String, CaseIterable, Identifiable {
    case chat
    case patchsheet
    case training
    case gear
    case tickets
    case checklists
    case ideas
    case customize
    case users
    case account

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat: return "Chat"
        case .patchsheet: return "Patchsheet"
        case .training: return "Training"
        case .gear: return "Assets"
        case .tickets: return "Tickets"
        case .checklists: return "Checklist"
        case .ideas: return "Ideas"
        case .customize: return "Customize"
        case .users: return "Users"
        case .account: return "Account"
        }
    }

    var icon: String {
        switch self {
        case .chat: return "message"
        case .patchsheet: return "square.grid.3x2"
        case .training: return "graduationcap"
        case .gear: return "shippingbox"
        case .tickets: return "ticket"
        case .checklists: return "checklist"
        case .ideas: return "lightbulb"
        case .customize: return "paintbrush"
        case .users: return "person.3"
        case .account: return "person.crop.circle"
        }
    }

}

private func externalTicketFormSlug(from organizationName: String) -> String {
    let trimmed = organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "prodconnect" }

    let lowered = trimmed.lowercased()
    let allowed = CharacterSet.alphanumerics
    var slug = ""
    var previousWasHyphen = false

    for scalar in lowered.unicodeScalars {
        if allowed.contains(scalar) {
            slug.unicodeScalars.append(scalar)
            previousWasHyphen = false
        } else if !previousWasHyphen {
            slug.append("-")
            previousWasHyphen = true
        }
    }

    slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return slug.isEmpty ? "prodconnect" : slug
}

private func adaptiveTableColumnWidths(
    availableWidth: CGFloat,
    minimums: [CGFloat],
    weights: [CGFloat],
    horizontalPadding: CGFloat = 28
) -> [CGFloat] {
    guard minimums.count == weights.count, !minimums.isEmpty else { return minimums }
    let totalMinimum = minimums.reduce(0, +)
    let usableWidth = max(availableWidth - horizontalPadding, totalMinimum)
    let extraWidth = max(usableWidth - totalMinimum, 0)
    let totalWeight = max(weights.reduce(0, +), 1)

    return zip(minimums, weights).map { minimum, weight in
        minimum + (extraWidth * (weight / totalWeight))
    }
}

struct MacRootView: View {
    @EnvironmentObject private var store: ProdConnectStore
    @State private var selectedRoute: MacRoute? = .chat
    @State private var isShowingNotifications = false
    @State private var showsWelcomeScreen = true

    private var sidebarRoutes: [MacRoute] {
        MacRoute.allCases.filter { route in
            switch route {
            case .chat:
                return store.canSeeChat
            case .training:
                return store.canSeeTrainingTab
            case .tickets:
                return store.canUseTickets
            default:
                return true
            }
        }
    }

    private var shellGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.02, green: 0.04, blue: 0.1),
                Color(red: 0.03, green: 0.18, blue: 0.3),
                Color.black
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        Group {
            if store.user == nil {
                MacLoginView()
            } else {
                ZStack {
                    shellGradient
                        .ignoresSafeArea()

                    if showsWelcomeScreen {
                        MacWelcomeView(
                            userDisplayName: userDisplayName,
                            organizationDisplayName: organizationDisplayName,
                            routes: sidebarRoutes,
                            openRoute: { route in
                                selectedRoute = route
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showsWelcomeScreen = false
                                }
                            }
                        )
                    } else {
                        NavigationSplitView {
                            sidebar
                        } detail: {
                            detail
                        }
                        .navigationSplitViewStyle(.balanced)
                        .toolbar {
                            ToolbarItem(placement: .primaryAction) {
                                Button {
                                    isShowingNotifications = true
                                } label: {
                                    ZStack(alignment: .topTrailing) {
                                        Image(systemName: notificationBadgeCount > 0 ? "bell.badge.fill" : "bell")
                                            .font(.system(size: 16, weight: .semibold))

                                        if notificationBadgeCount > 0 {
                                            Text(notificationBadgeCount > 99 ? "99+" : "\(notificationBadgeCount)")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(Color.red, in: Capsule())
                                                .offset(x: 10, y: -8)
                                        }
                                    }
                                }
                                .help("Notifications")
                            }
                        }
                    }
                }
                .onAppear {
                    if let selectedRoute, !sidebarRoutes.contains(selectedRoute) {
                        self.selectedRoute = sidebarRoutes.first
                    } else if selectedRoute == nil {
                        self.selectedRoute = sidebarRoutes.first
                    }
                }
                .onChange(of: store.user?.id) { _, newValue in
                    showsWelcomeScreen = newValue != nil
                }
                .sheet(isPresented: $isShowingNotifications) {
                    MacNotificationsView()
                        .environmentObject(store)
                }
            }
        }
        .multilineTextAlignment(.leading)
    }

    private var notificationBadgeCount: Int {
        store.notificationBadgeCount
    }

    private var userDisplayName: String {
        let trimmedName = store.user?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedName.isEmpty {
            return trimmedName
        }

        let fallbackEmail = store.user?.email.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let prefix = fallbackEmail.split(separator: "@").first, !prefix.isEmpty {
            return String(prefix)
        }
        return "User"
    }

    private var organizationDisplayName: String? {
        let trimmedName = store.organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? nil : trimmedName
    }

    private var sidebar: some View {
        List(sidebarRoutes, selection: $selectedRoute) { route in
            Label(route.title, systemImage: route.icon)
                .tag(route)
        }
        .navigationTitle("ProdConnect")
        .scrollContentBackground(.hidden)
        .background(Color.black.opacity(0.2))
    }

    @ViewBuilder
    private var detail: some View {
        switch selectedRoute ?? .chat {
        case .chat:
            MacChatView()
        case .patchsheet:
            MacPatchsheetView()
        case .training:
            MacTrainingView()
        case .gear:
            MacGearView()
        case .tickets:
            MacTicketsView()
        case .checklists:
            MacChecklistView()
        case .ideas:
            MacIdeasView()
        case .customize:
            MacCustomizeView()
        case .users:
            MacUsersView()
        case .account:
            MacAccountView()
        }
    }
}

private struct MacWelcomeView: View {
    let userDisplayName: String
    let organizationDisplayName: String?
    let routes: [MacRoute]
    let openRoute: (MacRoute) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.11, green: 0.55, blue: 0.53).opacity(0.2))
                .frame(width: 320, height: 320)
                .blur(radius: 28)
                .offset(x: -220, y: -170)

            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 260, height: 260)
                .blur(radius: 30)
                .offset(x: 240, y: 200)

            VStack {
                Spacer()

                VStack(spacing: 24) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 92, height: 92)

                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    VStack(spacing: 10) {
                        Text("Welcome")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.68))

                        Text(userDisplayName)
                            .font(.system(size: 46, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)

                        if let organizationDisplayName, !organizationDisplayName.isEmpty {
                            Text(organizationDisplayName)
                                .font(.system(size: 28, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.82))
                                .multilineTextAlignment(.center)
                        }
                    }

                    Text("You’re signed in and ready to jump back in.")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)

                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(routes) { route in
                            Button {
                                openRoute(route)
                            } label: {
                                VStack(spacing: 10) {
                                    Image(systemName: route.icon)
                                        .font(.system(size: 20, weight: .semibold))
                                    Text(route.title)
                                        .font(.subheadline.weight(.semibold))
                                        .multilineTextAlignment(.center)
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 88)
                                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 36)
                .padding(.vertical, 38)
                .frame(maxWidth: 560)
                .background(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 34, style: .continuous)
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        )
                )
                .shadow(color: Color.black.opacity(0.28), radius: 30, x: 0, y: 22)

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 44)
        .padding(.vertical, 36)
    }
}

private struct MacNotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ProdConnectStore

    var body: some View {
        NavigationStack {
            List {
                if store.notificationIncomingChannels.isEmpty
                    && store.notificationAssignedTickets.isEmpty
                    && store.notificationTicketReminders.isEmpty
                    && store.checklistNotificationNotices.isEmpty
                    && store.checklistReminderNotices.isEmpty {
                    Text("No notifications")
                        .foregroundStyle(.secondary)
                }

                if !store.notificationIncomingChannels.isEmpty {
                    Section("Messages") {
                        ForEach(store.notificationIncomingChannels) { channel in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(channel.name.isEmpty ? "Chat" : channel.name)
                                    .font(.headline)
                                if let last = channel.messages.last {
                                    Text(last.text.isEmpty ? "New attachment" : last.text)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                if !store.notificationAssignedTickets.isEmpty {
                    Section("Assigned Tickets") {
                        ForEach(store.notificationAssignedTickets) { ticket in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(ticket.title.isEmpty ? "Untitled Ticket" : ticket.title)
                                    .font(.headline)
                                Text(ticket.status.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                if !store.notificationTicketReminders.isEmpty {
                    Section("Ticket Reminders") {
                        ForEach(store.notificationTicketReminders) { notice in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(notice.ticket.title.isEmpty ? "Untitled Ticket" : notice.ticket.title)
                                    .font(.headline)
                                Text("\(notice.kind.title) • \(notice.ticket.dueDate?.formatted(date: .abbreviated, time: .shortened) ?? "")")
                                    .font(.caption)
                                    .foregroundStyle(notice.kind == .overdue ? .red : .secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                if !store.checklistNotificationNotices.isEmpty {
                    Section("Checklist Assignments") {
                        ForEach(store.checklistNotificationNotices) { notice in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(notice.checklist.title)
                                    .font(.headline)
                                Text(notice.item.text)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                if !store.checklistReminderNotices.isEmpty {
                    Section("Checklist Reminders") {
                        ForEach(store.checklistReminderNotices) { notice in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(notice.checklist.title)
                                    .font(.headline)
                                Text("\(notice.kind.title) • \(notice.checklist.dueDate?.formatted(date: .abbreviated, time: .shortened) ?? "")")
                                    .font(.caption)
                                    .foregroundStyle(notice.kind == .overdue ? .red : .secondary)
                                if let preview = notice.itemPreview, !preview.isEmpty {
                                    Text(preview)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("Notifications")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        closeNotifications()
                    }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 420)
        .onDisappear {
            store.markAllNotificationsSeen()
        }
    }

    private func closeNotifications() {
        store.markAllNotificationsSeen()
        dismiss()
    }
}

private struct MacLoginView: View {
    @EnvironmentObject private var store: ProdConnectStore
    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var teamCode = ""
    @State private var errorMessage = ""
    @State private var isWorking = false

    private var fallbackGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.02, green: 0.04, blue: 0.1),
                Color(red: 0.03, green: 0.18, blue: 0.3),
                Color.black
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        ZStack {
            Group {
                if NSImage(named: "BackgroundImage") != nil {
                    Image("BackgroundImage")
                        .resizable()
                        .scaledToFill()
                        .ignoresSafeArea()
                } else {
                    fallbackGradient.ignoresSafeArea()
                }
            }

            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    Text("ProdConnect")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                    Text("Where Production Comes Together")
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 14) {
                    Picker("Mode", selection: $isSignUp) {
                        Text("Sign In").tag(false)
                        Text("Create Account").tag(true)
                    }
                    .pickerStyle(.segmented)

                    TextField("Email", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(trySubmitFromKeyboard)

                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(trySubmitFromKeyboard)

                    if isSignUp {
                        TextField("Team Code (optional)", text: $teamCode)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(trySubmitFromKeyboard)
                    }

                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button(isSignUp ? "Create Account" : "Sign In", action: submit)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(isWorking || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
                }
                .frame(width: 460)
                .padding(40)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .frame(width: 560)
            }
        }
    }

    private func submit() {
        isWorking = true
        errorMessage = ""
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCode = teamCode.trimmingCharacters(in: .whitespacesAndNewlines)

        let finish: (Result<Void, Error>) -> Void = { result in
            DispatchQueue.main.async {
                isWorking = false
                if case .failure(let error) = result {
                    errorMessage = error.localizedDescription
                }
            }
        }

        if isSignUp {
            store.signUp(email: trimmedEmail, password: password, teamCode: trimmedCode.isEmpty ? nil : trimmedCode, completion: finish)
        } else {
            store.signIn(email: trimmedEmail, password: password, completion: finish)
        }
    }

    private func trySubmitFromKeyboard() {
        guard !isWorking else { return }
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !password.isEmpty else { return }
        submit()
    }
}

private struct MacChatView: View {
    @EnvironmentObject private var store: ProdConnectStore
    @State private var selectedChannelID: String?
    @State private var newChannelName = ""
    @State private var draftMessage = ""
    @State private var editingMessageID: String?
    @State private var pendingDeleteMessage: ChatMessage?
    @State private var pendingAttachmentURL: URL?
    @State private var pendingAttachmentName: String?
    @State private var pendingAttachmentKind: ChatAttachmentKind?
    @State private var previewAttachment: MacChatAttachmentPreviewItem?
    @State private var isUploadingAttachment = false
    @State private var attachmentError: String?

    private var currentEmail: String? {
        store.user?.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var groupChannels: [ChatChannel] {
        store.channels
            .filter { $0.kind == .group }
            .sorted { $0.position < $1.position }
    }

    private var directChannels: [ChatChannel] {
        store.channels
            .filter { $0.kind == .direct }
            .filter { channel in
                guard let currentEmail else { return true }
                let participants = channel.participantEmails.map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                }
                return participants.isEmpty || participants.contains(currentEmail)
            }
            .sorted { lhs, rhs in
                let lhsDate = lhs.lastMessageAt ?? .distantPast
                let rhsDate = rhs.lastMessageAt ?? .distantPast
                if lhsDate == rhsDate {
                    return channelTitle(lhs) < channelTitle(rhs)
                }
                return lhsDate > rhsDate
            }
    }

    private var directMessageUsersToShow: [UserProfile] {
        guard let currentEmail else { return [] }
        let existingOneToOneRecipients = Set(
            directChannels.compactMap { channel -> String? in
                let participants = channel.participantEmails
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .filter { !$0.isEmpty }
                guard participants.count == 2, participants.contains(currentEmail) else { return nil }
                return participants.first(where: { $0 != currentEmail })
            }
        )

        return store.teamMembers
            .filter {
                let email = $0.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return email != currentEmail && !existingOneToOneRecipients.contains(email)
            }
            .sorted { lhs, rhs in
                let lhsName = lhs.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                let rhsName = rhs.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !lhsName.isEmpty && !rhsName.isEmpty {
                    return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
                }
                return lhs.email.localizedCaseInsensitiveCompare(rhs.email) == .orderedAscending
            }
    }

    private var selectedChannel: ChatChannel? {
        store.channels.first(where: { $0.id == selectedChannelID }) ?? groupChannels.first ?? directChannels.first
    }

    var body: some View {
        GeometryReader { proxy in
            let sidebarWidth = min(300, max(240, proxy.size.width * 0.26))

            HStack(spacing: 0) {
                VStack(spacing: 12) {
                    HStack {
                        TextField("New channel", text: $newChannelName)
                        Button("Add") {
                            let name = newChannelName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !name.isEmpty else { return }
                            let channel = ChatChannel(
                                name: name,
                                teamCode: store.teamCode ?? "",
                                position: store.nextChannelPosition()
                            )
                            store.saveChannel(channel)
                            selectedChannelID = channel.id
                            newChannelName = ""
                        }
                    }
                    List(selection: $selectedChannelID) {
                        Section("Channels") {
                            ForEach(groupChannels) { channel in
                                channelRow(channel)
                                    .tag(channel.id)
                            }
                            .onMove(perform: moveChannels)
                        }
                        Section("Direct Messages") {
                            ForEach(directChannels) { channel in
                                channelRow(channel)
                                    .tag(channel.id)
                            }
                            ForEach(directMessageUsersToShow) { member in
                                Button {
                                    openOrCreateDirectMessage(with: [member])
                                } label: {
                                    Text(displayName(for: member.email))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
                .frame(width: sidebarWidth, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .padding()
                .background(Color.clear)

                Divider()

                Group {
                    if let channel = selectedChannel {
                        VStack(spacing: 0) {
                            ScrollViewReader { reader in
                                GeometryReader { scrollProxy in
                                    ScrollView {
                                        LazyVStack(alignment: .leading, spacing: 0) {
                                            ForEach(Array(channel.messages.enumerated()), id: \.element.id) { index, message in
                                                VStack(alignment: .leading, spacing: 0) {
                                                    if shouldShowDateHeader(for: index, in: channel.messages) {
                                                        Text(dateHeaderText(for: message.timestamp))
                                                            .font(.caption)
                                                            .foregroundStyle(.secondary)
                                                            .padding(.top, index == 0 ? 4 : 14)
                                                            .padding(.bottom, 8)
                                                            .frame(maxWidth: .infinity, alignment: .center)
                                                    }

                                                    VStack(alignment: .leading, spacing: 4) {
                                                        Text(displayName(for: message.author)).font(.headline)
                                                        if !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                                            Text(message.text)
                                                        }
                                                        HStack(spacing: 8) {
                                                            Text(message.timestamp, style: .time)
                                                            if message.editedAt != nil {
                                                                Text("Edited")
                                                            }
                                                        }
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                        attachmentView(for: message)
                                                    }
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                    .padding(.vertical, 14)
                                                    .padding(.leading, 12)
                                                    .padding(.trailing, 12)
                                                    .overlay(alignment: .bottom) {
                                                        Divider()
                                                    }
                                                    .contextMenu {
                                                        Button("Edit") {
                                                            beginEditing(message)
                                                        }
                                                        .disabled(channel.isReadOnly)

                                                        Button("Delete", role: .destructive) {
                                                            pendingDeleteMessage = message
                                                        }
                                                        .disabled(channel.isReadOnly)
                                                    }
                                                    .id(message.id)
                                                }
                                            }
                                        }
                                        .frame(width: scrollProxy.size.width, alignment: .leading)
                                    }
                                    .onAppear {
                                        scrollToLatestMessage(using: reader, in: channel)
                                    }
                                    .onChange(of: channel.messages.count) { _, _ in
                                        scrollToLatestMessage(using: reader, in: channel)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                            Divider()

                            VStack(spacing: 8) {
                                if let pendingAttachmentName {
                                    HStack(spacing: 8) {
                                        Image(systemName: pendingAttachmentKind == .image ? "photo" : "doc")
                                            .foregroundStyle(.secondary)
                                        Text(pendingAttachmentName)
                                            .font(.caption)
                                            .lineLimit(1)
                                        Button(role: .destructive) {
                                            clearPendingAttachment()
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                        }
                                    }
                                }

                                HStack {
                                    Button {
                                        pickAttachment(allowedTypes: [.image], preferredKind: .image)
                                    } label: {
                                        Image(systemName: "photo.on.rectangle")
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(channel.isReadOnly || isUploadingAttachment || editingMessageID != nil)

                                    Button {
                                        pickAttachment(allowedTypes: [.data], preferredKind: .file)
                                    } label: {
                                        Image(systemName: "paperclip")
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(channel.isReadOnly || isUploadingAttachment || editingMessageID != nil)

                                    TextField("Message", text: $draftMessage)
                                        .onSubmit {
                                            saveMessage(in: channel)
                                        }
                                        .disabled(isUploadingAttachment)
                                    if editingMessageID != nil {
                                        Button("Cancel") {
                                            cancelMessageEditing()
                                        }
                                    }
                                    Button(editingMessageID == nil ? "Send" : "Save") {
                                        saveMessage(in: channel)
                                    }
                                    .controlSize(.large)
                                    .disabled(channel.isReadOnly || isUploadingAttachment)
                                }

                                if isUploadingAttachment {
                                    ProgressView()
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }

                                if let attachmentError {
                                    Text(attachmentError)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 16)
                            .padding(.leading, 16)
                            .padding(.bottom, 16)
                            .padding(.trailing, 28)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .navigationTitle(channelTitle(channel))
                        .background(Color.clear)
                        .alert("Delete Message?", isPresented: isShowingDeleteMessageAlert, presenting: pendingDeleteMessage) { message in
                            Button("Cancel", role: .cancel) { }
                            Button("Delete", role: .destructive) {
                                deleteMessage(message, from: channel)
                            }
                        } message: { _ in
                            Text("This will permanently remove the message.")
                        }
                    } else {
                        ContentUnavailableView("No Channels", systemImage: "message", description: Text("Create or select a channel."))
                    }
                }
                .frame(width: max(proxy.size.width - sidebarWidth - 13, 0), alignment: .topLeading)
                .padding(.trailing, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            selectedChannelID = selectedChannelID ?? groupChannels.first?.id ?? directChannels.first?.id
        }
        .onChange(of: selectedChannelID) { _, _ in
            cancelMessageEditing()
        }
        .sheet(item: $previewAttachment) { item in
            MacChatAttachmentPreviewView(item: item)
        }
    }

    @ViewBuilder
    private func channelRow(_ channel: ChatChannel) -> some View {
        Text(channelTitle(channel))
    }

    private func displayName(for email: String) -> String {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.isEmpty {
            return "Unknown"
        }
        if let member = store.teamMembers.first(where: {
            $0.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized
        }) {
            return member.displayName
        }
        if let user = store.user,
           user.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized {
            return user.displayName
        }
        return email.components(separatedBy: "@").first ?? email
    }

    private func openOrCreateDirectMessage(with members: [UserProfile]) {
        guard let teamCode = store.teamCode?.trimmingCharacters(in: .whitespacesAndNewlines), !teamCode.isEmpty else { return }
        guard let currentEmail else { return }

        let recipients = members
            .map { $0.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && $0 != currentEmail }
        guard !recipients.isEmpty else { return }

        let participants = Array(Set(recipients + [currentEmail])).sorted()
        if let existing = store.channels.first(where: { channel in
            channel.kind == .direct
                && channel.participantEmails.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.sorted() == participants
        }) {
            selectedChannelID = existing.id
            return
        }

        let newChannel = ChatChannel(
            name: "Direct Message",
            teamCode: teamCode,
            position: 0,
            isReadOnly: false,
            isHidden: false,
            readOnlyUserEmails: [],
            hiddenUserEmails: [],
            messages: [],
            kind: .direct,
            participantEmails: participants,
            lastMessageAt: nil
        )
        store.saveChannel(newChannel)
        selectedChannelID = newChannel.id
    }

    private func channelTitle(_ channel: ChatChannel) -> String {
        guard channel.kind == .direct else { return channel.name }

        let currentUserEmail = store.user?.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let names = channel.participantEmails
            .filter { email in
                let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return normalized != currentUserEmail
            }
            .map(displayName(for:))

        if !names.isEmpty {
            return names.joined(separator: ", ")
        }
        return channel.name
    }

    private func shouldShowDateHeader(for index: Int, in messages: [ChatMessage]) -> Bool {
        guard messages.indices.contains(index) else { return false }
        guard index > 0 else { return true }
        return !Calendar.current.isDate(messages[index].timestamp, inSameDayAs: messages[index - 1].timestamp)
    }

    private func dateHeaderText(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "Today"
        }
        if Calendar.current.isDateInYesterday(date) {
            return "Yesterday"
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func moveChannels(from source: IndexSet, to destination: Int) {
        var reordered = groupChannels
        reordered.move(fromOffsets: source, toOffset: destination)

        for (index, channel) in reordered.enumerated() {
            var updated = channel
            updated.position = index
            store.saveChannel(updated)
        }
    }

    private var isShowingDeleteMessageAlert: Binding<Bool> {
        Binding(
            get: { pendingDeleteMessage != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteMessage = nil
                }
            }
        )
    }

    private func beginEditing(_ message: ChatMessage) {
        editingMessageID = message.id
        draftMessage = message.text
        attachmentError = nil
    }

    private func cancelMessageEditing() {
        editingMessageID = nil
        draftMessage = ""
        pendingDeleteMessage = nil
        attachmentError = nil
    }

    private func saveMessage(in channel: ChatChannel) {
        let text = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if let currentEditingMessageID = editingMessageID,
           let index = channel.messages.firstIndex(where: { $0.id == currentEditingMessageID }) {
            guard !text.isEmpty else { return }
            var updated = channel
            updated.messages[index].text = text
            updated.messages[index].editedAt = Date()
            updated.lastMessageAt = updated.messages.last?.timestamp
            store.saveChannel(updated)
            editingMessageID = nil
            draftMessage = ""
            return
        }

        if let pendingAttachmentName,
           let pendingAttachmentKind,
           let pendingAttachmentURL {
            isUploadingAttachment = true
            attachmentError = nil
            uploadAttachment(localURL: pendingAttachmentURL, for: channel) { result in
                DispatchQueue.main.async {
                    self.isUploadingAttachment = false
                    switch result {
                    case .success(let urlString):
                        var updated = channel
                        updated.messages.append(
                            ChatMessage(
                                author: store.user?.email ?? "unknown",
                                text: text,
                                timestamp: Date(),
                                editedAt: nil,
                                attachmentURL: urlString,
                                attachmentName: pendingAttachmentName,
                                attachmentKind: pendingAttachmentKind
                            )
                        )
                        updated.lastMessageAt = updated.messages.last?.timestamp
                        store.saveChannel(updated)
                        clearPendingAttachment()
                        draftMessage = ""
                    case .failure(let error):
                        attachmentError = "Attachment upload failed: \(error.localizedDescription)"
                    }
                }
            }
        } else {
            guard !text.isEmpty else { return }
            var updated = channel
            updated.messages.append(
                ChatMessage(
                    author: store.user?.email ?? "unknown",
                    text: text,
                    timestamp: Date()
                )
            )
            updated.lastMessageAt = updated.messages.last?.timestamp
            store.saveChannel(updated)
            draftMessage = ""
        }
    }

    private func deleteMessage(_ message: ChatMessage, from channel: ChatChannel) {
        var updated = channel
        updated.messages.removeAll { $0.id == message.id }
        updated.lastMessageAt = updated.messages.last?.timestamp
        store.saveChannel(updated)
        pendingDeleteMessage = nil
        if editingMessageID == message.id {
            cancelMessageEditing()
        }
    }

    @ViewBuilder
    private func attachmentView(for message: ChatMessage) -> some View {
        if let urlString = message.attachmentURL,
           let url = URL(string: urlString) {
            if message.attachmentKind == .image {
                Button {
                    openAttachmentURL(url, kind: .image)
                } label: {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 260, maxHeight: 180)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        case .failure:
                            attachmentLinkLabel(name: message.attachmentName ?? "Image")
                        default:
                            ProgressView()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .buttonStyle(.plain)
            } else {
                attachmentLink(url: url, name: message.attachmentName ?? "Attachment")
            }
        }
    }

    private func attachmentLink(url: URL, name: String) -> some View {
        Button {
            openAttachmentURL(url, kind: .file)
        } label: {
            attachmentLinkLabel(name: name)
        }
        .buttonStyle(.plain)
    }

    private func attachmentLinkLabel(name: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc")
            Text(name)
                .lineLimit(1)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func openAttachmentURL(_ url: URL, kind: ChatAttachmentKind) {
        let scheme = (url.scheme ?? "").lowercased()
        let supportedSchemes = ["https", "http", "file"]
        guard supportedSchemes.contains(scheme) else {
            attachmentError = "Unsupported attachment URL."
            return
        }
        previewAttachment = MacChatAttachmentPreviewItem(url: url, kind: kind)
    }

    private func setPendingAttachment(url: URL, kind: ChatAttachmentKind) {
        let inferredType = UTType(filenameExtension: url.pathExtension.lowercased())
        let resolvedKind = kind == .file && inferredType?.conforms(to: .image) == true ? ChatAttachmentKind.image : kind
        pendingAttachmentURL = url
        pendingAttachmentName = url.lastPathComponent
        pendingAttachmentKind = resolvedKind
    }

    private func clearPendingAttachment() {
        pendingAttachmentURL = nil
        pendingAttachmentName = nil
        pendingAttachmentKind = nil
        attachmentError = nil
    }

    private func uploadAttachment(localURL: URL, for channel: ChatChannel, completion: @escaping (Result<String, Error>) -> Void) {
        let filename = (pendingAttachmentName ?? localURL.lastPathComponent)
            .replacingOccurrences(of: " ", with: "_")
        let path = "chatAttachments/\(channel.id)/\(UUID().uuidString)-\(filename)"
        let storageRef = Storage.storage().reference().child(path)

        let didAccess = localURL.startAccessingSecurityScopedResource()
        storageRef.putFile(from: localURL, metadata: nil) { _, error in
            if didAccess {
                localURL.stopAccessingSecurityScopedResource()
            }

            if let error {
                completion(.failure(error))
                return
            }

            storageRef.downloadURL { url, downloadError in
                if let downloadError {
                    completion(.failure(downloadError))
                } else if let absoluteString = url?.absoluteString {
                    completion(.success(absoluteString))
                } else {
                    completion(.failure(NSError(
                        domain: "ProdConnectMacChat",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Missing download URL."]
                    )))
                }
            }
        }
    }

    @MainActor
    private func pickAttachment(allowedTypes: [UTType], preferredKind: ChatAttachmentKind) {
        attachmentError = nil

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = allowedTypes

        if let keyWindow = NSApp.keyWindow {
            panel.beginSheetModal(for: keyWindow) { response in
                guard response == .OK, let url = panel.url else { return }
                self.setPendingAttachment(url: url, kind: preferredKind)
            }
            return
        }

        if panel.runModal() == .OK, let url = panel.url {
            setPendingAttachment(url: url, kind: preferredKind)
        }
    }

    private func scrollToLatestMessage(using reader: ScrollViewProxy, in channel: ChatChannel) {
        guard let lastMessageID = channel.messages.last?.id else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeOut(duration: 0.2)) {
                reader.scrollTo(lastMessageID, anchor: .bottom)
            }
        }
    }
}

private struct MacChatAttachmentPreviewItem: Identifiable {
    let url: URL
    let kind: ChatAttachmentKind

    var id: String { url.absoluteString }
}

private struct MacChatAttachmentPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let item: MacChatAttachmentPreviewItem

    var body: some View {
        NavigationStack {
            Group {
                if item.kind == .image {
                    ScrollView {
                        AsyncImage(url: item.url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .padding()
                            case .failure:
                                MacWebVideoView(url: item.url)
                            default:
                                ProgressView()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                    }
                } else {
                    MacWebVideoView(url: item.url)
                }
            }
            .navigationTitle("Attachment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .frame(minWidth: 720, minHeight: 520)
    }
}

private struct MacPatchsheetView: View {
    @EnvironmentObject private var store: ProdConnectStore
    @State private var selectedCategory = "Audio"
    @State private var field1 = ""
    @State private var field2 = ""
    @State private var field3 = ""
    @State private var field4 = ""
    @State private var selectedPatch: PatchRow?

    private let categories = ["Audio", "Video", "Lighting"]

    private var filtered: [PatchRow] {
        store.patchsheet
            .filter { $0.category == selectedCategory }
            .sorted(by: PatchRow.autoSort)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Category", selection: $selectedCategory) {
                ForEach(categories, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)

            List {
                ForEach(filtered) { item in
                    Button {
                        selectedPatch = item
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.name).font(.headline)
                                Text("\(item.input) -> \(item.output)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if !item.campus.isEmpty {
                                Text(item.campus)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        store.deletePatch(filtered[index])
                    }
                }
            }
            .scrollContentBackground(.hidden)

            GroupBox("Add Patch") {
                VStack(spacing: 10) {
                    TextField(selectedCategory == "Lighting" ? "Fixture" : "Name", text: $field1)
                    HStack(spacing: 10) {
                        TextField(primaryPlaceholder, text: $field2)
                        TextField(secondaryPlaceholder, text: $field3)
                    }
                    if selectedCategory == "Lighting" {
                        TextField("Universe", text: $field4)
                    }
                    Button("Save Patch") {
                        store.savePatch(
                            PatchRow(
                                name: field1,
                                input: field2,
                                output: field3,
                                teamCode: store.teamCode ?? "",
                                category: selectedCategory,
                                campus: "",
                                room: "",
                                channelCount: selectedCategory == "Lighting" ? Int(field3.trimmingCharacters(in: .whitespacesAndNewlines)) : nil,
                                universe: selectedCategory == "Lighting" ? field4.trimmingCharacters(in: .whitespacesAndNewlines) : nil
                            )
                        )
                        field1 = ""
                        field2 = ""
                        field3 = ""
                        field4 = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(field1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding()
        .background(Color.clear)
        .navigationTitle("Patchsheet")
        .sheet(item: $selectedPatch) { patch in
            MacEditPatchView(patch: patch)
                .environmentObject(store)
        }
    }

    private var primaryPlaceholder: String {
        switch selectedCategory {
        case "Video": return "Source"
        case "Lighting": return "DMX Channel"
        default: return "Input"
        }
    }

    private var secondaryPlaceholder: String {
        switch selectedCategory {
        case "Video": return "Destination"
        case "Lighting": return "Channel Count"
        default: return "Output"
        }
    }
}

private struct MacEditPatchView: View {
    @EnvironmentObject private var store: ProdConnectStore
    @Environment(\.dismiss) private var dismiss
    @State private var patch: PatchRow
    @State private var channelCountText = ""
    @State private var universeText = ""
    @State private var errorMessage: String?
    @State private var showDeleteConfirmation = false
    @State private var isSaving = false

    init(patch: PatchRow) {
        _patch = State(initialValue: patch)
        _channelCountText = State(initialValue: patch.channelCount.map(String.init) ?? "")
        _universeText = State(initialValue: patch.universe ?? "")
    }

    private var canEdit: Bool { store.canEditPatchsheet }

    var body: some View {
        NavigationStack {
            Form {
                Section("Patch Details") {
                    TextField("Name", text: $patch.name).disabled(!canEdit)

                    if patch.category == "Lighting" {
                        TextField("DMX Channel", text: $patch.input).disabled(!canEdit)
                        TextField("Channel Count", text: $channelCountText).disabled(!canEdit)
                        TextField("Universe", text: $universeText).disabled(!canEdit)
                    } else if patch.category == "Video" {
                        TextField("Source", text: $patch.input).disabled(!canEdit)
                        TextField("Destination", text: $patch.output).disabled(!canEdit)
                    } else {
                        TextField("Input", text: $patch.input).disabled(!canEdit)
                        TextField("Output", text: $patch.output).disabled(!canEdit)
                    }

                    if store.locations.isEmpty {
                        TextField("Campus/Location", text: $patch.campus).disabled(!canEdit)
                    } else {
                        Picker("Campus/Location", selection: $patch.campus) {
                            Text("Select campus/location").tag("")
                            ForEach(store.locations.sorted(), id: \.self) { campus in
                                Text(campus).tag(campus)
                            }
                        }
                        .disabled(!canEdit)
                    }

                    if store.rooms.isEmpty {
                        TextField("Room", text: $patch.room).disabled(!canEdit)
                    } else {
                        Picker("Room", selection: $patch.room) {
                            Text("Select room").tag("")
                            ForEach(store.rooms.sorted(), id: \.self) { room in
                                Text(room).tag(room)
                            }
                        }
                        .disabled(!canEdit)
                    }
                }

                if canEdit {
                    Section {
                        Button("Delete Patch", role: .destructive) {
                            showDeleteConfirmation = true
                        }
                        .disabled(isSaving)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Edit Patch")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if canEdit {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            isSaving = true
                            let trimmed = channelCountText.trimmingCharacters(in: .whitespacesAndNewlines)
                            let parsed = Int(trimmed) ?? 0
                            patch.channelCount = parsed > 0 ? parsed : nil
                            patch.universe = universeText.trimmingCharacters(in: .whitespacesAndNewlines)
                            store.savePatch(patch) { result in
                                switch result {
                                case .success:
                                    isSaving = false
                                    dismiss()
                                case .failure(let error):
                                    isSaving = false
                                    errorMessage = error.localizedDescription
                                }
                            }
                        }
                        .disabled(isSaving)
                    }
                }
            }
            .alert("Delete Patch?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    isSaving = true
                    store.deletePatch(patch) { result in
                        switch result {
                        case .success:
                            isSaving = false
                            dismiss()
                        case .failure(let error):
                            isSaving = false
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            } message: {
                Text("This permanently deletes this patch.")
            }
        }
    }
}

private struct MacTrainingView: View {
    @EnvironmentObject private var store: ProdConnectStore
    @State private var selectedLesson: TrainingLesson?
    @State private var showAddTrainingSheet = false
    @State private var title = ""
    @State private var category = "Audio"
    @State private var urlString = ""

    private let categories = ["Audio", "Video", "Lighting", "Misc"]
    private var canSaveNewLesson: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Group {
            if let selectedLesson {
                VStack(alignment: .leading, spacing: 16) {
                    Button {
                        self.selectedLesson = nil
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.bordered)

                    MacTrainingLessonPlayerView(lesson: selectedLesson)
                }
                .padding()
                .background(Color.clear)
                .navigationTitle(selectedLesson.title)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Spacer()
                        Button {
                            showAddTrainingSheet = true
                        } label: {
                            Label("Add", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    List {
                        ForEach(store.lessons.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }) { lesson in
                            Button {
                                selectedLesson = lesson
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(lesson.title).font(.headline)
                                        Text(lesson.category).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if hasPlayableURL(lesson) {
                                        Image(systemName: "play.circle.fill")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { indexSet in
                            let lessons = store.lessons.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                            for index in indexSet {
                                store.deleteLesson(lessons[index])
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
                .padding()
                .background(Color.clear)
                .navigationTitle("Training")
            }
        }
        .sheet(isPresented: $showAddTrainingSheet) {
            NavigationStack {
                Form {
                    TextField("Title", text: $title)
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Video URL (optional)", text: $urlString)
                }
                .navigationTitle("Add Training")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            resetNewLessonForm()
                            showAddTrainingSheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            saveNewLesson()
                        }
                        .disabled(!canSaveNewLesson)
                    }
                }
            }
            .frame(minWidth: 420, minHeight: 240)
        }
    }

    private func hasPlayableURL(_ lesson: TrainingLesson) -> Bool {
        let raw = lesson.urlString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !raw.isEmpty && URL(string: raw) != nil
    }

    private func saveNewLesson() {
        store.saveLesson(
            TrainingLesson(
                title: title,
                category: category,
                teamCode: store.teamCode ?? "",
                urlString: urlString.isEmpty ? nil : urlString
            )
        )
        resetNewLessonForm()
        showAddTrainingSheet = false
    }

    private func resetNewLessonForm() {
        title = ""
        category = categories.first ?? "Audio"
        urlString = ""
    }
}

private struct MacTrainingLessonPlayerView: View {
    let lesson: TrainingLesson

    private var lessonURL: URL? {
        let raw = lesson.urlString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    private var youTubeWatchURL: URL? {
        guard let url = lessonURL else { return nil }
        guard let host = url.host?.lowercased() else { return nil }

        if host.contains("youtu.be") {
            let id = url.pathComponents.dropFirst().first ?? ""
            return id.isEmpty ? nil : URL(string: "https://www.youtube.com/watch?v=\(id)")
        }

        if host.contains("youtube.com") {
            if url.path.lowercased() == "/watch",
               let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let id = components.queryItems?.first(where: { $0.name == "v" })?.value,
               !id.isEmpty,
               let normalized = URL(string: "https://www.youtube.com/watch?v=\(id)") {
                return normalized
            }
            if url.path.lowercased().contains("/embed/"),
               let embedID = url.pathComponents.last,
               !embedID.isEmpty {
                return URL(string: "https://www.youtube.com/watch?v=\(embedID)")
            }
        }

        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(lesson.title)
                    .font(.title2.weight(.semibold))
                Text(lesson.category)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let watchURL = youTubeWatchURL {
                MacWebVideoView(url: watchURL)
                    .frame(minHeight: 480)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else if let url = lessonURL {
                VideoPlayer(player: AVPlayer(url: url))
                    .frame(minHeight: 480)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                ContentUnavailableView(
                    "No Video URL",
                    systemImage: "play.slash",
                    description: Text("This lesson does not have a playable video URL yet.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct MacWebVideoView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsBackForwardNavigationGestures = false
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
    }
}

private struct MacGearView: View {
    @EnvironmentObject private var store: ProdConnectStore
    @State private var selectedGearItem: GearItem?
    @State private var showAddGearForm = false
    @State private var editingGearID: String?
    @State private var editingImageURL: String?
    @State private var editingCreatedBy: String?
    @State private var searchText = ""
    @State private var selectedCategory: String?
    @State private var selectedStatus: GearItem.GearStatus?
    @State private var selectedLocation: String?
    @State private var name = ""
    @State private var category = "Audio"
    @State private var status: GearItem.GearStatus = .available
    @State private var location = ""
    @State private var campus = ""
    @State private var purchaseDate = Date()
    @State private var purchasedFrom = ""
    @State private var costText = ""
    @State private var serialNumber = ""
    @State private var assetId = ""
    @State private var installDate = Date()
    @State private var maintenanceIssue = ""
    @State private var maintenanceCostText = ""
    @State private var maintenanceRepairDate = Date()
    @State private var maintenanceNotes = ""
    @State private var showDeleteAssetConfirmation = false
    @State private var deleteAssetErrorMessage: String?
    @State private var isExporting = false
    @State private var showMergeConfirm = false
    @State private var isMerging = false
    @State private var mergeResultMessage = ""
    @State private var showMergeResult = false
    @State private var duplicateGearGroupCount = 0
    @State private var saveErrorMessage: String?
    @State private var gearSortColumn: GearSortColumn = .name
    @State private var gearSortAscending = true

    private enum GearSortColumn {
        case name
        case category
        case campus
        case status
    }

    private let gearMinimumColumnWidths: [CGFloat] = [240, 170, 170, 120]
    private let gearColumnWeights: [CGFloat] = [0.34, 0.24, 0.24, 0.18]

    private var availableCategories: [String] {
        Array(Set(store.gear.map(\.category))).filter { !$0.isEmpty }.sorted()
    }

    private var categoryOptions: [String] {
        let current = category.trimmingCharacters(in: .whitespacesAndNewlines)
        var options = ProdConnectStore.defaultGearCategories
        let existing = store.gear.map(\.category).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        for option in existing where !options.contains(where: { $0.caseInsensitiveCompare(option) == .orderedSame }) {
            options.append(option)
        }
        if !current.isEmpty && !options.contains(where: { $0.caseInsensitiveCompare(current) == .orderedSame }) {
            options.append(current)
        }
        return options.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var allGearLocations: [String] {
        Array(Set(store.gear.map(\.location))).filter { !$0.isEmpty }.sorted()
    }

    private var filteredGear: [GearItem] {
        var result = store.gear
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.category.localizedCaseInsensitiveContains(searchText) ||
                $0.location.localizedCaseInsensitiveContains(searchText)
            }
        }
        if let selectedCategory {
            result = result.filter { $0.category == selectedCategory }
        }
        if let selectedStatus {
            result = result.filter { $0.status == selectedStatus }
        }
        if let selectedLocation {
            result = result.filter { $0.location == selectedLocation }
        }
        return result
    }

    private func gearColumns(for availableWidth: CGFloat) -> [GridItem] {
        adaptiveTableColumnWidths(
            availableWidth: availableWidth,
            minimums: gearMinimumColumnWidths,
            weights: gearColumnWeights
        ).map { width in
            GridItem(.fixed(width), spacing: 0, alignment: .leading)
        }
    }

    private func gearTableWidth(for availableWidth: CGFloat) -> CGFloat {
        adaptiveTableColumnWidths(
            availableWidth: availableWidth,
            minimums: gearMinimumColumnWidths,
            weights: gearColumnWeights
        ).reduce(28, +)
    }

    private var sortedFilteredGear: [GearItem] {
        filteredGear.sorted { lhs, rhs in
            let result: ComparisonResult
            switch gearSortColumn {
            case .name:
                result = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            case .category:
                result = lhs.category.localizedCaseInsensitiveCompare(rhs.category)
            case .campus:
                result = gearCampusLabel(lhs).localizedCaseInsensitiveCompare(gearCampusLabel(rhs))
            case .status:
                result = lhs.status.rawValue.localizedCaseInsensitiveCompare(rhs.status.rawValue)
            }

            if result == .orderedSame {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return gearSortAscending ? (result == .orderedAscending) : (result == .orderedDescending)
        }
    }

    var body: some View {
        Group {
            if editingGearID != nil {
                VStack(alignment: .leading, spacing: 16) {
                    Button {
                        editingGearID = nil
                        editingImageURL = nil
                        editingCreatedBy = nil
                        resetGearForm()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.bordered)

                    gearEditor(title: "Edit Asset", buttonTitle: "Save Changes", fullScreen: true)
                }
                .padding()
                .background(Color.clear)
                .navigationTitle(name.isEmpty ? "Edit Asset" : name)
            } else
            if let selectedGearItem {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Button {
                            self.selectedGearItem = nil
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                        .buttonStyle(.bordered)

                        Button("Edit") {
                            beginEditing(selectedGearItem)
                        }
                        .buttonStyle(.borderedProminent)

                        if store.canEditGear {
                            Button("Delete", role: .destructive) {
                                showDeleteAssetConfirmation = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    MacGearDetailView(
                        item: selectedGearItem,
                        statusColor: statusColor(for: selectedGearItem.status)
                    )
                }
                .padding()
                .background(Color.clear)
                .navigationTitle(selectedGearItem.name)
                .alert("Delete Asset?", isPresented: $showDeleteAssetConfirmation) {
                    Button("Cancel", role: .cancel) {}
                    Button("Delete", role: .destructive) {
                        let itemToDelete = selectedGearItem
                        store.deleteGear(items: [itemToDelete]) { result in
                            switch result {
                            case .success:
                                self.selectedGearItem = nil
                            case .failure(let error):
                                deleteAssetErrorMessage = error.localizedDescription
                            }
                        }
                    }
                } message: {
                    Text("This permanently deletes this asset.")
                }
                .alert("Unable to Delete Asset", isPresented: Binding(
                    get: { deleteAssetErrorMessage != nil },
                    set: { if !$0 { deleteAssetErrorMessage = nil } }
                )) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(deleteAssetErrorMessage ?? "")
                }
            } else {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Spacer()
                if showAddGearForm {
                    Button("Cancel") {
                        showAddGearForm = false
                        if editingGearID == nil {
                            resetGearForm()
                        }
                    }
                    .buttonStyle(.bordered)
                }
                Button(action: exportGear) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .disabled(isExporting || filteredGear.isEmpty)

                Button(action: { showMergeConfirm = true }) {
                    Label("Merge", systemImage: "arrow.triangle.merge")
                }
                .buttonStyle(.bordered)
                .disabled(duplicateGearGroupCount == 0 || isMerging)

                Button {
                    if showAddGearForm {
                        showAddGearForm = false
                    } else {
                        resetGearForm()
                        showAddGearForm = true
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            TextField("Search assets...", text: $searchText)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                Menu {
                    Button("Clear") { selectedCategory = nil }
                    Divider()
                    ForEach(availableCategories, id: \.self) { option in
                        Button(option) { selectedCategory = option }
                    }
                } label: {
                    filterChip(
                        title: selectedCategory ?? "Category",
                        icon: "line.3.horizontal.decrease.circle",
                        isActive: selectedCategory != nil
                    )
                }

                if !allGearLocations.isEmpty {
                    Menu {
                        Button("Clear") { selectedLocation = nil }
                        Divider()
                        ForEach(allGearLocations, id: \.self) { option in
                            Button(option) { selectedLocation = option }
                        }
                    } label: {
                        filterChip(
                            title: selectedLocation ?? "Location",
                            icon: "mappin.circle",
                            isActive: selectedLocation != nil
                        )
                    }
                }

                Menu {
                    Button("Clear") { selectedStatus = nil }
                    Divider()
                    ForEach(GearItem.GearStatus.allCases, id: \.self) { option in
                        Button(option.rawValue) { selectedStatus = option }
                    }
                } label: {
                    filterChip(
                        title: selectedStatus?.rawValue ?? "Status",
                        icon: "checkmark.circle",
                        isActive: selectedStatus != nil
                    )
                }
            }

            GeometryReader { proxy in
                let tableWidth = gearTableWidth(for: proxy.size.width)
                let columns = gearColumns(for: proxy.size.width)

                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        gearTableHeader(columns: columns)
                            .frame(minWidth: tableWidth, alignment: .leading)

                        ScrollView {
                            LazyVStack(spacing: 0) {
                                if sortedFilteredGear.isEmpty {
                                    Text("No matching assets")
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 18)
                                } else {
                                    ForEach(sortedFilteredGear) { item in
                                        gearRow(item, columns: columns)
                                        Divider()
                                    }
                                }
                            }
                        }
                        .frame(minWidth: tableWidth, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            if showAddGearForm {
                gearEditor(title: "Add Asset", buttonTitle: "Save Asset", fullScreen: false)
            }
        }
        .padding()
        .background(Color.clear)
        .navigationTitle("Assets")
            }
        }
        .alert("Merge Duplicates", isPresented: $showMergeConfirm) {
            Button("Merge", role: .destructive) { mergeDuplicates() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Found \(duplicateGearGroupCount) duplicate group(s). Merge now?")
        }
        .alert("Assets", isPresented: $showMergeResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(mergeResultMessage)
        }
        .alert("Unable to Save Asset", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "")
        }
        .onAppear {
            refreshDuplicateGroupCount()
        }
        .onReceive(store.$gear) { _ in
            refreshDuplicateGroupCount()
        }
    }

    @ViewBuilder
    private func filterChip(title: String, icon: String, isActive: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(title).lineLimit(1)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isActive ? Color.blue : Color.gray.opacity(0.3))
        .foregroundColor(.white)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func gearTableHeader(columns: [GridItem]) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 0) {
            gearHeaderButton("Name", column: .name)
            gearHeaderButton("Category", column: .category)
            gearHeaderButton("Campus", column: .campus)
            gearHeaderButton("Status", column: .status)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func gearHeaderButton(_ title: String, column: GearSortColumn) -> some View {
        let iconName = gearSortColumn == column
            ? (gearSortAscending ? "arrow.up" : "arrow.down")
            : "arrow.up.arrow.down"

        return Button {
            if gearSortColumn == column {
                gearSortAscending.toggle()
            } else {
                gearSortColumn = column
                gearSortAscending = column != .status
            }
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()

                Image(systemName: iconName)
                    .font(.caption2)
                    .foregroundStyle(gearSortColumn == column ? .blue : .secondary)
                    .frame(width: 12, alignment: .center)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func gearRow(_ item: GearItem, columns: [GridItem]) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 0) {
            gearOpenButtonCell(item.name.isEmpty ? "Untitled" : item.name, item: item, weight: .medium)
            gearOpenButtonCell(item.category, item: item)
            gearOpenButtonCell(gearCampusLabel(item), item: item)
            Button {
                selectedGearItem = item
            } label: {
                Text(item.status.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(statusColor(for: item.status).opacity(0.2))
                    .foregroundStyle(statusColor(for: item.status))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(Color.white.opacity(0.015))
        .contextMenu {
            Button("Edit") {
                beginEditing(item)
            }
            if store.canEditGear {
                Button("Delete", role: .destructive) {
                    store.deleteGear(items: [item])
                }
            }
        }
    }

    private func gearOpenButtonCell(_ value: String, item: GearItem, weight: Font.Weight = .regular, color: Color = .primary) -> some View {
        Button {
            selectedGearItem = item
        } label: {
            Text(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "—" : value)
                .font(.system(size: 13, weight: weight))
                .foregroundStyle(color)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func gearCampusLabel(_ item: GearItem) -> String {
        let campus = item.campus.trimmingCharacters(in: .whitespacesAndNewlines)
        if !campus.isEmpty {
            return campus
        }
        let fallback = item.location.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? "—" : fallback
    }

    private func statusColor(for status: GearItem.GearStatus) -> Color {
        switch status {
        case .available:
            return .green
        case .checkedOut:
            return .orange
        case .maintenance:
            return .yellow
        case .lost:
            return .red
        case .unknown:
            return .gray
        case .inUse:
            return .blue
        case .needsRepair:
            return .pink
        case .retired:
            return .gray
        case .missing:
            return .red
        case .blank:
            return .gray
        }
    }

    private func beginEditing(_ item: GearItem) {
        editingGearID = item.id
        editingImageURL = item.imageURL
        editingCreatedBy = item.createdBy
        name = item.name
        category = item.category.isEmpty ? "Audio" : item.category
        status = item.status
        location = item.location
        campus = item.campus
        purchaseDate = item.purchaseDate ?? Date()
        purchasedFrom = item.purchasedFrom
        costText = item.cost.map { "\($0)" } ?? ""
        serialNumber = item.serialNumber
        assetId = item.assetId
        installDate = item.installDate ?? Date()
        maintenanceIssue = item.maintenanceIssue
        maintenanceCostText = item.maintenanceCost.map { "\($0)" } ?? ""
        maintenanceRepairDate = item.maintenanceRepairDate ?? Date()
        maintenanceNotes = item.maintenanceNotes
        selectedGearItem = nil
        showAddGearForm = false
    }

    private func findDuplicateGearGroups() -> [[GearItem]] {
        let grouped = Dictionary(grouping: store.gear) { item in
            let name = item.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let serial = item.serialNumber.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(name)|\(serial)"
        }
        return grouped.values.filter { $0.count > 1 }
    }

    private func refreshDuplicateGroupCount() {
        duplicateGearGroupCount = findDuplicateGearGroups().count
    }

    private func mergeDuplicates() {
        isMerging = true
        let groups = findDuplicateGearGroups()
        mergeDuplicateGroups(groups, mergedCount: 0)
    }

    private func mergeDuplicateGroups(_ groups: [[GearItem]], mergedCount: Int) {
        guard let group = groups.first else {
            isMerging = false
            mergeResultMessage = "Merged \(mergedCount) duplicate group(s)."
            showMergeResult = true
            return
        }

        guard var merged = group.first else {
            mergeDuplicateGroups(Array(groups.dropFirst()), mergedCount: mergedCount)
            return
        }

        for item in group.dropFirst() {
            if merged.category.isEmpty, !item.category.isEmpty { merged.category = item.category }
            if merged.location.isEmpty, !item.location.isEmpty { merged.location = item.location }
            if merged.maintenanceNotes.isEmpty, !item.maintenanceNotes.isEmpty { merged.maintenanceNotes = item.maintenanceNotes }
            if merged.status == .unknown, item.status != .unknown { merged.status = item.status }
        }

        let duplicatesToDelete = Array(group.dropFirst())
        store.deleteGear(items: duplicatesToDelete) { result in
            switch result {
            case .success:
                store.saveGear(merged) { saveResult in
                    switch saveResult {
                    case .success:
                        mergeDuplicateGroups(Array(groups.dropFirst()), mergedCount: mergedCount + 1)
                    case .failure(let error):
                        isMerging = false
                        mergeResultMessage = "Merge failed: \(error.localizedDescription)"
                        showMergeResult = true
                    }
                }
            case .failure(let error):
                isMerging = false
                mergeResultMessage = "Merge failed: \(error.localizedDescription)"
                showMergeResult = true
            }
        }
    }

    private func exportGear() {
        guard !filteredGear.isEmpty else { return }
        isExporting = true

        let header = [
            "Name",
            "Category",
            "Status",
            "Campus",
            "Room",
            "Serial Number",
            "Asset ID",
            "Purchased From",
            "Notes"
        ].map(csvEscaped).joined(separator: ",")

        let rows = filteredGear.map { item in
            [
                item.name,
                item.category,
                item.status.rawValue,
                item.campus,
                item.location,
                item.serialNumber,
                item.assetId,
                item.purchasedFrom,
                item.maintenanceNotes
            ].map(csvEscaped).joined(separator: ",")
        }

        let csv = "\u{FEFF}" + ([header] + rows).joined(separator: "\n")
        let savePanel = NSSavePanel()
        savePanel.title = "Export Assets"
        savePanel.nameFieldStringValue = "GearExport.csv"
        savePanel.allowedContentTypes = [.commaSeparatedText]
        savePanel.canCreateDirectories = true

        do {
            guard savePanel.runModal() == .OK, let url = savePanel.url else {
                isExporting = false
                return
            }
            try csv.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            mergeResultMessage = "Export failed: \(error.localizedDescription)"
            showMergeResult = true
        }

        isExporting = false
    }

    private func csvEscaped(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private func resetGearForm() {
        name = ""
        category = "Audio"
        status = .available
        location = ""
        campus = ""
        purchaseDate = Date()
        purchasedFrom = ""
        costText = ""
        serialNumber = ""
        assetId = ""
        installDate = Date()
        maintenanceIssue = ""
        maintenanceCostText = ""
        maintenanceRepairDate = Date()
        maintenanceNotes = ""
    }

    @ViewBuilder
    private func gearEditor(title: String, buttonTitle: String, fullScreen: Bool) -> some View {
        GroupBox(title) {
            ScrollView {
                VStack(spacing: 14) {
                    GroupBox("Details") {
                        VStack(spacing: 10) {
                            labeledTextField("Name", text: $name)
                            labeledTextField("Serial Number", text: $serialNumber)
                            labeledTextField("Asset ID", text: $assetId)
                            fieldHeader("Category")
                            Picker("Category", selection: $category) {
                                ForEach(categoryOptions, id: \.self) { option in
                                    Text(option).tag(option)
                                }
                            }
                            if store.locations.isEmpty {
                                labeledTextField("Campus", text: $campus)
                            } else {
                                fieldHeader("Campus")
                                Picker("Campus", selection: $campus) {
                                    Text("Select campus").tag("")
                                    ForEach(store.locations.sorted(), id: \.self) { option in
                                        Text(option).tag(option)
                                    }
                                }
                            }
                            if store.rooms.isEmpty {
                                labeledTextField("Room", text: $location)
                            } else {
                                fieldHeader("Room")
                                Picker("Room", selection: $location) {
                                    Text("Select room").tag("")
                                    ForEach(store.rooms.sorted(), id: \.self) { option in
                                        Text(option).tag(option)
                                    }
                                }
                            }
                            fieldHeader("Status")
                            Picker("Status", selection: $status) {
                                ForEach(GearItem.GearStatus.allCases, id: \.self) { option in
                                    Text(option.rawValue).tag(option)
                                }
                            }
                        }
                    }

                    GroupBox("Install Info") {
                        labeledDatePicker("Install Date", selection: $installDate)
                    }

                    GroupBox("Purchase Info") {
                        VStack(spacing: 10) {
                            labeledDatePicker("Purchase Date", selection: $purchaseDate)
                            labeledTextField("Purchased From", text: $purchasedFrom)
                            labeledTextField("Cost", text: $costText)
                        }
                    }

                    GroupBox("Maintenance") {
                        VStack(spacing: 10) {
                            labeledTextField("Issue", text: $maintenanceIssue)
                            labeledTextField("Cost", text: $maintenanceCostText)
                            labeledDatePicker("Repair Date", selection: $maintenanceRepairDate)
                            fieldHeader("Notes")
                            TextEditor(text: $maintenanceNotes)
                                .frame(minHeight: 90)
                        }
                    }

                    GroupBox("Image") {
                        HStack {
                            Image(systemName: "photo")
                            Text("Image upload is not wired on macOS yet.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button(buttonTitle) {
                        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedName.isEmpty else { return }
                        let gearItem = GearItem(
                            id: editingGearID ?? UUID().uuidString,
                            name: trimmedName,
                            category: category,
                            status: status,
                            teamCode: store.teamCode ?? "",
                            purchaseDate: purchaseDate,
                            purchasedFrom: purchasedFrom.trimmingCharacters(in: .whitespacesAndNewlines),
                            cost: Double(costText),
                            location: location.trimmingCharacters(in: .whitespacesAndNewlines),
                            serialNumber: serialNumber.trimmingCharacters(in: .whitespacesAndNewlines),
                            campus: campus.trimmingCharacters(in: .whitespacesAndNewlines),
                            assetId: assetId.trimmingCharacters(in: .whitespacesAndNewlines),
                            installDate: installDate,
                            maintenanceIssue: maintenanceIssue.trimmingCharacters(in: .whitespacesAndNewlines),
                            maintenanceCost: Double(maintenanceCostText),
                            maintenanceRepairDate: maintenanceRepairDate,
                            maintenanceNotes: maintenanceNotes.trimmingCharacters(in: .whitespacesAndNewlines),
                            imageURL: editingImageURL,
                            createdBy: editingCreatedBy
                        )
                        store.saveGear(gearItem) { result in
                            switch result {
                            case .success:
                                editingGearID = nil
                                editingImageURL = nil
                                editingCreatedBy = nil
                                resetGearForm()
                                showAddGearForm = false
                            case .failure(let error):
                                saveErrorMessage = error.localizedDescription
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .frame(maxHeight: fullScreen ? .infinity : 420)
        }
    }

    @ViewBuilder
    private func fieldHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func labeledTextField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldHeader(title)
            TextField(title, text: text)
        }
    }

    @ViewBuilder
    private func labeledDatePicker(_ title: String, selection: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldHeader(title)
            DatePicker(title, selection: selection, displayedComponents: .date)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct MacGearDetailView: View {
    let item: GearItem
    let statusColor: Color

    var body: some View {
        Form {
            Section("Details") {
                detailRow("Name", item.name)
                detailRow("Category", item.category)
                detailRow("Status", item.status.rawValue, valueColor: statusColor)
                detailRow("Serial Number", item.serialNumber)
                detailRow("Asset ID", item.assetId)
                detailRow("Campus", item.campus)
                detailRow("Room", item.location)
            }

            Section("Install Info") {
                detailRow("Install Date", formatted(item.installDate))
            }

            Section("Purchase Info") {
                detailRow("Purchase Date", formatted(item.purchaseDate))
                detailRow("Purchased From", item.purchasedFrom)
                detailRow("Cost", currency(item.cost))
            }

            Section("Maintenance") {
                detailRow("Issue", item.maintenanceIssue)
                detailRow("Maintenance Cost", currency(item.maintenanceCost))
                detailRow("Repair Date", formatted(item.maintenanceRepairDate))
                detailRow("Notes", item.maintenanceNotes)
            }

            Section("Ticket History") {
                if item.ticketHistory.isEmpty {
                    Text("No tickets linked")
                        .foregroundStyle(.secondary)
                } else {
                    if !item.activeTicketIDs.isEmpty {
                        Text("\(item.activeTicketIDs.count) active ticket(s)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    ForEach(item.ticketHistory.sorted { $0.updatedAt > $1.updatedAt }) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.ticketTitle)
                                Spacer()
                                Text(entry.status.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(entry.status == .resolved ? .green : .orange)
                            }
                            let locationLine = [entry.campus, entry.room]
                                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.isEmpty }
                                .joined(separator: " • ")
                            if !locationLine.isEmpty {
                                Text(locationLine)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text((entry.resolvedAt ?? entry.updatedAt).formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Section("Meta") {
                detailRow("Created By", item.createdBy)
                detailRow("Image URL", item.imageURL)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .navigationTitle(item.name)
    }

    @ViewBuilder
    private func detailRow(_ label: String, _ value: String?, valueColor: Color? = nil) -> some View {
        LabeledContent(label) {
            Text(displayValue(value))
                .foregroundStyle(valueColor ?? (isMissing(value) ? .secondary : .primary))
                .multilineTextAlignment(.trailing)
        }
    }

    private func displayValue(_ value: String?) -> String {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return "Not set"
        }
        return trimmed
    }

    private func isMissing(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
    }

    private func formatted(_ date: Date?) -> String {
        guard let date else { return "Not set" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func currency(_ amount: Double?) -> String {
        guard let amount else { return "Not set" }
        return amount.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
    }
}

private struct MacTicketsView: View {
    @EnvironmentObject private var store: ProdConnectStore
    @State private var selectedTicket: SupportTicket?
    @State private var startsEditingSelectedTicket = false
    @State private var isShowingAddTicket = false
    @State private var title = ""
    @State private var detail = ""
    @State private var category = ""
    @State private var subcategory = ""
    @State private var campus = ""
    @State private var room = ""
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var attachmentURL: String?
    @State private var attachmentName: String?
    @State private var attachmentKind: TicketAttachmentKind?
    @State private var isUploadingAttachment = false
    @State private var attachmentError: String?
    @State private var locationFilter = ""
    @State private var statusFilter = ""
    @State private var agentFilter = ""
    @State private var ticketSortColumn: TicketSortColumn = .createdDate
    @State private var ticketSortAscending = false
    @State private var isShowingExportSheet = false
    @State private var isExportingTicketReport = false
    @State private var exportStatusFilter = TicketReportStatusFilter.active.rawValue
    @State private var exportCampusFilter = ""
    @State private var exportAgentSelection = ""
    @State private var externalTicketFormEnabled = false
    @State private var externalTicketFormAccessKey = ""
    @State private var isSavingExternalTicketForm = false
    @State private var externalTicketStatusMessage = ""

    private let unassignedAgentFilter = "__UNASSIGNED__"

    private enum TicketSortColumn {
        case createdDate
        case subject
        case requester
        case state
        case status
        case assignedTo
    }

    private let ticketMinimumColumnWidths: [CGFloat] = [170, 220, 170, 120, 110, 170]
    private let ticketColumnWeights: [CGFloat] = [0.18, 0.24, 0.18, 0.12, 0.10, 0.18]

    private enum TicketReportStatusFilter: String, CaseIterable {
        case all = "all"
        case active = "active"
        case closed = "closed"
        case new = "new"
        case open = "open"
        case inProgress = "in_progress"

        var title: String {
            switch self {
            case .all: return "All Tickets"
            case .active: return "Active Tickets"
            case .closed: return "Closed Tickets"
            case .new: return "New"
            case .open: return "Open"
            case .inProgress: return "In Progress"
            }
        }
    }

    private func ticketColumns(for availableWidth: CGFloat) -> [GridItem] {
        adaptiveTableColumnWidths(
            availableWidth: availableWidth,
            minimums: ticketMinimumColumnWidths,
            weights: ticketColumnWeights
        ).map { width in
            GridItem(.fixed(width), spacing: 0, alignment: .leading)
        }
    }

    private func ticketTableWidth(for availableWidth: CGFloat) -> CGFloat {
        adaptiveTableColumnWidths(
            availableWidth: availableWidth,
            minimums: ticketMinimumColumnWidths,
            weights: ticketColumnWeights
        ).reduce(28, +)
    }

    private var ticketCategoryOptions: [String] {
        store.availableTicketCategories
    }

    private var ticketSubcategoryOptions: [String] {
        store.availableTicketSubcategories
    }

    private var canManageExternalTicketForm: Bool {
        (store.user?.isAdmin == true || store.user?.isOwner == true)
            && (store.user?.hasTicketingFeatures == true)
    }

    private var availableTicketReportCampuses: [String] {
        let fromTickets = store.visibleTickets.map { $0.campus.trimmingCharacters(in: .whitespacesAndNewlines) }
        let values = Array(Set((store.locations + fromTickets).filter { !$0.isEmpty }))
        return values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var reportTickets: [SupportTicket] {
        store.visibleTickets.filter { ticket in
            let campusMatches = exportCampusFilter.isEmpty
                || ticket.campus.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(exportCampusFilter) == .orderedSame

            let agentMatches: Bool
            if exportAgentSelection.isEmpty {
                agentMatches = true
            } else if exportAgentSelection == unassignedAgentFilter {
                agentMatches = ticket.assignedAgentID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
            } else {
                agentMatches = ticket.assignedAgentID?.trimmingCharacters(in: .whitespacesAndNewlines) == exportAgentSelection
            }

            let statusFilter = TicketReportStatusFilter(rawValue: exportStatusFilter) ?? .active
            let statusMatches: Bool
            switch statusFilter {
            case .all:
                statusMatches = true
            case .active:
                statusMatches = ticket.status != .resolved
            case .closed:
                statusMatches = ticket.status == .resolved
            case .new:
                statusMatches = ticket.status == .new
            case .open:
                statusMatches = ticket.status == .open
            case .inProgress:
                statusMatches = ticket.status == .inProgress
            }

            return campusMatches && agentMatches && statusMatches
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    private var externalTicketFormURLString: String {
        let teamCode = (store.teamCode ?? store.user?.teamCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let accessKey = externalTicketFormAccessKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard externalTicketFormEnabled, !teamCode.isEmpty, !accessKey.isEmpty else { return "" }
        let slug = externalTicketFormSlug(from: store.organizationName)
        return "https://prodconnect-1ea3a.web.app/support/\(slug)?team=\(teamCode)&key=\(accessKey)"
    }

    @ViewBuilder
    private var externalTicketFormSection: some View {
        if canManageExternalTicketForm {
            GroupBox("External Ticket Form") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Enable External Form", isOn: $externalTicketFormEnabled)

                    if !externalTicketFormURLString.isEmpty {
                        TextField("Public Link", text: .constant(externalTicketFormURLString))
                            .textFieldStyle(.roundedBorder)

                        HStack {
                            Button("Copy Public Link") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(externalTicketFormURLString, forType: .string)
                                externalTicketStatusMessage = "External ticket form link copied."
                            }
                            .buttonStyle(.bordered)

                            Button("Generate New Link") {
                                externalTicketFormEnabled = true
                                externalTicketFormAccessKey = store.generateExternalTicketAccessKey()
                                externalTicketStatusMessage = "New public link generated. Save to make it active."
                            }
                            .buttonStyle(.bordered)

                            Button {
                                saveExternalTicketForm()
                            } label: {
                                if isSavingExternalTicketForm {
                                    ProgressView()
                                } else {
                                    Text("Save External Form")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isSavingExternalTicketForm)
                        }
                    }

                    if !externalTicketStatusMessage.isEmpty {
                        Text(externalTicketStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var selectedTicketContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                startsEditingSelectedTicket = false
                self.selectedTicket = nil
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(.bordered)

            if let selectedTicket {
                MacTicketDetailView(
                    ticket: selectedTicket,
                    startEditing: startsEditingSelectedTicket
                )
            }
        }
        .padding()
        .background(Color.clear)
        .navigationTitle("Ticket")
    }

    private var ticketsListContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !store.canUseTickets {
                ContentUnavailableView(
                    "Ticketing Locked",
                    systemImage: "ticket",
                    description: Text("Upgrade the team to Premium W/Ticketing to enable tickets.")
                )
            } else {
                if isShowingAddTicket {
                    ZStack(alignment: .topTrailing) {
                        VStack {
                            Spacer(minLength: 0)
                            HStack {
                                Spacer(minLength: 0)
                                addTicketSection
                                Spacer(minLength: 0)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        HStack(spacing: 10) {
                            Button("Cancel") {
                                isShowingAddTicket = false
                                resetNewTicketForm()
                            }
                            .buttonStyle(.bordered)

                            Button {
                                isShowingAddTicket = false
                                resetNewTicketForm()
                            } label: {
                                Label("Close", systemImage: "xmark")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.top, 4)
                    }
                } else {
                    HStack {
                        Spacer()
                        Button {
                            isShowingExportSheet = true
                        } label: {
                            Label("Export Report", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            resetNewTicketForm()
                            isShowingAddTicket = true
                        } label: {
                            Label("Add", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    HStack(spacing: 12) {
                        ticketLocationMenu
                        ticketStatusMenu
                        ticketAgentMenu
                    }

                    GeometryReader { proxy in
                        let tableWidth = ticketTableWidth(for: proxy.size.width)
                        let columns = ticketColumns(for: proxy.size.width)

                        ScrollView(.horizontal, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 12) {
                                ticketTableHeader(columns: columns)
                                    .frame(minWidth: tableWidth, alignment: .leading)

                                ScrollView {
                                    LazyVStack(spacing: 0) {
                                        if sortedTickets.isEmpty {
                                            Text("No matching tickets")
                                                .foregroundStyle(.secondary)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 18)
                                        } else {
                                            ForEach(sortedTickets) { ticket in
                                                ticketRow(ticket, columns: columns)
                                                Divider()
                                            }
                                        }
                                    }
                                }
                                .frame(minWidth: tableWidth, alignment: .leading)
                                .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
            }
        }
        .padding()
        .background(Color.clear)
        .navigationTitle("Tickets")
        .sheet(isPresented: $isShowingExportSheet) {
            ticketExportSheet
        }
    }

    private var ticketExportSheet: some View {
        NavigationStack {
            Form {
                Section("Report Filters") {
                    Picker("Status", selection: $exportStatusFilter) {
                        ForEach(TicketReportStatusFilter.allCases, id: \.rawValue) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }

                    Picker("Campus", selection: $exportCampusFilter) {
                        Text("All Campuses").tag("")
                        ForEach(availableTicketReportCampuses, id: \.self) { campus in
                            Text(campus).tag(campus)
                        }
                    }

                    Picker("Agent", selection: $exportAgentSelection) {
                        Text("All Agents").tag("")
                        Text("Unassigned").tag(unassignedAgentFilter)
                        ForEach(availableAgents) { member in
                            Text(ticketMemberDisplayName(member)).tag(member.id)
                        }
                    }
                }

                Section("Preview") {
                    LabeledContent("Matching Tickets", value: "\(reportTickets.count)")
                    Text("Exports a CSV report you can open in Excel.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Export Tickets")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isShowingExportSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        exportTicketReport()
                    } label: {
                        if isExportingTicketReport {
                            ProgressView()
                        } else {
                            Text("Export")
                        }
                    }
                    .disabled(isExportingTicketReport || reportTickets.isEmpty)
                }
            }
        }
        .frame(minWidth: 460, minHeight: 320)
    }

    private var addTicketSection: some View {
        GroupBox("Add Ticket") {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Title")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("Issue title", text: $title)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Description")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextEditor(text: $detail)
                        .frame(minHeight: 120)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 12) {
                    GridRow {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Due Date")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Toggle("Set due date", isOn: $hasDueDate)
                            if hasDueDate {
                                DatePicker("Due", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                                    .labelsHidden()
                            }
                        }

                        Color.clear
                    }

                    GridRow {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Category")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            if ticketCategoryOptions.isEmpty {
                                TextField("Category", text: $category)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                Picker("Category", selection: $category) {
                                    Text("Select category").tag("")
                                    ForEach(ticketCategoryOptions, id: \.self) { option in
                                        Text(option).tag(option)
                                    }
                                }
                                .labelsHidden()
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Subcategory")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            if ticketSubcategoryOptions.isEmpty {
                                TextField("Subcategory", text: $subcategory)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                Picker("Subcategory", selection: $subcategory) {
                                    Text("Select subcategory").tag("")
                                    ForEach(ticketSubcategoryOptions, id: \.self) { option in
                                        Text(option).tag(option)
                                    }
                                }
                                .labelsHidden()
                            }
                        }
                    }

                    GridRow {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Campus")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            if store.locations.isEmpty {
                                TextField("Campus", text: $campus)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                Picker("Campus", selection: $campus) {
                                    Text("Select campus").tag("")
                                    ForEach(store.locations.sorted(), id: \.self) { option in
                                        Text(option).tag(option)
                                    }
                                }
                                .labelsHidden()
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Room")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            if store.rooms.isEmpty {
                                TextField("Room", text: $room)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                Picker("Room", selection: $room) {
                                    Text("Select room").tag("")
                                    ForEach(store.rooms.sorted(), id: \.self) { option in
                                        Text(option).tag(option)
                                    }
                                }
                                .labelsHidden()
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Attachment")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Button("Upload Photo") {
                            pickTicketAttachment()
                        }
                        .buttonStyle(.bordered)
                        .disabled(isUploadingAttachment)

                        if attachmentURL != nil {
                            Button("Clear") {
                                attachmentURL = nil
                                attachmentName = nil
                                attachmentKind = nil
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    if isUploadingAttachment {
                        ProgressView("Uploading attachment…")
                    }
                    ticketAttachmentPreview(
                        urlString: attachmentURL,
                        attachmentName: attachmentName,
                        attachmentKind: attachmentKind
                    )
                }

                Button("Save Ticket") {
                    let activeTeamCode = [
                        store.teamCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                        store.user?.teamCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    ].first(where: { !$0.isEmpty }) ?? ""
                    store.saveTicket(
                        SupportTicket(
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            detail: detail.trimmingCharacters(in: .whitespacesAndNewlines),
                            category: category.trimmingCharacters(in: .whitespacesAndNewlines),
                            subcategory: subcategory.trimmingCharacters(in: .whitespacesAndNewlines),
                            teamCode: activeTeamCode,
                            campus: campus.trimmingCharacters(in: .whitespacesAndNewlines),
                            room: room.trimmingCharacters(in: .whitespacesAndNewlines),
                            status: .new,
                            createdBy: store.user?.email ?? Auth.auth().currentUser?.email,
                            createdByUserID: store.user?.id,
                            dueDate: hasDueDate ? dueDate : nil,
                            lastUpdatedBy: currentUserLabel,
                            attachmentURL: attachmentURL,
                            attachmentName: attachmentName,
                            attachmentKind: attachmentKind,
                            activity: [
                                TicketActivityEntry(
                                    message: "Ticket created",
                                    createdAt: Date(),
                                    author: currentUserLabel
                                )
                            ]
                        )
                    )
                    isShowingAddTicket = false
                    resetNewTicketForm()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .frame(maxWidth: 760, alignment: .leading)
        }
        .frame(maxWidth: 820)
    }

    private var availableAgents: [UserProfile] {
        store.teamMembers
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var availableLocations: [String] {
        Array(Set(store.visibleTickets.map { $0.campus.trimmingCharacters(in: .whitespacesAndNewlines) }))
            .filter { !$0.isEmpty }
            .sorted()
    }

    private var filteredTickets: [SupportTicket] {
        store.visibleTickets.filter { ticket in
            let locationMatches = locationFilter.isEmpty
                || ticket.campus.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(locationFilter) == .orderedSame
            let statusMatches = statusFilter.isEmpty
                ? ticket.status != .resolved
                : ticket.status.rawValue == statusFilter
            let agentMatches: Bool
            if agentFilter.isEmpty {
                agentMatches = true
            } else if agentFilter == unassignedAgentFilter {
                agentMatches = (ticket.assignedAgentID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false)
            } else {
                agentMatches = ticket.assignedAgentID?.trimmingCharacters(in: .whitespacesAndNewlines) == agentFilter
            }
            return locationMatches && statusMatches && agentMatches
        }
    }

    private var sortedTickets: [SupportTicket] {
        filteredTickets.sorted { lhs, rhs in
            let result: ComparisonResult
            switch ticketSortColumn {
            case .createdDate:
                result = compare(lhs.createdAt, rhs.createdAt)
            case .subject:
                result = compare(lhs.title, rhs.title)
            case .requester:
                result = compare(ticketRequesterName(lhs), ticketRequesterName(rhs))
            case .state:
                result = compare(ticketStateLabel(lhs), ticketStateLabel(rhs))
            case .status:
                result = compare(lhs.status.rawValue, rhs.status.rawValue)
            case .assignedTo:
                result = compare(ticketAssignedLabel(lhs), ticketAssignedLabel(rhs))
            }

            if result == .orderedSame {
                return lhs.createdAt > rhs.createdAt
            }
            return ticketSortAscending ? (result == .orderedAscending) : (result == .orderedDescending)
        }
    }

    var body: some View {
        if selectedTicket != nil {
            selectedTicketContent
        } else {
            ticketsListContent
        }
    }

    @ViewBuilder
    private func ticketRow(_ ticket: SupportTicket, columns: [GridItem]) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 0) {
            ticketOpenButtonCell(ticket.createdAt.formatted(date: .abbreviated, time: .shortened), ticket: ticket, weight: .medium)
            ticketOpenButtonCell(ticket.title.isEmpty ? "Untitled" : ticket.title, ticket: ticket, weight: .medium)
            ticketOpenButtonCell(ticketRequesterName(ticket), ticket: ticket)
            ticketOpenButtonCell(ticketStateLabel(ticket), ticket: ticket, color: ticketStateColor(ticket))
            ticketStatusMenuCell(ticket)
            ticketAssignedMenuCell(ticket)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(Color.white.opacity(0.015))
        .contextMenu {
            Button("Edit") {
                startsEditingSelectedTicket = true
                selectedTicket = ticket
            }
        }
    }

    private func ticketTableHeader(columns: [GridItem]) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 0) {
            ticketHeaderButton("Created Date", column: .createdDate)
            ticketHeaderButton("Subject", column: .subject)
            ticketHeaderButton("Requester", column: .requester)
            ticketHeaderButton("State", column: .state)
            ticketHeaderButton("Status", column: .status)
            ticketHeaderButton("Assigned to", column: .assignedTo)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func ticketHeaderButton(_ title: String, column: TicketSortColumn) -> some View {
        let iconName = ticketSortColumn == column
            ? (ticketSortAscending ? "arrow.up" : "arrow.down")
            : "arrow.up.arrow.down"

        return Button {
            if ticketSortColumn == column {
                ticketSortAscending.toggle()
            } else {
                ticketSortColumn = column
                ticketSortAscending = column == .subject || column == .requester || column == .state || column == .status || column == .assignedTo
            }
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()

                Image(systemName: iconName)
                    .font(.caption2)
                    .foregroundStyle(ticketSortColumn == column ? .blue : .secondary)
                    .frame(width: 12, alignment: .center)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        }
        .buttonStyle(.plain)
    }

    private func ticketCell(_ value: String, weight: Font.Weight = .regular, color: Color = .primary) -> some View {
        Text(value.isEmpty ? "—" : value)
            .font(.system(size: 13, weight: weight))
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
    }

    private func ticketOpenButtonCell(_ value: String, ticket: SupportTicket, weight: Font.Weight = .regular, color: Color = .primary) -> some View {
        Button {
            startsEditingSelectedTicket = false
            selectedTicket = ticket
        } label: {
            ticketCell(value, weight: weight, color: color)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func ticketStatusMenuCell(_ ticket: SupportTicket) -> some View {
        Picker(
            "",
            selection: Binding(
                get: { ticket.status },
                set: { newValue in
                    updateTicketStatus(ticket, status: newValue)
                }
            )
        ) {
            ForEach(TicketStatus.allCases, id: \.self) { status in
                Text(status.rawValue).tag(status)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .tint(ticket.status == .resolved ? .green : .orange)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func ticketAssignedMenuCell(_ ticket: SupportTicket) -> some View {
        if store.canSeeAllTickets {
            Picker(
                "",
                selection: Binding(
                    get: { ticket.assignedAgentID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" },
                    set: { newValue in
                        updateTicketAssignee(ticket, agentID: newValue.isEmpty ? nil : newValue)
                    }
                )
            ) {
                Text("Unassigned").tag("")
                ForEach(availableAgents) { member in
                    Text(ticketMemberDisplayName(member)).tag(member.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ticketCell(ticketAssignedLabel(ticket))
        }
    }

    private func ticketRequesterName(_ ticket: SupportTicket) -> String {
        let candidates = [
            ticket.externalRequesterName,
            ticket.createdBy?.components(separatedBy: "@").first
        ]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? "Unknown"
    }

    private func ticketAssignedLabel(_ ticket: SupportTicket) -> String {
        let assigned = ticket.assignedAgentName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return assigned.isEmpty ? "Unassigned" : assigned
    }

    private func ticketMemberDisplayName(_ member: UserProfile) -> String {
        let displayName = member.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !displayName.isEmpty { return displayName }
        return member.email.components(separatedBy: "@").first ?? member.email
    }

    private func updateTicketStatus(_ ticket: SupportTicket, status: TicketStatus) {
        guard let index = store.tickets.firstIndex(where: { $0.id == ticket.id }) else { return }
        var updated = store.tickets[index]
        updated.status = status
        updated.lastUpdatedBy = currentUserLabel
        store.saveTicket(updated)
    }

    private func updateTicketAssignee(_ ticket: SupportTicket, agentID: String?) {
        guard let index = store.tickets.firstIndex(where: { $0.id == ticket.id }) else { return }
        var updated = store.tickets[index]
        let trimmedID = agentID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedID.isEmpty {
            updated.assignedAgentID = nil
            updated.assignedAgentName = nil
        } else if let member = availableAgents.first(where: { $0.id == trimmedID }) {
            updated.assignedAgentID = member.id
            updated.assignedAgentName = ticketMemberDisplayName(member)
        }
        updated.lastUpdatedBy = currentUserLabel
        store.saveTicket(updated)
    }

    private func ticketStateLabel(_ ticket: SupportTicket) -> String {
        if ticket.status == .resolved {
            return "Resolved"
        }
        guard let dueDate = ticket.dueDate else {
            return "Open"
        }
        let now = Date()
        if dueDate < now {
            return "Overdue"
        }
        if dueDate <= Calendar.current.date(byAdding: .day, value: 1, to: now) ?? dueDate {
            return "Due Soon"
        }
        return "Scheduled"
    }

    private func ticketStateColor(_ ticket: SupportTicket) -> Color {
        switch ticketStateLabel(ticket) {
        case "Resolved":
            return .green
        case "Overdue":
            return .red
        case "Due Soon":
            return .orange
        default:
            return .secondary
        }
    }

    private func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        lhs.localizedCaseInsensitiveCompare(rhs)
    }

    private func compare(_ lhs: Date, _ rhs: Date) -> ComparisonResult {
        if lhs == rhs { return .orderedSame }
        return lhs < rhs ? .orderedAscending : .orderedDescending
    }

    private func csvEscaped(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private func exportTicketReport() {
        guard !reportTickets.isEmpty else { return }
        isExportingTicketReport = true

        let header = [
            "Created Date",
            "Updated Date",
            "Subject",
            "Requester",
            "Requester Email",
            "State",
            "Status",
            "Assigned To",
            "Campus",
            "Room",
            "Category",
            "Subcategory",
            "Due Date",
            "Resolved At",
            "Linked Asset",
            "Created By",
            "Description"
        ].map(csvEscaped).joined(separator: ",")

        let rows = reportTickets.map { ticket in
            [
                ticket.createdAt.formatted(date: .abbreviated, time: .shortened),
                ticket.updatedAt.formatted(date: .abbreviated, time: .shortened),
                ticket.title,
                ticketRequesterName(ticket),
                ticket.externalRequesterEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                ticketStateLabel(ticket),
                ticket.status.rawValue,
                ticketAssignedLabel(ticket),
                ticket.campus,
                ticket.room,
                ticket.category,
                ticket.subcategory,
                ticket.dueDate?.formatted(date: .abbreviated, time: .shortened) ?? "",
                ticket.resolvedAt?.formatted(date: .abbreviated, time: .shortened) ?? "",
                ticket.linkedGearName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                ticket.createdBy ?? "",
                ticket.detail
            ].map(csvEscaped).joined(separator: ",")
        }

        let csv = ([header] + rows).joined(separator: "\n")
        let savePanel = NSSavePanel()
        savePanel.title = "Export Tickets Report"
        savePanel.nameFieldStringValue = "TicketsReport.csv"
        savePanel.allowedContentTypes = [.commaSeparatedText]
        savePanel.canCreateDirectories = true

        defer { isExportingTicketReport = false }
        guard savePanel.runModal() == .OK, let url = savePanel.url else { return }

        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            isShowingExportSheet = false
        } catch {
            print("Ticket export failed:", error.localizedDescription)
        }
    }

    private func resetNewTicketForm() {
        title = ""
        detail = ""
        category = ""
        subcategory = ""
        campus = store.user?.assignedCampus.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        room = ""
        hasDueDate = false
        dueDate = Date()
        attachmentURL = nil
        attachmentName = nil
        attachmentKind = nil
        isUploadingAttachment = false
        attachmentError = nil
    }

    private func loadExternalTicketFormState() {
        let settings = store.externalTicketFormIntegration
        externalTicketFormEnabled = settings.isEnabled
        externalTicketFormAccessKey = settings.accessKey
        if externalTicketFormAccessKey.isEmpty, canManageExternalTicketForm {
            externalTicketFormAccessKey = store.generateExternalTicketAccessKey()
        }
    }

    private func saveExternalTicketForm() {
        isSavingExternalTicketForm = true
        externalTicketStatusMessage = ""
        store.saveExternalTicketFormIntegration(
            isEnabled: externalTicketFormEnabled,
            accessKey: externalTicketFormAccessKey
        ) { result in
            isSavingExternalTicketForm = false
            switch result {
            case .success(let settings):
                externalTicketFormEnabled = settings.isEnabled
                externalTicketFormAccessKey = settings.accessKey
                externalTicketStatusMessage = settings.isEnabled ?
                    "External ticket form is live." :
                    "External ticket form is saved but disabled."
            case .failure(let error):
                externalTicketStatusMessage = "Save failed: \(error.localizedDescription)"
            }
        }
    }

    private var currentUserLabel: String {
        let name = store.user?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !name.isEmpty { return name }
        return store.user?.email ?? Auth.auth().currentUser?.email ?? "Unknown User"
    }

    @ViewBuilder
    private func ticketAttachmentPreview(
        urlString: String?,
        attachmentName: String?,
        attachmentKind: TicketAttachmentKind?
    ) -> some View {
        let rawURL = urlString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if rawURL.isEmpty {
            Text("No attachment")
                .foregroundStyle(.secondary)
        } else if let url = URL(string: rawURL) {
            Link(destination: url) {
                Label(
                    attachmentName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                        ? (attachmentName ?? "Open Attachment")
                        : "Open Attachment",
                    systemImage: "paperclip"
                )
            }
        } else {
            Text("Invalid attachment link")
                .foregroundStyle(.secondary)
        }
    }

    @MainActor
    private func pickTicketAttachment() {
        attachmentError = nil

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]

        let handleSelection: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            uploadTicketAttachment(from: url, kind: inferredTicketAttachmentKind(for: url))
        }

        if let keyWindow = NSApp.keyWindow {
            panel.beginSheetModal(for: keyWindow, completionHandler: handleSelection)
        } else {
            handleSelection(panel.runModal())
        }
    }

    private func uploadTicketAttachment(from localURL: URL, kind: TicketAttachmentKind) {
        attachmentError = nil
        isUploadingAttachment = true

        let safeName = localURL.lastPathComponent.replacingOccurrences(of: " ", with: "_")
        let path = "ticketAttachments/\(UUID().uuidString)/\(UUID().uuidString)-\(safeName)"
        let storageRef = Storage.storage().reference().child(path)
        let metadata = StorageMetadata()
        metadata.contentType = contentType(for: localURL, kind: kind)
        let didAccess = localURL.startAccessingSecurityScopedResource()

        storageRef.putFile(from: localURL, metadata: metadata) { _, error in
            if didAccess {
                localURL.stopAccessingSecurityScopedResource()
            }

            if let error {
                DispatchQueue.main.async {
                    isUploadingAttachment = false
                    attachmentError = "Attachment upload failed: \(error.localizedDescription)"
                }
                return
            }

            storageRef.downloadURL { url, downloadError in
                DispatchQueue.main.async {
                    isUploadingAttachment = false
                    if let downloadError {
                        attachmentError = "Attachment upload failed: \(downloadError.localizedDescription)"
                        return
                    }
                    attachmentURL = url?.absoluteString
                    attachmentName = safeName
                    attachmentKind = kind
                }
            }
        }
    }

    private func contentType(for url: URL, kind: TicketAttachmentKind) -> String {
        if let type = UTType(filenameExtension: url.pathExtension), let mime = type.preferredMIMEType {
            return mime
        }
        switch kind {
        case .image:
            return "image/jpeg"
        case .video:
            return "video/quicktime"
        case .document:
            return "application/octet-stream"
        }
    }

    private func inferredTicketAttachmentKind(for url: URL) -> TicketAttachmentKind {
        if let type = UTType(filenameExtension: url.pathExtension) {
            if type.conforms(to: .image) {
                return .image
            }
            if type.conforms(to: .movie) || type.conforms(to: .video) {
                return .video
            }
        }
        return .document
    }

    private var ticketLocationMenu: some View {
        Menu {
            Button("Clear") { locationFilter = "" }
            Divider()
            ForEach(availableLocations, id: \.self) { option in
                Button(option) { locationFilter = option }
            }
        } label: {
            filterChip(
                title: locationFilter.isEmpty ? "Location" : locationFilter,
                icon: "mappin.circle",
                isActive: !locationFilter.isEmpty
            )
        }
    }

    private var ticketStatusMenu: some View {
        Menu {
            Button("Active") { statusFilter = "" }
            Divider()
            ForEach(TicketStatus.allCases, id: \.self) { option in
                Button(option.rawValue) { statusFilter = option.rawValue }
            }
        } label: {
            filterChip(
                title: statusFilter.isEmpty ? "Active" : statusFilter,
                icon: "checkmark.circle",
                isActive: !statusFilter.isEmpty
            )
        }
    }

    private var ticketAgentMenu: some View {
        Menu {
            Button("Clear") { agentFilter = "" }
            Divider()
            Button("Unassigned") { agentFilter = unassignedAgentFilter }
            if !availableAgents.isEmpty {
                Divider()
                ForEach(availableAgents) { member in
                    Button(member.displayName) { agentFilter = member.id }
                }
            }
        } label: {
            filterChip(
                title: agentFilterTitle,
                icon: "person.crop.circle",
                isActive: !agentFilter.isEmpty
            )
        }
    }

    private var agentFilterTitle: String {
        if agentFilter.isEmpty { return "Agent" }
        if agentFilter == unassignedAgentFilter { return "Unassigned" }
        return availableAgents.first(where: { $0.id == agentFilter })?.displayName ?? "Agent"
    }

    @ViewBuilder
    private func filterChip(title: String, icon: String, isActive: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(title).lineLimit(1)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isActive ? Color.blue : Color.gray.opacity(0.3))
        .foregroundColor(.white)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct MacTicketDetailView: View {
    @EnvironmentObject private var store: ProdConnectStore
    @State private var ticket: SupportTicket
    @State private var isEditing = false
    @State private var originalTicket: SupportTicket?
    @State private var scheduledStatusSaveWorkItem: DispatchWorkItem?
    @State private var showAssetPicker = false
    @State private var isUploadingAttachment = false
    @State private var attachmentError: String?
    @State private var newPrivateNote = ""

    init(ticket: SupportTicket, startEditing: Bool = false) {
        _ticket = State(initialValue: ticket)
        _isEditing = State(initialValue: startEditing)
        _originalTicket = State(initialValue: startEditing ? ticket : nil)
    }

    private var availableAgents: [UserProfile] {
        store.teamMembers
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var availableGear: [GearItem] {
        store.gear.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var ticketCategoryOptions: [String] {
        let current = ticket.category.trimmingCharacters(in: .whitespacesAndNewlines)
        var options = store.availableTicketCategories
        if !current.isEmpty && !options.contains(where: { $0.caseInsensitiveCompare(current) == .orderedSame }) {
            options.append(current)
        }
        return options.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var ticketSubcategoryOptions: [String] {
        let current = ticket.subcategory.trimmingCharacters(in: .whitespacesAndNewlines)
        var options = store.availableTicketSubcategories
        if !current.isEmpty && !options.contains(where: { $0.caseInsensitiveCompare(current) == .orderedSame }) {
            options.append(current)
        }
        return options.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func scheduleStatusSave() {
        scheduledStatusSaveWorkItem?.cancel()
        var ticketToSave = ticket
        ticketToSave.lastUpdatedBy = currentUserLabel
        let workItem = DispatchWorkItem {
            store.saveTicket(ticketToSave)
        }
        scheduledStatusSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Spacer()
                if isEditing {
                    Button("Cancel") {
                        if let originalTicket {
                            ticket = originalTicket
                        }
                        originalTicket = nil
                        isEditing = false
                    }
                    .buttonStyle(.bordered)

                    Button("Save") {
                        appendPendingPrivateNoteIfNeeded()
                        ticket.lastUpdatedBy = currentUserLabel
                        store.saveTicket(ticket)
                        originalTicket = nil
                        isEditing = false
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(ticket.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    Button("Edit") {
                        originalTicket = ticket
                        isEditing = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Form {
                Section("Overview") {
                    if isEditing {
                        TextField("Title", text: $ticket.title)
                        TextEditor(text: $ticket.detail)
                            .frame(minHeight: 120)
                    } else {
                        Text(ticket.title)
                        Text(ticket.detail.isEmpty ? "No details" : ticket.detail)
                            .foregroundStyle(ticket.detail.isEmpty ? .secondary : .primary)
                    }
                }

                Section("Status") {
                    Picker(
                        "Status",
                        selection: Binding(
                            get: { ticket.status },
                            set: { newValue in
                                ticket.status = newValue
                                if !isEditing {
                                    scheduleStatusSave()
                                }
                            }
                        )
                    ) {
                        ForEach(TicketStatus.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                }

                Section("Due Date") {
                    if isEditing {
                        Toggle("Set Due Date", isOn: hasDueDateBinding)
                        if ticket.dueDate != nil {
                            DatePicker("Due", selection: dueDateBinding, displayedComponents: [.date, .hourAndMinute])
                        }
                    } else if let dueDate = ticket.dueDate {
                        Text(dueDate.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(dueDate < Date() && ticket.status != .resolved ? .red : .primary)
                    } else {
                        Text("Not set")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Category") {
                    if isEditing {
                        if ticketCategoryOptions.isEmpty {
                            TextField("Category", text: $ticket.category)
                            TextField("Subcategory", text: $ticket.subcategory)
                        } else {
                            Picker("Category", selection: $ticket.category) {
                                Text("Select category").tag("")
                                ForEach(ticketCategoryOptions, id: \.self) { option in
                                    Text(option).tag(option)
                                }
                            }
                            if ticketSubcategoryOptions.isEmpty {
                                TextField("Subcategory", text: $ticket.subcategory)
                            } else {
                                Picker("Subcategory", selection: $ticket.subcategory) {
                                    Text("Select subcategory").tag("")
                                    ForEach(ticketSubcategoryOptions, id: \.self) { option in
                                        Text(option).tag(option)
                                    }
                                }
                            }
                        }
                    } else {
                        let categoryLine = [ticket.category, ticket.subcategory]
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                            .joined(separator: " • ")
                        Text(categoryLine.isEmpty ? "Not set" : categoryLine)
                            .foregroundStyle(categoryLine.isEmpty ? .secondary : .primary)
                    }
                }

                Section("Location") {
                    if isEditing {
                        if store.locations.isEmpty {
                            TextField("Campus", text: $ticket.campus)
                        } else {
                            Picker("Campus", selection: $ticket.campus) {
                                Text("Select campus").tag("")
                                ForEach(store.locations.sorted(), id: \.self) { option in
                                    Text(option).tag(option)
                                }
                            }
                        }
                        if store.rooms.isEmpty {
                            TextField("Room", text: $ticket.room)
                        } else {
                            Picker("Room", selection: $ticket.room) {
                                Text("Select room").tag("")
                                ForEach(store.rooms.sorted(), id: \.self) { option in
                                    Text(option).tag(option)
                                }
                            }
                        }
                    } else {
                        let locationLine = [ticket.campus, ticket.room]
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                            .joined(separator: " • ")
                        Text(locationLine.isEmpty ? "Not set" : locationLine)
                            .foregroundStyle(locationLine.isEmpty ? .secondary : .primary)
                    }
                }

                Section("Linked Asset") {
                    if isEditing {
                        Button {
                            showAssetPicker = true
                        } label: {
                            HStack {
                                Text("Asset")
                                Spacer()
                                Text(selectedAssetLabel)
                                    .foregroundStyle(selectedAssetName == nil ? .secondary : .primary)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        if ticket.linkedGearID != nil || ticket.linkedGearName != nil {
                            Button("Clear Asset Link") {
                                ticket.linkedGearID = nil
                                ticket.linkedGearName = nil
                            }
                        }
                    } else {
                        Text((ticket.linkedGearName ?? "").isEmpty ? "None" : (ticket.linkedGearName ?? ""))
                            .foregroundStyle((ticket.linkedGearName ?? "").isEmpty ? .secondary : .primary)
                    }
                }

                Section("Attachment") {
                    if isEditing {
                        HStack(spacing: 10) {
                            Button("Upload Photo") {
                                pickTicketAttachment()
                            }
                            .buttonStyle(.bordered)
                            .disabled(isUploadingAttachment)

                            if ticket.attachmentURL != nil {
                                Button("Clear Attachment") {
                                    ticket.attachmentURL = nil
                                    ticket.attachmentName = nil
                                    ticket.attachmentKind = nil
                                }
                            }
                        }
                        if isUploadingAttachment {
                            ProgressView("Uploading attachment…")
                        }
                        if let attachmentError, !attachmentError.isEmpty {
                            Text(attachmentError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }

                    ticketAttachmentPreview
                }

                Section("Assignment") {
                    if isEditing && store.canSeeAllTickets {
                        Picker(
                            "Agent",
                            selection: Binding(
                                get: { ticket.assignedAgentID ?? "" },
                                set: { newValue in
                                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if trimmed.isEmpty {
                                        ticket.assignedAgentID = nil
                                        ticket.assignedAgentName = nil
                                    } else if let member = availableAgents.first(where: { $0.id == trimmed }) {
                                        ticket.assignedAgentID = member.id
                                        ticket.assignedAgentName = member.displayName
                                    }
                                }
                            )
                        ) {
                            Text("Unassigned").tag("")
                            ForEach(availableAgents) { member in
                                Text(member.displayName).tag(member.id)
                            }
                        }
                    } else {
                        Text((ticket.assignedAgentName ?? "").isEmpty ? "Unassigned" : (ticket.assignedAgentName ?? ""))
                            .foregroundStyle((ticket.assignedAgentName ?? "").isEmpty ? .secondary : .primary)
                    }
                }

                Section("Requester") {
                    if let requesterName = requesterName {
                        LabeledContent("Name", value: requesterName)
                    }
                    if let requesterEmail = requesterEmail {
                        LabeledContent("Email", value: requesterEmail)
                        Button("Email Requester") {
                            if let url = requesterEmailURL {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    } else {
                        Text("No requester email")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Private Notes") {
                    if isEditing {
                        TextEditor(text: $newPrivateNote)
                            .frame(minHeight: 120)
                            .overlay(alignment: .topLeading) {
                                if newPrivateNote.isEmpty {
                                    Text("Add a private note")
                                        .foregroundStyle(.secondary)
                                        .padding(.top, 8)
                                        .padding(.leading, 5)
                                }
                            }
                    }
                    if ticket.privateNoteEntries.isEmpty {
                        Text("No private notes")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(ticket.privateNoteEntries.sorted { $0.createdAt > $1.createdAt }) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.message)
                                HStack {
                                    if let author = entry.author?.trimmingCharacters(in: .whitespacesAndNewlines),
                                       !author.isEmpty {
                                        Text(author)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    Text("Visible only inside ProdConnect.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Activity") {
                    if ticket.activity.isEmpty {
                        Text("No updates yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(ticket.activity.sorted { $0.createdAt > $1.createdAt }) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.message)
                                HStack {
                                    if let author = entry.author?.trimmingCharacters(in: .whitespacesAndNewlines),
                                       !author.isEmpty {
                                        Text(author)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .navigationTitle("Ticket")
        .sheet(isPresented: $showAssetPicker) {
            MacAssetPickerView(
                selectedAssetID: ticket.linkedGearID,
                onSelect: { item in
                    ticket.linkedGearID = item.id
                    ticket.linkedGearName = item.name
                }
            )
            .environmentObject(store)
        }
        .onAppear {
            newPrivateNote = ""
        }
    }

    private var currentUserLabel: String {
        let name = store.user?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !name.isEmpty { return name }
        return store.user?.email ?? Auth.auth().currentUser?.email ?? "Unknown User"
    }

    private func appendPendingPrivateNoteIfNeeded() {
        let trimmedNote = newPrivateNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNote.isEmpty else { return }
        ticket.privateNoteEntries.append(
            TicketPrivateNoteEntry(
                message: trimmedNote,
                createdAt: Date(),
                author: currentUserLabel
            )
        )
        newPrivateNote = ""
    }

    private var selectedAssetName: String? {
        let currentName = ticket.linkedGearName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !currentName.isEmpty {
            return currentName
        }
        guard let linkedGearID = ticket.linkedGearID else { return nil }
        return availableGear.first(where: { $0.id == linkedGearID })?.name
    }

    private var selectedAssetLabel: String {
        selectedAssetName ?? "Select Asset"
    }

    private var requesterName: String? {
        let candidates = [
            ticket.externalRequesterName,
            ticket.createdBy?.components(separatedBy: "@").first
        ]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }

    private var requesterEmail: String? {
        let candidates = [
            ticket.externalRequesterEmail,
            ticket.createdBy
        ]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty && $0.contains("@") })
    }

    private var requesterEmailURL: URL? {
        guard let requesterEmail else { return nil }
        let subject = "Re: \(ticket.title.isEmpty ? "Your Support Ticket" : ticket.title)"
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "mailto:\(requesterEmail)?subject=\(encodedSubject)")
    }

    private var hasDueDateBinding: Binding<Bool> {
        Binding(
            get: { ticket.dueDate != nil },
            set: { isEnabled in
                ticket.dueDate = isEnabled ? (ticket.dueDate ?? Date()) : nil
            }
        )
    }

    private var dueDateBinding: Binding<Date> {
        Binding(
            get: { ticket.dueDate ?? Date() },
            set: { ticket.dueDate = $0 }
        )
    }

    @ViewBuilder
    private var ticketAttachmentPreview: some View {
        let rawURL = ticket.attachmentURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if rawURL.isEmpty {
            Text("No attachment")
                .foregroundStyle(.secondary)
        } else if let url = URL(string: rawURL) {
            Link(destination: url) {
                Label(
                    ticket.attachmentName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                        ? (ticket.attachmentName ?? "Open Attachment")
                        : "Open Attachment",
                    systemImage: "paperclip"
                )
            }
        } else {
            Text("Invalid attachment link")
                .foregroundStyle(.secondary)
        }
    }

    @MainActor
    private func pickTicketAttachment() {
        attachmentError = nil

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]

        let handleSelection: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            uploadTicketAttachment(from: url, kind: inferredTicketAttachmentKind(for: url))
        }

        if let keyWindow = NSApp.keyWindow {
            panel.beginSheetModal(for: keyWindow, completionHandler: handleSelection)
        } else {
            handleSelection(panel.runModal())
        }
    }

    private func uploadTicketAttachment(from localURL: URL, kind: TicketAttachmentKind) {
        attachmentError = nil
        isUploadingAttachment = true

        let safeName = localURL.lastPathComponent.replacingOccurrences(of: " ", with: "_")
        let path = "ticketAttachments/\(ticket.id)/\(UUID().uuidString)-\(safeName)"
        let storageRef = Storage.storage().reference().child(path)
        let metadata = StorageMetadata()
        metadata.contentType = contentType(for: localURL, kind: kind)
        let didAccess = localURL.startAccessingSecurityScopedResource()

        storageRef.putFile(from: localURL, metadata: metadata) { _, error in
            if didAccess {
                localURL.stopAccessingSecurityScopedResource()
            }

            if let error {
                DispatchQueue.main.async {
                    isUploadingAttachment = false
                    attachmentError = "Attachment upload failed: \(error.localizedDescription)"
                }
                return
            }

            storageRef.downloadURL { url, downloadError in
                DispatchQueue.main.async {
                    isUploadingAttachment = false
                    if let downloadError {
                        attachmentError = "Attachment upload failed: \(downloadError.localizedDescription)"
                        return
                    }
                    ticket.attachmentURL = url?.absoluteString
                    ticket.attachmentName = safeName
                    ticket.attachmentKind = kind
                }
            }
        }
    }

    private func contentType(for url: URL, kind: TicketAttachmentKind) -> String {
        if let type = UTType(filenameExtension: url.pathExtension), let mime = type.preferredMIMEType {
            return mime
        }
        switch kind {
        case .image:
            return "image/jpeg"
        case .video:
            return "video/quicktime"
        case .document:
            return "application/octet-stream"
        }
    }

    private func inferredTicketAttachmentKind(for url: URL) -> TicketAttachmentKind {
        if let type = UTType(filenameExtension: url.pathExtension) {
            if type.conforms(to: .image) {
                return .image
            }
            if type.conforms(to: .movie) || type.conforms(to: .video) {
                return .video
            }
        }
        return .document
    }
}

private struct MacAssetPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ProdConnectStore
    @State private var searchText = ""
    @State private var selectedCategory: String?
    @State private var selectedStatus: GearItem.GearStatus?
    @State private var selectedLocation: String?

    let selectedAssetID: String?
    let onSelect: (GearItem) -> Void

    private var availableCategories: [String] {
        Array(Set(store.gear.map(\.category))).filter { !$0.isEmpty }.sorted()
    }

    private var availableLocations: [String] {
        Array(Set(store.gear.map(\.location))).filter { !$0.isEmpty }.sorted()
    }

    private var filteredAssets: [GearItem] {
        var result = store.gear
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.category.localizedCaseInsensitiveContains(searchText) ||
                $0.location.localizedCaseInsensitiveContains(searchText)
            }
        }
        if let selectedCategory {
            result = result.filter { $0.category == selectedCategory }
        }
        if let selectedStatus {
            result = result.filter { $0.status == selectedStatus }
        }
        if let selectedLocation {
            result = result.filter { $0.location == selectedLocation }
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Select Asset")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
            }

            TextField("Search assets...", text: $searchText)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                categoryMenu
                if !availableLocations.isEmpty {
                    locationMenu
                }
                statusMenu
            }

            List {
                if filteredAssets.isEmpty {
                    Text("No assets found")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredAssets) { item in
                        Button {
                            onSelect(item)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name)
                                        .font(.headline)
                                    Text(item.category)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if !item.location.isEmpty {
                                        Text(item.location)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if item.id == selectedAssetID {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .padding()
        .frame(minWidth: 520, minHeight: 520)
    }

    private var categoryMenu: some View {
        Menu {
            Button("Clear") { selectedCategory = nil }
            Divider()
            ForEach(availableCategories, id: \.self) { option in
                Button(option) { selectedCategory = option }
            }
        } label: {
            filterChip(
                title: selectedCategory ?? "Category",
                icon: "line.3.horizontal.decrease.circle",
                isActive: selectedCategory != nil
            )
        }
    }

    private var locationMenu: some View {
        Menu {
            Button("Clear") { selectedLocation = nil }
            Divider()
            ForEach(availableLocations, id: \.self) { option in
                Button(option) { selectedLocation = option }
            }
        } label: {
            filterChip(
                title: selectedLocation ?? "Location",
                icon: "mappin.circle",
                isActive: selectedLocation != nil
            )
        }
    }

    private var statusMenu: some View {
        Menu {
            Button("Clear") { selectedStatus = nil }
            Divider()
            ForEach(GearItem.GearStatus.allCases, id: \.self) { option in
                Button(option.rawValue) { selectedStatus = option }
            }
        } label: {
            filterChip(
                title: selectedStatus?.rawValue ?? "Status",
                icon: "checkmark.circle",
                isActive: selectedStatus != nil
            )
        }
    }

    @ViewBuilder
    private func filterChip(title: String, icon: String, isActive: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(title).lineLimit(1)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isActive ? Color.blue : Color.gray.opacity(0.3))
        .foregroundColor(.white)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct MacChecklistView: View {
    @EnvironmentObject private var store: ProdConnectStore
    @State private var selectedChecklist: ChecklistTemplate?
    @State private var startsEditingSelectedChecklist = false
    @State private var isShowingAddChecklist = false
    @State private var isShowingAddGroup = false
    @State private var title = ""
    @State private var groupName = ""
    @State private var newGroupName = ""
    @State private var newChecklistItems = Array(repeating: "", count: 3)
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var collapsedGroups: Set<String> = []
    private var canManageChecklistDueDate: Bool { store.user?.isAdmin == true || store.user?.isOwner == true }
    @State private var checklistSortColumn: ChecklistSortColumn = .name
    @State private var checklistSortAscending = true

    private enum ChecklistSortColumn {
        case name
        case assignee
        case dueDate
    }

    private let checklistMinimumColumnWidths: [CGFloat] = [320, 180, 150]
    private let checklistColumnWeights: [CGFloat] = [0.58, 0.24, 0.18]

    private func checklistColumns(for availableWidth: CGFloat) -> [GridItem] {
        adaptiveTableColumnWidths(
            availableWidth: availableWidth,
            minimums: checklistMinimumColumnWidths,
            weights: checklistColumnWeights
        ).map { width in
            GridItem(.fixed(width), spacing: 0, alignment: .leading)
        }
    }

    private func checklistTableWidth(for availableWidth: CGFloat) -> CGFloat {
        adaptiveTableColumnWidths(
            availableWidth: availableWidth,
            minimums: checklistMinimumColumnWidths,
            weights: checklistColumnWeights
        ).reduce(28, +)
    }

    private var sortedChecklists: [ChecklistTemplate] {
        store.checklists.sorted { lhs, rhs in
            let result: ComparisonResult
            switch checklistSortColumn {
            case .name:
                result = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
            case .assignee:
                result = checklistAssigneeLabel(lhs).localizedCaseInsensitiveCompare(checklistAssigneeLabel(rhs))
            case .dueDate:
                result = compareChecklistDates(lhs.dueDate, rhs.dueDate)
            }

            if result == .orderedSame {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return checklistSortAscending ? (result == .orderedAscending) : (result == .orderedDescending)
        }
    }

    private var groupedSortedChecklists: [(group: String, items: [ChecklistTemplate])] {
        let grouped = Dictionary(grouping: sortedChecklists) { checklistGroupTitle(for: $0) }
        let allGroups = Set(grouped.keys).union(store.availableChecklistGroups.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        return allGroups.sorted { lhs, rhs in
            if lhs == "Ungrouped" { return false }
            if rhs == "Ungrouped" { return true }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }.map { key in
            (group: key, items: grouped[key] ?? [])
        }
    }

    var body: some View {
        if let selectedChecklist {
            VStack(alignment: .leading, spacing: 16) {
                Button {
                    startsEditingSelectedChecklist = false
                    self.selectedChecklist = nil
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)

                MacChecklistDetailView(
                    checklist: selectedChecklist,
                    startEditing: startsEditingSelectedChecklist
                )
            }
            .padding()
            .background(Color.clear)
            .navigationTitle(selectedChecklist.title)
        } else {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Spacer()
                if isShowingAddChecklist || isShowingAddGroup {
                    Button("Cancel") {
                        isShowingAddChecklist = false
                        isShowingAddGroup = false
                        resetNewChecklistForm()
                    }
                    .buttonStyle(.bordered)
                }
                Menu {
                    Button("Add Group") {
                        isShowingAddChecklist = false
                        isShowingAddGroup = true
                        newGroupName = ""
                    }
                    Button("Add Checklist") {
                        resetNewChecklistForm()
                        isShowingAddGroup = false
                        isShowingAddChecklist = true
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(nsColor: .controlAccentColor))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            GeometryReader { proxy in
                let tableWidth = checklistTableWidth(for: proxy.size.width)
                let columns = checklistColumns(for: proxy.size.width)

                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        checklistTableHeader(columns: columns)
                            .frame(minWidth: tableWidth, alignment: .leading)

                        ScrollView {
                            LazyVStack(spacing: 0) {
                                if sortedChecklists.isEmpty {
                                    Text("No checklists")
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 18)
                                } else {
                                    ForEach(groupedSortedChecklists, id: \.group) { section in
                                        Button {
                                            toggleGroup(section.group)
                                        } label: {
                                            HStack(spacing: 8) {
                                                Image(systemName: collapsedGroups.contains(section.group) ? "chevron.right" : "chevron.down")
                                                    .font(.caption.weight(.semibold))
                                                Text(section.group)
                                                    .font(.title3.weight(.semibold))
                                                Spacer()
                                            }
                                            .foregroundStyle(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.horizontal, 14)
                                            .padding(.top, 12)
                                            .padding(.bottom, 6)
                                        }
                                        .buttonStyle(.plain)
                                        if !collapsedGroups.contains(section.group) {
                                            ForEach(section.items) { checklist in
                                                checklistRow(checklist, columns: columns)
                                                Divider()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .frame(minWidth: tableWidth, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            if isShowingAddGroup {
                GroupBox("Add Group") {
                    VStack(spacing: 10) {
                        TextField("Group", text: $newGroupName)
                        HStack {
                            Spacer()
                            Button("Save Group") {
                                store.addChecklistGroup(newGroupName)
                                newGroupName = ""
                                isShowingAddGroup = false
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }

            if isShowingAddChecklist {
                GroupBox("Add Checklist") {
                    VStack(spacing: 10) {
                        TextField("Title", text: $title)
                        TextField("Group", text: $groupName)
                        if !store.availableChecklistGroups.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(store.availableChecklistGroups, id: \.self) { group in
                                        Button(group) {
                                            groupName = group
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if canManageChecklistDueDate {
                            Toggle("Set due date", isOn: $hasDueDate)
                            if hasDueDate {
                                DatePicker("Due", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                            }
                        } else {
                            Text("Only owners and admins can set the overall checklist due date.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Text("Items")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(Array(newChecklistItems.indices), id: \.self) { index in
                            TextField("Item \(index + 1)", text: $newChecklistItems[index])
                        }
                        Button("Add Another Item") {
                            newChecklistItems.append("")
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Save Checklist") {
                            let parsedItems = newChecklistItems.compactMap { item -> ChecklistItem? in
                                let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !trimmed.isEmpty else { return nil }
                                return ChecklistItem(text: trimmed)
                            }
                            let items = parsedItems.isEmpty ? [ChecklistItem(text: "New Item")] : parsedItems
                            var checklist = ChecklistTemplate(
                                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                teamCode: store.teamCode ?? "",
                                groupName: groupName.trimmingCharacters(in: .whitespacesAndNewlines),
                                items: items,
                                createdBy: store.user?.email
                            )
                            checklist.dueDate = hasDueDate ? dueDate : nil
                            store.saveChecklist(checklist)
                            resetNewChecklistForm()
                            isShowingAddChecklist = false
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .padding()
        .background(Color.clear)
        .navigationTitle("Checklist")
        }
    }

    @ViewBuilder
    private func checklistRow(_ checklist: ChecklistTemplate, columns: [GridItem]) -> some View {
        Button {
            isShowingAddChecklist = false
            startsEditingSelectedChecklist = false
            selectedChecklist = checklist
        } label: {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(checklist.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(checklistSubtitle(checklist))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(checklistAssigneeLabel(checklist))
                    .foregroundStyle(checklistAssigneeLabel(checklist) == "Unassigned" ? .secondary : .primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(checklistDueDateLabel(checklist))
                    .foregroundStyle(checklistDueDateColor(checklist))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(Color.white.opacity(0.015))
        .contextMenu {
            Button("Edit") {
                isShowingAddChecklist = false
                startsEditingSelectedChecklist = true
                selectedChecklist = checklist
            }
            Button("Duplicate") {
                duplicateChecklist(checklist)
            }

            Button(role: .destructive) {
                store.deleteChecklist(checklist)
            } label: {
                Text("Delete")
            }
        }
    }

    private func checklistTableHeader(columns: [GridItem]) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 0) {
            checklistHeaderButton("Name", column: .name)
            checklistHeaderButton("Assignee", column: .assignee)
            checklistHeaderButton("Due date", column: .dueDate)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func checklistHeaderButton(_ title: String, column: ChecklistSortColumn) -> some View {
        let iconName = checklistSortColumn == column
            ? (checklistSortAscending ? "arrow.up" : "arrow.down")
            : "arrow.up.arrow.down"

        return Button {
            if checklistSortColumn == column {
                checklistSortAscending.toggle()
            } else {
                checklistSortColumn = column
                checklistSortAscending = column != .dueDate
            }
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()

                Image(systemName: iconName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, alignment: .trailing)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func isChecklistCompleted(_ checklist: ChecklistTemplate) -> Bool {
        !checklist.items.isEmpty && checklist.items.allSatisfy(\.isDone)
    }

    private func duplicateChecklist(_ checklist: ChecklistTemplate) {
        var copy = checklist
        copy.id = UUID().uuidString
        copy.title = "\(checklist.title) Copy"
        copy.dueDate = nil
        copy.completedAt = nil
        copy.completedBy = nil
        copy.items = checklist.items.map { item in
            var newItem = item
            newItem.id = UUID().uuidString
            newItem.isDone = false
            newItem.completedAt = nil
            newItem.completedBy = nil
            return newItem
        }
        copy.createdBy = Auth.auth().currentUser?.email
        store.saveChecklist(copy)
    }

    private func resetNewChecklistForm() {
        title = ""
        groupName = ""
        newGroupName = ""
        newChecklistItems = Array(repeating: "", count: 3)
        hasDueDate = false
        dueDate = Date()
    }

    private func checklistSubtitle(_ checklist: ChecklistTemplate) -> String {
        if isChecklistCompleted(checklist) {
            if let completedAt = checklist.completedAt {
                let completedBy = checklist.completedBy?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let completedBy, !completedBy.isEmpty {
                    return "Completed by \(completedBy) on \(completedAt.formatted(date: .abbreviated, time: .shortened))"
                }
                return "Completed on \(completedAt.formatted(date: .abbreviated, time: .shortened))"
            }
            return "Completed"
        }
        return "\(checklist.items.count) tasks"
    }

    private func checklistGroupTitle(for checklist: ChecklistTemplate) -> String {
        let trimmed = checklist.groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Ungrouped" : trimmed
    }

    private func toggleGroup(_ group: String) {
        if collapsedGroups.contains(group) {
            collapsedGroups.remove(group)
        } else {
            collapsedGroups.insert(group)
        }
    }

    private func checklistAssigneeLabel(_ checklist: ChecklistTemplate) -> String {
        let names = checklist.items.compactMap { item in
            let storedName = item.assignedUserName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !storedName.isEmpty { return storedName }
            let storedEmail = item.assignedUserEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !storedEmail.isEmpty {
                return storedEmail.components(separatedBy: "@").first ?? storedEmail
            }
            return nil
        }

        let uniqueNames = Array(NSOrderedSet(array: names)) as? [String] ?? []
        if uniqueNames.isEmpty { return "Unassigned" }
        if uniqueNames.count == 1 { return uniqueNames[0] }
        return "\(uniqueNames[0]) +\(uniqueNames.count - 1)"
    }

    private func checklistDueDateLabel(_ checklist: ChecklistTemplate) -> String {
        guard let dueDate = checklist.dueDate else { return "No due date" }
        return dueDate.formatted(date: .abbreviated, time: .shortened)
    }

    private func checklistDueDateColor(_ checklist: ChecklistTemplate) -> Color {
        guard let dueDate = checklist.dueDate else { return .secondary }
        if !isChecklistCompleted(checklist) && dueDate < Date() {
            return .red
        }
        return .primary
    }

    private func compareChecklistDates(_ lhs: Date?, _ rhs: Date?) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (left?, right?):
            if left == right { return .orderedSame }
            return left < right ? .orderedAscending : .orderedDescending
        case (nil, nil):
            return .orderedSame
        case (nil, _):
            return .orderedDescending
        case (_, nil):
            return .orderedAscending
        }
    }
}

private struct MacChecklistDetailView: View {
    @EnvironmentObject private var store: ProdConnectStore
    @State private var checklist: ChecklistTemplate
    @State private var isEditing = false
    @State private var originalChecklist: ChecklistTemplate?
    @State private var newItemText = ""
    @State private var newItemNotes = ""
    @State private var newItemAssignedUserID = ""
    @State private var newItemHasDueDate = false
    @State private var newItemDueDate = Date()

    init(checklist: ChecklistTemplate, startEditing: Bool = false) {
        _checklist = State(initialValue: checklist)
        _isEditing = State(initialValue: startEditing)
        _originalChecklist = State(initialValue: startEditing ? checklist : nil)
    }

    private var canAssignTasks: Bool { store.canAssignChecklistTasks }
    private var canManageChecklistDueDate: Bool { store.user?.isAdmin == true || store.user?.isOwner == true }
    private var assignableMembers: [UserProfile] {
        store.teamMembers.sorted {
            displayName(for: $0).localizedCaseInsensitiveCompare(displayName(for: $1)) == .orderedAscending
        }
    }
    private var showsAssignmentFeatures: Bool { store.teamHasChecklistTaskAssignmentFeatures }
    private var todoItemIndices: [Int] { checklist.items.indices.filter { !checklist.items[$0].isDone } }
    private var completedItemIndices: [Int] { checklist.items.indices.filter { checklist.items[$0].isDone } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Spacer()
                if isEditing {
                    Button("Cancel") {
                        if let originalChecklist {
                            checklist = originalChecklist
                        }
                        originalChecklist = nil
                        isEditing = false
                        newItemText = ""
                        newItemNotes = ""
                        newItemAssignedUserID = ""
                        newItemHasDueDate = false
                        newItemDueDate = Date()
                    }
                    .buttonStyle(.bordered)

                    Button("Save") {
                        saveChecklistChanges()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(checklist.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    Button("Edit") {
                        originalChecklist = checklist
                        isEditing = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Form {
                if isEditing {
                    Section("Overview") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Title")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("Title", text: $checklist.title)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Group")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("Group", text: $checklist.groupName)
                        }
                        LabeledContent("Created By", value: textValue(checklist.createdBy))
                        if canManageChecklistDueDate {
                            Toggle("Set overall due date", isOn: checklistHasDueDateBinding)
                            if checklist.dueDate != nil {
                                DatePicker("Due Date", selection: checklistDueDateBinding, displayedComponents: [.date, .hourAndMinute])
                            }
                        } else {
                            LabeledContent("Due Date", value: dateValue(checklist.dueDate))
                        }
                    }

                    Section("To Do") {
                        if todoItemIndices.isEmpty {
                            Text("No open tasks")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(todoItemIndices, id: \.self) { index in
                                editableTaskCard(index: index)
                            }
                        }
                    }
                    if !completedItemIndices.isEmpty {
                        Section("Completed") {
                            ForEach(completedItemIndices, id: \.self) { index in
                                editableTaskCard(index: index)
                            }
                        }
                    }

                    Section("Add Task") {
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("New Item", text: $newItemText)
                            if canAssignTasks {
                                Picker("Assigned To", selection: $newItemAssignedUserID) {
                                    Text("Unassigned").tag("")
                                    ForEach(assignableMembers) { member in
                                        Text(displayName(for: member)).tag(member.id)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                            Toggle("Set task due date", isOn: $newItemHasDueDate)
                            if newItemHasDueDate {
                                DatePicker("Task Due", selection: $newItemDueDate, displayedComponents: [.date, .hourAndMinute])
                            }
                            TextField("Notes (optional)", text: $newItemNotes, axis: .vertical)
                                .lineLimit(2...4)
                            HStack {
                                Spacer()
                                Button("Add Item") {
                                    let trimmed = newItemText.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !trimmed.isEmpty else { return }
                                    let trimmedNotes = newItemNotes.trimmingCharacters(in: .whitespacesAndNewlines)
                                    checklist.items.append(
                                        makeChecklistItem(
                                            text: trimmed,
                                            notes: trimmedNotes,
                                            assignedUserID: newItemAssignedUserID,
                                            dueDate: newItemHasDueDate ? newItemDueDate : nil
                                        )
                                    )
                                    newItemText = ""
                                    newItemNotes = ""
                                    newItemAssignedUserID = ""
                                    newItemHasDueDate = false
                                    newItemDueDate = Date()
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(newItemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                    }
                } else {
                    Section("Overview") {
                        LabeledContent("Title", value: checklist.title)
                        LabeledContent("Group", value: textValue(checklist.groupName))
                        LabeledContent("Items", value: "\(checklist.items.count)")
                        LabeledContent("Created By", value: textValue(checklist.createdBy))
                        LabeledContent("Due Date", value: dateValue(checklist.dueDate))
                        LabeledContent("Completed At", value: dateValue(checklist.completedAt))
                        LabeledContent("Completed By", value: textValue(checklist.completedBy))
                    }

                    Section("To Do") {
                        if todoItemIndices.isEmpty {
                            Text("No open tasks")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(todoItemIndices, id: \.self) { index in
                                readOnlyTaskCard(item: checklist.items[index])
                            }
                        }
                    }
                    if !completedItemIndices.isEmpty {
                        Section("Completed") {
                            ForEach(completedItemIndices, id: \.self) { index in
                                readOnlyTaskCard(item: checklist.items[index])
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .navigationTitle(checklist.title)
        .onAppear {
            store.listenToTeamMembers()
        }
    }

    @ViewBuilder
    private func editableTaskCard(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TextField("Item", text: $checklist.items[index].text)
                Button(role: .destructive) {
                    checklist.items.remove(at: index)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            if canAssignTasks {
                Picker("Assigned To", selection: assignmentSelection(for: index)) {
                    Text("Unassigned").tag("")
                    ForEach(assignableMembers) { member in
                        Text(displayName(for: member)).tag(member.id)
                    }
                }
                .pickerStyle(.menu)
            }

            Toggle("Set task due date", isOn: itemHasDueDateBinding(for: index))
            if checklist.items[index].dueDate != nil {
                DatePicker("Task Due", selection: itemDueDateBinding(for: index), displayedComponents: [.date, .hourAndMinute])
            }
            if showsAssignmentFeatures {
                taskMetadataRow(for: checklist.items[index])
            }

            TextField("Notes (optional)", text: $checklist.items[index].notes, axis: .vertical)
                .lineLimit(2...4)
        }
        .padding(12)
        .background(taskCardBackground(for: checklist.items[index]))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func readOnlyTaskCard(item: ChecklistItem) -> some View {
        Button {
            toggleItem(itemID: item.id)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isDone ? Color.green : Color.secondary)
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.text)
                        .foregroundStyle(.primary)
                        .font(.body.weight(.medium))
                    let trimmedNotes = item.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedNotes.isEmpty {
                        Text(trimmedNotes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if showsAssignmentFeatures {
                        taskMetadataRow(for: item)
                    }
                    if item.isDone, let completedAt = item.completedAt {
                        if let completedBy = item.completedBy?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !completedBy.isEmpty {
                            Text("Checked by \(completedBy) on \(completedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Checked on \(completedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(12)
            .background(taskCardBackground(for: item))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func textValue(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Not set" : trimmed
    }

    private func displayName(for member: UserProfile) -> String {
        let trimmed = member.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return member.email.components(separatedBy: "@").first ?? member.email
    }

    private func assignmentSelection(for index: Int) -> Binding<String> {
        Binding(
            get: {
                guard checklist.items.indices.contains(index) else { return "" }
                return checklist.items[index].assignedUserID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            },
            set: { newValue in
                guard checklist.items.indices.contains(index) else { return }
                applyAssignment(selectedUserID: newValue, to: index)
            }
        )
    }

    private var checklistHasDueDateBinding: Binding<Bool> {
        Binding(
            get: { checklist.dueDate != nil },
            set: { shouldSetDueDate in
                checklist.dueDate = shouldSetDueDate ? (checklist.dueDate ?? Date()) : nil
            }
        )
    }

    private var checklistDueDateBinding: Binding<Date> {
        Binding(
            get: { checklist.dueDate ?? Date() },
            set: { newValue in
                checklist.dueDate = newValue
            }
        )
    }

    private func itemHasDueDateBinding(for index: Int) -> Binding<Bool> {
        Binding(
            get: {
                guard checklist.items.indices.contains(index) else { return false }
                return checklist.items[index].dueDate != nil
            },
            set: { shouldSetDueDate in
                guard checklist.items.indices.contains(index) else { return }
                checklist.items[index].dueDate = shouldSetDueDate ? (checklist.items[index].dueDate ?? checklist.dueDate ?? Date()) : nil
            }
        )
    }

    private func itemDueDateBinding(for index: Int) -> Binding<Date> {
        Binding(
            get: {
                guard checklist.items.indices.contains(index) else { return checklist.dueDate ?? Date() }
                return checklist.items[index].dueDate ?? checklist.dueDate ?? Date()
            },
            set: { newValue in
                guard checklist.items.indices.contains(index) else { return }
                checklist.items[index].dueDate = newValue
            }
        )
    }

    private func makeChecklistItem(text: String, notes: String, assignedUserID: String, dueDate: Date?) -> ChecklistItem {
        var item = ChecklistItem(text: text, notes: notes, dueDate: dueDate)
        applyAssignment(selectedUserID: assignedUserID, to: &item)
        return item
    }

    private func applyAssignment(selectedUserID: String, to index: Int) {
        guard checklist.items.indices.contains(index) else { return }
        applyAssignment(selectedUserID: selectedUserID, to: &checklist.items[index])
    }

    private func applyAssignment(selectedUserID: String, to item: inout ChecklistItem) {
        let trimmedID = selectedUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty,
              let member = assignableMembers.first(where: { $0.id == trimmedID }) else {
            item.assignedUserID = nil
            item.assignedUserName = nil
            item.assignedUserEmail = nil
            return
        }
        item.assignedUserID = member.id
        item.assignedUserName = displayName(for: member)
        item.assignedUserEmail = member.email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func assignmentLabel(for item: ChecklistItem) -> String? {
        if let member = assignedMember(for: item) {
            return displayName(for: member)
        }

        let storedName = item.assignedUserName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !storedName.isEmpty { return storedName }

        let storedEmail = item.assignedUserEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !storedEmail.isEmpty {
            return storedEmail.components(separatedBy: "@").first ?? storedEmail
        }

        return nil
    }

    @ViewBuilder
    private func taskMetadataRow(for item: ChecklistItem) -> some View {
        HStack(spacing: 8) {
            if let assignmentText = assignmentLabel(for: item) {
                Label(assignmentText, systemImage: "person.crop.circle")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.14))
                    .clipShape(Capsule())
            }
            if let dueDate = item.dueDate {
                Label(dueDateLabel(for: dueDate), systemImage: dueDate < Date() && !item.isDone ? "exclamationmark.circle" : "calendar")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(dueDate < Date() && !item.isDone ? Color.red : Color.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((dueDate < Date() && !item.isDone ? Color.red : Color.gray).opacity(0.12))
                    .clipShape(Capsule())
            }
            Spacer(minLength: 0)
        }
    }

    private func dueDateLabel(for dueDate: Date) -> String {
        if Calendar.current.isDateInToday(dueDate) { return "Today" }
        if Calendar.current.isDateInTomorrow(dueDate) { return "Tomorrow" }
        return dueDate.formatted(date: .abbreviated, time: .shortened)
    }

    private func taskCardBackground(for item: ChecklistItem) -> Color {
        if item.isDone { return Color.green.opacity(0.08) }
        if showsAssignmentFeatures && isAssignedToCurrentUser(item) { return Color.yellow.opacity(0.16) }
        return Color.white.opacity(0.04)
    }

    private func isAssignedToCurrentUser(_ item: ChecklistItem) -> Bool {
        guard let current = store.user else { return false }
        let assignedID = item.assignedUserID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !assignedID.isEmpty,
           assignedID == current.id.trimmingCharacters(in: .whitespacesAndNewlines) {
            return true
        }
        let assignedEmail = item.assignedUserEmail?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if !assignedEmail.isEmpty,
           assignedEmail == current.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            return true
        }
        return false
    }

    private func assignedMember(for item: ChecklistItem) -> UserProfile? {
        let assignedID = item.assignedUserID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !assignedID.isEmpty,
           let member = assignableMembers.first(where: { $0.id == assignedID }) {
            return member
        }

        let assignedEmail = item.assignedUserEmail?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if !assignedEmail.isEmpty {
            return assignableMembers.first {
                $0.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == assignedEmail
            }
        }

        return nil
    }

    private func dateValue(_ value: Date?) -> String {
        guard let value else { return "Not set" }
        return value.formatted(date: .abbreviated, time: .shortened)
    }

    private func toggleItem(itemID: String) {
        guard let idx = checklist.items.firstIndex(where: { $0.id == itemID }) else { return }
        checklist.items[idx].isDone.toggle()
        if checklist.items[idx].isDone {
            checklist.items[idx].completedAt = Date()
            checklist.items[idx].completedBy = completionUserLabel
        } else {
            checklist.items[idx].completedAt = nil
            checklist.items[idx].completedBy = nil
        }
        updateChecklistCompletionMetadata()
        store.saveChecklist(checklist)
    }

    private func updateChecklistCompletionMetadata() {
        if checklist.items.isEmpty {
            checklist.completedAt = nil
            checklist.completedBy = nil
            return
        }

        if checklist.items.allSatisfy(\.isDone) {
            if checklist.completedAt == nil {
                checklist.completedAt = Date()
            }
            if (checklist.completedBy ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                checklist.completedBy = completionUserLabel
            }
        } else {
            checklist.completedAt = nil
            checklist.completedBy = nil
        }
    }

    private func saveChecklistChanges() {
        checklist.title = checklist.title.trimmingCharacters(in: .whitespacesAndNewlines)
        checklist.groupName = checklist.groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        checklist.items = checklist.items.compactMap { item in
            let trimmed = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            var updatedItem = item
            updatedItem.text = trimmed
            updatedItem.notes = updatedItem.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            return updatedItem
        }
        updateChecklistCompletionMetadata()
        store.saveChecklist(checklist)
        originalChecklist = nil
        newItemText = ""
        newItemNotes = ""
        newItemAssignedUserID = ""
        newItemHasDueDate = false
        newItemDueDate = Date()
        isEditing = false
    }

    private var completionUserLabel: String {
        let displayName = store.user?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !displayName.isEmpty { return displayName }
        let email = store.user?.email.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !email.isEmpty { return email }
        return "Unknown User"
    }
}

private struct MacIdeasView: View {
    @EnvironmentObject private var store: ProdConnectStore
    @State private var isShowingAddIdea = false
    @State private var editingIdea: IdeaCard?
    @State private var title = ""
    @State private var detail = ""
    @State private var tags = ""
    
    private var canSaveIdea: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var currentUserID: String {
        store.user?.id.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var canEditIdeas: Bool {
        store.canEditIdeas
    }

    private var activeIdeas: [IdeaCard] {
        store.ideas
            .filter { !$0.implemented }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var completedIdeas: [IdeaCard] {
        store.ideas
            .filter(\.implemented)
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Spacer()
                if isShowingAddIdea {
                    Button("Cancel") {
                        resetIdeaForm()
                        isShowingAddIdea = false
                    }
                    .buttonStyle(.bordered)
                }
                Button {
                    if isShowingAddIdea {
                        resetIdeaForm()
                        isShowingAddIdea = false
                    } else {
                        resetIdeaForm()
                        isShowingAddIdea = true
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            List {
                if !activeIdeas.isEmpty {
                    Section("Not Completed") {
                        ForEach(activeIdeas) { idea in
                            ideaRow(idea)
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                store.deleteIdea(activeIdeas[index])
                            }
                        }
                    }
                }

                if !completedIdeas.isEmpty {
                    Section("Completed") {
                        ForEach(completedIdeas) { idea in
                            ideaRow(idea)
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                store.deleteIdea(completedIdeas[index])
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)

            if isShowingAddIdea {
                GroupBox(editingIdea == nil ? "Add Idea" : "Edit Idea") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Title", text: $title)
                        TextEditor(text: $detail)
                            .frame(minHeight: 120)
                        TextField("Tags (comma separated)", text: $tags)
                        Button("Save Idea") {
                            saveIdea()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canSaveIdea)
                    }
                }
            }
        }
        .padding()
        .background(Color.clear)
        .navigationTitle("Ideas")
    }

    private func saveIdea() {
        let parsedTags = tags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let existingIdea = editingIdea
        store.saveIdea(
            IdeaCard(
                id: existingIdea?.id ?? UUID().uuidString,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                detail: detail.trimmingCharacters(in: .whitespacesAndNewlines),
                tags: parsedTags,
                teamCode: store.teamCode ?? "",
                createdBy: existingIdea?.createdBy ?? store.user?.email,
                implemented: existingIdea?.implemented ?? false,
                completedAt: existingIdea?.completedAt,
                likedBy: existingIdea?.likedBy ?? []
            )
        )
        resetIdeaForm()
        isShowingAddIdea = false
    }

    private func beginEditing(_ idea: IdeaCard) {
        editingIdea = idea
        title = idea.title
        detail = idea.detail
        tags = idea.tags.joined(separator: ", ")
        isShowingAddIdea = true
    }

    private func isIdeaLiked(_ idea: IdeaCard) -> Bool {
        let userID = currentUserID
        return !userID.isEmpty && idea.likedBy.contains(userID)
    }

    private func toggleLike(for idea: IdeaCard) {
        let userID = currentUserID
        guard !userID.isEmpty else { return }

        var updatedIdea = idea
        if updatedIdea.likedBy.contains(userID) {
            updatedIdea.likedBy.removeAll { $0 == userID }
        } else {
            updatedIdea.likedBy.append(userID)
        }
        store.saveIdea(updatedIdea)
    }

    private func toggleImplemented(_ idea: IdeaCard) {
        guard canEditIdeas else { return }
        var updatedIdea = idea
        if updatedIdea.implemented {
            updatedIdea.implemented = false
            updatedIdea.completedAt = nil
        } else {
            updatedIdea.implemented = true
            updatedIdea.completedAt = Date()
        }
        store.saveIdea(updatedIdea)
    }

    @ViewBuilder
    private func ideaRow(_ idea: IdeaCard) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(idea.title).font(.headline)
                    if idea.implemented {
                        Text("Implemented")
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.25), in: Capsule())
                    }
                }
                if !idea.detail.isEmpty {
                    Text(idea.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if !idea.tags.isEmpty {
                    Text(idea.tags.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let completedAt = idea.completedAt {
                    Text("Completed: \(completedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                beginEditing(idea)
            }

            if canEditIdeas {
                Button {
                    toggleImplemented(idea)
                } label: {
                    Image(systemName: idea.implemented ? "checkmark.circle.fill" : "checkmark.circle")
                        .foregroundStyle(idea.implemented ? Color.green : Color.secondary)
                }
                .buttonStyle(.borderless)
                .help(idea.implemented ? "Mark Not Implemented" : "Mark Implemented")
            }

            Button {
                toggleLike(for: idea)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isIdeaLiked(idea) ? "heart.fill" : "heart")
                    Text("\(idea.likedBy.count)")
                }
                .foregroundStyle(isIdeaLiked(idea) ? Color.red : Color.blue)
            }
            .buttonStyle(.borderless)
            .help(isIdeaLiked(idea) ? "Unlike" : "Like")
        }
        .contextMenu {
            Button("Edit") {
                beginEditing(idea)
            }
            if canEditIdeas {
                Button(idea.implemented ? "Mark Not Implemented" : "Mark Implemented") {
                    toggleImplemented(idea)
                }
            }
            Button("Delete", role: .destructive) {
                store.deleteIdea(idea)
            }
        }
    }

    private func resetIdeaForm() {
        editingIdea = nil
        title = ""
        detail = ""
        tags = ""
    }
}

private struct MacCustomizeView: View {
    private enum FreshserviceImportKind: String, CaseIterable, Identifiable {
        case assets
        case tickets

        var id: String { rawValue }

        var title: String {
            switch self {
            case .assets: return "Assets"
            case .tickets: return "Tickets"
            }
        }
    }

    private enum FreshserviceDestination: String, CaseIterable, Identifiable {
        case assetsTab
        case ticketsTab

        var id: String { rawValue }

        var title: String {
            switch self {
            case .assetsTab: return "Assets Tab"
            case .ticketsTab: return "Tickets Tab"
            }
        }
    }

    @EnvironmentObject private var store: ProdConnectStore
    @State private var newLocation = ""
    @State private var newRoom = ""
    @State private var newTicketCategory = ""
    @State private var newTicketSubcategory = ""
    @State private var gearSheetLink = ""
    @State private var audioPatchSheetLink = ""
    @State private var videoPatchSheetLink = ""
    @State private var lightingPatchSheetLink = ""
    @State private var isImporting = false
    @State private var resultMessage = ""
    @State private var pendingResetAction: ResetAction?
    @State private var freshserviceAPIURL = ""
    @State private var freshserviceAPIKey = ""
    @State private var freshserviceEnabled = false
    @State private var managedByGroupFilter = ""
    @State private var managedByGroupOptions: [String] = []
    @State private var freshserviceSyncMode: ProdConnectStore.FreshserviceSyncMode = .pull
    @State private var selectedImportKind: FreshserviceImportKind = .assets
    @State private var selectedDestination: FreshserviceDestination = .assetsTab
    @State private var isSavingFreshserviceIntegration = false
    @State private var isTestingFreshserviceIntegration = false
    @State private var isImportingFreshserviceData = false
    @State private var isLoadingManagedByGroups = false
    @State private var freshserviceStatusMessage = ""
    @State private var externalTicketFormEnabled = false
    @State private var externalTicketFormAccessKey = ""
    @State private var isSavingExternalTicketForm = false
    @State private var externalTicketStatusMessage = ""
    @State private var bulkOperationMessage = ""
    @State private var isBulkOperationInProgress = false

    private enum ResetAction: String, Identifiable {
        case deleteAllGear
        case deleteAudioPatchsheet
        case deleteVideoPatchsheet
        case deleteLightingPatchsheet

        var id: String { rawValue }

        var title: String {
            switch self {
            case .deleteAllGear: return "Delete All Assets?"
            case .deleteAudioPatchsheet: return "Delete Audio Patchsheet?"
            case .deleteVideoPatchsheet: return "Delete Video Patchsheet?"
            case .deleteLightingPatchsheet: return "Delete Lighting Patchsheet?"
            }
        }

        var message: String {
            switch self {
            case .deleteAllGear:
                return "Are you sure you want to delete all asset items? This cannot be undone."
            case .deleteAudioPatchsheet:
                return "Are you sure you want to delete all audio patches? This cannot be undone."
            case .deleteVideoPatchsheet:
                return "Are you sure you want to delete all video patches? This cannot be undone."
            case .deleteLightingPatchsheet:
                return "Are you sure you want to delete all lighting patches? This cannot be undone."
            }
        }
    }

    private var canManageExternalTicketForm: Bool {
        (store.user?.isAdmin == true || store.user?.isOwner == true)
            && (store.user?.hasTicketingFeatures == true)
    }

    private var canImportTickets: Bool {
        store.user?.hasTicketingFeatures == true
    }

    private var availableImportKinds: [FreshserviceImportKind] {
        canImportTickets ? FreshserviceImportKind.allCases : [.assets]
    }

    private var availableDestinations: [FreshserviceDestination] {
        canImportTickets ? FreshserviceDestination.allCases : [.assetsTab]
    }

    private var availableManagedByGroupOptions: [String] {
        let trimmedFilter = managedByGroupFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let merged = trimmedFilter.isEmpty ? managedByGroupOptions : managedByGroupOptions + [trimmedFilter]
        return Array(Set(merged)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var externalTicketFormURLString: String {
        let teamCode = (store.teamCode ?? store.user?.teamCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let accessKey = externalTicketFormAccessKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard externalTicketFormEnabled, !teamCode.isEmpty, !accessKey.isEmpty else { return "" }
        let slug = externalTicketFormSlug(from: store.organizationName)
        return "https://prodconnect-1ea3a.web.app/support/\(slug)?team=\(teamCode)&key=\(accessKey)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 20) {
                    GroupBox("Campuses") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                TextField("Add campus", text: $newLocation)
                                Button("Save") {
                                    let trimmed = newLocation.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !trimmed.isEmpty else { return }
                                    store.saveLocation(trimmed)
                                    newLocation = ""
                                }
                            }
                            Button {
                                syncGearLocationsToCampuses()
                            } label: {
                                Label("Copy Locations from Assets", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .buttonStyle(.bordered)

                            List {
                                ForEach(store.locations.sorted(), id: \.self) { location in
                                    HStack {
                                        Text(location)
                                        Spacer()
                                        Button(role: .destructive) {
                                            store.deleteLocation(location)
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .frame(minHeight: 220)
                            .scrollContentBackground(.hidden)
                        }
                    }

                    GroupBox("Rooms") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                TextField("Add room", text: $newRoom)
                                Button("Save") {
                                    let trimmed = newRoom.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !trimmed.isEmpty else { return }
                                    store.saveRoom(trimmed)
                                    newRoom = ""
                                }
                            }
                            List {
                                ForEach(store.rooms.sorted(), id: \.self) { room in
                                    HStack {
                                        Text(room)
                                        Spacer()
                                        Button(role: .destructive) {
                                            store.deleteRoom(room)
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .frame(minHeight: 220)
                            .scrollContentBackground(.hidden)
                        }
                    }
                }

                HStack(alignment: .top, spacing: 20) {
                    GroupBox("Ticket Categories") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                TextField("Add category", text: $newTicketCategory)
                                Button("Save") {
                                    let trimmed = newTicketCategory.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !trimmed.isEmpty else { return }
                                    store.saveTicketCategory(trimmed)
                                    newTicketCategory = ""
                                }
                            }
                            List {
                                ForEach(store.ticketCategories.sorted(), id: \.self) { category in
                                    HStack {
                                        Text(category)
                                        Spacer()
                                        Button(role: .destructive) {
                                            store.deleteTicketCategory(category)
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .frame(minHeight: 220)
                            .scrollContentBackground(.hidden)
                        }
                    }

                    GroupBox("Ticket Subcategories") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                TextField("Add subcategory", text: $newTicketSubcategory)
                                Button("Save") {
                                    let trimmed = newTicketSubcategory.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !trimmed.isEmpty else { return }
                                    store.saveTicketSubcategory(trimmed)
                                    newTicketSubcategory = ""
                                }
                            }
                            List {
                                ForEach(store.ticketSubcategories.sorted(), id: \.self) { subcategory in
                                    HStack {
                                        Text(subcategory)
                                        Spacer()
                                        Button(role: .destructive) {
                                            store.deleteTicketSubcategory(subcategory)
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .frame(minHeight: 220)
                            .scrollContentBackground(.hidden)
                        }
                    }
                }

                GroupBox("Import from Google Sheets") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Paste your Google Sheet share link and click Import.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        importRow(title: "Assets sheet link", text: $gearSheetLink) {
                            importGearData()
                        }
                        importRow(title: "Audio patchsheet link", text: $audioPatchSheetLink) {
                            importPatchData(category: "Audio", link: audioPatchSheetLink)
                        }
                        importRow(title: "Video patchsheet link", text: $videoPatchSheetLink) {
                            importPatchData(category: "Video", link: videoPatchSheetLink)
                        }
                        importRow(title: "Lighting patchsheet link", text: $lightingPatchSheetLink) {
                            importPatchData(category: "Lighting", link: lightingPatchSheetLink)
                        }
                    }
                }

                if canManageIntegrations {
                    GroupBox("Integrations") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Connect Freshservice API")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Toggle("Enable Freshservice", isOn: $freshserviceEnabled)

                            Picker("Import Data", selection: $selectedImportKind) {
                                ForEach(availableImportKinds) { kind in
                                    Text(kind.title).tag(kind)
                                }
                            }

                            Picker("Destination", selection: $selectedDestination) {
                                ForEach(availableDestinations) { destination in
                                    Text(destination.title).tag(destination)
                                }
                            }

                            Picker("Sync Mode", selection: $freshserviceSyncMode) {
                                ForEach(ProdConnectStore.FreshserviceSyncMode.allCases, id: \.self) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }

                            TextField("Freshservice URL", text: $freshserviceAPIURL)
                                .textFieldStyle(.roundedBorder)

                            SecureField("Freshservice API Key", text: $freshserviceAPIKey)
                                .textFieldStyle(.roundedBorder)

                            if selectedImportKind == .assets {
                                Picker("Managed By Group", selection: $managedByGroupFilter) {
                                    Text("All Groups").tag("")
                                    ForEach(availableManagedByGroupOptions, id: \.self) { option in
                                        Text(option).tag(option)
                                    }
                                }

                                Button {
                                    refreshManagedByGroupOptions()
                                } label: {
                                    if isLoadingManagedByGroups {
                                        ProgressView()
                                    } else {
                                        Text("Refresh Groups")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(
                                    isSavingFreshserviceIntegration
                                    || isTestingFreshserviceIntegration
                                    || isImportingFreshserviceData
                                    || isLoadingManagedByGroups
                                    || freshserviceAPIURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    || freshserviceAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                )
                            }

                            HStack(spacing: 12) {
                                Button {
                                    saveFreshserviceIntegration()
                                } label: {
                                    if isSavingFreshserviceIntegration {
                                        ProgressView()
                                    } else {
                                        Text("Save Connection")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(isSavingFreshserviceIntegration || isTestingFreshserviceIntegration || isImportingFreshserviceData)

                                Button {
                                    testFreshserviceConnection()
                                } label: {
                                    if isTestingFreshserviceIntegration {
                                        ProgressView()
                                    } else {
                                        Text("Test Connection")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(
                                    isSavingFreshserviceIntegration
                                    || isTestingFreshserviceIntegration
                                    || isImportingFreshserviceData
                                    || freshserviceAPIURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    || freshserviceAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                )

                                Button {
                                    importFreshserviceData()
                                } label: {
                                    if isImportingFreshserviceData {
                                        ProgressView()
                                    } else {
                                        Text("Import")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(
                                    isSavingFreshserviceIntegration
                                    || isTestingFreshserviceIntegration
                                    || isImportingFreshserviceData
                                    || freshserviceAPIURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    || freshserviceAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                )
                            }

                            if !freshserviceStatusMessage.isEmpty {
                                Text(freshserviceStatusMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if canManageExternalTicketForm {
                    GroupBox("External Ticket Form") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Enable External Form", isOn: $externalTicketFormEnabled)

                            if !externalTicketFormURLString.isEmpty {
                                TextField("Public Link", text: .constant(externalTicketFormURLString))
                                    .textFieldStyle(.roundedBorder)

                                Button("Copy Public Link") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(externalTicketFormURLString, forType: .string)
                                    externalTicketStatusMessage = "External ticket form link copied."
                                }
                                .buttonStyle(.bordered)
                            }

                            Button {
                                saveCustomizeExternalTicketForm()
                            } label: {
                                if isSavingExternalTicketForm {
                                    ProgressView()
                                } else {
                                    Text("Save External Form")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isSavingExternalTicketForm)

                            if !externalTicketStatusMessage.isEmpty {
                                Text(externalTicketStatusMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                GroupBox("Reset") {
                    VStack(alignment: .leading, spacing: 10) {
                        resetButton("Delete All Assets", action: .deleteAllGear)
                        resetButton("Delete Audio Patchsheet", action: .deleteAudioPatchsheet)
                        resetButton("Delete Video Patchsheet", action: .deleteVideoPatchsheet)
                        resetButton("Delete Lighting Patchsheet", action: .deleteLightingPatchsheet)
                    }
                }

                if !resultMessage.isEmpty {
                    Text(resultMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color.clear)
        .navigationTitle("Customize")
        .disabled(isBulkOperationInProgress)
        .onAppear(perform: loadFreshserviceIntegrationState)
        .onChange(of: store.freshserviceIntegration) { _, _ in
            loadFreshserviceIntegrationState()
        }
        .onChange(of: store.externalTicketFormIntegration) { _, _ in
            loadExternalTicketFormCustomizeState()
        }
        .alert(item: $pendingResetAction) { action in
            Alert(
                title: Text(action.title),
                message: Text(action.message),
                primaryButton: .destructive(Text("Delete")) {
                    performReset(action)
                },
                secondaryButton: .cancel()
            )
        }
        .overlay {
            if isBulkOperationInProgress {
                ZStack {
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()

                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text(bulkOperationMessage)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                    }
                    .padding(20)
                    .frame(maxWidth: 320)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 10)
                }
            }
        }
    }

    private var canManageIntegrations: Bool {
        let isPrivilegedUser = store.user?.isAdmin == true || store.user?.isOwner == true
        return isPrivilegedUser && (store.user?.hasChatAndTrainingFeatures ?? false)
    }

    @ViewBuilder
    private func importRow(title: String, text: Binding<String>, action: @escaping () -> Void) -> some View {
        HStack {
            TextField(title, text: text)
            Button("Import", action: action)
                .buttonStyle(.borderedProminent)
                .disabled(text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isImporting)
        }
    }

    @ViewBuilder
    private func resetButton(_ title: String, action: ResetAction) -> some View {
        Button(role: .destructive) {
            pendingResetAction = action
        } label: {
            Label(title, systemImage: "trash.fill")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.borderless)
    }

    private func performReset(_ action: ResetAction) {
        beginBulkOperation("Deleting, please wait")
        switch action {
        case .deleteAllGear:
            store.deleteAllGear { result in
                finishReset(result, successMessage: "All assets have been deleted.")
            }
        case .deleteAudioPatchsheet:
            store.deletePatchesByCategory("Audio") { result in
                finishReset(result, successMessage: "Audio patchsheet has been deleted.")
            }
        case .deleteVideoPatchsheet:
            store.deletePatchesByCategory("Video") { result in
                finishReset(result, successMessage: "Video patchsheet has been deleted.")
            }
        case .deleteLightingPatchsheet:
            store.deletePatchesByCategory("Lighting") { result in
                finishReset(result, successMessage: "Lighting patchsheet has been deleted.")
            }
        }
    }

    private func syncGearLocationsToCampuses() {
        var existing = Set(store.locations.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        let source = Array(Set(store.gear.map { $0.location.trimmingCharacters(in: .whitespacesAndNewlines) }))
            .filter { !$0.isEmpty }
            .sorted()

        var added = 0
        for location in source {
            let key = location.lowercased()
            if !existing.contains(key) {
                store.saveLocation(location)
                existing.insert(key)
                added += 1
            }
        }

        resultMessage = added == 0 ? "No new locations to copy from Assets." : "Added \(added) location(s) from Assets."
    }

    private func importGearData() {
        isImporting = true
        let csvURL = convertGoogleSheetLinkToCSV(gearSheetLink)

        URLSession.shared.dataTask(with: csvURL) { data, _, error in
            guard let data, error == nil else {
                DispatchQueue.main.async {
                    isImporting = false
                    resultMessage = "Failed to fetch sheet: \(error?.localizedDescription ?? "Unknown error")"
                }
                return
            }

            guard let csvString = String(data: data, encoding: .utf8) else {
                DispatchQueue.main.async {
                    isImporting = false
                    resultMessage = "Failed to decode CSV response."
                }
                return
            }

            let gearItems = parseGearCSV(csvString)
            DispatchQueue.main.async {
                beginBulkOperation("Importing, please wait")
                store.replaceAllGear(gearItems) { result in
                    endBulkOperation()
                    isImporting = false
                    switch result {
                    case .success:
                        gearSheetLink = ""
                        resultMessage = "Imported \(gearItems.count) asset items."
                    case .failure(let error):
                        resultMessage = "Import failed: \(error.localizedDescription)"
                    }
                }
            }
        }.resume()
    }

    private func importPatchData(category: String, link: String) {
        isImporting = true
        let csvURL = convertGoogleSheetLinkToCSV(link)

        URLSession.shared.dataTask(with: csvURL) { data, _, error in
            guard let data, error == nil else {
                DispatchQueue.main.async {
                    isImporting = false
                    resultMessage = "Failed to fetch sheet: \(error?.localizedDescription ?? "Unknown error")"
                }
                return
            }

            guard let csvString = String(data: data, encoding: .utf8) else {
                DispatchQueue.main.async {
                    isImporting = false
                    resultMessage = "Failed to decode CSV response."
                }
                return
            }

            let patchRows = parsePatchCSV(csvString).map { row in
                var updated = row
                updated.category = category
                return updated
            }

            DispatchQueue.main.async {
                beginBulkOperation("Importing, please wait")
                store.replaceAllPatch(patchRows) { result in
                    endBulkOperation()
                    isImporting = false
                    switch result {
                    case .success:
                        switch category {
                        case "Audio":
                            audioPatchSheetLink = ""
                        case "Video":
                            videoPatchSheetLink = ""
                        case "Lighting":
                            lightingPatchSheetLink = ""
                        default:
                            break
                        }
                        resultMessage = "Imported \(patchRows.count) \(category) patches."
                    case .failure(let error):
                        resultMessage = "Import failed: \(error.localizedDescription)"
                    }
                }
            }
        }.resume()
    }

    private func beginBulkOperation(_ message: String) {
        bulkOperationMessage = message
        isBulkOperationInProgress = true
    }

    private func endBulkOperation() {
        isBulkOperationInProgress = false
        bulkOperationMessage = ""
    }

    private func finishReset(_ result: Result<Void, Error>, successMessage: String) {
        endBulkOperation()
        switch result {
        case .success:
            resultMessage = successMessage
        case .failure(let error):
            resultMessage = "Delete failed: \(error.localizedDescription)"
        }
    }

    private func loadFreshserviceIntegrationState() {
        let settings = store.freshserviceIntegration
        freshserviceAPIURL = settings.apiURL
        freshserviceAPIKey = settings.apiKey
        freshserviceEnabled = settings.isEnabled
        managedByGroupFilter = settings.managedByGroup
        managedByGroupOptions = settings.managedByGroupOptions
        freshserviceSyncMode = settings.syncMode
        if !canImportTickets, selectedImportKind == .tickets {
            selectedImportKind = .assets
        }
        if !availableDestinations.contains(selectedDestination) {
            selectedDestination = availableDestinations.first ?? .assetsTab
        }
        loadExternalTicketFormCustomizeState()
    }

    private func loadExternalTicketFormCustomizeState() {
        let settings = store.externalTicketFormIntegration
        externalTicketFormEnabled = settings.isEnabled
        externalTicketFormAccessKey = settings.accessKey
        if externalTicketFormAccessKey.isEmpty, canManageExternalTicketForm {
            externalTicketFormAccessKey = store.generateExternalTicketAccessKey()
        }
    }

    private func saveCustomizeExternalTicketForm() {
        isSavingExternalTicketForm = true
        externalTicketStatusMessage = ""
        store.saveExternalTicketFormIntegration(
            isEnabled: externalTicketFormEnabled,
            accessKey: externalTicketFormAccessKey
        ) { result in
            isSavingExternalTicketForm = false
            switch result {
            case .success(let settings):
                externalTicketFormEnabled = settings.isEnabled
                externalTicketFormAccessKey = settings.accessKey
                externalTicketStatusMessage = settings.isEnabled ?
                    "External ticket form is live." :
                    "External ticket form is saved but disabled."
            case .failure(let error):
                externalTicketStatusMessage = "Save failed: \(error.localizedDescription)"
            }
        }
    }

    private func saveFreshserviceIntegration() {
        isSavingFreshserviceIntegration = true
        freshserviceStatusMessage = ""
        store.saveFreshserviceIntegration(
            apiURL: freshserviceAPIURL,
            apiKey: freshserviceAPIKey,
            managedByGroup: managedByGroupFilter,
            managedByGroupOptions: managedByGroupOptions,
            syncMode: freshserviceSyncMode,
            isEnabled: freshserviceEnabled
        ) { result in
            isSavingFreshserviceIntegration = false
            switch result {
            case .success:
                freshserviceStatusMessage = "Freshservice connection saved."
            case .failure(let error):
                freshserviceStatusMessage = "Save failed: \(error.localizedDescription)"
            }
        }
    }

    private func testFreshserviceConnection() {
        let trimmedURL = freshserviceAPIURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = freshserviceAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty, !trimmedKey.isEmpty else {
            freshserviceStatusMessage = "Enter both the Freshservice URL and API key."
            return
        }

        isTestingFreshserviceIntegration = true
        freshserviceStatusMessage = ""
        let assetCompletion: (Result<([[String: Any]], Bool), Error>) -> Void = { result in
            DispatchQueue.main.async {
                isTestingFreshserviceIntegration = false
                switch result {
                case .success(let payload):
                    let (items, reachedCap) = payload
                    let filteredItems = filteredFreshserviceItems(items)
                    if reachedCap {
                        freshserviceStatusMessage = "Connected to Freshservice. Found at least \(filteredItems.count) assets (20,000 asset cap reached)."
                    } else {
                        freshserviceStatusMessage = "Connected to Freshservice. Found \(filteredItems.count) assets."
                    }
                case .failure(let error):
                    freshserviceStatusMessage = "Connection failed: \(error.localizedDescription)"
                }
            }
        }
        let ticketCompletion: (Result<([[String: Any]], Bool), Error>) -> Void = { result in
            DispatchQueue.main.async {
                isTestingFreshserviceIntegration = false
                switch result {
                case .success(let payload):
                    let (items, reachedCap) = payload
                    if reachedCap {
                        freshserviceStatusMessage = "Connected to Freshservice. Found at least \(items.count) tickets (20,000 ticket cap reached)."
                    } else {
                        freshserviceStatusMessage = "Connected to Freshservice. Found \(items.count) tickets."
                    }
                case .failure(let error):
                    freshserviceStatusMessage = "Connection failed: \(error.localizedDescription)"
                }
            }
        }

        switch selectedImportKind {
        case .assets:
            MacFreshserviceAPI.fetchAllAssetsWithAPIKey(apiKey: trimmedKey, apiUrl: trimmedURL, maxPages: 20, completion: assetCompletion)
        case .tickets:
            MacFreshserviceAPI.fetchAllTicketsWithAPIKey(apiKey: trimmedKey, apiUrl: trimmedURL, completion: ticketCompletion)
        }
    }

    private func importFreshserviceData() {
        let trimmedURL = freshserviceAPIURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = freshserviceAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty, !trimmedKey.isEmpty else {
            freshserviceStatusMessage = "Enter both the Freshservice URL and API key."
            return
        }

        isImportingFreshserviceData = true
        freshserviceStatusMessage = ""

        let assetCompletion: (Result<([[String: Any]], Bool), Error>) -> Void = { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let payload):
                    let (items, reachedCap) = payload
                    let filteredItems = filteredFreshserviceItems(items)
                    switch selectedDestination {
                    case .assetsTab:
                        let imported = filteredItems.compactMap { mapFreshserviceAsset($0) }
                        store.upsertGear(imported) { saveResult in
                            isImportingFreshserviceData = false
                            switch saveResult {
                            case .success:
                                freshserviceStatusMessage = reachedCap
                                    ? "Imported \(imported.count) Freshservice \(selectedImportKind.rawValue) into Assets and Firebase. 20,000 asset cap reached."
                                    : "Imported \(imported.count) Freshservice \(selectedImportKind.rawValue) into Assets and Firebase."
                            case .failure(let error):
                                freshserviceStatusMessage = "Import failed while saving assets: \(error.localizedDescription)"
                            }
                        }
                    case .ticketsTab:
                        let imported = filteredItems.compactMap { mapFreshserviceTicket($0) }
                        store.upsertTickets(imported) { saveResult in
                            isImportingFreshserviceData = false
                            switch saveResult {
                            case .success:
                                freshserviceStatusMessage = reachedCap
                                    ? "Imported \(imported.count) Freshservice \(selectedImportKind.rawValue) into Tickets and Firebase. 20,000 asset cap reached."
                                    : "Imported \(imported.count) Freshservice \(selectedImportKind.rawValue) into Tickets and Firebase."
                            case .failure(let error):
                                freshserviceStatusMessage = "Import failed while saving tickets: \(error.localizedDescription)"
                            }
                        }
                    }
                case .failure(let error):
                    isImportingFreshserviceData = false
                    freshserviceStatusMessage = "Import failed: \(error.localizedDescription)"
                }
            }
        }

        let ticketCompletion: (Result<([[String: Any]], Bool), Error>) -> Void = { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let payload):
                    let (items, reachedCap) = payload
                    switch selectedDestination {
                    case .assetsTab:
                        let imported = items.compactMap { mapFreshserviceAsset($0) }
                        store.upsertGear(imported) { saveResult in
                            isImportingFreshserviceData = false
                            switch saveResult {
                            case .success:
                                freshserviceStatusMessage = reachedCap
                                    ? "Imported \(imported.count) Freshservice tickets into Assets and Firebase. 20,000 ticket cap reached."
                                    : "Imported \(imported.count) Freshservice tickets into Assets and Firebase."
                            case .failure(let error):
                                freshserviceStatusMessage = "Import failed while saving assets: \(error.localizedDescription)"
                            }
                        }
                    case .ticketsTab:
                        let imported = items.compactMap { mapFreshserviceTicket($0) }
                        store.upsertTickets(imported) { saveResult in
                            isImportingFreshserviceData = false
                            switch saveResult {
                            case .success:
                                freshserviceStatusMessage = reachedCap
                                    ? "Imported \(imported.count) Freshservice tickets into Tickets and Firebase. 20,000 ticket cap reached."
                                    : "Imported \(imported.count) Freshservice tickets into Tickets and Firebase."
                            case .failure(let error):
                                freshserviceStatusMessage = "Import failed while saving tickets: \(error.localizedDescription)"
                            }
                        }
                    }
                case .failure(let error):
                    isImportingFreshserviceData = false
                    freshserviceStatusMessage = "Import failed: \(error.localizedDescription)"
                }
            }
        }

        switch selectedImportKind {
        case .assets:
            MacFreshserviceAPI.fetchAllAssetsWithAPIKey(apiKey: trimmedKey, apiUrl: trimmedURL, completion: assetCompletion)
        case .tickets:
            MacFreshserviceAPI.fetchAllTicketsWithAPIKey(apiKey: trimmedKey, apiUrl: trimmedURL, completion: ticketCompletion)
        }
    }

    private func filteredFreshserviceItems(_ items: [[String: Any]]) -> [[String: Any]] {
        switch selectedImportKind {
        case .assets:
            let filter = managedByGroupFilter.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !filter.isEmpty else { return items }
            return items.filter { matchesManagedByGroup($0, filter: filter) }
        case .tickets:
            return items.filter { shouldIncludeFreshserviceTicket($0) }
        }
    }

    private func refreshManagedByGroupOptions() {
        let trimmedURL = freshserviceAPIURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = freshserviceAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty, !trimmedKey.isEmpty else {
            freshserviceStatusMessage = "Enter both the Freshservice URL and API key."
            return
        }

        isLoadingManagedByGroups = true
        MacFreshserviceAPI.fetchAllAssetsWithAPIKey(apiKey: trimmedKey, apiUrl: trimmedURL) { result in
            DispatchQueue.main.async {
                isLoadingManagedByGroups = false
                switch result {
                case .success(let payload):
                    let (assets, reachedCap) = payload
                    managedByGroupOptions = extractManagedByGroupOptions(from: assets)
                    store.saveFreshserviceIntegration(
                        apiURL: freshserviceAPIURL,
                        apiKey: freshserviceAPIKey,
                        managedByGroup: managedByGroupFilter,
                        managedByGroupOptions: managedByGroupOptions,
                        syncMode: freshserviceSyncMode,
                        isEnabled: freshserviceEnabled
                    )
                    if managedByGroupOptions.isEmpty {
                        freshserviceStatusMessage = "Connected to Freshservice. No managed-by groups were found."
                    } else if reachedCap {
                        freshserviceStatusMessage = "Loaded \(managedByGroupOptions.count) managed-by groups from the first 20,000 assets."
                    } else {
                        freshserviceStatusMessage = "Loaded \(managedByGroupOptions.count) managed-by groups from Freshservice."
                    }
                case .failure(let error):
                    freshserviceStatusMessage = "Failed to load managed-by groups: \(error.localizedDescription)"
                }
            }
        }
    }

    private func extractManagedByGroupOptions(from assets: [[String: Any]]) -> [String] {
        let values = assets.compactMap { asset in
            managedByGroupName(from: asset)
        }
        return Array(Set(values)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func managedByGroupName(from asset: [String: Any]) -> String? {
        let candidates: [String?] = [
            nestedStringValue(asset["managed_by_group"], key: "name"),
            nestedStringValue(asset["managed_by"], key: "name"),
            nestedStringValue(asset["group"], key: "name"),
            stringValue(asset["managed_by_group"]),
            stringValue(asset["managed_by"]),
            stringValue(asset["group_name"])
        ]

        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }

    private func mapFreshserviceAsset(_ asset: [String: Any]) -> GearItem? {
        let freshserviceID = stringValue(asset["id"]) ?? stringValue(asset["display_id"]) ?? stringValue(asset["asset_tag"])
        let name = stringValue(asset["name"])
            ?? stringValue(asset["display_name"])
            ?? nestedStringValue(asset["product"], key: "name")
            ?? "Freshservice Asset"

        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        var item = GearItem(
            id: freshserviceID.map { "freshservice-\($0)" } ?? UUID().uuidString,
            name: name,
            category: nestedStringValue(asset["asset_type"], key: "name")
                ?? nestedStringValue(asset["product"], key: "name")
                ?? stringValue(asset["asset_type_name"])
                ?? "Freshservice",
            status: mappedStatus(from: asset),
            teamCode: store.teamCode ?? "",
            location: nestedStringValue(asset["location"], key: "name")
                ?? nestedStringValue(asset["department"], key: "name")
                ?? "",
            serialNumber: stringValue(asset["serial_number"]) ?? "",
            campus: nestedStringValue(asset["department"], key: "name") ?? "",
            assetId: stringValue(asset["asset_tag"]) ?? stringValue(asset["display_id"]) ?? "",
            maintenanceNotes: stringValue(asset["description"]) ?? "",
            createdBy: "Freshservice Import"
        )

        item.purchasedFrom = nestedStringValue(asset["vendor"], key: "name") ?? ""
        item.purchaseDate = parsedDate(from: asset["purchase_date"]) ?? parsedDate(from: asset["created_at"])
        item.installDate = parsedDate(from: asset["created_at"])
        item.cost = doubleValue(asset["cost"]) ?? doubleValue(asset["salvage_price"])
        return item
    }

    private func mapFreshserviceTicket(_ ticket: [String: Any]) -> SupportTicket? {
        let ticketID = stringValue(ticket["id"]) ?? stringValue(ticket["display_id"])
        let title = stringValue(ticket["subject"]) ?? stringValue(ticket["name"]) ?? "Freshservice Ticket"
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let requesterName = nestedStringValue(ticket["requester"], key: "name")
            ?? nestedStringValue(ticket["requester"], key: "email")
            ?? stringValue(ticket["requester_name"])
            ?? stringValue(ticket["email"])

        let campusValue =
            nestedStringValue(ticket["department"], key: "name")
            ?? nestedStringValue(ticket["group"], key: "name")
            ?? nestedStringValue(ticket["custom_fields"], key: "department")
            ?? nestedStringValue(ticket["custom_fields"], key: "campus")
            ?? stringValue(ticket["department_name"])
            ?? stringValue(ticket["group_name"])
            ?? stringValue(ticket["campus"])

        let roomValue =
            nestedStringValue(ticket["location"], key: "name")
            ?? nestedStringValue(ticket["custom_fields"], key: "location")
            ?? nestedStringValue(ticket["custom_fields"], key: "room")
            ?? stringValue(ticket["location_name"])
            ?? stringValue(ticket["room"])

        let assignedAgentIDCandidates = [
            stringValue(ticket["assigned_agent_id"]),
            stringValue(ticket["responder_id"]),
            stringValue(ticket["agent_id"]),
            nestedStringValue(ticket["responder"], key: "id"),
            nestedStringValue(ticket["agent"], key: "id"),
            nestedStringValue(ticket["assigned_to"], key: "id")
        ]
        let assignedAgentID = assignedAgentIDCandidates.compactMap { $0 }.first

        let assignedAgentNameCandidates = [
            nestedStringValue(ticket["responder"], key: "name"),
            nestedStringValue(ticket["responder"], key: "email"),
            nestedStringValue(ticket["agent"], key: "name"),
            nestedStringValue(ticket["agent"], key: "email"),
            nestedStringValue(ticket["assigned_to"], key: "name"),
            nestedStringValue(ticket["assigned_to"], key: "email"),
            stringValue(ticket["responder_email"]),
            stringValue(ticket["agent_email"]),
            stringValue(ticket["responder_name"]),
            stringValue(ticket["agent_name"]),
            stringValue(ticket["assigned_agent_name"])
        ]
        let assignedAgentName = assignedAgentNameCandidates.compactMap { $0 }.first ?? assignedAgentID.map { "Agent \($0)" }

        var item = SupportTicket(
            id: ticketID.map { "freshservice-ticket-\($0)" } ?? UUID().uuidString,
            title: title,
            detail: stringValue(ticket["description_text"]) ?? stringValue(ticket["description"]) ?? "",
            teamCode: store.teamCode ?? "",
            campus: campusValue ?? "",
            room: roomValue ?? "",
            status: mappedTicketStatus(from: ticket),
            createdBy: requesterName
        )
        item.createdAt = parsedDate(from: ticket["created_at"]) ?? Date()
        item.updatedAt = parsedDate(from: ticket["updated_at"]) ?? item.createdAt
        item.assignedAgentID = assignedAgentID
        item.assignedAgentName = assignedAgentName
        item.lastUpdatedBy = assignedAgentName
        if let attachment = firstFreshserviceAttachment(from: ticket) {
            item.attachmentURL = attachment.url
            item.attachmentName = attachment.name
            item.attachmentKind = attachment.kind
        }
        return item
    }

    private func mappedStatus(from asset: [String: Any]) -> GearItem.GearStatus {
        let raw = (
            nestedStringValue(asset["state"], key: "name")
            ?? nestedStringValue(asset["ci_status"], key: "name")
            ?? stringValue(asset["usage_type"])
            ?? stringValue(asset["status"])
            ?? ""
        ).lowercased()

        if raw.contains("repair") || raw.contains("maint") { return .needsRepair }
        if raw.contains("retired") { return .retired }
        if raw.contains("missing") || raw.contains("lost") { return .missing }
        if raw.contains("use") || raw.contains("deployed") || raw.contains("assigned") || raw.contains("checkout") { return .inUse }
        return .available
    }

    private func mappedTicketStatus(from ticket: [String: Any]) -> TicketStatus {
        let statusCode = stringValue(ticket["status"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let raw = (
            nestedStringValue(ticket["status"], key: "name")
            ?? stringValue(ticket["status_name"])
            ?? ""
        ).lowercased()

        if ["4", "5"].contains(statusCode) { return .resolved }
        if ["3", "6", "7"].contains(statusCode) { return .inProgress }
        if statusCode == "2" { return .open }
        if statusCode == "1" { return .new }
        if raw.contains("resolve") || raw.contains("closed") { return .resolved }
        if raw.contains("progress") || raw.contains("pending") || raw.contains("awaiting") || raw.contains("waiting") { return .inProgress }
        if raw.contains("open") { return .open }
        return .new
    }

    private func firstFreshserviceAttachment(from ticket: [String: Any]) -> (url: String, name: String?, kind: TicketAttachmentKind?)? {
        guard let attachments = ticket["attachments"] as? [[String: Any]], let first = attachments.first else {
            return nil
        }

        guard
            let url = stringValue(first["attachment_url"])
                ?? stringValue(first["url"])
                ?? stringValue(first["content_url"])
        else {
            return nil
        }

        let name = stringValue(first["name"]) ?? stringValue(first["file_name"])
        let contentType = (stringValue(first["content_type"]) ?? "").lowercased()
        let kind: TicketAttachmentKind?
        if contentType.hasPrefix("image/") {
            kind = .image
        } else if contentType.hasPrefix("video/") {
            kind = .video
        } else {
            kind = nil
        }

        return (url, name, kind)
    }

    private func shouldIncludeFreshserviceTicket(_ ticket: [String: Any]) -> Bool {
        let rawStatusName = (
            nestedStringValue(ticket["status"], key: "name")
            ?? stringValue(ticket["status_name"])
            ?? ""
        ).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let rawStatusCode = stringValue(ticket["status"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if ["1", "2", "3", "6"].contains(rawStatusCode) { return true }
        if rawStatusName.contains("new") { return true }
        if rawStatusName.contains("open") { return true }
        if rawStatusName.contains("pending") { return true }
        if rawStatusName.contains("awaiting response") || rawStatusName.contains("waiting on customer") || rawStatusName.contains("waiting for customer") { return true }

        return false
    }

    private func matchesManagedByGroup(_ asset: [String: Any], filter: String) -> Bool {
        let normalizedFilter = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedFilter.isEmpty else { return true }

        let candidates: [String?] = [
            nestedStringValue(asset["managed_by_group"], key: "name"),
            nestedStringValue(asset["managed_by"], key: "name"),
            nestedStringValue(asset["group"], key: "name"),
            stringValue(asset["managed_by_group"]),
            stringValue(asset["managed_by"]),
            stringValue(asset["group_name"])
        ]

        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .contains { $0 == normalizedFilter }
    }

    private func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private func nestedStringValue(_ value: Any?, key: String) -> String? {
        guard let dictionary = value as? [String: Any] else { return nil }
        return stringValue(dictionary[key])
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String {
            return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private func parsedDate(from value: Any?) -> Date? {
        guard let raw = stringValue(value) else { return nil }
        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: raw) {
            return date
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd", "yyyy-MM-dd HH:mm:ss", "MM/dd/yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) {
                return date
            }
        }
        return nil
    }

    private func convertGoogleSheetLinkToCSV(_ link: String) -> URL {
        let cleanLink = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if let spreadsheetID = extractSpreadsheetID(from: cleanLink) {
            return URL(string: "https://docs.google.com/spreadsheets/d/\(spreadsheetID)/export?format=csv")!
        }
        return URL(string: cleanLink)!
    }

    private func extractSpreadsheetID(from link: String) -> String? {
        guard let range = link.range(of: "/d/") else { return nil }
        let afterD = link[range.upperBound...]
        if let slashRange = afterD.range(of: "/") {
            return String(afterD[..<slashRange.lowerBound])
        }
        return String(afterD)
    }

    private func parseGearCSV(_ csv: String) -> [GearItem] {
        let lines = csv.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard lines.count > 1 else { return [] }

        var items: [GearItem] = []
        let headers = lines[0].components(separatedBy: ",")

        for line in lines.dropFirst() {
            let values = line.components(separatedBy: ",")
            var item = GearItem(name: "", category: "", teamCode: store.teamCode ?? "")

            for (index, header) in headers.enumerated() {
                guard index < values.count else { continue }
                let value = values[index].trimmingCharacters(in: .whitespaces)

                switch header.lowercased() {
                case "name": item.name = value
                case "category": item.category = value
                case "location": item.location = value
                case "campus": item.campus = value
                case "serial", "serialnumber": item.serialNumber = value
                case "asset id", "assetid": item.assetId = value
                case "status":
                    let lowerValue = value.lowercased()
                    if lowerValue.contains("stock") || lowerValue.contains("available") {
                        item.status = .available
                    } else if lowerValue.contains("in use") {
                        item.status = .inUse
                    } else if lowerValue.contains("repair") {
                        item.status = .needsRepair
                    } else if lowerValue.contains("retired") {
                        item.status = .retired
                    } else if lowerValue.contains("missing") {
                        item.status = .missing
                    } else {
                        item.status = .blank
                    }
                case "purchased", "purchasedate": item.purchaseDate = parseDate(value)
                case "purchasedfrom", "purchased from": item.purchasedFrom = value
                case "cost": item.cost = Double(value)
                case "install date", "installdate": item.installDate = parseDate(value)
                case "maintenance issue", "maintenanceissue": item.maintenanceIssue = value
                case "maintenance cost", "maintenancecost": item.maintenanceCost = Double(value)
                case "maintenance repair date", "maintenancerepairdate": item.maintenanceRepairDate = parseDate(value)
                case "maintenance notes", "maintenancenotes": item.maintenanceNotes = value
                case "image url", "imageurl": item.imageURL = value
                default: break
                }
            }

            if !item.name.isEmpty {
                items.append(item)
            }
        }

        return items
    }

    private func parsePatchCSV(_ csv: String) -> [PatchRow] {
        let lines = csv.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard lines.count > 1 else { return [] }

        var rows: [PatchRow] = []
        let headers = lines[0].components(separatedBy: ",")

        for line in lines.dropFirst() {
            let values = line.components(separatedBy: ",")
            var row = PatchRow(name: "", input: "", output: "", teamCode: store.teamCode ?? "", category: "", campus: "", room: "")

            for (index, header) in headers.enumerated() {
                guard index < values.count else { continue }
                let value = values[index].trimmingCharacters(in: .whitespaces)

                switch header.lowercased() {
                case "name": row.name = value
                case "input": row.input = value
                case "output": row.output = value
                case "category": row.category = value
                case "campus": row.campus = value
                case "room": row.room = value
                case "universe": row.universe = value
                default: break
                }
            }

            if !row.name.isEmpty {
                rows.append(row)
            }
        }

        return rows
    }

    private func parseDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString)
    }
}

private struct MacUsersView: View {
    @EnvironmentObject private var store: ProdConnectStore
    @State private var selectedUser: UserProfile?

    private var canManageUsers: Bool {
        store.user?.isAdmin == true || store.user?.isOwner == true
    }

    var body: some View {
        List(store.teamMembers.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }) { user in
            userRow(for: user)
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .navigationTitle("Users")
        .sheet(item: $selectedUser) { user in
            NavigationStack {
                MacUserDetailView(user: user)
                    .environmentObject(store)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                selectedUser = nil
                            }
                        }
                    }
            }
            .frame(minWidth: 520, minHeight: 640)
        }
    }

    @ViewBuilder
    private func userRow(for user: UserProfile) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(user.displayName).font(.headline)
                Text(user.email).font(.caption).foregroundStyle(.secondary)
                if !user.assignedCampus.isEmpty {
                    Text(user.assignedCampus).font(.caption2).foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            if canManageUsers {
                Button("Edit User") {
                    selectedUser = user
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct MacUserDetailView: View {
    @EnvironmentObject private var store: ProdConnectStore
    @Environment(\.dismiss) private var dismiss
    @State private var user: UserProfile
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showTransferConfirm = false
    @State private var showDeleteConfirm = false

    private var canDeleteUser: Bool {
        guard let currentUser = store.user else { return false }
        return currentUser.canDelete(user)
    }

    init(user: UserProfile) {
        _user = State(initialValue: user)
    }

    var body: some View {
        Form {
            Section("User") {
                LabeledContent("Name", value: user.displayName)
                LabeledContent("Email", value: user.email)
            }

            Section("Role") {
                Toggle("Admin", isOn: $user.isAdmin)
                    .disabled(isSaving || user.isOwner)
                    .onChange(of: user.isAdmin) { _, isAdmin in
                        updateAdminFlag(isAdmin: isAdmin)
                    }
            }

            if store.user?.isOwner == true, user.id != store.user?.id {
                Section("Ownership") {
                    Button("Transfer Ownership") {
                        showTransferConfirm = true
                    }
                    .disabled(isSaving)
                }
            }

            if !user.isAdmin && (store.user?.hasCampusRoomFeatures ?? false) {
                Section("Assigned Campus") {
                    Picker("Campus", selection: $user.assignedCampus) {
                        Text("No campus assigned").tag("")
                        ForEach(store.locations.sorted(), id: \.self) { campus in
                            Text(campus).tag(campus)
                        }
                    }
                    .onChange(of: user.assignedCampus) { _, campus in
                        updateAssignedCampus(campus: campus)
                    }
                }
            }

            Section("Permissions") {
                Toggle("Can edit patchsheet", isOn: $user.canEditPatchsheet)
                    .onChange(of: user.canEditPatchsheet) { _, value in
                        updatePermission(key: "canEditPatchsheet", value: value)
                    }
                Toggle("Can edit training", isOn: $user.canEditTraining)
                    .onChange(of: user.canEditTraining) { _, value in
                        updatePermission(key: "canEditTraining", value: value)
                    }
                Toggle("Can edit assets", isOn: $user.canEditGear)
                    .onChange(of: user.canEditGear) { _, value in
                        updatePermission(key: "canEditGear", value: value)
                    }
                Toggle("Can edit ideas", isOn: $user.canEditIdeas)
                    .onChange(of: user.canEditIdeas) { _, value in
                        updatePermission(key: "canEditIdeas", value: value)
                    }
                Toggle("Can edit checklists", isOn: $user.canEditChecklists)
                    .onChange(of: user.canEditChecklists) { _, value in
                        updatePermission(key: "canEditChecklists", value: value)
                    }
                Toggle("Ticket Agent", isOn: $user.isTicketAgent)
                    .onChange(of: user.isTicketAgent) { _, value in
                        updatePermission(key: "isTicketAgent", value: value)
                    }
            }

            if !user.isAdmin {
                Section("Visible Tabs") {
                    Toggle("Chat", isOn: $user.canSeeChat)
                        .onChange(of: user.canSeeChat) { _, value in
                            updatePermission(key: "canSeeChat", value: value)
                        }
                    Toggle("Patchsheet", isOn: $user.canSeePatchsheet)
                        .onChange(of: user.canSeePatchsheet) { _, value in
                            updatePermission(key: "canSeePatchsheet", value: value)
                        }
                    Toggle("Training", isOn: $user.canSeeTraining)
                        .onChange(of: user.canSeeTraining) { _, value in
                            updatePermission(key: "canSeeTraining", value: value)
                        }
                    Toggle("Assets", isOn: $user.canSeeGear)
                        .onChange(of: user.canSeeGear) { _, value in
                            updatePermission(key: "canSeeGear", value: value)
                        }
                    Toggle("Ideas", isOn: $user.canSeeIdeas)
                        .onChange(of: user.canSeeIdeas) { _, value in
                            updatePermission(key: "canSeeIdeas", value: value)
                        }
                    Toggle("Checklists", isOn: $user.canSeeChecklists)
                        .onChange(of: user.canSeeChecklists) { _, value in
                            updatePermission(key: "canSeeChecklists", value: value)
                        }
                    Toggle("Tickets", isOn: $user.canSeeTickets)
                        .onChange(of: user.canSeeTickets) { _, value in
                            updatePermission(key: "canSeeTickets", value: value)
                        }
                }
            }

            if canDeleteUser {
                Section {
                    Button("Delete User", role: .destructive) {
                        showDeleteConfirm = true
                    }
                    .disabled(isSaving)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Edit User")
        .alert("Transfer Ownership?", isPresented: $showTransferConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Transfer", role: .destructive) {
                transferOwnership()
            }
        } message: {
            Text("This will move the Owner role and subscription control to this user.")
        }
        .alert("Delete User?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteUser()
            }
        } message: {
            Text("This permanently deletes \(user.displayName)'s user profile.")
        }
        .toolbar {
            if isSaving {
                ToolbarItem {
                    ProgressView()
                }
            }
        }
    }

    private func transferOwnership() {
        guard let currentOwner = store.user, currentOwner.isOwner else { return }
        let teamCode = (currentOwner.teamCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !teamCode.isEmpty else {
            errorMessage = "No team code available."
            return
        }

        isSaving = true
        errorMessage = nil

        let batch = store.db.batch()
        let teamRef = store.db.collection("teams").document(teamCode)
        let currentOwnerRef = store.db.collection("users").document(currentOwner.id)
        let newOwnerRef = store.db.collection("users").document(user.id)

        batch.setData([
            "ownerId": user.id,
            "ownerEmail": user.email,
            "code": teamCode,
            "isActive": true
        ], forDocument: teamRef, merge: true)

        batch.setData([
            "isOwner": false
        ], forDocument: currentOwnerRef, merge: true)

        let newOwnerUpdates: [String: Any] = [
            "isOwner": true,
            "isAdmin": true
        ]
        batch.setData(newOwnerUpdates, forDocument: newOwnerRef, merge: true)

        batch.commit { error in
            DispatchQueue.main.async {
                self.isSaving = false
                if let error {
                    self.errorMessage = "Transfer failed: \(error.localizedDescription)"
                    return
                }

                if currentOwner.id == self.store.user?.id {
                    self.store.user?.isOwner = false
                }
                self.user.isOwner = true
                self.user.isAdmin = true
                self.replaceTeamMember()
            }
        }
    }

    private func updateAdminFlag(isAdmin: Bool) {
        isSaving = true
        errorMessage = nil
        store.db.collection("users").document(user.id).updateData(["isAdmin": isAdmin]) { error in
            DispatchQueue.main.async {
                self.isSaving = false
                if let error {
                    self.errorMessage = "Update failed: \(error.localizedDescription)"
                    self.user.isAdmin.toggle()
                    return
                }

                self.replaceTeamMember()
            }
        }
    }

    private func updateAssignedCampus(campus: String) {
        guard !user.id.isEmpty else {
            errorMessage = "Update failed: missing user id"
            return
        }

        isSaving = true
        errorMessage = nil
        store.db.collection("users").document(user.id).setData(["assignedCampus": campus], merge: true) { error in
            DispatchQueue.main.async {
                self.isSaving = false
                if let error {
                    self.errorMessage = "Update failed: \(error.localizedDescription)"
                    return
                }

                self.user.assignedCampus = campus
                self.replaceTeamMember()
            }
        }
    }

    private func updatePermission(key: String, value: Bool) {
        isSaving = true
        errorMessage = nil
        store.db.collection("users").document(user.id).updateData([key: value]) { error in
            DispatchQueue.main.async {
                self.isSaving = false
                if let error {
                    self.errorMessage = "Update failed: \(error.localizedDescription)"
                    return
                }

                switch key {
                case "canEditPatchsheet":
                    self.user.canEditPatchsheet = value
                case "canEditTraining":
                    self.user.canEditTraining = value
                case "canEditGear":
                    self.user.canEditGear = value
                case "canEditIdeas":
                    self.user.canEditIdeas = value
                case "canEditChecklists":
                    self.user.canEditChecklists = value
                case "isTicketAgent":
                    self.user.isTicketAgent = value
                case "canSeeChat":
                    self.user.canSeeChat = value
                case "canSeePatchsheet":
                    self.user.canSeePatchsheet = value
                case "canSeeTraining":
                    self.user.canSeeTraining = value
                case "canSeeGear":
                    self.user.canSeeGear = value
                case "canSeeIdeas":
                    self.user.canSeeIdeas = value
                case "canSeeChecklists":
                    self.user.canSeeChecklists = value
                case "canSeeTickets":
                    self.user.canSeeTickets = value
                default:
                    break
                }

                self.replaceTeamMember()
            }
        }
    }

    private func replaceTeamMember() {
        guard let index = store.teamMembers.firstIndex(where: { $0.id == user.id }) else { return }
        store.teamMembers[index] = user
    }

    private func deleteUser() {
        guard canDeleteUser else { return }

        isSaving = true
        errorMessage = nil

        store.db.collection("users").document(user.id).delete { error in
            DispatchQueue.main.async {
                self.isSaving = false
                if let error {
                    self.errorMessage = "Delete failed: \(error.localizedDescription)"
                    return
                }

                self.store.teamMembers.removeAll { $0.id == self.user.id }
                dismiss()
            }
        }
    }
}

private struct MacAccountView: View {
    @EnvironmentObject private var store: ProdConnectStore
    @State private var showEditAccount = false
    @State private var showDeleteConfirm = false
    @State private var showSubscriptionOptions = false
    @State private var isDeletingAccount = false
    @State private var errorMessage: String?
    @State private var subscriptionErrorMessage: String?
    @State private var organizationName = ""
    @State private var organizationStatusMessage: String?
    private let termsURLString = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
    private let privacyPolicyURLString = "https://bmsatori.github.io/prodconnect-privacy/"

    private var roleLabel: String {
        if store.user?.isOwner == true { return "Owner" }
        if store.user?.isAdmin == true { return "Admin" }
        return "Basic"
    }

    private var appVersionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        if !version.isEmpty && !build.isEmpty {
            return "\(version) (\(build))"
        }
        return version.isEmpty ? build : version
    }

    private var canViewTeamCode: Bool {
        guard let user = store.user else { return false }
        return user.isAdmin || user.isOwner
    }

    private var normalizedSubscriptionTier: String {
        canonicalSubscriptionTier(store.user?.subscriptionTier)
    }

    private var canManageSubscription: Bool {
        guard let user = store.user else { return false }
        if normalizedSubscriptionTier == "free" {
            return true
        }
        return (user.isAdmin || user.isOwner) && normalizedSubscriptionTier != "premium_ticketing"
    }

    private var subscriptionButtonTitle: String {
        normalizedSubscriptionTier == "free" ? "Subscribe" : "Upgrade Subscription"
    }

    private var canEditOrganizationName: Bool {
        store.user?.isAdmin == true || store.user?.isOwner == true
    }

    private var subscriptionTierLabel: String {
        switch normalizedSubscriptionTier {
        case "premium_ticketing", "premium w/ticketing", "premium with ticketing":
            return "Premium W/Ticketing"
        case "premium":
            return "Premium"
        case "basic_ticketing", "basic w/ticketing", "basic with ticketing":
            return "Basic W/Ticketing"
        case "basic":
            return "Basic"
        default:
            return "Free"
        }
    }

    var body: some View {
        Form {
            if let user = store.user {
                LabeledContent("Name", value: user.displayName)
                LabeledContent("Email", value: user.email)
                if canViewTeamCode {
                    LabeledContent("Team Code", value: user.teamCode ?? "None")
                }
                LabeledContent("Subscription", value: subscriptionTierLabel)
                LabeledContent("Role", value: roleLabel)
                if !appVersionText.isEmpty {
                    LabeledContent("App Version", value: appVersionText)
                }
                if !user.assignedCampus.isEmpty {
                    LabeledContent("Campus", value: user.assignedCampus)
                }
            }

            if canEditOrganizationName {
                Section("Organization") {
                    TextField("Organization Name", text: $organizationName)
                    Button("Save Organization Name") {
                        saveOrganizationName()
                    }
                    .buttonStyle(.borderedProminent)
                    if let organizationStatusMessage {
                        Text(organizationStatusMessage)
                            .foregroundStyle(organizationStatusMessage.hasPrefix("Saved") ? .green : .red)
                    }
                }
            }

            if canManageSubscription {
                Section("Subscription") {
                    Button(subscriptionButtonTitle) {
                        showSubscriptionOptions = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Section("Actions") {
                Button("Edit Account") {
                    showEditAccount = true
                }

                Button("Support") {
                    if let url = URL(string: "mailto:prodconnectapp@gmail.com") {
                        NSWorkspace.shared.open(url)
                    }
                }

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Text(isDeletingAccount ? "Deleting..." : "Delete Account")
                }
                .disabled(isDeletingAccount)

                Button("Sign Out") {
                    store.signOut()
                }
                .buttonStyle(.borderedProminent)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding()
        .background(Color.clear)
        .navigationTitle("Account")
        .task {
            await reconcileSubscriptionState(showNoActiveError: false)
        }
        .onAppear {
            organizationName = store.organizationName
        }
        .onReceive(store.$organizationName) { value in
            organizationName = value
        }
        .task {
            await observeTransactionUpdates()
        }
        .sheet(isPresented: $showEditAccount) {
            MacEditAccountView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showSubscriptionOptions) {
            MacSubscriptionOptionsView(
                currentTier: normalizedSubscriptionTier,
                termsURLString: termsURLString,
                privacyPolicyURLString: privacyPolicyURLString,
                onPurchaseBasic: {
                    await purchaseSubscription(productID: "Basic3", targetTier: "basic")
                },
                onPurchaseBasicTicketing: {
                    await purchaseSubscription(productID: "Basic_Ticketing", targetTier: "basic_ticketing")
                },
                onPurchasePremium: {
                    await purchaseSubscription(productID: "Premium2", targetTier: "premium")
                },
                onPurchasePremiumTicketing: {
                    await purchaseSubscription(productID: "Premium_Ticketing", targetTier: "premium_ticketing")
                },
                onRestorePurchases: {
                    await restorePurchases()
                }
            )
        }
        .alert("Subscription Error", isPresented: subscriptionErrorAlertIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(subscriptionErrorMessage ?? "Unknown subscription error.")
        }
        .alert("Delete Account?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                performAccountDeletion()
            }
        } message: {
            Text("This permanently deletes your account. You may need to sign in again before retrying if Apple requires recent authentication.")
        }
    }

    private func performAccountDeletion() {
        guard let currentUser = Auth.auth().currentUser else {
            errorMessage = "No logged in user."
            return
        }

        isDeletingAccount = true
        errorMessage = nil
        let uid = currentUser.uid

        currentUser.delete { deleteError in
            DispatchQueue.main.async {
                if let deleteError = deleteError as NSError? {
                    self.isDeletingAccount = false
                    if deleteError.code == AuthErrorCode.requiresRecentLogin.rawValue {
                        self.errorMessage = "For security, sign out and back in, then try deleting your account again."
                    } else {
                        self.errorMessage = "Account deletion failed: \(deleteError.localizedDescription)"
                    }
                    return
                }

                self.store.db.collection("users").document(uid).delete { _ in
                    DispatchQueue.main.async {
                        self.isDeletingAccount = false
                        self.store.signOut()
                    }
                }
            }
        }
    }

    private func saveOrganizationName() {
        organizationStatusMessage = nil
        store.saveOrganizationName(organizationName) { result in
            switch result {
            case .success:
                organizationStatusMessage = "Saved organization name."
            case .failure(let error):
                organizationStatusMessage = "Save failed: \(error.localizedDescription)"
            }
        }
    }

    private var subscriptionErrorAlertIsPresented: Binding<Bool> {
        Binding(
            get: { subscriptionErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    subscriptionErrorMessage = nil
                }
            }
        )
    }

    private func purchaseSubscription(productID: String, targetTier: String) async {
        do {
            let products = try await Product.products(for: [productID])
            guard let product = products.first else {
                throw MacSubscriptionError.productNotFound
            }

            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                try await applySubscription(targetTier: targetTier)
                await transaction.finish()
                showSubscriptionOptions = false
            case .userCancelled:
                break
            case .pending:
                throw MacSubscriptionError.pending
            @unknown default:
                throw MacSubscriptionError.unknown
            }
        } catch {
            subscriptionErrorMessage = error.localizedDescription
        }
    }

    private func restorePurchases() async {
        do {
            try await AppStore.sync()
            await reconcileSubscriptionState(showNoActiveError: true)
        } catch {
            subscriptionErrorMessage = error.localizedDescription
        }
    }

    private func applySubscription(targetTier: String) async throws {
        guard var user = store.user else {
            throw MacSubscriptionError.userNotLoaded
        }

        let resolvedTier = canonicalSubscriptionTier(targetTier)
        user.isAdmin = true
        user.subscriptionTier = resolvedTier
        user.canEditPatchsheet = true
        user.canEditTraining = true
        user.canEditGear = true
        user.canEditIdeas = true
        user.canEditChecklists = true
        user.canSeeChat = true
        user.canSeeTraining = true
        user.canSeeTickets = resolvedTier == "basic_ticketing" || resolvedTier == "premium_ticketing"

        if (user.teamCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let generatedCode = store.generateTeamCode()
            user.teamCode = generatedCode
            try await store.db.collection("teams").document(generatedCode).setData([
                "code": generatedCode,
                "createdAt": FieldValue.serverTimestamp(),
                "createdBy": user.email,
                "isActive": true
            ], merge: true)
        }

        let uid = Auth.auth().currentUser?.uid ?? user.id
        let updates: [String: Any] = [
            "isAdmin": true,
            "subscriptionTier": user.subscriptionTier,
            "teamCode": user.teamCode ?? "",
            "canEditPatchsheet": true,
            "canEditTraining": true,
            "canEditGear": true,
            "canEditIdeas": true,
            "canEditChecklists": true,
            "canSeeChat": true,
            "canSeeTraining": true,
            "canSeeTickets": user.canSeeTickets
        ]

        try await store.db.collection("users").document(uid).setData(updates, merge: true)

        store.user = user
        store.teamCode = user.teamCode
        store.listenToTeamData()
        store.listenToTeamMembers()
    }

    private func observeTransactionUpdates() async {
        for await update in Transaction.updates {
            do {
                let transaction = try checkVerified(update)
                await reconcileSubscriptionState(showNoActiveError: false)
                await transaction.finish()
            } catch {
                subscriptionErrorMessage = error.localizedDescription
            }
        }
    }

    private func reconcileSubscriptionState(showNoActiveError: Bool) async {
        do {
            var highestTier: String?
            for try await verification in Transaction.currentEntitlements {
                let transaction = try checkVerified(verification)
                guard let resolvedTier = subscriptionTier(for: transaction.productID) else {
                    continue
                }
                if highestTier == nil || subscriptionTierRank(for: resolvedTier) > subscriptionTierRank(for: highestTier ?? "free") {
                    highestTier = resolvedTier
                }
            }

            if let highestTier {
                try await applySubscription(targetTier: highestTier)
                showSubscriptionOptions = false
            } else if showNoActiveError {
                throw MacSubscriptionError.noActiveSubscription
            }
        } catch {
            if showNoActiveError || (error as? MacSubscriptionError) != .noActiveSubscription {
                subscriptionErrorMessage = error.localizedDescription
            }
        }
    }

    private func revokeSubscriptionEntitlements() async throws {
        guard var user = store.user else {
            throw MacSubscriptionError.userNotLoaded
        }
        guard canonicalSubscriptionTier(user.subscriptionTier) != "free" else { return }

        user.subscriptionTier = "free"
        user.canEditTraining = false
        user.canSeeChat = false
        user.canSeeTraining = false
        user.canSeeTickets = false

        let uid = Auth.auth().currentUser?.uid ?? user.id
        try await store.db.collection("users").document(uid).setData([
            "subscriptionTier": "free",
            "canEditTraining": false,
            "canSeeChat": false,
            "canSeeTraining": false,
            "canSeeTickets": false
        ], merge: true)

        store.user = user
    }

    private func subscriptionTier(for productID: String) -> String? {
        switch productID {
        case "Premium_Ticketing":
            return "premium_ticketing"
        case "Premium2":
            return "premium"
        case "Basic_Ticketing":
            return "basic_ticketing"
        case "Basic3":
            return "basic"
        default:
            return nil
        }
    }

    private func subscriptionTierRank(for tier: String) -> Int {
        switch canonicalSubscriptionTier(tier) {
        case "premium_ticketing":
            return 4
        case "premium":
            return 3
        case "basic_ticketing":
            return 2
        case "basic":
            return 1
        default:
            return 0
        }
    }

    private func canonicalSubscriptionTier(_ rawValue: String?) -> String {
        switch rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "free" {
        case "premium_ticketing", "premium w/ticketing", "premium with ticketing":
            return "premium_ticketing"
        case "basic_ticketing", "basic w/ticketing", "basic with ticketing":
            return "basic_ticketing"
        case "premium":
            return "premium"
        case "basic":
            return "basic"
        default:
            return "free"
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, _):
            throw MacSubscriptionError.verificationFailed
        case .verified(let signedType):
            return signedType
        }
    }
}

private struct MacSubscriptionOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var basicProduct: Product?
    @State private var basicTicketingProduct: Product?
    @State private var premiumProduct: Product?
    @State private var premiumTicketingProduct: Product?
    @State private var isLoadingProducts = false
    @State private var isPurchasing = false

    let currentTier: String
    let termsURLString: String
    let privacyPolicyURLString: String
    let onPurchaseBasic: () async -> Void
    let onPurchaseBasicTicketing: () async -> Void
    let onPurchasePremium: () async -> Void
    let onPurchasePremiumTicketing: () async -> Void
    let onRestorePurchases: () async -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("ProdConnect Subscriptions")
                        .font(.title3.weight(.semibold))

                    Text("Choose the plan that fits your production team. Subscriptions renew automatically unless canceled in your Apple account settings.")
                        .foregroundStyle(.secondary)

                    subscriptionCard(
                        title: basicProduct?.displayName ?? "Basic",
                        subtitle: "$99.99. Includes chat and training, but hides Locations, Rooms, and Tickets.",
                        price: priceText(for: basicProduct),
                        buttonTitle: currentTier == "basic" ? "Current Plan" : "Choose Basic",
                        isPrimary: true,
                        isDisabled: isPurchasing || currentTier == "basic" || currentTier == "basic_ticketing" || currentTier == "premium" || currentTier == "premium_ticketing"
                    ) {
                        await runPurchase(onPurchaseBasic)
                    }

                    subscriptionCard(
                        title: basicTicketingProduct?.displayName ?? "Basic W/Ticketing",
                        subtitle: "$199.99. Includes chat, training, and Tickets, but hides Locations and Rooms.",
                        price: priceText(for: basicTicketingProduct),
                        buttonTitle: currentTier == "basic_ticketing" ? "Current Plan" : "Choose Basic W/Ticketing",
                        isPrimary: false,
                        isDisabled: isPurchasing || currentTier == "basic_ticketing" || currentTier == "premium" || currentTier == "premium_ticketing"
                    ) {
                        await runPurchase(onPurchaseBasicTicketing)
                    }

                    subscriptionCard(
                        title: premiumProduct?.displayName ?? "Premium",
                        subtitle: "$249.99. Includes everything except Tickets.",
                        price: priceText(for: premiumProduct),
                        buttonTitle: currentTier == "premium" ? "Current Plan" : "Choose Premium",
                        isPrimary: false,
                        isDisabled: isPurchasing || currentTier == "premium" || currentTier == "premium_ticketing"
                    ) {
                        await runPurchase(onPurchasePremium)
                    }

                    subscriptionCard(
                        title: premiumTicketingProduct?.displayName ?? "Premium W/Ticketing",
                        subtitle: "$499.99. Includes every feature.",
                        price: priceText(for: premiumTicketingProduct),
                        buttonTitle: currentTier == "premium_ticketing" ? "Current Plan" : "Choose Premium W/Ticketing",
                        isPrimary: false,
                        isDisabled: isPurchasing || currentTier == "premium_ticketing"
                    ) {
                        await runPurchase(onPurchasePremiumTicketing)
                    }

                    Button(isPurchasing ? "Working..." : "Restore Purchases") {
                        Task {
                            await runPurchase(onRestorePurchases)
                        }
                    }
                    .disabled(isPurchasing)

                    if let termsURL = URL(string: termsURLString) {
                        Link("Terms of Use (EULA)", destination: termsURL)
                            .font(.footnote)
                    }
                    if let privacyURL = URL(string: privacyPolicyURLString) {
                        Link("Privacy Policy", destination: privacyURL)
                            .font(.footnote)
                    }
                }
                .padding()
            }
            .navigationTitle("Subscription")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                await loadProducts()
            }
        }
        .frame(minWidth: 520, minHeight: 420)
    }

    @ViewBuilder
    private func subscriptionCard(
        title: String,
        subtitle: String,
        price: String,
        buttonTitle: String,
        isPrimary: Bool,
        isDisabled: Bool,
        action: @escaping () async -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            Text(price)
                .font(.subheadline.weight(.medium))
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if isPrimary {
                Button(buttonTitle) {
                    Task {
                        await action()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isDisabled)
            } else {
                Button(buttonTitle) {
                    Task {
                        await action()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isDisabled)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let products = try await Product.products(for: ["Basic3", "Basic_Ticketing", "Premium2", "Premium_Ticketing"])
            basicProduct = products.first(where: { $0.id == "Basic3" })
            basicTicketingProduct = products.first(where: { $0.id == "Basic_Ticketing" })
            premiumProduct = products.first(where: { $0.id == "Premium2" })
            premiumTicketingProduct = products.first(where: { $0.id == "Premium_Ticketing" })
        } catch {
            // Keep the fallback copy visible even if products fail to load.
        }
    }

    private func priceText(for product: Product?) -> String {
        if isLoadingProducts {
            return "Loading pricing..."
        }
        return product?.displayPrice ?? "Available in App Store"
    }

    private func runPurchase(_ action: @escaping () async -> Void) async {
        guard !isPurchasing else { return }
        isPurchasing = true
        await action()
        isPurchasing = false
    }
}

private enum MacSubscriptionError: LocalizedError {
    case productNotFound
    case pending
    case unknown
    case noActiveSubscription
    case userNotLoaded
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .productNotFound:
            return "The subscription product could not be loaded."
        case .pending:
            return "The purchase is still pending approval."
        case .unknown:
            return "An unknown subscription error occurred."
        case .noActiveSubscription:
            return "No active subscription was found to restore."
        case .userNotLoaded:
            return "Your account information is not loaded yet."
        case .verificationFailed:
            return "The App Store transaction could not be verified."
        }
    }
}

private struct MacEditAccountView: View {
    @EnvironmentObject private var store: ProdConnectStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    @State private var displayName = ""
    @State private var newEmail = ""
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    private enum Field: Hashable {
        case displayName
        case email
        case currentPassword
        case newPassword
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Display Name") {
                    TextField("Display Name", text: $displayName)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled(true)
                        .focused($focusedField, equals: .displayName)
                }

                Section("Login Email") {
                    TextField("New Email", text: $newEmail)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled(true)
                        .focused($focusedField, equals: .email)
                }

                Section("Password") {
                    SecureField("Current Password", text: $currentPassword)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .currentPassword)
                    SecureField("New Password", text: $newPassword)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .newPassword)
                }

                Section {
                    Button("Save Changes") {
                        saveChanges()
                    }
                    .disabled(isSaving)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Edit Account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                displayName = store.user?.displayName ?? (Auth.auth().currentUser?.email?.components(separatedBy: "@").first ?? "")
                newEmail = ""
                currentPassword = ""
                newPassword = ""
                DispatchQueue.main.async {
                    focusedField = .displayName
                }
            }
            .alert("Account Updated", isPresented: Binding(get: { successMessage != nil }, set: { if !$0 { successMessage = nil } })) {
                Button("OK", role: .cancel) { dismiss() }
            } message: {
                Text(successMessage ?? "")
            }
        }
    }

    private func saveChanges() {
        guard let currentUser = Auth.auth().currentUser else {
            errorMessage = "No logged in user."
            return
        }

        errorMessage = nil
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = newEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = newPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        let emailChanged = !trimmedEmail.isEmpty && trimmedEmail != currentUser.email
        let passwordChanged = !trimmedPassword.isEmpty
        let nameChanged = !trimmedName.isEmpty && trimmedName != (store.user?.displayName ?? "")
        let needsReauth = emailChanged || passwordChanged

        if needsReauth && currentPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "Current password is required to change email or password."
            return
        }

        isSaving = true

        func finish(_ error: Error?) {
            DispatchQueue.main.async {
                self.isSaving = false
                if let error {
                    self.errorMessage = error.localizedDescription
                } else {
                    self.successMessage = "Your account changes have been saved."
                }
            }
        }

        func updateDisplayNameIfNeeded(completion: @escaping (Error?) -> Void) {
            guard nameChanged, let uid = store.user?.id else {
                completion(nil)
                return
            }
            let changeRequest = currentUser.createProfileChangeRequest()
            changeRequest.displayName = trimmedName
            changeRequest.commitChanges { authError in
                if let authError {
                    completion(authError)
                    return
                }
                store.db.collection("users").document(uid).updateData(["displayName": trimmedName]) { error in
                    if error == nil {
                        DispatchQueue.main.async {
                            store.user?.displayName = trimmedName
                            store.listenToTeamMembers()
                        }
                    }
                    completion(error)
                }
            }
        }

        func updateEmailIfNeeded(completion: @escaping (Error?) -> Void) {
            guard emailChanged else {
                completion(nil)
                return
            }
            currentUser.sendEmailVerification(beforeUpdatingEmail: trimmedEmail) { error in
                if let error {
                    completion(error)
                    return
                }
                DispatchQueue.main.async {
                    self.successMessage = "Check \(trimmedEmail) to verify the email change."
                }
                completion(nil)
            }
        }

        func updatePasswordIfNeeded(completion: @escaping (Error?) -> Void) {
            guard passwordChanged else {
                completion(nil)
                return
            }
            currentUser.updatePassword(to: trimmedPassword, completion: completion)
        }

        func runUpdates() {
            updateEmailIfNeeded { emailError in
                if let emailError {
                    finish(emailError)
                    return
                }
                updatePasswordIfNeeded { passwordError in
                    if let passwordError {
                        finish(passwordError)
                        return
                    }
                    updateDisplayNameIfNeeded { nameError in
                        finish(nameError)
                    }
                }
            }
        }

        if needsReauth {
            guard let email = currentUser.email else {
                finish(NSError(domain: "Auth", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing email for reauthentication."]))
                return
            }
            let credential = EmailAuthProvider.credential(withEmail: email, password: currentPassword)
            currentUser.reauthenticate(with: credential) { _, error in
                if let error {
                    finish(error)
                } else {
                    runUpdates()
                }
            }
        } else {
            runUpdates()
        }
    }
}
