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
    private static let maxRateLimitRetries = 2
    private static var didLogAssetDetailSample = false
    private static var didLogAssetDetailAttempt = false
    private static let objectRequestTimeout: TimeInterval = 15

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

    private static func retryDelay(for response: HTTPURLResponse, attempt: Int) -> TimeInterval {
        if let retryAfter = response.value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespacesAndNewlines),
           let seconds = TimeInterval(retryAfter),
           seconds > 0 {
            return min(seconds, 30)
        }

        let backoff = pow(2.0, Double(attempt))
        return min(backoff, 30)
    }

    private static func rateLimitError(for response: HTTPURLResponse) -> Error {
        let delay = Int(ceil(retryDelay(for: response, attempt: maxRateLimitRetries)))
        return NSError(
            domain: "Freshservice",
            code: response.statusCode,
            userInfo: [
                NSLocalizedDescriptionKey: "Freshservice rate-limited the request. Wait \(delay) seconds and try again."
            ]
        )
    }

    private static func performListRequest(
        apiKey: String,
        apiUrl: String,
        endpoint: String,
        queryItems: [URLQueryItem] = [],
        attempt: Int = 0,
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
        request.timeoutInterval = objectRequestTimeout
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
                if httpResponse.statusCode == 429, attempt < maxRateLimitRetries {
                    let delay = retryDelay(for: httpResponse, attempt: attempt)
                    DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                        performListRequest(
                            apiKey: apiKey,
                            apiUrl: apiUrl,
                            endpoint: endpoint,
                            queryItems: queryItems,
                            attempt: attempt + 1,
                            completion: completion
                        )
                    }
                    return
                }

                if httpResponse.statusCode == 429 {
                    completion(.failure(rateLimitError(for: httpResponse)))
                    return
                }

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

    private static func performObjectRequest(
        apiKey: String,
        apiUrl: String,
        endpoint: String,
        queryItems: [URLQueryItem] = [],
        attempt: Int = 0,
        completion: @escaping (Result<[String: Any], Error>) -> Void
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
                if httpResponse.statusCode == 429, attempt < maxRateLimitRetries {
                    let delay = retryDelay(for: httpResponse, attempt: attempt)
                    DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                        performObjectRequest(
                            apiKey: apiKey,
                            apiUrl: apiUrl,
                            endpoint: endpoint,
                            queryItems: queryItems,
                            attempt: attempt + 1,
                            completion: completion
                        )
                    }
                    return
                }

                if httpResponse.statusCode == 429 {
                    completion(.failure(rateLimitError(for: httpResponse)))
                    return
                }

                completion(.failure(NSError(
                    domain: "Freshservice",
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: extractErrorMessage(from: data, response: httpResponse)]
                )))
                return
            }

            do {
                let jsonObject = try JSONSerialization.jsonObject(with: data)
                if let json = jsonObject as? [String: Any] {
                    completion(.success(json))
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
        maxPages: Int = 300,
        completion: @escaping (Result<([[String: Any]], Bool), Error>) -> Void
    ) {
        func fetchPage(_ page: Int, collected: [[String: Any]]) {
            let queryItems = [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "per_page", value: String(perPage)),
                URLQueryItem(name: "include", value: "type_fields")
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

    static func fetchLocationsWithAPIKey(
        apiKey: String,
        apiUrl: String,
        completion: @escaping (Result<[String: String], Error>) -> Void
    ) {
        func fetchPage(_ page: Int, collected: [String: String]) {
            let queryItems = [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "per_page", value: "100")
            ]
            performListRequest(apiKey: apiKey, apiUrl: apiUrl, endpoint: "api/v2/locations", queryItems: queryItems) { result in
                switch result {
                case .success(let items):
                    var map = collected
                    for item in items {
                        guard let name = item["name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                        if let idInt = item["id"] as? Int {
                            map[String(idInt)] = name
                        } else if let idString = item["id"] as? String, !idString.isEmpty {
                            map[idString] = name
                        }
                    }
                    if items.count >= 100 {
                        fetchPage(page + 1, collected: map)
                    } else {
                        completion(.success(map))
                    }
                case .failure:
                    completion(.success(collected))
                }
            }
        }
        fetchPage(1, collected: [:])
    }

    static func fetchAssetTypesWithAPIKey(
        apiKey: String,
        apiUrl: String,
        completion: @escaping (Result<[String: String], Error>) -> Void
    ) {
        func fetchPage(_ page: Int, collected: [String: String]) {
            let queryItems = [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "per_page", value: "100")
            ]
            performListRequest(apiKey: apiKey, apiUrl: apiUrl, endpoint: "api/v2/asset_types", queryItems: queryItems) { result in
                switch result {
                case .success(let items):
                    var map = collected
                    for item in items {
                        guard let name = item["name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                        if let idInt = item["id"] as? Int {
                            map[String(idInt)] = name
                        } else if let idString = item["id"] as? String, !idString.isEmpty {
                            map[idString] = name
                        }
                    }
                    if items.count >= 100 {
                        fetchPage(page + 1, collected: map)
                    } else {
                        completion(.success(map))
                    }
                case .failure:
                    completion(.success(collected))
                }
            }
        }
        fetchPage(1, collected: [:])
    }

    static func fetchAllAssetsForImportWithAPIKey(
        apiKey: String,
        apiUrl: String,
        perPage: Int = 100,
        maxPages: Int = 300,
        completion: @escaping (Result<([[String: Any]], Bool), Error>) -> Void
    ) {
        fetchAllLegacyAssetsWithAPIKey(
            apiKey: apiKey,
            apiUrl: apiUrl,
            perPage: perPage,
            maxPages: maxPages
        ) { legacyResult in
            switch legacyResult {
            case .success:
                completion(legacyResult)
            case .failure:
                fetchAllAssetsWithAPIKey(
                    apiKey: apiKey,
                    apiUrl: apiUrl,
                    perPage: perPage,
                    maxPages: maxPages,
                    completion: completion
                )
            }
        }
    }

    private static func fetchAllLegacyAssetsWithAPIKey(
        apiKey: String,
        apiUrl: String,
        perPage: Int,
        maxPages: Int,
        completion: @escaping (Result<([[String: Any]], Bool), Error>) -> Void
    ) {
        func fetchPage(_ page: Int, collected: [[String: Any]]) {
            let queryItems = [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "per_page", value: String(perPage))
            ]
            performListRequest(apiKey: apiKey, apiUrl: apiUrl, endpoint: "cmdb/items.json", queryItems: queryItems) { result in
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

    static func fetchAssetDetailsWithAPIKey(
        apiKey: String,
        apiUrl: String,
        assetID: String,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        if !didLogAssetDetailAttempt {
            didLogAssetDetailAttempt = true
            print("Freshservice asset detail request starting for asset id:", assetID)
        }
        performObjectRequest(
            apiKey: apiKey,
            apiUrl: apiUrl,
            endpoint: "api/v2/assets/\(assetID)"
        ) { result in
            switch result {
            case .success(let json):
                let objectKeys = ["asset", "config_item", "ci", "item", "data"]
                for key in objectKeys {
                    if let object = json[key] as? [String: Any] {
                        if !didLogAssetDetailSample {
                            didLogAssetDetailSample = true
                            let sortedKeys = object.keys.sorted()
                            print("Freshservice asset detail sample keys:", sortedKeys.joined(separator: ", "))
                        }
                        completion(.success(object))
                        return
                    }
                }

                if json["id"] != nil || json["display_id"] != nil || json["name"] != nil {
                    if !didLogAssetDetailSample {
                        didLogAssetDetailSample = true
                        let sortedKeys = json.keys.sorted()
                        print("Freshservice asset detail sample keys:", sortedKeys.joined(separator: ", "))
                    }
                    completion(.success(json))
                } else {
                    print("Freshservice asset detail response missing asset object for id:", assetID)
                    completion(.failure(NSError(
                        domain: "Freshservice",
                        code: 0,
                        userInfo: [NSLocalizedDescriptionKey: "Freshservice asset detail response was missing the asset object."]
                    )))
                }
            case .failure(let error):
                print("Freshservice asset detail request failed for id \(assetID):", error.localizedDescription)
                completion(.failure(error))
            }
        }
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
    case overview
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
        case .overview: return "Overview"
        case .customize: return "Settings"
        case .users: return "Users"
        case .account: return "Account"
        }
    }

    var icon: String {
        switch self {
        case .chat: return "message"
        case .patchsheet: return "square.grid.3x2"
        case .runOfShow: return "music.note.list"
        case .training: return "graduationcap"
        case .gear: return "shippingbox"
        case .tickets: return "ticket"
        case .checklists: return "checklist"
        case .ideas: return "lightbulb"
        case .overview: return "square.grid.2x2"
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
    case overview = "Overview"
    case ndi = "NDI"
    case midi = "MIDI"
    case users = "Users"

    var id: String { rawValue }
}

private struct MacOverviewSourceOption: Identifiable, Equatable {
    let id: String
    let title: String
    let systemImage: String
}

private enum MacNDIOverviewSourceID {
    static let runOfShowLive = "runOfShowLive"
    static let stagePlot = "stagePlot"
    static let setlist = "setlist"
    static let smaart = "smaart"
    static let timecode = "timecode"
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
    @EnvironmentObject private var automaticMessaging: MacAutomaticMessagingController
    @State private var selectedRoute: MacRoute? = .chat
    @State private var draggingSidebarRoute: MacRoute?
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
            case .overview:
                return store.user?.normalizedSubscriptionTier != "free"
            case .users:
                return store.user?.isAdmin == true || store.user?.isOwner == true
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
                .onChange(of: sidebarRoutes.map(\.rawValue)) { _, _ in
                    if let selectedRoute, !sidebarRoutes.contains(selectedRoute) {
                        self.selectedRoute = sidebarRoutes.first
                    }
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
        List {
            ForEach(sidebarRoutes) { route in
                Button {
                    selectedRoute = route
                } label: {
                    Label(route.title, systemImage: route.icon)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedRoute == route ? Color.accentColor : Color.primary)
                .listRowBackground(
                    selectedRoute == route
                        ? Color.accentColor.opacity(0.15)
                        : Color.clear
                )
                .onDrag {
                    draggingSidebarRoute = route
                    return NSItemProvider(object: route.rawValue as NSString)
                }
                .onDrop(
                    of: [.text],
                    delegate: MacSidebarRouteDropDelegate(
                        targetRoute: route,
                        routes: sidebarRoutes,
                        draggingRoute: $draggingSidebarRoute,
                        persistRoutes: persistSidebarRoutes
                    )
                )
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("ProdConnect")
        .navigationSplitViewColumnWidth(min: 180, ideal: 205, max: 240)
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
        case .overview:
            MacOverviewMultiview()
                .environmentObject(store)
                .environmentObject(ndiSettings)
        case .customize:
            MacSettingsView()
                .environmentObject(store)
                .environmentObject(ndiSettings)
                .environmentObject(runOfShowControls)
                .environmentObject(automaticMessaging)
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

}

private struct MacSidebarRouteDropDelegate: DropDelegate {
    let targetRoute: MacRoute
    let routes: [MacRoute]
    @Binding var draggingRoute: MacRoute?
    let persistRoutes: ([MacRoute]) -> Void

    func dropEntered(info: DropInfo) {
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let draggingRoute,
              draggingRoute != targetRoute,
              let fromIndex = routes.firstIndex(of: draggingRoute),
              let toIndex = routes.firstIndex(of: targetRoute) else {
            self.draggingRoute = nil
            return false
        }

        var reordered = routes
        let moved = reordered.remove(at: fromIndex)
        reordered.insert(moved, at: toIndex)
        persistRoutes(reordered)
        self.draggingRoute = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
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
    @State private var channelSettingsDraft: ChatChannel?

    private var canManageChannels: Bool {
        store.user?.isAdmin == true || store.user?.isOwner == true
    }

    private var currentEmail: String? {
        store.user?.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var groupChannels: [ChatChannel] {
        store.channels
            .filter { $0.kind == .group }
            .filter { channel in
                guard !canManageChannels, let currentEmail else { return true }
                if channel.isHidden { return false }
                let hiddenUsers = Set(channel.hiddenUserEmails.map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                })
                return !hiddenUsers.contains(currentEmail)
            }
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
        let visibleChannels = groupChannels + directChannels
        return visibleChannels.first(where: { $0.id == selectedChannelID }) ?? groupChannels.first ?? directChannels.first
    }

    private func canSendMessages(in channel: ChatChannel) -> Bool {
        if canManageChannels { return true }
        guard let currentEmail else { return false }
        if channel.isReadOnly { return false }
        let readOnlyUsers = Set(channel.readOnlyUserEmails.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })
        return !readOnlyUsers.contains(currentEmail)
    }

    private func canEditOrDeleteMessages(in channel: ChatChannel) -> Bool {
        canManageChannels || canSendMessages(in: channel)
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
                    .disabled(!canManageChannels)
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
                                                        .disabled(!canEditOrDeleteMessages(in: channel))

                                                        Button("Delete", role: .destructive) {
                                                            pendingDeleteMessage = message
                                                        }
                                                        .disabled(!canEditOrDeleteMessages(in: channel))
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
                                    .disabled(!canSendMessages(in: channel) || isUploadingAttachment || editingMessageID != nil)

                                    Button {
                                        pickAttachment(allowedTypes: [.data], preferredKind: .file)
                                    } label: {
                                        Image(systemName: "paperclip")
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!canSendMessages(in: channel) || isUploadingAttachment || editingMessageID != nil)

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
                                    .disabled(!canSendMessages(in: channel) || isUploadingAttachment)
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

                                if !canSendMessages(in: channel) {
                                    Text("Read-only channel. Only admins can post.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
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
                        .toolbar {
                            if canManageChannels && channel.kind == .group {
                                ToolbarItem(placement: .primaryAction) {
                                    Button {
                                        channelSettingsDraft = channel
                                    } label: {
                                        Image(systemName: "slider.horizontal.3")
                                    }
                                }
                            }
                        }
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
        .sheet(item: $channelSettingsDraft) { draft in
            MacChannelSettingsView(channel: draft) { updated in
                store.saveChannel(updated)
                selectedChannelID = updated.id
            }
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
        guard let channel = selectedChannel, canEditOrDeleteMessages(in: channel) else { return }
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
        guard canSendMessages(in: channel) else { return }
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
        guard canEditOrDeleteMessages(in: channel) else { return }
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

private struct MacChannelSettingsView: View {
    @EnvironmentObject private var store: ProdConnectStore
    @Environment(\.dismiss) private var dismiss
    @State private var channel: ChatChannel
    @State private var channelName: String
    let onSave: (ChatChannel) -> Void

    init(channel: ChatChannel, onSave: @escaping (ChatChannel) -> Void) {
        _channel = State(initialValue: channel)
        _channelName = State(initialValue: channel.name)
        self.onSave = onSave
    }

    private var trimmedChannelName: String {
        channelName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Channel Name", text: $channelName)
                }

                Section("Permissions") {
                    Toggle("Read-only for non-admins", isOn: $channel.isReadOnly)
                    Toggle("Hidden from non-admins", isOn: $channel.isHidden)
                }

                Section("Read-only users") {
                    ForEach(store.teamMembers) { member in
                        Toggle(isOn: Binding(
                            get: {
                                channel.readOnlyUserEmails.contains(member.email)
                            },
                            set: { isOn in
                                if isOn {
                                    if !channel.readOnlyUserEmails.contains(member.email) {
                                        channel.readOnlyUserEmails.append(member.email)
                                    }
                                } else {
                                    channel.readOnlyUserEmails.removeAll { $0 == member.email }
                                }
                            }
                        )) {
                            Text(member.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? member.email : member.displayName)
                        }
                    }
                }

                Section("Hidden users") {
                    ForEach(store.teamMembers) { member in
                        Toggle(isOn: Binding(
                            get: {
                                channel.hiddenUserEmails.contains(member.email)
                            },
                            set: { isOn in
                                if isOn {
                                    if !channel.hiddenUserEmails.contains(member.email) {
                                        channel.hiddenUserEmails.append(member.email)
                                    }
                                } else {
                                    channel.hiddenUserEmails.removeAll { $0 == member.email }
                                }
                            }
                        )) {
                            Text(member.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? member.email : member.displayName)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Channel Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        channel.name = trimmedChannelName
                        onSave(channel)
                        dismiss()
                    }
                    .disabled(trimmedChannelName.isEmpty)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 620)
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
    @State private var micboardMicrophoneDrafts: [String: String] = [:]
    @State private var micboardInEarMonitorDrafts: [String: String] = [:]
    private enum PatchsheetFocusedField: Hashable {
        case notes(String)
        case micboardMicrophone(String)
        case micboardInEarMonitor(String)
    }
    @FocusState private var focusedPatchsheetField: PatchsheetFocusedField?
    @State private var isExporting = false

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
    private var hasMicboardFeature: Bool {
        store.user?.normalizedSubscriptionTier != "free"
    }
    private var canManageMicboard: Bool {
        hasMicboardFeature && store.canEditPatchsheet
    }
    private var showsMicboardColumn: Bool {
        selectedCategory == "Audio" && hasMicboardFeature
    }
    private var showsMicboardAssignmentColumns: Bool {
        selectedCategory == "Audio" && hasMicboardFeature
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
    private var patchsheetMicboardAssignmentColumnWidth: CGFloat { 125 * patchsheetZoom }
    private var patchsheetOrderColumnWidth: CGFloat { store.canEditPatchsheet ? 78 : 0 }
    private var patchsheetNDIColumnWidth: CGFloat { 72 }
    private var patchsheetMicboardColumnWidth: CGFloat { 92 }
    private var patchsheetCheckboxCellHorizontalPadding: CGFloat { 8 }
    private var patchsheetPaddedTextColumnCount: Int {
        3
            + (showsLightingUniverseColumn ? 1 : 0)
            + 1
            + (showsMicboardAssignmentColumns ? 2 : 0)
    }
    private var patchsheetTableWidth: CGFloat {
        patchsheetNameColumnWidth
            + patchsheetInputColumnWidth
            + patchsheetOutputColumnWidth
            + (showsLightingUniverseColumn ? patchsheetUniverseColumnWidth : 0)
            + patchsheetNotesColumnWidth
            + (showsMicboardAssignmentColumns ? patchsheetMicboardAssignmentColumnWidth * 2 : 0)
            + patchsheetOrderColumnWidth
            + (showsMicboardColumn ? patchsheetMicboardColumnWidth : 0)
            + (hasNDIFeature ? patchsheetNDIColumnWidth : 0)
            + CGFloat(patchsheetPaddedTextColumnCount) * 28
            + (showsMicboardColumn ? patchsheetCheckboxCellHorizontalPadding * 2 : 0)
            + (hasNDIFeature ? patchsheetCheckboxCellHorizontalPadding * 2 : 0)
    }
    private var patchsheetHeaderFont: Font { .system(size: 11 * patchsheetZoom, weight: .semibold) }
    private var patchsheetRowFont: Font { .system(size: 13 * patchsheetZoom) }
    private var patchsheetEmphasisFont: Font { .system(size: 13 * patchsheetZoom, weight: .semibold) }
    private var patchsheetCellVerticalPadding: CGFloat { 10 * patchsheetZoom }
    private var allFilteredNDIEnabled: Bool { !filtered.isEmpty && filtered.allSatisfy(\.ndiEnabled) }
    private var allFilteredMicboardEnabled: Bool { !filtered.isEmpty && filtered.allSatisfy(\.micboardEnabled) }
    private var patchsheetBulkNDISymbolName: String {
        if allFilteredNDIEnabled { return "checkmark.square.fill" }
        return "square"
    }
    private var patchsheetBulkMicboardSymbolName: String {
        if allFilteredMicboardEnabled { return "checkmark.square.fill" }
        return "square"
    }

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

                Button(action: exportPatchsheet) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .disabled(isExporting || filtered.isEmpty)

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
        .onChange(of: focusedPatchsheetField) { oldValue, newValue in
            guard oldValue != newValue, let oldValue else { return }
            saveDraft(for: oldValue)
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
            if showsMicboardAssignmentColumns {
                patchsheetHeaderCell("Microphone", width: patchsheetMicboardAssignmentColumnWidth)
                patchsheetHeaderCell("Monitor", width: patchsheetMicboardAssignmentColumnWidth)
            }
            if store.canEditPatchsheet {
                patchsheetOrderHeaderCell
            }
            if showsMicboardColumn {
                patchsheetMicboardHeaderCell
            }
            if hasNDIFeature {
                patchsheetNDIHeaderCell
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

    private var patchsheetOrderHeaderCell: some View {
        Text("Order")
            .font(patchsheetHeaderFont)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .frame(width: patchsheetOrderColumnWidth, alignment: .center)
            .padding(.vertical, 11 * patchsheetZoom)
    }

    private var patchsheetNDIHeaderCell: some View {
        HStack(spacing: 6) {
            Text("NDI")
                .font(patchsheetHeaderFont)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            Button {
                setAllFilteredNDIEnabled(!allFilteredNDIEnabled)
            } label: {
                Image(systemName: patchsheetBulkNDISymbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(canManageNDI ? (allFilteredNDIEnabled ? .green : .secondary) : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!canManageNDI || filtered.isEmpty)
        }
        .frame(width: patchsheetNDIColumnWidth + (patchsheetCheckboxCellHorizontalPadding * 2), alignment: .center)
        .padding(.vertical, 11 * patchsheetZoom)
    }

    private var patchsheetMicboardHeaderCell: some View {
        HStack(spacing: 6) {
            Text("Micboard")
                .font(patchsheetHeaderFont)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            Button {
                setAllFilteredMicboardEnabled(!allFilteredMicboardEnabled)
            } label: {
                Image(systemName: patchsheetBulkMicboardSymbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(canManageMicboard ? (allFilteredMicboardEnabled ? .green : .secondary) : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!canManageMicboard || filtered.isEmpty)
        }
        .frame(width: patchsheetMicboardColumnWidth + (patchsheetCheckboxCellHorizontalPadding * 2), alignment: .center)
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
            if showsMicboardAssignmentColumns {
                patchsheetMicboardAssignmentCell(for: patch, field: .micboardMicrophone(patch.id), title: "Microphone")
                patchsheetMicboardAssignmentCell(for: patch, field: .micboardInEarMonitor(patch.id), title: "Monitor")
            }
            if store.canEditPatchsheet {
                patchsheetOrderCell(for: patch)
            }
            if showsMicboardColumn {
                patchsheetMicboardCell(for: patch)
            }
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
            .focused($focusedPatchsheetField, equals: .notes(patch.id))
            .disabled(!store.canEditPatchsheet)
            .onSubmit {
                saveDraft(for: .notes(patch.id))
            }
    }

    private func patchsheetMicboardAssignmentCell(for patch: PatchRow, field: PatchsheetFocusedField, title: String) -> some View {
        TextField(title, text: micboardAssignmentBinding(for: patch, field: field))
            .textFieldStyle(.plain)
            .font(patchsheetRowFont)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .frame(width: patchsheetMicboardAssignmentColumnWidth, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, patchsheetCellVerticalPadding)
            .focused($focusedPatchsheetField, equals: field)
            .disabled(!store.canEditPatchsheet)
            .onSubmit {
                saveDraft(for: field)
            }
    }

    private func patchsheetNDICell(for patch: PatchRow) -> some View {
        Button {
            toggleNDI(for: patch)
        } label: {
            Image(systemName: patch.ndiEnabled ? "checkmark.square.fill" : "square")
                .foregroundStyle(canManageNDI ? (patch.ndiEnabled ? .green : .secondary) : .secondary)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: patchsheetNDIColumnWidth + (patchsheetCheckboxCellHorizontalPadding * 2), alignment: .center)
                .padding(.vertical, patchsheetCellVerticalPadding)
        }
        .buttonStyle(.plain)
        .disabled(!canManageNDI)
    }

    private func patchsheetMicboardCell(for patch: PatchRow) -> some View {
        Button {
            toggleMicboard(for: patch)
        } label: {
            Image(systemName: patch.micboardEnabled ? "checkmark.square.fill" : "square")
                .foregroundStyle(canManageMicboard ? (patch.micboardEnabled ? .green : .secondary) : .secondary)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: patchsheetMicboardColumnWidth + (patchsheetCheckboxCellHorizontalPadding * 2), alignment: .center)
                .padding(.vertical, patchsheetCellVerticalPadding)
        }
        .buttonStyle(.plain)
        .disabled(!canManageMicboard)
    }

    private var primaryPlaceholder: String {
        switch selectedCategory {
        case "Video": return "Source"
        case "Lighting": return "DMX Channel"
        default: return "Input"
        }
    }

    private func patchsheetOrderCell(for patch: PatchRow) -> some View {
        let ids = filtered.map(\.id)
        let currentIndex = ids.firstIndex(of: patch.id)
        let canMoveUp = currentIndex.map { $0 > 0 } ?? false
        let canMoveDown = currentIndex.map { $0 < ids.count - 1 } ?? false

        return HStack(spacing: 6) {
            Button {
                movePatch(patch, direction: -1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.plain)
            .disabled(!canMoveUp)

            Button {
                movePatch(patch, direction: 1)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.plain)
            .disabled(!canMoveDown)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.secondary)
        .frame(width: patchsheetOrderColumnWidth, alignment: .center)
        .padding(.vertical, patchsheetCellVerticalPadding)
    }

    private var secondaryPlaceholder: String {
        switch selectedCategory {
        case "Video": return "Destination"
        case "Lighting": return "Channel Count"
        default: return "Output"
        }
    }

    private func exportPatchsheet() {
        guard !filtered.isEmpty else { return }
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                exportPatchsheet()
            }
            return
        }
        isExporting = true
        defer { isExporting = false }

        let header = [
            "Name",
            inputColumnTitle,
            outputColumnTitle,
            "Universe",
            "Notes",
            "Microphone",
            "Monitor",
            "Category",
            "Campus",
            "Room",
            "NDI Enabled"
        ].map(csvEscaped).joined(separator: ",")

        let rows = filtered.map { patch in
            [
                patch.name,
                patch.input,
                patch.output,
                patch.universe ?? "",
                patch.notes,
                patch.micboardMicrophone,
                patch.micboardInEarMonitor,
                patch.category,
                patch.campus,
                patch.room,
                patch.ndiEnabled ? "Yes" : "No"
            ].map(csvEscaped).joined(separator: ",")
        }

        let csv = "\u{FEFF}" + ([header] + rows).joined(separator: "\n")
        let savePanel = NSSavePanel()
        savePanel.title = "Export Patchsheet"
        savePanel.nameFieldStringValue = "Patchsheet-\(selectedCategory.replacingOccurrences(of: " ", with: "")).csv"
        savePanel.allowedContentTypes = [.commaSeparatedText]
        savePanel.canCreateDirectories = true

        guard savePanel.runModal() == .OK, let url = savePanel.url else { return }

        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            print("Patchsheet export failed:", error.localizedDescription)
        }
    }

    private func csvEscaped(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
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

    private func toggleMicboard(for patch: PatchRow) {
        guard canManageMicboard, patch.category == "Audio" else { return }
        var updated = patch
        updated.micboardEnabled.toggle()
        store.savePatch(updated)
        if selectedPatch?.id == updated.id {
            selectedPatch = updated
        }
    }

    private func setAllFilteredNDIEnabled(_ isEnabled: Bool) {
        guard canManageNDI else { return }

        for patch in filtered where patch.ndiEnabled != isEnabled {
            var updated = patch
            updated.ndiEnabled = isEnabled
            store.savePatch(updated)
            if selectedPatch?.id == updated.id {
                selectedPatch = updated
            }
        }
    }

    private func setAllFilteredMicboardEnabled(_ isEnabled: Bool) {
        guard canManageMicboard, selectedCategory == "Audio" else { return }

        for patch in filtered where patch.micboardEnabled != isEnabled {
            var updated = patch
            updated.micboardEnabled = isEnabled
            store.savePatch(updated)
            if selectedPatch?.id == updated.id {
                selectedPatch = updated
            }
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

    private func micboardAssignmentBinding(for patch: PatchRow, field: PatchsheetFocusedField) -> Binding<String> {
        Binding(
            get: {
                switch field {
                case .micboardMicrophone(let patchID):
                    return micboardMicrophoneDrafts[patchID] ?? patch.micboardMicrophone
                case .micboardInEarMonitor(let patchID):
                    return micboardInEarMonitorDrafts[patchID] ?? patch.micboardInEarMonitor
                case .notes:
                    return ""
                }
            },
            set: { newValue in
                switch field {
                case .micboardMicrophone(let patchID):
                    micboardMicrophoneDrafts[patchID] = newValue
                case .micboardInEarMonitor(let patchID):
                    micboardInEarMonitorDrafts[patchID] = newValue
                case .notes:
                    break
                }
            }
        )
    }

    private func saveDraft(for field: PatchsheetFocusedField) {
        guard store.canEditPatchsheet else { return }
        let patchID: String
        switch field {
        case .notes(let id), .micboardMicrophone(let id), .micboardInEarMonitor(let id):
            patchID = id
        }
        guard let patch = store.patchsheet.first(where: { $0.id == patchID }) else { return }

        var updated = patch
        switch field {
        case .notes:
            let draft = (noteDrafts[patchID] ?? patch.notes).trimmingCharacters(in: .whitespacesAndNewlines)
            guard draft != patch.notes.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            updated.notes = draft
            noteDrafts[patchID] = draft
        case .micboardMicrophone:
            let draft = (micboardMicrophoneDrafts[patchID] ?? patch.micboardMicrophone).trimmingCharacters(in: .whitespacesAndNewlines)
            guard draft != patch.micboardMicrophone.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            updated.micboardMicrophone = draft
            micboardMicrophoneDrafts[patchID] = draft
        case .micboardInEarMonitor:
            let draft = (micboardInEarMonitorDrafts[patchID] ?? patch.micboardInEarMonitor).trimmingCharacters(in: .whitespacesAndNewlines)
            guard draft != patch.micboardInEarMonitor.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
            updated.micboardInEarMonitor = draft
            micboardInEarMonitorDrafts[patchID] = draft
        }
        store.savePatch(updated)
        if selectedPatch?.id == updated.id {
            selectedPatch = updated
        }
    }

    private func movePatch(_ patch: PatchRow, direction: Int) {
        let current = filtered
        guard let currentIndex = current.firstIndex(where: { $0.id == patch.id }) else { return }
        let destinationIndex = currentIndex + direction
        guard current.indices.contains(destinationIndex) else { return }

        var reordered = current
        let moved = reordered.remove(at: currentIndex)
        reordered.insert(moved, at: destinationIndex)

        store.reorderPatchsheet(category: selectedCategory, orderedIDs: reordered.map(\.id))
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

enum MacNDIOutputResolution: String, CaseIterable, Codable, Identifiable {
    case hd720
    case hd1080
    case uhd4K

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hd720: return "720p"
        case .hd1080: return "1080p"
        case .uhd4K: return "4K UHD"
        }
    }

    private var landscapeSize: CGSize {
        switch self {
        case .hd720: return CGSize(width: 1280, height: 720)
        case .hd1080: return CGSize(width: 1920, height: 1080)
        case .uhd4K: return CGSize(width: 3840, height: 2160)
        }
    }

    func outputSize(for orientation: MacNDIOrientation) -> CGSize {
        let size = landscapeSize
        switch orientation {
        case .landscape:
            return size
        case .portrait:
            return CGSize(width: size.height, height: size.width)
        }
    }

    func windowSize(for orientation: MacNDIOrientation) -> CGSize {
        let outputSize = outputSize(for: orientation)
        let maxWidth: CGFloat = orientation == .landscape ? 1200 : 720
        let maxHeight: CGFloat = orientation == .landscape ? 720 : 1200
        let scale = min(maxWidth / outputSize.width, maxHeight / outputSize.height)
        return CGSize(width: outputSize.width * scale, height: outputSize.height * scale)
    }
}

enum MacNDIFrameRate: String, CaseIterable, Codable, Identifiable {
    case fps5
    case fps10
    case fps15
    case fps24
    case fps30
    case fps60

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fps5: return "5 FPS"
        case .fps10: return "10 FPS"
        case .fps15: return "15 FPS"
        case .fps24: return "24 FPS"
        case .fps30: return "30 FPS"
        case .fps60: return "60 FPS"
        }
    }

    var framesPerSecond: Double {
        switch self {
        case .fps5: return 5
        case .fps10: return 10
        case .fps15: return 15
        case .fps24: return 24
        case .fps30: return 30
        case .fps60: return 60
        }
    }

    var numerator: Int32 {
        switch self {
        case .fps5: return 5000
        case .fps10: return 10000
        case .fps15: return 15000
        case .fps24: return 24000
        case .fps30: return 30000
        case .fps60: return 60000
        }
    }

    var denominator: Int32 { 1000 }
}

enum MacNDIFeedSourceType: String, CaseIterable, Codable, Identifiable {
    case overview
    case patchsheet
    case tickets
    case runOfShow
    case runOfShowLive
    case stagePlot
    case micboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview Grid"
        case .patchsheet: return "Patchsheet"
        case .tickets: return "Tickets"
        case .runOfShow: return "Run of Show"
        case .runOfShowLive: return "Run of Show Live"
        case .stagePlot: return "Stage Plot"
        case .micboard: return "Micboard"
        }
    }
}

enum MacTicketNDIStatusFilter: String, CaseIterable, Codable, Identifiable {
    case all = "All Tickets"
    case new = "New"
    case open = "Open"
    case inProgress = "Pending"
    case resolved = "Resolved"

    var id: String { rawValue }

    var title: String { rawValue }

    func matches(_ status: TicketStatus) -> Bool {
        switch self {
        case .all:
            return true
        case .new:
            return status == .new
        case .open:
            return status == .open
        case .inProgress:
            return status == .inProgress
        case .resolved:
            return status == .resolved
        }
    }
}

struct MacNDIFeedConfiguration: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var title: String = "ProdConnect Feed"
    var sourceType: MacNDIFeedSourceType = .patchsheet
    var overviewRouteIDs: [String] = MacNDIFeedConfiguration.defaultOverviewRouteIDs
    var category: String = "Audio"
    var ticketStatusFilter: MacTicketNDIStatusFilter = .all
    var runOfShowID: String?
    var isLive = false
    var showsHeaders = true
    var scale = 1.2
    var orientation: MacNDIOrientation = .landscape

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case sourceType
        case overviewRouteIDs
        case category
        case ticketStatusFilter
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
        overviewRouteIDs: [String] = MacNDIFeedConfiguration.defaultOverviewRouteIDs,
        category: String = "Audio",
        ticketStatusFilter: MacTicketNDIStatusFilter = .all,
        runOfShowID: String? = nil,
        isLive: Bool = false,
        showsHeaders: Bool = true,
        scale: Double = 1.2,
        orientation: MacNDIOrientation = .landscape
    ) {
        self.id = id
        self.title = title
        self.sourceType = sourceType
        self.overviewRouteIDs = overviewRouteIDs
        self.category = category
        self.ticketStatusFilter = ticketStatusFilter
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
        overviewRouteIDs = try container.decodeIfPresent([String].self, forKey: .overviewRouteIDs) ?? Self.defaultOverviewRouteIDs
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? "Audio"
        ticketStatusFilter = try container.decodeIfPresent(MacTicketNDIStatusFilter.self, forKey: .ticketStatusFilter) ?? .all
        runOfShowID = try container.decodeIfPresent(String.self, forKey: .runOfShowID)
        isLive = try container.decodeIfPresent(Bool.self, forKey: .isLive) ?? false
        showsHeaders = try container.decodeIfPresent(Bool.self, forKey: .showsHeaders) ?? true
        scale = try container.decodeIfPresent(Double.self, forKey: .scale) ?? 1.2
        orientation = try container.decodeIfPresent(MacNDIOrientation.self, forKey: .orientation) ?? .landscape
    }

    static let defaultOverviewRouteIDs = [
        MacRoute.patchsheet.rawValue,
        MacRoute.runOfShow.rawValue,
        MacNDIOverviewSourceID.runOfShowLive,
        MacNDIOverviewSourceID.stagePlot,
        MacRoute.gear.rawValue,
        MacRoute.tickets.rawValue
    ]
}

// MARK: - Smaart Integration

enum SmaartLevelColor: String, Equatable {
    case green
    case yellow
    case red

    var color: Color {
        switch self {
        case .green: return .green
        case .yellow: return .yellow
        case .red: return .red
        }
    }

    static func parse(_ value: Any?) -> SmaartLevelColor? {
        guard let raw = value as? String else { return nil }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let components = normalized
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "rgb", with: "")
            .replacingOccurrences(of: "rgba", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: ";", with: ",")
            .split(separator: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        if components.count >= 3 {
            let red = components[0]
            let green = components[1]
            let blue = components[2]
            if red > 180, green < 140, blue < 140 { return .red }
            if red > 180, green > 150, blue < 140 { return .yellow }
            if green > 140, red < 160, blue < 160 { return .green }
        }
        if normalized.hasPrefix("#") || normalized.count == 6 {
            let hex = normalized.replacingOccurrences(of: "#", with: "")
            if hex.hasPrefix("ff") || hex.hasPrefix("e6") || hex.hasPrefix("cc") {
                if hex.dropFirst(2).hasPrefix("ff") || hex.dropFirst(2).hasPrefix("cc") {
                    return .yellow
                }
                return .red
            }
            if hex.dropFirst(2).hasPrefix("ff") || hex.dropFirst(2).hasPrefix("cc") {
                return .green
            }
        }
        if normalized.contains("green") || normalized.contains("normal") || normalized.contains("safe") || normalized.contains("ok") {
            return .green
        }
        if normalized.contains("yellow") || normalized.contains("amber") || normalized.contains("warning") || normalized.contains("warn") || normalized.contains("caution") {
            return .yellow
        }
        if normalized.contains("red") || normalized.contains("over") || normalized.contains("clip") || normalized.contains("high") || normalized.contains("danger") {
            return .red
        }
        return nil
    }
}

struct SmaartChannel: Identifiable, Equatable {
    let id: String
    let name: String
    let dB: Double
    let peakDB: Double
    var average10MinDB: Double? = nil
    var levelColor: SmaartLevelColor? = nil
    var displayColor: Color { levelColor?.color ?? (isClipping ? .red : .primary) }
    var statusColor: Color { levelColor?.color ?? (isClipping ? .red : Color.secondary.opacity(0.7)) }
    var isClipping: Bool { levelColor == .red || dB >= 120 || peakDB >= 120 }

    var formattedDB: String {
        dB <= -900 ? "—" : String(format: "%.1f dB SPL", dB)
    }
    var formattedPeak: String {
        peakDB <= -900 ? "—" : String(format: "%.1f dB SPL", peakDB)
    }
    var compactPeak: String {
        peakDB <= -900 ? "—" : String(format: "%.1f", peakDB)
    }
    var formattedAverage10Min: String {
        guard let average10MinDB else { return "—" }
        return String(format: "%.1f dB SPL", average10MinDB)
    }
}

enum SmaartConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)

    var label: String {
        switch self {
        case .disconnected: return "Not connected"
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        case .error(let msg): return "Error: \(msg)"
        }
    }
    var isConnected: Bool { self == .connected }
    var indicatorColor: Color {
        switch self {
        case .connected: return .green
        case .connecting: return .yellow
        case .disconnected: return .secondary
        case .error: return .red
        }
    }
}

struct SmaartSettings: Codable {
    var isEnabled: Bool = false
    var host: String = "localhost"
    var port: Int = 9090
    var apiPath: String = ""
    var password: String = ""
    var pollIntervalSeconds: Double = 0.1

    private static let defaultsKey = "prodconnect.smaart.settings.v1"

    static func load() -> SmaartSettings {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(SmaartSettings.self, from: data)
        else { return SmaartSettings() }
        return decoded
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: SmaartSettings.defaultsKey)
        }
    }

    var resolvedURL: URL? {
        let portStr = port > 0 ? ":\(port)" : ""
        let path = apiPath.hasPrefix("/") ? apiPath : (apiPath.isEmpty ? "" : "/\(apiPath)")
        return URL(string: "http://\(host.trimmingCharacters(in: .whitespacesAndNewlines))\(portStr)\(path)")
    }
}

@MainActor
final class SmaartAPIController: ObservableObject {
    static let shared = SmaartAPIController()

    @Published private(set) var channels: [SmaartChannel] = []
    @Published private(set) var connectionStatus: SmaartConnectionStatus = .disconnected
    @Published private(set) var lastRawResponse: String = ""
    @Published var settings: SmaartSettings = SmaartSettings.load()

    private var pollingTask: Task<Void, Never>?
    private var webSocketTask: URLSessionWebSocketTask?
    private var recentSamplesByChannelID: [String: [(date: Date, value: Double)]] = [:]
    private var peakByChannelID: [String: Double] = [:]
    private var lastChannelPublishAt = Date.distantPast
    private let channelPublishInterval: TimeInterval = 1.0 / 6.0
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3.0
        return URLSession(configuration: config)
    }()

    func applySettings(_ newSettings: SmaartSettings) {
        settings = newSettings
        settings.save()
        restart()
    }

    func trackingSnapshot(since startDate: Date? = nil) -> (peakDB: Double?, averageDB: Double?) {
        guard let channel = channels.first else { return (nil, nil) }
        if let startDate {
            let values = recentSamplesByChannelID[channel.id, default: []]
                .filter { $0.date >= startDate }
                .map(\.value)
            if !values.isEmpty {
                let peak = values.max()
                let average = values.reduce(0, +) / Double(values.count)
                return (peak, average)
            }
        }
        let peak = channel.peakDB > -900 ? channel.peakDB : nil
        let average = channel.average10MinDB ?? (channel.dB > -900 ? channel.dB : nil)
        return (peak, average)
    }

    func restart() {
        pollingTask?.cancel()
        pollingTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        channels = []
        recentSamplesByChannelID = [:]
        peakByChannelID = [:]
        lastChannelPublishAt = .distantPast
        lastRawResponse = ""
        connectionStatus = .disconnected
        guard settings.isEnabled, settings.resolvedURL != nil else { return }
        connectionStatus = .connecting
        if shouldUseSmaartWebSocket {
            pollingTask = Task { await streamSmaartWebSocket() }
        } else {
            pollingTask = Task {
            while !Task.isCancelled {
                await poll()
                let ms = max(50, Int(settings.pollIntervalSeconds * 1000))
                try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
            }
            }
        }
    }

    private var shouldUseSmaartWebSocket: Bool {
        let path = settings.apiPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty || path == "/"
    }

    private func poll() async {
        guard let url = settings.resolvedURL else {
            connectionStatus = .error("Invalid URL")
            return
        }
        do {
            if settings.apiPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
               settings.apiPath.trimmingCharacters(in: .whitespacesAndNewlines) == "/" {
                let wsResponses = await webSocketResponses(from: url)
                for wsResponse in wsResponses {
                    let parsed = parseSmaartResponse(wsResponse.data)
                    if !parsed.isEmpty {
                        lastRawResponse = wsResponse.preview
                        updateChannels(parsed)
                        connectionStatus = .connected
                        return
                    }
                    lastRawResponse = wsResponse.preview
                }
                if !wsResponses.isEmpty {
                    channels = []
                    connectionStatus = .error("Connected to Smaart WebSocket, but no SPL channels parsed — see raw response")
                    return
                }
            }

            let (data, finalURL) = try await fetchData(from: url)
            lastRawResponse = String(data: data, encoding: .utf8).map {
                $0.count > 800 ? String($0.prefix(800)) + "…" : $0
            } ?? "(binary data)"
            // Detect HTML — root URL returned the web viewer, not the data endpoint
            let responseText = String(data: data, encoding: .utf8) ?? ""
            if responseText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("<!doctype") ||
               responseText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("<html") {
                for wsResponse in await webSocketResponses(from: url) {
                    let parsed = parseSmaartResponse(wsResponse.data)
                    if !parsed.isEmpty {
                        lastRawResponse = wsResponse.preview
                        updateChannels(parsed)
                        connectionStatus = .connected
                        return
                    }
                    lastRawResponse = wsResponse.preview
                }
                var triedURLs: [URL] = []
                for apiResponse in await apiV3CommandResponses(from: url) {
                    let parsed = parseSmaartResponse(apiResponse.data)
                    if !parsed.isEmpty {
                        lastRawResponse = apiResponse.preview
                        updateChannels(parsed)
                        connectionStatus = .connected
                        return
                    }
                }
                for candidateURL in await candidateDataURLs(from: url, html: responseText) {
                    triedURLs.append(candidateURL)
                    guard let (jsonData, _) = try? await fetchData(from: candidateURL) else { continue }
                    let text = String(data: jsonData, encoding: .utf8) ?? ""
                    guard !isHTML(text) else { continue }
                    let parsed = parseSmaartResponse(jsonData)
                    if !parsed.isEmpty {
                        lastRawResponse = text.count > 800 ? String(text.prefix(800)) + "…" : text
                        updateChannels(parsed)
                        connectionStatus = .connected
                        return
                    }
                    lastRawResponse = text.count > 800 ? String(text.prefix(800)) + "…" : text
                }
                if !triedURLs.isEmpty {
                    lastRawResponse = await smaartDebugSummary(rootURL: url, html: responseText, triedURLs: triedURLs)
                }
                connectionStatus = .error("Smaart returned its web page, not meter data. Leave API Path blank to auto-detect, or use the SPL webviewer data path.")
                channels = []
                return
            }
            let parsed = parseSmaartResponse(data)
            updateChannels(parsed)
            connectionStatus = parsed.isEmpty ? .error("Connected but no channels parsed — see raw response") : .connected
            _ = finalURL
        } catch {
            if !Task.isCancelled {
                connectionStatus = .error(error.localizedDescription)
                channels = []
            }
        }
    }

    private func updateChannels(_ newChannels: [SmaartChannel]) {
        let now = Date()
        let cutoff = now.addingTimeInterval(-600)
        let updatedChannels = newChannels.map { channel in
            let sampleValue = channel.dB
            var samples = recentSamplesByChannelID[channel.id, default: []]
            if sampleValue > -900 {
                samples.append((date: now, value: sampleValue))
            }
            samples.removeAll { $0.date < cutoff }
            recentSamplesByChannelID[channel.id] = samples

            let rollingAverage = samples.isEmpty
                ? channel.average10MinDB
                : samples.map(\.value).reduce(0, +) / Double(samples.count)
            let peak = max(peakByChannelID[channel.id] ?? channel.peakDB, channel.peakDB, sampleValue)
            peakByChannelID[channel.id] = peak
            return SmaartChannel(
                id: channel.id,
                name: channel.name,
                dB: channel.dB,
                peakDB: peak,
                average10MinDB: channel.average10MinDB ?? rollingAverage,
                levelColor: channel.levelColor
            )
        }
        if channels.isEmpty || now.timeIntervalSince(lastChannelPublishAt) >= channelPublishInterval {
            channels = updatedChannels
            lastChannelPublishAt = now
        }
    }

    private func fetchData(from url: URL) async throws -> (Data, URL) {
        var request = URLRequest(url: url)
        if !settings.password.isEmpty {
            let cred = Data(":\(settings.password)".utf8).base64EncodedString()
            request.setValue("Basic \(cred)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return (data, url)
    }

    private struct SmaartAPIResponse {
        let data: Data
        let preview: String
    }

    private final class ContinuationGate<Value> {
        private let lock = NSLock()
        private var hasResumed = false
        private let continuation: CheckedContinuation<Value, Never>

        init(_ continuation: CheckedContinuation<Value, Never>) {
            self.continuation = continuation
        }

        func resume(returning value: Value) {
            lock.lock()
            let shouldResume = !hasResumed
            hasResumed = true
            lock.unlock()
            guard shouldResume else { return }
            continuation.resume(returning: value)
        }
    }

    private enum SmaartWebSocketReceiveResult {
        case message(URLSessionWebSocketTask.Message)
        case failure(String)
    }

    private struct SmaartStreamEndpoint {
        let name: String
        let path: String
    }

    private func streamSmaartWebSocket() async {
        guard let rootURL = settings.resolvedURL
        else {
            connectionStatus = .error("Invalid Smaart URL")
            return
        }

        while !Task.isCancelled {
            let streamEndpoints = await smaartMetricStreamEndpoints(rootURL: rootURL)
            let candidateURLs = streamEndpoints.isEmpty
                ? []
                : streamEndpoints.compactMap { webSocketURL(for: $0.path, rootURL: rootURL) }
            var foundLiveStream = false
            var attemptSummaries: [String] = []
            func appendAttemptSummary(_ summary: String) {
                let maxSummaries = 12
                if attemptSummaries.count < maxSummaries {
                    attemptSummaries.append(summary)
                } else if attemptSummaries.count == maxSummaries {
                    attemptSummaries.append("Additional live Smaart messages suppressed to keep memory bounded.")
                }
            }

            for wsURL in candidateURLs {
                guard !Task.isCancelled else { return }
                var request = URLRequest(url: wsURL)
                request.timeoutInterval = 3.0
                if !settings.password.isEmpty {
                    let cred = Data(":\(settings.password)".utf8).base64EncodedString()
                    request.setValue("Basic \(cred)", forHTTPHeaderField: "Authorization")
                }

                let task = session.webSocketTask(with: request)
                webSocketTask = task
                task.resume()
                _ = await sendWebSocketString(#"{"action":"set","properties":[{"targetFPS":12}]}"#, on: task, timeoutSeconds: 1.0)

                let shouldSendGet = wsURL.path == "/api/v3/" || wsURL.path == "/api/v4/"
                if shouldSendGet, let sendError = await sendWebSocketString(#"{"action":"get"}"#, on: task, timeoutSeconds: 3.0) {
                    appendAttemptSummary("WebSocket \(wsURL.absoluteString)\nSend failed: \(sendError)")
                    if !Task.isCancelled {
                        connectionStatus = .error("Smaart WebSocket send failed: \(sendError)")
                        lastRawResponse = attemptSummaries.last ?? ""
                    }
                    task.cancel(with: .goingAway, reason: nil)
                    continue
                }

                connectionStatus = .connecting
                    lastRawResponse = "WebSocket \(wsURL.absoluteString)\nListening for SPL updates"
                var lastMessageAt = Date()
                var lastDebugUpdateAt = Date.distantPast
                var parsedAnyReading = false
                var messageCount = 0

                while !Task.isCancelled {
                    let result = await receiveWebSocketMessage(task, timeoutSeconds: 5.0)
                    switch result {
                    case .message(let message):
                        lastMessageAt = Date()
                        messageCount += 1
                        let data: Data
                        let text: String
                        switch message {
                        case .string(let messageText):
                            text = messageText
                            data = Data(messageText.utf8)
                        case .data(let messageData):
                            data = messageData
                            text = String(data: messageData, encoding: .utf8) ?? "(binary data)"
                        @unknown default:
                            continue
                        }

                        let preview = text.count > 1200 ? String(text.prefix(1200)) + "..." : text
                        if !parsedAnyReading || Date().timeIntervalSince(lastDebugUpdateAt) >= 5 {
                            lastRawResponse = preview
                            lastDebugUpdateAt = Date()
                        }
                        let parsed = parseSmaartResponse(data)
                        if !parsed.isEmpty {
                            updateChannels(parsed)
                            connectionStatus = .connected
                            parsedAnyReading = true
                            foundLiveStream = true
                        } else if !parsedAnyReading || messageCount <= 2 {
                            appendAttemptSummary("WebSocket \(wsURL.absoluteString)\nMessage \(messageCount):\n\(preview)")
                        }

                        if !parsedAnyReading && messageCount >= 2 {
                            break
                        }
                    case .failure(let message):
                        appendAttemptSummary("WebSocket \(wsURL.absoluteString)\nReceive failed: \(message)")
                        if !parsedAnyReading && message.localizedCaseInsensitiveContains("timed out") {
                            break
                        } else if Date().timeIntervalSince(lastMessageAt) >= 4.5 {
                            _ = await sendWebSocketString(#"{"action":"get"}"#, on: task, timeoutSeconds: 1.0)
                        } else {
                            lastRawResponse = "WebSocket \(wsURL.absoluteString)\nReceive failed: \(message)"
                        }
                        if message.localizedCaseInsensitiveContains("cancel") || message.localizedCaseInsensitiveContains("closed") {
                            break
                        }
                    }
                }

                task.cancel(with: .goingAway, reason: nil)
                if webSocketTask === task {
                    webSocketTask = nil
                }
                if foundLiveStream {
                    break
                }
            }

            if !Task.isCancelled {
                if channels.isEmpty {
                    connectionStatus = .error("Connected to Smaart, but no SPL meter stream was found — see raw response")
                    if candidateURLs.isEmpty {
                        let discoveryResponse = lastRawResponse.trimmingCharacters(in: .whitespacesAndNewlines)
                        lastRawResponse = discoveryResponse.isEmpty
                            ? "No active calibrated SPL inputs were returned by Smaart. In Smaart, make sure at least one calibrated input is active/logging."
                            : "No active calibrated SPL stream endpoints were returned.\n\n\(discoveryResponse)"
                    } else {
                        lastRawResponse = await smaartStreamDebugSummary(rootURL: rootURL, candidateURLs: candidateURLs, attemptSummaries: attemptSummaries)
                    }
                } else {
                    connectionStatus = .connected
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func webSocketURL(for path: String, rootURL: URL) -> URL? {
        if path.hasPrefix("ws://") || path.hasPrefix("wss://") {
            return URL(string: path)
        }
        guard var components = URLComponents(url: rootURL, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = "ws"
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        if normalizedPath.contains("%") {
            components.percentEncodedPath = normalizedPath
        } else {
            components.path = normalizedPath
        }
        components.query = nil
        return components.url
    }

    private func smaartMetricStreamEndpoints(rootURL: URL) async -> [SmaartStreamEndpoint] {
        guard let responseData = await sendSmaartAPIRequest(
            ["action": "get", "target": "activeCalibratedInputs"],
            rootURL: rootURL,
            apiPaths: ["/api/v4/", "/api/v3/"],
            expectedResponse: { data in
                !self.extractSmaartStreamEndpoints(from: data).isEmpty
            }
        ) else { return [] }
        lastRawResponse = String(data: responseData, encoding: .utf8).map {
            $0.count > 1200 ? String($0.prefix(1200)) + "..." : $0
        } ?? "(binary data)"
        return extractSmaartStreamEndpoints(from: responseData)
    }

    private func sendSmaartAPIRequest(
        _ payload: [String: Any],
        rootURL: URL,
        apiPaths: [String],
        expectedResponse: (Data) -> Bool
    ) async -> Data? {
        guard let body = try? JSONSerialization.data(withJSONObject: payload),
              let requestText = String(data: body, encoding: .utf8)
        else { return nil }

        var debugMessages: [String] = []
        for apiPath in apiPaths {
            guard var components = URLComponents(url: rootURL, resolvingAgainstBaseURL: false) else { continue }
            components.scheme = "ws"
            components.path = apiPath
            components.query = nil
            guard let apiURL = components.url else { continue }

            var request = URLRequest(url: apiURL)
            request.timeoutInterval = 3.0
            if !settings.password.isEmpty {
                let cred = Data(":\(settings.password)".utf8).base64EncodedString()
                request.setValue("Basic \(cred)", forHTTPHeaderField: "Authorization")
            }

            let task = session.webSocketTask(with: request)
            task.resume()

            debugMessages.append("WebSocket \(apiURL.absoluteString)\nSent:\n\(requestText)")

            if let sendError = await sendWebSocketString(requestText, on: task, timeoutSeconds: 3.0) {
                debugMessages.append("WebSocket \(apiURL.absoluteString)\nSend failed: \(sendError)")
                task.cancel(with: .goingAway, reason: nil)
                continue
            }

            var didHitTerminalReceiveFailure = false
            for index in 1...8 {
                switch await receiveWebSocketMessage(task, timeoutSeconds: 4.0) {
                case .message(let message):
                    let data: Data
                    let text: String
                    switch message {
                    case .string(let messageText):
                        text = messageText
                        data = Data(messageText.utf8)
                    case .data(let messageData):
                        data = messageData
                        text = String(data: messageData, encoding: .utf8) ?? "(binary data)"
                    @unknown default:
                        continue
                    }
                    let preview = text.count > 800 ? String(text.prefix(800)) + "..." : text
                    debugMessages.append("WebSocket \(apiURL.absoluteString)\nMessage \(index):\n\(preview)")
                    if expectedResponse(data) {
                        task.cancel(with: .goingAway, reason: nil)
                        lastRawResponse = preview
                        return data
                    }
                case .failure(let message):
                    debugMessages.append("WebSocket \(apiURL.absoluteString)\nReceive failed: \(message)")
                    didHitTerminalReceiveFailure = true
                }
                if didHitTerminalReceiveFailure { break }
            }
            task.cancel(with: .goingAway, reason: nil)
        }
        lastRawResponse = debugMessages.joined(separator: "\n\n")
        return nil
    }

    private func extractSmaartStreamEndpoints(from data: Data) -> [SmaartStreamEndpoint] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = json["response"] as? [String: Any],
              let devices = response["devices"] as? [[String: Any]]
        else { return [] }

        return devices.flatMap { device -> [SmaartStreamEndpoint] in
            let deviceName = device["deviceName"] as? String ?? "Smaart"
            let channels = device["activeCalibratedChannels"] as? [[String: Any]] ?? []
            return channels.compactMap { channel in
                guard let endpoint = channel["streamEndpoint"] as? String, !endpoint.isEmpty else { return nil }
                let channelName = channel["channelName"] as? String ?? deviceName
                return SmaartStreamEndpoint(name: channelName, path: endpoint)
            }
        }
    }

    private func smaartWebSocketURLs(rootURL: URL) async -> [URL] {
        var urls: [URL] = []
        func append(_ path: String) {
            guard var components = URLComponents(url: rootURL, resolvingAgainstBaseURL: false) else { return }
            components.scheme = "ws"
            components.path = path
            components.query = nil
            if let url = components.url {
                urls.append(url)
            }
        }

        append("/api/v3/")
        append("/api/v4/")
        append("/api/v3/stream")
        append("/api/v3/stream/")
        append("/api/v3/SPL")
        append("/api/v3/spl")
        append("/api/v3/meter")
        append("/api/v3/meters")
        append("/api/v3/meterArray")
        append("/stream")
        append("/stream/")
        append("/spl")
        append("/SPL")
        append("/meters")
        append("/meterArray")
        append("/splStream")
        append("/meterStream")
        append("/live")
        append("/live/spl")

        if let rootData = try? await fetchData(from: rootURL).0,
           let html = String(data: rootData, encoding: .utf8) {
            for assetURL in assetURLs(in: html, relativeTo: rootURL).prefix(8) {
                guard let (assetData, _) = try? await fetchData(from: assetURL),
                      let assetText = String(data: assetData, encoding: .utf8)
                else { continue }
                for path in webSocketPaths(in: assetText) {
                    append(path)
                }
            }
        }

        var seen = Set<String>()
        return urls.filter { seen.insert($0.absoluteString).inserted }
    }

    private func webSocketPaths(in text: String) -> [String] {
        let pattern = #"["']([^"']*(?:api/v3|api/v4|stream|spl|meter|endpoint)[^"']*)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            let raw = nsText.substring(with: match.range(at: 1))
            guard !raw.contains("{"), !raw.contains("}"), !raw.contains("\\") else { return nil }
            if raw.hasPrefix("ws://") || raw.hasPrefix("wss://") {
                return URL(string: raw)?.path
            }
            if raw.hasPrefix("/") {
                return raw
            }
            if raw.hasPrefix("api/") {
                return "/\(raw)"
            }
            return nil
        }
    }

    private func smaartStreamDebugSummary(rootURL: URL, candidateURLs: [URL], attemptSummaries: [String]) async -> String {
        var sections: [String] = ["Smaart stream debug summary:"]
        if !attemptSummaries.isEmpty {
            sections.append(attemptSummaries.prefix(10).joined(separator: "\n\n"))
        }
        sections.append("Tried WebSocket endpoints:\n" + candidateURLs.map(\.absoluteString).joined(separator: "\n"))

        if let rootData = try? await fetchData(from: rootURL).0,
           let html = String(data: rootData, encoding: .utf8) {
            for assetURL in assetURLs(in: html, relativeTo: rootURL).prefix(8) {
                guard let (assetData, _) = try? await fetchData(from: assetURL),
                      let assetText = String(data: assetData, encoding: .utf8)
                else { continue }
                let snippet = javascriptSnippet(from: assetText, needles: ["streamEndpoint", "new WebSocket", "meterArray", "setFramerate", "createMeter", "api/v3", "addReadyHandler", "serverProbe", "Smaart", "host +"])
                if !snippet.isEmpty {
                    sections.append("JS \(assetURL.absoluteString)\n\(snippet)")
                }
            }
        }

        return sections.joined(separator: "\n\n")
    }

    private func webSocketResponses(from rootURL: URL) async -> [SmaartAPIResponse] {
        guard var components = URLComponents(url: rootURL, resolvingAgainstBaseURL: false) else { return [] }
        components.scheme = "ws"
        components.path = "/api/v3/"
        components.query = nil
        guard let wsURL = components.url else { return [] }

        var request = URLRequest(url: wsURL)
        request.timeoutInterval = 3.0
        if !settings.password.isEmpty {
            let cred = Data(":\(settings.password)".utf8).base64EncodedString()
            request.setValue("Basic \(cred)", forHTTPHeaderField: "Authorization")
        }

        let task = session.webSocketTask(with: request)
        task.resume()
        defer { task.cancel(with: .goingAway, reason: nil) }

        if let sendError = await sendWebSocketString(#"{"action":"get"}"#, on: task, timeoutSeconds: 3.0) {
            return [SmaartAPIResponse(data: Data(), preview: "WebSocket \(wsURL.absoluteString)\nSend failed: \(sendError)")]
        }

        var responses: [SmaartAPIResponse] = []
        for _ in 0..<4 {
            let result = await receiveWebSocketMessage(task, timeoutSeconds: 2.0)
            switch result {
            case .failure(let message):
                if responses.isEmpty {
                    responses.append(SmaartAPIResponse(
                        data: Data(),
                        preview: "WebSocket \(wsURL.absoluteString)\nSent {\"action\":\"get\"}\nReceive failed: \(message)"
                    ))
                }
                return responses
            case .message(let message):
                switch message {
            case .string(let text):
                let data = Data(text.utf8)
                responses.append(SmaartAPIResponse(
                    data: data,
                    preview: "WebSocket \(wsURL.absoluteString)\nSent {\"action\":\"get\"}\n\(text.prefix(1200))"
                ))
            case .data(let data):
                let text = String(data: data, encoding: .utf8) ?? "(binary data)"
                responses.append(SmaartAPIResponse(
                    data: data,
                    preview: "WebSocket \(wsURL.absoluteString)\nSent {\"action\":\"get\"}\n\(text.prefix(1200))"
                ))
            @unknown default:
                break
                }
            }
        }

        if responses.isEmpty {
            return [SmaartAPIResponse(data: Data(), preview: "WebSocket \(wsURL.absoluteString)\nConnected, but no response to {\"action\":\"get\"}")]
        }
        return responses
    }

    private func sendWebSocketString(_ text: String, on task: URLSessionWebSocketTask, timeoutSeconds: Double) async -> String? {
        await withCheckedContinuation { continuation in
            let gate = ContinuationGate<String?>(continuation)
            let timeout = DispatchWorkItem {
                gate.resume(returning: "Timed out after \(String(format: "%.1f", timeoutSeconds))s")
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeoutSeconds, execute: timeout)
            task.send(.string(text)) { error in
                timeout.cancel()
                gate.resume(returning: error?.localizedDescription)
            }
        }
    }

    private func receiveWebSocketMessage(_ task: URLSessionWebSocketTask, timeoutSeconds: Double) async -> SmaartWebSocketReceiveResult {
        await withCheckedContinuation { continuation in
            let gate = ContinuationGate<SmaartWebSocketReceiveResult>(continuation)
            let timeout = DispatchWorkItem {
                gate.resume(returning: .failure("Timed out after \(String(format: "%.1f", timeoutSeconds))s"))
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeoutSeconds, execute: timeout)
            task.receive { result in
                timeout.cancel()
                switch result {
                case .success(let message):
                    gate.resume(returning: .message(message))
                case .failure(let error):
                    gate.resume(returning: .failure(error.localizedDescription))
                }
            }
        }
    }

    private func apiV3CommandResponses(from rootURL: URL) async -> [SmaartAPIResponse] {
        guard let apiURL = URL(string: "/api/v3/", relativeTo: rootURL)?.absoluteURL else { return [] }
        let payloads: [[String: Any]] = [
            ["command": "meterArray"],
            ["command": "getMeterArray"],
            ["command": "getMeters"],
            ["command": "getSPL"],
            ["command": "SPL"],
            ["request": "meterArray"],
            ["request": "SPL"],
            ["method": "meterArray"],
            ["method": "get", "path": "meterArray"],
            ["method": "get", "path": "SPL"],
            ["jsonrpc": "2.0", "id": 1, "method": "get", "params": ["meterArray"]],
            ["jsonrpc": "2.0", "id": 1, "method": "get", "params": ["SPL"]]
        ]

        var responses: [SmaartAPIResponse] = []
        for payload in payloads {
            guard let body = try? JSONSerialization.data(withJSONObject: payload) else { continue }
            var request = URLRequest(url: apiURL)
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if !settings.password.isEmpty {
                let cred = Data(":\(settings.password)".utf8).base64EncodedString()
                request.setValue("Basic \(cred)", forHTTPHeaderField: "Authorization")
            }
            guard let (data, response) = try? await session.data(for: request),
                  let http = response as? HTTPURLResponse
            else { continue }
            let text = String(data: data, encoding: .utf8) ?? "(binary data)"
            let command = String(data: body, encoding: .utf8) ?? "{}"
            let preview = "POST \(apiURL.absoluteString)\n\(command)\nStatus \(http.statusCode)\n\(text.prefix(800))"
            if (200...299).contains(http.statusCode) {
                responses.append(SmaartAPIResponse(data: data, preview: preview))
            }
        }
        return responses
    }

    private func isHTML(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.hasPrefix("<!doctype") || trimmed.hasPrefix("<html") || trimmed.hasPrefix("<")
    }

    private func candidateDataURLs(from rootURL: URL, html: String) async -> [URL] {
        let commonPaths = [
            "/data",
            "/data.json",
            "/spl",
            "/spl.json",
            "/meters",
            "/meters.json",
            "/api",
            "/api/",
            "/api/data",
            "/api/data.json",
            "/api/spl",
            "/api/spl.json",
            "/api/meters",
            "/api/meters.json",
            "/api/channels",
            "/api/inputs",
            "/api/v1",
            "/api/v1/data",
            "/api/v1/spl",
            "/api/v1/meters",
            "/api/v1/channels",
            "/api/v3/",
            "/api/v3/meterArray",
            "/api/v3/SPL",
            "/api/v3/input",
            "/api/v3/plotInputs"
        ]
        var paths = commonPaths
        paths.append(contentsOf: endpointPaths(in: html))

        for assetURL in assetURLs(in: html, relativeTo: rootURL).prefix(8) {
            guard let (assetData, _) = try? await fetchData(from: assetURL),
                  let assetText = String(data: assetData, encoding: .utf8)
            else { continue }
            paths.append(contentsOf: endpointPaths(in: assetText))
        }

        var seen = Set<String>()
        return paths.compactMap { path in
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  !trimmed.hasPrefix("#"),
                  !trimmed.lowercased().hasPrefix("javascript:")
            else { return nil }

            let resolved = URL(string: trimmed, relativeTo: rootURL)?.absoluteURL
            guard let resolved, seen.insert(resolved.absoluteString).inserted else { return nil }
            return resolved
        }
    }

    private func smaartDebugSummary(rootURL: URL, html: String, triedURLs: [URL]) async -> String {
        var lines: [String] = ["Smaart debug summary:"]
        let importantURLs = triedURLs.filter { url in
            let path = url.path.lowercased()
            return path == "/api/v3/" ||
                   path.contains("meterarray") ||
                   path.contains("/spl") ||
                   path.contains("plotinputs")
        }.prefix(12)

        for url in importantURLs {
            var request = URLRequest(url: url)
            if !settings.password.isEmpty {
                let cred = Data(":\(settings.password)".utf8).base64EncodedString()
                request.setValue("Basic \(cred)", forHTTPHeaderField: "Authorization")
            }
            if let (data, response) = try? await session.data(for: request),
               let http = response as? HTTPURLResponse {
                let text = String(data: data, encoding: .utf8) ?? "(binary data)"
                lines.append("GET \(url.absoluteString)\nStatus \(http.statusCode)\n\(text.prefix(260))")
            } else {
                lines.append("GET \(url.absoluteString)\nNo response")
            }
        }

        for assetURL in assetURLs(in: html, relativeTo: rootURL).prefix(4) {
            guard let (data, _) = try? await fetchData(from: assetURL),
                  let text = String(data: data, encoding: .utf8)
            else { continue }
            let snippet = javascriptSnippet(from: text)
            if !snippet.isEmpty {
                lines.append("JS \(assetURL.absoluteString)\n\(snippet)")
            }
        }

        lines.append("Tried \(triedURLs.count) GET endpoints.")
        return lines.joined(separator: "\n\n")
    }

    private func javascriptSnippet(from text: String, needles: [String] = ["api/v3", "XMLHttpRequest", ".open(", "fetch(", "WebSocket", "meterArray"]) -> String {
        let nsText = text as NSString
        var snippets: [String] = []
        for needle in needles {
            guard let range = text.range(of: needle, options: .caseInsensitive) else { continue }
            let offset = text.distance(from: text.startIndex, to: range.lowerBound)
            let start = max(0, offset - 220)
            let length = min(nsText.length - start, 520)
            snippets.append(nsText.substring(with: NSRange(location: start, length: length)))
        }
        return snippets.prefix(3).joined(separator: "\n---\n")
    }

    private func endpointPaths(in text: String) -> [String] {
        let pattern = #"["']([^"']*(?:api|data|spl|meter|level|channel|input)[^"']*)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            let raw = nsText.substring(with: match.range(at: 1))
            guard !raw.contains("{"),
                  !raw.contains("}"),
                  !raw.contains("\\"),
                  !raw.contains(" "),
                  !raw.hasSuffix(".css"),
                  !raw.hasSuffix(".js"),
                  !raw.hasSuffix(".png"),
                  !raw.hasSuffix(".jpg"),
                  !raw.hasSuffix(".gif")
            else { return nil }
            return raw
        }
    }

    private func assetURLs(in html: String, relativeTo rootURL: URL) -> [URL] {
        let pattern = #"(?:src|href)=["']([^"']+\.(?:js|json))["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let nsHTML = html as NSString
        return regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            return URL(string: nsHTML.substring(with: match.range(at: 1)), relativeTo: rootURL)?.absoluteURL
        }
    }

    private func parseSmaartResponse(_ data: Data) -> [SmaartChannel] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }

        // Helper: extract dB value from a dict using many possible key names
        func number(_ value: Any?) -> Double? {
            if value is Bool { return nil }
            if let v = value as? Double { return v }
            if let v = value as? Int { return Double(v) }
            if let v = value as? Float { return Double(v) }
            if let v = value as? NSNumber { return v.doubleValue }
            if let v = value as? String { return Double(v.trimmingCharacters(in: .whitespacesAndNewlines)) }
            return nil
        }

        func hasDBSignal(_ d: [String: Any]) -> Bool {
            let keys = Set(d.keys.map { $0.lowercased() })
            return !keys.isDisjoint(with: ["rms", "db", "value", "level", "leveldb", "level_db", "spl", "fast", "slow", "leq", "laeq", "lcpeak", "peak", "peakdb", "peak_db"])
        }

        func extractDB(_ d: [String: Any]) -> Double {
            for key in ["rms", "db", "dB", "value", "level", "levelDb", "level_db", "spl", "SPL", "fast", "slow", "leq", "Leq", "laeq", "LAeq", "lcpeak", "LCpeak"] {
                if let v = number(d[key]) { return v }
            }
            return -999.0
        }
        func extractPeak(_ d: [String: Any], fallback: Double) -> Double {
            for key in ["Peak A", "peakA", "peak_a", "peak", "peakDb", "peak_db", "Peak", "lcpeak", "LCpeak"] {
                if let v = number(d[key]) { return v }
            }
            return fallback
        }
        func normalizedMetricName(_ value: String) -> String {
            value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "  ", with: " ")
        }
        func collectMetricValues(_ metrics: [[String: Any]]) -> [String: Double] {
            var metricValues: [String: Double] = [:]
            let nameKeys = ["name", "label", "title", "metric", "meter", "type", "id"]
            let valueKeys = ["value", "db", "dB", "level", "levelDb", "level_db", "spl", "SPL"]

            for metric in metrics {
                for (key, value) in metric {
                    if let numeric = number(value) {
                        metricValues[key] = numeric
                        metricValues[normalizedMetricName(key)] = numeric
                    }
                }

                let metricName = nameKeys.compactMap { metric[$0] as? String }.first
                let metricValue = valueKeys.compactMap { number(metric[$0]) }.first
                if let metricName, let metricValue {
                    metricValues[metricName] = metricValue
                    metricValues[normalizedMetricName(metricName)] = metricValue
                }
            }

            return metricValues
        }
        func metricValue(_ values: [String: Double], _ names: [String]) -> Double? {
            for name in names {
                if let value = values[name] { return value }
                if let value = values[normalizedMetricName(name)] { return value }
            }
            return nil
        }
        func extractLevelColor(_ d: [String: Any]) -> SmaartLevelColor? {
            for key in ["targetColor", "target_color", "color", "rangeColor", "range_color", "statusColor", "status_color", "state", "status", "range"] {
                if let color = SmaartLevelColor.parse(d[key]) { return color }
            }
            for value in d.values {
                if let nested = value as? [String: Any],
                   let color = extractLevelColor(nested) {
                    return color
                }
                if let nestedArray = value as? [[String: Any]] {
                    for nested in nestedArray {
                        if let color = extractLevelColor(nested) {
                            return color
                        }
                    }
                }
            }
            return nil
        }
        func makeChannel(_ index: Int, _ name: String, _ d: [String: Any]) -> SmaartChannel {
            let db = extractDB(d)
            let peak = extractPeak(d, fallback: db)
            let average10 = number(d["LAeq 10"]) ?? number(d["Leq 10"]) ?? number(d["LCeq 10"])
            return SmaartChannel(id: "\(name)\(index)", name: name, dB: db, peakDB: peak, average10MinDB: average10, levelColor: extractLevelColor(d))
        }

        func channelName(_ d: [String: Any], index: Int) -> String {
            (d["name"] as? String) ??
            (d["channel"] as? String) ??
            (d["label"] as? String) ??
            (d["input"] as? String) ??
            "Ch \(index + 1)"
        }

        func channels(from dictionary: [String: Any]) -> [SmaartChannel] {
            dictionary.sorted(by: { $0.key < $1.key }).enumerated().compactMap { i, kv in
                if let inner = kv.value as? [String: Any] {
                    guard hasDBSignal(inner) else { return nil }
                    return makeChannel(i, kv.key, inner)
                }
                if let value = kv.value as? Double {
                    guard kv.key.localizedCaseInsensitiveContains("spl") ||
                          kv.key.localizedCaseInsensitiveContains("db") ||
                          kv.key.localizedCaseInsensitiveContains("level") ||
                          kv.key.localizedCaseInsensitiveContains("leq") ||
                          kv.key.localizedCaseInsensitiveContains("peak")
                    else { return nil }
                    return SmaartChannel(id: "\(kv.key)\(i)", name: kv.key, dB: value, peakDB: value, levelColor: extractLevelColor(dictionary))
                }
                if let value = kv.value as? Int {
                    guard kv.key.localizedCaseInsensitiveContains("spl") ||
                          kv.key.localizedCaseInsensitiveContains("db") ||
                          kv.key.localizedCaseInsensitiveContains("level") ||
                          kv.key.localizedCaseInsensitiveContains("leq") ||
                          kv.key.localizedCaseInsensitiveContains("peak")
                    else { return nil }
                    return SmaartChannel(id: "\(kv.key)\(i)", name: kv.key, dB: Double(value), peakDB: Double(value), levelColor: extractLevelColor(dictionary))
                }
                return nil
            }
        }

        // Format 1: array of dicts  [{name, rms, peak}, ...]
        if let arr = json as? [[String: Any]] {
            return arr.enumerated().map { i, d in
                makeChannel(i, channelName(d, index: i), d)
            }
        }

        if let arr = json as? [Any] {
            let parsed = arr.enumerated().compactMap { i, value -> SmaartChannel? in
                if let d = value as? [String: Any] {
                    return makeChannel(i, channelName(d, index: i), d)
                }
                if let db = number(value) {
                    return SmaartChannel(id: "spl\(i)", name: i == 0 ? "SPL" : "Ch \(i + 1)", dB: db, peakDB: db)
                }
                return nil
            }
            if !parsed.isEmpty { return parsed }
        }

        if let root = json as? [String: Any] {
            if let metrics = root["metrics"] as? [[String: Any]] {
                let metricValues = collectMetricValues(metrics)
                let current = metricValue(metricValues, [
                    "SPL A Slow",
                    "SPL Slow",
                    "SPL A Fast",
                    "SPL Fast",
                    "SPL",
                    "LAeq 1",
                    "Leq 1"
                ])
                if let current {
                    let peak = metricValue(metricValues, ["Peak A", "LCpeak", "Peak"]) ?? -999.0
                    let average10 = metricValue(metricValues, ["LAeq 10", "Leq 10", "LCeq 10"])
                    let name = (root["channelName"] as? String) ??
                        (root["deviceName"] as? String) ??
                        "SPL"
                    return [SmaartChannel(
                        id: "smaart-\(name)",
                        name: name,
                        dB: current,
                        peakDB: peak,
                        average10MinDB: average10,
                        levelColor: extractLevelColor(root)
                    )]
                }
            }

            // Format 2: {meters: [...]} or {channels: [...]} or {data: [...]} or {result: [...]}
            for key in ["meters", "channels", "data", "result", "inputs", "outputs", "levels", "measurements", "payload", "value", "values", "message", "response", "meterArray"] {
                if let arr = root[key] as? [[String: Any]] {
                    return arr.enumerated().map { i, d in
                        makeChannel(i, channelName(d, index: i), d)
                    }
                }
                if let dict = root[key] as? [String: Any] {
                    if let nestedData = try? JSONSerialization.data(withJSONObject: dict) {
                        let nestedParsed = parseSmaartResponse(nestedData)
                        if !nestedParsed.isEmpty { return nestedParsed }
                    }
                    let parsed = channels(from: dict)
                    if !parsed.isEmpty { return parsed }
                }
                if let arr = root[key] as? [Any],
                   let nestedData = try? JSONSerialization.data(withJSONObject: arr) {
                    let nestedParsed = parseSmaartResponse(nestedData)
                    if !nestedParsed.isEmpty { return nestedParsed }
                }
            }

            let nestedCandidates = root.compactMap { _, value -> [String: Any]? in
                value as? [String: Any]
            }
            for candidate in nestedCandidates {
                if let nestedData = try? JSONSerialization.data(withJSONObject: candidate) {
                    let nestedParsed = parseSmaartResponse(nestedData)
                    if !nestedParsed.isEmpty { return nestedParsed }
                }
            }

            // Format 3: {spl: {fast, peak}} — single-channel
            if let splDict = root["spl"] as? [String: Any] {
                let db = extractDB(splDict)
                if db > -999 {
                    let peak = extractPeak(splDict, fallback: db)
                    return [SmaartChannel(id: "spl0", name: "SPL", dB: db, peakDB: peak, levelColor: extractLevelColor(splDict))]
                }
            }

            // Format 4: {spl: {channelName: {fast, peak, ...}, ...}}  (Smaart v8/v9 SPL Webserver)
            if let splDict = root["spl"] as? [String: Any] {
                let parsed = channels(from: splDict)
                if !parsed.isEmpty { return parsed }
            }

            // Format 5: flat single-channel root dict {rms, peak, name?}
            let db = extractDB(root)
            if db > -999, hasDBSignal(root) {
                let name = (root["name"] as? String) ?? (root["channel"] as? String) ?? "SPL"
                let peak = extractPeak(root, fallback: db)
                return [SmaartChannel(id: "root0", name: name, dB: db, peakDB: peak, levelColor: extractLevelColor(root))]
            }
        }

        return []
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
    @Published var outputResolution: MacNDIOutputResolution = .hd1080 {
        didSet {
            persistOutputResolution()
            syncOutputs()
        }
    }
    @Published var outputFrameRate: MacNDIFrameRate = .fps10 {
        didSet {
            persistOutputFrameRate()
            syncOutputs()
        }
    }

    @Published private(set) var previewVisibleFeedIDs: Set<String> = []

    private let store: ProdConnectStore
    private let userDefaults = UserDefaults.standard
    private let feedsDefaultsKey = "prodconnect.mac.ndiFeeds.v1"
    private let outputResolutionDefaultsKey = "prodconnect.mac.ndiOutputResolution.v1"
    private let outputFrameRateDefaultsKey = "prodconnect.mac.ndiOutputFrameRate.v1"
    private var controllers: [String: MacPatchsheetNDIOutputWindowController] = [:]
    private var cancellables: Set<AnyCancellable> = []

    init(store: ProdConnectStore) {
        self.store = store
        self.feeds = Self.loadPersistedFeeds()
        self.outputResolution = Self.loadPersistedOutputResolution()
        self.outputFrameRate = Self.loadPersistedOutputFrameRate()

        store.$patchsheet
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncOutputs()
            }
            .store(in: &cancellables)

        store.$tickets
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

        store.$gear
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncOutputs()
            }
            .store(in: &cancellables)

        store.$lessons
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncOutputs()
            }
            .store(in: &cancellables)

        store.$checklists
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncOutputs()
            }
            .store(in: &cancellables)

        store.$ideas
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncOutputs()
            }
            .store(in: &cancellables)

        store.$channels
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncOutputs()
            }
            .store(in: &cancellables)

        store.$teamMembers
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

    func closeAllPreviews() {
        for controller in controllers.values {
            controller.hideWindow()
        }
        previewVisibleFeedIDs = []
    }

    func updateFeedValue<Value>(_ value: Value, at index: Int, keyPath: WritableKeyPath<MacNDIFeedConfiguration, Value>) {
        guard feeds.indices.contains(index) else { return }
        feeds[index][keyPath: keyPath] = value
    }

    func updateRunOfShowID(_ runOfShowID: String?, at index: Int) {
        guard feeds.indices.contains(index) else { return }
        let normalizedID = runOfShowID?.isEmpty == true ? nil : runOfShowID
        feeds[index].runOfShowID = normalizedID
    }

    func overviewFeeds() -> [(index: Int, feed: MacNDIFeedConfiguration)] {
        Array(feeds.enumerated())
            .filter { $0.element.sourceType == .overview }
            .map { (index: $0.offset, feed: $0.element) }
    }

    func addOverviewFeedIfNeeded() {
        guard canManageNDI else { return }
        if feeds.contains(where: { $0.sourceType == .overview }) { return }
        feeds.append(
            MacNDIFeedConfiguration(
                title: "ProdConnect Overview",
                sourceType: .overview,
                overviewRouteIDs: MacNDIFeedConfiguration.defaultOverviewRouteIDs,
                scale: 1.0
            )
        )
    }

    fileprivate func availableOverviewSources() -> [MacOverviewSourceOption] {
        guard hasNDIFeature else { return [] }
        var options = MacRoute.allCases.compactMap { route -> MacOverviewSourceOption? in
            let isVisible: Bool
            switch route {
            case .chat:
                isVisible = store.canSeeChat
            case .runOfShow:
                isVisible = store.canSeeRunOfShow
            case .training:
                isVisible = store.canSeeTrainingTab
            case .tickets:
                isVisible = store.canUseTickets
            case .overview, .customize, .account:
                isVisible = false
            case .users:
                isVisible = store.user?.isAdmin == true || store.user?.isOwner == true
            default:
                isVisible = true
            }
            guard isVisible else { return nil }
            let overriddenTitle: String = route == .runOfShow ? "Shows" : route.title
            return MacOverviewSourceOption(id: route.rawValue, title: overriddenTitle, systemImage: route.icon)
        }

        if store.canSeeRunOfShow {
            options.append(
                MacOverviewSourceOption(
                    id: MacNDIOverviewSourceID.runOfShowLive,
                    title: "Run of Show Live",
                    systemImage: "timer"
                )
            )
            options.append(
                MacOverviewSourceOption(
                    id: MacNDIOverviewSourceID.setlist,
                    title: "Setlist",
                    systemImage: "list.number"
                )
            )
            options.append(
                MacOverviewSourceOption(
                    id: MacNDIOverviewSourceID.stagePlot,
                    title: "Stage Plot",
                    systemImage: "music.note.house"
                )
            )
        }

        if hasNDIFeature, SmaartAPIController.shared.settings.isEnabled {
            options.append(
                MacOverviewSourceOption(
                    id: MacNDIOverviewSourceID.smaart,
                    title: "Smaart dB",
                    systemImage: "waveform.path.ecg"
                )
            )
        }

        options.append(
            MacOverviewSourceOption(
                id: MacNDIOverviewSourceID.timecode,
                title: "Timecode",
                systemImage: "timer"
            )
        )

        return options
    }

    fileprivate func overviewSources(for feed: MacNDIFeedConfiguration) -> [MacOverviewSourceOption] {
        let available = availableOverviewSources()
        let availableSet = Set(available.map(\.id))
        let selectedIDs = feed.overviewRouteIDs.filter { availableSet.contains($0) }
        let selected = selectedIDs.compactMap { id in available.first(where: { $0.id == id }) }
        return selected.isEmpty ? Array(available.prefix(4)) : selected
    }

    fileprivate func setOverviewSource(_ source: MacOverviewSourceOption, isIncluded: Bool, at index: Int) {
        guard feeds.indices.contains(index) else { return }
        DispatchQueue.main.async {
            guard self.feeds.indices.contains(index) else { return }
            var ids = self.feeds[index].overviewRouteIDs
            if isIncluded {
                if !ids.contains(source.id) {
                    ids.append(source.id)
                }
            } else {
                ids.removeAll { $0 == source.id }
            }
            self.feeds[index].overviewRouteIDs = ids
        }
    }

    func patches(for category: String) -> [PatchRow] {
        store.patchsheet
            .filter { $0.category == category && $0.ndiEnabled }
            .sorted(by: PatchRow.autoSort)
    }

    func micboardItems(for show: RunOfShowDocument?) -> [RunOfShowMicboardItem] {
        makeMicboardItems(fromAudioPatchRows: store.patchsheet, storedItems: show?.micboardItems ?? [])
    }

    func runOfShows() -> [RunOfShowDocument] {
        RunOfShowDocument.sortedShows(store.runOfShows)
    }

    func runOfShow(for feed: MacNDIFeedConfiguration) -> RunOfShowDocument? {
        let shows = runOfShows()
        if let runOfShowID = feed.runOfShowID,
           let matched = shows.first(where: { $0.id == runOfShowID }) {
            return matched
        }
        return shows.first
    }

    func tickets(for feed: MacNDIFeedConfiguration) -> [SupportTicket] {
        store.visibleTickets
            .filter { feed.ticketStatusFilter.matches($0.status) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func descriptorText(for feed: MacNDIFeedConfiguration) -> String {
        switch feed.sourceType {
        case .overview:
            return "\(overviewSources(for: feed).count) sources in the overview grid"
        case .patchsheet:
            return "\(patches(for: feed.category).count) selected patches in \(feed.category)"
        case .tickets:
            return "\(tickets(for: feed).count) \(feed.ticketStatusFilter.title.lowercased())"
        case .runOfShow:
            let show = runOfShow(for: feed)
            let title = show?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return "\(show?.sortedItems.count ?? 0) items in \(title.isEmpty ? "selected show" : title)"
        case .runOfShowLive:
            let show = runOfShow(for: feed)
            let title = show?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return "Live view for \(title.isEmpty ? "selected show" : title)"
        case .stagePlot:
            let show = runOfShow(for: feed)
            let title = show?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return "\(show?.sortedStagePlotItems.count ?? 0) stage plot items in \(title.isEmpty ? "selected show" : title)"
        case .micboard:
            let show = runOfShow(for: feed)
            let title = show?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let manualCount = show?.sortedMicboardItems.filter { !$0.id.hasPrefix("patchsheet-") }.count ?? 0
            return "\(micboardItems(for: show).count + manualCount) micboard assignments in \(title.isEmpty ? "selected show" : title)"
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
            let shouldOwnController = feed.isLive || previewVisibleFeedIDs.contains(feed.id)
            guard shouldOwnController else {
                if let controller = controllers.removeValue(forKey: feed.id) {
                    controller.close()
                }
                continue
            }

            let feedController = controller(for: feed.id)
            let selectedRunOfShow = runOfShow(for: feed)
            if feed.sourceType == .overview {
                feedController.liveOverviewTilesProvider = { [weak self] in
                    self?.overviewTiles(for: feed, rowLimit: nil, now: Date()) ?? []
                }
            }
            feedController.update(
                configuration: MacPatchsheetNDIOutputConfiguration(
                    isActive: feed.isLive,
                    title: feed.title,
                    sourceType: feed.sourceType,
                    overviewTiles: feed.sourceType == .overview ? overviewTiles(for: feed, rowLimit: nil, now: Date()) : [],
                    category: feed.category,
                    runOfShow: selectedRunOfShow,
                    micboardItems: micboardItems(for: selectedRunOfShow),
                    tickets: tickets(for: feed),
                    patches: patches(for: feed.category),
                    nameColumnTitle: Self.nameColumnTitle(for: feed.category),
                    inputColumnTitle: Self.inputColumnTitle(for: feed.category),
                    outputColumnTitle: Self.outputColumnTitle(for: feed.category),
                    showsUniverseColumn: feed.category == "Lighting",
                    showsHeaders: feed.showsHeaders,
                    scale: feed.scale,
                    orientation: feed.orientation,
                    resolution: outputResolution,
                    frameRate: outputFrameRate
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

    func disableAllOutputsOnShutdown() {
        let hadLiveFeeds = feeds.contains { $0.isLive }
        if hadLiveFeeds {
            feeds = feeds.map { feed in
                var updated = feed
                updated.isLive = false
                return updated
            }
        } else {
            persistFeeds()
        }

        for controller in controllers.values {
            controller.close()
        }
        previewVisibleFeedIDs = []
    }

    private func controller(for feedID: String) -> MacPatchsheetNDIOutputWindowController {
        if let existing = controllers[feedID] {
            return existing
        }
        let controller = MacPatchsheetNDIOutputWindowController()
        controllers[feedID] = controller
        return controller
    }

    fileprivate func overviewTiles(for feed: MacNDIFeedConfiguration) -> [MacOverviewTileData] {
        overviewTiles(for: feed, rowLimit: nil, now: Date())
    }

    fileprivate func overviewTiles(for feed: MacNDIFeedConfiguration, now: Date) -> [MacOverviewTileData] {
        overviewTiles(for: feed, rowLimit: nil, now: now)
    }

    private func overviewTiles(for feed: MacNDIFeedConfiguration, rowLimit: Int?, now: Date) -> [MacOverviewTileData] {
        overviewSources(for: feed).map { overviewTile(for: $0, rowLimit: rowLimit, now: now) }
    }

    private func liveOverviewRunOfShow() -> RunOfShowDocument? {
        let shows = runOfShows()
        return shows.first(where: { $0.isLiveActive }) ?? shows.first
    }

    private func limitedRows(_ rows: [String], rowLimit: Int?) -> [String] {
        guard let rowLimit else { return rows }
        return Array(rows.prefix(rowLimit))
    }

    private func overviewTile(for source: MacOverviewSourceOption, rowLimit: Int?, now: Date) -> MacOverviewTileData {
        if source.id == MacNDIOverviewSourceID.runOfShowLive {
            let show = liveOverviewRunOfShow()
            let items = show?.sortedItems ?? []
            let currentID = show?.isLiveActive == true ? show?.liveCurrentItemID : items.first?.id
            let currentItem = currentID.flatMap { id in items.first(where: { $0.id == id }) }
            let elapsed = show?.isLiveActive == true ? max(Int(now.timeIntervalSince(show?.liveItemStartedAt ?? now)), 0) : 0
            let currentDuration = currentItem?.durationSeconds ?? 0
            let remaining = show?.isLiveActive == true ? max(currentDuration - elapsed, 0) : currentDuration
            let overrun = show?.isLiveActive == true ? max(elapsed - currentDuration, 0) : 0
            let isOverrun = overrun > 0
            let projectedEnd = show?.projectedEndTime(at: now) ?? now
            return MacOverviewTileData(
                id: source.id,
                title: source.title,
                subtitle: show?.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? show?.title ?? "Selected show" : "Selected show",
                systemImage: source.systemImage,
                accent: isOverrun ? .red : .green,
                rows: limitedRows([
                    currentItem?.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? "Now: \(currentItem?.title ?? "")" : "No active item",
                    isOverrun ? "Item overrun: \(runOfShowOverrunClock(seconds: overrun))" : "Item remaining: \(runOfShowFormattedClock(seconds: remaining))",
                    "Show ends: \(projectedEnd.formatted(date: .omitted, time: .shortened))",
                    "\(items.count) show items",
                    show?.isLiveActive == true ? "Live timer running" : "Live timer stopped"
                ], rowLimit: rowLimit),
                runOfShowLiveShow: show,
                runOfShowLiveNow: now
            )
        }

        if source.id == MacNDIOverviewSourceID.setlist {
            let show = liveOverviewRunOfShow()
            let items = show?.sortedItems ?? []
            let limit = rowLimit ?? items.count
            return MacOverviewTileData(
                id: source.id,
                title: source.title,
                subtitle: show?.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? show!.title : "No show selected",
                systemImage: source.systemImage,
                accent: .green,
                rows: [],
                columnHeaders: ["Title", "Length", "Person"],
                columnRows: Array(items.prefix(limit).map { item in
                    let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    let person = item.person.trimmingCharacters(in: .whitespacesAndNewlines)
                    return [
                        title.isEmpty ? "Untitled" : title,
                        item.formattedDuration,
                        person.isEmpty ? "—" : person
                    ]
                })
            )
        }

        if source.id == MacNDIOverviewSourceID.stagePlot {
            let show = liveOverviewRunOfShow()
            return MacOverviewTileData(
                id: source.id,
                title: source.title,
                subtitle: show?.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? show!.title : "Stage Plot",
                systemImage: source.systemImage,
                accent: .teal,
                rows: [],
                stagePlotShow: show ?? RunOfShowDocument(title: "", teamCode: "", items: [])
            )
        }

        if source.id == MacNDIOverviewSourceID.smaart {
            let smaartChannels = SmaartAPIController.shared.channels
            let status = SmaartAPIController.shared.connectionStatus
            let selectedChannelID = UserDefaults.standard.string(forKey: MacOverviewTileData.smaartSelectedChannelDefaultsKey)
            let selectedChannel = selectedChannelID.flatMap { id in
                smaartChannels.first(where: { $0.id == id })
            } ?? smaartChannels.first
            let subtitle: String = status.isConnected
                ? "\(smaartChannels.count) channel\(smaartChannels.count == 1 ? "" : "s")"
                : status.label
            return MacOverviewTileData(
                id: source.id,
                title: source.title,
                subtitle: subtitle,
                systemImage: source.systemImage,
                accent: status.isConnected ? .green : .orange,
                rows: smaartChannels.isEmpty ? [status.label] : [],
                columnHeaders: smaartChannels.count > 1 ? ["Channel", "RMS", "Peak"] : [],
                columnRows: selectedChannel == nil
                    ? []
                    : Array(smaartChannels.filter { $0.id != selectedChannel?.id }.prefix(rowLimit ?? smaartChannels.count).map { ch in
                        [ch.name, ch.formattedDB, ch.formattedPeak]
                }),
                smaartChannel: selectedChannel,
                smaartChannels: smaartChannels,
                smaartConnectionStatus: status
            )
        }

        if source.id == MacNDIOverviewSourceID.timecode {
            let controller = MacExternalTimecodeController.shared
            return MacOverviewTileData(
                id: source.id,
                title: source.title,
                subtitle: controller.statusText,
                systemImage: source.systemImage,
                accent: controller.isReceiving ? .green : .orange,
                rows: [],
                timecodeDisplay: controller.timecodeDisplay,
                timecodeFrameRate: controller.frameRateLabel,
                timecodeStatus: controller.statusText,
                timecodeIsReceiving: controller.isReceiving
            )
        }

        guard let route = MacRoute(rawValue: source.id) else {
            return MacOverviewTileData(id: source.id, title: source.title, subtitle: "Overview source", systemImage: source.systemImage, accent: .gray, rows: [])
        }

        switch route {
        case .chat:
            let channels = store.channels.sorted { ($0.lastMessageAt ?? .distantPast) > ($1.lastMessageAt ?? .distantPast) }
            return MacOverviewTileData(
                id: source.id,
                title: source.title,
                subtitle: "\(channels.count) channels",
                systemImage: source.systemImage,
                accent: .blue,
                rows: limitedRows(channels.map { $0.name.isEmpty ? "Untitled channel" : $0.name }, rowLimit: rowLimit)
            )
        case .patchsheet:
            let patches = store.patchsheet.sorted(by: PatchRow.autoSort)
            let patchLimit = rowLimit.map { $0 } ?? patches.count
            return MacOverviewTileData(
                id: source.id,
                title: route.title,
                subtitle: "\(patches.count) patch rows",
                systemImage: route.icon,
                accent: .cyan,
                rows: [],
                columnHeaders: ["Name", "Input", "Output"],
                columnRows: Array(patches.prefix(patchLimit).map { patch in
                    [
                        patch.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : patch.name,
                        patch.input.trimmingCharacters(in: .whitespacesAndNewlines),
                        patch.output.trimmingCharacters(in: .whitespacesAndNewlines)
                    ]
                })
            )
        case .runOfShow:
            let shows = RunOfShowDocument.sortedShows(store.runOfShows)
            return MacOverviewTileData(
                id: source.id,
                title: source.title,
                subtitle: "\(shows.count) shows",
                systemImage: route.icon,
                accent: .green,
                rows: limitedRows(shows.map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled show" : $0.title }, rowLimit: rowLimit)
            )
        case .training:
            let lessons = store.lessons.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            return MacOverviewTileData(
                id: source.id,
                title: route.title,
                subtitle: "\(lessons.count) lessons",
                systemImage: route.icon,
                accent: .purple,
                rows: limitedRows(lessons.map { $0.title.isEmpty ? "Untitled lesson" : $0.title }, rowLimit: rowLimit)
            )
        case .gear:
            let gear = store.gear.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            let gearLimit = rowLimit.map { $0 } ?? gear.count
            return MacOverviewTileData(
                id: source.id,
                title: route.title,
                subtitle: "\(gear.count) assets",
                systemImage: route.icon,
                accent: .orange,
                rows: [],
                columnHeaders: ["Name", "Location"],
                columnRows: Array(gear.prefix(gearLimit).map { item in
                    let location = [item.campus.isEmpty ? item.location : item.campus, item.room].filter { !$0.isEmpty }.joined(separator: " / ")
                    return [item.name.isEmpty ? "Untitled" : item.name, location]
                })
            )
        case .tickets:
            let tickets = store.visibleTickets.sorted { $0.updatedAt > $1.updatedAt }
            let ticketLimit = rowLimit.map { $0 } ?? tickets.count
            return MacOverviewTileData(
                id: source.id,
                title: route.title,
                subtitle: "\(tickets.count) visible tickets",
                systemImage: route.icon,
                accent: .red,
                rows: [],
                columnHeaders: ["Title", "Status"],
                columnRows: Array(tickets.prefix(ticketLimit).map { ticket in
                    [ticket.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : ticket.title, ticket.status.rawValue]
                })
            )
        case .checklists:
            let checklists = store.checklists.sorted { $0.position < $1.position }
            return MacOverviewTileData(
                id: source.id,
                title: route.title,
                subtitle: "\(checklists.count) checklists",
                systemImage: route.icon,
                accent: .mint,
                rows: limitedRows(checklists.map { $0.title.isEmpty ? "Untitled checklist" : $0.title }, rowLimit: rowLimit)
            )
        case .ideas:
            let ideas = store.ideas.sorted { $0.updatedAt > $1.updatedAt }
            return MacOverviewTileData(
                id: source.id,
                title: route.title,
                subtitle: "\(ideas.count) ideas",
                systemImage: route.icon,
                accent: .yellow,
                rows: limitedRows(ideas.map { $0.title.isEmpty ? "Untitled idea" : $0.title }, rowLimit: rowLimit)
            )
        case .users:
            let members = store.teamMembers.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            return MacOverviewTileData(
                id: source.id,
                title: route.title,
                subtitle: "\(members.count) team members",
                systemImage: route.icon,
                accent: .indigo,
                rows: limitedRows(members.map { $0.displayName.isEmpty ? $0.email : $0.displayName }, rowLimit: rowLimit)
            )
        case .overview, .customize, .account:
            return MacOverviewTileData(id: source.id, title: route.title, subtitle: "Settings", systemImage: route.icon, accent: .gray, rows: [])
        }
    }

    private func overviewPatchRowText(_ patch: PatchRow) -> String {
        let name = patch.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled patch" : patch.name
        let input = patch.input.trimmingCharacters(in: .whitespacesAndNewlines)
        let output = patch.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = patch.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let universe = patch.universe?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var details: [String] = []

        if !input.isEmpty {
            details.append("In \(input)")
        }
        if !output.isEmpty {
            details.append("Out \(output)")
        }
        if patch.category == "Lighting", !universe.isEmpty {
            details.append("U \(universe)")
        }
        if let channelCount = patch.channelCount, channelCount > 0 {
            details.append("\(channelCount)ch")
        }
        if !notes.isEmpty {
            details.append(notes)
        }

        return details.isEmpty ? name : "\(name) - \(details.joined(separator: " | "))"
    }

    private func persistFeeds() {
        guard let data = try? JSONEncoder().encode(feeds) else { return }
        userDefaults.set(data, forKey: feedsDefaultsKey)
    }

    private func persistOutputResolution() {
        userDefaults.set(outputResolution.rawValue, forKey: outputResolutionDefaultsKey)
    }

    private func persistOutputFrameRate() {
        userDefaults.set(outputFrameRate.rawValue, forKey: outputFrameRateDefaultsKey)
    }

    private static func loadPersistedOutputResolution() -> MacNDIOutputResolution {
        let rawValue = UserDefaults.standard.string(forKey: "prodconnect.mac.ndiOutputResolution.v1") ?? ""
        return MacNDIOutputResolution(rawValue: rawValue) ?? .hd1080
    }

    private static func loadPersistedOutputFrameRate() -> MacNDIFrameRate {
        let rawValue = UserDefaults.standard.string(forKey: "prodconnect.mac.ndiOutputFrameRate.v1") ?? ""
        return MacNDIFrameRate(rawValue: rawValue) ?? .fps10
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

enum MacAutomaticMessageTriggerType: String, CaseIterable, Identifiable, Codable {
    case midiNote = "MIDI Note"
    case timeOfDay = "Time of Day"

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

struct MacAutomaticMessageRule: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var isEnabled: Bool = true
    var name: String = ""
    var channelID: String = ""
    var messageText: String = ""
    var triggerType: MacAutomaticMessageTriggerType = .midiNote
    var midiChannel: Int = 1
    var noteNumber: Int = 60
    var minimumVelocity: Int = 1
    var timeOfDayMinutes: Int = 9 * 60

    enum CodingKeys: String, CodingKey {
        case id
        case isEnabled
        case name
        case channelID
        case messageText
        case triggerType
        case midiChannel
        case noteNumber
        case minimumVelocity
        case timeOfDayMinutes
    }

    init(
        id: String = UUID().uuidString,
        isEnabled: Bool = true,
        name: String = "",
        channelID: String = "",
        messageText: String = "",
        triggerType: MacAutomaticMessageTriggerType = .midiNote,
        midiChannel: Int = 1,
        noteNumber: Int = 60,
        minimumVelocity: Int = 1,
        timeOfDayMinutes: Int = 9 * 60
    ) {
        self.id = id
        self.isEnabled = isEnabled
        self.name = name
        self.channelID = channelID
        self.messageText = messageText
        self.triggerType = triggerType
        self.midiChannel = midiChannel
        self.noteNumber = noteNumber
        self.minimumVelocity = minimumVelocity
        self.timeOfDayMinutes = timeOfDayMinutes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        channelID = try container.decodeIfPresent(String.self, forKey: .channelID) ?? ""
        messageText = try container.decodeIfPresent(String.self, forKey: .messageText) ?? ""
        triggerType = try container.decodeIfPresent(MacAutomaticMessageTriggerType.self, forKey: .triggerType) ?? .midiNote
        midiChannel = try container.decodeIfPresent(Int.self, forKey: .midiChannel) ?? 1
        noteNumber = try container.decodeIfPresent(Int.self, forKey: .noteNumber) ?? 60
        minimumVelocity = try container.decodeIfPresent(Int.self, forKey: .minimumVelocity) ?? 1
        timeOfDayMinutes = try container.decodeIfPresent(Int.self, forKey: .timeOfDayMinutes) ?? (9 * 60)
    }
}

struct MacMIDISourceDescriptor: Identifiable, Equatable {
    let id: String
    let uniqueID: MIDIUniqueID
    let name: String
}

struct MacLTCAudioSourceDescriptor: Identifiable, Equatable {
    let id: String
    let name: String
}

enum MacExternalTimecodeInputMode: String, CaseIterable, Identifiable {
    case mtc
    case ltc

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mtc: "MTC MIDI"
        case .ltc: "LTC Audio"
        }
    }
}

@MainActor
final class MacExternalTimecodeController: ObservableObject {
    static let shared = MacExternalTimecodeController()

    @Published var inputMode: MacExternalTimecodeInputMode {
        didSet {
            userDefaults.set(inputMode.rawValue, forKey: inputModeDefaultsKey)
            applyInputMode()
        }
    }

    @Published var selectedMIDISourceID: String? {
        didSet {
            userDefaults.set(selectedMIDISourceID, forKey: selectedMIDISourceDefaultsKey)
#if canImport(CoreMIDI)
            if inputMode == .mtc {
                refreshMIDISourceConnection()
            }
#endif
        }
    }

    @Published var selectedLTCAudioSourceID: String? {
        didSet {
            userDefaults.set(selectedLTCAudioSourceID, forKey: selectedLTCAudioSourceDefaultsKey)
            if inputMode == .ltc {
                refreshLTCAudioConnection()
            }
        }
    }

    @Published private(set) var timecodeDisplay = "--:--:--:--"
    @Published private(set) var frameRateLabel = "SMPTE"
    @Published private(set) var lastReceivedAt: Date?
    @Published private(set) var lastLTCAudioLevel: Double = 0

    private let userDefaults = UserDefaults.standard
    private let inputModeDefaultsKey = "prodconnect.mac.externalTimecode.inputMode"
    private let selectedMIDISourceDefaultsKey = "prodconnect.mac.externalTimecode.selectedMIDISourceID"
    private let selectedLTCAudioSourceDefaultsKey = "prodconnect.mac.externalTimecode.selectedLTCAudioSourceID"
    private var quarterFrameValues = [Int](repeating: 0, count: 8)
    private var ltcCaptureSession: AVCaptureSession?
    private var ltcCaptureProcessor: MacLTCAudioCaptureProcessor?

#if canImport(CoreMIDI)
    private var midiClient = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var connectedSourceID: MIDIUniqueID?
#endif

    private init() {
        let savedMode = userDefaults.string(forKey: inputModeDefaultsKey).flatMap(MacExternalTimecodeInputMode.init(rawValue:))
        inputMode = savedMode ?? .mtc
        selectedMIDISourceID = userDefaults.string(forKey: selectedMIDISourceDefaultsKey)
        selectedLTCAudioSourceID = userDefaults.string(forKey: selectedLTCAudioSourceDefaultsKey)
#if canImport(CoreMIDI)
        configureMIDI()
#endif
        applyInputMode()
    }

    deinit {
        ltcCaptureSession?.stopRunning()
#if canImport(CoreMIDI)
        if inputPort != 0 { MIDIPortDispose(inputPort) }
        if midiClient != 0 { MIDIClientDispose(midiClient) }
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
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
#else
        return []
#endif
    }

    var ltcAudioSources: [MacLTCAudioSourceDescriptor] {
        AVCaptureDevice.devices(for: .audio)
            .map { MacLTCAudioSourceDescriptor(id: $0.uniqueID, name: $0.localizedName) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var midiSourceCount: Int {
        midiSources.count
    }

    var statusText: String {
        guard let lastReceivedAt else {
            return inputMode == .ltc ? "Waiting for SMPTE LTC audio" : "Waiting for SMPTE MTC"
        }
        let age = Date().timeIntervalSince(lastReceivedAt)
        return age <= 2.0 ? "Receiving \(frameRateLabel)" : "No timecode received recently"
    }

    var isReceiving: Bool {
        guard let lastReceivedAt else { return false }
        return Date().timeIntervalSince(lastReceivedAt) <= 2.0
    }

    func updateSelectedMIDISourceID(_ id: String) {
        selectedMIDISourceID = id.isEmpty ? nil : id
    }

    func updateSelectedLTCAudioSourceID(_ id: String) {
        selectedLTCAudioSourceID = id.isEmpty ? nil : id
    }

    private func applyInputMode() {
#if canImport(CoreMIDI)
        if inputMode == .mtc {
            refreshMIDISourceConnection()
        } else {
            disconnectMIDISource()
        }
#endif
        if inputMode == .ltc {
            refreshLTCAudioConnection()
        } else {
            stopLTCAudioConnection()
        }
        frameRateLabel = inputMode == .ltc ? "SMPTE LTC" : "SMPTE MTC"
    }

    private func refreshLTCAudioConnection() {
        stopLTCAudioConnection()
        if selectedLTCAudioSourceID == nil {
            selectedLTCAudioSourceID = ltcAudioSources.first?.id
        }

        guard let selectedLTCAudioSourceID,
              let device = AVCaptureDevice.devices(for: .audio).first(where: { $0.uniqueID == selectedLTCAudioSourceID }) else {
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startLTCAudioConnection(device: device)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                guard granted else { return }
                Task { @MainActor in
                    self?.refreshLTCAudioConnection()
                }
            }
        default:
            break
        }
    }

    private func startLTCAudioConnection(device: AVCaptureDevice) {
        do {
            let session = AVCaptureSession()
            session.beginConfiguration()
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { return }
            session.addInput(input)

            let output = AVCaptureAudioDataOutput()
            let processor = MacLTCAudioCaptureProcessor { [weak self] decoded, level in
                Task { @MainActor in
                    self?.handleLTCUpdate(decoded: decoded, level: level)
                }
            }
            output.setSampleBufferDelegate(processor, queue: DispatchQueue(label: "prodconnect.ltc.audio"))
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            session.commitConfiguration()
            session.startRunning()

            ltcCaptureProcessor = processor
            ltcCaptureSession = session
        } catch {
            stopLTCAudioConnection()
        }
    }

    private func stopLTCAudioConnection() {
        ltcCaptureSession?.stopRunning()
        ltcCaptureSession = nil
        ltcCaptureProcessor = nil
        lastLTCAudioLevel = 0
    }

    private func handleLTCUpdate(decoded: MacLTCDecodedTimecode?, level: Double) {
        lastLTCAudioLevel = level
        guard let decoded else { return }
        timecodeDisplay = decoded.display
        frameRateLabel = decoded.rateLabel
        lastReceivedAt = Date()
    }

#if canImport(CoreMIDI)
    private func configureMIDI() {
        MIDIClientCreateWithBlock("ProdConnect External Timecode MIDI" as CFString, &midiClient) { _ in }
        MIDIInputPortCreateWithBlock(midiClient, "ProdConnect Timecode Input" as CFString, &inputPort) { [weak self] packetList, _ in
            guard let self else { return }
            self.handle(packetList: packetList)
        }
        if selectedMIDISourceID == nil {
            selectedMIDISourceID = midiSources.first?.id
        }
        if inputMode == .mtc {
            refreshMIDISourceConnection()
        }
    }

    private func refreshMIDISourceConnection() {
        disconnectMIDISource()

        guard let selectedMIDISourceID,
              let parsedUniqueID = Int32(selectedMIDISourceID),
              let selectedUniqueID = MIDIUniqueID(exactly: parsedUniqueID),
              let source = midiSourceRef(for: selectedUniqueID) else { return }

        MIDIPortConnectSource(inputPort, source, nil)
        connectedSourceID = selectedUniqueID
    }

    private func disconnectMIDISource() {
        if let connectedSourceID,
           let source = midiSourceRef(for: connectedSourceID) {
            MIDIPortDisconnectSource(inputPort, source)
            self.connectedSourceID = nil
        }
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
        var index = 0
        while index < bytes.count {
            let status = bytes[index]
            if status == 0xF1, index + 1 < bytes.count {
                handleQuarterFrame(dataByte: bytes[index + 1])
                index += 2
            } else {
                index += 1
            }
        }
    }

    private func handleQuarterFrame(dataByte: UInt8) {
        let piece = Int((dataByte >> 4) & 0x07)
        let value = Int(dataByte & 0x0F)
        quarterFrameValues[piece] = value

        let frame = (quarterFrameValues[1] << 4) | quarterFrameValues[0]
        let seconds = (quarterFrameValues[3] << 4) | quarterFrameValues[2]
        let minutes = (quarterFrameValues[5] << 4) | quarterFrameValues[4]
        let hours = ((quarterFrameValues[7] & 0x01) << 4) | quarterFrameValues[6]
        let rateCode = (quarterFrameValues[7] >> 1) & 0x03

        guard hours < 24, minutes < 60, seconds < 60 else { return }
        let maxFrame: Int
        switch rateCode {
        case 0:
            frameRateLabel = "SMPTE MTC 24 fps"
            maxFrame = 24
        case 1:
            frameRateLabel = "SMPTE MTC 25 fps"
            maxFrame = 25
        case 2:
            frameRateLabel = "SMPTE MTC 29.97 df"
            maxFrame = 30
        default:
            frameRateLabel = "SMPTE MTC 30 fps"
            maxFrame = 30
        }
        guard frame < maxFrame else { return }

        timecodeDisplay = String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frame)
        lastReceivedAt = Date()
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
}

private struct MacLTCDecodedTimecode {
    let display: String
    let rateLabel: String
}

private final class MacLTCAudioCaptureProcessor: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private var decoder = MacLTCDecoder()
    private let onUpdate: @Sendable (MacLTCDecodedTimecode?, Double) -> Void

    init(onUpdate: @escaping @Sendable (MacLTCDecodedTimecode?, Double) -> Void) {
        self.onUpdate = onUpdate
        super.init()
    }

    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee else {
            return
        }
        let samples = Self.samples(from: sampleBuffer, streamDescription: streamDescription)
        guard !samples.isEmpty else { return }

        let squaredSum = samples.reduce(0.0) { $0 + ($1 * $1) }
        let rms = sqrt(squaredSum / Double(samples.count))
        let level = min(1.0, max(0.0, rms * 4.0))
        let decoded = decoder.process(samples: samples, sampleRate: streamDescription.mSampleRate)
        onUpdate(decoded, level)
    }

    private nonisolated static func samples(from sampleBuffer: CMSampleBuffer, streamDescription: AudioStreamBasicDescription) -> [Double] {
        var neededSize = 0
        var blockBuffer: CMBlockBuffer?
        var status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &neededSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr, neededSize > 0 else { return [] }

        let rawBufferList = UnsafeMutableRawPointer.allocate(
            byteCount: neededSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawBufferList.deallocate() }
        let audioBufferList = rawBufferList.bindMemory(to: AudioBufferList.self, capacity: 1)

        status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferList,
            bufferListSize: neededSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return [] }

        let isFloat = (streamDescription.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let bitsPerChannel = Int(streamDescription.mBitsPerChannel)
        let channelsPerFrame = max(1, Int(streamDescription.mChannelsPerFrame))
        var result: [Double] = []

        for buffer in UnsafeMutableAudioBufferListPointer(audioBufferList) {
            guard let data = buffer.mData else { continue }
            if isFloat, bitsPerChannel == 32 {
                let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.stride
                let pointer = data.assumingMemoryBound(to: Float.self)
                result.reserveCapacity(result.count + sampleCount / channelsPerFrame)
                for index in stride(from: 0, to: sampleCount, by: channelsPerFrame) {
                    result.append(Double(pointer[index]))
                }
            } else if !isFloat, bitsPerChannel == 16 {
                let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Int16>.stride
                let pointer = data.assumingMemoryBound(to: Int16.self)
                result.reserveCapacity(result.count + sampleCount / channelsPerFrame)
                for index in stride(from: 0, to: sampleCount, by: channelsPerFrame) {
                    result.append(Double(pointer[index]) / Double(Int16.max))
                }
            }
        }

        return result
    }
}

private final class MacLTCDecoder: @unchecked Sendable {
    private var sampleIndex = 0
    private var previousPolarity: Bool?
    private var lastTransitionSample: Int?
    private var halfCellSamples: Double?
    private var waitingForSecondHalf = false
    private var bits: [Int] = []

    func process(samples: [Double], sampleRate: Double) -> MacLTCDecodedTimecode? {
        var latestDecoded: MacLTCDecodedTimecode?
        let noiseFloor = 0.02

        for sample in samples {
            defer { sampleIndex += 1 }
            guard abs(sample) >= noiseFloor else { continue }
            let polarity = sample >= 0
            guard let previousPolarity else {
                self.previousPolarity = polarity
                continue
            }
            guard polarity != previousPolarity else { continue }
            self.previousPolarity = polarity

            guard let lastTransitionSample else {
                self.lastTransitionSample = sampleIndex
                continue
            }

            let interval = sampleIndex - lastTransitionSample
            self.lastTransitionSample = sampleIndex
            guard interval >= 3 else { continue }

            let estimatedHalfCell = halfCellSamples ?? max(4.0, sampleRate / (30.0 * 160.0))
            let isHalfCell = Double(interval) < estimatedHalfCell * 1.55
            let observedHalfCell = isHalfCell ? Double(interval) : Double(interval) / 2.0
            halfCellSamples = (estimatedHalfCell * 0.92) + (observedHalfCell * 0.08)

            if isHalfCell {
                if waitingForSecondHalf {
                    latestDecoded = append(bit: 1, sampleRate: sampleRate)
                    waitingForSecondHalf = false
                } else {
                    waitingForSecondHalf = true
                }
            } else {
                waitingForSecondHalf = false
                latestDecoded = append(bit: 0, sampleRate: sampleRate)
            }
        }

        return latestDecoded
    }

    private func append(bit: Int, sampleRate: Double) -> MacLTCDecodedTimecode? {
        bits.append(bit)
        if bits.count > 160 {
            bits.removeFirst(bits.count - 160)
        }

        guard bits.count >= 80 else { return nil }
        let frame = Array(bits.suffix(80))
        guard syncMatches(frame) else { return nil }
        return decode(frame: frame, sampleRate: sampleRate)
    }

    private func syncMatches(_ frame: [Int]) -> Bool {
        let syncBits = Array(frame.suffix(16))
        let value = syncBits.enumerated().reduce(0) { partial, element in
            partial | ((element.element & 1) << element.offset)
        }
        return value == 0x3FFD || value == 0xBFFC
    }

    private func decode(frame bits: [Int], sampleRate: Double) -> MacLTCDecodedTimecode? {
        let frames = bcd(units: 0...3, tens: 8...9, in: bits)
        let seconds = bcd(units: 16...19, tens: 24...26, in: bits)
        let minutes = bcd(units: 32...35, tens: 40...42, in: bits)
        let hours = bcd(units: 48...51, tens: 56...57, in: bits)
        guard hours < 24, minutes < 60, seconds < 60, frames < 60 else { return nil }

        let display = String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames)
        return MacLTCDecodedTimecode(display: display, rateLabel: inferredRateLabel(sampleRate: sampleRate))
    }

    private func bcd(units: ClosedRange<Int>, tens: ClosedRange<Int>, in bits: [Int]) -> Int {
        let unitValue = units.enumerated().reduce(0) { partial, element in
            partial | ((bits[element.element] & 1) << element.offset)
        }
        let tenValue = tens.enumerated().reduce(0) { partial, element in
            partial | ((bits[element.element] & 1) << element.offset)
        }
        return (tenValue * 10) + unitValue
    }

    private func inferredRateLabel(sampleRate: Double) -> String {
        guard let halfCellSamples, halfCellSamples > 0 else { return "SMPTE LTC" }
        let bitRate = sampleRate / (halfCellSamples * 2.0)
        let frameRate = bitRate / 80.0
        let knownRates: [(Double, String)] = [
            (24.0, "SMPTE LTC 24 fps"),
            (25.0, "SMPTE LTC 25 fps"),
            (29.97, "SMPTE LTC 29.97 fps"),
            (30.0, "SMPTE LTC 30 fps")
        ]
        if let match = knownRates.min(by: { abs($0.0 - frameRate) < abs($1.0 - frameRate) }),
           abs(match.0 - frameRate) < 1.5 {
            return match.1
        }
        return "SMPTE LTC"
    }
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
        RunOfShowDocument.sortedShows(store.runOfShows)
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
        updated.startLiveSession(at: Date())
        store.saveRunOfShow(updated)
    }

    private func move(_ show: RunOfShowDocument, direction: Int) {
        let spl = SmaartAPIController.shared.trackingSnapshot(since: show.currentLiveTrackingStartedAt())
        var updated = show
        updated.moveLiveSession(direction: direction, at: Date(), splPeakDB: spl.peakDB, splAverageDB: spl.averageDB)
        store.saveRunOfShow(updated)
    }

    private func reset(_ show: RunOfShowDocument) {
        autoStartSuppressedShowIDs.insert(show.id)
        var updated = show
        updated.resetLiveSession()
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

@MainActor
final class MacAutomaticMessagingController: ObservableObject {
    @Published var isEnabled: Bool {
        didSet { userDefaults.set(isEnabled, forKey: enabledDefaultsKey) }
    }
    @Published var selectedMIDISourceID: String? {
        didSet {
            userDefaults.set(selectedMIDISourceID, forKey: selectedMIDISourceDefaultsKey)
#if canImport(CoreMIDI)
            refreshMIDISourceConnection()
#endif
        }
    }
    @Published var rules: [MacAutomaticMessageRule] {
        didSet { persistRules() }
    }
    @Published var listeningRuleID: String?
    @Published private(set) var lastStatusText = "No automatic messages sent yet."

    private let store: ProdConnectStore
    private let userDefaults = UserDefaults.standard
    private let enabledDefaultsKey = "prodconnect.mac.automaticMessaging.enabled"
    private let selectedMIDISourceDefaultsKey = "prodconnect.mac.automaticMessaging.selectedMIDISourceID"
    private let rulesDefaultsKey = "prodconnect.mac.automaticMessaging.rules.v1"
    private var lastTriggeredAtByRuleID: [String: Date] = [:]
    private var sentTimeRuleDayByRuleID: [String: String] = [:]
    private var timeRuleTimer: Timer?
    private let triggerCooldown: TimeInterval = 1.0

#if canImport(CoreMIDI)
    private var midiClient = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var connectedSourceID: MIDIUniqueID?
#endif

    init(store: ProdConnectStore) {
        self.store = store
        self.isEnabled = userDefaults.bool(forKey: enabledDefaultsKey)
        self.selectedMIDISourceID = userDefaults.string(forKey: selectedMIDISourceDefaultsKey)
        self.rules = Self.loadPersistedRules(userDefaults: userDefaults)
        startTimeRuleTimer()
#if canImport(CoreMIDI)
        configureMIDI()
#endif
    }

    deinit {
        timeRuleTimer?.invalidate()
#if canImport(CoreMIDI)
        if inputPort != 0 { MIDIPortDispose(inputPort) }
        if midiClient != 0 { MIDIClientDispose(midiClient) }
#endif
    }

    var canManageMessaging: Bool {
        guard let user = store.user else { return false }
        return user.hasPaidSubscription && (user.isAdmin || user.isOwner)
    }

    var groupChannels: [ChatChannel] {
        store.channels
            .filter { $0.kind == .group }
            .sorted { $0.position < $1.position }
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
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
#else
        return []
#endif
    }

    var midiSourceCount: Int {
        midiSources.count
    }

    func updateSelectedMIDISourceID(_ id: String) {
        selectedMIDISourceID = id.isEmpty ? nil : id
    }

    func addRule() {
        guard canManageMessaging else { return }
        rules.append(
            MacAutomaticMessageRule(
                name: "New Message Trigger",
                channelID: groupChannels.first?.id ?? "",
                messageText: "",
                midiChannel: 1,
                noteNumber: 60,
                minimumVelocity: 1
            )
        )
    }

    func removeRule(id: String) {
        guard canManageMessaging else { return }
        rules.removeAll { $0.id == id }
        if listeningRuleID == id {
            listeningRuleID = nil
        }
        lastTriggeredAtByRuleID[id] = nil
    }

    func updateRuleValue<Value>(_ value: Value, ruleID: String, keyPath: WritableKeyPath<MacAutomaticMessageRule, Value>) {
        guard canManageMessaging,
              let index = rules.firstIndex(where: { $0.id == ruleID }) else { return }
        var updated = rules[index]
        updated[keyPath: keyPath] = value
        updated.midiChannel = min(max(updated.midiChannel, 1), 16)
        updated.noteNumber = min(max(updated.noteNumber, 0), 127)
        updated.minimumVelocity = min(max(updated.minimumVelocity, 1), 127)
        updated.timeOfDayMinutes = min(max(updated.timeOfDayMinutes, 0), 1439)
        rules[index] = updated
    }

    func toggleListening(ruleID: String) {
        guard canManageMessaging else { return }
        listeningRuleID = listeningRuleID == ruleID ? nil : ruleID
    }

    func isListening(ruleID: String) -> Bool {
        listeningRuleID == ruleID
    }

    func channelName(for channelID: String) -> String {
        groupChannels.first(where: { $0.id == channelID })?.name ?? "Select Channel"
    }

    private func persistRules() {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        userDefaults.set(data, forKey: rulesDefaultsKey)
    }

    private static func loadPersistedRules(userDefaults: UserDefaults) -> [MacAutomaticMessageRule] {
        guard let data = userDefaults.data(forKey: "prodconnect.mac.automaticMessaging.rules.v1"),
              let decoded = try? JSONDecoder().decode([MacAutomaticMessageRule].self, from: data) else {
            return []
        }
        return decoded
    }

    private func learn(ruleID: String, midiChannel: Int, noteNumber: Int, velocity: Int) {
        guard let index = rules.firstIndex(where: { $0.id == ruleID }) else { return }
        rules[index].midiChannel = min(max(midiChannel, 1), 16)
        rules[index].noteNumber = min(max(noteNumber, 0), 127)
        rules[index].minimumVelocity = min(max(velocity, 1), 127)
        listeningRuleID = nil
        lastStatusText = "Learned note \(noteNumber) on channel \(midiChannel)."
    }

    private func triggerRules(midiChannel: Int, noteNumber: Int, velocity: Int) {
        guard isEnabled, canManageMessaging else { return }
        if let listeningRuleID {
            learn(ruleID: listeningRuleID, midiChannel: midiChannel, noteNumber: noteNumber, velocity: velocity)
            return
        }

        let now = Date()
        for rule in rules where rule.isEnabled
            && rule.triggerType == .midiNote
            && rule.midiChannel == midiChannel
            && rule.noteNumber == noteNumber
            && velocity >= rule.minimumVelocity {
            if let lastTriggeredAt = lastTriggeredAtByRuleID[rule.id],
               now.timeIntervalSince(lastTriggeredAt) < triggerCooldown {
                continue
            }
            sendMessage(for: rule, triggeredAt: now)
        }
    }

    private func startTimeRuleTimer() {
        timeRuleTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.performTimeRulesIfNeeded(now: Date())
            }
        }
        if let timeRuleTimer {
            RunLoop.main.add(timeRuleTimer, forMode: .common)
        }
    }

    private func performTimeRulesIfNeeded(now: Date) {
        guard isEnabled, canManageMessaging else { return }
        let calendar = Calendar.current
        let currentMinutes = (calendar.component(.hour, from: now) * 60) + calendar.component(.minute, from: now)
        let dayKey = Self.dayKey(for: now, calendar: calendar)

        for rule in rules where rule.isEnabled && rule.triggerType == .timeOfDay && rule.timeOfDayMinutes == currentMinutes {
            guard sentTimeRuleDayByRuleID[rule.id] != dayKey else { continue }
            sendMessage(for: rule, triggeredAt: now)
            sentTimeRuleDayByRuleID[rule.id] = dayKey
        }
    }

    private static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

    private func sendMessage(for rule: MacAutomaticMessageRule, triggeredAt: Date) {
        let trimmedText = rule.messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            lastStatusText = "Matched \(rule.name.isEmpty ? "a rule" : rule.name), but no message text is set."
            return
        }
        guard let channelIndex = store.channels.firstIndex(where: { $0.id == rule.channelID && $0.kind == .group }) else {
            lastStatusText = "Matched \(rule.name.isEmpty ? "a rule" : rule.name), but the channel was not found."
            return
        }

        var updated = store.channels[channelIndex]
        updated.messages.append(
            ChatMessage(
                author: store.user?.email ?? "automation@prodconnect",
                text: trimmedText,
                timestamp: triggeredAt
            )
        )
        updated.lastMessageAt = updated.messages.last?.timestamp
        store.saveChannel(updated)
        lastTriggeredAtByRuleID[rule.id] = triggeredAt
        lastStatusText = "Sent to \(updated.name) at \(triggeredAt.formatted(date: .omitted, time: .standard))."
    }

#if canImport(CoreMIDI)
    private func configureMIDI() {
        MIDIClientCreateWithBlock("ProdConnect Automatic Messaging MIDI" as CFString, &midiClient) { _ in }
        MIDIInputPortCreateWithBlock(midiClient, "ProdConnect Messaging Input" as CFString, &inputPort) { [weak self] packetList, _ in
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
        var index = 0
        while index + 2 < bytes.count {
            let status = bytes[index]
            let type = status & 0xF0
            let channel = Int((status & 0x0F) + 1)
            let note = Int(bytes[index + 1])
            let velocity = Int(bytes[index + 2])
            if type == 0x90, velocity > 0 {
                Task { @MainActor in
                    self.triggerRules(midiChannel: channel, noteNumber: note, velocity: velocity)
                }
            }
            index += 3
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
}

private struct MacOverviewMultiview: View {
    @EnvironmentObject private var store: ProdConnectStore
    @EnvironmentObject private var ndiSettings: MacNDISettingsController
    @State private var localOverviewRouteIDs = MacNDIFeedConfiguration.defaultOverviewRouteIDs

    private var canManageNDI: Bool {
        guard let user = store.user else { return false }
        return user.normalizedSubscriptionTier != "free" && (user.isAdmin || user.isOwner)
    }

    private var overviewFeedItem: (index: Int, feed: MacNDIFeedConfiguration)? {
        ndiSettings.overviewFeeds().first
    }

    private var displayFeed: MacNDIFeedConfiguration {
        if let feed = overviewFeedItem?.feed {
            return feed
        }
        return MacNDIFeedConfiguration(
            title: "ProdConnect Overview",
            sourceType: .overview,
            overviewRouteIDs: localOverviewRouteIDs,
            scale: 1.0
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Overview")
                        .font(.system(size: 28, weight: .bold))
                    Text("A summary of your selected ProdConnect windows.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let item = overviewFeedItem {
                    Toggle("Send over NDI", isOn: feedBinding(item.index, \.isLive))
                        .disabled(!canManageNDI)
                } else {
                    Button("Configure in Settings") { }
                        .buttonStyle(.bordered)
                        .disabled(true)
                }
            }

            ScrollView {
                TimelineView(.periodic(from: .now, by: 0.1)) { context in
                    overviewTilesGrid(tiles: ndiSettings.overviewTiles(for: displayFeed, now: context.date))
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func overviewTilesGrid(tiles: [MacOverviewTileData]) -> some View {
        VStack(spacing: 20) {
            if tiles.isEmpty {
                ContentUnavailableView(
                    "No Overview Sources",
                    systemImage: "square.grid.2x2",
                    description: Text("Select sources in Settings → Overview.")
                )
                .frame(height: 260)
            } else {
                ViewThatFits(in: .horizontal) {
                    twoColumnOverviewTiles(tiles)
                    oneColumnOverviewTiles(tiles)
                }
            }
        }
    }

    private func twoColumnOverviewTiles(_ tiles: [MacOverviewTileData]) -> some View {
        let leftTiles = tiles.enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
        let rightTiles = tiles.enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
        return HStack(alignment: .top, spacing: 20) {
            VStack(spacing: 20) {
                ForEach(leftTiles) { tile in
                    MacOverviewTileCard(tile: tile, onDrop: { draggedID in moveTile(fromID: draggedID, toID: tile.id) })
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            VStack(spacing: 20) {
                ForEach(rightTiles) { tile in
                    MacOverviewTileCard(tile: tile, onDrop: { draggedID in moveTile(fromID: draggedID, toID: tile.id) })
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func oneColumnOverviewTiles(_ tiles: [MacOverviewTileData]) -> some View {
        VStack(spacing: 20) {
            ForEach(tiles) { tile in
                MacOverviewTileCard(tile: tile, onDrop: { draggedID in moveTile(fromID: draggedID, toID: tile.id) })
            }
        }
    }

    private func moveTile(fromID: String, toID: String) {
        guard fromID != toID else { return }
        if let item = overviewFeedItem {
            var ids = item.feed.overviewRouteIDs
            guard let fromIndex = ids.firstIndex(of: fromID),
                  let toIndex = ids.firstIndex(of: toID) else { return }
            ids.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
            ndiSettings.updateFeedValue(ids, at: item.index, keyPath: \.overviewRouteIDs)
        } else {
            var ids = localOverviewRouteIDs
            guard let fromIndex = ids.firstIndex(of: fromID),
                  let toIndex = ids.firstIndex(of: toID) else { return }
            ids.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
            localOverviewRouteIDs = ids
        }
    }

    private func feedBinding<Value>(_ index: Int, _ keyPath: WritableKeyPath<MacNDIFeedConfiguration, Value>) -> Binding<Value> {
        Binding(
            get: { ndiSettings.feeds[index][keyPath: keyPath] },
            set: { ndiSettings.updateFeedValue($0, at: index, keyPath: keyPath) }
        )
    }
}

private struct MacOverviewTileCard: View {
    let tile: MacOverviewTileData
    var onDrop: ((String) -> Void)? = nil

    private static let minHeight: Double = 160
    private static let maxHeight: Double = 1800
    private static let defaultHeight: Double = 280

    @State private var storedHeight: Double
    @GestureState private var dragDelta: Double = 0
    @State private var isDropTargeted = false
    @State private var selectedSmaartChannelID: String?

    init(tile: MacOverviewTileData, onDrop: ((String) -> Void)? = nil) {
        self.tile = tile
        self.onDrop = onDrop
        let saved = UserDefaults.standard.double(forKey: "prodconnect.overviewTileHeight.\(tile.id)")
        self._storedHeight = State(initialValue: saved > 0 ? saved : Self.defaultHeight)
        self._selectedSmaartChannelID = State(initialValue: UserDefaults.standard.string(forKey: MacOverviewTileData.smaartSelectedChannelDefaultsKey))
    }

    private var displayHeight: Double {
        max(Self.minHeight, min(Self.maxHeight, storedHeight + dragDelta))
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .updating($dragDelta) { value, state, _ in
                state = value.translation.height
            }
            .onEnded { value in
                storedHeight = max(Self.minHeight, min(Self.maxHeight, storedHeight + value.translation.height))
                UserDefaults.standard.set(storedHeight, forKey: "prodconnect.overviewTileHeight.\(tile.id)")
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: tile.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tile.accent)
                    .frame(width: 32, height: 32)
                    .background(tile.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(tile.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(tile.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .padding(.leading, 4)
                    .draggable(tile.id)
                    .onHover { isHovering in
                        if isHovering { NSCursor.openHand.push() } else { NSCursor.pop() }
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.03))

            Divider().opacity(0.5)

            Group {
                if let show = tile.runOfShowLiveShow {
                    MacRunOfShowLiveOverviewTile(show: show, now: tile.runOfShowLiveNow)
                        .padding(10)
                } else if let show = tile.stagePlotShow {
                    MacStagePlotCanvas(show: show)
                        .padding(10)
                } else if tile.timecodeDisplay != nil {
                    timecodeDisplay
                } else if let channel = selectedSmaartChannel {
                    smaartMeter(channel)
                } else if !tile.columnRows.isEmpty {
                    columnTable
                } else if tile.rows.isEmpty {
                    Text("No items to show")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(tile.rows.enumerated()), id: \.offset) { _, row in
                                Text(row.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : row)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.primary)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .overlay(alignment: .bottom) {
                                        Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
                                    }
                            }
                        }
                    }
                    .scrollIndicators(.never)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.bottom, 18)
            .clipped()
        }
        .frame(maxWidth: .infinity, minHeight: displayHeight, maxHeight: displayHeight, alignment: .topLeading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isDropTargeted ? tile.accent.opacity(0.8) : tile.accent.opacity(0.24), lineWidth: isDropTargeted ? 2 : 1)
        )
        .overlay(alignment: .bottom) {
            resizeHandle
        }
        .dropDestination(for: String.self) { items, _ in
            guard let draggedID = items.first, draggedID != tile.id else { return false }
            onDrop?(draggedID)
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
    }

    private var selectedSmaartChannel: SmaartChannel? {
        guard !tile.smaartChannels.isEmpty else { return tile.smaartChannel }
        if let selectedSmaartChannelID,
           let channel = tile.smaartChannels.first(where: { $0.id == selectedSmaartChannelID }) {
            return channel
        }
        return tile.smaartChannel ?? tile.smaartChannels.first
    }

    private func selectSmaartChannel(_ channel: SmaartChannel) {
        selectedSmaartChannelID = channel.id
        UserDefaults.standard.set(channel.id, forKey: MacOverviewTileData.smaartSelectedChannelDefaultsKey)
    }

    private var timecodeDisplay: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(tile.timecodeDisplay ?? "--:--:--:--")
                .font(.system(size: 52, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(tile.timecodeIsReceiving ? Color.green : Color.orange)
                .lineLimit(1)
                .minimumScaleFactor(0.35)
            HStack(spacing: 10) {
                Text(tile.timecodeFrameRate.isEmpty ? "SMPTE" : tile.timecodeFrameRate)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Circle()
                    .fill(tile.timecodeIsReceiving ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(tile.timecodeStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func smaartMeter(_ channel: SmaartChannel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Menu {
                    ForEach(tile.smaartChannels) { option in
                        Button {
                            selectSmaartChannel(option)
                        } label: {
                            HStack {
                                Text(option.name)
                                if option.id == channel.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(channel.name)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.primary)
                        if tile.smaartChannels.count > 1 {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(tile.smaartChannels.count <= 1)
                Spacer()
            }

            Text(String(format: "%.1f", channel.dB))
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(channel.displayColor)
                .lineLimit(1)
                .minimumScaleFactor(0.55)

            Text("Current dB SPL")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                smaartMetric(label: "Peak", value: channel.compactPeak)
                smaartMetric(label: "Avg 10 min", value: channel.average10MinDB.map { String(format: "%.1f", $0) } ?? "—")
                Circle()
                    .fill(tile.smaartConnectionStatus.indicatorColor)
                    .frame(width: 13, height: 13)
                    .padding(.leading, 4)
            }

            if !tile.columnRows.isEmpty {
                Divider().opacity(0.45)
                columnTable
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.opacity(0.24))
    }

    private func smaartMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var columnTable: some View {
        VStack(spacing: 0) {
            if !tile.columnHeaders.isEmpty {
                HStack(spacing: 0) {
                    ForEach(Array(tile.columnHeaders.enumerated()), id: \.offset) { colIndex, header in
                        Text(header)
                            .font(.system(size: 10, weight: .semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: colIndex == 0 ? .infinity : 130, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                    }
                }
                .background(Color.white.opacity(0.04))
                Divider().opacity(0.5)
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(tile.columnRows.enumerated()), id: \.offset) { _, cols in
                        HStack(spacing: 0) {
                            ForEach(Array(cols.enumerated()), id: \.offset) { colIndex, cell in
                                Text(cell.isEmpty ? "—" : cell)
                                    .font(.system(size: 12, weight: colIndex == 0 ? .semibold : .regular))
                                    .foregroundStyle(colIndex == 0 ? Color.primary : Color.secondary)
                                    .lineLimit(1)
                                    .frame(maxWidth: colIndex == 0 ? .infinity : 130, alignment: .leading)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                            }
                        }
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1)
                        }
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }

    private var resizeHandle: some View {
        Rectangle()
            .fill(Color.white.opacity(0.035))
            .frame(maxWidth: .infinity)
            .frame(height: 18)
            .contentShape(Rectangle())
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 1)
            }
            .overlay(alignment: .center) {
                Capsule()
                    .fill(Color.primary.opacity(0.28))
                    .frame(width: 36, height: 3)
            }
            .gesture(resizeGesture)
            .onHover { isHovering in
                if isHovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}

struct MacSettingsView: View {
    @EnvironmentObject private var store: ProdConnectStore
    @EnvironmentObject private var ndiSettings: MacNDISettingsController
    @EnvironmentObject private var runOfShowControls: MacRunOfShowControlController
    @EnvironmentObject private var automaticMessaging: MacAutomaticMessagingController
    @ObservedObject private var timecodeController = MacExternalTimecodeController.shared
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

    private var availableSettingsSections: [MacSettingsSection] {
        MacSettingsSection.allCases.filter { section in
            switch section {
            case .overview:
                return hasNDIFeature
            default:
                return true
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Settings")
                .font(.system(size: 28, weight: .bold))

            settingsTabBar

            if selectedSection == .users {
                selectedSectionContent
            } else {
                ScrollView {
                    selectedSectionContent
                }
            }
        }
        .padding(20)
        .frame(minWidth: 860, minHeight: 620)
        .onAppear {
            if !availableSettingsSections.contains(selectedSection) {
                selectedSection = .integrations
            }
        }
        .onChange(of: hasNDIFeature) { _, _ in
            if !availableSettingsSections.contains(selectedSection) {
                selectedSection = .integrations
            }
        }
    }

    private var settingsTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(availableSettingsSections) { section in
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
        case .overview:
            if !hasNDIFeature {
                Text("Overview grid and NDI output are available on paid subscriptions.")
                    .foregroundStyle(.secondary)
            } else {
                overviewSettingsSection
            }
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

            automaticMessagingSection

            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Format", selection: $timecodeController.inputMode) {
                        ForEach(MacExternalTimecodeInputMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if timecodeController.inputMode == .mtc {
                        Picker(
                            "MTC MIDI Input",
                            selection: Binding(
                                get: { timecodeController.selectedMIDISourceID ?? timecodeController.midiSources.first?.id ?? "" },
                                set: { timecodeController.updateSelectedMIDISourceID($0) }
                            )
                        ) {
                            if timecodeController.midiSources.isEmpty {
                                Text("No MIDI Devices").tag("")
                            }
                            ForEach(timecodeController.midiSources) { source in
                                Text(source.name).tag(source.id)
                            }
                        }
                        .disabled(timecodeController.midiSources.isEmpty)
                    } else {
                        Picker(
                            "LTC Audio Input",
                            selection: Binding(
                                get: { timecodeController.selectedLTCAudioSourceID ?? timecodeController.ltcAudioSources.first?.id ?? "" },
                                set: { timecodeController.updateSelectedLTCAudioSourceID($0) }
                            )
                        ) {
                            if timecodeController.ltcAudioSources.isEmpty {
                                Text("No Audio Inputs").tag("")
                            }
                            ForEach(timecodeController.ltcAudioSources) { source in
                                Text(source.name).tag(source.id)
                            }
                        }
                        .disabled(timecodeController.ltcAudioSources.isEmpty)

                        ProgressView(value: timecodeController.lastLTCAudioLevel)
                            .progressViewStyle(.linear)
                    }

                    HStack(spacing: 8) {
                        Circle()
                            .fill(timecodeController.isReceiving ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(timecodeController.statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("Select an SMPTE MTC MIDI source or an SMPTE LTC audio input. Add Timecode in Settings > Overview to display it on the Overview tab and Overview NDI feed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } label: {
                Text("SMPTE Timecode")
                    .font(.headline)
            }
        }
    }

    private var automaticMessagingSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Enable automatic messaging", isOn: $automaticMessaging.isEnabled)
                    .disabled(!automaticMessaging.canManageMessaging)

                Picker(
                    "MIDI Input",
                    selection: Binding(
                        get: { automaticMessaging.selectedMIDISourceID ?? automaticMessaging.midiSources.first?.id ?? "" },
                        set: { automaticMessaging.updateSelectedMIDISourceID($0) }
                    )
                ) {
                    if automaticMessaging.midiSources.isEmpty {
                        Text("No MIDI Devices").tag("")
                    }
                    ForEach(automaticMessaging.midiSources) { source in
                        Text(source.name).tag(source.id)
                    }
                }
                .disabled(!automaticMessaging.canManageMessaging || automaticMessaging.midiSources.isEmpty)

                Text("Listening to \(automaticMessaging.midiSourceCount) available MIDI source\(automaticMessaging.midiSourceCount == 1 ? "" : "s"). Incoming MIDI Note On messages can send saved text to group channels.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !automaticMessaging.canManageMessaging {
                    Text("Automatic messaging is available to admins and owners on paid subscriptions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if automaticMessaging.groupChannels.isEmpty {
                    Text("Create a group chat channel before adding automatic message rules.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !automaticMessaging.lastStatusText.isEmpty {
                    Text(automaticMessaging.lastStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(automaticMessaging.rules) { rule in
                    automaticMessageRuleEditor(rule: rule)
                }

                Button("Add Message Trigger") {
                    automaticMessaging.addRule()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!automaticMessaging.canManageMessaging || automaticMessaging.groupChannels.isEmpty)
            }
        } label: {
            Text("Automatic Messaging")
                .font(.headline)
        }
    }

    private var ndiSettingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NDI Outputs")
                        .font(.title2.weight(.semibold))
                    Text("Each feed can target Patchsheet, Tickets, Run of Show, Run of Show Live, Stage Plot, or Micboard.")
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
                Text("NDI runtime is unavailable in this build. Network NDI output stays disabled until the bundled runtime is present.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 18) {
                HStack(spacing: 8) {
                    Text("Output Resolution")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker("Output Resolution", selection: $ndiSettings.outputResolution) {
                        ForEach(MacNDIOutputResolution.allCases) { resolution in
                            Text(resolution.title).tag(resolution)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                }

                HStack(spacing: 8) {
                    Text("FPS")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker("FPS", selection: $ndiSettings.outputFrameRate) {
                        ForEach(MacNDIFrameRate.allCases) { frameRate in
                            Text(frameRate.title).tag(frameRate)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }

                Text("Applies to all NDI feeds. Higher values increase CPU use.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .disabled(!canManageNDI)

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
                            } else if feed.sourceType == .tickets {
                                Picker("Status", selection: feedBinding(index, \.ticketStatusFilter)) {
                                    ForEach(MacTicketNDIStatusFilter.allCases) { option in
                                        Text(option.title).tag(option)
                                    }
                                }
                                .frame(width: 150)
                            } else if feed.sourceType == .runOfShow || feed.sourceType == .runOfShowLive || feed.sourceType == .stagePlot || feed.sourceType == .micboard {
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
                        }
                    }
                    .disabled(!canManageNDI)
                } label: {
                    Text("Feed \(index + 1)")
                        .font(.headline)
                }
            }
        }
        .onAppear {
            ndiSettings.closeAllPreviews()
        }
    }

    private var overviewSettingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Overview Grid")
                        .font(.title2.weight(.semibold))
                    Text("Choose the Mac windows to combine into one grid feed.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Create Overview Feed") {
                    ndiSettings.addOverviewFeedIfNeeded()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canManageNDI)
            }

            if !canManageNDI {
                Text("Only admins and owners can manage overview NDI settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if ndiSettings.overviewFeeds().isEmpty {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("No overview feed configured.")
                            .font(.headline)
                        Text("Create an overview feed, then select the windows to show and turn on Live to send it over NDI.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                }
            }

            ForEach(ndiSettings.overviewFeeds(), id: \.feed.id) { item in
                let index = item.index
                let feed = item.feed
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            TextField("Feed Name", text: feedBinding(index, \.title))
                                .textFieldStyle(.roundedBorder)
                            Toggle("Send over NDI", isOn: feedBinding(index, \.isLive))
                            Picker("Orientation", selection: feedBinding(index, \.orientation)) {
                                ForEach(MacNDIOrientation.allCases) { orientation in
                                    Text(orientation.title).tag(orientation)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 220)
                            Button("Remove") {
                                ndiSettings.removeFeed(id: feed.id)
                            }
                            .buttonStyle(.bordered)
                        }

                        HStack {
                            Text("Grid Scale")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Slider(value: feedBinding(index, \.scale), in: 0.75...1.35, step: 0.05)
                            Text("\(Int((feed.scale * 100).rounded()))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 48, alignment: .trailing)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Windows")
                                .font(.headline)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], spacing: 10) {
                                ForEach(ndiSettings.availableOverviewSources()) { source in
                                    Toggle(
                                        isOn: Binding(
                                            get: { feed.overviewRouteIDs.contains(source.id) },
                                            set: { ndiSettings.setOverviewSource(source, isIncluded: $0, at: index) }
                                        )
                                    ) {
                                        Label(source.title, systemImage: source.systemImage)
                                    }
                                    .toggleStyle(.checkbox)
                                    .disabled(!canManageNDI)
                                }
                            }
                        }

                        MacOverviewGridNDIPreview(
                            tiles: ndiSettings.overviewTiles(for: feed),
                            outputName: feed.title,
                            isActive: feed.isLive,
                            scale: min(feed.scale, 1.0),
                            sizesToContent: true
                        )
                    }
                    .disabled(!canManageNDI)
                } label: {
                    Text("Overview Feed")
                        .font(.headline)
                }
            }
        }
        .onAppear {
            ndiSettings.addOverviewFeedIfNeeded()
            ndiSettings.closeAllPreviews()
        }
    }

    private func automaticMessageRuleEditor(rule: MacAutomaticMessageRule) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Toggle(
                    "Enabled",
                    isOn: automaticMessageRuleBinding(rule, \.isEnabled)
                )
                .frame(width: 92, alignment: .leading)

                TextField("Rule Name", text: automaticMessageRuleBinding(rule, \.name))
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 160)

                Picker("Group", selection: automaticMessageRuleBinding(rule, \.channelID)) {
                    if automaticMessaging.groupChannels.isEmpty {
                        Text("No Group Channels").tag("")
                    }
                    ForEach(automaticMessaging.groupChannels) { channel in
                        Text(channel.name.isEmpty ? "Channel" : channel.name).tag(channel.id)
                    }
                }
                .frame(width: 220)

                Button("Remove") {
                    automaticMessaging.removeRule(id: rule.id)
                }
                .buttonStyle(.bordered)

                Spacer()
            }

            HStack(spacing: 12) {
                Picker("Trigger", selection: automaticMessageRuleBinding(rule, \.triggerType)) {
                    ForEach(MacAutomaticMessageTriggerType.allCases) { triggerType in
                        Text(triggerType.rawValue).tag(triggerType)
                    }
                }
                .frame(width: 180)

                if rule.triggerType == .timeOfDay {
                    DatePicker(
                        "Send At",
                        selection: automaticMessageTimeBinding(rule),
                        displayedComponents: [.hourAndMinute]
                    )
                    .frame(width: 220)
                }

                Spacer()
            }

            TextField("Message to send", text: automaticMessageRuleBinding(rule, \.messageText), axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)

            if rule.triggerType == .midiNote {
                HStack(spacing: 12) {
                    Stepper(
                        "Ch \(rule.midiChannel)",
                        value: automaticMessageRuleBinding(rule, \.midiChannel),
                        in: 1...16
                    )
                    .frame(width: 110)

                    Stepper(
                        "Note #\(rule.noteNumber)",
                        value: automaticMessageRuleBinding(rule, \.noteNumber),
                        in: 0...127
                    )
                    .frame(width: 130)

                    Stepper(
                        "Min Velocity \(rule.minimumVelocity)",
                        value: automaticMessageRuleBinding(rule, \.minimumVelocity),
                        in: 1...127
                    )
                    .frame(width: 165)

                    Button(automaticMessaging.isListening(ruleID: rule.id) ? "Listening..." : "Listen") {
                        automaticMessaging.toggleListening(ruleID: rule.id)
                    }
                    .buttonStyle(.borderedProminent)

                    Text("Sends to \(automaticMessaging.channelName(for: rule.channelID))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()
                }
            } else {
                Text("Sends to \(automaticMessaging.channelName(for: rule.channelID)) once per day at the selected time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
        .disabled(!automaticMessaging.canManageMessaging)
    }

    private func automaticMessageRuleBinding<Value>(_ rule: MacAutomaticMessageRule, _ keyPath: WritableKeyPath<MacAutomaticMessageRule, Value>) -> Binding<Value> {
        Binding(
            get: {
                automaticMessaging.rules.first(where: { $0.id == rule.id })?[keyPath: keyPath] ?? rule[keyPath: keyPath]
            },
            set: {
                automaticMessaging.updateRuleValue($0, ruleID: rule.id, keyPath: keyPath)
            }
        )
    }

    private func automaticMessageTimeBinding(_ rule: MacAutomaticMessageRule) -> Binding<Date> {
        Binding(
            get: {
                let minutes = automaticMessaging.rules.first(where: { $0.id == rule.id })?.timeOfDayMinutes ?? rule.timeOfDayMinutes
                var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                components.hour = minutes / 60
                components.minute = minutes % 60
                components.second = 0
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                let minutes = ((components.hour ?? 0) * 60) + (components.minute ?? 0)
                automaticMessaging.updateRuleValue(minutes, ruleID: rule.id, keyPath: \.timeOfDayMinutes)
            }
        )
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
        case .overview:
            MacOverviewGridNDIPreview(
                tiles: ndiSettings.overviewTiles(for: feed),
                outputName: feed.title,
                isActive: feed.isLive,
                scale: min(feed.scale, 1.0)
            )
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
        case .tickets:
            MacTicketsNDIPreview(
                tickets: ndiSettings.tickets(for: feed),
                outputName: feed.title,
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
        case .stagePlot:
            MacStagePlotNDIPreview(
                show: ndiSettings.runOfShow(for: feed),
                outputName: feed.title,
                isActive: feed.isLive,
                scale: min(feed.scale, 1.0)
            )
        case .micboard:
            let selectedRunOfShow = ndiSettings.runOfShow(for: feed)
            MacMicboardNDIPreview(
                show: selectedRunOfShow,
                patchsheetItems: ndiSettings.micboardItems(for: selectedRunOfShow),
                outputName: feed.title,
                isActive: feed.isLive,
                scale: min(feed.scale, 1.0)
            )
        }
    }
}

private struct MacPatchsheetNDIOutputConfiguration {
    let isActive: Bool
    let title: String
    let sourceType: MacNDIFeedSourceType
    let overviewTiles: [MacOverviewTileData]
    let category: String
    let runOfShow: RunOfShowDocument?
    let micboardItems: [RunOfShowMicboardItem]
    let tickets: [SupportTicket]
    let patches: [PatchRow]
    let nameColumnTitle: String
    let inputColumnTitle: String
    let outputColumnTitle: String
    let showsUniverseColumn: Bool
    let showsHeaders: Bool
    let scale: Double
    let orientation: MacNDIOrientation
    let resolution: MacNDIOutputResolution
    let frameRate: MacNDIFrameRate

    var outputSize: CGSize {
        resolution.outputSize(for: orientation)
    }

    var windowSize: CGSize {
        resolution.windowSize(for: orientation)
    }
}

private struct MacOverviewTileData: Identifiable {
    static let smaartSelectedChannelDefaultsKey = "prodconnect.overview.smaart.selectedChannelID"

    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let accent: Color
    let rows: [String]
    var columnHeaders: [String] = []
    var columnRows: [[String]] = []
    var stagePlotShow: RunOfShowDocument? = nil
    var runOfShowLiveShow: RunOfShowDocument? = nil
    var runOfShowLiveNow: Date = Date()
    var smaartChannel: SmaartChannel? = nil
    var smaartChannels: [SmaartChannel] = []
    var smaartConnectionStatus: SmaartConnectionStatus = .disconnected
    var timecodeDisplay: String? = nil
    var timecodeFrameRate: String = ""
    var timecodeStatus: String = ""
    var timecodeIsReceiving: Bool = false
}

@MainActor
private final class MacPatchsheetNDIOutputWindowController {
    private var window: NSWindow?
    private var currentConfiguration: MacPatchsheetNDIOutputConfiguration?
    private var frameTimer: Timer?
    private var timerFrameRate: MacNDIFrameRate?
    private let sender = MacNDISender()
    var isWindowVisible: Bool { window != nil }
    var liveOverviewTilesProvider: (() -> [MacOverviewTileData])? = nil

    // Frame cache — prevents re-rendering the heavy overview view every NDI tick.
    // Overview data changes at most ~1/s; other source types re-render every frame as before.
    private var cachedOverviewFrame: CGImage? = nil
    private var lastOverviewRenderTime: Date = .distantPast
    private var isRenderingFrame = false
    private static let overviewRenderInterval: TimeInterval = 1.0

    func update(configuration: MacPatchsheetNDIOutputConfiguration) {
        let wasActive = currentConfiguration?.isActive == true
        currentConfiguration = configuration

        let resolvedTitle = configuration.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "ProdConnect Patchsheet"
            : configuration.title.trimmingCharacters(in: .whitespacesAndNewlines)

        if configuration.isActive {
            sender.updateOutputName(resolvedTitle)
            startFrameTimerIfNeeded(frameRate: configuration.frameRate)
            if !wasActive {
                sendCurrentFrameIfPossible()
            }
        } else {
            frameTimer?.invalidate()
            frameTimer = nil
            timerFrameRate = nil
            cachedOverviewFrame = nil
            lastOverviewRenderTime = .distantPast
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
        timerFrameRate = nil
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
        let windowSize = currentConfiguration.windowSize

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
            case .overview:
                MacOverviewGridNDIPreview(
                    tiles: configuration.overviewTiles,
                    outputName: title,
                    isActive: sender.isReadyToSend,
                    scale: configuration.scale,
                    outputSize: configuration.outputSize
                )
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
            case .tickets:
                MacTicketsNDIPreview(
                    tickets: configuration.tickets,
                    outputName: title,
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
            case .stagePlot:
                MacStagePlotNDIPreview(
                    show: configuration.runOfShow,
                    outputName: title,
                    isActive: sender.isReadyToSend,
                    scale: configuration.scale
                )
            case .micboard:
                MacMicboardNDIPreview(
                    show: configuration.runOfShow,
                    patchsheetItems: configuration.micboardItems,
                    outputName: title,
                    isActive: sender.isReadyToSend,
                    scale: configuration.scale
                )
            }
        }
    }

    private func startFrameTimerIfNeeded(frameRate: MacNDIFrameRate) {
        if timerFrameRate != frameRate {
            frameTimer?.invalidate()
            frameTimer = nil
            timerFrameRate = nil
        }
        guard frameTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / frameRate.framesPerSecond, repeats: true) { [weak self] _ in
            guard let controller = self else { return }
            Task { @MainActor [controller] in
                controller.sendCurrentFrameIfPossible()
            }
        }
        frameTimer = timer
        timerFrameRate = frameRate
        RunLoop.main.add(timer, forMode: .default)
    }

    private func sendCurrentFrameIfPossible() {
        // Prevent queued tasks from piling up if a previous render is still running
        guard !isRenderingFrame else { return }
        guard sender.isReadyToSend, var currentConfiguration else { return }

        let resolvedTitle = currentConfiguration.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "ProdConnect Patchsheet"
            : currentConfiguration.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let outputSize = currentConfiguration.outputSize

        if currentConfiguration.sourceType == .micboard {
            MacMicboardImageCache.shared.preload(
                urlStrings: currentConfiguration.micboardItems.map(\.imageURLString) + (currentConfiguration.runOfShow?.sortedMicboardItems.map(\.imageURLString) ?? [])
            )
        }

        if currentConfiguration.sourceType == .overview, let provider = liveOverviewTilesProvider {
            let now = Date()
            let needsRender = cachedOverviewFrame == nil ||
                now.timeIntervalSince(lastOverviewRenderTime) >= Self.overviewRenderInterval

            if needsRender {
                isRenderingFrame = true
                let tiles = provider()
                currentConfiguration = MacPatchsheetNDIOutputConfiguration(
                    isActive: currentConfiguration.isActive,
                    title: currentConfiguration.title,
                    sourceType: currentConfiguration.sourceType,
                    overviewTiles: tiles,
                    category: currentConfiguration.category,
                    runOfShow: currentConfiguration.runOfShow,
                    micboardItems: currentConfiguration.micboardItems,
                    tickets: currentConfiguration.tickets,
                    patches: currentConfiguration.patches,
                    nameColumnTitle: currentConfiguration.nameColumnTitle,
                    inputColumnTitle: currentConfiguration.inputColumnTitle,
                    outputColumnTitle: currentConfiguration.outputColumnTitle,
                    showsUniverseColumn: currentConfiguration.showsUniverseColumn,
                    showsHeaders: currentConfiguration.showsHeaders,
                    scale: currentConfiguration.scale,
                    orientation: currentConfiguration.orientation,
                    resolution: currentConfiguration.resolution,
                    frameRate: currentConfiguration.frameRate
                )
                let preview = outputPreviewView(for: currentConfiguration, title: resolvedTitle)
                    .frame(width: outputSize.width, height: outputSize.height)
                if let image = MacNDIRenderer.snapshot(of: preview, size: outputSize) {
                    cachedOverviewFrame = image
                    lastOverviewRenderTime = now
                }
                isRenderingFrame = false
            }

            // Always send the cached frame so the NDI stream stays at the configured frame rate
            if let cached = cachedOverviewFrame {
                sender.send(image: cached, frameRate: currentConfiguration.frameRate)
            }
            return
        }

        // All other source types: render every frame as before
        isRenderingFrame = true
        let preview = outputPreviewView(for: currentConfiguration, title: resolvedTitle)
            .frame(width: outputSize.width, height: outputSize.height)
        if let image = MacNDIRenderer.snapshot(of: preview, size: outputSize) {
            sender.send(image: image, frameRate: currentConfiguration.frameRate)
        }
        isRenderingFrame = false
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
        // NDI should receive exact output pixels, not Retina-scaled backing pixels.
        renderer.scale = 1.0
        return renderer.cgImage
    }
}

@MainActor
private final class MacMicboardImageCache {
    static let shared = MacMicboardImageCache()

    private var imagesByURL: [URL: NSImage] = [:]
    private var loadingURLs: Set<URL> = []

    private init() {}

    func image(for url: URL) -> NSImage? {
        imagesByURL[url]
    }

    func preload(urlStrings: [String]) {
        for rawValue in urlStrings {
            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let url = URL(string: trimmed) else { continue }
            loadIfNeeded(url)
        }
    }

    private func loadIfNeeded(_ url: URL) {
        guard imagesByURL[url] == nil, !loadingURLs.contains(url) else { return }
        loadingURLs.insert(url)
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = NSImage(data: data) else {
                DispatchQueue.main.async {
                    self?.loadingURLs.remove(url)
                }
                return
            }
            DispatchQueue.main.async {
                self?.imagesByURL[url] = image
                self?.loadingURLs.remove(url)
            }
        }.resume()
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

    func send(image: CGImage, frameRate: MacNDIFrameRate) {
        guard let senderInstance else { return }
        guard let payload = makeVideoFramePayload(from: image, frameRate: frameRate) else { return }
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

    private func makeVideoFramePayload(from image: CGImage, frameRate: MacNDIFrameRate) -> (frame: NDIVideoFrameV2, storage: [UInt8])? {
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
                frame_rate_N: frameRate.numerator,
                frame_rate_D: frameRate.denominator,
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

private struct MacRunOfShowLiveOverviewTile: View {
    let show: RunOfShowDocument
    let now: Date
    var scale: Double = 1.0

    private var items: [RunOfShowItem] { show.sortedItems }
    private var currentIndex: Int? {
        let activeID = show.isLiveActive ? show.liveCurrentItemID : items.first?.id
        return show.itemIndex(for: activeID)
    }
    private var currentItem: RunOfShowItem? {
        currentIndex.flatMap { items.indices.contains($0) ? items[$0] : nil }
    }
    private var nextItem: RunOfShowItem? {
        currentIndex.flatMap { index in
            let nextIndex = index + 1
            return items.indices.contains(nextIndex) ? items[nextIndex] : nil
        }
    }
    private var remainingSeconds: Int {
        currentItem.map { show.isLiveActive ? show.currentRemainingSeconds(at: now) : $0.durationSeconds } ?? 0
    }
    private var overrunSeconds: Int {
        show.isLiveActive ? show.currentOverrunSeconds(at: now) : 0
    }
    private var isOverrun: Bool { overrunSeconds > 0 }
    private var projectedEndTime: Date {
        show.isLiveActive
            ? show.projectedEndTime(at: now)
            : show.scheduledStart.addingTimeInterval(TimeInterval(show.totalDurationSeconds))
    }

    var body: some View {
        HStack(spacing: 0) {
            liveSidebar
            liveMain
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.08, green: 0.09, blue: 0.11))
        .clipShape(RoundedRectangle(cornerRadius: 12 * scale, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12 * scale, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var liveSidebar: some View {
        VStack(spacing: 0) {
            countdownBlock
            rundownList
        }
        .frame(width: 155 * scale)
    }

    private var countdownBlock: some View {
        VStack(spacing: 6 * scale) {
            Text(isOverrun ? runOfShowOverrunClock(seconds: overrunSeconds) : runOfShowFormattedClock(seconds: remainingSeconds))
                .font(.system(size: 34 * scale, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(show.isLiveActive ? "Show should end \(projectedEndTime.formatted(date: .omitted, time: .shortened))" : "live not started")
                .font(.system(size: 10 * scale, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.82))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8 * scale)
        .padding(.vertical, 16 * scale)
        .background(isOverrun ? Color(red: 0.79, green: 0.17, blue: 0.2) : Color(red: 0.2, green: 0.68, blue: 0.36))
    }

    private var rundownList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.prefix(6).enumerated()), id: \.element.id) { index, item in
                rundownRow(item: item, index: index)
            }
            if items.count > 6 {
                Text("+\(items.count - 6) more")
                    .font(.system(size: 10 * scale, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .padding(.horizontal, 10 * scale)
                    .padding(.vertical, 7 * scale)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.1, green: 0.11, blue: 0.14))
    }

    private func rundownRow(item: RunOfShowItem, index: Int) -> some View {
        let isCurrent = item.id == currentItem?.id
        return Text(item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : item.title)
            .font(.system(size: 11 * scale, weight: isCurrent ? .semibold : .regular))
            .foregroundStyle(isCurrent ? Color.white : Color.white.opacity(0.68))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10 * scale)
            .padding(.vertical, 7 * scale)
            .background(isCurrent ? Color.orange.opacity(0.2) : (index.isMultiple(of: 2) ? Color.white.opacity(0.03) : Color.clear))
    }

    private var liveMain: some View {
        VStack(alignment: .leading, spacing: 0) {
            overviewLiveSection(label: "NOW", title: currentItem?.title, subtitle: currentItem.map(summary), accentLine: true)
                .background(Color(red: 0.11, green: 0.12, blue: 0.15))
            notesSection
            overviewLiveSection(label: "NEXT", title: nextItem?.title, subtitle: nextItem.map(summary) ?? "End of show", accentLine: false)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .background(Color(red: 0.09, green: 0.1, blue: 0.13))
        }
    }

    private var notesSection: some View {
        let notes = currentItem?.notes.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return VStack(alignment: .leading, spacing: 6 * scale) {
            Text("ITEM NOTES")
                .font(.system(size: 10 * scale, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.65))
            Text(notes.isEmpty ? "No item notes" : notes)
                .font(.system(size: 12 * scale))
                .foregroundStyle(Color.white.opacity(0.86))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(9 * scale)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8 * scale, style: .continuous))
        }
        .padding(14 * scale)
        .background(Color(red: 0.11, green: 0.12, blue: 0.15))
    }

    private func overviewLiveSection(label: String, title: String?, subtitle: String?, accentLine: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8 * scale) {
            Text(label)
                .font(.system(size: 10 * scale, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.7))
                .padding(.horizontal, 10 * scale)
                .padding(.vertical, 5 * scale)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6 * scale, style: .continuous))

            Text(title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? title ?? "" : (label == "NOW" ? "No active item" : "No next item"))
                .font(.system(size: 22 * scale, weight: .light))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11 * scale))
                    .foregroundStyle(Color.white.opacity(0.64))
                    .lineLimit(1)
            }
        }
        .padding(14 * scale)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottom) {
            if accentLine {
                Rectangle()
                    .fill(Color(red: 0.2, green: 0.68, blue: 0.36))
                    .frame(height: max(1, 2 * scale))
            }
        }
    }

    private func summary(for item: RunOfShowItem) -> String {
        "\(item.formattedDuration) • \(item.person.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No person assigned" : item.person)"
    }
}

private struct MacOverviewGridNDIPreview: View {
    let tiles: [MacOverviewTileData]
    let outputName: String
    let isActive: Bool
    let scale: Double
    var outputSize: CGSize? = nil
    var allowsTileScrolling = false
    var sizesToContent = false
    private let outerPaddingBase: Double = 20
    private let headerHeightBase: Double = 40
    private let headerSpacingBase: Double = 16
    private let tileGapBase: Double = 14

    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 14 * scale),
            GridItem(.flexible(), spacing: 14 * scale)
        ]
    }

    var body: some View {
        overviewContent(effectiveScale)
        .padding(outerPaddingBase * effectiveScale)
        .frame(maxWidth: .infinity, maxHeight: sizesToContent ? nil : .infinity, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.07, blue: 0.11),
                    Color(red: 0.02, green: 0.03, blue: 0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var effectiveScale: Double {
        guard let outputSize else { return scale }
        let contentHeight = measuredContentHeight(at: scale)
        guard contentHeight > outputSize.height, contentHeight > 0 else { return scale }
        return max(0.35, scale * (outputSize.height / contentHeight))
    }

    private func measuredContentHeight(at candidateScale: Double) -> Double {
        let leftTiles = tiles.enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
        let rightTiles = tiles.enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
        let leftHeight = measuredColumnHeight(leftTiles, scale: candidateScale)
        let rightHeight = measuredColumnHeight(rightTiles, scale: candidateScale)
        let gridHeight = tiles.isEmpty ? 220 * candidateScale : max(leftHeight, rightHeight)
        return (outerPaddingBase * 2 + headerHeightBase + headerSpacingBase) * candidateScale + gridHeight
    }

    private func measuredColumnHeight(_ columnTiles: [MacOverviewTileData], scale candidateScale: Double) -> Double {
        guard !columnTiles.isEmpty else { return 0 }
        let tileHeights = columnTiles.reduce(0) { total, tile in
            total + storedTileHeight(tile) * candidateScale
        }
        return tileHeights + Double(max(columnTiles.count - 1, 0)) * tileGapBase * candidateScale
    }

    private func overviewContent(_ contentScale: Double) -> some View {
        VStack(alignment: .leading, spacing: headerSpacingBase * contentScale) {
            overviewHeader(contentScale)
            overviewGrid(contentScale)
        }
    }

    private func overviewHeader(_ contentScale: Double) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4 * contentScale) {
                Text(outputName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "ProdConnect Overview" : outputName)
                    .font(.system(size: 28 * contentScale, weight: .bold))
                    .foregroundStyle(.white)
                Text("\(tiles.count) selected window\(tiles.count == 1 ? "" : "s")")
                    .font(.system(size: 12 * contentScale, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.68))
            }
            Spacer()
            Text(isActive ? "LIVE" : "PREVIEW")
                .font(.system(size: 10 * contentScale, weight: .bold))
                .padding(.horizontal, 10 * contentScale)
                .padding(.vertical, 6 * contentScale)
                .background((isActive ? Color.green : Color.gray).opacity(0.22))
                .clipShape(Capsule())
                .foregroundStyle(isActive ? Color.green : Color.white.opacity(0.75))
        }
        .frame(minHeight: headerHeightBase * contentScale)
    }

    @ViewBuilder
    private func overviewGrid(_ contentScale: Double) -> some View {
        if tiles.isEmpty {
            VStack(spacing: 10 * contentScale) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 34 * contentScale))
                    .foregroundStyle(Color.white.opacity(0.5))
                Text("No windows selected")
                    .font(.system(size: 22 * contentScale, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Select windows in Settings to populate this overview.")
                    .font(.system(size: 13 * contentScale))
                    .foregroundStyle(Color.white.opacity(0.64))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let leftTiles = tiles.enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
            let rightTiles = tiles.enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
            HStack(alignment: .top, spacing: tileGapBase * contentScale) {
                VStack(spacing: tileGapBase * contentScale) {
                    ForEach(leftTiles) { tile in
                        overviewTile(tile, scale: contentScale)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                VStack(spacing: tileGapBase * contentScale) {
                    ForEach(rightTiles) { tile in
                        overviewTile(tile, scale: contentScale)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private var tileRows: [[MacOverviewTileData]] {
        stride(from: 0, to: tiles.count, by: 2).map { index in
            Array(tiles[index..<min(index + 2, tiles.count)])
        }
    }

    private func overviewTile(_ tile: MacOverviewTileData, scale tileScale: Double? = nil) -> some View {
        let renderScale = tileScale ?? scale
        return VStack(alignment: .leading, spacing: 10 * renderScale) {
            HStack(spacing: 10 * renderScale) {
                Image(systemName: tile.systemImage)
                    .font(.system(size: 15 * renderScale, weight: .semibold))
                    .foregroundStyle(tile.accent)
                    .frame(width: 28 * renderScale, height: 28 * renderScale)
                    .background(tile.accent.opacity(0.16))
                    .clipShape(RoundedRectangle(cornerRadius: 7 * renderScale, style: .continuous))
                VStack(alignment: .leading, spacing: 2 * renderScale) {
                    Text(tile.title)
                        .font(.system(size: 18 * renderScale, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(tile.subtitle)
                        .font(.system(size: 11 * renderScale, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.62))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            if let show = tile.runOfShowLiveShow {
                MacRunOfShowLiveOverviewTile(show: show, now: tile.runOfShowLiveNow, scale: renderScale)
            } else if let show = tile.stagePlotShow {
                MacStagePlotCanvas(show: show, scale: renderScale)
                    .padding(4 * renderScale)
            } else if tile.timecodeDisplay != nil {
                ndiTimecodeDisplay(tile, renderScale: renderScale)
            } else if let channel = tile.smaartChannel {
                ndiSmaartMeter(channel, extraRows: tile.columnRows, connectionStatus: tile.smaartConnectionStatus, renderScale: renderScale)
            } else if !tile.columnRows.isEmpty {
                ndiColumnRows(tile.columnRows, renderScale: renderScale)
            } else if tile.rows.isEmpty {
                Text("No items to show")
                    .font(.system(size: 12 * renderScale))
                    .foregroundStyle(Color.white.opacity(0.56))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                if allowsTileScrolling {
                    ScrollView {
                        tileRows(tile.rows, renderScale: renderScale)
                    }
                    .scrollIndicators(.visible)
                } else {
                    tileRows(Array(tile.rows.prefix(8)), renderScale: renderScale)
                }
            }
        }
        .padding(14 * renderScale)
        .frame(maxWidth: .infinity, minHeight: storedTileHeight(tile) * renderScale, maxHeight: storedTileHeight(tile) * renderScale, alignment: .topLeading)
        .background(Color.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 12 * renderScale, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12 * renderScale, style: .continuous)
                .stroke(tile.accent.opacity(0.24), lineWidth: 1)
        )
    }

    private func ndiTimecodeDisplay(_ tile: MacOverviewTileData, renderScale: Double) -> some View {
        VStack(alignment: .leading, spacing: 14 * renderScale) {
            Text(tile.timecodeDisplay ?? "--:--:--:--")
                .font(.system(size: 54 * renderScale, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(tile.timecodeIsReceiving ? Color.green : Color.orange)
                .lineLimit(1)
                .minimumScaleFactor(0.28)
            HStack(spacing: 10 * renderScale) {
                Text(tile.timecodeFrameRate.isEmpty ? "SMPTE" : tile.timecodeFrameRate)
                    .font(.system(size: 12 * renderScale, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.62))
                Circle()
                    .fill(tile.timecodeIsReceiving ? Color.green : Color.orange)
                    .frame(width: 8 * renderScale, height: 8 * renderScale)
                Text(tile.timecodeStatus)
                    .font(.system(size: 12 * renderScale))
                    .foregroundStyle(Color.white.opacity(0.62))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func ndiSmaartMeter(_ channel: SmaartChannel, extraRows: [[String]], connectionStatus: SmaartConnectionStatus, renderScale: Double? = nil) -> some View {
        let meterScale = renderScale ?? scale
        return VStack(alignment: .leading, spacing: 9 * meterScale) {
            Text(channel.name)
                .font(.system(size: 14 * meterScale, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Text(String(format: "%.1f", channel.dB))
                .font(.system(size: 48 * meterScale, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(channel.levelColor?.color ?? .white)
                .lineLimit(1)
                .minimumScaleFactor(0.55)

            Text("Current dB SPL")
                .font(.system(size: 11 * meterScale, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.62))

            HStack(spacing: 8 * meterScale) {
                ndiSmaartMetric(label: "Peak", value: channel.compactPeak, renderScale: meterScale)
                ndiSmaartMetric(label: "Avg 10 min", value: channel.average10MinDB.map { String(format: "%.1f", $0) } ?? "—", renderScale: meterScale)
                Circle()
                    .fill(connectionStatus.indicatorColor)
                    .frame(width: 10 * meterScale, height: 10 * meterScale)
            }

            if !extraRows.isEmpty {
                ndiColumnRows(extraRows, renderScale: meterScale)
                    .padding(.top, 4 * meterScale)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func ndiSmaartMetric(label: String, value: String, renderScale: Double? = nil) -> some View {
        let metricScale = renderScale ?? scale
        return VStack(alignment: .leading, spacing: 2 * metricScale) {
            Text(label)
                .font(.system(size: 9 * metricScale, weight: .bold))
                .textCase(.uppercase)
                .foregroundStyle(Color.white.opacity(0.58))
            Text(value)
                .font(.system(size: 18 * metricScale, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9 * metricScale)
        .padding(.vertical, 7 * metricScale)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7 * metricScale, style: .continuous))
    }

    private func storedTileHeight(_ tile: MacOverviewTileData) -> Double {
        let saved = UserDefaults.standard.double(forKey: "prodconnect.overviewTileHeight.\(tile.id)")
        return saved > 0 ? min(saved, 1800) : 280
    }

    private func ndiColumnRows(_ columnRows: [[String]], renderScale: Double? = nil) -> some View {
        let rowScale = renderScale ?? scale
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(columnRows.enumerated()), id: \.offset) { _, cols in
                HStack(spacing: 0) {
                    ForEach(Array(cols.enumerated()), id: \.offset) { colIndex, cell in
                        Text(cell.isEmpty ? "—" : cell)
                            .font(.system(size: 12 * rowScale, weight: colIndex == 0 ? .semibold : .regular))
                            .foregroundStyle(colIndex == 0 ? Color.white : Color.white.opacity(0.75))
                            .lineLimit(1)
                            .frame(maxWidth: colIndex == 0 ? .infinity : 110 * rowScale, alignment: .leading)
                    }
                }
                .padding(.vertical, 5 * rowScale)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
                }
            }
        }
    }

    private func tileRows(_ rows: [String], renderScale: Double? = nil) -> some View {
        let rowScale = renderScale ?? scale
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                Text(row.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : row)
                    .font(.system(size: 12 * rowScale, weight: index == 0 ? .semibold : .regular))
                    .foregroundStyle(index == 0 ? Color.white : Color.white.opacity(0.78))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6 * rowScale)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.white.opacity(0.06))
                            .frame(height: 1)
                    }
            }
        }
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
                        headerCell("Notes")
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
                            valueCell(patch.notes)
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

private struct MacStagePlotNDIPreview: View {
    let show: RunOfShowDocument?
    let outputName: String
    let isActive: Bool
    let scale: Double

    var body: some View {
        let items = show?.sortedStagePlotItems ?? []
        let resolvedTitle = show?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return ZStack(alignment: .topLeading) {
            stagePlotPreviewSurface(type: show?.stageType ?? .rectangle)

            VStack(alignment: .leading, spacing: 8 * scale) {
                HStack {
                    VStack(alignment: .leading, spacing: 4 * scale) {
                        Text(outputName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "ProdConnect Stage Plot" : outputName)
                            .font(.system(size: 26 * scale, weight: .bold))
                            .foregroundStyle(.white)
                        Text(resolvedTitle.isEmpty ? "Stage Plot Preview" : resolvedTitle)
                            .font(.system(size: 12 * scale, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.7))
                    }
                    Spacer()
                    Text(isActive ? "LIVE" : "PREVIEW")
                        .font(.system(size: 10 * scale, weight: .bold))
                        .padding(.horizontal, 10 * scale)
                        .padding(.vertical, 6 * scale)
                        .background((isActive ? Color.green : Color.gray).opacity(0.24))
                        .clipShape(Capsule())
                        .foregroundStyle(isActive ? Color.green : Color.white.opacity(0.75))
                }
                Spacer()
            }
            .padding(20 * scale)

            VStack {
                Text("UPSTAGE")
                    .font(.system(size: 11 * scale, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.76))
                Spacer()
                HStack {
                    Text("STAGE RIGHT")
                    Spacer()
                    Text("STAGE LEFT")
                }
                .font(.system(size: 10 * scale, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.54))
                Text("DOWNSTAGE")
                    .font(.system(size: 11 * scale, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.76))
            }
            .padding(24 * scale)

            GeometryReader { proxy in
                let size = proxy.size
                ForEach(items) { item in
                    stagePlotPreviewNode(item)
                    .scaleEffect(item.sizeScale)
                    .rotationEffect(.degrees(item.rotationDegrees))
                    .position(
                        x: 44 * scale + item.x * max(size.width - (88 * scale), 1),
                        y: 86 * scale + item.y * max(size.height - (172 * scale), 1)
                    )
                }
            }

            if items.isEmpty {
                VStack(spacing: 10 * scale) {
                    Image(systemName: "music.note.house")
                        .font(.system(size: 34 * scale))
                        .foregroundStyle(Color.white.opacity(0.48))
                    Text("No stage plot items")
                        .font(.system(size: 22 * scale, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Add instruments or vocals in Run of Show to populate this feed.")
                        .font(.system(size: 13 * scale))
                        .foregroundStyle(Color.white.opacity(0.64))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func stagePlotPreviewSurface(type: RunOfShowStageType) -> some View {
        ZStack {
            switch type {
            case .rectangle:
                RoundedRectangle(cornerRadius: 22 * scale, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.13, green: 0.13, blue: 0.16),
                                Color(red: 0.07, green: 0.07, blue: 0.1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                RoundedRectangle(cornerRadius: 22 * scale, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    .padding(14 * scale)
            case .archedFront:
                MacStagePlotArchedFrontShape(curveDepth: 0.18, cornerRadius: 22 * scale)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.13, green: 0.13, blue: 0.16),
                            Color(red: 0.07, green: 0.07, blue: 0.1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                MacStagePlotArchedFrontShape(curveDepth: 0.18, cornerRadius: 22 * scale)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                .padding(14 * scale)
            case .round:
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.13, green: 0.13, blue: 0.16),
                                Color(red: 0.07, green: 0.07, blue: 0.1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    .padding(14 * scale)
            }
        }
    }

    private func stagePlotPreviewTitle(_ item: RunOfShowStagePlotItem) -> String {
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? item.role.defaultTitle : title
    }

    private func stagePlotPreviewColor(for role: RunOfShowStagePlotRole) -> Color {
        switch role {
        case .instrument:
            return Color(red: 0.25, green: 0.52, blue: 0.94)
        case .vocal:
            return Color(red: 0.88, green: 0.33, blue: 0.46)
        case .drumSet:
            return Color(red: 0.77, green: 0.41, blue: 0.18)
        case .guitar:
            return Color(red: 0.98, green: 0.66, blue: 0.19)
        case .bassGuitar:
            return Color(red: 0.28, green: 0.77, blue: 0.58)
        case .microphoneStand:
            return Color(red: 0.69, green: 0.37, blue: 0.93)
        case .keyboard:
            return Color(red: 0.36, green: 0.72, blue: 0.96)
        case .speaker:
            return Color(red: 0.54, green: 0.59, blue: 0.66)
        }
    }

    @ViewBuilder
    private func stagePlotPreviewNode(_ item: RunOfShowStagePlotItem) -> some View {
        if item.role.usesSymbolArtwork {
            VStack(spacing: 6 * scale) {
                stagePlotPreviewArtwork(for: item.role, color: stagePlotPreviewColor(for: item.role))
                    .frame(width: 46 * scale, height: 40 * scale)
                Text(stagePlotPreviewTitle(item))
                    .font(.system(size: 11 * scale, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 10 * scale)
                    .padding(.vertical, 6 * scale)
                    .background(Color.black.opacity(0.32))
                    .clipShape(Capsule())
            }
            .padding(10 * scale)
            .background(
                RoundedRectangle(cornerRadius: 14 * scale, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14 * scale, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
        } else {
            VStack(alignment: .leading, spacing: 2 * scale) {
                Text(stagePlotPreviewTitle(item))
                    .font(.system(size: 12 * scale, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if !item.subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(item.subtitle)
                        .font(.system(size: 10 * scale))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10 * scale)
            .padding(.vertical, 8 * scale)
            .frame(minWidth: 100 * scale, maxWidth: 170 * scale, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12 * scale, style: .continuous)
                    .fill(stagePlotPreviewColor(for: item.role).opacity(0.86))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12 * scale, style: .continuous)
                    .stroke(Color.white.opacity(0.26), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func stagePlotPreviewArtwork(for role: RunOfShowStagePlotRole, color: Color) -> some View {
        if let symbolName = role.systemImageName {
            ZStack {
                Circle()
                    .fill(color.opacity(0.22))
                    .frame(width: 38 * scale, height: 38 * scale)
                Image(systemName: symbolName)
                    .font(.system(size: 21 * scale, weight: .semibold))
                    .foregroundStyle(.white)
            }
        } else {
            EmptyView()
        }
    }
}

private struct MacStagePlotCanvas: View {
    let show: RunOfShowDocument?
    var scale: Double = 1.0

    var body: some View {
        let items = show?.sortedStagePlotItems ?? []
        ZStack {
            surfaceShape(type: show?.stageType ?? .rectangle)
            VStack {
                Text("UPSTAGE")
                    .font(.system(size: 9 * scale, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.55))
                Spacer()
                HStack {
                    Text("STAGE RIGHT")
                    Spacer()
                    Text("STAGE LEFT")
                }
                .font(.system(size: 8 * scale, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.38))
                Text("DOWNSTAGE")
                    .font(.system(size: 9 * scale, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            .padding(12 * scale)
            if items.isEmpty {
                VStack(spacing: 6 * scale) {
                    Image(systemName: "music.note.house")
                        .font(.system(size: 22 * scale))
                        .foregroundStyle(Color.white.opacity(0.38))
                    Text("No stage plot items")
                        .font(.system(size: 12 * scale))
                        .foregroundStyle(Color.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { proxy in
                    let size = proxy.size
                    let padX = 20 * scale
                    let padY = 28 * scale
                    ForEach(items) { item in
                        node(item)
                            .scaleEffect(item.sizeScale)
                            .rotationEffect(.degrees(item.rotationDegrees))
                            .position(
                                x: padX + item.x * max(size.width - padX * 2, 1),
                                y: padY + item.y * max(size.height - padY * 2, 1)
                            )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func surfaceShape(type: RunOfShowStageType) -> some View {
        let gradient = LinearGradient(
            colors: [Color(red: 0.13, green: 0.13, blue: 0.16), Color(red: 0.07, green: 0.07, blue: 0.1)],
            startPoint: .top, endPoint: .bottom
        )
        return ZStack {
            switch type {
            case .rectangle:
                RoundedRectangle(cornerRadius: 14 * scale, style: .continuous).fill(gradient)
                RoundedRectangle(cornerRadius: 14 * scale, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1).padding(10 * scale)
            case .archedFront:
                MacStagePlotArchedFrontShape(curveDepth: 0.18, cornerRadius: 14 * scale).fill(gradient)
                MacStagePlotArchedFrontShape(curveDepth: 0.18, cornerRadius: 14 * scale).stroke(Color.white.opacity(0.12), lineWidth: 1).padding(10 * scale)
            case .round:
                Circle().fill(gradient)
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 1).padding(10 * scale)
            }
        }
    }

    @ViewBuilder private func node(_ item: RunOfShowStagePlotItem) -> some View {
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? item.role.defaultTitle : item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let color = roleColor(item.role)
        if item.role.usesSymbolArtwork, let symbolName = item.role.systemImageName {
            VStack(spacing: 4 * scale) {
                ZStack {
                    Circle().fill(color.opacity(0.22)).frame(width: 30 * scale, height: 30 * scale)
                    Image(systemName: symbolName).font(.system(size: 16 * scale, weight: .semibold)).foregroundStyle(.white)
                }
                Text(title).font(.system(size: 9 * scale, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    .padding(.horizontal, 6 * scale).padding(.vertical, 3 * scale)
                    .background(Color.black.opacity(0.32)).clipShape(Capsule())
            }
            .padding(7 * scale)
            .background(RoundedRectangle(cornerRadius: 10 * scale, style: .continuous).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 10 * scale, style: .continuous).stroke(Color.white.opacity(0.18), lineWidth: 1))
        } else {
            VStack(alignment: .leading, spacing: 2 * scale) {
                Text(title).font(.system(size: 10 * scale, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                if !item.subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(item.subtitle).font(.system(size: 8 * scale)).foregroundStyle(Color.white.opacity(0.72)).lineLimit(1)
                }
            }
            .padding(.horizontal, 8 * scale).padding(.vertical, 6 * scale)
            .frame(minWidth: 70 * scale, maxWidth: 130 * scale, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9 * scale, style: .continuous).fill(color.opacity(0.86)))
            .overlay(RoundedRectangle(cornerRadius: 9 * scale, style: .continuous).stroke(Color.white.opacity(0.26), lineWidth: 1))
        }
    }

    private func roleColor(_ role: RunOfShowStagePlotRole) -> Color {
        switch role {
        case .instrument: return Color(red: 0.25, green: 0.52, blue: 0.94)
        case .vocal: return Color(red: 0.88, green: 0.33, blue: 0.46)
        case .drumSet: return Color(red: 0.77, green: 0.41, blue: 0.18)
        case .guitar: return Color(red: 0.98, green: 0.66, blue: 0.19)
        case .bassGuitar: return Color(red: 0.28, green: 0.77, blue: 0.58)
        case .microphoneStand: return Color(red: 0.69, green: 0.37, blue: 0.93)
        case .keyboard: return Color(red: 0.36, green: 0.72, blue: 0.96)
        case .speaker: return Color(red: 0.54, green: 0.59, blue: 0.66)
        }
    }
}

private enum StagePlotRotationCorner: CaseIterable, Identifiable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing

    var id: Self { self }

    var alignment: Alignment {
        switch self {
        case .topLeading:
            return .topLeading
        case .topTrailing:
            return .topTrailing
        case .bottomLeading:
            return .bottomLeading
        case .bottomTrailing:
            return .bottomTrailing
        }
    }

    var offset: CGSize {
        switch self {
        case .topLeading:
            return CGSize(width: -14, height: -14)
        case .topTrailing:
            return CGSize(width: 14, height: -14)
        case .bottomLeading:
            return CGSize(width: -14, height: 14)
        case .bottomTrailing:
            return CGSize(width: 14, height: 14)
        }
    }

    var iconRotationDegrees: Double {
        switch self {
        case .topLeading:
            return 180
        case .topTrailing:
            return 0
        case .bottomLeading:
            return 90
        case .bottomTrailing:
            return -90
        }
    }
}

private struct MacTicketsNDIPreview: View {
    let tickets: [SupportTicket]
    let outputName: String
    let isActive: Bool
    let scale: Double

    private var visibleTickets: [SupportTicket] {
        tickets.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4 * scale) {
                    Text(outputName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "ProdConnect Tickets" : outputName)
                        .font(.system(size: 30 * scale, weight: .bold))
                        .foregroundStyle(.white)
                    Text("\(visibleTickets.count) visible tickets")
                        .font(.system(size: 12 * scale, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.72))
                }
                Spacer()
                Circle()
                    .fill(isActive ? Color.green : Color.gray.opacity(0.6))
                    .frame(width: 12 * scale, height: 12 * scale)
            }
            .padding(.horizontal, 24 * scale)
            .padding(.vertical, 20 * scale)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.08, green: 0.12, blue: 0.18), Color(red: 0.04, green: 0.06, blue: 0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

            if visibleTickets.isEmpty {
                VStack(spacing: 10 * scale) {
                    Image(systemName: "ticket")
                        .font(.system(size: 34 * scale))
                        .foregroundStyle(Color.white.opacity(0.5))
                    Text("No visible tickets")
                        .font(.system(size: 22 * scale, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Tickets will appear here when they are visible to the current user.")
                        .font(.system(size: 13 * scale))
                        .foregroundStyle(Color.white.opacity(0.62))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.05, green: 0.06, blue: 0.08))
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        ticketsHeaderCell("Subject", width: 520 * scale)
                        ticketsHeaderCell("Status", width: 130 * scale)
                        ticketsHeaderCell("Requester", width: 220 * scale)
                        ticketsHeaderCell("Updated", width: 170 * scale)
                    }
                    .background(Color.white.opacity(0.08))

                    ForEach(Array(visibleTickets.prefix(10).enumerated()), id: \.element.id) { index, ticket in
                        HStack(spacing: 0) {
                            ticketsValueCell(ticket.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : ticket.title, width: 520 * scale, emphasized: true)
                            ticketsStatusCell(ticket, width: 130 * scale)
                            ticketsValueCell(ticketRequesterName(ticket), width: 220 * scale)
                            ticketsValueCell(ticket.updatedAt.formatted(date: .abbreviated, time: .shortened), width: 170 * scale)
                        }
                        .background(index.isMultiple(of: 2) ? Color.white.opacity(0.03) : Color.clear)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(Color.white.opacity(0.06))
                                .frame(height: 1)
                        }
                    }
                }
                .background(Color(red: 0.05, green: 0.06, blue: 0.08))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20 * scale, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20 * scale, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func ticketsHeaderCell(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .font(.system(size: 11 * scale, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.68))
            .textCase(.uppercase)
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, 14 * scale)
            .padding(.vertical, 10 * scale)
    }

    private func ticketsValueCell(_ value: String, width: CGFloat, emphasized: Bool = false) -> some View {
        Text(value)
            .font(.system(size: emphasized ? 14 * scale : 13 * scale, weight: emphasized ? .semibold : .regular))
            .foregroundStyle(.white)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, 14 * scale)
            .padding(.vertical, 12 * scale)
    }

    private func ticketsStatusCell(_ ticket: SupportTicket, width: CGFloat) -> some View {
        Text(ticket.status.rawValue)
            .font(.system(size: 12 * scale, weight: .semibold))
            .foregroundStyle(ticketStatusColor(ticket.status))
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, 14 * scale)
            .padding(.vertical, 12 * scale)
    }

    private func ticketRequesterName(_ ticket: SupportTicket) -> String {
        let name = ticket.externalRequesterName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !name.isEmpty { return name }
        let createdBy = ticket.createdBy?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return createdBy.isEmpty ? "Unknown" : createdBy
    }

    private func ticketStatusColor(_ status: TicketStatus) -> Color {
        switch status {
        case .new:
            return Color(red: 0.47, green: 0.74, blue: 1.0)
        case .open:
            return Color(red: 0.63, green: 0.82, blue: 0.99)
        case .inProgress:
            return Color(red: 0.99, green: 0.72, blue: 0.25)
        case .resolved:
            return Color(red: 0.41, green: 0.85, blue: 0.55)
        }
    }
}

private struct MacMicboardNDIPreview: View {
    let show: RunOfShowDocument?
    let patchsheetItems: [RunOfShowMicboardItem]
    let outputName: String
    let isActive: Bool
    let scale: Double

    private var titleText: String {
        let title = show?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? "Micboard" : title
    }

    private var dateText: String {
        guard let date = show?.scheduledStart else { return "" }
        return date.formatted(date: .long, time: .omitted)
    }

    var body: some View {
        let assignments = patchsheetItems + (show?.sortedMicboardItems.filter { !$0.id.hasPrefix("patchsheet-") } ?? [])

        return VStack(alignment: .leading, spacing: 22 * scale) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7 * scale) {
                    Text(titleText)
                        .font(.system(size: 34 * scale, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(dateText)
                        .font(.system(size: 18 * scale, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.58))
                }
                Spacer()
                Text(isActive ? "LIVE" : "PREVIEW")
                    .font(.system(size: 10 * scale, weight: .bold))
                    .padding(.horizontal, 10 * scale)
                    .padding(.vertical, 6 * scale)
                    .background((isActive ? Color.green : Color.gray).opacity(0.22))
                    .clipShape(Capsule())
                    .foregroundStyle(isActive ? Color.green : Color.white.opacity(0.75))
            }

            if assignments.isEmpty {
                VStack(spacing: 12 * scale) {
                    Image(systemName: "music.mic")
                        .font(.system(size: 46 * scale, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.44))
                    Text("No micboard assignments")
                        .font(.system(size: 24 * scale, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Add performers, microphones, and in-ear mixes in Run of Show.")
                        .font(.system(size: 14 * scale, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { proxy in
                    let columns = max(1, min(assignments.count, 8))
                    HStack(spacing: 0) {
                        ForEach(assignments) { assignment in
                            micboardColumn(assignment)
                                .frame(width: proxy.size.width / CGFloat(columns))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
        .padding(24 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.06, blue: 0.13),
                    Color(red: 0.08, green: 0.12, blue: 0.20),
                    Color(red: 0.05, green: 0.08, blue: 0.14)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func micboardColumn(_ item: RunOfShowMicboardItem) -> some View {
        VStack(spacing: 0) {
            micboardImageBlock(item)
                .aspectRatio(2.12, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8 * scale, style: .continuous))
                .padding(.horizontal, 14 * scale)
                .padding(.top, 14 * scale)
            VStack(spacing: 18 * scale) {
                VStack(spacing: 6 * scale) {
                    Text(item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unassigned" : item.name)
                        .font(.system(size: 25 * scale, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.55)
                    Text(item.role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? " " : item.role)
                        .font(.system(size: 13 * scale, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .lineLimit(1)
                }
                Spacer()
                if !item.microphone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    assignmentBadge(label: "Microphone", value: item.microphone)
                }
                if !item.inEarMonitor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    assignmentBadge(label: "In-Ear Monitor", value: item.inEarMonitor)
                }
            }
            .padding(.horizontal, 18 * scale)
            .padding(.vertical, 22 * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.white.opacity(0.035))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)
        }
    }

    private func micboardImageBlock(_ item: RunOfShowMicboardItem) -> some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.12),
                        Color.white.opacity(0.035)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                if let url = URL(string: item.imageURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
                   !item.imageURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let image = MacMicboardImageCache.shared.image(for: url) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else {
                    Text(initials(for: item.name))
                        .font(.system(size: 38 * scale, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
        }
        .clipped()
    }

    private func assignmentBadge(label: String, value: String) -> some View {
        VStack(spacing: 7 * scale) {
            Text(label)
                .font(.system(size: 10 * scale, weight: .bold))
                .textCase(.uppercase)
                .foregroundStyle(Color.white.opacity(0.58))
                .lineLimit(1)
            Text(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "-" : value)
                .font(.system(size: 20 * scale, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10 * scale)
        .padding(.vertical, 10 * scale)
        .background(Color.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 8 * scale, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8 * scale, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let result = parts.compactMap { $0.first }.map(String.init).joined()
        return result.isEmpty ? "?" : result.uppercased()
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

                GeometryReader { proxy in
                    let itemCount = max(items.count, 1)
                    let rowHeight = max(18 * scale, min(40 * scale, proxy.size.height / CGFloat(itemCount)))
                    let rowFontSize = max(9 * scale, min(12 * scale, rowHeight * 0.34))

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(items, id: \.id) { item in
                            HStack(spacing: 8 * scale) {
                                Text(item.title)
                                    .font(.system(size: rowFontSize, weight: item.id == currentItem?.id ? .semibold : .regular))
                                    .foregroundStyle(item.id == currentItem?.id ? Color.white : Color.white.opacity(0.68))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10 * scale)
                            .frame(maxWidth: .infinity, minHeight: rowHeight, maxHeight: rowHeight, alignment: .leading)
                            .background(item.id == currentItem?.id ? Color.orange.opacity(0.2) : Color.clear)
                        }
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

private func makeMicboardItems(
    fromAudioPatchRows patches: [PatchRow],
    storedItems: [RunOfShowMicboardItem] = [],
    startingPosition: Int = 0
) -> [RunOfShowMicboardItem] {
    let storedItemsByID = Dictionary(uniqueKeysWithValues: storedItems.map { ($0.id, $0) })
    return patches
        .filter { $0.category == "Audio" && $0.micboardEnabled }
        .sorted(by: PatchRow.autoSort)
        .enumerated()
        .map { offset, patch in
            let id = "patchsheet-\(patch.id)"
            let storedItem = storedItemsByID[id]
            return RunOfShowMicboardItem(
                id: id,
                name: patch.name,
                role: patch.notes,
                microphone: patch.micboardMicrophone,
                inEarMonitor: patch.micboardInEarMonitor,
                imageURLString: storedItem?.imageURLString ?? "",
                position: startingPosition + offset
            )
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

                    TextField("Notes", text: $patch.notes, axis: .vertical)
                        .lineLimit(2...6)
                        .disabled(!canEdit)

                    if patch.category == "Audio" {
                        TextField("Microphone", text: $patch.micboardMicrophone)
                            .disabled(!canEdit)
                        TextField("Monitor", text: $patch.micboardInEarMonitor)
                            .disabled(!canEdit)
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

private struct MacRunOfShowView: View {
    private enum ExportSubject: String, Identifiable {
        case runOfShow = "Run of Show"
        case stagePlot = "Stage Plot"

        var id: String { rawValue }
    }

    private enum ExportFormat: String, Identifiable {
        case pdf = "PDF"
        case jpeg = "JPEG"

        var id: String { rawValue }
        var fileExtension: String { self == .pdf ? "pdf" : "jpg" }
    }

    @EnvironmentObject private var store: ProdConnectStore
    @EnvironmentObject private var runOfShowControls: MacRunOfShowControlController
    @State private var selectedShowID: String?
    @State private var showToDelete: RunOfShowDocument?
    @State private var draggingShowID: String?
    @State private var draggingItemID: String?
    @State private var selectedStagePlotItemID: String?
    @State private var editingStagePlotItemID: String?
    @State private var stagePlotDragPoints: [String: CGPoint] = [:]
    @State private var stagePlotRotationDrafts: [String: Double] = [:]
    @State private var activeStagePlotRotationItemID: String?
    @State private var exportErrorMessage: String?
    @State private var pendingExportSubject: ExportSubject?
    @State private var pendingExportData: Data?
    @State private var pendingExportFilename: String?
    @State private var pendingExportContentType: UTType?
    @State private var isShowingExportSheet = false
    @State private var uploadingMicboardItemIDs: Set<String> = []
    @State private var micboardUploadProgressByItemID: [String: Double] = [:]
    @State private var micboardUploadError: String?

    private var canEdit: Bool {
        store.canEditRunOfShow
    }

    private var hasMicboardFeature: Bool {
        store.user?.normalizedSubscriptionTier != "free"
    }

    private var shows: [RunOfShowDocument] {
        RunOfShowDocument.sortedShows(store.runOfShows)
    }

    private var selectedShow: RunOfShowDocument? {
        guard let selectedShowID else { return shows.first }
        return shows.first(where: { $0.id == selectedShowID }) ?? shows.first
    }

    private func patchsheetMicboardItems(for show: RunOfShowDocument) -> [RunOfShowMicboardItem] {
        makeMicboardItems(fromAudioPatchRows: store.patchsheet, storedItems: show.micboardItems)
    }

    private func manualMicboardItems(for show: RunOfShowDocument) -> [RunOfShowMicboardItem] {
        show.sortedMicboardItems.filter { !$0.id.hasPrefix("patchsheet-") }
    }

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width < 980

            Group {
                if isCompact {
                    VStack(spacing: 16) {
                        sidebar
                            .frame(maxWidth: .infinity, minHeight: 170, maxHeight: 190, alignment: .topLeading)
                        runOfShowDetail
                    }
                } else {
                    HStack(spacing: 20) {
                        sidebar
                            .frame(width: min(280, max(230, proxy.size.width * 0.26)), alignment: .topLeading)
                        runOfShowDetail
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .overlay {
            if isShowingExportSheet {
                exportOverlay
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
        .onAppear {
            if selectedShowID == nil {
                selectedShowID = shows.first?.id
            }
            syncSelectedStagePlotItem()
            syncStagePlotDragPoints()
        }
        .onChange(of: shows.map(\.id)) { _, ids in
            if let selectedShowID, ids.contains(selectedShowID) {
                syncSelectedStagePlotItem()
                syncStagePlotDragPoints()
                return
            }
            self.selectedShowID = ids.first
            syncSelectedStagePlotItem()
            syncStagePlotDragPoints()
        }
        .onChange(of: isShowingExportSheet) { oldValue, newValue in
            if oldValue && !newValue {
                presentPendingSavePanelIfNeeded()
            }
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
        .alert("Export Failed", isPresented: Binding(
            get: { exportErrorMessage != nil },
            set: { if !$0 { exportErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportErrorMessage ?? "Unable to export this file.")
        }
        .sheet(isPresented: Binding(
            get: { editingStagePlotItemID != nil },
            set: { if !$0 { editingStagePlotItemID = nil } }
        )) {
            if let show = selectedShow,
               let itemID = editingStagePlotItemID,
               let item = show.sortedStagePlotItems.first(where: { $0.id == itemID }) {
                stagePlotEditorSheet(show: show, item: item)
            }
        }
    }

    @ViewBuilder
    private var runOfShowDetail: some View {
        if let show = selectedShow {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    showHeader(show)
                    timelineGrid(for: show)
                    stagePlotPanel(for: show)
                    micboardPanel(for: show)
                    livePanel(for: show)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Run of Show")
        } else {
            ContentUnavailableView(
                "No Shows/Events",
                systemImage: "list.bullet.rectangle.portrait",
                description: Text("Create a show to build your timeline and live view.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Shows/Events")
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
                        .draggable(show.id) {
                            Text(show.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Show" : show.title)
                                .padding(8)
                        }
                        .dropDestination(for: String.self) { ids, _ in
                            guard canEdit, let draggedID = ids.first else { return false }
                            moveShow(fromID: draggedID, toID: show.id)
                            return true
                        } isTargeted: { targeted in
                            if targeted {
                                draggingShowID = show.id
                            } else if draggingShowID == show.id {
                                draggingShowID = nil
                            }
                        }
                        .opacity(draggingShowID == show.id ? 0.72 : 1)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(16)
        .background(Color.black.opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                Button("Export") {
                    pendingExportSubject = nil
                    isShowingExportSheet = true
                }
                .buttonStyle(.bordered)

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
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    timelineHeaderCell("Time", width: 110)
                    timelineHeaderCell("Length", width: 90)
                    timelineHeaderCell("Actual", width: 90)
                    timelineHeaderCell("Title", width: 260)
                    timelineHeaderCell("Person", width: 180)
                    timelineHeaderCell("Notes", width: 230)
                    timelineHeaderCell("", width: 110)
                }
                .background(Color.white.opacity(0.05))

                ForEach(Array(show.sortedItems.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 0) {
                        timelineValueCell(startTimeText(for: show, itemIndex: index), width: 110)
                        timelineLengthCell(show: show, item: item)
                        timelineActualRuntimeCell(show: show, item: item)
                        timelineEditableCell(title: "Title", text: item.title, width: 260) { newValue in
                            updateItem(show, itemID: item.id) { $0.title = newValue }
                        }
                        timelineEditableCell(title: "Person", text: item.person, width: 180) { newValue in
                            updateItem(show, itemID: item.id) { $0.person = newValue }
                        }
                        timelineEditableCell(title: "Notes", text: item.notes, width: 230) { newValue in
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
                    .draggable(item.id) {
                        Text(item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Item" : item.title)
                            .padding(8)
                    }
                    .dropDestination(for: String.self) { ids, _ in
                        guard canEdit, let draggedID = ids.first else { return false }
                        moveItem(show, fromID: draggedID, toID: item.id)
                        return true
                    } isTargeted: { targeted in
                        if targeted {
                            draggingItemID = item.id
                        } else if draggingItemID == item.id {
                            draggingItemID = nil
                        }
                    }
                    .opacity(draggingItemID == item.id ? 0.72 : 1)
                }
            }
            .frame(minWidth: 1070, alignment: .leading)
        }
        .background(Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func stagePlotPanel(for show: RunOfShowDocument) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            stagePlotHeader(show)
            stagePlotCanvas(show)

            if show.sortedStagePlotItems.isEmpty {
                ContentUnavailableView(
                    "No Stage Plot Items",
                    systemImage: "music.note.house",
                    description: Text("Add instruments or vocals to build a stage layout for this show.")
                )
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(show.sortedStagePlotItems) { item in
                        stagePlotEditorCard(show: show, item: item)
                    }
                }
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func micboardPanel(for show: RunOfShowDocument) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Micboard")
                        .font(.title2.weight(.semibold))
                    Text("\(show.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Show" : show.title) • \(show.scheduledStart.formatted(date: .abbreviated, time: .omitted))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    addMicboardItem(to: show)
                } label: {
                    Label("Add Performer", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canEdit || !hasMicboardFeature)
            }

            if !hasMicboardFeature {
                ContentUnavailableView(
                    "Micboard Requires a Paid Subscription",
                    systemImage: "music.mic",
                    description: Text("Upgrade the team subscription to build microphone and in-ear monitor assignments.")
                )
            } else if patchsheetMicboardItems(for: show).isEmpty && manualMicboardItems(for: show).isEmpty {
                ContentUnavailableView(
                    "No Micboard Assignments",
                    systemImage: "music.mic",
                    description: Text("Check Micboard on audio patchsheet rows, or add performers here.")
                )
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(patchsheetMicboardItems(for: show)) { item in
                            micboardPatchsheetCard(show: show, item: item)
                                .frame(width: 245)
                        }
                        ForEach(manualMicboardItems(for: show)) { item in
                            micboardEditorCard(show: show, item: item)
                                .frame(width: 245)
                                .draggable(item.id) {
                                    Text(item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Micboard Assignment" : item.name)
                                        .padding(8)
                                }
                                .dropDestination(for: String.self) { ids, _ in
                                    guard canEdit, let draggedID = ids.first else { return false }
                                    moveMicboardItem(show, fromID: draggedID, toID: item.id)
                                    return true
                                }
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func micboardPatchsheetCard(show: RunOfShowDocument, item: RunOfShowMicboardItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            micboardPhotoPreview(item)
                .frame(height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            micboardReadOnlyField("Name", value: item.name)
            micboardReadOnlyField("Notes", value: item.role)
            if !item.microphone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                micboardReadOnlyField("Microphone", value: item.microphone)
            }
            if !item.inEarMonitor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                micboardReadOnlyField("In-Ear Monitor", value: item.inEarMonitor)
            }

            Label("Linked from audio patchsheet", systemImage: "link")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if uploadingMicboardItemIDs.contains(item.id) {
                ProgressView(value: micboardUploadProgressByItemID[item.id] ?? 0)
                    .progressViewStyle(.linear)
            }

            if let micboardUploadError, !micboardUploadError.isEmpty {
                Text(micboardUploadError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            Button("Upload Image") {
                pickMicboardImage(for: show, itemID: item.id)
            }
            .buttonStyle(.bordered)
            .disabled(!canEdit || uploadingMicboardItemIDs.contains(item.id))
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
        )
    }

    private func micboardEditorCard(show: RunOfShowDocument, item: RunOfShowMicboardItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            micboardPhotoPreview(item)
            .frame(height: 104)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            micboardTextField("Name", value: item.name) { value in
                updateMicboardItem(show, itemID: item.id) { $0.name = value }
            }
            micboardTextField("Role", value: item.role) { value in
                updateMicboardItem(show, itemID: item.id) { $0.role = value }
            }
            micboardTextField("Microphone", value: item.microphone) { value in
                updateMicboardItem(show, itemID: item.id) { $0.microphone = value }
            }
            micboardTextField("In-Ear Monitor", value: item.inEarMonitor) { value in
                updateMicboardItem(show, itemID: item.id) { $0.inEarMonitor = value }
            }
            micboardTextField("Photo URL", value: item.imageURLString) { value in
                updateMicboardItem(show, itemID: item.id) { $0.imageURLString = value }
            }

            if uploadingMicboardItemIDs.contains(item.id) {
                ProgressView(value: micboardUploadProgressByItemID[item.id] ?? 0)
                    .progressViewStyle(.linear)
            }

            if let micboardUploadError, !micboardUploadError.isEmpty {
                Text(micboardUploadError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            HStack {
                Button("Upload Image") {
                    pickMicboardImage(for: show, itemID: item.id)
                }
                .buttonStyle(.bordered)
                .disabled(!canEdit || uploadingMicboardItemIDs.contains(item.id))

                Button("Delete", role: .destructive) {
                    deleteMicboardItem(show, itemID: item.id)
                }
                .buttonStyle(.bordered)
                .disabled(!canEdit)
                Spacer()
                Text("#\(item.position + 1)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private func micboardReadOnlyField(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "-" : value)
                .font(.body)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    private func micboardPhotoPreview(_ item: RunOfShowMicboardItem) -> some View {
        ZStack {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.26), Color.white.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if let url = URL(string: item.imageURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
               !item.imageURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Text(micboardInitials(for: item.name))
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(.white.opacity(0.82))
                    default:
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            } else {
                Text(micboardInitials(for: item.name))
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white.opacity(0.82))
            }
        }
        .clipped()
    }

    private func micboardTextField(_ title: String, value: String, onChange: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            TextField(title, text: Binding(get: { value }, set: onChange))
                .textFieldStyle(.roundedBorder)
                .disabled(!canEdit)
        }
    }

    private func micboardInitials(for name: String) -> String {
        let result = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        return result.isEmpty ? "?" : result.uppercased()
    }

    private func stagePlotHeader(_ show: RunOfShowDocument) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Stage Plot")
                        .font(.title2.weight(.semibold))
                    Text("Drag each label into place on the stage.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if canEdit {
                    Menu("Add Item") {
                        stagePlotAddButtons(show: show)
                    }
                    .menuStyle(.borderlessButton)
                    .buttonStyle(.borderedProminent)
                }
            }

            Picker(
                "Stage Type",
                selection: Binding(
                    get: { show.stageType },
                    set: { newValue in
                        updateShow(show) { $0.stageType = newValue }
                    }
                )
            ) {
                ForEach(RunOfShowStageType.allCases) { stageType in
                    Text(stageType.rawValue).tag(stageType)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!canEdit)
        }
    }

    private func stagePlotCanvas(_ show: RunOfShowDocument) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                stagePlotStageSurface(type: show.stageType)

                VStack {
                    Text("UPSTAGE")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.7))
                    Spacer()
                    HStack {
                        Text("STAGE RIGHT")
                        Spacer()
                        Text("STAGE LEFT")
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.55))
                    Text("DOWNSTAGE")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.7))
                }
                .padding(16)

                ForEach(show.sortedStagePlotItems) { item in
                    stagePlotCanvasItem(item, canvasSize: size)
                }
            }
        }
        .frame(height: 360)
    }

    private func stagePlotCanvasItem(_ item: RunOfShowStagePlotItem, canvasSize: CGSize) -> some View {
        let isSelected = item.id == selectedStagePlotItemID
        let displayPosition = stagePlotDisplayPosition(for: item)
        let displayRotation = stagePlotDisplayRotation(for: item)

        return stagePlotCanvasNode(item, isSelected: isSelected)
        .overlay {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(item.role.usesSymbolArtwork ? Color.clear : Color.white.opacity(isSelected ? 0.95 : 0.28), lineWidth: isSelected ? 2 : 1)
                if canEdit, let show = selectedShow, isSelected {
                    stagePlotRotationHotZone(item: item, show: show)
                }
            }
        }
        .scaleEffect(item.sizeScale)
        .rotationEffect(.degrees(displayRotation))
        .shadow(color: Color.black.opacity(0.28), radius: 10, y: 6)
        .position(stagePlotPoint(x: displayPosition.x, y: displayPosition.y, canvasSize: canvasSize))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard canEdit else { return }
                    selectedStagePlotItemID = item.id
                    stagePlotDragPoints[item.id] = normalizedStagePlotPoint(for: value.location, canvasSize: canvasSize)
                }
                .onEnded { value in
                    guard canEdit, let show = selectedShow else { return }
                    let point = normalizedStagePlotPoint(for: value.location, canvasSize: canvasSize)
                    stagePlotDragPoints[item.id] = point
                    updateStagePlotItem(show, itemID: item.id) {
                        $0.x = point.x
                        $0.y = point.y
                    }
                    stagePlotDragPoints[item.id] = nil
                }
        )
        .onTapGesture { selectedStagePlotItemID = item.id }
        .contextMenu {
            if let show = selectedShow, canEdit {
                Button("Rename / Edit") {
                    openStagePlotEditor(item.id)
                }
                Button(role: .destructive) {
                    deleteStagePlotItem(show, itemID: item.id)
                } label: {
                    Text("Delete")
                }
            }
        }
    }

    private func stagePlotEditorCard(show: RunOfShowDocument, item: RunOfShowStagePlotItem) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(stagePlotColor(for: item.role).opacity(0.22))
                .frame(width: 8)

            VStack(alignment: .leading, spacing: 6) {
                Text(stagePlotItemTitle(item))
                    .font(.headline)
                    .foregroundStyle(item.id == selectedStagePlotItemID ? Color.accentColor : Color.primary)
                Text(item.subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? item.role.rawValue : item.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("X \(Int((item.x * 100).rounded()))  •  Y \(Int((item.y * 100).rounded()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            if canEdit {
                Button("Edit") {
                    openStagePlotEditor(item.id)
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    deleteStagePlotItem(show, itemID: item.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(item.id == selectedStagePlotItemID ? Color.accentColor.opacity(0.08) : Color.white.opacity(0.04))
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            selectedStagePlotItemID = item.id
        }
        .contextMenu {
            if canEdit {
                Button("Rename / Edit") {
                    openStagePlotEditor(item.id)
                }
                Button(role: .destructive) {
                    deleteStagePlotItem(show, itemID: item.id)
                } label: {
                    Text("Delete")
                }
            }
        }
    }

    private func stagePlotEditorSheet(show: RunOfShowDocument, item: RunOfShowStagePlotItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Stage Item")
                .font(.title3.weight(.semibold))

            Picker(
                "Type",
                selection: Binding(
                    get: { item.role },
                    set: { newValue in
                        updateStagePlotItem(show, itemID: item.id) { $0.role = newValue }
                    }
                )
            ) {
                ForEach(RunOfShowStagePlotRole.allCases) { role in
                    Text(role.rawValue).tag(role)
                }
            }

            TextField(
                item.role.usesSymbolArtwork ? "Label" : (item.role == .instrument ? "Instrument Name" : "Vocal Name"),
                text: Binding(
                    get: { item.title },
                    set: { newValue in
                        updateStagePlotItem(show, itemID: item.id) { $0.title = newValue }
                    }
                )
            )
            .textFieldStyle(.roundedBorder)

            TextField(
                item.role == .vocal ? "Mic / Notes" : "Player / Notes",
                text: Binding(
                    get: { item.subtitle },
                    set: { newValue in
                        updateStagePlotItem(show, itemID: item.id) { $0.subtitle = newValue }
                    }
                )
            )
            .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Size")
                    Spacer()
                    Text("\(Int((item.sizeScale * 100).rounded()))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Slider(
                    value: Binding(
                        get: { item.sizeScale },
                        set: { newValue in
                            updateStagePlotItem(show, itemID: item.id) { $0.sizeScale = newValue }
                        }
                    ),
                    in: 0.6...1.8
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Rotation")
                    Spacer()
                    Text("\(Int(item.rotationDegrees.rounded()))°")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                HStack {
                    Button("-15°") {
                        updateStagePlotItem(show, itemID: item.id) { $0.rotationDegrees -= 15 }
                    }
                    Button("Reset") {
                        updateStagePlotItem(show, itemID: item.id) { $0.rotationDegrees = 0 }
                    }
                    Button("+15°") {
                        updateStagePlotItem(show, itemID: item.id) { $0.rotationDegrees += 15 }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Done") {
                    editingStagePlotItemID = nil
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    @ViewBuilder
    private func stagePlotStageSurface(type: RunOfShowStageType) -> some View {
        ZStack {
            switch type {
            case .rectangle:
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.14, green: 0.14, blue: 0.17),
                                Color(red: 0.08, green: 0.08, blue: 0.11)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    .padding(10)
            case .archedFront:
                MacStagePlotArchedFrontShape(curveDepth: 0.18, cornerRadius: 18)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.14, green: 0.14, blue: 0.17),
                            Color(red: 0.08, green: 0.08, blue: 0.11)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                MacStagePlotArchedFrontShape(curveDepth: 0.18, cornerRadius: 18)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                .padding(10)
            case .round:
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.14, green: 0.14, blue: 0.17),
                                Color(red: 0.08, green: 0.08, blue: 0.11)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    .padding(10)
            }
        }
    }

    private func stagePlotPoint(for item: RunOfShowStagePlotItem, canvasSize: CGSize) -> CGPoint {
        stagePlotPoint(x: item.x, y: item.y, canvasSize: canvasSize)
    }

    private func stagePlotPoint(x: Double, y: Double, canvasSize: CGSize) -> CGPoint {
        CGPoint(
            x: 36 + x * max(canvasSize.width - 72, 1),
            y: 42 + y * max(canvasSize.height - 84, 1)
        )
    }

    private func normalizedStagePlotPoint(for location: CGPoint, canvasSize: CGSize) -> CGPoint {
        let x = min(max((location.x - 36) / max(canvasSize.width - 72, 1), 0), 1)
        let y = min(max((location.y - 42) / max(canvasSize.height - 84, 1), 0), 1)
        return CGPoint(x: x, y: y)
    }

    private func stagePlotItemTitle(_ item: RunOfShowStagePlotItem) -> String {
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? item.role.defaultTitle : title
    }

    private func openStagePlotEditor(_ itemID: String) {
        selectedStagePlotItemID = itemID
        editingStagePlotItemID = itemID
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

                Button("Complete") {
                    completeLive(show)
                }
                .buttonStyle(.borderedProminent)
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

            TimelineView(.periodic(from: .now, by: 1)) { context in
                eventTrackingView(show: show, now: context.date)
            }
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

    private func eventTrackingView(show: RunOfShowDocument, now: Date) -> some View {
        let records = show.liveEventTrackingRecords.sorted {
            if $0.position != $1.position { return $0.position < $1.position }
            return $0.startedAt < $1.startedAt
        }
        let activeItem = show.isLiveActive ? show.liveCurrentItemID.flatMap { id in show.sortedItems.first(where: { $0.id == id }) } : nil
        let activeActualSeconds = activeItem.map { show.actualRuntimeSeconds(for: $0.id, at: now) ?? 0 }
        let activeItemID = activeItem?.id
        let completedActualTotal = records
            .filter { $0.itemID != activeItemID }
            .reduce(0) { $0 + $1.actualSeconds }
        let actualTotal = completedActualTotal + (activeActualSeconds ?? 0)
        let overage = actualTotal - show.totalDurationSeconds

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Event Tracking")
                        .font(.headline)
                    Text(show.liveTrackingCompletedAt.map { "Completed \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Live run metrics")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label(show.liveTrackingCompletedAt == nil ? "Tracking" : "Complete", systemImage: show.liveTrackingCompletedAt == nil ? "record.circle" : "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(show.liveTrackingCompletedAt == nil ? .orange : .green)
            }

            HStack(spacing: 10) {
                trackingSummaryCard(title: "Planned", value: formatDurationLabel(seconds: show.totalDurationSeconds), accent: .secondary)
                trackingSummaryCard(title: "Actual", value: formatDurationLabel(seconds: actualTotal), accent: .primary)
                trackingSummaryCard(title: "Overage", value: signedDurationLabel(seconds: overage), accent: overage > 0 ? .orange : .green)
                trackingSummaryCard(title: "Items", value: "\(records.count) / \(show.sortedItems.count)", accent: .primary)
            }

            VStack(spacing: 0) {
                trackingHeaderRow
                ForEach(records.filter { $0.itemID != activeItemID }) { record in
                    trackingRecordRow(record)
                }
                if let activeItem, let activeActualSeconds {
                    trackingActiveRow(item: activeItem, actualSeconds: activeActualSeconds)
                }
                if records.isEmpty && activeItem == nil {
                    Text("Start Run of Show Live to capture item timing and SPL metrics.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
            }
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )

            if !show.liveTrackingSessions.isEmpty {
                savedTrackingSessionsView(show.liveTrackingSessions)
            }
        }
    }

    private func savedTrackingSessionsView(_ sessions: [RunOfShowTrackingSession]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Saved Sessions")
                .font(.subheadline.weight(.semibold))
            ForEach(sessions.prefix(6)) { session in
                DisclosureGroup {
                    VStack(spacing: 0) {
                        trackingHeaderRow
                        ForEach(session.records) { record in
                            trackingRecordRow(record)
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    HStack(spacing: 12) {
                        Text(session.completedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption.weight(.semibold))
                            .frame(width: 135, alignment: .leading)
                        Text("Actual \(formatDurationLabel(seconds: session.actualSeconds))")
                            .font(.caption)
                        Text("Overage \(signedDurationLabel(seconds: session.actualSeconds - session.plannedSeconds))")
                            .font(.caption)
                            .foregroundStyle(session.actualSeconds > session.plannedSeconds ? .orange : .green)
                        Text("\(session.records.count) items")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                .padding(10)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private func trackingSummaryCard(title: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var trackingHeaderRow: some View {
        HStack(spacing: 10) {
            trackingItemHeaderCell("Item")
            trackingCell("Planned", width: 70, weight: .bold, color: .secondary)
            trackingCell("Actual", width: 70, weight: .bold, color: .secondary)
            trackingCell("+/-", width: 58, weight: .bold, color: .secondary)
            trackingCell("SPL Peak", width: 76, weight: .bold, color: .secondary)
            trackingCell("SPL Avg", width: 70, weight: .bold, color: .secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04))
    }

    private func trackingItemHeaderCell(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func trackingRecordRow(_ record: RunOfShowEventTrackingRecord) -> some View {
        let delta = record.actualSeconds - record.plannedSeconds
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if !record.subtitle.isEmpty {
                    Text(record.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trackingCell(formatDurationLabel(seconds: record.plannedSeconds), width: 70)
            trackingCell(formatDurationLabel(seconds: record.actualSeconds), width: 70)
            trackingCell(signedDurationLabel(seconds: delta), width: 58, color: delta > 0 ? .orange : (delta < 0 ? .green : .secondary))
            trackingCell(splValue(record.splPeakDB), width: 76, color: record.splPeakDB == nil ? .secondary : .orange)
            trackingCell(splValue(record.splAverageDB), width: 70, color: record.splAverageDB == nil ? .secondary : .green)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
        }
    }

    private func trackingActiveRow(item: RunOfShowItem, actualSeconds: Int) -> some View {
        let delta = actualSeconds - item.durationSeconds
        return HStack(spacing: 10) {
            Text(item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : item.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            trackingCell(formatDurationLabel(seconds: item.durationSeconds), width: 70)
            trackingCell(formatDurationLabel(seconds: actualSeconds), width: 70, color: .orange)
            trackingCell(signedDurationLabel(seconds: delta), width: 58, color: delta > 0 ? .orange : .green)
            trackingCell("-", width: 76, color: .secondary)
            trackingCell("-", width: 70, color: .secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func trackingCell(_ text: String, width: CGFloat?, weight: Font.Weight = .regular, color: Color = .primary) -> some View {
        Text(text)
            .font(.system(size: 12, weight: weight, design: .rounded))
            .foregroundStyle(color)
            .lineLimit(1)
            .frame(width: width, alignment: .leading)
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
        MacRunOfShowInlineTextField(
            title: title,
            text: text,
            width: width,
            isEditable: canEdit,
            setter: setter
        )
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

    private func timelineActualRuntimeCell(show: RunOfShowDocument, item: RunOfShowItem) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let actualSeconds = show.actualRuntimeSeconds(for: item.id, at: now)
            let isCurrent = show.isLiveActive && show.liveCurrentItemID == item.id
            let isOverrun = (actualSeconds ?? 0) > item.durationSeconds

            Text(actualSeconds.map { formatDuration(seconds: $0) } ?? "—")
                .font(.system(size: 12, weight: isCurrent ? .semibold : .regular, design: .monospaced))
                .foregroundStyle(
                    actualSeconds == nil
                        ? Color.secondary
                        : (isOverrun ? Color.red : (isCurrent ? Color.orange : Color.primary))
                )
                .frame(width: 90, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
        }
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
            title: "New Show",
            teamCode: store.teamCode ?? "",
            scheduledStart: Date(),
            items: [
                RunOfShowItem(title: "Welcome", lengthMinutes: 5, lengthSeconds: 0, position: 0),
                RunOfShowItem(title: "Song 1", lengthMinutes: 5, lengthSeconds: 0, position: 1)
            ],
            position: shows.count
        )
        store.saveRunOfShow(show)
        selectedShowID = show.id
    }

    private func performExport(subject: ExportSubject, format: ExportFormat, show: RunOfShowDocument) {
        let export: (Data?, String) = {
            switch (subject, format) {
            case (.runOfShow, .pdf):
                return (makeRunOfShowPDFData(show), exportFilename(prefix: "RunOfShow", showTitle: show.title, fileExtension: format.fileExtension))
            case (.runOfShow, .jpeg):
                return (makeRunOfShowJPEGData(show), exportFilename(prefix: "RunOfShow", showTitle: show.title, fileExtension: format.fileExtension))
            case (.stagePlot, .pdf):
                return (makeStagePlotPDFData(show), exportFilename(prefix: "StagePlot", showTitle: show.title, fileExtension: format.fileExtension))
            case (.stagePlot, .jpeg):
                return (makeStagePlotJPEGData(show), exportFilename(prefix: "StagePlot", showTitle: show.title, fileExtension: format.fileExtension))
            }
        }()

        guard let data = export.0 else {
            exportErrorMessage = "Unable to render \(subject.rawValue) \(format.rawValue)."
            return
        }

        pendingExportData = data
        pendingExportFilename = export.1
        pendingExportContentType = format == .pdf ? .pdf : .jpeg
        isShowingExportSheet = false
    }

    private func presentPendingSavePanelIfNeeded(attempt: Int = 0) {
        guard let data = pendingExportData,
              let filename = pendingExportFilename,
              let contentType = pendingExportContentType else { return }

        let activeWindow = NSApp.keyWindow ?? NSApp.mainWindow
        if let activeWindow, activeWindow.attachedSheet != nil, attempt < 12 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                presentPendingSavePanelIfNeeded(attempt: attempt + 1)
            }
            return
        }

        pendingExportData = nil
        pendingExportFilename = nil
        pendingExportContentType = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            presentExportFolderPicker(data: data, filename: filename, contentType: contentType)
        }
    }

    @MainActor
    private func presentExportFolderPicker(data: Data, filename: String, contentType: UTType) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                presentExportFolderPicker(data: data, filename: filename, contentType: contentType)
            }
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Choose Export Folder"
        panel.message = "Choose where to save \(filename)"
        panel.prompt = "Choose Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let directoryURL = panel.url else { return }
            let destinationURL = directoryURL.appendingPathComponent(filename)
            let didAccessDirectory = directoryURL.startAccessingSecurityScopedResource()
            let didAccessDestination = destinationURL.startAccessingSecurityScopedResource()
            defer {
                if didAccessDestination {
                    destinationURL.stopAccessingSecurityScopedResource()
                }
                if didAccessDirectory {
                    directoryURL.stopAccessingSecurityScopedResource()
                }
            }

            var coordinationError: NSError?
            let coordinator = NSFileCoordinator()
            coordinator.coordinate(writingItemAt: destinationURL, options: .forReplacing, error: &coordinationError) { coordinatedURL in
                do {
                    try data.write(to: coordinatedURL, options: .atomic)
                } catch {
                    exportErrorMessage = error.localizedDescription
                }
            }

            if let coordinationError {
                exportErrorMessage = coordinationError.localizedDescription
            }
        }

        if let hostWindow = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: hostWindow, completionHandler: handleResponse)
            return
        }

        handleResponse(panel.runModal())
    }

    private var exportOverlay: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture {
                    cancelExportFlow()
                }

            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Export")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Button("Cancel") {
                        cancelExportFlow()
                    }
                    .buttonStyle(.bordered)
                }

                Text("Choose what to export and the file format.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Content")
                        .font(.headline)
                    HStack(spacing: 10) {
                        Button("Run of Show") {
                            pendingExportSubject = .runOfShow
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(pendingExportSubject == .runOfShow ? .accentColor : .gray)

                        Button("Stage Plot") {
                            pendingExportSubject = .stagePlot
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(pendingExportSubject == .stagePlot ? .accentColor : .gray)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Format")
                        .font(.headline)
                    HStack(spacing: 10) {
                        Button("PDF") {
                            guard let show = selectedShow, let subject = pendingExportSubject else { return }
                            performExport(subject: subject, format: .pdf, show: show)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(pendingExportSubject == nil)

                        Button("JPEG") {
                            guard let show = selectedShow, let subject = pendingExportSubject else { return }
                            performExport(subject: subject, format: .jpeg, show: show)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(pendingExportSubject == nil)
                    }
                }
            }
            .padding(24)
            .frame(width: 420)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.28), radius: 22, y: 12)
        }
    }

    private func cancelExportFlow() {
        pendingExportSubject = nil
        pendingExportData = nil
        pendingExportFilename = nil
        pendingExportContentType = nil
        isShowingExportSheet = false
    }

    private func exportFilename(prefix: String, showTitle: String, fileExtension: String) -> String {
        let trimmed = showTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "UntitledShow" : trimmed
        let sanitized = base.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return "\(prefix)-\(sanitized).\(fileExtension)"
    }

    private func makeRunOfShowPDFData(_ show: RunOfShowDocument) -> Data? {
        let width: CGFloat = 1000
        let height = runOfShowExportHeight(for: show, rowHeight: 54, minimumHeight: 560)
        let size = CGSize(width: width, height: height)
        let content = runOfShowExportView(show)
            .frame(width: width, height: height)

        guard let image = MacNDIRenderer.snapshot(of: content, size: size) else { return nil }
        return makePDFData(from: image, size: size)
    }

    private func makeRunOfShowJPEGData(_ show: RunOfShowDocument) -> Data? {
        let width: CGFloat = 1200
        let height = runOfShowExportHeight(for: show, rowHeight: 66, minimumHeight: 800)
        let size = CGSize(width: width, height: height)
        let content = runOfShowExportView(show)
            .frame(width: width, height: height)

        guard let image = MacNDIRenderer.snapshot(of: content, size: size) else { return nil }
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92])
    }

    private func makeStagePlotPDFData(_ show: RunOfShowDocument) -> Data? {
        let size = CGSize(width: 1100, height: 720)
        let content = stagePlotExportView(show)
            .frame(width: size.width, height: size.height)

        guard let image = MacNDIRenderer.snapshot(of: content, size: size) else { return nil }
        return makePDFData(from: image, size: size)
    }

    private func makeStagePlotJPEGData(_ show: RunOfShowDocument) -> Data? {
        let size = CGSize(width: 1600, height: 900)
        let content = stagePlotExportView(show)
            .frame(width: size.width, height: size.height)

        guard let image = MacNDIRenderer.snapshot(of: content, size: size) else { return nil }
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92])
    }

    private func makePDFData(from image: CGImage, size: CGSize) -> Data? {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
        var mediaBox = CGRect(origin: .zero, size: size)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }
        context.beginPDFPage(nil)
        context.draw(image, in: mediaBox)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    private func runOfShowExportView(_ show: RunOfShowDocument) -> some View {
        let items = show.sortedItems

        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text(show.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Run of Show" : show.title)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Color.black)
                Text("Scheduled Start: \(show.scheduledStart.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.65))
                Text("\(items.count) items • \(formatDuration(seconds: show.totalDurationSeconds)) total")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.65))
            }
            .padding(.leading, 64)
            .padding(.trailing, 14)
            .padding(.top, 30)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.95, green: 0.97, blue: 1.0))

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    exportHeaderCell("Time", width: 120)
                    exportHeaderCell("Length", width: 90)
                    exportHeaderCell("Title", width: 240)
                    exportHeaderCell("Person", width: 165)
                    exportHeaderCell("Notes", width: 285)
                }

                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HStack(alignment: .top, spacing: 0) {
                        exportValueCell(startTimeText(for: show, itemIndex: index), width: 120)
                        exportValueCell(item.formattedDuration, width: 90)
                        exportValueCell(item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : item.title, width: 240)
                        exportValueCell(item.person.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unassigned" : item.person, width: 165)
                        exportValueCell(item.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? " " : item.notes, width: 285)
                    }
                    .background(index.isMultiple(of: 2) ? Color.black.opacity(0.03) : Color.white)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.black.opacity(0.08))
                            .frame(height: 1)
                    }
                }
            }
            .padding(.leading, 64)
            .padding(.trailing, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white)
    }

    private func runOfShowExportHeight(for show: RunOfShowDocument, rowHeight: CGFloat, minimumHeight: CGFloat) -> CGFloat {
        let itemCount = CGFloat(max(show.sortedItems.count, 1))
        let headerHeight: CGFloat = 124
        let tableHeaderHeight: CGFloat = 42
        let bottomPadding: CGFloat = 24
        return max(minimumHeight, headerHeight + tableHeaderHeight + (itemCount * rowHeight) + bottomPadding)
    }

    private func stagePlotExportView(_ show: RunOfShowDocument) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(show.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Stage Plot" : show.title)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Stage Plot")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.68))
                }
                Spacer()
                Text(show.stageType.rawValue)
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                    .foregroundStyle(.white)
            }

            GeometryReader { proxy in
                let size = proxy.size

                ZStack {
                    stagePlotStageSurface(type: show.stageType)

                    VStack {
                        Text("UPSTAGE")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.76))
                        Spacer()
                        HStack {
                            Text("STAGE RIGHT")
                            Spacer()
                            Text("STAGE LEFT")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.58))
                        Text("DOWNSTAGE")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.76))
                    }
                    .padding(28)

                    ForEach(show.sortedStagePlotItems) { item in
                        stagePlotCanvasNode(item, isSelected: false)
                            .scaleEffect(item.sizeScale)
                            .rotationEffect(.degrees(item.rotationDegrees))
                            .position(stagePlotPoint(x: item.x, y: item.y, canvasSize: size))
                    }
                }
            }
        }
        .padding(28)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.1, blue: 0.13),
                    Color(red: 0.03, green: 0.04, blue: 0.06)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func exportHeaderCell(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .textCase(.uppercase)
            .foregroundStyle(Color.black.opacity(0.65))
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.05))
    }

    private func exportValueCell(_ value: String, width: CGFloat) -> some View {
        Text(value)
            .font(.system(size: 13))
            .foregroundStyle(Color.black.opacity(0.9))
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .lineLimit(3)
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

    private func moveShow(fromID: String, toID: String) {
        guard fromID != toID else { return }
        var ordered = shows
        guard let fromIndex = ordered.firstIndex(where: { $0.id == fromID }),
              let toIndex = ordered.firstIndex(where: { $0.id == toID }) else { return }
        let moved = ordered.remove(at: fromIndex)
        ordered.insert(moved, at: toIndex)
        for (position, show) in ordered.enumerated() {
            var updated = show
            updated.position = position
            store.saveRunOfShow(updated)
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

    private func moveItem(_ show: RunOfShowDocument, fromID: String, toID: String) {
        guard fromID != toID else { return }
        updateShow(show) { mutable in
            var items = mutable.sortedItems
            guard let fromIndex = items.firstIndex(where: { $0.id == fromID }),
                  let toIndex = items.firstIndex(where: { $0.id == toID }) else { return }
            let moved = items.remove(at: fromIndex)
            items.insert(moved, at: toIndex)
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
            mutable.startLiveSession(at: Date())
        }
    }

    private func moveLive(_ show: RunOfShowDocument, direction: Int) {
        let spl = SmaartAPIController.shared.trackingSnapshot(since: show.currentLiveTrackingStartedAt())
        updateShow(show) { mutable in
            mutable.moveLiveSession(direction: direction, at: Date(), splPeakDB: spl.peakDB, splAverageDB: spl.averageDB)
        }
    }

    private func completeLive(_ show: RunOfShowDocument) {
        let spl = SmaartAPIController.shared.trackingSnapshot(since: show.currentLiveTrackingStartedAt())
        runOfShowControls.suppressAutoStart(for: show.id)
        updateShow(show) { mutable in
            mutable.completeLiveSession(at: Date(), splPeakDB: spl.peakDB, splAverageDB: spl.averageDB)
        }
    }

    private func resetLive(_ show: RunOfShowDocument) {
        runOfShowControls.suppressAutoStart(for: show.id)
        updateShow(show) { mutable in
            mutable.resetLiveSession()
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

    private func syncSelectedStagePlotItem() {
        let ids = Set(selectedShow?.sortedStagePlotItems.map(\.id) ?? [])
        if let selectedStagePlotItemID, ids.contains(selectedStagePlotItemID) {
            return
        }
        selectedStagePlotItemID = selectedShow?.sortedStagePlotItems.first?.id
    }

    private func syncStagePlotDragPoints() {
        let validIDs = Set(selectedShow?.sortedStagePlotItems.map(\.id) ?? [])
        stagePlotDragPoints = stagePlotDragPoints.filter { validIDs.contains($0.key) }
        stagePlotRotationDrafts = stagePlotRotationDrafts.filter { validIDs.contains($0.key) }
        if let activeStagePlotRotationItemID, !validIDs.contains(activeStagePlotRotationItemID) {
            self.activeStagePlotRotationItemID = nil
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

    private func formatDurationLabel(seconds: Int) -> String {
        let clamped = max(seconds, 0)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private func signedDurationLabel(seconds: Int) -> String {
        if seconds == 0 { return "-" }
        let sign = seconds > 0 ? "+" : "-"
        return "\(sign)\(formatDurationLabel(seconds: abs(seconds)))"
    }

    private func splValue(_ value: Double?) -> String {
        guard let value else { return "-" }
        return String(format: "%.1f", value)
    }

    private func addMicboardItem(to show: RunOfShowDocument) {
        guard hasMicboardFeature else { return }
        updateShow(show) { mutable in
            let nextPosition = mutable.micboardItems.count
            mutable.micboardItems.append(
                RunOfShowMicboardItem(
                    name: "New Performer",
                    role: "Vocalist",
                    microphone: "",
                    inEarMonitor: "",
                    position: nextPosition
                )
            )
        }
    }

    private func pickMicboardImage(for show: RunOfShowDocument, itemID: String) {
        guard hasMicboardFeature, canEdit else { return }
        micboardUploadError = nil
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]

        let handleSelection: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            uploadingMicboardItemIDs.insert(itemID)
            micboardUploadProgressByItemID[itemID] = 0
            uploadMicboardImage(from: url, showID: show.id, itemID: itemID) { result in
                DispatchQueue.main.async {
                    uploadingMicboardItemIDs.remove(itemID)
                    micboardUploadProgressByItemID[itemID] = nil
                    switch result {
                    case .success(let urlString):
                        updateMicboardImageURL(show, itemID: itemID, urlString: urlString)
                    case .failure(let error):
                        micboardUploadError = "Image upload failed: \(error.localizedDescription)"
                    }
                }
            }
        }

        if let keyWindow = NSApp.keyWindow {
            panel.beginSheetModal(for: keyWindow, completionHandler: handleSelection)
        } else {
            handleSelection(panel.runModal())
        }
    }

    private func uploadMicboardImage(from localURL: URL, showID: String, itemID: String, completion: @escaping (Result<String, Error>) -> Void) {
        let safeName = localURL.lastPathComponent.replacingOccurrences(of: " ", with: "_")
        let path = "micboardImages/\(showID)/\(itemID)-\(UUID().uuidString)-\(safeName)"
        let storageRef = Storage.storage().reference().child(path)
        let metadata = StorageMetadata()
        metadata.contentType = micboardImageContentType(for: localURL)
        let didAccess = localURL.startAccessingSecurityScopedResource()

        let uploadTask = storageRef.putFile(from: localURL, metadata: metadata)
        uploadTask.observe(.progress) { snapshot in
            DispatchQueue.main.async {
                micboardUploadProgressByItemID[itemID] = snapshot.progress?.fractionCompleted ?? 0
            }
        }
        uploadTask.observe(.failure) { snapshot in
            if didAccess {
                localURL.stopAccessingSecurityScopedResource()
            }
            completion(.failure(snapshot.error ?? NSError(
                domain: "ProdConnectMicboardUpload",
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
                        domain: "ProdConnectMicboardUpload",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Upload finished, but no download URL was returned."]
                    )))
                }
            }
        }
    }

    private func micboardImageContentType(for url: URL) -> String {
        if let type = UTType(filenameExtension: url.pathExtension),
           let mimeType = type.preferredMIMEType {
            return mimeType
        }
        return "image/jpeg"
    }

    private func updateMicboardItem(_ show: RunOfShowDocument, itemID: String, change: (inout RunOfShowMicboardItem) -> Void) {
        guard hasMicboardFeature else { return }
        updateShow(show) { mutable in
            guard let index = mutable.micboardItems.firstIndex(where: { $0.id == itemID }) else { return }
            change(&mutable.micboardItems[index])
        }
    }

    private func updateMicboardImageURL(_ show: RunOfShowDocument, itemID: String, urlString: String) {
        guard hasMicboardFeature else { return }
        updateShow(show) { mutable in
            if let index = mutable.micboardItems.firstIndex(where: { $0.id == itemID }) {
                mutable.micboardItems[index].imageURLString = urlString
                return
            }

            mutable.micboardItems.append(
                RunOfShowMicboardItem(
                    id: itemID,
                    imageURLString: urlString,
                    position: mutable.micboardItems.count
                )
            )
        }
    }

    private func deleteMicboardItem(_ show: RunOfShowDocument, itemID: String) {
        guard hasMicboardFeature else { return }
        updateShow(show) { mutable in
            mutable.micboardItems.removeAll { $0.id == itemID }
            mutable.micboardItems = mutable.sortedMicboardItems.enumerated().map { offset, item in
                var updated = item
                updated.position = offset
                return updated
            }
        }
    }

    private func moveMicboardItem(_ show: RunOfShowDocument, fromID: String, toID: String) {
        guard hasMicboardFeature, fromID != toID else { return }
        updateShow(show) { mutable in
            var items = mutable.sortedMicboardItems
            guard let fromIndex = items.firstIndex(where: { $0.id == fromID }),
                  let toIndex = items.firstIndex(where: { $0.id == toID }) else { return }
            let moved = items.remove(at: fromIndex)
            items.insert(moved, at: toIndex)
            mutable.micboardItems = items.enumerated().map { offset, item in
                var updated = item
                updated.position = offset
                return updated
            }
        }
    }

    private func addStagePlotItem(to show: RunOfShowDocument, role: RunOfShowStagePlotRole) {
        updateShow(show) { mutable in
            let nextPosition = mutable.stagePlotItems.count
            let defaultPosition = role.defaultPosition
            let newItem = RunOfShowStagePlotItem(
                role: role,
                title: role.defaultTitle,
                subtitle: "",
                x: defaultPosition.x,
                y: defaultPosition.y,
                position: nextPosition
            )
            mutable.stagePlotItems.append(newItem)
            selectedStagePlotItemID = newItem.id
        }
    }

    private func updateStagePlotItem(_ show: RunOfShowDocument, itemID: String, change: (inout RunOfShowStagePlotItem) -> Void) {
        updateShow(show) { mutable in
            guard let index = mutable.stagePlotItems.firstIndex(where: { $0.id == itemID }) else { return }
            change(&mutable.stagePlotItems[index])
            mutable.stagePlotItems[index].x = min(max(mutable.stagePlotItems[index].x, 0), 1)
            mutable.stagePlotItems[index].y = min(max(mutable.stagePlotItems[index].y, 0), 1)
            mutable.stagePlotItems[index].rotationDegrees = min(max(mutable.stagePlotItems[index].rotationDegrees, -180), 180)
            mutable.stagePlotItems[index].sizeScale = min(max(mutable.stagePlotItems[index].sizeScale, 0.6), 1.8)
        }
    }

    private func deleteStagePlotItem(_ show: RunOfShowDocument, itemID: String) {
        updateShow(show) { mutable in
            mutable.stagePlotItems.removeAll { $0.id == itemID }
            mutable.stagePlotItems = mutable.stagePlotItems.enumerated().map { offset, item in
                var updated = item
                updated.position = offset
                return updated
            }
            if selectedStagePlotItemID == itemID {
                selectedStagePlotItemID = mutable.sortedStagePlotItems.first?.id
            }
        }
    }

    private func stagePlotColor(for role: RunOfShowStagePlotRole) -> Color {
        switch role {
        case .instrument:
            return Color(red: 0.25, green: 0.52, blue: 0.94)
        case .vocal:
            return Color(red: 0.88, green: 0.33, blue: 0.46)
        case .drumSet:
            return Color(red: 0.77, green: 0.41, blue: 0.18)
        case .guitar:
            return Color(red: 0.98, green: 0.66, blue: 0.19)
        case .bassGuitar:
            return Color(red: 0.28, green: 0.77, blue: 0.58)
        case .microphoneStand:
            return Color(red: 0.69, green: 0.37, blue: 0.93)
        case .keyboard:
            return Color(red: 0.36, green: 0.72, blue: 0.96)
        case .speaker:
            return Color(red: 0.54, green: 0.59, blue: 0.66)
        }
    }

    @ViewBuilder
    private func stagePlotAddButtons(show: RunOfShowDocument) -> some View {
        ForEach(RunOfShowStagePlotRole.allCases) { role in
            Button {
                addStagePlotItem(to: show, role: role)
            } label: {
                if let symbol = role.systemImageName {
                    Label(role.rawValue, systemImage: symbol)
                } else {
                    Text(role.rawValue)
                }
            }
        }
    }

    private func stagePlotDisplayPosition(for item: RunOfShowStagePlotItem) -> CGPoint {
        stagePlotDragPoints[item.id] ?? CGPoint(x: item.x, y: item.y)
    }

    private func stagePlotDisplayRotation(for item: RunOfShowStagePlotItem) -> Double {
        stagePlotRotationDrafts[item.id] ?? item.rotationDegrees
    }

    private func normalizedStagePlotRotation(_ degrees: Double) -> Double {
        let wrapped = degrees.truncatingRemainder(dividingBy: 360)
        if wrapped > 180 { return wrapped - 360 }
        if wrapped < -180 { return wrapped + 360 }
        return wrapped
    }

    private func stagePlotRotationAngle(for location: CGPoint, in size: CGSize) -> Double {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radians = atan2(location.y - center.y, location.x - center.x)
        return normalizedStagePlotRotation((radians * 180 / .pi) + 90)
    }

    private func commitStagePlotRotation(_ rotation: Double, show: RunOfShowDocument, itemID: String) {
        let normalized = normalizedStagePlotRotation(rotation)
        stagePlotRotationDrafts[itemID] = normalized
        updateStagePlotItem(show, itemID: itemID) { $0.rotationDegrees = normalized }
        stagePlotRotationDrafts[itemID] = nil
    }

    private func nudgeStagePlotRotation(show: RunOfShowDocument, itemID: String, by degrees: Double = 15) {
        guard let item = show.stagePlotItems.first(where: { $0.id == itemID }) else { return }
        commitStagePlotRotation(item.rotationDegrees + degrees, show: show, itemID: itemID)
    }

    private func stagePlotRotationHotZone(item: RunOfShowStagePlotItem, show: RunOfShowDocument) -> some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(StagePlotRotationCorner.allCases) { corner in
                    stagePlotRotationHandle(item: item, show: show, corner: corner, size: proxy.size)
                }
            }
        }
    }

    private func stagePlotRotationHandle(
        item: RunOfShowStagePlotItem,
        show: RunOfShowDocument,
        corner: StagePlotRotationCorner,
        size: CGSize
    ) -> some View {
        Circle()
            .fill(Color.clear)
            .frame(width: 34, height: 34)
            .overlay {
                Circle()
                    .fill(Color.white.opacity(activeStagePlotRotationItemID == item.id ? 1 : 0.94))
                    .frame(width: 22, height: 22)
                    .overlay(
                        Image(systemName: "rotate.right.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.72))
                            .rotationEffect(.degrees(corner.iconRotationDegrees))
                    )
                    .shadow(color: Color.black.opacity(0.22), radius: 4, y: 2)
            }
            .contentShape(Circle())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: corner.alignment)
            .offset(x: corner.offset.width, y: corner.offset.height)
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        activeStagePlotRotationItemID = item.id
                        stagePlotRotationDrafts[item.id] = stagePlotRotationAngle(for: value.location, in: size)
                    }
                    .onEnded { value in
                        defer { activeStagePlotRotationItemID = nil }
                        commitStagePlotRotation(
                            stagePlotRotationAngle(for: value.location, in: size),
                            show: show,
                            itemID: item.id
                        )
                    }
            )
            .simultaneousGesture(
                TapGesture()
                    .onEnded {
                        activeStagePlotRotationItemID = nil
                        nudgeStagePlotRotation(show: show, itemID: item.id)
                    }
            )
    }

    @ViewBuilder
    private func stagePlotCanvasNode(_ item: RunOfShowStagePlotItem, isSelected: Bool) -> some View {
        if item.role.usesSymbolArtwork {
            VStack(spacing: 6) {
                stagePlotCanvasArtwork(for: item.role, color: stagePlotColor(for: item.role))
                    .frame(width: 46, height: 40)
                Text(stagePlotItemTitle(item))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(isSelected ? 0.45 : 0.28))
                    .clipShape(Capsule())
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.1 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(isSelected ? 0.4 : 0.14), lineWidth: isSelected ? 2 : 1)
            )
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(stagePlotItemTitle(item))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if !item.subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(item.subtitle)
                        .font(.caption2)
                        .foregroundStyle(Color.white.opacity(0.72))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minWidth: 96, maxWidth: 160, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(stagePlotColor(for: item.role).opacity(isSelected ? 0.95 : 0.78))
            )
        }
    }

    @ViewBuilder
    private func stagePlotCanvasArtwork(for role: RunOfShowStagePlotRole, color: Color) -> some View {
        if let symbolName = role.systemImageName {
            ZStack {
                Circle()
                    .fill(color.opacity(0.22))
                    .frame(width: 38, height: 38)
                Image(systemName: symbolName)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white)
            }
        } else {
            EmptyView()
        }
    }

    private func overrunClock(seconds: Int) -> String {
        let minutes = max(seconds, 0) / 60
        let remainingSeconds = max(seconds, 0) % 60
        return String(format: "-%02d:%02d", minutes, remainingSeconds)
    }
}

private struct MacRunOfShowInlineTextField: View {
    let title: String
    let text: String
    let width: CGFloat
    let isEditable: Bool
    let setter: (String) -> Void

    @State private var draft: String
    @FocusState private var isFocused: Bool

    init(title: String, text: String, width: CGFloat, isEditable: Bool, setter: @escaping (String) -> Void) {
        self.title = title
        self.text = text
        self.width = width
        self.isEditable = isEditable
        self.setter = setter
        _draft = State(initialValue: text)
    }

    var body: some View {
        TextField(title, text: $draft)
            .focused($isFocused)
            .textFieldStyle(.plain)
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .disabled(!isEditable)
            .onChange(of: draft) { _, newValue in
                setter(newValue)
            }
            .onChange(of: text) { _, newValue in
                if !isFocused && draft != newValue {
                    draft = newValue
                }
            }
    }
}

private struct MacStagePlotArchedFrontShape: Shape {
    var curveDepth: CGFloat
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let depth = max(12, min(rect.height * curveDepth, rect.height * 0.35))
        let radius = min(cornerRadius, rect.width * 0.12, rect.height * 0.18)
        let top = rect.minY
        let left = rect.minX
        let right = rect.maxX
        let backBottom = rect.maxY - depth

        var path = Path()
        path.move(to: CGPoint(x: left + radius, y: top))
        path.addLine(to: CGPoint(x: right - radius, y: top))
        path.addQuadCurve(
            to: CGPoint(x: right, y: top + radius),
            control: CGPoint(x: right, y: top)
        )
        path.addLine(to: CGPoint(x: right, y: backBottom))
        path.addQuadCurve(
            to: CGPoint(x: left, y: backBottom),
            control: CGPoint(x: rect.midX, y: rect.maxY + depth * 1.05)
        )
        path.addLine(to: CGPoint(x: left, y: top + radius))
        path.addQuadCurve(
            to: CGPoint(x: left + radius, y: top),
            control: CGPoint(x: left, y: top)
        )
        path.closeSubpath()
        return path
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

private struct CSVExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    let data: Data

    init(text: String) {
        self.data = Data(text.utf8)
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
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
    @State private var room = ""
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
        Array(Set(store.gear.map { gearCampusLabel($0) })).filter { $0 != "—" && !$0.isEmpty }.sorted()
    }

    private var filteredGear: [GearItem] {
        var result = store.gear
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.category.localizedCaseInsensitiveContains(searchText) ||
                gearCampusLabel($0).localizedCaseInsensitiveContains(searchText)
            }
        }
        if let selectedCategory {
            result = result.filter { $0.category == selectedCategory }
        }
        if let selectedStatus {
            result = result.filter { $0.status == selectedStatus }
        }
        if let selectedLocation {
            result = result.filter { gearCampusLabel($0) == selectedLocation }
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
            gearHeaderButton("Location", column: .campus)
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
        let location = item.location.trimmingCharacters(in: .whitespacesAndNewlines)
        if !location.isEmpty {
            return location
        }
        let campus = item.campus.trimmingCharacters(in: .whitespacesAndNewlines)
        if !campus.isEmpty {
            return campus
        }
        let fallback = item.room.trimmingCharacters(in: .whitespacesAndNewlines)
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
        case .recycle:
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
        room = item.room
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
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                exportGear()
            }
            return
        }
        isExporting = true
        defer { isExporting = false }

        let header = [
            "Name",
            "Category",
            "Status",
            "Location",
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
                item.location,
                item.room,
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

        guard savePanel.runModal() == .OK, let url = savePanel.url else { return }

        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            mergeResultMessage = "Export failed: \(error.localizedDescription)"
            showMergeResult = true
        }
    }

    private func csvEscaped(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private func resetGearForm() {
        name = ""
        category = "Audio"
        status = .available
        location = ""
        room = ""
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
                                labeledTextField("Location", text: $location)
                            } else {
                                fieldHeader("Location")
                                Picker("Location", selection: $location) {
                                    Text("Select location").tag("")
                                    ForEach(store.locations.sorted(), id: \.self) { option in
                                        Text(option).tag(option)
                                    }
                                }
                            }
                            if store.rooms.isEmpty {
                                labeledTextField("Room", text: $room)
                            } else {
                                fieldHeader("Room")
                                Picker("Room", selection: $room) {
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
                            room: room.trimmingCharacters(in: .whitespacesAndNewlines),
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
                detailRow("Location", item.location)
                detailRow("Room", item.room)
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
    @State private var exportCategoryFilter = ""
    @State private var exportSubcategoryFilter = ""
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

    private var availableTicketReportCategories: [String] {
        let values = Set(store.visibleTickets.map { $0.category.trimmingCharacters(in: .whitespacesAndNewlines) }).filter { !$0.isEmpty }
        return values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var availableTicketReportSubcategories: [String] {
        let source = exportCategoryFilter.isEmpty
            ? store.visibleTickets
            : store.visibleTickets.filter { $0.category.trimmingCharacters(in: .whitespacesAndNewlines) == exportCategoryFilter }
        let values = Set(source.map { $0.subcategory.trimmingCharacters(in: .whitespacesAndNewlines) }).filter { !$0.isEmpty }
        return values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var reportTickets: [SupportTicket] {
        store.visibleTickets.filter { ticket in
            let campusMatches = exportCampusFilter.isEmpty
                || ticket.campus.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(exportCampusFilter) == .orderedSame

            let categoryMatches = exportCategoryFilter.isEmpty
                || ticket.category.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(exportCategoryFilter) == .orderedSame

            let subcategoryMatches = exportSubcategoryFilter.isEmpty
                || ticket.subcategory.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(exportSubcategoryFilter) == .orderedSame

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

            return campusMatches && categoryMatches && subcategoryMatches && agentMatches && statusMatches
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

                    Picker("Category", selection: $exportCategoryFilter) {
                        Text("All Categories").tag("")
                        ForEach(availableTicketReportCategories, id: \.self) { category in
                            Text(category).tag(category)
                        }
                    }
                    .onChange(of: exportCategoryFilter) { _ in
                        // Clear subcategory if it no longer exists under the new category
                        if !exportSubcategoryFilter.isEmpty && !availableTicketReportSubcategories.contains(exportSubcategoryFilter) {
                            exportSubcategoryFilter = ""
                        }
                    }

                    if !availableTicketReportSubcategories.isEmpty {
                        Picker("Subcategory", selection: $exportSubcategoryFilter) {
                            Text("All Subcategories").tag("")
                            ForEach(availableTicketReportSubcategories, id: \.self) { sub in
                                Text(sub).tag(sub)
                            }
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

    @MainActor
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
    @State private var notes = ""
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
                        Text("Idea")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $detail)
                            .frame(minHeight: 120)
                        Text("Notes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $notes)
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
        let now = Date()
        store.saveIdea(
            IdeaCard(
                id: existingIdea?.id ?? UUID().uuidString,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                detail: detail.trimmingCharacters(in: .whitespacesAndNewlines),
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                tags: parsedTags,
                teamCode: existingIdea?.teamCode ?? store.teamCode ?? "",
                createdBy: existingIdea?.createdBy ?? store.user?.email,
                createdAt: existingIdea?.createdAt ?? now,
                updatedAt: now,
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
        notes = idea.notes
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
                if !idea.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label("Notes added", systemImage: "note.text")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if !idea.tags.isEmpty {
                    Text(idea.tags.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text("Updated \(idea.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
        notes = ""
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
    @State private var smaartEnabled = false
    @State private var smaartHost = "localhost"
    @State private var smaartPort = "9090"
    @State private var smaartPath = ""
    @State private var smaartPassword = ""
    @State private var smaartPollInterval = "1.0"
    @ObservedObject private var smaartController = SmaartAPIController.shared
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

    private var hasOverviewFeature: Bool {
        guard let user = store.user else { return false }
        return user.normalizedSubscriptionTier != "free"
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
        .onAppear {
            loadFreshserviceIntegrationState()
            loadSmaartSettings()
        }
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
        case .overview, .ndi, .midi, .users:
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
            if canManageExternalTicketForm {
                externalTicketFormGroup
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
        }
    }

    private var externalTicketFormGroup: some View {
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

            if hasOverviewFeature {
            GroupBox("Smaart") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Connect to the Smaart SPL Webserver to display real-time dB measurements in the Overview.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Enable Smaart Integration", isOn: $smaartEnabled)

                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Host").font(.caption).foregroundStyle(.secondary)
                            TextField("localhost", text: $smaartHost)
                                .textFieldStyle(.roundedBorder)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Port").font(.caption).foregroundStyle(.secondary)
                            TextField("9090", text: $smaartPort)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("API Path (optional; leave blank to auto-detect)").font(.caption).foregroundStyle(.secondary)
                        TextField("Auto-detect", text: $smaartPath)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Password (optional)").font(.caption).foregroundStyle(.secondary)
                        SecureField("Password", text: $smaartPassword)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Poll Interval (seconds)").font(.caption).foregroundStyle(.secondary)
                        TextField("0.10", text: $smaartPollInterval)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }

                    HStack(spacing: 12) {
                        Button("Save") {
                            saveSmaartSettings()
                        }
                        .buttonStyle(.borderedProminent)

                        HStack(spacing: 6) {
                            Circle()
                                .fill(smaartController.connectionStatus.isConnected ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(smaartController.connectionStatus.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !smaartController.lastRawResponse.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Last Raw Response (for debugging):")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ScrollView(.vertical) {
                                Text(smaartController.lastRawResponse)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            .frame(maxHeight: 120)
                            .padding(8)
                            .background(Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }

                    Text("For SPL readings, enable Smaart's SPL Webviewer/webserver. Smaart's main API uses WebSocket commands; this overview tile reads HTTP JSON meter data when available.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
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

    private func loadSmaartSettings() {
        let s = smaartController.settings
        smaartEnabled = s.isEnabled
        smaartHost = s.host
        smaartPort = "\(s.port)"
        smaartPath = s.apiPath
        smaartPassword = s.password
        smaartPollInterval = String(format: "%.2f", s.pollIntervalSeconds)
    }

    private func saveSmaartSettings() {
        var s = SmaartSettings()
        s.isEnabled = smaartEnabled
        s.host = smaartHost.trimmingCharacters(in: .whitespacesAndNewlines)
        s.port = Int(smaartPort.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 9090
        s.apiPath = smaartPath.trimmingCharacters(in: .whitespacesAndNewlines)
        s.password = smaartPassword
        s.pollIntervalSeconds = max(0.05, Double(smaartPollInterval) ?? 0.1)
        smaartController.applySettings(s)
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
                        freshserviceStatusMessage = "Connected to Freshservice. Found at least \(filteredItems.count) assets (2,000 asset test cap reached)."
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
                    logFreshserviceAssetSample(items)
                    let filteredItems = filteredFreshserviceItems(items)
                    switch selectedDestination {
                    case .assetsTab:
                        let saveAssets: ([[String: Any]]) -> Void = { importItems in
                            let rawImported = importItems.compactMap { mapFreshserviceAsset($0) }
                            // Deduplicate by ID — Freshservice can return the same asset on multiple pages
                            var seen = Set<String>()
                            let imported = rawImported.filter { seen.insert($0.id).inserted }
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
                        }

                        let resolveAndSave: ([[String: Any]]) -> Void = { assetsToResolve in
                            resolveFreshserviceAssetLookups(assetsToResolve, apiKey: trimmedKey, apiUrl: trimmedURL) { resolvedItems in
                                saveAssets(resolvedItems)
                            }
                        }

                        if hasResolvedFreshserviceAssetFields(filteredItems) {
                            resolveAndSave(filteredItems)
                        } else {
                            enrichFreshserviceAssets(filteredItems, apiKey: trimmedKey, apiUrl: trimmedURL) { enrichedItems in
                                DispatchQueue.main.async {
                                    resolveAndSave(enrichedItems)
                                }
                            }
                        }
                    case .ticketsTab:
                        let imported = filteredItems.compactMap { mapFreshserviceTicket($0) }
                        store.upsertTickets(imported) { saveResult in
                            isImportingFreshserviceData = false
                            switch saveResult {
                            case .success:
                                freshserviceStatusMessage = reachedCap
                                    ? "Imported \(imported.count) Freshservice \(selectedImportKind.rawValue) into Tickets and Firebase. 30,000 asset cap reached."
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
            MacFreshserviceAPI.fetchAllAssetsForImportWithAPIKey(apiKey: trimmedKey, apiUrl: trimmedURL, completion: assetCompletion)
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

    private func logFreshserviceAssetSample(_ items: [[String: Any]]) {
        guard selectedImportKind == .assets, let first = items.first else { return }
        let sortedKeys = first.keys.sorted()
        print("Freshservice asset sample keys:", sortedKeys.joined(separator: ", "))
        if let typeFields = first["type_fields"] as? [String: Any] {
            let tfKeys = typeFields.keys.sorted()
            print("Freshservice type_fields keys:", tfKeys.joined(separator: ", "))
            for key in tfKeys {
                print("  type_fields[\(key)]:", String(describing: typeFields[key]!))
            }
        } else {
            print("Freshservice type_fields: not present (include=type_fields may not be supported on list endpoint)")
        }
    }

    private func hasResolvedFreshserviceAssetFields(_ assets: [[String: Any]]) -> Bool {
        guard let first = assets.first else { return false }

        // Freshservice v2 API returns only IDs (location_id, asset_type_id) — never embedded
        // name objects or flat name strings. Per-asset detail fetches return the same structure,
        // so enrichment cannot resolve names. Skip it and let resolveFreshserviceAssetLookups
        // handle resolution via the /locations and /asset_types endpoints instead.
        let hasIDOnlyFields = stringValue(first["location_id"]) != nil
            || stringValue(first["asset_type_id"]) != nil
        if hasIDOnlyFields { return true }

        let resolvedFields = [
            nestedStringValue(first["asset_type"], key: "name"),
            stringValue(first["asset_type_name"]),
            stringValue(first["ci_type_name"]),
            stringValue(first["config_item_type_name"]),
            nestedStringValue(first["location"], key: "name"),
            stringValue(first["location_name"]),
            nestedStringValue(first["department"], key: "name"),
            stringValue(first["department_name"]),
            nestedStringValue(first["asset_state"], key: "name"),
            stringValue(first["asset_state_name"]),
            stringValue(first["state_name"])
        ]

        return resolvedFields
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains { !$0.isEmpty }
    }

    private func resolveFreshserviceAssetLookups(
        _ assets: [[String: Any]],
        apiKey: String,
        apiUrl: String,
        completion: @escaping ([[String: Any]]) -> Void
    ) {
        let group = DispatchGroup()
        var locationMap = [String: String]()
        var assetTypeMap = [String: String]()

        group.enter()
        MacFreshserviceAPI.fetchLocationsWithAPIKey(apiKey: apiKey, apiUrl: apiUrl) { result in
            if case .success(let map) = result { locationMap = map }
            group.leave()
        }

        group.enter()
        MacFreshserviceAPI.fetchAssetTypesWithAPIKey(apiKey: apiKey, apiUrl: apiUrl) { result in
            if case .success(let map) = result { assetTypeMap = map }
            group.leave()
        }

        group.notify(queue: .main) {
            let resolved = assets.map { asset -> [String: Any] in
                var enriched = asset

                // Resolve top-level location_id → location_name
                if stringValue(asset["location_name"]) == nil,
                   let locID = stringValue(asset["location_id"]),
                   let locName = locationMap[locID] {
                    enriched["location_name"] = locName
                }

                // Resolve asset_type_id → asset_type_name
                if stringValue(asset["asset_type_name"]) == nil,
                   let typeID = stringValue(asset["asset_type_id"]),
                   let typeName = assetTypeMap[typeID] {
                    enriched["asset_type_name"] = typeName
                }

                // Resolve any type_fields values that are numeric location IDs
                // (e.g. lf_physical_room_location_* stores a location_id integer)
                if var typeFields = enriched["type_fields"] as? [String: Any] {
                    for (key, value) in typeFields {
                        let idStr: String?
                        if let n = value as? Int { idStr = String(n) }
                        else if let s = value as? String, s.allSatisfy({ $0.isNumber }), !s.isEmpty { idStr = s }
                        else { idStr = nil }

                        if let id = idStr, let name = locationMap[id] {
                            typeFields[key] = name
                        }
                    }
                    enriched["type_fields"] = typeFields
                }

                return enriched
            }
            completion(resolved)
        }
    }

    private func enrichFreshserviceAssets(
        _ assets: [[String: Any]],
        apiKey: String,
        apiUrl: String,
        completion: @escaping ([[String: Any]]) -> Void
    ) {
        let indexedAssets = assets.enumerated().compactMap { index, asset -> (Int, [String], [String: Any])? in
            let identifiers = [
                stringValue(asset["display_id"]),
                stringValue(asset["id"]),
                stringValue(asset["asset_tag"])
            ]
            .compactMap { $0 }
            .reduce(into: [String]()) { partialResult, identifier in
                if !partialResult.contains(identifier) {
                    partialResult.append(identifier)
                }
            }

            guard !identifiers.isEmpty else { return nil }
            return (index, identifiers, asset)
        }
        guard !indexedAssets.isEmpty else {
            completion(assets)
            return
        }

        let maxConcurrentRequests = 8
        let syncQueue = DispatchQueue(label: "MacFreshserviceAssetEnrichmentSync")
        var nextIndex = 0
        var activeRequests = 0
        var didComplete = false
        var enrichedAssets = assets

        func finishIfNeeded() {
            guard !didComplete else { return }
            if nextIndex >= indexedAssets.count && activeRequests == 0 {
                didComplete = true
                DispatchQueue.main.async {
                    completion(enrichedAssets)
                }
            }
        }

        func launchMoreRequests() {
            guard !didComplete else { return }
            while activeRequests < maxConcurrentRequests && nextIndex < indexedAssets.count {
                let (assetIndex, identifiers, originalAsset) = indexedAssets[nextIndex]
                nextIndex += 1
                activeRequests += 1

                fetchFreshserviceAssetDetails(
                    identifiers: identifiers,
                    apiKey: apiKey,
                    apiUrl: apiUrl
                ) { result in
                    syncQueue.async {
                        defer {
                            activeRequests -= 1
                            launchMoreRequests()
                            finishIfNeeded()
                        }

                        guard !didComplete else { return }
                        guard case .success(let detail) = result else { return }

                        var merged = originalAsset
                        merged.merge(detail) { _, new in new }
                        enrichedAssets[assetIndex] = merged
                    }
                }
            }
        }

        syncQueue.async {
            launchMoreRequests()
            finishIfNeeded()
        }
    }

    private func fetchFreshserviceAssetDetails(
        identifiers: [String],
        apiKey: String,
        apiUrl: String,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        guard let identifier = identifiers.first else {
            completion(.failure(NSError(
                domain: "Freshservice",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "No Freshservice asset identifier was available."]
            )))
            return
        }

        MacFreshserviceAPI.fetchAssetDetailsWithAPIKey(apiKey: apiKey, apiUrl: apiUrl, assetID: identifier) { result in
            switch result {
            case .success:
                completion(result)
            case .failure:
                let remaining = Array(identifiers.dropFirst())
                guard !remaining.isEmpty else {
                    completion(result)
                    return
                }
                fetchFreshserviceAssetDetails(
                    identifiers: remaining,
                    apiKey: apiKey,
                    apiUrl: apiUrl,
                    completion: completion
                )
            }
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
                        freshserviceStatusMessage = "Loaded \(managedByGroupOptions.count) managed-by groups from the first 30,000 assets."
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
        let category = freshserviceAssetTypeName(from: asset) ?? "Freshservice"
        let location = freshserviceLocationName(from: asset) ?? ""
        let campus = freshserviceCampusName(from: asset) ?? location
        let room = typeFieldValue(from: asset, prefix: "lf_physical_room_location") ?? ""

        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let serialNumber = stringValue(asset["serial_number"])
            ?? typeFieldValue(from: asset, prefix: "serial_number")
            ?? ""

        var item = GearItem(
            id: freshserviceID.map { "freshservice-\($0)" } ?? UUID().uuidString,
            name: name,
            category: category,
            status: mappedStatus(from: asset),
            teamCode: store.teamCode ?? "",
            location: location,
            room: room,
            serialNumber: serialNumber,
            campus: campus,
            assetId: stringValue(asset["asset_tag"]) ?? stringValue(asset["display_id"]) ?? "",
            maintenanceNotes: freshserviceAssetNotes(from: asset),
            createdBy: "Freshservice Import"
        )

        item.purchasedFrom = typeFieldValue(from: asset, prefix: "purchase_from")
            ?? nestedStringValue(asset["vendor"], key: "name")
            ?? ""
        item.purchaseDate = parsedDate(from: typeFieldValue(from: asset, prefix: "acquisition_date"))
            ?? parsedDate(from: asset["purchase_date"])
            ?? parsedDate(from: asset["created_at"])
        item.installDate = parsedDate(from: asset["created_at"])
        item.cost = doubleValue(typeFieldValue(from: asset, prefix: "cost"))
            ?? doubleValue(asset["cost"])
            ?? doubleValue(asset["salvage_price"])
        return item
    }

    private func freshserviceAssetTypeName(from asset: [String: Any]) -> String? {
        [
            nestedStringValue(asset["asset_type"], key: "name"),
            stringValue(asset["asset_type_name"]),
            stringValue(asset["ci_type_name"]),
            stringValue(asset["config_item_type_name"]),
            nestedStringValue(asset["product"], key: "name")
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty }
    }

    private func freshserviceLocationName(from asset: [String: Any]) -> String? {
        [
            nestedStringValue(asset["location"], key: "name"),
            stringValue(asset["location_name"])
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty }
    }

    private func freshserviceCampusName(from asset: [String: Any]) -> String? {
        [
            nestedStringValue(asset["department"], key: "name"),
            stringValue(asset["department_name"]),
            nestedStringValue(asset["location"], key: "name"),
            stringValue(asset["location_name"])
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty }
    }

    private func freshserviceAssetNotes(from asset: [String: Any]) -> String {
        [
            typeFieldValue(from: asset, prefix: "notes"),
            typeFieldValue(from: asset, prefix: "note"),
            typeFieldValue(from: asset, prefix: "comments"),
            typeFieldValue(from: asset, prefix: "comment"),
            stringValue(asset["notes"]),
            stringValue(asset["note"]),
            stringValue(asset["description"])
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty } ?? ""
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
        // Asset state lives in type_fields with a tenant-suffixed key, e.g. "asset_state_37000348776"
        let statusCandidates: [String?] = [
            typeFieldValue(from: asset, prefix: "asset_state"),
            typeFieldValue(from: asset, prefix: "lifecycle_state"),
            nestedStringValue(asset["asset_state"], key: "name"),
            stringValue(asset["asset_state_name"]),
            nestedStringValue(asset["lifecycle_state"], key: "name"),
            stringValue(asset["lifecycle_state_name"]),
            nestedStringValue(asset["state"], key: "name"),
            nestedStringValue(asset["ci_status"], key: "name"),
            stringValue(asset["state_name"]),
            stringValue(asset["ci_status_name"]),
            stringValue(asset["status"])
        ]
        let raw = statusCandidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })?
            .lowercased() ?? ""

        if raw.contains("repair") || raw.contains("maint") { return .needsRepair }
        if raw.contains("recycle") || raw.contains("recycling") { return .recycle }
        if raw.contains("retired") || raw.contains("disposal") || raw.contains("disposed") || raw.contains("decommission") || raw.contains("obsolete") {
            return .retired
        }
        if raw.contains("missing") || raw.contains("lost") { return .missing }
        if raw.contains("checkout") || raw.contains("checked out") { return .checkedOut }
        if raw.contains("use") || raw.contains("deployed") || raw.contains("assigned") || raw.contains("loaner") { return .inUse }
        if raw.contains("stock") || raw.contains("available") || raw.contains("store") || raw.contains("spare") { return .available }
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

    /// Finds the first value in `type_fields` whose key starts with `prefix` (Freshservice
    /// appends a numeric tenant ID suffix to all type field keys, e.g. "asset_state_37000348776").
    private func typeFieldValue(from asset: [String: Any], prefix: String) -> String? {
        guard let typeFields = asset["type_fields"] as? [String: Any] else { return nil }
        for (key, value) in typeFields where key.hasPrefix(prefix) {
            if let str = stringValue(value) { return str }
        }
        return nil
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
                case "room": item.room = value
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
                    } else if lowerValue.contains("recycle") {
                        item.status = .recycle
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

                switch header
                    .replacingOccurrences(of: "\u{FEFF}", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased() {
                case "name": row.name = value
                case "input": row.input = value
                case "output": row.output = value
                case "notes", "note", "comments", "comment": row.notes = value
                case "category": row.category = value
                case "campus": row.campus = value
                case "room": row.room = value
                case "universe": row.universe = value
                default: break
                }
            }

            if !row.name.isEmpty {
                row.position = rows.count
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

    private var visibleUsers: [UserProfile] {
        var usersByID: [String: UserProfile] = [:]
        for member in store.teamMembers {
            usersByID[member.id] = member
        }
        if let currentUser = store.user {
            usersByID[currentUser.id] = currentUser
        }
        return usersByID.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    var body: some View {
        Group {
            if visibleUsers.isEmpty {
                VStack(spacing: 10) {
                    Text("No users loaded")
                        .font(.headline)
                    Text("Team members will appear here once the team user list finishes loading.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(visibleUsers) { user in
                    userRow(for: user)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .navigationTitle("Users")
        .onAppear {
            store.listenToTeamMembers()
        }
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
    @EnvironmentObject private var store: ProdConnectStore
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

    private var shouldHighlightIntroOffer: Bool {
        guard currentTier == "free" else { return false }
        guard let user = store.user else { return false }
        let distinctMemberIDs = Set(store.teamMembers.map(\.id))
        return distinctMemberIDs.isEmpty || distinctMemberIDs == [user.id]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("ProdConnect Subscriptions")
                        .font(.title3.weight(.semibold))

                    Text("Choose the plan that fits your production team. Subscriptions renew automatically unless canceled in your Apple account settings.")
                        .foregroundStyle(.secondary)

                    if shouldHighlightIntroOffer {
                        Text("Start with a 7-day free trial on any plan.")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.green)

                        Text("Available for new individual subscriptions. Team members on someone else’s account are not eligible.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    subscriptionCard(
                        title: basicProduct?.displayName ?? "Basic",
                        subtitle: "$99.99. Includes chat and training, but hides Locations, Rooms, and Tickets.",
                        price: priceText(for: basicProduct),
                        offerText: introductoryOfferText(for: basicProduct),
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
                        offerText: introductoryOfferText(for: basicTicketingProduct),
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
                        offerText: introductoryOfferText(for: premiumProduct),
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
                        offerText: introductoryOfferText(for: premiumTicketingProduct),
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
        offerText: String?,
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
            if let offerText {
                Text(offerText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            }
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

    private func introductoryOfferText(for product: Product?) -> String? {
        guard shouldHighlightIntroOffer else { return nil }
        guard let offer = product?.subscription?.introductoryOffer else {
            return "Includes a 7-day free trial for new subscribers."
        }

        let periodText = subscriptionPeriodText(value: offer.period.value, unit: offer.period.unit)
        switch offer.paymentMode {
        case .freeTrial:
            return "Includes \(periodText) free trial for new subscribers."
        case .payAsYouGo:
            return "Intro offer: \(offer.displayPrice) for \(periodText)."
        case .payUpFront:
            return "Intro offer: \(offer.displayPrice) upfront for \(periodText)."
        default:
            return "Intro offer available for new subscribers."
        }
    }

    private func subscriptionPeriodText(value: Int, unit: Product.SubscriptionPeriod.Unit) -> String {
        let resolvedUnit: String
        switch unit {
        case .day:
            resolvedUnit = value == 1 ? "day" : "days"
        case .week:
            resolvedUnit = value == 1 ? "week" : "weeks"
        case .month:
            resolvedUnit = value == 1 ? "month" : "months"
        case .year:
            resolvedUnit = value == 1 ? "year" : "years"
        @unknown default:
            resolvedUnit = "period"
        }
        return "\(value) \(resolvedUnit)"
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
