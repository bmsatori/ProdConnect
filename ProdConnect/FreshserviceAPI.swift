import Foundation

class FreshserviceAPI {
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

    private static func mappedError(_ error: Error) -> Error {
        guard let urlError = error as? URLError else { return error }

        switch urlError.code {
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot:
            return NSError(
                domain: "Freshservice",
                code: urlError.errorCode,
                userInfo: [
                    NSLocalizedDescriptionKey: "TLS/SSL connection failed. Use your Freshservice base URL only, like https://yourcompany.freshservice.com, and make sure the domain's certificate is valid."
                ]
            )
        case .badURL, .unsupportedURL:
            return NSError(
                domain: "Freshservice",
                code: urlError.errorCode,
                userInfo: [
                    NSLocalizedDescriptionKey: "Invalid Freshservice URL. Enter only the base URL, like https://yourcompany.freshservice.com."
                ]
            )
        default:
            return error
        }
    }

    private static func extractItems(from jsonObject: Any, preferredKeys: [String]) -> [[String: Any]]? {
        if let items = jsonObject as? [[String: Any]] {
            return items
        }

        guard let json = jsonObject as? [String: Any] else {
            return nil
        }

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

        if
            let jsonObject = try? JSONSerialization.jsonObject(with: data),
            let json = jsonObject as? [String: Any]
        {
            if let description = json["description"] as? String, !description.isEmpty {
                return description
            }
            if let message = json["message"] as? String, !message.isEmpty {
                return message
            }
            if
                let errors = json["errors"] as? [[String: Any]],
                let firstError = errors.first
            {
                if let message = firstError["message"] as? String, !message.isEmpty {
                    return message
                }
                if let field = firstError["field"] as? String, let code = firstError["code"] as? String {
                    return "\(field): \(code)"
                }
            }
        }

        if let body = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !body.isEmpty
        {
            if body.hasPrefix("<") {
                return fallback
            }
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
            completion(.failure(NSError(domain: "Invalid URL", code: 0)))
            return
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            completion(.failure(NSError(domain: "Invalid URL", code: 0)))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = objectRequestTimeout
        let credentialData = "\(apiKey):X".data(using: .utf8)!
        let base64Credentials = credentialData.base64EncodedString()
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(mappedError(error)))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(NSError(
                    domain: "Freshservice",
                    code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "Freshservice returned an invalid HTTP response."]
                )))
                return
            }
            guard let data = data else {
                completion(.failure(NSError(
                    domain: "Freshservice",
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "Freshservice returned no data."]
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
                let preferredKeys: [String]
                if endpoint.contains("tickets") {
                    preferredKeys = ["tickets", "results", "data"]
                } else {
                    preferredKeys = ["assets", "config_items", "cis", "results", "data"]
                }

                if let items = extractItems(from: jsonObject, preferredKeys: preferredKeys) {
                    completion(.success(items))
                    return
                }

                completion(.failure(NSError(
                    domain: "Freshservice",
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "Freshservice returned a response in an unsupported format."]
                )))
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
            completion(.failure(NSError(domain: "Invalid URL", code: 0)))
            return
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            completion(.failure(NSError(domain: "Invalid URL", code: 0)))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let credentialData = "\(apiKey):X".data(using: .utf8)!
        let base64Credentials = credentialData.base64EncodedString()
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(mappedError(error)))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(NSError(
                    domain: "Freshservice",
                    code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "Freshservice returned an invalid HTTP response."]
                )))
                return
            }
            guard let data = data else {
                completion(.failure(NSError(
                    domain: "Freshservice",
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "Freshservice returned no data."]
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

    static func fetchAssetsWithAPIKey(apiKey: String, apiUrl: String, completion: @escaping (Result<[[String: Any]], Error>) -> Void) {
        performListRequest(apiKey: apiKey, apiUrl: apiUrl, endpoint: "api/v2/assets", completion: completion)
    }

    /// Fetches all Freshservice locations (paginated) and returns a dictionary mapping ID strings to location names.
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

    /// Fetches all Freshservice asset types (paginated) and returns a dictionary mapping ID strings to type names.
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

            performListRequest(
                apiKey: apiKey,
                apiUrl: apiUrl,
                endpoint: "api/v2/assets",
                queryItems: queryItems
            ) { result in
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

            performListRequest(
                apiKey: apiKey,
                apiUrl: apiUrl,
                endpoint: "cmdb/items.json",
                queryItems: queryItems
            ) { result in
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

    static func fetchTicketsWithAPIKey(apiKey: String, apiUrl: String, completion: @escaping (Result<[[String: Any]], Error>) -> Void) {
        performListRequest(apiKey: apiKey, apiUrl: apiUrl, endpoint: "api/v2/tickets", completion: completion)
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

            performListRequest(
                apiKey: apiKey,
                apiUrl: apiUrl,
                endpoint: "api/v2/tickets",
                queryItems: queryItems
            ) { result in
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

    static func fetchTicketDetailsWithAPIKey(
        apiKey: String,
        apiUrl: String,
        ticketID: String,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        performObjectRequest(
            apiKey: apiKey,
            apiUrl: apiUrl,
            endpoint: "api/v2/tickets/\(ticketID)",
            queryItems: [URLQueryItem(name: "include", value: "requester")]
        ) { result in
            switch result {
            case .success(let json):
                if let ticket = json["ticket"] as? [String: Any] {
                    completion(.success(ticket))
                } else {
                    completion(.failure(NSError(
                        domain: "Freshservice",
                        code: 0,
                        userInfo: [NSLocalizedDescriptionKey: "Freshservice ticket detail response was missing the ticket object."]
                    )))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
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

                            let interestingFields = [
                                "id",
                                "display_id",
                                "name",
                                "display_name",
                                "asset_tag",
                                "serial_number",
                                "status",
                                "status_name",
                                "state",
                                "state_name",
                                "asset_state",
                                "asset_state_name",
                                "ci_status",
                                "ci_status_name",
                                "lifecycle_state",
                                "lifecycle_state_name",
                                "asset_type",
                                "asset_type_name",
                                "asset_type_id",
                                "ci_type",
                                "ci_type_name",
                                "config_item_type",
                                "config_item_type_name",
                                "department",
                                "department_name",
                                "department_id",
                                "location",
                                "location_name",
                                "location_id",
                                "site",
                                "site_name",
                                "workspace",
                                "workspace_name",
                                "usage_type",
                                "custom_fields"
                            ]

                            for field in interestingFields where object[field] != nil {
                                print("Freshservice asset detail sample \(field):", String(describing: object[field]!))
                            }
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

    static func fetchAgentNameWithAPIKey(
        apiKey: String,
        apiUrl: String,
        agentID: String,
        completion: @escaping (Result<String?, Error>) -> Void
    ) {
        performObjectRequest(
            apiKey: apiKey,
            apiUrl: apiUrl,
            endpoint: "api/v2/agents/\(agentID)"
        ) { result in
            switch result {
            case .success(let json):
                let agent = json["agent"] as? [String: Any]
                let user = agent?["user"] as? [String: Any]
                let contact = agent?["contact"] as? [String: Any]
                let occasionalAgent = agent?["occasional_agent"] as? [String: Any]

                let firstName = (user?["first_name"] as? String) ?? (agent?["first_name"] as? String)
                let lastName = (user?["last_name"] as? String) ?? (agent?["last_name"] as? String)
                let fullName = [firstName, lastName]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")

                let nameCandidates: [String?] = [
                    agent?["name"] as? String,
                    user?["name"] as? String,
                    contact?["name"] as? String,
                    occasionalAgent?["name"] as? String,
                    fullName.isEmpty ? nil : fullName,
                    agent?["email"] as? String,
                    user?["email"] as? String,
                    contact?["email"] as? String
                ]

                let resolvedName = nameCandidates
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first { !$0.isEmpty }

                completion(.success(resolvedName))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    static func fetchGroupNameWithAPIKey(
        apiKey: String,
        apiUrl: String,
        groupID: String,
        completion: @escaping (Result<String?, Error>) -> Void
    ) {
        performObjectRequest(
            apiKey: apiKey,
            apiUrl: apiUrl,
            endpoint: "api/v2/groups/\(groupID)"
        ) { result in
            switch result {
            case .success(let json):
                let group = json["group"] as? [String: Any]
                completion(.success(group?["name"] as? String))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    static func fetchDepartmentNameWithAPIKey(
        apiKey: String,
        apiUrl: String,
        departmentID: String,
        completion: @escaping (Result<String?, Error>) -> Void
    ) {
        performObjectRequest(
            apiKey: apiKey,
            apiUrl: apiUrl,
            endpoint: "api/v2/departments/\(departmentID)"
        ) { result in
            switch result {
            case .success(let json):
                let department = json["department"] as? [String: Any]
                completion(.success(department?["name"] as? String))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    static func fetchAssets(accessToken: String, completion: @escaping (Result<[[String: Any]], Error>) -> Void) {
        // Replace with your Freshservice domain
        let urlString = "https://YOUR_DOMAIN.freshservice.com/api/v2/assets"
        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "Invalid URL", code: 0)))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(NSError(domain: "No data", code: 0)))
                return
            }
            do {
                let jsonObject = try JSONSerialization.jsonObject(with: data)
                if let assets = extractItems(from: jsonObject, preferredKeys: ["assets", "config_items", "cis", "results", "data"]) {
                    completion(.success(assets))
                } else {
                    completion(.failure(NSError(domain: "Invalid response", code: 0)))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}
