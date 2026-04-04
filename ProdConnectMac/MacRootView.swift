import AVFoundation
import AVKit
import AppKit
import Combine
#if canImport(CoreMIDI)
import CoreMIDI
#endif
import Darwin
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
    case runOfShow
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
        case .runOfShow: return "Run of Show"
        case .training: return "Training"
        case .gear: return "Assets"
        case .tickets: return "Tickets"
        case .checklists: return "Checklist"
        case .ideas: return "Ideas"
        case .customize: return "Settings"
        case .users: return "Users"
        case .account: return "Account"
        }
    }

    var icon: String {
        switch self {
        case .chat: return "message"
        case .patchsheet: return "square.grid.3x2"
        case .runOfShow: return "list.bullet.rectangle.portrait"
        case .training: return "graduationcap"
        case .gear: return "shippingbox"
        case .tickets: return "ticket"
        case .checklists: return "checklist"
        case .ideas: return "lightbulb"
        case .customize: return "slider.horizontal.3"
        case .users: return "person.3"
        case .account: return "person.crop.circle"
        }
    }

}

private enum MacSettingsSection: String, CaseIterable, Identifiable {
    case importData = "Import"
    case locationsRooms = "Locations / Rooms"
    case tickets = "Tickets"
    case integrations = "Integrations"
    case ndi = "NDI"
    case midi = "MIDI"
    case users = "Users"

    var id: String { rawValue }
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
    @EnvironmentObject private var ndiSettings: MacNDISettingsController
    @EnvironmentObject private var runOfShowControls: MacRunOfShowControlController
    @State private var selectedRoute: MacRoute? = .chat
    @State private var isShowingNotifications = false
    @State private var showsWelcomeScreen = true
    @AppStorage("prodconnect.mac.sidebarRouteOrder") private var sidebarRouteOrderStorage = ""

    private var sidebarRoutes: [MacRoute] {
        let visibleRoutes = MacRoute.allCases.filter { route in
            switch route {
            case .chat:
                return store.canSeeChat
            case .runOfShow:
                return store.canSeeRunOfShow
            case .training:
                return store.canSeeTrainingTab
            case .tickets:
                return store.canUseTickets
            case .users:
                return false
            default:
                return true
            }
        }
        return resolvedSidebarRoutes(from: visibleRoutes)
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
        List(selection: $selectedRoute) {
            ForEach(sidebarRoutes) { route in
                Label(route.title, systemImage: route.icon)
                    .tag(route)
            }
            .onMove(perform: moveSidebarRoutes)
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
        case .runOfShow:
            MacRunOfShowView()
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
            MacSettingsView()
                .environmentObject(store)
                .environmentObject(ndiSettings)
                .environmentObject(runOfShowControls)
        case .users:
            MacUsersView()
        case .account:
            MacAccountView()
        }
    }

    private func resolvedSidebarRoutes(from visibleRoutes: [MacRoute]) -> [MacRoute] {
        let preferred = sidebarRouteOrderStorage
            .split(separator: ",")
            .compactMap { MacRoute(rawValue: String($0)) }
        let visibleSet = Set(visibleRoutes)
        var ordered: [MacRoute] = []

        for route in preferred where visibleSet.contains(route) && !ordered.contains(route) {
            ordered.append(route)
        }
        for route in visibleRoutes where !ordered.contains(route) {
            ordered.append(route)
        }
        return ordered
    }

    private func persistSidebarRoutes(_ routes: [MacRoute]) {
        sidebarRouteOrderStorage = routes.map(\.rawValue).joined(separator: ",")
    }

    private func moveSidebarRoutes(from source: IndexSet, to destination: Int) {
        var routes = sidebarRoutes
        routes.move(fromOffsets: source, toOffset: destination)
        persistSidebarRoutes(routes)
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
    @EnvironmentObject private var ndiSettings: MacNDISettingsController
    @AppStorage("prodconnect.mac.patchsheetZoom") private var patchsheetZoom = 1.0
    @State private var selectedCategory = "Audio"
    @State private var field1 = ""
    @State private var field2 = ""
    @State private var field3 = ""
    @State private var field4 = ""
    @State private var selectedPatch: PatchRow?
    @State private var noteDrafts: [String: String] = [:]
    @FocusState private var focusedNotesPatchID: String?

    private let categories = ["Audio", "Video", "Lighting"]

    private var filtered: [PatchRow] {
        store.patchsheet
            .filter { $0.category == selectedCategory }
            .sorted(by: PatchRow.autoSort)
    }
    private var hasNDIFeature: Bool {
        guard let user = store.user else { return false }
        return user.normalizedSubscriptionTier != "free"
    }
    private var canManageNDI: Bool {
        guard let user = store.user else { return false }
        return hasNDIFeature && (user.isAdmin || user.isOwner)
    }
    private var nameColumnTitle: String {
        selectedCategory == "Lighting" ? "Fixture" : "Name"
    }
    private var inputColumnTitle: String {
        switch selectedCategory {
        case "Video": return "Source"
        case "Lighting": return "DMX Channel"
        default: return "Input"
        }
    }
    private var outputColumnTitle: String {
        switch selectedCategory {
        case "Video": return "Destination"
        case "Lighting": return "Channel Count"
        default: return "Output"
        }
    }
    private var showsLightingUniverseColumn: Bool {
        selectedCategory == "Lighting"
    }
    private var patchsheetNameColumnWidth: CGFloat { 250 * patchsheetZoom }
    private var patchsheetInputColumnWidth: CGFloat { 160 * patchsheetZoom }
    private var patchsheetOutputColumnWidth: CGFloat { 160 * patchsheetZoom }
    private var patchsheetUniverseColumnWidth: CGFloat { 110 * patchsheetZoom }
    private var patchsheetNotesColumnWidth: CGFloat { 260 * patchsheetZoom }
    private var patchsheetNDIColumnWidth: CGFloat { 72 }
    private var patchsheetTableWidth: CGFloat {
        patchsheetNameColumnWidth
            + patchsheetInputColumnWidth
            + patchsheetOutputColumnWidth
            + (showsLightingUniverseColumn ? patchsheetUniverseColumnWidth : 0)
            + patchsheetNotesColumnWidth
            + (hasNDIFeature ? patchsheetNDIColumnWidth : 0)
    }
    private var patchsheetHeaderFont: Font { .system(size: 11 * patchsheetZoom, weight: .semibold) }
    private var patchsheetRowFont: Font { .system(size: 13 * patchsheetZoom) }
    private var patchsheetEmphasisFont: Font { .system(size: 13 * patchsheetZoom, weight: .semibold) }
    private var patchsheetCellVerticalPadding: CGFloat { 10 * patchsheetZoom }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                Picker("Category", selection: $selectedCategory) {
                    ForEach(categories, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 10) {
                    Text("Zoom")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Slider(value: $patchsheetZoom, in: 0.8...1.5, step: 0.05)
                        .frame(width: 180)
                    Text("\(Int((patchsheetZoom * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 42, alignment: .trailing)
                }

                Spacer(minLength: 0)

            }

            patchsheetTable
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            GroupBox("Add Patch") {
                VStack(spacing: 10) {
                    TextField(selectedCategory == "Lighting" ? "Fixture" : "Name", text: $field1)
                        .onSubmit {
                            submitNewPatch()
                        }
                    HStack(spacing: 10) {
                        TextField(primaryPlaceholder, text: $field2)
                            .onSubmit {
                                submitNewPatch()
                            }
                        TextField(secondaryPlaceholder, text: $field3)
                            .onSubmit {
                                submitNewPatch()
                            }
                    }
                    if selectedCategory == "Lighting" {
                        TextField("Universe", text: $field4)
                            .onSubmit {
                                submitNewPatch()
                            }
                    }
                    Button("Save Patch") {
                        submitNewPatch()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmitNewPatch)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding()
        .background(Color.clear)
        .navigationTitle("Patchsheet")
        .sheet(item: $selectedPatch) { patch in
            MacEditPatchView(patch: patch)
                .environmentObject(store)
        }
        .onChange(of: focusedNotesPatchID) { oldValue, newValue in
            guard oldValue != newValue, let oldValue else { return }
            saveNotes(forPatchID: oldValue)
        }
    }

    private var patchsheetTable: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                patchsheetHeaderRow
                ForEach(filtered) { item in
                    Button {
                        selectedPatch = item
                    } label: {
                        patchsheetRow(for: item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: patchsheetTableWidth, alignment: .leading)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var patchsheetHeaderRow: some View {
        HStack(spacing: 0) {
            patchsheetHeaderCell(nameColumnTitle, width: patchsheetNameColumnWidth)
            patchsheetHeaderCell(inputColumnTitle, width: patchsheetInputColumnWidth)
            patchsheetHeaderCell(outputColumnTitle, width: patchsheetOutputColumnWidth)
            if showsLightingUniverseColumn {
                patchsheetHeaderCell("Universe", width: patchsheetUniverseColumnWidth)
            }
            patchsheetHeaderCell("Notes", width: patchsheetNotesColumnWidth)
            if hasNDIFeature {
                patchsheetHeaderCell("NDI", width: patchsheetNDIColumnWidth, alignment: .center)
            }
        }
        .background(Color.white.opacity(0.045))
    }

    private func patchsheetHeaderCell(_ title: String, width: CGFloat, alignment: Alignment = .leading) -> some View {
        Text(title)
            .font(patchsheetHeaderFont)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: alignment)
            .padding(.horizontal, 14)
            .padding(.vertical, 11 * patchsheetZoom)
    }

    private func patchsheetRow(for patch: PatchRow) -> some View {
        HStack(spacing: 0) {
            patchsheetValueButtonCell(patch.name, width: patchsheetNameColumnWidth, emphasized: true) {
                selectedPatch = patch
            }
            patchsheetValueButtonCell(patch.input, width: patchsheetInputColumnWidth) {
                selectedPatch = patch
            }
            patchsheetValueButtonCell(patch.output, width: patchsheetOutputColumnWidth) {
                selectedPatch = patch
            }
            if showsLightingUniverseColumn {
                patchsheetValueButtonCell(patch.universe ?? "", width: patchsheetUniverseColumnWidth) {
                    selectedPatch = patch
                }
            }
            patchsheetNotesCell(for: patch)
            if hasNDIFeature {
                patchsheetNDICell(for: patch)
            }
        }
        .background(Color.white.opacity(0.02))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(height: 1)
        }
    }

    private func patchsheetValueCell(_ value: String, width: CGFloat, emphasized: Bool = false) -> some View {
        Text(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? " " : value)
            .font(emphasized ? patchsheetEmphasisFont : patchsheetRowFont)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, patchsheetCellVerticalPadding)
    }

    private func patchsheetValueButtonCell(_ value: String, width: CGFloat, emphasized: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            patchsheetValueCell(value, width: width, emphasized: emphasized)
        }
        .buttonStyle(.plain)
    }

    private func patchsheetNotesCell(for patch: PatchRow) -> some View {
        TextField("Notes", text: notesBinding(for: patch), axis: .vertical)
            .textFieldStyle(.plain)
            .font(patchsheetRowFont)
            .foregroundStyle(.primary)
            .lineLimit(1...3)
            .frame(width: patchsheetNotesColumnWidth, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, patchsheetCellVerticalPadding)
            .focused($focusedNotesPatchID, equals: patch.id)
            .disabled(!store.canEditPatchsheet)
            .onSubmit {
                saveNotes(forPatchID: patch.id)
            }
    }

    private func patchsheetNDICell(for patch: PatchRow) -> some View {
        Button {
            toggleNDI(for: patch)
        } label: {
            Image(systemName: patch.ndiEnabled ? "checkmark.square.fill" : "square")
                .foregroundStyle(canManageNDI ? (patch.ndiEnabled ? .green : .secondary) : .secondary)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: patchsheetNDIColumnWidth, alignment: .center)
                .padding(.vertical, patchsheetCellVerticalPadding)
        }
        .buttonStyle(.plain)
        .disabled(!canManageNDI)
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

    private var canSubmitNewPatch: Bool {
        !field1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submitNewPatch() {
        guard canSubmitNewPatch else { return }
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

    private func toggleNDI(for patch: PatchRow) {
        guard canManageNDI else { return }
        var updated = patch
        updated.ndiEnabled.toggle()
        store.savePatch(updated)
        if selectedPatch?.id == updated.id {
            selectedPatch = updated
        }
    }

    private func notesBinding(for patch: PatchRow) -> Binding<String> {
        Binding(
            get: {
                noteDrafts[patch.id] ?? patch.notes
            },
            set: { newValue in
                noteDrafts[patch.id] = newValue
            }
        )
    }

    private func saveNotes(forPatchID patchID: String) {
        guard store.canEditPatchsheet else { return }
        guard let patch = store.patchsheet.first(where: { $0.id == patchID }) else { return }
        let draft = (noteDrafts[patchID] ?? patch.notes).trimmingCharacters(in: .whitespacesAndNewlines)
        let current = patch.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard draft != current else { return }

        var updated = patch
        updated.notes = draft
        noteDrafts[patchID] = draft
        store.savePatch(updated)
        if selectedPatch?.id == updated.id {
            selectedPatch = updated
        }
    }
}

enum MacNDIOrientation: String, CaseIterable, Codable, Identifiable {
    case landscape
    case portrait

    var id: String { rawValue }

    var title: String {
        switch self {
        case .landscape: return "Landscape"
        case .portrait: return "Portrait"
        }
    }

    var outputSize: CGSize {
        switch self {
        case .landscape: return CGSize(width: 1920, height: 1080)
        case .portrait: return CGSize(width: 1080, height: 1920)
        }
    }

    var windowSize: CGSize {
        switch self {
        case .landscape: return CGSize(width: 1200, height: 720)
        case .portrait: return CGSize(width: 720, height: 1200)
        }
    }
}

enum MacNDIFeedSourceType: String, CaseIterable, Codable, Identifiable {
    case patchsheet
    case runOfShow
    case runOfShowLive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .patchsheet: return "Patchsheet"
        case .runOfShow: return "Run of Show"
        case .runOfShowLive: return "Run of Show Live"
        }
    }
}

struct MacNDIFeedConfiguration: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var title: String = "ProdConnect Feed"
    var sourceType: MacNDIFeedSourceType = .patchsheet
    var category: String = "Audio"
    var runOfShowID: String?
    var isLive = false
    var showsHeaders = true
    var scale = 1.2
    var orientation: MacNDIOrientation = .landscape

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case sourceType
        case category
        case runOfShowID
        case isLive
        case showsHeaders
        case scale
        case orientation
    }

    init(
        id: String = UUID().uuidString,
        title: String = "ProdConnect Feed",
        sourceType: MacNDIFeedSourceType = .patchsheet,
        category: String = "Audio",
        runOfShowID: String? = nil,
        isLive: Bool = false,
        showsHeaders: Bool = true,
        scale: Double = 1.2,
        orientation: MacNDIOrientation = .landscape
    ) {
        self.id = id
        self.title = title
        self.sourceType = sourceType
        self.category = category
        self.runOfShowID = runOfShowID
        self.isLive = isLive
        self.showsHeaders = showsHeaders
        self.scale = scale
        self.orientation = orientation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "ProdConnect Feed"
        sourceType = try container.decodeIfPresent(MacNDIFeedSourceType.self, forKey: .sourceType) ?? .patchsheet
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? "Audio"
        runOfShowID = try container.decodeIfPresent(String.self, forKey: .runOfShowID)
        isLive = try container.decodeIfPresent(Bool.self, forKey: .isLive) ?? false
        showsHeaders = try container.decodeIfPresent(Bool.self, forKey: .showsHeaders) ?? true
        scale = try container.decodeIfPresent(Double.self, forKey: .scale) ?? 1.2
        orientation = try container.decodeIfPresent(MacNDIOrientation.self, forKey: .orientation) ?? .landscape
    }
}

@MainActor
final class MacNDISettingsController: ObservableObject {
    @Published var feeds: [MacNDIFeedConfiguration] {
        didSet {
            persistFeeds()
            syncOutputs()
        }
    }

    @Published private(set) var previewVisibleFeedIDs: Set<String> = []

    private let store: ProdConnectStore
    private let userDefaults = UserDefaults.standard
    private let feedsDefaultsKey = "prodconnect.mac.ndiFeeds.v1"
    private var controllers: [String: MacPatchsheetNDIOutputWindowController] = [:]
    private var cancellables: Set<AnyCancellable> = []

    init(store: ProdConnectStore) {
        self.store = store
        self.feeds = Self.loadPersistedFeeds()

        store.$patchsheet
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncOutputs()
            }
            .store(in: &cancellables)

        store.$runOfShows
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncOutputs()
            }
            .store(in: &cancellables)

        store.$user
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncOutputs()
            }
            .store(in: &cancellables)

        syncOutputs()
    }

    var runtimeAvailable: Bool {
        MacNDISender.isRuntimeAvailable
    }

    var hasNDIFeature: Bool {
        guard let user = store.user else { return false }
        return user.normalizedSubscriptionTier != "free"
    }

    var canManageNDI: Bool {
        guard let user = store.user else { return false }
        return hasNDIFeature && (user.isAdmin || user.isOwner)
    }

    func addFeed() {
        feeds.append(
            MacNDIFeedConfiguration(
                title: "ProdConnect Feed \(feeds.count + 1)",
                category: "Audio"
            )
        )
    }

    func removeFeed(id: String) {
        feeds.removeAll { $0.id == id }
        if let controller = controllers.removeValue(forKey: id) {
            controller.close()
        }
        previewVisibleFeedIDs.remove(id)
    }

    func togglePreview(for feedID: String) {
        let controller = controller(for: feedID)
        if controller.isWindowVisible {
            controller.hideWindow()
            previewVisibleFeedIDs.remove(feedID)
        } else {
            controller.showWindow()
            previewVisibleFeedIDs.insert(feedID)
        }
    }

    func isPreviewVisible(for feedID: String) -> Bool {
        previewVisibleFeedIDs.contains(feedID)
    }

    func updateFeedValue<Value>(_ value: Value, at index: Int, keyPath: WritableKeyPath<MacNDIFeedConfiguration, Value>) {
        guard feeds.indices.contains(index) else { return }
        DispatchQueue.main.async {
            guard self.feeds.indices.contains(index) else { return }
            self.feeds[index][keyPath: keyPath] = value
        }
    }

    func updateRunOfShowID(_ runOfShowID: String?, at index: Int) {
        guard feeds.indices.contains(index) else { return }
        let normalizedID = runOfShowID?.isEmpty == true ? nil : runOfShowID
        DispatchQueue.main.async {
            guard self.feeds.indices.contains(index) else { return }
            self.feeds[index].runOfShowID = normalizedID
        }
    }

    func patches(for category: String) -> [PatchRow] {
        store.patchsheet
            .filter { $0.category == category && $0.ndiEnabled }
            .sorted(by: PatchRow.autoSort)
    }

    func runOfShows() -> [RunOfShowDocument] {
        store.runOfShows.sorted { $0.updatedAt > $1.updatedAt }
    }

    func runOfShow(for feed: MacNDIFeedConfiguration) -> RunOfShowDocument? {
        let shows = runOfShows()
        if let runOfShowID = feed.runOfShowID,
           let matched = shows.first(where: { $0.id == runOfShowID }) {
            return matched
        }
        return shows.first
    }

    func descriptorText(for feed: MacNDIFeedConfiguration) -> String {
        switch feed.sourceType {
        case .patchsheet:
            return "\(patches(for: feed.category).count) selected patches in \(feed.category)"
        case .runOfShow:
            let show = runOfShow(for: feed)
            let title = show?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return "\(show?.sortedItems.count ?? 0) items in \(title.isEmpty ? "selected show" : title)"
        case .runOfShowLive:
            let show = runOfShow(for: feed)
            let title = show?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return "Live view for \(title.isEmpty ? "selected show" : title)"
        }
    }

    func syncOutputs() {
        let validIDs = Set(feeds.map(\.id))

        for (id, controller) in controllers where !validIDs.contains(id) {
            controller.close()
            controllers.removeValue(forKey: id)
        }

        guard canManageNDI else {
            for controller in controllers.values {
                controller.close()
            }
            previewVisibleFeedIDs = []
            return
        }

        for feed in feeds {
            controller(for: feed.id).update(
                configuration: MacPatchsheetNDIOutputConfiguration(
                    isActive: feed.isLive,
                    title: feed.title,
                    sourceType: feed.sourceType,
                    category: feed.category,
                    runOfShow: runOfShow(for: feed),
                    patches: patches(for: feed.category),
                    nameColumnTitle: Self.nameColumnTitle(for: feed.category),
                    inputColumnTitle: Self.inputColumnTitle(for: feed.category),
                    outputColumnTitle: Self.outputColumnTitle(for: feed.category),
                    showsUniverseColumn: feed.category == "Lighting",
                    showsHeaders: feed.showsHeaders,
                    scale: feed.scale,
                    orientation: feed.orientation
                )
            )
        }

        let visibleFeedIDs = Set(
            controllers.compactMap { id, controller in
                controller.isWindowVisible ? id : nil
            }
        )
        if previewVisibleFeedIDs != visibleFeedIDs {
            DispatchQueue.main.async {
                self.previewVisibleFeedIDs = visibleFeedIDs
            }
        }
    }

    private func controller(for feedID: String) -> MacPatchsheetNDIOutputWindowController {
        if let existing = controllers[feedID] {
            return existing
        }
        let controller = MacPatchsheetNDIOutputWindowController()
        controllers[feedID] = controller
        return controller
    }

    private func persistFeeds() {
        guard let data = try? JSONEncoder().encode(feeds) else { return }
        userDefaults.set(data, forKey: feedsDefaultsKey)
    }

    private static func loadPersistedFeeds() -> [MacNDIFeedConfiguration] {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "prodconnect.mac.ndiFeeds.v1"),
           let decoded = try? JSONDecoder().decode([MacNDIFeedConfiguration].self, from: data),
           !decoded.isEmpty {
            return decoded
        }

        let legacyTitle = defaults.string(forKey: "prodconnect.mac.patchsheet.ndiOutputName") ?? "ProdConnect Patchsheet"
        let legacyLive = defaults.bool(forKey: "prodconnect.mac.patchsheet.ndiPreviewEnabled")
        let legacyHeaders = defaults.object(forKey: "prodconnect.mac.patchsheet.ndiShowsHeaders") as? Bool ?? true
        let legacyScale = defaults.object(forKey: "prodconnect.mac.patchsheet.ndiPreviewScale") as? Double ?? 1.0

        return [
            MacNDIFeedConfiguration(
                title: legacyTitle,
                category: "Audio",
                isLive: legacyLive,
                showsHeaders: legacyHeaders,
                scale: legacyScale
            )
        ]
    }

    static func nameColumnTitle(for category: String) -> String {
        category == "Lighting" ? "Fixture" : "Name"
    }

    static func inputColumnTitle(for category: String) -> String {
        switch category {
        case "Video": return "Source"
        case "Lighting": return "DMX Channel"
        default: return "Input"
        }
    }

    static func outputColumnTitle(for category: String) -> String {
        switch category {
        case "Video": return "Destination"
        case "Lighting": return "Channel Count"
        default: return "Output"
        }
    }
}

enum MacRunOfShowMIDIMessageType: String, CaseIterable, Identifiable, Codable {
    case noteOn = "Note"
    case controlChange = "CC"

    var id: String { rawValue }
}

enum MacRunOfShowMIDIAction: String, CaseIterable, Identifiable {
    case startRestart = "Start / Restart"
    case previous = "Previous"
    case next = "Next"
    case reset = "Reset"

    var id: String { rawValue }
}

struct MacRunOfShowMIDIMapping: Codable, Equatable {
    var messageType: MacRunOfShowMIDIMessageType = .noteOn
    var channel: Int = 1
    var value: Int = 0
    var velocity: Int = 127

    enum CodingKeys: String, CodingKey {
        case messageType
        case channel
        case value
        case velocity
    }

    init(
        messageType: MacRunOfShowMIDIMessageType = .noteOn,
        channel: Int = 1,
        value: Int = 0,
        velocity: Int = 127
    ) {
        self.messageType = messageType
        self.channel = channel
        self.value = value
        self.velocity = velocity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        messageType = try container.decodeIfPresent(MacRunOfShowMIDIMessageType.self, forKey: .messageType) ?? .noteOn
        channel = try container.decodeIfPresent(Int.self, forKey: .channel) ?? 1
        value = try container.decodeIfPresent(Int.self, forKey: .value) ?? 0
        velocity = try container.decodeIfPresent(Int.self, forKey: .velocity) ?? 127
    }
}

struct MacMIDISourceDescriptor: Identifiable, Equatable {
    let id: String
    let uniqueID: MIDIUniqueID
    let name: String
}

@MainActor
final class MacRunOfShowControlController: ObservableObject {
    @Published var selectedShowID: String? {
        didSet { userDefaults.set(selectedShowID, forKey: selectedShowDefaultsKey) }
    }
    @Published var midiEnabled: Bool {
        didSet { userDefaults.set(midiEnabled, forKey: midiEnabledDefaultsKey) }
    }
    @Published var selectedMIDISourceID: String? {
        didSet {
            userDefaults.set(selectedMIDISourceID, forKey: selectedMIDISourceDefaultsKey)
#if canImport(CoreMIDI)
            refreshMIDISourceConnection()
#endif
        }
    }
    @Published var startRestartMapping: MacRunOfShowMIDIMapping {
        didSet { persistMappings() }
    }
    @Published var previousMapping: MacRunOfShowMIDIMapping {
        didSet { persistMappings() }
    }
    @Published var nextMapping: MacRunOfShowMIDIMapping {
        didSet { persistMappings() }
    }
    @Published var resetMapping: MacRunOfShowMIDIMapping {
        didSet { persistMappings() }
    }
    @Published var listeningAction: MacRunOfShowMIDIAction?

    private let store: ProdConnectStore
    private let userDefaults = UserDefaults.standard
    private let selectedShowDefaultsKey = "prodconnect.mac.runOfShow.selectedShowID"
    private let midiEnabledDefaultsKey = "prodconnect.mac.runOfShow.midiEnabled"
    private let selectedMIDISourceDefaultsKey = "prodconnect.mac.runOfShow.selectedMIDISourceID"
    private let mappingDefaultsKey = "prodconnect.mac.runOfShow.midiMappings.v1"
    private var autoStartTimer: Timer?
    private var autoStartSuppressedShowIDs: Set<String> = []

#if canImport(CoreMIDI)
    private var midiClient = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var connectedSourceID: MIDIUniqueID?
#endif

    init(store: ProdConnectStore) {
        self.store = store
        self.selectedShowID = userDefaults.string(forKey: selectedShowDefaultsKey)
        self.midiEnabled = userDefaults.bool(forKey: midiEnabledDefaultsKey)
        self.selectedMIDISourceID = userDefaults.string(forKey: selectedMIDISourceDefaultsKey)

        let persistedMappings = Self.loadPersistedMappings(userDefaults: userDefaults)
        self.startRestartMapping = persistedMappings[.startRestart] ?? MacRunOfShowMIDIMapping(messageType: .noteOn, channel: 1, value: 20)
        self.previousMapping = persistedMappings[.previous] ?? MacRunOfShowMIDIMapping(messageType: .noteOn, channel: 1, value: 21)
        self.nextMapping = persistedMappings[.next] ?? MacRunOfShowMIDIMapping(messageType: .noteOn, channel: 1, value: 22)
        self.resetMapping = persistedMappings[.reset] ?? MacRunOfShowMIDIMapping(messageType: .noteOn, channel: 1, value: 23)
        self.listeningAction = nil

        startAutoStartTimer()
#if canImport(CoreMIDI)
        configureMIDI()
#endif
    }

    deinit {
        autoStartTimer?.invalidate()
#if canImport(CoreMIDI)
        if inputPort != 0 { MIDIPortDispose(inputPort) }
        if midiClient != 0 { MIDIClientDispose(midiClient) }
#endif
    }

    var shows: [RunOfShowDocument] {
        store.runOfShows.sorted { $0.updatedAt > $1.updatedAt }
    }

    var selectedShow: RunOfShowDocument? {
        if let selectedShowID,
           let show = shows.first(where: { $0.id == selectedShowID }) {
            return show
        }
        return shows.first
    }

    var midiSourceCount: Int {
#if canImport(CoreMIDI)
        midiSources.count
#else
        0
#endif
    }

    var midiSources: [MacMIDISourceDescriptor] {
#if canImport(CoreMIDI)
        var result: [MacMIDISourceDescriptor] = []
        let sourceCount = MIDIGetNumberOfSources()
        for index in 0..<sourceCount {
            let source = MIDIGetSource(index)
            var sourceID = MIDIUniqueID()
            guard MIDIObjectGetIntegerProperty(source, kMIDIPropertyUniqueID, &sourceID) == noErr else { continue }
            let name = midiSourceName(for: source) ?? "MIDI Source \(index + 1)"
            result.append(MacMIDISourceDescriptor(id: String(sourceID), uniqueID: sourceID, name: name))
        }
        return result
#else
        return []
#endif
    }

    var canManageControls: Bool {
        guard let user = store.user else { return false }
        return user.hasPaidSubscription && (user.isAdmin || user.isOwner)
    }

    func binding(for action: MacRunOfShowMIDIAction) -> Binding<MacRunOfShowMIDIMapping> {
        Binding(
            get: { self.mapping(for: action) },
            set: { self.setMapping($0, for: action) }
        )
    }

    func updateSelectedShowID(_ id: String) {
        selectedShowID = id.isEmpty ? nil : id
    }

    func updateSelectedMIDISourceID(_ id: String) {
        selectedMIDISourceID = id.isEmpty ? nil : id
    }

    func updateAutoStart(_ enabled: Bool, for show: RunOfShowDocument) {
        guard canManageControls else { return }
        var updatedShow = show
        updatedShow.autoStartLive = enabled
        if !enabled {
            autoStartSuppressedShowIDs.remove(show.id)
        }
        store.saveRunOfShow(updatedShow)
    }

    func suppressAutoStart(for showID: String) {
        autoStartSuppressedShowIDs.insert(showID)
    }

    func clearAutoStartSuppression(for showID: String) {
        autoStartSuppressedShowIDs.remove(showID)
    }

    func isAutoStartSuppressed(for showID: String) -> Bool {
        autoStartSuppressedShowIDs.contains(showID)
    }

    func toggleListening(for action: MacRunOfShowMIDIAction) {
        listeningAction = listeningAction == action ? nil : action
    }

    func isListening(for action: MacRunOfShowMIDIAction) -> Bool {
        listeningAction == action
    }

    private func mapping(for action: MacRunOfShowMIDIAction) -> MacRunOfShowMIDIMapping {
        switch action {
        case .startRestart: return startRestartMapping
        case .previous: return previousMapping
        case .next: return nextMapping
        case .reset: return resetMapping
        }
    }

    private func setMapping(_ mapping: MacRunOfShowMIDIMapping, for action: MacRunOfShowMIDIAction) {
        let normalized = MacRunOfShowMIDIMapping(
            messageType: mapping.messageType,
            channel: min(max(mapping.channel, 1), 16),
            value: min(max(mapping.value, 0), 127),
            velocity: min(max(mapping.velocity, 0), 127)
        )
        switch action {
        case .startRestart: startRestartMapping = normalized
        case .previous: previousMapping = normalized
        case .next: nextMapping = normalized
        case .reset: resetMapping = normalized
        }
    }

    private func persistMappings() {
        let mappings: [String: MacRunOfShowMIDIMapping] = [
            MacRunOfShowMIDIAction.startRestart.rawValue: startRestartMapping,
            MacRunOfShowMIDIAction.previous.rawValue: previousMapping,
            MacRunOfShowMIDIAction.next.rawValue: nextMapping,
            MacRunOfShowMIDIAction.reset.rawValue: resetMapping
        ]
        guard let data = try? JSONEncoder().encode(mappings) else { return }
        userDefaults.set(data, forKey: mappingDefaultsKey)
    }

    private static func loadPersistedMappings(userDefaults: UserDefaults) -> [MacRunOfShowMIDIAction: MacRunOfShowMIDIMapping] {
        guard let data = userDefaults.data(forKey: "prodconnect.mac.runOfShow.midiMappings.v1"),
              let decoded = try? JSONDecoder().decode([String: MacRunOfShowMIDIMapping].self, from: data) else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
            guard let action = MacRunOfShowMIDIAction(rawValue: key) else { return nil }
            return (action, value)
        })
    }

    private func startAutoStartTimer() {
        autoStartTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.performAutoStartIfNeeded()
            }
        }
        if let autoStartTimer {
            RunLoop.main.add(autoStartTimer, forMode: .common)
        }
    }

    private func performAutoStartIfNeeded() {
        guard canManageControls else { return }
        let now = Date()
        for show in shows where show.autoStartLive && !autoStartSuppressedShowIDs.contains(show.id) && !show.isLiveActive && show.liveCurrentItemID == nil && !show.sortedItems.isEmpty && now >= show.scheduledStart {
            startOrRestart(show)
        }
    }

    private func startOrRestart(_ show: RunOfShowDocument) {
        autoStartSuppressedShowIDs.remove(show.id)
        var updated = show
        let items = updated.sortedItems
        guard let first = items.first else { return }
        let now = Date()
        updated.isLiveActive = true
        updated.liveCurrentItemID = first.id
        updated.liveShowStartedAt = now
        updated.liveItemStartedAt = now
        store.saveRunOfShow(updated)
    }

    private func move(_ show: RunOfShowDocument, direction: Int) {
        var updated = show
        let items = updated.sortedItems
        guard let currentIndex = updated.itemIndex(for: updated.liveCurrentItemID) else { return }
        let newIndex = currentIndex + direction
        guard items.indices.contains(newIndex) else { return }
        updated.isLiveActive = true
        updated.liveCurrentItemID = items[newIndex].id
        updated.liveItemStartedAt = Date()
        if updated.liveShowStartedAt == nil {
            updated.liveShowStartedAt = Date()
        }
        store.saveRunOfShow(updated)
    }

    private func reset(_ show: RunOfShowDocument) {
        autoStartSuppressedShowIDs.insert(show.id)
        var updated = show
        updated.isLiveActive = false
        updated.liveCurrentItemID = nil
        updated.liveShowStartedAt = nil
        updated.liveItemStartedAt = nil
        store.saveRunOfShow(updated)
    }

    private func perform(action: MacRunOfShowMIDIAction) {
        guard midiEnabled, canManageControls, let show = selectedShow else { return }
        switch action {
        case .startRestart:
            startOrRestart(show)
        case .previous:
            move(show, direction: -1)
        case .next:
            move(show, direction: 1)
        case .reset:
            reset(show)
        }
    }

#if canImport(CoreMIDI)
    private func configureMIDI() {
        MIDIClientCreateWithBlock("ProdConnect Run Of Show MIDI" as CFString, &midiClient) { _ in }
        MIDIInputPortCreateWithBlock(midiClient, "ProdConnect Input" as CFString, &inputPort) { [weak self] packetList, _ in
            guard let self else { return }
            self.handle(packetList: packetList)
        }
        if selectedMIDISourceID == nil {
            selectedMIDISourceID = midiSources.first?.id
        }
        refreshMIDISourceConnection()
    }

    private func refreshMIDISourceConnection() {
        if let connectedSourceID,
           let source = midiSourceRef(for: connectedSourceID) {
            MIDIPortDisconnectSource(inputPort, source)
            self.connectedSourceID = nil
        }

        guard let selectedMIDISourceID,
              let parsedUniqueID = Int32(selectedMIDISourceID),
              let selectedUniqueID = MIDIUniqueID(exactly: parsedUniqueID),
              let source = midiSourceRef(for: selectedUniqueID) else { return }

        MIDIPortConnectSource(inputPort, source, nil)
        connectedSourceID = selectedUniqueID
    }

    private func handle(packetList: UnsafePointer<MIDIPacketList>) {
        var packet = packetList.pointee.packet
        for _ in 0..<packetList.pointee.numPackets {
            let length = Int(packet.length)
            let bytes = withUnsafeBytes(of: packet.data) { rawBuffer in
                Array(rawBuffer.prefix(length))
            }
            handle(bytes: bytes)
            packet = MIDIPacketNext(&packet).pointee
        }
    }

    private func handle(bytes: [UInt8]) {
        guard bytes.count >= 3 else { return }
        let status = bytes[0]
        let type = status & 0xF0
        let channel = Int((status & 0x0F) + 1)
        let number = Int(bytes[1])
        let velocity = Int(bytes[2])

        let messageType: MacRunOfShowMIDIMessageType?
        switch type {
        case 0x90 where velocity > 0:
            messageType = .noteOn
        case 0xB0:
            messageType = .controlChange
        default:
            messageType = nil
        }

        guard let messageType else { return }

        if let listeningAction {
            let learnedMapping = MacRunOfShowMIDIMapping(
                messageType: messageType,
                channel: channel,
                value: number,
                velocity: velocity
            )
            Task { @MainActor in
                self.setMapping(learnedMapping, for: listeningAction)
                self.listeningAction = nil
            }
            return
        }

        let matchedAction: MacRunOfShowMIDIAction?
        matchedAction = self.action(for: messageType, channel: channel, value: number, velocity: velocity)

        guard let matchedAction else { return }
        Task { @MainActor in
            self.perform(action: matchedAction)
        }
    }

    private func midiSourceRef(for uniqueID: MIDIUniqueID) -> MIDIEndpointRef? {
        let sourceCount = MIDIGetNumberOfSources()
        for index in 0..<sourceCount {
            let source = MIDIGetSource(index)
            var sourceID = MIDIUniqueID()
            guard MIDIObjectGetIntegerProperty(source, kMIDIPropertyUniqueID, &sourceID) == noErr else { continue }
            if sourceID == uniqueID {
                return source
            }
        }
        return nil
    }

    private func midiSourceName(for source: MIDIEndpointRef) -> String? {
        var unmanagedName: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(source, kMIDIPropertyDisplayName, &unmanagedName) == noErr
                || MIDIObjectGetStringProperty(source, kMIDIPropertyName, &unmanagedName) == noErr else {
            return nil
        }
        return unmanagedName?.takeRetainedValue() as String?
    }
#endif

    private func action(for messageType: MacRunOfShowMIDIMessageType, channel: Int, value: Int, velocity: Int) -> MacRunOfShowMIDIAction? {
        for action in MacRunOfShowMIDIAction.allCases {
            let mapping = mapping(for: action)
            if mapping.messageType == messageType
                && mapping.channel == channel
                && mapping.value == value
                && mapping.velocity == velocity {
                return action
            }
        }
        return nil
    }
}

struct MacSettingsView: View {
    @EnvironmentObject private var store: ProdConnectStore
    @EnvironmentObject private var ndiSettings: MacNDISettingsController
    @EnvironmentObject private var runOfShowControls: MacRunOfShowControlController
    @State private var selectedSection: MacSettingsSection = .integrations

    private let categories = ["Audio", "Video", "Lighting"]
    private let sourceTypes = MacNDIFeedSourceType.allCases

    private var hasNDIFeature: Bool {
        guard let user = store.user else { return false }
        return user.normalizedSubscriptionTier != "free"
    }

    private var canManageNDI: Bool {
        guard let user = store.user else { return false }
        return hasNDIFeature && (user.isAdmin || user.isOwner)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Settings")
                    .font(.system(size: 28, weight: .bold))

                settingsTabBar
                selectedSectionContent
            }
            .padding(20)
        }
        .frame(minWidth: 860, minHeight: 620)
    }

    private var settingsTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(MacSettingsSection.allCases) { section in
                    Button {
                        selectedSection = section
                    } label: {
                        Text(section.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(selectedSection == section ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
                            .foregroundStyle(selectedSection == section ? Color.accentColor : Color.primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var selectedSectionContent: some View {
        switch selectedSection {
        case .importData, .locationsRooms, .tickets, .integrations:
            MacCustomizeView(section: selectedSection)
                .environmentObject(store)
        case .ndi:
            if !hasNDIFeature {
                Text("NDI settings are available on paid subscriptions.")
                    .foregroundStyle(.secondary)
            } else {
                ndiSettingsSection
            }
        case .midi:
            if !hasNDIFeature {
                Text("Run of Show Live MIDI controls are available on paid subscriptions.")
                    .foregroundStyle(.secondary)
            } else {
                runOfShowControlsSection
            }
        case .users:
            MacUsersView()
                .environmentObject(store)
        }
    }

    private var runOfShowControlsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Run of Show Live Controls")
                .font(.title2.weight(.semibold))

            if runOfShowControls.shows.isEmpty {
                Text("Create a Run of Show first to configure auto-start and MIDI control.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker(
                            "Controlled Show",
                            selection: Binding(
                                get: { runOfShowControls.selectedShowID ?? runOfShowControls.shows.first?.id ?? "" },
                                set: { runOfShowControls.updateSelectedShowID($0) }
                            )
                        ) {
                            ForEach(runOfShowControls.shows) { show in
                                Text(show.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Show" : show.title)
                                    .tag(show.id)
                            }
                        }
                        .disabled(!runOfShowControls.canManageControls)

                        Toggle("Enable MIDI control", isOn: $runOfShowControls.midiEnabled)
                            .disabled(!runOfShowControls.canManageControls)

                        Picker(
                            "MIDI Input",
                            selection: Binding(
                                get: { runOfShowControls.selectedMIDISourceID ?? runOfShowControls.midiSources.first?.id ?? "" },
                                set: { runOfShowControls.updateSelectedMIDISourceID($0) }
                            )
                        ) {
                            if runOfShowControls.midiSources.isEmpty {
                                Text("No MIDI Devices").tag("")
                            }
                            ForEach(runOfShowControls.midiSources) { source in
                                Text(source.name).tag(source.id)
                            }
                        }
                        .disabled(!runOfShowControls.canManageControls || runOfShowControls.midiSources.isEmpty)

                        Text("Listening to \(runOfShowControls.midiSourceCount) available MIDI source\(runOfShowControls.midiSourceCount == 1 ? "" : "s"). The selected device triggers Start/Restart, Previous, Next, and Reset.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        midiMappingEditor(title: "Start / Restart", action: .startRestart)
                        midiMappingEditor(title: "Previous", action: .previous)
                        midiMappingEditor(title: "Next", action: .next)
                        midiMappingEditor(title: "Reset", action: .reset)
                    }
                    .disabled(!runOfShowControls.canManageControls)
                } label: {
                    Text("Live Automation")
                        .font(.headline)
                }
            }
        }
    }

    private var ndiSettingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NDI Outputs")
                        .font(.title2.weight(.semibold))
                    Text("Each feed can target Patchsheet, Run of Show, or Run of Show Live.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Add Feed") {
                    ndiSettings.addFeed()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canManageNDI)
            }

            if !canManageNDI {
                Text("Only admins and owners can manage NDI settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !ndiSettings.runtimeAvailable {
                Text("NDI runtime is unavailable in this build. Preview windows work, but network NDI output stays disabled until the bundled runtime is present.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(ndiSettings.feeds.enumerated()), id: \.element.id) { index, feed in
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            TextField("Feed Name", text: feedBinding(index, \.title))
                                .textFieldStyle(.roundedBorder)
                            Picker("Source", selection: feedBinding(index, \.sourceType)) {
                                ForEach(sourceTypes) { sourceType in
                                    Text(sourceType.title).tag(sourceType)
                                }
                            }
                            .frame(width: 140)
                            if feed.sourceType == .patchsheet {
                                Picker("Category", selection: feedBinding(index, \.category)) {
                                    ForEach(categories, id: \.self) { category in
                                        Text(category).tag(category)
                                    }
                                }
                                .frame(width: 140)
                            } else {
                                Picker(
                                    "Show",
                                    selection: runOfShowBinding(for: index, feed: feed)
                                ) {
                                    if ndiSettings.runOfShows().isEmpty {
                                        Text("No Run of Show").tag("")
                                    }
                                    ForEach(ndiSettings.runOfShows()) { show in
                                        Text(show.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Show" : show.title)
                                            .tag(show.id)
                                    }
                                }
                                .frame(width: 220)
                            }
                            Button("Remove") {
                                ndiSettings.removeFeed(id: feed.id)
                            }
                            .buttonStyle(.bordered)
                            .disabled(!canManageNDI || ndiSettings.feeds.count == 1)
                        }

                        HStack(spacing: 14) {
                            Toggle("Live", isOn: feedBinding(index, \.isLive))
                            Toggle("Show Headers", isOn: feedBinding(index, \.showsHeaders))
                            Picker("Orientation", selection: feedBinding(index, \.orientation)) {
                                ForEach(MacNDIOrientation.allCases) { orientation in
                                    Text(orientation.title).tag(orientation)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 220)
                        }

                        HStack {
                            Text("Preview Scale")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Slider(value: feedBinding(index, \.scale), in: 0.9...2.2, step: 0.05)
                            Text("\(Int((feed.scale * 100).rounded()))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 48, alignment: .trailing)
                        }

                        HStack {
                            Text(ndiSettings.descriptorText(for: feed))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(ndiSettings.isPreviewVisible(for: feed.id) ? "Hide Preview" : "Show Preview") {
                                ndiSettings.togglePreview(for: feed.id)
                            }
                            .buttonStyle(.bordered)
                        }

                        ndiPreview(for: feed)
                        .frame(height: feed.orientation == .portrait ? 320 : 240)
                    }
                    .disabled(!canManageNDI)
                } label: {
                    Text("Feed \(index + 1)")
                        .font(.headline)
                }
            }
        }
    }

    private func midiMappingEditor(title: String, action: MacRunOfShowMIDIAction) -> some View {
        let binding = runOfShowControls.binding(for: action)
        let messageNumberLabel = binding.wrappedValue.messageType == .noteOn ? "Note #\(binding.wrappedValue.value)" : "CC #\(binding.wrappedValue.value)"
        let velocityLabel = "Velocity \(binding.wrappedValue.velocity)"
        return HStack(spacing: 12) {
            Text(title)
                .frame(width: 120, alignment: .leading)
            Picker("Type", selection: Binding(
                get: { binding.wrappedValue.messageType },
                set: { newValue in
                    var updated = binding.wrappedValue
                    updated.messageType = newValue
                    binding.wrappedValue = updated
                }
            )) {
                ForEach(MacRunOfShowMIDIMessageType.allCases) { messageType in
                    Text(messageType.rawValue).tag(messageType)
                }
            }
            .frame(width: 90)

            Stepper(
                "Ch \(binding.wrappedValue.channel)",
                value: Binding(
                    get: { binding.wrappedValue.channel },
                    set: { newValue in
                        var updated = binding.wrappedValue
                        updated.channel = newValue
                        binding.wrappedValue = updated
                    }
                ),
                in: 1...16
            )
            .frame(width: 120)

            Stepper(
                messageNumberLabel,
                value: Binding(
                    get: { binding.wrappedValue.value },
                    set: { newValue in
                        var updated = binding.wrappedValue
                        updated.value = newValue
                        binding.wrappedValue = updated
                    }
                ),
                in: 0...127
            )
            .frame(width: 120)

            Stepper(
                velocityLabel,
                value: Binding(
                    get: { binding.wrappedValue.velocity },
                    set: { newValue in
                        var updated = binding.wrappedValue
                        updated.velocity = newValue
                        binding.wrappedValue = updated
                    }
                ),
                in: 0...127
            )
            .frame(width: 128)

            Button(runOfShowControls.isListening(for: action) ? "Listening..." : "Listen") {
                runOfShowControls.toggleListening(for: action)
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
    }

    private func feedBinding<Value>(_ index: Int, _ keyPath: WritableKeyPath<MacNDIFeedConfiguration, Value>) -> Binding<Value> {
        Binding(
            get: { ndiSettings.feeds[index][keyPath: keyPath] },
            set: { ndiSettings.updateFeedValue($0, at: index, keyPath: keyPath) }
        )
    }

    private func runOfShowBinding(for index: Int, feed: MacNDIFeedConfiguration) -> Binding<String> {
        Binding(
            get: { feed.runOfShowID ?? ndiSettings.runOfShows().first?.id ?? "" },
            set: { newValue in
                ndiSettings.updateRunOfShowID(newValue, at: index)
            }
        )
    }

    @ViewBuilder
    private func ndiPreview(for feed: MacNDIFeedConfiguration) -> some View {
        switch feed.sourceType {
        case .patchsheet:
            MacPatchsheetNDIPreview(
                patches: ndiSettings.patches(for: feed.category),
                category: feed.category,
                outputName: feed.title,
                nameColumnTitle: MacNDISettingsController.nameColumnTitle(for: feed.category),
                inputColumnTitle: MacNDISettingsController.inputColumnTitle(for: feed.category),
                outputColumnTitle: MacNDISettingsController.outputColumnTitle(for: feed.category),
                showsUniverseColumn: feed.category == "Lighting",
                showsHeaders: feed.showsHeaders,
                isActive: feed.isLive,
                scale: min(feed.scale, 1.0)
            )
        case .runOfShow:
            MacRunOfShowNDIPreview(
                show: ndiSettings.runOfShow(for: feed),
                outputName: feed.title,
                isActive: feed.isLive,
                scale: min(feed.scale, 1.0)
            )
        case .runOfShowLive:
            MacRunOfShowLiveNDIPreview(
                show: ndiSettings.runOfShow(for: feed),
                outputName: feed.title,
                isActive: feed.isLive,
                scale: min(feed.scale, 1.0),
                now: Date()
            )
        }
    }
}

private struct MacPatchsheetNDIOutputConfiguration {
    let isActive: Bool
    let title: String
    let sourceType: MacNDIFeedSourceType
    let category: String
    let runOfShow: RunOfShowDocument?
    let patches: [PatchRow]
    let nameColumnTitle: String
    let inputColumnTitle: String
    let outputColumnTitle: String
    let showsUniverseColumn: Bool
    let showsHeaders: Bool
    let scale: Double
    let orientation: MacNDIOrientation
}

@MainActor
private final class MacPatchsheetNDIOutputWindowController {
    private var window: NSWindow?
    private var currentConfiguration: MacPatchsheetNDIOutputConfiguration?
    private var frameTimer: Timer?
    private let sender = MacNDISender()
    var isWindowVisible: Bool { window != nil }

    func update(configuration: MacPatchsheetNDIOutputConfiguration) {
        currentConfiguration = configuration

        let resolvedTitle = configuration.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "ProdConnect Patchsheet"
            : configuration.title.trimmingCharacters(in: .whitespacesAndNewlines)

        if configuration.isActive {
            sender.updateOutputName(resolvedTitle)
            startFrameTimerIfNeeded()
            sendCurrentFrameIfPossible()
        } else {
            frameTimer?.invalidate()
            frameTimer = nil
            sender.stop()
        }

        refreshWindowIfVisible()
    }

    func showWindow() {
        refreshWindowIfVisible(forceCreate: true)
    }

    func hideWindow() {
        window?.close()
        window = nil
    }

    func close() {
        frameTimer?.invalidate()
        frameTimer = nil
        currentConfiguration = nil
        sender.stop()
        hideWindow()
    }

    private func refreshWindowIfVisible(forceCreate: Bool = false) {
        guard let currentConfiguration else { return }
        guard forceCreate || window != nil else { return }

        let resolvedTitle = currentConfiguration.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "ProdConnect Patchsheet"
            : currentConfiguration.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let windowSize = currentConfiguration.orientation.windowSize

        let rootView = outputPreviewView(for: currentConfiguration, title: resolvedTitle)
            .frame(minWidth: windowSize.width, minHeight: windowSize.height)

        if window == nil {
            let newWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: windowSize.width, height: windowSize.height),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            newWindow.center()
            newWindow.isReleasedWhenClosed = false
            newWindow.titleVisibility = .visible
            newWindow.titlebarAppearsTransparent = true
            newWindow.backgroundColor = .black
            newWindow.contentView = NSHostingView(rootView: rootView)
            newWindow.makeKeyAndOrderFront(nil)
            window = newWindow
        } else {
            window?.setContentSize(windowSize)
            window?.contentView = NSHostingView(rootView: rootView)
            window?.makeKeyAndOrderFront(nil)
        }

        window?.title = resolvedTitle
    }

    private func outputPreviewView(for configuration: MacPatchsheetNDIOutputConfiguration, title: String) -> some View {
        Group {
            switch configuration.sourceType {
            case .patchsheet:
                MacPatchsheetNDIPreview(
                    patches: configuration.patches,
                    category: configuration.category,
                    outputName: title,
                    nameColumnTitle: configuration.nameColumnTitle,
                    inputColumnTitle: configuration.inputColumnTitle,
                    outputColumnTitle: configuration.outputColumnTitle,
                    showsUniverseColumn: configuration.showsUniverseColumn,
                    showsHeaders: configuration.showsHeaders,
                    isActive: sender.isReadyToSend,
                    scale: configuration.scale
                )
            case .runOfShow:
                MacRunOfShowNDIPreview(
                    show: configuration.runOfShow,
                    outputName: title,
                    isActive: sender.isReadyToSend,
                    scale: configuration.scale
                )
            case .runOfShowLive:
                MacRunOfShowLiveNDIPreview(
                    show: configuration.runOfShow,
                    outputName: title,
                    isActive: sender.isReadyToSend,
                    scale: configuration.scale,
                    now: Date()
                )
            }
        }
    }

    private func startFrameTimerIfNeeded() {
        guard frameTimer == nil else { return }
        frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 12.0, repeats: true) { [weak self] _ in
            guard let controller = self else { return }
            Task { @MainActor [controller] in
                controller.sendCurrentFrameIfPossible()
            }
        }
        if let frameTimer {
            RunLoop.main.add(frameTimer, forMode: .common)
        }
    }

    private func sendCurrentFrameIfPossible() {
        guard sender.isReadyToSend, let currentConfiguration else { return }
        let resolvedTitle = currentConfiguration.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "ProdConnect Patchsheet"
            : currentConfiguration.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let outputSize = currentConfiguration.orientation.outputSize
        let preview = outputPreviewView(for: currentConfiguration, title: resolvedTitle)
            .frame(width: outputSize.width, height: outputSize.height)
        guard let image = MacNDIRenderer.snapshot(of: preview, size: outputSize) else { return }
        sender.send(image: image)
    }
}

private enum MacNDIRenderer {
    @MainActor
    static func snapshot<Content: View>(of view: Content, size: CGSize) -> CGImage? {
        let renderer = ImageRenderer(
            content: view
                .frame(width: size.width, height: size.height)
        )
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0
        return renderer.cgImage
    }
}

private struct NDISendCreateSettings {
    var p_ndi_name: UnsafePointer<CChar>?
    var p_groups: UnsafePointer<CChar>?
    var clock_video: UInt8
    var clock_audio: UInt8
}

private struct NDIVideoFrameV2 {
    var xres: Int32
    var yres: Int32
    var FourCC: UInt32
    var frame_rate_N: Int32
    var frame_rate_D: Int32
    var picture_aspect_ratio: Float
    var frame_format_type: Int32
    var timecode: Int64
    var p_data: UnsafeMutablePointer<UInt8>?
    var line_stride_in_bytes: Int32
    var p_metadata: UnsafePointer<CChar>?
    var timestamp: Int64
}

private typealias NDIInitializeFunction = @convention(c) () -> Bool
private typealias NDIDestroyFunction = @convention(c) () -> Void
private typealias NDISendCreateFunction = @convention(c) (UnsafeRawPointer?) -> OpaquePointer?
private typealias NDISendDestroyFunction = @convention(c) (OpaquePointer?) -> Void
private typealias NDISendVideoFunction = @convention(c) (OpaquePointer?, UnsafeRawPointer?) -> Void

private final class MacNDIRuntime {
    static let shared = MacNDIRuntime()

    let isAvailable: Bool
    private let handle: UnsafeMutableRawPointer?
    private let destroyFunction: NDIDestroyFunction?
    private let sendCreateFunction: NDISendCreateFunction?
    private let sendDestroyFunction: NDISendDestroyFunction?
    private let sendVideoFunction: NDISendVideoFunction?

    private init() {
        let candidatePaths = Self.candidateLibraryPaths()

        var loadedHandle: UnsafeMutableRawPointer?
        for path in candidatePaths {
            loadedHandle = dlopen(path, RTLD_NOW | RTLD_LOCAL)
            if loadedHandle != nil { break }
        }

        handle = loadedHandle

        guard let handle,
              let initializeSymbol = dlsym(handle, "NDIlib_initialize"),
              let destroySymbol = dlsym(handle, "NDIlib_destroy"),
              let sendCreateSymbol = dlsym(handle, "NDIlib_send_create"),
              let sendDestroySymbol = dlsym(handle, "NDIlib_send_destroy"),
              let sendVideoSymbol = dlsym(handle, "NDIlib_send_send_video_v2") else {
            isAvailable = false
            destroyFunction = nil
            sendCreateFunction = nil
            sendDestroyFunction = nil
            sendVideoFunction = nil
            return
        }

        let initialize = unsafeBitCast(initializeSymbol, to: NDIInitializeFunction.self)
        destroyFunction = unsafeBitCast(destroySymbol, to: NDIDestroyFunction.self)
        sendCreateFunction = unsafeBitCast(sendCreateSymbol, to: NDISendCreateFunction.self)
        sendDestroyFunction = unsafeBitCast(sendDestroySymbol, to: NDISendDestroyFunction.self)
        sendVideoFunction = unsafeBitCast(sendVideoSymbol, to: NDISendVideoFunction.self)
        isAvailable = initialize()
    }

    deinit {
        if isAvailable {
            destroyFunction?()
        }
        if let handle {
            dlclose(handle)
        }
    }

    private static func candidateLibraryPaths() -> [String] {
        var paths: [String] = []

        if let bundled = bundledLibraryPaths() {
            paths.append(contentsOf: bundled)
        }

        paths.append(contentsOf: [
            ProcessInfo.processInfo.environment["NDI_RUNTIME_PATH"],
            "/Library/NDI SDK for Apple/lib/macOS/libndi.dylib",
            "/usr/local/lib/libndi.dylib",
            "/Library/Application Support/NDI/lib/macOS/libndi.dylib",
            "libndi.dylib"
        ].compactMap { $0 })

        var seen: Set<String> = []
        return paths.filter { seen.insert($0).inserted }
    }

    private static func bundledLibraryPaths() -> [String]? {
        guard let bundleURL = Bundle.main.bundleURL.standardizedFileURL as URL? else { return nil }

        let bundleRelativeCandidates = [
            "Contents/Frameworks/libndi.dylib",
            "Contents/Frameworks/NDIlib.framework/NDIlib",
            "Contents/Frameworks/NDI.framework/NDI",
            "Contents/Resources/NDI/libndi.dylib",
            "Contents/Resources/NDI/NDIlib.framework/NDIlib",
            "Contents/Resources/libndi.dylib"
        ]

        let directCandidates = [
            Bundle.main.privateFrameworksURL?.appendingPathComponent("libndi.dylib"),
            Bundle.main.privateFrameworksURL?.appendingPathComponent("NDIlib.framework/NDIlib"),
            Bundle.main.privateFrameworksURL?.appendingPathComponent("NDI.framework/NDI"),
            Bundle.main.resourceURL?.appendingPathComponent("NDI/libndi.dylib"),
            Bundle.main.resourceURL?.appendingPathComponent("NDI/NDIlib.framework/NDIlib"),
            Bundle.main.resourceURL?.appendingPathComponent("libndi.dylib")
        ]
        .compactMap { $0?.path }

        let relativeCandidates = bundleRelativeCandidates.map {
            bundleURL.appendingPathComponent($0).path
        }

        return directCandidates + relativeCandidates
    }

    func makeSender(named name: String) -> OpaquePointer? {
        guard let sendCreateFunction else { return nil }
        return name.withCString { ndiName in
            var settings = NDISendCreateSettings(
                p_ndi_name: ndiName,
                p_groups: nil,
                clock_video: 0,
                clock_audio: 0
            )
            return withUnsafePointer(to: &settings) { pointer in
                sendCreateFunction(UnsafeRawPointer(pointer))
            }
        }
    }

    func destroySender(_ sender: OpaquePointer?) {
        sendDestroyFunction?(sender)
    }

    func sendVideo(_ frame: NDIVideoFrameV2, on sender: OpaquePointer?) {
        guard let sendVideoFunction else { return }
        var mutableFrame = frame
        withUnsafePointer(to: &mutableFrame) { pointer in
            sendVideoFunction(sender, UnsafeRawPointer(pointer))
        }
    }
}

@MainActor
private final class MacNDISender {
    static var isRuntimeAvailable: Bool { MacNDIRuntime.shared.isAvailable }

    private let runtime = MacNDIRuntime.shared
    private var senderInstance: OpaquePointer?
    private var currentOutputName = ""

    var isReadyToSend: Bool {
        senderInstance != nil
    }

    func updateOutputName(_ outputName: String) {
        guard runtime.isAvailable else { return }
        let resolved = outputName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "ProdConnect Patchsheet"
            : outputName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard currentOutputName != resolved || senderInstance == nil else { return }
        stop()
        senderInstance = runtime.makeSender(named: resolved)
        currentOutputName = resolved
    }

    func send(image: CGImage) {
        guard let senderInstance else { return }
        guard let payload = makeVideoFramePayload(from: image) else { return }
        runtime.sendVideo(payload.frame, on: senderInstance)
        _ = payload
    }

    func stop() {
        if let senderInstance {
            runtime.destroySender(senderInstance)
        }
        senderInstance = nil
        currentOutputName = ""
    }

    private func makeVideoFramePayload(from image: CGImage) -> (frame: NDIVideoFrameV2, storage: [UInt8])? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerRow = width * 4
        var storage = [UInt8](repeating: 0, count: height * bytesPerRow)
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(
            data: &storage,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let frame = storage.withUnsafeMutableBufferPointer { buffer -> NDIVideoFrameV2 in
            NDIVideoFrameV2(
                xres: Int32(width),
                yres: Int32(height),
                FourCC: MacNDISender.fourCC("BGRA"),
                frame_rate_N: 30000,
                frame_rate_D: 1000,
                picture_aspect_ratio: Float(width) / Float(height),
                frame_format_type: 1,
                timecode: Int64.max,
                p_data: buffer.baseAddress,
                line_stride_in_bytes: Int32(bytesPerRow),
                p_metadata: nil,
                timestamp: 0
            )
        }

        return (frame, storage)
    }

    private static func fourCC(_ value: String) -> UInt32 {
        let utf8 = Array(value.utf8.prefix(4))
        guard utf8.count == 4 else { return 0 }
        return UInt32(utf8[0])
            | (UInt32(utf8[1]) << 8)
            | (UInt32(utf8[2]) << 16)
            | (UInt32(utf8[3]) << 24)
    }
}

private struct MacPatchsheetNDIPreview: View {
    let patches: [PatchRow]
    let category: String
    let outputName: String
    let nameColumnTitle: String
    let inputColumnTitle: String
    let outputColumnTitle: String
    let showsUniverseColumn: Bool
    let showsHeaders: Bool
    let isActive: Bool
    let scale: Double

    private var titleFont: Font { .system(size: 20 * scale, weight: .bold) }
    private var subtitleFont: Font { .system(size: 12 * scale, weight: .medium) }
    private var headerFont: Font { .system(size: 11 * scale, weight: .semibold) }
    private var rowFont: Font { .system(size: 18 * scale, weight: .semibold) }
    private var cellPadding: CGFloat { 12 * scale }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(outputName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "ProdConnect Patchsheet" : outputName)
                        .font(titleFont)
                        .foregroundStyle(.white)
                    Text("\(category) preview")
                        .font(subtitleFont)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.white.opacity(0.65))
                }
                Spacer()
                Text(isActive ? "LIVE" : "PREVIEW")
                    .font(.system(size: 10 * scale, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background((isActive ? Color.green : Color.gray).opacity(0.22))
                    .clipShape(Capsule())
                    .foregroundStyle(isActive ? Color.green : Color.white.opacity(0.75))
            }

            if patches.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No patches selected")
                        .font(.system(size: 18 * scale, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Enable the NDI checkbox on any patch row to include it in this output.")
                        .font(.system(size: 13 * scale))
                        .foregroundStyle(Color.white.opacity(0.72))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 12)
            } else {
                if showsHeaders {
                    HStack(spacing: 0) {
                        headerCell(nameColumnTitle)
                        headerCell(inputColumnTitle)
                        headerCell(outputColumnTitle)
                        if showsUniverseColumn {
                            headerCell("Universe")
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(patches) { patch in
                        HStack(spacing: 0) {
                            valueCell(patch.name)
                            valueCell(patch.input)
                            valueCell(patch.output)
                            if showsUniverseColumn {
                                valueCell(patch.universe ?? "")
                            }
                        }
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(Color.white.opacity(0.08))
                                .frame(height: 1)
                        }
                    }
                }
            }
        }
        .padding(18 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.08, green: 0.17, blue: 0.27),
                            Color(red: 0.04, green: 0.08, blue: 0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func headerCell(_ value: String) -> some View {
        Text(value)
            .font(headerFont)
            .textCase(.uppercase)
            .foregroundStyle(Color.white.opacity(0.62))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, cellPadding)
            .padding(.vertical, 10 * scale)
            .background(Color.white.opacity(0.06))
    }

    private func valueCell(_ value: String) -> some View {
        Text(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? " " : value)
            .font(rowFont)
            .foregroundStyle(.white)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, cellPadding)
            .padding(.vertical, 12 * scale)
    }
}

private struct MacRunOfShowNDIPreview: View {
    let show: RunOfShowDocument?
    let outputName: String
    let isActive: Bool
    let scale: Double

    private var titleFont: Font { .system(size: 22 * scale, weight: .bold) }
    private var subtitleFont: Font { .system(size: 12 * scale, weight: .medium) }
    private var rowFont: Font { .system(size: 16 * scale, weight: .semibold) }

    var body: some View {
        let resolvedShow = show
        let items = resolvedShow?.sortedItems ?? []

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    let showTitle = resolvedShow?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    Text(outputName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "ProdConnect Run of Show" : outputName)
                        .font(titleFont)
                        .foregroundStyle(.white)
                    Text(showTitle.isEmpty ? "Run of Show Preview" : showTitle)
                        .font(subtitleFont)
                        .foregroundStyle(Color.white.opacity(0.7))
                }
                Spacer()
                Text(isActive ? "LIVE" : "PREVIEW")
                    .font(.system(size: 10 * scale, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background((isActive ? Color.green : Color.gray).opacity(0.22))
                    .clipShape(Capsule())
                    .foregroundStyle(isActive ? Color.green : Color.white.opacity(0.75))
            }

            if items.isEmpty {
                Text("No run of show items available.")
                    .foregroundStyle(Color.white.opacity(0.75))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        headerCell("Length")
                            .frame(width: 110, alignment: .leading)
                        headerCell("Title")
                        headerCell("Person")
                        headerCell("Notes")
                    }

                    ForEach(items) { item in
                        HStack(spacing: 0) {
                            valueCell(item.formattedDuration)
                                .frame(width: 110, alignment: .leading)
                            valueCell(item.title)
                            valueCell(item.person)
                            valueCell(item.notes)
                        }
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(Color.white.opacity(0.08))
                                .frame(height: 1)
                        }
                    }
                }
            }
        }
        .padding(18 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.13, green: 0.13, blue: 0.16),
                            Color(red: 0.08, green: 0.08, blue: 0.11)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }

    private func headerCell(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11 * scale, weight: .semibold))
            .textCase(.uppercase)
            .foregroundStyle(Color.white.opacity(0.62))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10 * scale)
            .padding(.vertical, 10 * scale)
            .background(Color.white.opacity(0.06))
    }

    private func valueCell(_ text: String) -> some View {
        Text(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? " " : text)
            .font(rowFont)
            .foregroundStyle(.white)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10 * scale)
            .padding(.vertical, 12 * scale)
    }
}

private struct MacRunOfShowLiveNDIPreview: View {
    let show: RunOfShowDocument?
    let outputName: String
    let isActive: Bool
    let scale: Double
    let now: Date

    var body: some View {
        let items = show?.sortedItems ?? []
        let activeCurrentItemID = show?.isLiveActive == true ? show?.liveCurrentItemID : items.first?.id
        let currentIndex = show?.itemIndex(for: activeCurrentItemID)
        let currentItem = currentIndex.flatMap { items.indices.contains($0) ? items[$0] : nil }
        let nextItem = currentIndex.flatMap { index in
            let nextIndex = index + 1
            return items.indices.contains(nextIndex) ? items[nextIndex] : nil
        }
        let remaining = {
            guard let show, let currentItem else { return 0 }
            if show.isLiveActive {
                return show.currentRemainingSeconds(at: now)
            }
            return currentItem.durationSeconds
        }()
        let overrunSeconds = show?.isLiveActive == true ? (show?.currentOverrunSeconds(at: now) ?? 0) : 0
        let isOverrun = overrunSeconds > 0
        let endTime = {
            guard let show else { return now }
            if show.isLiveActive {
                return show.projectedEndTime(at: now)
            }
            return show.scheduledStart.addingTimeInterval(TimeInterval(show.totalDurationSeconds))
        }()
        let currentTitle = currentItem?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let currentNotes = currentItem?.notes.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let nextTitle = nextItem?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let currentSummary = currentItem.map { "\($0.formattedDuration) • \($0.person.isEmpty ? "No person assigned" : $0.person)" } ?? "Waiting to start"
        let nextSummary = nextItem.map { "\($0.formattedDuration) • \($0.person.isEmpty ? "No person assigned" : $0.person)" } ?? "End of show"

        return HStack(spacing: 0) {
            VStack(spacing: 0) {
                VStack(spacing: 8 * scale) {
                    Text(isOverrun ? runOfShowOverrunClock(seconds: overrunSeconds) : runOfShowFormattedClock(seconds: remaining))
                        .font(.system(size: 40 * scale, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Show should end \(endTime.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 10 * scale, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.82))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18 * scale)
                .background(isOverrun ? Color(red: 0.79, green: 0.17, blue: 0.2) : Color(red: 0.2, green: 0.68, blue: 0.36))

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(items.prefix(6).enumerated()), id: \.element.id) { _, item in
                        HStack(spacing: 8 * scale) {
                            Text(item.title)
                                .font(.system(size: 11 * scale, weight: item.id == currentItem?.id ? .semibold : .regular))
                                .foregroundStyle(item.id == currentItem?.id ? Color.white : Color.white.opacity(0.68))
                                .lineLimit(2)
                            Spacer()
                        }
                        .padding(.horizontal, 10 * scale)
                        .padding(.vertical, 8 * scale)
                        .background(item.id == currentItem?.id ? Color.orange.opacity(0.2) : Color.clear)
                    }
                }
                .background(Color(red: 0.1, green: 0.11, blue: 0.14))

                Spacer(minLength: 0)
            }
            .frame(width: 210 * scale)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .bottom, spacing: 12 * scale) {
                    Text("NOW")
                        .font(.system(size: 12 * scale, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .padding(.horizontal, 12 * scale)
                        .padding(.vertical, 5 * scale)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6 * scale, style: .continuous))

                    Text(currentTitle.isEmpty ? "No active item" : currentTitle)
                        .font(.system(size: 30 * scale, weight: .light))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(18 * scale)
                .background(Color(red: 0.11, green: 0.12, blue: 0.15))
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color(red: 0.2, green: 0.68, blue: 0.36))
                        .frame(height: max(1, 2 * scale))
                }

                VStack(alignment: .leading, spacing: 6 * scale) {
                    Text("ITEM NOTES")
                        .font(.system(size: 10 * scale, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.65))
                    Text(currentNotes.isEmpty ? "No item notes" : currentNotes)
                        .font(.system(size: 13 * scale))
                        .foregroundStyle(Color.white.opacity(0.86))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10 * scale)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8 * scale, style: .continuous))
                }
                .padding(18 * scale)
                .background(Color(red: 0.11, green: 0.12, blue: 0.15))

                VStack(alignment: .leading, spacing: 10 * scale) {
                    Text("NEXT")
                        .font(.system(size: 12 * scale, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .padding(.horizontal, 12 * scale)
                        .padding(.vertical, 5 * scale)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6 * scale, style: .continuous))

                    Text(nextTitle.isEmpty ? "No next item" : nextTitle)
                        .font(.system(size: 24 * scale, weight: .light))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .lineLimit(2)

                    Text(nextSummary)
                        .font(.system(size: 12 * scale))
                        .foregroundStyle(Color.white.opacity(0.64))

                    Text(currentSummary)
                        .font(.system(size: 11 * scale))
                        .foregroundStyle(Color.white.opacity(0.52))

                    Spacer(minLength: 0)
                }
                .padding(18 * scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(red: 0.09, green: 0.1, blue: 0.13))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.08, green: 0.09, blue: 0.11))
        .clipShape(RoundedRectangle(cornerRadius: 18 * scale, style: .continuous))
    }
}

private func runOfShowFormattedClock(seconds: Int) -> String {
    let minutes = max(seconds, 0) / 60
    let remainingSeconds = max(seconds, 0) % 60
    return String(format: "%02d:%02d", minutes, remainingSeconds)
}

private func runOfShowOverrunClock(seconds: Int) -> String {
    let minutes = max(seconds, 0) / 60
    let remainingSeconds = max(seconds, 0) % 60
    return String(format: "-%02d:%02d", minutes, remainingSeconds)
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

                    TextField("Notes", text: $patch.notes, axis: .vertical)
                        .lineLimit(2...6)
                        .disabled(!canEdit)

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

private struct MacRunOfShowView: View {
    @EnvironmentObject private var store: ProdConnectStore
    @EnvironmentObject private var runOfShowControls: MacRunOfShowControlController
    @State private var selectedShowID: String?
    @State private var showToDelete: RunOfShowDocument?

    private var canEdit: Bool {
        store.canEditRunOfShow
    }

    private var shows: [RunOfShowDocument] {
        store.runOfShows.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var selectedShow: RunOfShowDocument? {
        guard let selectedShowID else { return shows.first }
        return shows.first(where: { $0.id == selectedShowID }) ?? shows.first
    }

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 320)

            if let show = selectedShow {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        showHeader(show)
                        timelineGrid(for: show)
                        livePanel(for: show)
                    }
                    .padding(20)
                }
                .navigationTitle("Run of Show")
            } else {
                ContentUnavailableView(
                    "No Run of Show",
                    systemImage: "list.bullet.rectangle.portrait",
                    description: Text("Create a show to build your timeline and live view.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if selectedShowID == nil {
                selectedShowID = shows.first?.id
            }
        }
        .onChange(of: shows.map(\.id)) { _, ids in
            if let selectedShowID, ids.contains(selectedShowID) {
                return
            }
            self.selectedShowID = ids.first
        }
        .alert("Delete Run of Show?", isPresented: Binding(
            get: { showToDelete != nil },
            set: { if !$0 { showToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                guard let showToDelete else { return }
                store.deleteRunOfShow(showToDelete)
                if selectedShowID == showToDelete.id {
                    selectedShowID = shows.first(where: { $0.id != showToDelete.id })?.id
                }
                self.showToDelete = nil
            }
        } message: {
            Text("This permanently deletes the selected run of show.")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Run of Show")
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                Button {
                    addShow()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canEdit)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(shows) { show in
                        Button {
                            selectedShowID = show.id
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(show.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Show" : show.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(show.scheduledStart.formatted(date: .omitted, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(selectedShowID == show.id ? Color.accentColor.opacity(0.18) : Color.white.opacity(0.04))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.black.opacity(0.16))
    }

    private func showHeader(_ show: RunOfShowDocument) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    TextField(
                        "Show Title",
                        text: Binding(
                            get: { show.title },
                            set: { newValue in
                                updateShow(show) { $0.title = newValue }
                            }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 28, weight: .bold))

                    Text("\(show.sortedItems.count) items • \(formatDuration(seconds: show.totalDurationSeconds)) total")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if canEdit {
                    Button("Delete", role: .destructive) {
                        showToDelete = show
                    }
                    .buttonStyle(.bordered)
                }
            }

            HStack(spacing: 12) {
                DatePicker(
                    "Start Time",
                    selection: Binding(
                        get: { show.scheduledStart },
                        set: { value in
                            updateShow(show) { mutable in
                                mutable.scheduledStart = value
                            }
                        }
                    ),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .disabled(!canEdit)

                Toggle(
                    "Auto Start",
                    isOn: Binding(
                        get: { show.autoStartLive },
                        set: { value in
                            updateShow(show) { mutable in
                                mutable.autoStartLive = value
                            }
                        }
                    )
                )
                .toggleStyle(.checkbox)
                .disabled(!canEdit)

                Spacer()

                Button("Add Item") {
                    addItem(to: show)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canEdit)
            }
        }
    }

    private func timelineGrid(for show: RunOfShowDocument) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                timelineHeaderCell("Time", width: 110)
                timelineHeaderCell("Length", width: 90)
                timelineHeaderCell("Title", width: 260)
                timelineHeaderCell("Person", width: 180)
                timelineHeaderCell("Notes", width: 320)
                timelineHeaderCell("", width: 110)
            }
            .background(Color.white.opacity(0.05))

            ForEach(Array(show.sortedItems.enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 0) {
                    timelineValueCell(startTimeText(for: show, itemIndex: index), width: 110)
                    timelineLengthCell(show: show, item: item)
                    timelineEditableCell(title: "Title", text: item.title, width: 260) { newValue in
                        updateItem(show, itemID: item.id) { $0.title = newValue }
                    }
                    timelineEditableCell(title: "Person", text: item.person, width: 180) { newValue in
                        updateItem(show, itemID: item.id) { $0.person = newValue }
                    }
                    timelineEditableCell(title: "Notes", text: item.notes, width: 320) { newValue in
                        updateItem(show, itemID: item.id) { $0.notes = newValue }
                    }
                    timelineActionsCell(show: show, item: item, index: index)
                }
                .background(index.isMultiple(of: 2) ? Color.white.opacity(0.02) : Color.clear)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.white.opacity(0.05))
                        .frame(height: 1)
                }
            }
        }
        .background(Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func livePanel(for show: RunOfShowDocument) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Run of Show Live")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button(show.isLiveActive ? "Restart" : "Start") {
                    startLive(show)
                }
                .buttonStyle(.borderedProminent)
                .disabled(show.sortedItems.isEmpty || !canEdit)

                Button("Previous") {
                    moveLive(show, direction: -1)
                }
                .buttonStyle(.bordered)
                .disabled(!show.isLiveActive || !canEdit)

                Button("Next") {
                    moveLive(show, direction: 1)
                }
                .buttonStyle(.bordered)
                .disabled(!show.isLiveActive || !canEdit)

                Button("Reset") {
                    resetLive(show)
                }
                .buttonStyle(.bordered)
                .disabled((!show.isLiveActive && show.liveCurrentItemID == nil) || !canEdit)
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                liveSnapshotView(show: show, now: context.date)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now in
            handleAutomaticLiveStart(for: show, now: now)
        }
    }

    private func liveSnapshotView(show: RunOfShowDocument, now: Date) -> some View {
        let items = show.sortedItems
        let activeCurrentItemID = show.isLiveActive ? show.liveCurrentItemID : items.first?.id
        let currentIndex = show.itemIndex(for: activeCurrentItemID)
        let currentItem = currentIndex.flatMap { items.indices.contains($0) ? items[$0] : nil }
        let nextItem = currentIndex.flatMap { index in
            let nextIndex = index + 1
            return items.indices.contains(nextIndex) ? items[nextIndex] : nil
        }
        let remainingSeconds = currentItem.map { item in
            if show.isLiveActive {
                return max(item.durationSeconds - Int(now.timeIntervalSince(show.liveItemStartedAt ?? now)), 0)
            }
            return item.durationSeconds
        } ?? 0
        let currentTitle = currentItem?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let currentNotes = currentItem?.notes.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let nextTitle = nextItem?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let currentSummary = currentItem.map { "\($0.formattedDuration) • \($0.person.isEmpty ? "No person assigned" : $0.person)" } ?? "Waiting to start"
        let nextSummary = nextItem.map { "\($0.formattedDuration) • \($0.person.isEmpty ? "No person assigned" : $0.person)" } ?? "End of show"
        let overrunSeconds = show.isLiveActive ? show.currentOverrunSeconds(at: now) : 0
        let isOverrun = overrunSeconds > 0
        let projectedEndTime = show.isLiveActive
            ? show.projectedEndTime(at: now)
            : show.scheduledStart.addingTimeInterval(TimeInterval(show.totalDurationSeconds))

        return HStack(spacing: 0) {
            liveSidebar(
                show: show,
                items: items,
                currentItemID: currentItem?.id,
                remainingSeconds: remainingSeconds,
                overrunSeconds: overrunSeconds,
                isOverrun: isOverrun,
                projectedEndTime: projectedEndTime
            )
            liveMainContent(
                projectedEndTime: projectedEndTime,
                currentItem: currentItem,
                currentTitle: currentTitle,
                currentNotes: currentNotes,
                currentSummary: currentSummary,
                nextTitle: nextTitle,
                nextSummary: nextSummary
            )
        }
        .frame(maxWidth: .infinity, minHeight: 560, alignment: .topLeading)
        .background(Color(red: 0.08, green: 0.09, blue: 0.11))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func liveSidebar(show: RunOfShowDocument, items: [RunOfShowItem], currentItemID: String?, remainingSeconds: Int, overrunSeconds: Int, isOverrun: Bool, projectedEndTime: Date) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Text(isOverrun ? overrunClock(seconds: overrunSeconds) : formattedClock(seconds: remainingSeconds))
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(show.isLiveActive ? "Show should end \(projectedEndTime.formatted(date: .omitted, time: .shortened))" : "live not started")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
            .background(isOverrun ? Color(red: 0.79, green: 0.17, blue: 0.2) : Color(red: 0.2, green: 0.68, blue: 0.36))

            HStack(spacing: 8) {
                Button("Prev") {
                    moveLive(show, direction: -1)
                }
                .buttonStyle(.bordered)
                .disabled(!show.isLiveActive || !canEdit)

                Button("Next") {
                    moveLive(show, direction: 1)
                }
                .buttonStyle(.bordered)
                .disabled(!show.isLiveActive || !canEdit)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(Color(red: 0.12, green: 0.13, blue: 0.16))

            liveRundownList(show: show, items: items, currentItemID: currentItemID)
            Spacer(minLength: 0)
        }
        .frame(width: 240)
    }

    private func liveRundownList(show: RunOfShowDocument, items: [RunOfShowItem], currentItemID: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Time")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.65))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let itemStart = startTimeText(for: show, itemIndex: index)
                let isCurrent = item.id == currentItemID

                HStack(spacing: 10) {
                    Text(itemStart)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(isCurrent ? Color.orange : Color.white.opacity(0.5))
                        .frame(width: 58, alignment: .leading)
                    Text(item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : item.title)
                        .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? Color.white : Color.white.opacity(0.7))
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(isCurrent ? Color.orange.opacity(0.18) : (index.isMultiple(of: 2) ? Color.white.opacity(0.03) : Color.clear))
            }
        }
        .background(Color(red: 0.1, green: 0.11, blue: 0.14))
    }

    private func liveMainContent(
        projectedEndTime: Date,
        currentItem: RunOfShowItem?,
        currentTitle: String,
        currentNotes: String,
        currentSummary: String,
        nextTitle: String,
        nextSummary: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 14) {
                Text("NOW")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(currentTitle.isEmpty ? "No active item" : currentTitle)
                        .font(.system(size: 42, weight: .light))
                        .foregroundStyle(.white)
                    Text(currentSummary)
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.65))
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 18)
            .background(Color(red: 0.11, green: 0.12, blue: 0.15))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color(red: 0.2, green: 0.68, blue: 0.36))
                    .frame(height: 2)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("ITEM NOTES")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.65))
                Text(currentNotes.isEmpty ? "No item notes" : currentNotes)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.white.opacity(0.88))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .padding(24)
            .background(Color(red: 0.11, green: 0.12, blue: 0.15))

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 14) {
                Text("NEXT")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                Text(nextTitle.isEmpty ? "No next item" : nextTitle)
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.92))

                Text(nextSummary)
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.65))

                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(red: 0.09, green: 0.1, blue: 0.13))

            HStack {
                Text("Show ends at \(projectedEndTime.formatted(date: .omitted, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.65))
                Spacer()
                if let currentItem {
                    Text("Current: \(currentItem.title)")
                        .font(.footnote)
                        .foregroundStyle(Color.white.opacity(0.65))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color(red: 0.11, green: 0.12, blue: 0.15))
        }
    }

    private func timelineHeaderCell(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
    }

    private func timelineValueCell(_ value: String, width: CGFloat) -> some View {
        Text(value)
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
    }

    private func timelineEditableCell(title: String, text: String, width: CGFloat, setter: @escaping (String) -> Void) -> some View {
        TextField(title, text: Binding(get: { text }, set: setter))
            .textFieldStyle(.plain)
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .disabled(!canEdit)
    }

    private func timelineLengthCell(show: RunOfShowDocument, item: RunOfShowItem) -> some View {
        HStack(spacing: 6) {
            TextField(
                "0",
                text: Binding(
                    get: { String(max(item.lengthMinutes, 0)) },
                    set: { newValue in
                        let digits = newValue.filter(\.isNumber)
                        let parsed = Int(digits) ?? 0
                        updateItemDuration(show, itemID: item.id, minutes: min(max(parsed, 0), 600), seconds: item.lengthSeconds)
                    }
                )
            )
            .textFieldStyle(.roundedBorder)
            .frame(width: 34)
            .multilineTextAlignment(.trailing)

            Text(":")
                .foregroundStyle(.secondary)

            TextField(
                "00",
                text: Binding(
                    get: { String(format: "%02d", min(max(item.lengthSeconds, 0), 59)) },
                    set: { newValue in
                        let digits = newValue.filter(\.isNumber)
                        let parsed = Int(digits) ?? 0
                        updateItemDuration(show, itemID: item.id, minutes: item.lengthMinutes, seconds: min(max(parsed, 0), 59))
                    }
                )
            )
            .textFieldStyle(.roundedBorder)
            .frame(width: 34)
            .multilineTextAlignment(.trailing)
        }
        .frame(width: 90, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .disabled(!canEdit)
    }

    private func timelineActionsCell(show: RunOfShowDocument, item: RunOfShowItem, index: Int) -> some View {
        HStack(spacing: 6) {
            Button {
                moveItem(show, from: index, direction: -1)
            } label: {
                Image(systemName: "arrow.up")
            }
            .buttonStyle(.plain)
            .disabled(index == 0 || !canEdit)

            Button {
                moveItem(show, from: index, direction: 1)
            } label: {
                Image(systemName: "arrow.down")
            }
            .buttonStyle(.plain)
            .disabled(index == show.sortedItems.count - 1 || !canEdit)

            Button(role: .destructive) {
                deleteItem(show, itemID: item.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .disabled(!canEdit)
        }
        .frame(width: 110)
        .padding(.vertical, 12)
    }

    private func addShow() {
        guard canEdit else { return }
        let show = RunOfShowDocument(
            title: "New Run of Show",
            teamCode: store.teamCode ?? "",
            scheduledStart: Date(),
            items: [
                RunOfShowItem(title: "Welcome", lengthMinutes: 5, lengthSeconds: 0, position: 0),
                RunOfShowItem(title: "Song 1", lengthMinutes: 5, lengthSeconds: 0, position: 1)
            ]
        )
        store.saveRunOfShow(show)
        selectedShowID = show.id
    }

    private func addItem(to show: RunOfShowDocument) {
        updateShow(show) { mutable in
            mutable.items.append(
                RunOfShowItem(
                    title: "New Item",
                    lengthMinutes: 5,
                    lengthSeconds: 0,
                    position: mutable.items.count
                )
            )
        }
    }

    private func deleteItem(_ show: RunOfShowDocument, itemID: String) {
        updateShow(show) { mutable in
            mutable.items.removeAll { $0.id == itemID }
        }
    }

    private func moveItem(_ show: RunOfShowDocument, from index: Int, direction: Int) {
        updateShow(show) { mutable in
            var items = mutable.sortedItems
            let newIndex = index + direction
            guard items.indices.contains(index), items.indices.contains(newIndex) else { return }
            let moved = items.remove(at: index)
            items.insert(moved, at: newIndex)
            mutable.items = items.enumerated().map { offset, item in
                var updated = item
                updated.position = offset
                return updated
            }
        }
    }

    private func startLive(_ show: RunOfShowDocument) {
        runOfShowControls.clearAutoStartSuppression(for: show.id)
        updateShow(show) { mutable in
            let items = mutable.sortedItems
            guard let first = items.first else { return }
            let now = Date()
            mutable.isLiveActive = true
            mutable.liveCurrentItemID = first.id
            mutable.liveShowStartedAt = now
            mutable.liveItemStartedAt = now
        }
    }

    private func moveLive(_ show: RunOfShowDocument, direction: Int) {
        updateShow(show) { mutable in
            let items = mutable.sortedItems
            guard let currentIndex = mutable.itemIndex(for: mutable.liveCurrentItemID) else { return }
            let newIndex = currentIndex + direction
            guard items.indices.contains(newIndex) else { return }
            mutable.isLiveActive = true
            mutable.liveCurrentItemID = items[newIndex].id
            mutable.liveItemStartedAt = Date()
            if mutable.liveShowStartedAt == nil {
                mutable.liveShowStartedAt = Date()
            }
        }
    }

    private func resetLive(_ show: RunOfShowDocument) {
        runOfShowControls.suppressAutoStart(for: show.id)
        updateShow(show) { mutable in
            mutable.isLiveActive = false
            mutable.liveCurrentItemID = nil
            mutable.liveShowStartedAt = nil
            mutable.liveItemStartedAt = nil
        }
    }

    private func updateItem(_ show: RunOfShowDocument, itemID: String, change: (inout RunOfShowItem) -> Void) {
        updateShow(show) { mutable in
            guard let index = mutable.items.firstIndex(where: { $0.id == itemID }) else { return }
            change(&mutable.items[index])
        }
    }

    private func updateItemDuration(_ show: RunOfShowDocument, itemID: String, minutes: Int, seconds: Int) {
        guard canEdit else { return }
        var mutable = show
        guard let index = mutable.items.firstIndex(where: { $0.id == itemID }) else { return }
        mutable.items[index].lengthMinutes = max(minutes, 0)
        mutable.items[index].lengthSeconds = min(max(seconds, 0), 59)
        store.saveRunOfShow(mutable)
    }

    private func updateShow(_ show: RunOfShowDocument, change: (inout RunOfShowDocument) -> Void) {
        guard canEdit else { return }
        var mutable = show
        change(&mutable)
        DispatchQueue.main.async {
            store.saveRunOfShow(mutable)
        }
    }

    private func handleAutomaticLiveStart(for show: RunOfShowDocument, now: Date) {
        guard canEdit,
              show.autoStartLive,
              !runOfShowControls.isAutoStartSuppressed(for: show.id),
              !show.isLiveActive,
              show.liveCurrentItemID == nil,
              !show.sortedItems.isEmpty,
              now >= show.scheduledStart else { return }
        startLive(show)
    }

    private func startTimeText(for show: RunOfShowDocument, itemIndex: Int) -> String {
        let offsetSeconds = show.sortedItems.prefix(itemIndex).reduce(0) { $0 + $1.durationSeconds }
        let start = show.scheduledStart.addingTimeInterval(TimeInterval(offsetSeconds))
        return start.formatted(date: .omitted, time: .shortened)
    }

    private func formattedClock(seconds: Int) -> String {
        let minutes = max(seconds, 0) / 60
        let remainingSeconds = max(seconds, 0) % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    private func formatDuration(seconds: Int) -> String {
        let minutes = max(seconds, 0) / 60
        let remainingSeconds = max(seconds, 0) % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    private func overrunClock(seconds: Int) -> String {
        let minutes = max(seconds, 0) / 60
        let remainingSeconds = max(seconds, 0) % 60
        return String(format: "-%02d:%02d", minutes, remainingSeconds)
    }
}

private struct MacTrainingView: View {
    private enum TrainingViewMode: String, CaseIterable, Identifiable {
        case list
        case grid

        var id: String { rawValue }
    }

    private enum AssignmentFilter: String, CaseIterable, Identifiable {
        case all = "All Assignments"
        case assigned = "Assigned"
        case unassigned = "Unassigned"

        var id: String { rawValue }
    }

    private enum CompletionFilter: String, CaseIterable, Identifiable {
        case all = "All Status"
        case incomplete = "Incomplete"
        case completed = "Completed"

        var id: String { rawValue }
    }

    @EnvironmentObject private var store: ProdConnectStore
    @AppStorage("prodconnect.mac.trainingViewMode") private var trainingViewModeRawValue = TrainingViewMode.list.rawValue
    @State private var selectedLesson: TrainingLesson?
    @State private var showAddTrainingSheet = false
    @State private var editingLesson: TrainingLesson?
    @State private var title = ""
    @State private var category = "Audio"
    @State private var groupName = ""
    @State private var selectedAssignedUserID = ""
    @State private var videoSource = "upload"
    @State private var urlString = ""
    @State private var selectedVideoURL: URL?
    @State private var isUploadingVideo = false
    @State private var uploadProgress: Double = 0
    @State private var uploadError: String?
    @State private var selectedCategory = "All"
    @State private var assignmentFilter: AssignmentFilter = .all
    @State private var completionFilter: CompletionFilter = .all
    @State private var searchText = ""

    private let lessonCategories = ["Audio", "Video", "Lighting", "Misc"]
    private let filterCategories = ["All", "Audio", "Video", "Lighting", "Misc"]
    private let trainingColumns: [GridItem] = [
        GridItem(.flexible(minimum: 280, maximum: .infinity), spacing: 0, alignment: .leading),
        GridItem(.fixed(140), spacing: 0, alignment: .leading),
        GridItem(.fixed(170), spacing: 0, alignment: .leading),
        GridItem(.fixed(140), spacing: 0, alignment: .leading)
    ]
    private var canEdit: Bool { store.user?.isAdmin == true || store.user?.canEditTraining == true }
    private var assignableMembers: [UserProfile] {
        store.teamMembers.sorted {
            memberDisplayName($0).localizedCaseInsensitiveCompare(memberDisplayName($1)) == .orderedAscending
        }
    }
    private var sortedLessons: [TrainingLesson] {
        store.lessons.sorted { lhs, rhs in
            lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }
    private var filteredLessons: [TrainingLesson] {
        var lessons = sortedLessons

        if selectedCategory != "All" {
            lessons = lessons.filter { $0.category == selectedCategory }
        }

        switch assignmentFilter {
        case .all:
            break
        case .assigned:
            lessons = lessons.filter(isLessonAssigned)
        case .unassigned:
            lessons = lessons.filter { !isLessonAssigned($0) }
        }

        switch completionFilter {
        case .all:
            break
        case .incomplete:
            lessons = lessons.filter { !$0.isCompleted }
        case .completed:
            lessons = lessons.filter(\.isCompleted)
        }

        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lessons = lessons.filter { lesson in
                trainingSearchTokens(for: lesson).contains {
                    $0.localizedCaseInsensitiveContains(searchText)
                }
            }
        }

        return lessons
    }
    private var groupedLessons: [(group: String, items: [TrainingLesson])] {
        let grouped = Dictionary(grouping: filteredLessons) { trainingGroupTitle(for: $0) }
        return grouped.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.map { key in
            (group: key, items: grouped[key] ?? [])
        }
    }
    private var canSaveNewLesson: Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty || isUploadingVideo { return false }
        if videoSource == "upload" {
            if selectedVideoURL != nil { return true }
            let existingURL = editingLesson?.urlString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !existingURL.isEmpty && !isYouTubeURLString(existingURL)
        }
        return !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var trainingViewMode: TrainingViewMode {
        get { TrainingViewMode(rawValue: trainingViewModeRawValue) ?? .list }
        nonmutating set { trainingViewModeRawValue = newValue.rawValue }
    }
    private var trainingViewModeBinding: Binding<TrainingViewMode> {
        Binding(
            get: { trainingViewMode },
            set: { trainingViewMode = $0 }
        )
    }
    private var hasActiveFilters: Bool {
        selectedCategory != "All"
            || assignmentFilter != .all
            || completionFilter != .all
            || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Training")
                                .font(.system(size: 24, weight: .semibold))
                            Text(trainingResultsText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("View", selection: trainingViewModeBinding) {
                            Label("List", systemImage: "list.bullet").tag(TrainingViewMode.list)
                            Label("Grid", systemImage: "square.grid.2x2").tag(TrainingViewMode.grid)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)

                        if canEdit {
                            Button {
                                editingLesson = nil
                                resetNewLessonForm()
                                showAddTrainingSheet = true
                            } label: {
                                Label("Add", systemImage: "plus")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }

                    trainingFilterBar

                    if trainingViewMode == .list {
                        trainingHeaderRow

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(groupedLessons, id: \.group) { section in
                                    trainingGroupHeader(section.group)
                                    ForEach(section.items) { lesson in
                                        trainingRow(lesson)
                                    }
                                }
                            }
                            .padding(.bottom, 8)
                        }
                        .background(Color.white.opacity(0.02))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                        )
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                ForEach(groupedLessons, id: \.group) { section in
                                    trainingGroupHeader(section.group)
                                        .padding(.horizontal, 18)

                                    LazyVGrid(
                                        columns: [GridItem(.adaptive(minimum: 280, maximum: 360), spacing: 18, alignment: .top)],
                                        spacing: 18
                                    ) {
                                        ForEach(section.items) { lesson in
                                            trainingGridCard(lesson)
                                        }
                                    }
                                }
                            }
                            .padding(18)
                        }
                        .background(Color.white.opacity(0.02))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                        )
                    }
                }
                .padding()
                .background(Color.clear)
                .navigationTitle("Training")
            }
        }
        .onAppear {
            store.listenToTeamMembers()
        }
        .sheet(isPresented: $showAddTrainingSheet) {
            trainingEditorSheet(title: "Add Training")
        }
        .sheet(item: $editingLesson) { lesson in
            trainingEditorSheet(title: "Edit Training", editing: lesson)
                .onAppear {
                    populateLessonForm(from: lesson)
                }
        }
    }

    private func trainingEditorSheet(title: String, editing lesson: TrainingLesson? = nil) -> some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $title)
                    Picker("Category", selection: $category) {
                        ForEach(lessonCategories, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Group", text: $groupName)
                    if canEdit {
                        Picker("Assign To", selection: $selectedAssignedUserID) {
                            Text("Unassigned").tag("")
                            ForEach(assignableMembers) { member in
                                Text(memberDisplayName(member)).tag(member.id)
                            }
                        }
                    }
                }

                Section("Video Source") {
                    Picker("Source", selection: $videoSource) {
                        Text("Upload File").tag("upload")
                        Text("Video URL").tag("url")
                    }
                    .pickerStyle(.segmented)

                    if videoSource == "upload" {
                        Button(selectedVideoURL == nil ? "Choose Video" : "Change Video") {
                            pickTrainingVideo()
                        }
                        if let selectedVideoURL {
                            Text(selectedVideoURL.lastPathComponent)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let existingURL = lesson?.urlString?.trimmingCharacters(in: .whitespacesAndNewlines),
                                  !existingURL.isEmpty,
                                  !isYouTubeURLString(existingURL) {
                            Text("Using current uploaded video")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        TextField("Video URL", text: $urlString)
                    }
                }

                if isUploadingVideo {
                    Section {
                        ProgressView(value: uploadProgress) {
                            Text("Uploading video…")
                        }
                    }
                }

                if let uploadError, !uploadError.isEmpty {
                    Section {
                        Text(uploadError)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        resetNewLessonForm()
                        editingLesson = nil
                        showAddTrainingSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveLesson(editing: lesson)
                    }
                    .disabled(!canSaveNewLesson)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 260)
    }

    private var trainingResultsText: String {
        if hasActiveFilters {
            return "\(filteredLessons.count) of \(sortedLessons.count) lessons"
        }
        return "\(sortedLessons.count) lessons"
    }

    private var trainingFilterBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search title, group, category, assignee", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )

            Picker("Category", selection: $selectedCategory) {
                ForEach(filterCategories, id: \.self) { value in
                    Text(value).tag(value)
                }
            }
            .frame(width: 150)

            Picker("Assignment", selection: $assignmentFilter) {
                ForEach(AssignmentFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .frame(width: 150)

            Picker("Status", selection: $completionFilter) {
                ForEach(CompletionFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .frame(width: 145)

            if hasActiveFilters {
                Button("Reset") {
                    selectedCategory = "All"
                    assignmentFilter = .all
                    completionFilter = .all
                    searchText = ""
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var trainingHeaderRow: some View {
        LazyVGrid(columns: trainingColumns, alignment: .leading, spacing: 0) {
            trainingHeaderCell("Name")
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 1)
                }
            trainingHeaderCell("Category")
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 1)
                }
            trainingHeaderCell("Assignee")
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 1)
                }
            trainingHeaderCell("Source")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.white.opacity(0.045))
    }

    private func trainingHeaderCell(_ title: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()

            Image(systemName: "arrow.up.arrow.down")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func trainingGroupHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.025))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(height: 1)
        }
    }

    private func trainingRow(_ lesson: TrainingLesson) -> some View {
        Button {
            selectedLesson = lesson
        } label: {
            LazyVGrid(columns: trainingColumns, alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .center, spacing: 10) {
                        MacTrainingThumbnailView(lesson: lesson, width: 72, height: 44)

                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 8) {
                                Text(lesson.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                if hasPlayableURL(lesson) {
                                    Image(systemName: "play.circle.fill")
                                        .foregroundStyle(.blue)
                                        .font(.system(size: 13))
                                }
                            }
                            if lesson.isCompleted {
                                Text("Completed")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.green)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 1)
                }

                Text(lesson.category)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(Color.white.opacity(0.06))
                            .frame(width: 1)
                    }

                Text(trainingAssigneeLabel(for: lesson))
                    .font(.system(size: 12))
                    .foregroundStyle(trainingAssigneeLabel(for: lesson) == "Unassigned" ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(Color.white.opacity(0.06))
                            .frame(width: 1)
                    }

                Text(trainingSourceLabel(for: lesson))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color.white.opacity(0.01))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.white.opacity(0.045))
                    .frame(height: 1)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if canEdit {
                Button("Edit") {
                    populateLessonForm(from: lesson)
                    editingLesson = lesson
                }
                Button(role: .destructive) {
                    if selectedLesson?.id == lesson.id {
                        selectedLesson = nil
                    }
                    store.deleteLesson(lesson)
                } label: {
                    Text("Delete")
                }
            }
        }
    }

    private func trainingGridCard(_ lesson: TrainingLesson) -> some View {
        Button {
            selectedLesson = lesson
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                MacTrainingThumbnailView(lesson: lesson, width: nil, height: 180)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(lesson.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                        if hasPlayableURL(lesson) {
                            Image(systemName: "play.circle.fill")
                                .foregroundStyle(.blue)
                                .font(.system(size: 14))
                        }
                    }

                    Text(lesson.category)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Text(trainingAssigneeLabel(for: lesson))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text(trainingSourceLabel(for: lesson))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if lesson.isCompleted {
                        Text("Completed")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if canEdit {
                Button("Edit") {
                    populateLessonForm(from: lesson)
                    editingLesson = lesson
                }
                Button(role: .destructive) {
                    if selectedLesson?.id == lesson.id {
                        selectedLesson = nil
                    }
                    store.deleteLesson(lesson)
                } label: {
                    Text("Delete")
                }
            }
        }
    }

    private func hasPlayableURL(_ lesson: TrainingLesson) -> Bool {
        let raw = lesson.urlString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !raw.isEmpty && URL(string: raw) != nil
    }

    private func saveLesson(editing existingLesson: TrainingLesson? = nil) {
        uploadError = nil
        if videoSource == "upload" {
            if let selectedVideoURL {
                isUploadingVideo = true
                uploadTrainingVideo(from: selectedVideoURL) { result in
                    DispatchQueue.main.async {
                        self.isUploadingVideo = false
                        switch result {
                        case .success(let uploadedURL):
                            persistLesson(urlString: uploadedURL, existingLesson: existingLesson)
                        case .failure(let error):
                            self.uploadError = "Video upload failed: \(error.localizedDescription)"
                        }
                    }
                }
            } else {
                let existingURL = existingLesson?.urlString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                persistLesson(urlString: existingURL, existingLesson: existingLesson)
            }
        } else {
            persistLesson(urlString: urlString.trimmingCharacters(in: .whitespacesAndNewlines), existingLesson: existingLesson)
        }
    }

    private func resetNewLessonForm() {
        title = ""
        category = lessonCategories.first ?? "Audio"
        groupName = ""
        selectedAssignedUserID = ""
        videoSource = "upload"
        urlString = ""
        selectedVideoURL = nil
        isUploadingVideo = false
        uploadProgress = 0
        uploadError = nil
    }

    private func persistLesson(urlString: String, existingLesson: TrainingLesson? = nil) {
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let assignedID = selectedAssignedUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        let assignedMember = assignableMembers.first(where: { $0.id == assignedID })

        store.saveLesson(
            TrainingLesson(
                id: existingLesson?.id ?? UUID().uuidString,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                category: category,
                groupName: normalizedTrainingGroupName(groupName),
                teamCode: store.teamCode ?? "",
                durationSeconds: existingLesson?.durationSeconds ?? 0,
                urlString: trimmedURL.isEmpty ? nil : trimmedURL,
                isCompleted: existingLesson?.isCompleted ?? false,
                assignedToUserID: assignedMember?.id,
                assignedToUserEmail: assignedMember?.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            )
        )
        resetNewLessonForm()
        editingLesson = nil
        showAddTrainingSheet = false
    }

    private func populateLessonForm(from lesson: TrainingLesson) {
        title = lesson.title
        category = lesson.category
        groupName = lesson.groupName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let assignedID = lesson.assignedToUserID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        selectedAssignedUserID = assignedID
        let existingURL = lesson.urlString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if isYouTubeURLString(existingURL) {
            videoSource = "url"
            urlString = existingURL
        } else {
            videoSource = "upload"
            urlString = ""
        }
        selectedVideoURL = nil
        uploadError = nil
        uploadProgress = 0
        isUploadingVideo = false
    }

    private func isYouTubeURLString(_ value: String) -> Bool {
        let lowered = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lowered.contains("youtube.com") || lowered.contains("youtu.be")
    }

    private func normalizedTrainingGroupName(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func trainingGroupTitle(for lesson: TrainingLesson) -> String {
        let trimmed = lesson.groupName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Ungrouped" : trimmed
    }

    @MainActor
    private func pickTrainingVideo() {
        uploadError = nil
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]

        let handleSelection: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            selectedVideoURL = url
            urlString = ""
        }

        if let keyWindow = NSApp.keyWindow {
            panel.beginSheetModal(for: keyWindow, completionHandler: handleSelection)
        } else {
            handleSelection(panel.runModal())
        }
    }

    private func uploadTrainingVideo(from localURL: URL, completion: @escaping (Result<String, Error>) -> Void) {
        let safeName = localURL.lastPathComponent.replacingOccurrences(of: " ", with: "_")
        let path = "trainingVideos/\(UUID().uuidString)-\(safeName)"
        let storageRef = Storage.storage().reference().child(path)
        let metadata = StorageMetadata()
        metadata.contentType = trainingVideoContentType(for: localURL)
        let didAccess = localURL.startAccessingSecurityScopedResource()

        let uploadTask = storageRef.putFile(from: localURL, metadata: metadata)
        uploadTask.observe(.progress) { snapshot in
            DispatchQueue.main.async {
                uploadProgress = snapshot.progress?.fractionCompleted ?? 0
            }
        }
        uploadTask.observe(.failure) { snapshot in
            if didAccess {
                localURL.stopAccessingSecurityScopedResource()
            }
            completion(.failure(snapshot.error ?? NSError(
                domain: "ProdConnectMacTraining",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Upload failed."]
            )))
        }
        uploadTask.observe(.success) { _ in
            if didAccess {
                localURL.stopAccessingSecurityScopedResource()
            }
            storageRef.downloadURL { url, error in
                if let error {
                    completion(.failure(error))
                } else if let absoluteString = url?.absoluteString {
                    completion(.success(absoluteString))
                } else {
                    completion(.failure(NSError(
                        domain: "ProdConnectMacTraining",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Missing download URL."]
                    )))
                }
            }
        }
    }

    private func trainingVideoContentType(for localURL: URL) -> String {
        if let type = UTType(filenameExtension: localURL.pathExtension),
           let mimeType = type.preferredMIMEType {
            return mimeType
        }
        return "video/quicktime"
    }

    private func trainingAssigneeLabel(for lesson: TrainingLesson) -> String {
        let assignedID = lesson.assignedToUserID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !assignedID.isEmpty,
           let member = assignableMembers.first(where: { $0.id == assignedID }) {
            return memberDisplayName(member)
        }
        let assignedEmail = lesson.assignedToUserEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !assignedEmail.isEmpty {
            return assignedEmail.components(separatedBy: "@").first ?? assignedEmail
        }
        return "Unassigned"
    }

    private func trainingSourceLabel(for lesson: TrainingLesson) -> String {
        let raw = lesson.urlString?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if raw.isEmpty { return "No video" }
        if raw.contains("youtube.com") || raw.contains("youtu.be") { return "Video URL" }
        return "Uploaded File"
    }

    private func isLessonAssigned(_ lesson: TrainingLesson) -> Bool {
        let assignedID = lesson.assignedToUserID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let assignedEmail = lesson.assignedToUserEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !assignedID.isEmpty || !assignedEmail.isEmpty
    }

    private func trainingSearchTokens(for lesson: TrainingLesson) -> [String] {
        [
            lesson.title,
            lesson.category,
            trainingGroupTitle(for: lesson),
            trainingAssigneeLabel(for: lesson),
            trainingSourceLabel(for: lesson),
            lesson.isCompleted ? "Completed" : "Incomplete"
        ]
    }

    private func memberDisplayName(_ member: UserProfile) -> String {
        let trimmed = member.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return member.email.components(separatedBy: "@").first ?? member.email
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

private struct MacTrainingThumbnailView: View {
    let lesson: TrainingLesson
    let width: CGFloat?
    let height: CGFloat

    @State private var generatedThumbnail: NSImage?

    private var lessonURL: URL? {
        let raw = lesson.urlString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    private var youTubeThumbnailURL: URL? {
        guard let url = lessonURL else { return nil }
        guard let host = url.host?.lowercased() else { return nil }

        let videoID: String?
        if host.contains("youtu.be") {
            videoID = url.pathComponents.dropFirst().first
        } else if host.contains("youtube.com"),
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            if url.path.lowercased() == "/watch" {
                videoID = components.queryItems?.first(where: { $0.name == "v" })?.value
            } else if url.path.lowercased().contains("/embed/") {
                videoID = url.pathComponents.last
            } else {
                videoID = nil
            }
        } else {
            videoID = nil
        }

        guard let videoID, !videoID.isEmpty else { return nil }
        return URL(string: "https://img.youtube.com/vi/\(videoID)/hqdefault.jpg")
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))

            if let youTubeThumbnailURL {
                AsyncImage(url: youTubeThumbnailURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        thumbnailPlaceholder
                    default:
                        ProgressView()
                    }
                }
            } else if let generatedThumbnail {
                Image(nsImage: generatedThumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                thumbnailPlaceholder
            }

            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.38)],
                startPoint: .top,
                endPoint: .bottom
            )

            Image(systemName: "play.circle.fill")
                .font(.system(size: min(height * 0.32, 40), weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
        }
        .frame(maxWidth: width == nil ? .infinity : nil)
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .task(id: lesson.urlString) {
            await loadGeneratedThumbnailIfNeeded()
        }
    }

    private var thumbnailPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "video")
                .font(.system(size: min(height * 0.22, 26), weight: .medium))
                .foregroundStyle(.secondary)
            Text(lesson.category)
                .font(.system(size: 10, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
        }
    }

    private func loadGeneratedThumbnailIfNeeded() async {
        guard youTubeThumbnailURL == nil, generatedThumbnail == nil, let url = lessonURL else { return }

        let image = await Task.detached(priority: .utility) { () -> NSImage? in
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 1280, height: 720)

            let preferredTimes = [
                CMTime(seconds: 1, preferredTimescale: 600),
                .zero
            ]

            for time in preferredTimes {
                if let cgImage = await generateThumbnailImage(with: generator, at: time) {
                    return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                }
            }
            return nil
        }.value

        guard let image else { return }
        await MainActor.run {
            generatedThumbnail = image
        }
    }

    private func generateThumbnailImage(with generator: AVAssetImageGenerator, at time: CMTime) async -> CGImage? {
        await withCheckedContinuation { continuation in
            generator.generateCGImageAsynchronously(for: time) { image, _, _ in
                continuation.resume(returning: image)
            }
        }
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
    @State private var dueDateEditorChecklistID: String?

    private enum ChecklistSortColumn {
        case name
        case assignee
        case dueDate
    }

    private let checklistMinimumColumnWidths: [CGFloat] = [320, 180, 150]
    private let checklistColumnWeights: [CGFloat] = [0.58, 0.24, 0.18]
    private let checklistTableCornerRadius: CGFloat = 14
    private var assignableMembers: [UserProfile] {
        store.teamMembers.sorted {
            checklistMemberDisplayName(for: $0).localizedCaseInsensitiveCompare(checklistMemberDisplayName(for: $1)) == .orderedAscending
        }
    }

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

    private var orderedGroupNames: [String] {
        store.availableChecklistGroups
    }

    private var sortedChecklists: [ChecklistTemplate] {
        store.checklists.sorted { lhs, rhs in
            let result: ComparisonResult
            switch checklistSortColumn {
            case .name:
                if lhs.position != rhs.position {
                    return lhs.position < rhs.position
                }
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
        return orderedGroupNames.map { key in
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Checklists")
                        .font(.system(size: 24, weight: .semibold))
                    Text("\(store.checklists.count) total")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
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
                    VStack(alignment: .leading, spacing: 0) {
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
                                                    .font(.system(size: 13, weight: .semibold))
                                                Text("\(section.items.count)")
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .foregroundStyle(.tertiary)
                                                Spacer()
                                            }
                                            .foregroundStyle(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.horizontal, 14)
                                            .padding(.top, 14)
                                            .padding(.bottom, 8)
                                        }
                                        .buttonStyle(.plain)
                                        .draggable(store.canPersistChecklistGroupOrder ? dragTokenForGroup(section.group) : "")
                                        .dropDestination(for: String.self) { items, _ in
                                            handleDroppedGroupToken(items.first, before: section.group)
                                        }
                                        if !collapsedGroups.contains(section.group) {
                                            ForEach(section.items) { checklist in
                                                checklistRow(checklist, columns: columns)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .frame(minWidth: tableWidth, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.22))
                    }
                    .background(
                        RoundedRectangle(cornerRadius: checklistTableCornerRadius, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: checklistTableCornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.05), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: checklistTableCornerRadius, style: .continuous))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            if isShowingAddGroup {
                GroupBox("Add Group") {
                    VStack(spacing: 10) {
                        TextField("Group", text: $newGroupName)
                            .onSubmit {
                                saveNewChecklistGroup()
                            }
                        HStack {
                            Spacer()
                            Button("Save Group") {
                                saveNewChecklistGroup()
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
        .navigationTitle("Checklists")
        .onAppear {
            store.listenToTeamMembers()
        }
        }
    }

    @ViewBuilder
    private func checklistRow(_ checklist: ChecklistTemplate, columns: [GridItem]) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Button {
                    toggleChecklistCompletion(checklist)
                } label: {
                    Image(systemName: isChecklistCompleted(checklist) ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isChecklistCompleted(checklist) ? Color.green : Color.secondary)
                        .padding(.top, 2)
                }
                .buttonStyle(.plain)

                Button {
                    isShowingAddChecklist = false
                    startsEditingSelectedChecklist = false
                    selectedChecklist = checklist
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(checklist.title)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            checklistStatusBadge(for: checklist)
                        }

                        HStack(spacing: 8) {
                            Text(checklistProgressLabel(for: checklist))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(isChecklistCompleted(checklist) ? Color.green : Color.accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background((isChecklistCompleted(checklist) ? Color.green : Color.accentColor).opacity(0.12))
                                .clipShape(Capsule())
                            Text(checklistSubtitle(checklist))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 1)
            }

            checklistAssigneeCell(for: checklist)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 1)
                }

            checklistDueDateCell(for: checklist)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 9)
        .padding(.horizontal, 14)
        .background(checklistRowBackground(for: checklist))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.045))
                .frame(height: 1)
        }
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
        .draggable(dragTokenForChecklist(checklist))
        .dropDestination(for: String.self) { items, _ in
            handleDroppedChecklistToken(items.first, before: checklist)
        }
    }

    private func checklistTableHeader(columns: [GridItem]) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 0) {
            checklistHeaderButton("Name", column: .name)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 1)
                }
            checklistHeaderButton("Assignee", column: .assignee)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 1)
                }
            checklistHeaderButton("Due date", column: .dueDate)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.white.opacity(0.045))
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
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
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

    @ViewBuilder
    private func checklistAssigneeCell(for checklist: ChecklistTemplate) -> some View {
        if store.canAssignChecklistTasks {
            Menu {
                Button("Unassigned") {
                    updateChecklistAssignee(checklist, userID: "")
                }
                Divider()
                ForEach(assignableMembers) { member in
                    Button(checklistMemberDisplayName(for: member)) {
                        updateChecklistAssignee(checklist, userID: member.id)
                    }
                }
            } label: {
                checklistAssigneeCellLabel(for: checklist)
            }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            checklistAssigneeCellLabel(for: checklist)
        }
    }

    @ViewBuilder
    private func checklistDueDateCell(for checklist: ChecklistTemplate) -> some View {
        if canManageChecklistDueDate {
            Button {
                dueDateEditorChecklistID = checklist.id
            } label: {
                checklistDueDateCellLabel(for: checklist)
            }
            .buttonStyle(.plain)
            .popover(isPresented: Binding(
                get: { dueDateEditorChecklistID == checklist.id },
                set: { newValue in
                    if !newValue, dueDateEditorChecklistID == checklist.id {
                        dueDateEditorChecklistID = nil
                    }
                }
            ), arrowEdge: .trailing) {
                checklistDueDateEditor(for: checklist)
                    .padding(14)
                    .frame(width: 260)
            }
        } else {
            checklistDueDateCellLabel(for: checklist)
        }
    }

    @ViewBuilder
    private func checklistAssigneeCellLabel(for checklist: ChecklistTemplate) -> some View {
        if checklistHasExplicitAssignee(checklist) {
            Text(checklistAssigneeLabel(checklist))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        } else {
            Image(systemName: "person.crop.circle.dashed")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
    }

    @ViewBuilder
    private func checklistDueDateCellLabel(for checklist: ChecklistTemplate) -> some View {
        if checklist.dueDate == nil {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        } else {
            Text(checklistDueDateLabel(checklist))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(checklistDueDateColor(checklist))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
    }

    private func checklistDueDateEditor(for checklist: ChecklistTemplate) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Due Date")
                .font(.headline)
            DatePicker(
                "Due",
                selection: Binding(
                    get: { checklist.dueDate ?? Date() },
                    set: { newValue in
                        updateChecklistDueDate(checklist, dueDate: newValue)
                    }
                ),
                displayedComponents: [.date, .hourAndMinute]
            )
            .labelsHidden()

            HStack {
                Button("Clear") {
                    updateChecklistDueDate(checklist, dueDate: nil)
                    dueDateEditorChecklistID = nil
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("Done") {
                    dueDateEditorChecklistID = nil
                }
                .buttonStyle(.borderedProminent)
            }
        }
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
        let completedCount = checklist.items.filter(\.isDone).count
        let openCount = max(checklist.items.count - completedCount, 0)
        return openCount == checklist.items.count
            ? "\(openCount) open tasks"
            : "\(openCount) open • \(completedCount) done"
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
        let explicitName = checklist.assignedUserName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !explicitName.isEmpty { return explicitName }
        let explicitEmail = checklist.assignedUserEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !explicitEmail.isEmpty {
            return explicitEmail.components(separatedBy: "@").first ?? explicitEmail
        }
        return "Unassigned"
    }

    private func checklistHasExplicitAssignee(_ checklist: ChecklistTemplate) -> Bool {
        let assignedID = checklist.assignedUserID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !assignedID.isEmpty { return true }
        let assignedName = checklist.assignedUserName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !assignedName.isEmpty { return true }
        let assignedEmail = checklist.assignedUserEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !assignedEmail.isEmpty
    }

    private func checklistMemberDisplayName(for member: UserProfile) -> String {
        let trimmed = member.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return member.email.components(separatedBy: "@").first ?? member.email
    }

    private func updateChecklistAssignee(_ checklist: ChecklistTemplate, userID: String) {
        var updated = checklist
        let trimmedID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedID.isEmpty {
            updated.assignedUserID = nil
            updated.assignedUserName = nil
            updated.assignedUserEmail = nil
        } else if let member = assignableMembers.first(where: { $0.id == trimmedID }) {
            updated.assignedUserID = member.id
            updated.assignedUserName = checklistMemberDisplayName(for: member)
            updated.assignedUserEmail = member.email.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        store.saveChecklist(updated)
    }

    private func updateChecklistDueDate(_ checklist: ChecklistTemplate, dueDate: Date?) {
        var updated = checklist
        updated.dueDate = dueDate
        store.saveChecklist(updated)
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

    private func checklistCompletionFraction(for checklist: ChecklistTemplate) -> Double {
        guard !checklist.items.isEmpty else { return 0 }
        let completedCount = checklist.items.filter(\.isDone).count
        return Double(completedCount) / Double(checklist.items.count)
    }

    private func checklistProgressLabel(for checklist: ChecklistTemplate) -> String {
        "\(Int((checklistCompletionFraction(for: checklist) * 100).rounded()))%"
    }

    private func toggleChecklistCompletion(_ checklist: ChecklistTemplate) {
        guard !checklist.items.isEmpty else { return }
        var updated = checklist
        let shouldComplete = !isChecklistCompleted(checklist)
        updated.items = updated.items.map { item in
            var next = item
            next.isDone = shouldComplete
            next.completedAt = shouldComplete ? Date() : nil
            next.completedBy = shouldComplete ? checklistCompletionUserLabel() : nil
            return next
        }
        updated.completedAt = shouldComplete ? Date() : nil
        updated.completedBy = shouldComplete ? checklistCompletionUserLabel() : nil
        store.saveChecklist(updated)
        if selectedChecklist?.id == updated.id {
            selectedChecklist = updated
        }
    }

    private func checklistCompletionUserLabel() -> String {
        let displayName = store.user?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !displayName.isEmpty { return displayName }
        let email = store.user?.email.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !email.isEmpty { return email }
        return Auth.auth().currentUser?.email ?? "Unknown User"
    }

    private func dragTokenForChecklist(_ checklist: ChecklistTemplate) -> String {
        "checklist:\(checklist.id)"
    }

    private func dragTokenForGroup(_ group: String) -> String {
        "group:\(group)"
    }

    private func handleDroppedChecklistToken(_ token: String?, before target: ChecklistTemplate) -> Bool {
        guard let token, token.hasPrefix("checklist:") else { return false }
        let draggedID = String(token.dropFirst("checklist:".count))
        reorderChecklist(draggedID: draggedID, before: target)
        return true
    }

    private func handleDroppedGroupToken(_ token: String?, before targetGroup: String) -> Bool {
        guard store.canPersistChecklistGroupOrder else { return false }
        guard let token, token.hasPrefix("group:") else { return false }
        let draggedGroup = String(token.dropFirst("group:".count))
        var ordered = orderedGroupNames
        guard let sourceIndex = ordered.firstIndex(of: draggedGroup),
              let destinationIndex = ordered.firstIndex(of: targetGroup),
              sourceIndex != destinationIndex else { return false }
        let moved = ordered.remove(at: sourceIndex)
        ordered.insert(moved, at: destinationIndex)
        store.reorderChecklistGroups(ordered)
        return true
    }

    private func saveNewChecklistGroup() {
        let trimmed = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.addChecklistGroup(trimmed)
        newGroupName = ""
        isShowingAddGroup = false
    }

    private func reorderChecklist(draggedID: String, before target: ChecklistTemplate) {
        var ordered = store.checklists.sorted {
            if $0.position != $1.position { return $0.position < $1.position }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        guard let sourceIndex = ordered.firstIndex(where: { $0.id == draggedID }),
              let destinationIndex = ordered.firstIndex(where: { $0.id == target.id }),
              sourceIndex != destinationIndex else { return }
        var moved = ordered.remove(at: sourceIndex)
        moved.groupName = target.groupName
        ordered.insert(moved, at: destinationIndex)
        store.reorderChecklists(ordered)
    }

    private func checklistStatusBadge(for checklist: ChecklistTemplate) -> some View {
        let label: String
        let foreground: Color
        let background: Color

        if isChecklistCompleted(checklist) {
            label = "Done"
            foreground = .green
            background = Color.green.opacity(0.14)
        } else if let dueDate = checklist.dueDate, dueDate < Date() {
            label = "Overdue"
            foreground = .red
            background = Color.red.opacity(0.14)
        } else if let dueDate = checklist.dueDate, Calendar.current.isDateInToday(dueDate) {
            label = "Today"
            foreground = .orange
            background = Color.orange.opacity(0.14)
        } else {
            label = "Active"
            foreground = .secondary
            background = Color.white.opacity(0.08)
        }

        return Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(background)
            .clipShape(Capsule())
    }

    private func checklistRowBackground(for checklist: ChecklistTemplate) -> some View {
        let isSelected = selectedChecklist?.id == checklist.id
        if isSelected {
            return AnyView(
                RoundedRectangle(cornerRadius: 0, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
            )
        }
        return AnyView(
            RoundedRectangle(cornerRadius: 0, style: .continuous)
                .fill(Color.white.opacity(0.01))
        )
    }

    private func isAssignedToCurrentUser(_ checklist: ChecklistTemplate) -> Bool {
        guard let current = store.user else { return false }
        let currentID = current.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentEmail = current.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let explicitID = checklist.assignedUserID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !currentID.isEmpty && explicitID == currentID {
            return true
        }
        let checklistAssignedEmail = checklist.assignedUserEmail?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return !currentEmail.isEmpty && !checklistAssignedEmail.isEmpty && checklistAssignedEmail == currentEmail
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
    @State private var selectedTaskID: String?
    @State private var taskDraftTitle = ""
    @State private var taskDraftComment = ""
    @State private var taskDraftAssignedUserID = ""
    @State private var taskDraftHasDueDate = false
    @State private var taskDraftDueDate = Date()
    @State private var activeTaskCommentMentionQuery = ""
    @State private var newTaskSubtaskTitle = ""
    @State private var isUploadingTaskAttachment = false
    @State private var taskAttachmentError: String?
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
    private var canEditTasks: Bool { store.canEditChecklists }
    private var canManageChecklistDueDate: Bool { store.user?.isAdmin == true || store.user?.isOwner == true }
    private var isChecklistComplete: Bool { !checklist.items.isEmpty && checklist.items.allSatisfy(\.isDone) }
    private var checklistProgress: Double {
        guard !checklist.items.isEmpty else { return 0 }
        return Double(checklist.items.filter(\.isDone).count) / Double(checklist.items.count)
    }
    private var progressTint: Color { isChecklistComplete ? .green : .accentColor }
    private var assignableMembers: [UserProfile] {
        store.teamMembers.sorted {
            displayName(for: $0).localizedCaseInsensitiveCompare(displayName(for: $1)) == .orderedAscending
        }
    }
    private var showsAssignmentFeatures: Bool { store.teamHasChecklistTaskAssignmentFeatures }
    private var todoItemIndices: [Int] { checklist.items.indices.filter { !checklist.items[$0].isDone } }
    private var completedItemIndices: [Int] { checklist.items.indices.filter { checklist.items[$0].isDone } }
    private var selectedTaskIndex: Int? {
        guard let selectedTaskID else { return nil }
        return checklist.items.firstIndex(where: { $0.id == selectedTaskID })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(checklist.title)
                        .font(.system(size: 24, weight: .semibold))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            detailBadge(text: textValue(checklist.groupName), systemImage: "folder")
                            detailBadge(text: checklistProgressLabel(), systemImage: "chart.bar.fill")
                            detailBadge(text: "\(todoItemIndices.count) open", systemImage: "circle")
                            detailBadge(text: "\(completedItemIndices.count) done", systemImage: "checkmark.circle.fill")
                            if let dueDate = checklist.dueDate {
                                detailBadge(
                                    text: dueDateLabel(for: dueDate),
                                    systemImage: dueDate < Date() && !isChecklistComplete ? "exclamationmark.circle.fill" : "calendar"
                                )
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Progress")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(checklistProgressLabel())
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(progressTint)
                        }
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.08))
                                Capsule()
                                    .fill(progressTint.gradient)
                                    .frame(width: max(proxy.size.width * checklistProgress, checklistProgress > 0 ? 8 : 0))
                            }
                        }
                        .frame(height: 10)
                    }
                    .padding(.top, 4)
                }
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

            if isEditing {
                Form {
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
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Assignee")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if canAssignTasks {
                                Picker("Assignee", selection: checklistAssignmentSelection) {
                                    Text("Unassigned").tag("")
                                    ForEach(assignableMembers) { member in
                                        Text(displayName(for: member)).tag(member.id)
                                    }
                                }
                                .pickerStyle(.menu)
                            } else {
                                Text(checklistAssignmentLabel)
                                    .foregroundStyle(.secondary)
                            }
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

                    Section("Tasks") {
                        Text("Task details now open directly from the task list when checklist editing is off.")
                            .foregroundStyle(.secondary)
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
                            TextField("Comment (optional)", text: $newItemNotes, axis: .vertical)
                                .lineLimit(2...4)
                            HStack {
                                Spacer()
                                Button("Add Item") {
                                    let trimmed = newItemText.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !trimmed.isEmpty else { return }
                                    let trimmedNotes = newItemNotes.trimmingCharacters(in: .whitespacesAndNewlines)
                                    let newItem = makeChecklistItem(
                                        text: trimmed,
                                        notes: trimmedNotes,
                                        assignedUserID: newItemAssignedUserID,
                                        dueDate: newItemHasDueDate ? newItemDueDate : nil
                                    )
                                    checklist.items.append(newItem)
                                    store.saveChecklist(checklist)
                                    selectTask(id: newItem.id)
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
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            } else {
                HStack(alignment: .top, spacing: 18) {
                    checklistTaskListPane
                        .frame(width: 360)
                    selectedTaskInspector
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
        .navigationTitle(checklist.title)
        .onAppear {
            store.listenToTeamMembers()
            ensureSelectedTask()
        }
    }

    private func detailBadge(text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.06))
            .clipShape(Capsule())
    }

    private func checklistCompletionFraction() -> Double {
        checklistProgress
    }

    private func checklistProgressLabel() -> String {
        "\(Int((checklistCompletionFraction() * 100).rounded()))%"
    }

    private var checklistTaskListPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                taskSection(title: "To Do", indices: todoItemIndices)
                if !completedItemIndices.isEmpty {
                    taskSection(title: "Completed", indices: completedItemIndices)
                }
                if canEditTasks {
                    quickAddTaskRow
                }
            }
            .padding(16)
        }
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func taskSection(title: String, indices: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            if indices.isEmpty {
                Text(title == "To Do" ? "No open tasks" : "No completed tasks")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(indices, id: \.self) { index in
                    taskListRow(item: checklist.items[index], isSelected: checklist.items[index].id == selectedTaskID)
                }
            }
        }
    }

    private var quickAddTaskRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            TextField("Add task...", text: $newItemText)
                .textFieldStyle(.plain)
                .onSubmit {
                    addQuickTask()
                }

            Button("Add") {
                addQuickTask()
            }
            .buttonStyle(.plain)
            .foregroundStyle(newItemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .tertiary : .secondary)
            .disabled(newItemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
        )
    }

    private func taskListRow(item: ChecklistItem, isSelected: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                toggleItem(itemID: item.id)
                loadSelectedTaskDraftIfNeeded(for: item.id)
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(item.isDone ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)

            Button {
                selectTask(id: item.id)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.text)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if showsAssignmentFeatures || item.dueDate != nil {
                        taskMetadataRow(for: item)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(isSelected ? Color.accentColor.opacity(0.14) : taskCardBackground(for: item))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.white.opacity(0.06), lineWidth: 1)
        )
        .draggable("task:\(item.id)")
        .dropDestination(for: String.self) { items, _ in
            guard let token = items.first, token.hasPrefix("task:") else { return false }
            let draggedID = String(token.dropFirst("task:".count))
            reorderTask(draggedID: draggedID, before: item.id)
            return true
        }
    }

    @ViewBuilder
    private var selectedTaskInspector: some View {
        if let index = selectedTaskIndex, checklist.items.indices.contains(index) {
            let item = checklist.items[index]
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 10) {
                        markCompleteButton(for: item)

                        Spacer()

                        if canEditTasks {
                            Button(role: .destructive) {
                                checklist.items.remove(at: index)
                                updateChecklistCompletionMetadata()
                                store.saveChecklist(checklist)
                                ensureSelectedTask()
                            } label: {
                                Label("Delete Task", systemImage: "trash")
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Task title", text: $taskDraftTitle)
                            .textFieldStyle(.plain)
                            .font(.system(size: 28, weight: .semibold))
                        if showsAssignmentFeatures || item.dueDate != nil {
                            taskMetadataRow(for: item)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        detailFieldLabel("Assignee")
                        if canAssignTasks {
                            Picker("Assignee", selection: $taskDraftAssignedUserID) {
                                Text("Unassigned").tag("")
                                ForEach(assignableMembers) { member in
                                    Text(displayName(for: member)).tag(member.id)
                                }
                            }
                            .pickerStyle(.menu)
                        } else {
                            Text(assignmentLabel(for: item) ?? "Unassigned")
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        detailFieldLabel("Due date")
                        if canManageChecklistDueDate {
                            Toggle("Set due date", isOn: $taskDraftHasDueDate)
                            if taskDraftHasDueDate {
                                DatePicker("Task Due", selection: $taskDraftDueDate, displayedComponents: [.date, .hourAndMinute])
                                    .labelsHidden()
                            }
                        } else {
                            Text(item.dueDate.map { dueDateLabel(for: $0) } ?? "No due date")
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        detailFieldLabel("Comment")
                        TextEditor(text: taskCommentBinding)
                            .font(.body)
                            .frame(minHeight: 180)
                            .padding(8)
                            .background(Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
                            )
                        if let _ = currentMentionContext(in: taskDraftComment) {
                            taskCommentMentionSuggestions
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        detailFieldLabel("Subtasks")
                        if item.subtasks.isEmpty {
                            Text("No subtasks")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(item.subtasks.indices), id: \.self) { subtaskIndex in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 10) {
                                        Button {
                                            toggleSelectedTaskSubtask(at: subtaskIndex)
                                        } label: {
                                            Image(systemName: item.subtasks[subtaskIndex].isDone ? "checkmark.circle.fill" : "checkmark.circle")
                                                .foregroundStyle(item.subtasks[subtaskIndex].isDone ? Color.green : Color.secondary)
                                        }
                                        .buttonStyle(.plain)

                                        if canEditTasks {
                                            TextField("Subtask", text: selectedTaskSubtaskBinding(for: subtaskIndex))
                                                .textFieldStyle(.roundedBorder)
                                        } else {
                                            Text(item.subtasks[subtaskIndex].text)
                                        }

                                        if canEditTasks {
                                            Button(role: .destructive) {
                                                removeSelectedTaskSubtask(at: subtaskIndex)
                                            } label: {
                                                Image(systemName: "trash")
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }

                                    if item.subtasks[subtaskIndex].isDone,
                                       let completedAt = item.subtasks[subtaskIndex].completedAt {
                                        let completedBy = item.subtasks[subtaskIndex].completedBy?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                                        Text(
                                            completedBy.isEmpty
                                            ? "Completed on \(completedAt.formatted(date: .abbreviated, time: .shortened))"
                                            : "Completed by \(completedBy) on \(completedAt.formatted(date: .abbreviated, time: .shortened))"
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }

                        if canEditTasks {
                            HStack {
                                TextField("Add subtask", text: $newTaskSubtaskTitle)
                                    .onSubmit {
                                        addSelectedTaskSubtask()
                                    }
                                Button("Add") {
                                    addSelectedTaskSubtask()
                                }
                                .buttonStyle(.bordered)
                                .disabled(newTaskSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        detailFieldLabel("Attachments")
                        if item.attachments.isEmpty {
                            Text("No attachments")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(item.attachments) { attachment in
                                HStack {
                                    if let url = URL(string: attachment.url.trimmingCharacters(in: .whitespacesAndNewlines)) {
                                        Link(destination: url) {
                                            Label(attachment.name, systemImage: attachmentSystemImage(for: attachment.kind))
                                        }
                                    } else {
                                        Label(attachment.name, systemImage: attachmentSystemImage(for: attachment.kind))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if canEditTasks {
                                        Button(role: .destructive) {
                                            removeSelectedTaskAttachment(id: attachment.id)
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }

                        if canEditTasks {
                            Button {
                                pickTaskAttachment()
                            } label: {
                                Label("Add Attachment", systemImage: "paperclip")
                            }
                            .buttonStyle(.bordered)
                            if isUploadingTaskAttachment {
                                ProgressView("Uploading attachment…")
                            }
                            if let taskAttachmentError, !taskAttachmentError.isEmpty {
                                Text(taskAttachmentError)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }

                    if item.isDone, let completedAt = item.completedAt {
                        VStack(alignment: .leading, spacing: 4) {
                            detailFieldLabel("Completion")
                            if let completedBy = item.completedBy?.trimmingCharacters(in: .whitespacesAndNewlines),
                               !completedBy.isEmpty {
                                Text("Checked by \(completedBy)")
                            }
                            Text("Completed on \(completedAt.formatted(date: .abbreviated, time: .shortened))")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if canEditTasks {
                        HStack {
                            Spacer()
                            Button("Save Changes") {
                                saveSelectedTaskChanges()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(taskDraftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                .padding(20)
            }
            .background(Color.white.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Select a task")
                    .font(.title3.weight(.semibold))
                Text("Click a task to view details, add a comment, or mark it complete.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(20)
            .background(Color.white.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func markCompleteButton(for item: ChecklistItem) -> some View {
        if item.isDone {
            Button {
                toggleItem(itemID: item.id)
                loadSelectedTaskDraftIfNeeded(for: item.id)
            } label: {
                Label("Completed", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        } else {
            Button {
                toggleItem(itemID: item.id)
                loadSelectedTaskDraftIfNeeded(for: item.id)
            } label: {
                Label("Mark Complete", systemImage: "checkmark.circle")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
        }
    }

    private func detailFieldLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private var taskCommentBinding: Binding<String> {
        Binding(
            get: { taskDraftComment },
            set: { newValue in
                taskDraftComment = newValue
                updateTaskCommentMentionContext(for: newValue)
            }
        )
    }

    @ViewBuilder
    private var taskCommentMentionSuggestions: some View {
        let suggestions = mentionSuggestions(for: activeTaskCommentMentionQuery)
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(suggestions.prefix(6)) { member in
                    Button {
                        applyMentionToTaskDraft(member)
                    } label: {
                        Text(displayName(for: member))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    if member.id != suggestions.prefix(6).last?.id {
                        Divider()
                    }
                }
            }
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
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

    private var checklistAssignmentSelection: Binding<String> {
        Binding(
            get: { checklist.assignedUserID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" },
            set: { newValue in
                let trimmedID = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedID.isEmpty,
                      let member = assignableMembers.first(where: { $0.id == trimmedID }) else {
                    checklist.assignedUserID = nil
                    checklist.assignedUserName = nil
                    checklist.assignedUserEmail = nil
                    return
                }
                checklist.assignedUserID = member.id
                checklist.assignedUserName = displayName(for: member)
                checklist.assignedUserEmail = member.email.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        )
    }

    private var checklistAssignmentLabel: String {
        let assignedName = checklist.assignedUserName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !assignedName.isEmpty { return assignedName }
        let assignedEmail = checklist.assignedUserEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !assignedEmail.isEmpty {
            return assignedEmail.components(separatedBy: "@").first ?? assignedEmail
        }
        return "Unassigned"
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

    private func addQuickTask() {
        let trimmed = newItemText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let trimmedNotes = newItemNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let newItem = makeChecklistItem(
            text: trimmed,
            notes: trimmedNotes,
            assignedUserID: newItemAssignedUserID,
            dueDate: newItemHasDueDate ? newItemDueDate : nil
        )
        checklist.items.append(newItem)
        updateChecklistCompletionMetadata()
        store.saveChecklist(checklist)
        selectTask(id: newItem.id)
        newItemText = ""
        newItemNotes = ""
        newItemAssignedUserID = ""
        newItemHasDueDate = false
        newItemDueDate = Date()
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
            checklist.items[idx].subtasks = checklist.items[idx].subtasks.map { subtask in
                var updated = subtask
                updated.isDone = true
                updated.completedAt = updated.completedAt ?? Date()
                updated.completedBy = (updated.completedBy ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? completionUserLabel
                    : updated.completedBy
                return updated
            }
            checklist.items[idx].completedAt = Date()
            checklist.items[idx].completedBy = completionUserLabel
        } else {
            checklist.items[idx].completedAt = nil
            checklist.items[idx].completedBy = nil
        }
        updateChecklistCompletionMetadata()
        store.saveChecklist(checklist)
        ensureSelectedTask()
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
        ensureSelectedTask()
    }

    private func ensureSelectedTask() {
        if let selectedTaskID,
           checklist.items.contains(where: { $0.id == selectedTaskID }) {
            loadSelectedTaskDraftIfNeeded(for: selectedTaskID)
            return
        }

        if let firstOpen = checklist.items.first(where: { !$0.isDone }) {
            selectTask(id: firstOpen.id)
        } else if let first = checklist.items.first {
            selectTask(id: first.id)
        } else {
            selectedTaskID = nil
        }
    }

    private func selectTask(id: String) {
        selectedTaskID = id
        loadSelectedTaskDraftIfNeeded(for: id, force: true)
    }

    private func loadSelectedTaskDraftIfNeeded(for id: String, force: Bool = false) {
        guard force || selectedTaskID == id,
              let index = checklist.items.firstIndex(where: { $0.id == id }) else { return }
        let item = checklist.items[index]
        taskDraftTitle = item.text
        taskDraftComment = item.notes
        taskDraftAssignedUserID = item.assignedUserID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        taskDraftHasDueDate = item.dueDate != nil
        taskDraftDueDate = item.dueDate ?? checklist.dueDate ?? Date()
    }

    private func saveSelectedTaskChanges() {
        guard let index = selectedTaskIndex, checklist.items.indices.contains(index) else { return }
        checklist.items[index].text = taskDraftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        checklist.items[index].notes = taskDraftComment.trimmingCharacters(in: .whitespacesAndNewlines)
        applyAssignment(selectedUserID: taskDraftAssignedUserID, to: index)
        checklist.items[index].dueDate = taskDraftHasDueDate ? taskDraftDueDate : nil
        updateChecklistCompletionMetadata()
        store.saveChecklist(checklist)
        loadSelectedTaskDraftIfNeeded(for: checklist.items[index].id, force: true)
    }

    private func persistSelectedTaskMutation(_ mutate: (inout ChecklistItem) -> Void) {
        guard let index = selectedTaskIndex, checklist.items.indices.contains(index) else { return }
        checklist.items[index].text = taskDraftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        checklist.items[index].notes = taskDraftComment.trimmingCharacters(in: .whitespacesAndNewlines)
        applyAssignment(selectedUserID: taskDraftAssignedUserID, to: index)
        checklist.items[index].dueDate = taskDraftHasDueDate ? taskDraftDueDate : nil
        mutate(&checklist.items[index])
        updateChecklistCompletionMetadata()
        store.saveChecklist(checklist)
        loadSelectedTaskDraftIfNeeded(for: checklist.items[index].id, force: true)
    }

    private func selectedTaskSubtaskBinding(for index: Int) -> Binding<String> {
        Binding(
            get: {
                guard let selectedTaskIndex, checklist.items[selectedTaskIndex].subtasks.indices.contains(index) else { return "" }
                return checklist.items[selectedTaskIndex].subtasks[index].text
            },
            set: { newValue in
                persistSelectedTaskMutation { item in
                    guard item.subtasks.indices.contains(index) else { return }
                    item.subtasks[index].text = newValue
                }
            }
        )
    }

    private func addSelectedTaskSubtask() {
        let trimmed = newTaskSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        persistSelectedTaskMutation { item in
            item.subtasks.append(ChecklistSubtask(text: trimmed))
        }
        newTaskSubtaskTitle = ""
    }

    private func toggleSelectedTaskSubtask(at index: Int) {
        persistSelectedTaskMutation { item in
            guard item.subtasks.indices.contains(index) else { return }
            item.subtasks[index].isDone.toggle()
            if item.subtasks[index].isDone {
                item.subtasks[index].completedAt = Date()
                item.subtasks[index].completedBy = completionUserLabel
            } else {
                item.subtasks[index].completedAt = nil
                item.subtasks[index].completedBy = nil
            }
        }
    }

    private func removeSelectedTaskSubtask(at index: Int) {
        persistSelectedTaskMutation { item in
            guard item.subtasks.indices.contains(index) else { return }
            item.subtasks.remove(at: index)
        }
    }

    private func removeSelectedTaskAttachment(id: String) {
        persistSelectedTaskMutation { item in
            item.attachments.removeAll { $0.id == id }
        }
    }

    private func attachmentSystemImage(for kind: TicketAttachmentKind) -> String {
        switch kind {
        case .image: return "photo"
        case .video: return "video"
        case .document: return "paperclip"
        }
    }

    @MainActor
    private func pickTaskAttachment() {
        taskAttachmentError = nil
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.item]

        let handleSelection: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            uploadTaskAttachment(from: url, kind: inferredTaskAttachmentKind(for: url))
        }

        if let keyWindow = NSApp.keyWindow {
            panel.beginSheetModal(for: keyWindow, completionHandler: handleSelection)
        } else {
            handleSelection(panel.runModal())
        }
    }

    private func uploadTaskAttachment(from localURL: URL, kind: TicketAttachmentKind) {
        taskAttachmentError = nil
        isUploadingTaskAttachment = true
        let safeName = localURL.lastPathComponent.replacingOccurrences(of: " ", with: "_")
        let path = "checklistTaskAttachments/\(checklist.id)/\(selectedTaskID ?? UUID().uuidString)/\(UUID().uuidString)-\(safeName)"
        let storageRef = Storage.storage().reference().child(path)
        let metadata = StorageMetadata()
        metadata.contentType = taskAttachmentContentType(for: localURL, kind: kind)
        let didAccess = localURL.startAccessingSecurityScopedResource()

        storageRef.putFile(from: localURL, metadata: metadata) { _, error in
            if didAccess {
                localURL.stopAccessingSecurityScopedResource()
            }

            if let error {
                DispatchQueue.main.async {
                    isUploadingTaskAttachment = false
                    taskAttachmentError = "Attachment upload failed: \(error.localizedDescription)"
                }
                return
            }

            storageRef.downloadURL { url, downloadError in
                DispatchQueue.main.async {
                    isUploadingTaskAttachment = false
                    if let downloadError {
                        taskAttachmentError = "Attachment upload failed: \(downloadError.localizedDescription)"
                        return
                    }
                    guard let urlString = url?.absoluteString else { return }
                    persistSelectedTaskMutation { item in
                        item.attachments.append(
                            ChecklistTaskAttachment(url: urlString, name: safeName, kind: kind)
                        )
                    }
                }
            }
        }
    }

    private func inferredTaskAttachmentKind(for url: URL) -> TicketAttachmentKind {
        let ext = url.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "heic", "gif", "webp"].contains(ext) {
            return .image
        }
        if ["mov", "mp4", "m4v", "avi"].contains(ext) {
            return .video
        }
        return .document
    }

    private func taskAttachmentContentType(for url: URL, kind: TicketAttachmentKind) -> String {
        if let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType {
            return type
        }
        switch kind {
        case .image: return "image/jpeg"
        case .video: return "video/quicktime"
        case .document: return "application/octet-stream"
        }
    }

    private func reorderTask(draggedID: String, before targetID: String) {
        guard let sourceIndex = checklist.items.firstIndex(where: { $0.id == draggedID }),
              let destinationIndex = checklist.items.firstIndex(where: { $0.id == targetID }),
              sourceIndex != destinationIndex else { return }
        let moved = checklist.items.remove(at: sourceIndex)
        checklist.items.insert(moved, at: destinationIndex)
        updateChecklistCompletionMetadata()
        store.saveChecklist(checklist)
        ensureSelectedTask()
    }

    private func mentionSuggestions(for query: String) -> [UserProfile] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return store.teamMembers
            .filter { member in
                let email = member.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if q.isEmpty { return true }
                let name = displayName(for: member).lowercased()
                let localPart = email.split(separator: "@").first.map(String.init) ?? ""
                return name.contains(q) || email.contains(q) || localPart.contains(q)
            }
            .sorted { displayName(for: $0).localizedCaseInsensitiveCompare(displayName(for: $1)) == .orderedAscending }
    }

    private func currentMentionContext(in text: String) -> (range: Range<String.Index>, query: String)? {
        guard let atIndex = text.lastIndex(of: "@") else { return nil }
        if atIndex != text.startIndex {
            let previous = text[text.index(before: atIndex)]
            if !previous.isWhitespace { return nil }
        }
        let queryStart = text.index(after: atIndex)
        let queryPart = text[queryStart...]
        if queryPart.contains(where: { $0.isWhitespace }) { return nil }
        return (atIndex..<text.endIndex, String(queryPart))
    }

    private func updateTaskCommentMentionContext(for text: String) {
        if let context = currentMentionContext(in: text) {
            activeTaskCommentMentionQuery = context.query
        } else {
            activeTaskCommentMentionQuery = ""
        }
    }

    private func mentionToken(for member: UserProfile) -> String {
        let name = displayName(for: member).trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            return name.lowercased().replacingOccurrences(of: " ", with: ".")
        }
        let email = member.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return email.split(separator: "@").first.map(String.init) ?? "user"
    }

    private func applyMentionToTaskDraft(_ member: UserProfile) {
        guard let context = currentMentionContext(in: taskDraftComment) else { return }
        taskDraftComment.replaceSubrange(context.range, with: "@\(mentionToken(for: member)) ")
        updateTaskCommentMentionContext(for: taskDraftComment)
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
    let section: MacSettingsSection
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
                sectionContent

                if !resultMessage.isEmpty {
                    Text(resultMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color.clear)
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

    @ViewBuilder
    private var sectionContent: some View {
        switch section {
        case .importData:
            importContent
        case .locationsRooms:
            locationsRoomsContent
        case .tickets:
            ticketsContent
        case .integrations:
            integrationsContent
        case .ndi, .midi, .users:
            EmptyView()
        }
    }

    private var locationsRoomsContent: some View {
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
        }
    }

    private var ticketsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
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
        }
    }

    private var importContent: some View {
        VStack(alignment: .leading, spacing: 18) {
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

            GroupBox("Reset") {
                VStack(alignment: .leading, spacing: 10) {
                    resetButton("Delete All Assets", action: .deleteAllGear)
                    resetButton("Delete Audio Patchsheet", action: .deleteAudioPatchsheet)
                    resetButton("Delete Video Patchsheet", action: .deleteVideoPatchsheet)
                    resetButton("Delete Lighting Patchsheet", action: .deleteLightingPatchsheet)
                }
            }
        }
    }

    private var integrationsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            if canManageIntegrations {
                GroupBox("Freshservice") {
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
                Toggle("Can edit run of show", isOn: $user.canEditRunOfShow)
                    .onChange(of: user.canEditRunOfShow) { _, value in
                        updatePermission(key: "canEditRunOfShow", value: value)
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
                    Toggle("Run of Show", isOn: $user.canSeeRunOfShow)
                        .onChange(of: user.canSeeRunOfShow) { _, value in
                            updatePermission(key: "canSeeRunOfShow", value: value)
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
                case "canEditRunOfShow":
                    self.user.canEditRunOfShow = value
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
                case "canSeeRunOfShow":
                    self.user.canSeeRunOfShow = value
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
