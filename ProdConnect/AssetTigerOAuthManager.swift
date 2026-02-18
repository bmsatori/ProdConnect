
import Foundation
import Combine
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

class AssetTigerOAuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var accessToken: String?
    
    // Replace with your AssetTiger OAuth details
    private let clientId = "YOUR_CLIENT_ID"
    private let clientSecret = "YOUR_CLIENT_SECRET"
    private let redirectUri = "YOUR_REDIRECT_URI"
    private let authEndpoint = "https://YOUR_DOMAIN.assettiger.com/oauth/authorize"
    private let tokenEndpoint = "https://YOUR_DOMAIN.assettiger.com/oauth/token"
    
    func startOAuthFlow(apiUrl: String) {
        let trimmedUrl = apiUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUrl.isEmpty else { return }
        let authEndpoint = "\(trimmedUrl)/oauth/authorize"
        // Construct the authorization URL
        let urlString = "\(authEndpoint)?response_type=code&client_id=\(clientId)&redirect_uri=\(redirectUri)&scope=assets.view assets.manage"
        if let url = URL(string: urlString) {
            #if os(iOS)
            UIApplication.shared.open(url)
            #elseif os(macOS)
            NSWorkspace.shared.open(url)
            #endif
        }
    }
    
    func handleRedirect(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else { return }
        exchangeCodeForToken(code: code)
    }
    
    private func exchangeCodeForToken(code: String) {
        guard let url = URL(string: tokenEndpoint) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let body = "grant_type=authorization_code&code=\(code)&redirect_uri=\(redirectUri)&client_id=\(clientId)&client_secret=\(clientSecret)"
        request.httpBody = body.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else { return }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let token = json["access_token"] as? String {
                DispatchQueue.main.async {
                    self.accessToken = token
                    self.isAuthenticated = true
                }
            }
        }.resume()
    }
}
