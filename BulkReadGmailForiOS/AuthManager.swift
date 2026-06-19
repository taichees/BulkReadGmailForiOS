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
        isAuthenticated = KeychainHelper.shared.read() != nil
    }
    
    func login(token: String) {
        KeychainHelper.shared.save(token)
        withAnimation(.easeInOut) {
            isAuthenticated = true
        }
    }
    
    func logout() {
        KeychainHelper.shared.delete()
        withAnimation(.easeInOut) {
            isAuthenticated = false
        }
    }
}