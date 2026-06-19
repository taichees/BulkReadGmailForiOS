import SwiftUI
import AuthenticationServices // ASWebAuthenticationSession を使用するために必要

struct LoginView: View {
    @Environment(AuthManager.self) private var authManager
    
    @State private var webAuthSession: ASWebAuthenticationSession?
    private let contextProvider = AuthenticationContextProvider()

    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            Image(systemName: "envelope.badge.shield.half.filled")
                .font(.system(size: 100))
                .foregroundStyle(.blue)
            
            VStack(spacing: 8) {
                Text("Gmail一括既読")
                    .font(.largeTitle.bold())
                Text("有料版 - プロフェッショナル")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button {
                // OAuth認証フローを開始
                startGoogleOAuth()
            } label: {
                HStack {
                    Image(systemName: "g.circle.fill")
                    Text("Googleアカウントでログイン")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .cornerRadius(12)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 50)
        }
    }
    
    private func startGoogleOAuth() {
        // Google Cloud Consoleで設定したクライアントID、リダイレクトURI、スコープを使用します。
        let clientID = "725405052696-1ijvqnh0b09t9rj9gd032s0aobhvuvrj.apps.googleusercontent.com"
        let redirectURI = "com.taichees.BulkReadGmailForiOS:/oauth2redirect"
        let scope = "https://www.googleapis.com/auth/gmail.readonly https://www.googleapis.com/auth/gmail.modify openid email"
        
        // 認証リクエストURLを構築
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"), // codeフローを使用
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "access_type", value: "offline"), // リフレッシュトークンを取得する場合
            URLQueryItem(name: "prompt", value: "consent select_account") // 常にアカウント選択と同意を促す
        ]
        
        guard let authURL = components.url else { return }
        
        webAuthSession = ASWebAuthenticationSession(url: authURL, callbackURLScheme: URL(string: redirectURI)?.scheme) { callbackURL, error in
            if let callbackURL = callbackURL {
                if let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: true),
                   let queryItems = components.queryItems,
                   let code = queryItems.first(where: { $0.name == "code" })?.value {
                    
                    Task {
                        if let userId = await sendAuthorizationCodeToServer(code: code) {
                            await MainActor.run {
                                authManager.login(token: userId)
                            }
                        } else {
                            print("OAuth認証失敗: サーバーでのトークン保存に失敗しました。")
                        }
                    }
                }
            } else if let error = error {
                print("OAuth認証エラー: \(error.localizedDescription)")
            }
        }
        webAuthSession?.presentationContextProvider = contextProvider
        webAuthSession?.start()
    }
    
    /// 認可コードをバックエンドサーバーに送信してトークン保存を行う
    private func sendAuthorizationCodeToServer(code: String) async -> String? {
        let backendURL = URL(string: "https://gmail-batch-read.chiaki-621.workers.dev/v1/auth/callback")!
        var request = URLRequest(url: backendURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let clientID = "725405052696-1ijvqnh0b09t9rj9gd032s0aobhvuvrj.apps.googleusercontent.com"
        let redirectURI = "com.taichees.BulkReadGmailForiOS:/oauth2redirect"
        
        struct AuthCallbackRequest: Codable {
            let code: String
            let client_id: String
            let redirect_uri: String
        }
        
        struct AuthCallbackResponse: Codable {
            let success: Bool?
            let user_id: String?
            let error: String?
        }
        
        let reqBody = AuthCallbackRequest(code: code, client_id: clientID, redirect_uri: redirectURI)
        do {
            request.httpBody = try JSONEncoder().encode(reqBody)
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                let res = try JSONDecoder().decode(AuthCallbackResponse.self, from: data)
                if res.success == true {
                    return res.user_id
                } else {
                    print("バックエンドがエラーを返しました: \(res.error ?? "不明なエラー")")
                }
            } else {
                print("HTTPエラー: \(response)")
            }
        } catch {
            print("認証コード送信中にエラーが発生しました: \(error)")
        }
        return nil
    }
}

// ASWebAuthenticationSession の表示コンテキストを提供するためのヘルパークラス
class AuthenticationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
