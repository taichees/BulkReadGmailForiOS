import Foundation

struct UserSession: Codable {
    let userId: String
    let accessToken: String
    let refreshToken: String?
    let expiryDate: Double // Unix timestamp in seconds
}
