import Foundation

class FreshserviceAPI {
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
