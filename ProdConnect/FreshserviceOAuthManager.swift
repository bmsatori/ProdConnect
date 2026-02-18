
import Foundation
import Combine
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

class FreshserviceAPIKeyManager: ObservableObject {
    @Published var apiKey: String = ""
    @Published var apiUrl: String = ""
    
    func setCredentials(apiKey: String, apiUrl: String) {
        self.apiKey = apiKey
        self.apiUrl = apiUrl
    }
    
    func performRequest(endpoint: String, completion: @escaping (Result<Data, Error>) -> Void) {
        guard !apiKey.isEmpty, !apiUrl.isEmpty else {
            completion(.failure(NSError(domain: "Freshservice", code: 401, userInfo: [NSLocalizedDescriptionKey: "API Key or URL missing"])));
            return
        }
        let urlString = apiUrl + endpoint
        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "Freshservice", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        var request = URLRequest(url: url)
        let credentialData = "\(apiKey):X".data(using: .utf8)!
        let base64Credentials = credentialData.base64EncodedString()
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        request.httpMethod = "GET"
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
            } else if let data = data {
                completion(.success(data))
            } else {
                completion(.failure(NSError(domain: "Freshservice", code: 500, userInfo: [NSLocalizedDescriptionKey: "Unknown error"])))
            }
        }.resume()
    }
}
