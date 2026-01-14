import Foundation

// Copilot entitlement response structure
struct CopilotEntitlement: Codable {
    let licenseType: String
    let quotas: CopilotQuotas
    let plan: String
    let trial: CopilotTrial

    enum CodingKeys: String, CodingKey {
        case licenseType
        case quotas
        case plan
        case trial
    }
}

struct CopilotQuotas: Codable {
    let limits: QuotaLimits
    let remaining: QuotaRemaining
    let resetDate: String
    let overagesEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case limits
        case remaining
        case resetDate
        case overagesEnabled
    }
}

struct QuotaLimits: Codable {
    let premiumInteractions: Int

    enum CodingKeys: String, CodingKey {
        case premiumInteractions
    }
}

struct QuotaRemaining: Codable {
    let premiumInteractions: Int
    let chatPercentage: Double
    let premiumInteractionsPercentage: Double

    enum CodingKeys: String, CodingKey {
        case premiumInteractions
        case chatPercentage
        case premiumInteractionsPercentage
    }
}

struct CopilotTrial: Codable {
    let eligible: Bool
}

class CopilotSessionAPIClient {
    private let cookieStorage: HTTPCookieStorage

    init() {
        self.cookieStorage = HTTPCookieStorage.shared
    }

    func fetchUsagePercentage() async throws -> Double {
        let urlString = "https://github.com/github-copilot/chat/entitlement"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Add cookies to request
        if let cookies = cookieStorage.cookies(for: url) {
            let cookieHeaders = HTTPCookie.requestHeaderFields(with: cookies)
            for (key, value) in cookieHeaders {
                request.setValue(value, forHTTPHeaderField: key)
            }
            print("🔍 Making entitlement request with \(cookies.count) cookies")
        } else {
            print("⚠️ No cookies found for GitHub")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Bad server response (not HTTP)")
            throw URLError(.badServerResponse)
        }

        print("📊 Entitlement API response status: \(httpResponse.statusCode)")

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            print("❌ Authentication failed - cookies may be expired")
            if let responseString = String(data: data, encoding: .utf8) {
                print("📄 Response: \(responseString)")
            }
            throw URLError(.userAuthenticationRequired)
        }

        guard httpResponse.statusCode == 200 else {
            if let responseString = String(data: data, encoding: .utf8) {
                print("📄 Error response body: \(responseString)")
            }
            throw URLError(.init(rawValue: httpResponse.statusCode))
        }

        let decoder = JSONDecoder()
        do {
            let entitlement = try decoder.decode(CopilotEntitlement.self, from: data)
            let remainingPercentage = entitlement.quotas.remaining.premiumInteractionsPercentage

            // API returns percentage REMAINING, we want to show percentage USED
            let usedPercentage = 100.0 - remainingPercentage

            print("✅ Premium requests: \(entitlement.quotas.remaining.premiumInteractions)/\(entitlement.quotas.limits.premiumInteractions)")
            print("📊 Remaining: \(remainingPercentage)% | Used: \(usedPercentage)%")
            print("📅 Reset date: \(entitlement.quotas.resetDate)")

            return usedPercentage
        } catch {
            print("❌ JSON decode error: \(error)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("📄 Response body: \(responseString)")
            }
            throw error
        }
    }

    func hasCookies() -> Bool {
        guard let url = URL(string: "https://github.com") else { return false }
        guard let cookies = cookieStorage.cookies(for: url) else { return false }

        return cookies.contains { $0.name == "user_session" }
    }

    func clearCookies() {
        guard let url = URL(string: "https://github.com") else { return }
        guard let cookies = cookieStorage.cookies(for: url) else { return }

        for cookie in cookies {
            cookieStorage.deleteCookie(cookie)
        }

        print("🗑️ Cleared all GitHub cookies")
    }
}
