import Foundation

struct CopilotUsage: Codable {
    let totalSeats: Int
    let seatsWithActivity: Int

    enum CodingKeys: String, CodingKey {
        case totalSeats = "total_seats"
        case seatsWithActivity = "seats_with_activity"
    }

    var usagePercentage: Double {
        guard totalSeats > 0 else { return 0.0 }
        return (Double(seatsWithActivity) / Double(totalSeats)) * 100.0
    }
}

struct SeatBreakdown: Codable {
    let total: Int
    let activeThisCycle: Int
    let inactiveThisCycle: Int
    let pendingInvitation: Int?
    let pendingCancellation: Int?
    let addedThisCycle: Int?

    enum CodingKeys: String, CodingKey {
        case total
        case activeThisCycle = "active_this_cycle"
        case inactiveThisCycle = "inactive_this_cycle"
        case pendingInvitation = "pending_invitation"
        case pendingCancellation = "pending_cancellation"
        case addedThisCycle = "added_this_cycle"
    }
}

struct CopilotBillingUsage: Codable {
    let seatBreakdown: SeatBreakdown

    enum CodingKeys: String, CodingKey {
        case seatBreakdown = "seat_breakdown"
    }

    var usagePercentage: Double {
        guard seatBreakdown.total > 0 else { return 0.0 }
        return (Double(seatBreakdown.activeThisCycle) / Double(seatBreakdown.total)) * 100.0
    }
}

class CopilotAPIClient {
    private let token: String
    private let organization: String

    init(token: String, organization: String) {
        self.token = token
        self.organization = organization
    }

    func fetchUsage() async throws -> Double {
        // Try the billing API first (newer endpoint)
        do {
            let billingUsage = try await fetchBillingUsage()
            let active = billingUsage.seatBreakdown.activeThisCycle
            let total = billingUsage.seatBreakdown.total
            print("✅ Billing API success: \(active)/\(total) = \(billingUsage.usagePercentage)%")
            return billingUsage.usagePercentage
        } catch {
            print("⚠️ Billing API failed: \(error)")
            // Fallback to seats API if billing API fails
            let usage = try await fetchSeatsUsage()
            print("✅ Seats API success: \(usage.seatsWithActivity)/\(usage.totalSeats) = \(usage.usagePercentage)%")
            return usage.usagePercentage
        }
    }

    private func fetchBillingUsage() async throws -> CopilotBillingUsage {
        let urlString = "https://api.github.com/orgs/\(organization)/copilot/billing"
        guard let url = URL(string: urlString) else {
            print("❌ Invalid URL: \(urlString)")
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        print("🔍 Fetching billing API: \(urlString)")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Bad server response (not HTTP)")
            throw URLError(.badServerResponse)
        }

        print("📊 Billing API response status: \(httpResponse.statusCode)")

        if httpResponse.statusCode != 200 {
            if let responseString = String(data: data, encoding: .utf8) {
                print("📄 Error response body: \(responseString)")
            }
            throw URLError(.init(rawValue: httpResponse.statusCode))
        }

        let decoder = JSONDecoder()
        do {
            return try decoder.decode(CopilotBillingUsage.self, from: data)
        } catch {
            print("❌ JSON decode error: \(error)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("📄 Response body: \(responseString)")
            }
            throw error
        }
    }

    private func fetchSeatsUsage() async throws -> CopilotUsage {
        let urlString = "https://api.github.com/orgs/\(organization)/copilot/seats"
        guard let url = URL(string: urlString) else {
            print("❌ Invalid URL: \(urlString)")
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        print("🔍 Fetching seats API: \(urlString)")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Bad server response (not HTTP)")
            throw URLError(.badServerResponse)
        }

        print("📊 Seats API response status: \(httpResponse.statusCode)")

        if httpResponse.statusCode != 200 {
            if let responseString = String(data: data, encoding: .utf8) {
                print("📄 Error response body: \(responseString)")
            }
            throw URLError(.init(rawValue: httpResponse.statusCode))
        }

        let decoder = JSONDecoder()
        do {
            return try decoder.decode(CopilotUsage.self, from: data)
        } catch {
            print("❌ JSON decode error: \(error)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("📄 Response body: \(responseString)")
            }
            throw error
        }
    }
}
