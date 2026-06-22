import SwiftUI
import Observation

@Observable
class AuthManager {
    var isAuthenticated: Bool = false
    
    init() {
        // 起動時にKeychainを確認して自動ログイン判定
        checkSession()
    }
    
    func checkSession() {
        isAuthenticated = KeychainHelper.shared.readSession() != nil
    }
    
    func login(session: UserSession) {
        KeychainHelper.shared.saveSession(session)
        withAnimation(.easeInOut) {
            isAuthenticated = true
        }
    }
    
    func logout() {
        KeychainHelper.shared.deleteSession()
        withAnimation(.easeInOut) {
            isAuthenticated = false
        }
    }
    
    func getUserId() -> String? {
        return KeychainHelper.shared.readSession()?.userId
    }
    
    func getValidAccessToken() async -> String? {
        guard let session = KeychainHelper.shared.readSession() else { return nil }
        let now = Date().timeIntervalSince1970
        // 5 minutes buffer
        if session.expiryDate > now + 300 {
            return session.accessToken
        }
        
        guard let refreshToken = session.refreshToken else { return nil }
        
        // GoogleのToken APIでリフレッシュ処理を行う
        let clientID = "725405052696-1ijvqnh0b09t9rj9gd032s0aobhvuvrj.apps.googleusercontent.com"
        var components = URLComponents(string: "https://oauth2.googleapis.com/token")!
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ]
        request.httpBody = body.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                struct GoogleTokenResponse: Codable {
                    let access_token: String
                    let expires_in: Int
                }
                let res = try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
                let updatedSession = UserSession(
                    userId: session.userId,
                    accessToken: res.access_token,
                    refreshToken: refreshToken,
                    expiryDate: Date().timeIntervalSince1970 + Double(res.expires_in)
                )
                KeychainHelper.shared.saveSession(updatedSession)
                return res.access_token
            } else {
                print("Token refresh failed with status code: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            }
        } catch {
            print("Failed to refresh access token: \(error)")
        }
        return nil
    }
}