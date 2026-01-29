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
    private let keychainStorage: KeychainCookieStorage
    private let entitlementURL = "https://github.com/github-copilot/chat/entitlement"

    init() {
        self.keychainStorage = KeychainCookieStorage.shared
    }

    private func createEntitlementRequest() throws -> URLRequest {
        guard let url = URL(string: entitlementURL) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let cookieHeaders = keychainStorage.cookieHeaderFields(for: url)
        for (key, value) in cookieHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        #if DEBUG
        print("Making entitlement request with cookies")
        #endif

        return request
    }

    private func handleResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            #if DEBUG
            print("Bad server response (not HTTP)")
            #endif
            throw URLError(.badServerResponse)
        }

        #if DEBUG
        print("Entitlement API response status: \(httpResponse.statusCode)")
        #endif

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            #if DEBUG
            print("Authentication failed - cookies may be expired")
            #endif
            throw URLError(.userAuthenticationRequired)
        }

        guard httpResponse.statusCode == 200 else {
            #if DEBUG
            if let responseString = String(data: data, encoding: .utf8) {
                print("Error response body: \(responseString)")
            }
            #endif
            throw URLError(.init(rawValue: httpResponse.statusCode))
        }
    }

    private func parseEntitlement(from data: Data) throws -> Double {
        do {
            let entitlement = try JSONDecoder().decode(CopilotEntitlement.self, from: data)
            let remainingPercentage = entitlement.quotas.remaining.premiumInteractionsPercentage
            let usedPercentage = 100.0 - remainingPercentage

            #if DEBUG
            let remaining = entitlement.quotas.remaining.premiumInteractions
            let limit = entitlement.quotas.limits.premiumInteractions
            print("Premium requests: \(remaining)/\(limit)")
            print("Remaining: \(remainingPercentage)% | Used: \(usedPercentage)%")
            print("Reset date: \(entitlement.quotas.resetDate)")
            #endif

            return usedPercentage
        } catch {
            #if DEBUG
            print("JSON decode error: \(error)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("Response body: \(responseString)")
            }
            #endif
            throw error
        }
    }

    func fetchUsagePercentage() async throws -> Double {
        let request = try createEntitlementRequest()
        let (data, response) = try await URLSession.shared.data(for: request)
        try handleResponse(response, data: data)
        return try parseEntitlement(from: data)
    }

    func hasCookies() -> Bool {
        return keychainStorage.hasValidSession()
    }

    func clearCookies() {
        keychainStorage.clearCookies()
        #if DEBUG
        print("Cleared all GitHub cookies from Keychain")
        #endif
    }
}
