import SwiftUI

struct MainView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var isLoading = false
    @State private var progressText = ""
    @State private var toastMessage: String? = nil
    @State private var showToast = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                VStack {
                    Spacer()
                    
                    // Android版を再現した大きな丸いメインボタン
                    Button {
                        Task { await performBulkRead() }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(isLoading ? Color.gray.opacity(0.4) : Color.red)
                                .frame(width: 240, height: 240)
                                .shadow(color: .red.opacity(0.3), radius: 15, x: 0, y: 10)
                            
                            if isLoading {
                                VStack(spacing: 15) {
                                    ProgressView()
                                        .tint(.white)
                                        .scaleEffect(1.5)
                                    Text(progressText)
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 10)
                                }
                            } else {
                                VStack(spacing: 12) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 60))
                                    Text("すべて既読にする")
                                        .font(.title3.bold())
                                }
                                .foregroundColor(.white)
                            }
                        }
                    }
                    .disabled(isLoading)
                    
                    Text("有料版：一回で全ての未読を処理します")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.top, 30)
                    
                    Spacer()
                }
                .navigationTitle("一括既読プロ")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task {
                                await performLogout()
                            }
                        } label: {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .foregroundColor(.red)
                        }
                    }
                }
                
                // トースト通知のオーバーレイ表示
                if showToast, let message = toastMessage {
                    VStack {
                        Spacer()
                        Text(message)
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 24)
                            .background(Color.black.opacity(0.85))
                            .cornerRadius(25)
                            .shadow(radius: 5)
                            .padding(.bottom, 50)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
        }
    }
    
    /// サーバーサイドAPIの呼び出し処理
    private func performBulkRead() async {
        isLoading = true
        progressText = "アクセストークン確認中..."
        
        guard let accessToken = await authManager.getValidAccessToken() else {
            isLoading = false
            triggerToast(message: "セッションが期限切れです。再ログインしてください。")
            authManager.logout()
            return
        }
        
        progressText = "メール取得中..."
        
        let url = URL(string: "https://gmail-batch-read.chiaki-621.workers.dev/v1/gmail/read-all")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        struct ReadAllRequest: Codable {
            let stream: Bool
        }
        
        let body = ReadAllRequest(stream: true)
        
        do {
            request.httpBody = try JSONEncoder().encode(body)
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                var total = 0
                
                struct ProgressUpdate: Codable {
                    let type: String
                    let total: Int?
                    let completed: Int?
                    let processed_count: Int?
                    let success: Bool?
                    let error: String?
                }
                
                for try await line in bytes.lines {
                    if let data = line.data(using: .utf8),
                       let update = try? JSONDecoder().decode(ProgressUpdate.self, from: data) {
                        
                        await MainActor.run {
                            switch update.type {
                            case "count":
                                total = update.total ?? 0
                                progressText = "既読処理中\n(0 / \(total) 件完了)"
                            case "progress":
                                let completed = update.completed ?? 0
                                progressText = "既読処理中\n(\(completed) / \(total) 件完了)"
                            case "result":
                                let count = update.processed_count ?? 0
                                triggerToast(message: "\(count)件を既読にしました")
                            case "error":
                                triggerToast(message: update.error ?? "エラーが発生しました")
                            default:
                                break
                            }
                        }
                    }
                }
            } else {
                print("Bulk read HTTP Error: \(response)")
                triggerToast(message: "通信エラーが発生しました")
            }
        } catch {
            print("Error: \(error)")
            triggerToast(message: "エラーが発生しました")
        }
        
        isLoading = false
    }
    
    /// トースト通知のアニメーション制御
    private func triggerToast(message: String) {
        toastMessage = message
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showToast = true
        }
        
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showToast = false
                }
            }
        }
    }
    
    /// バックエンドのセッション削除とローカルログアウト
    private func performLogout() async {
        guard let session = KeychainHelper.shared.readSession() else {
            authManager.logout()
            return
        }
        
        let url = URL(string: "https://gmail-batch-read.chiaki-621.workers.dev/v1/auth/logout")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        struct LogoutRequest: Codable {
            let user_id: String
        }
        
        let body = LogoutRequest(user_id: session.userId)
        
        do {
            request.httpBody = try JSONEncoder().encode(body)
            _ = try await URLSession.shared.data(for: request)
        } catch {
            print("Logout request failed: \(error)")
        }
        
        await MainActor.run {
            authManager.logout()
        }
    }
}