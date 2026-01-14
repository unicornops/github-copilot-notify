import Foundation
import AppKit

// GitHub OAuth Device Flow models
struct DeviceCodeResponse: Codable {
    let deviceCode: String
    let userCode: String
    let verificationUri: String
    let expiresIn: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationUri = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }
}

struct AccessTokenResponse: Codable {
    let accessToken: String
    let tokenType: String
    let scope: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
    }
}

struct AccessTokenErrorResponse: Codable {
    let error: String
    let errorDescription: String?
    let errorUri: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
        case errorUri = "error_uri"
    }
}

enum OAuthError: Error, LocalizedError {
    case authorizationPending
    case slowDown
    case expiredToken
    case accessDenied
    case unsupportedGrantType
    case incorrectClientCredentials
    case incorrectDeviceCode
    case deviceFlowDisabled
    case unknown(String)
    case networkError(Error)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .authorizationPending:
            return "Authorization pending - waiting for user to authorize"
        case .slowDown:
            return "Polling too quickly"
        case .expiredToken:
            return "The device code has expired"
        case .accessDenied:
            return "User denied authorization"
        case .unsupportedGrantType:
            return "Unsupported grant type"
        case .incorrectClientCredentials:
            return "Incorrect client credentials"
        case .incorrectDeviceCode:
            return "Incorrect device code"
        case .deviceFlowDisabled:
            return "Device flow is disabled for this application"
        case .unknown(let msg):
            return "Unknown error: \(msg)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from GitHub"
        }
    }
}

class GitHubOAuthClient {
    // GitHub OAuth App credentials
    // Note: For a production app, you should register your own OAuth app at:
    // https://github.com/settings/applications/new
    // For now, using a placeholder - you'll need to register the app
    private let clientId: String

    private let deviceCodeUrl = "https://github.com/login/device/code"
    private let accessTokenUrl = "https://github.com/login/oauth/access_token"

    init(clientId: String) {
        self.clientId = clientId
    }

    /// Step 1: Request a device code from GitHub
    func requestDeviceCode() async throws -> DeviceCodeResponse {
        guard let url = URL(string: deviceCodeUrl) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "client_id": clientId,
            "scope": "copilot read:org"
        ]

        request.httpBody = try JSONEncoder().encode(body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw OAuthError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                throw URLError(.init(rawValue: httpResponse.statusCode))
            }

            let decoder = JSONDecoder()
            return try decoder.decode(DeviceCodeResponse.self, from: data)
        } catch let error as OAuthError {
            throw error
        } catch {
            throw OAuthError.networkError(error)
        }
    }

    /// Step 2: Poll for access token
    func pollForAccessToken(deviceCode: String, interval: Int) async throws -> AccessTokenResponse {
        guard let url = URL(string: accessTokenUrl) else {
            throw URLError(.badURL)
        }

        var pollInterval = interval

        // Poll until we get a token or an error
        while true {
            // Wait for the specified interval
            try await Task.sleep(nanoseconds: UInt64(pollInterval) * 1_000_000_000)

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let body: [String: String] = [
                "client_id": clientId,
                "device_code": deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
            ]

            request.httpBody = try JSONEncoder().encode(body)

            do {
                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw OAuthError.invalidResponse
                }

                if httpResponse.statusCode == 200 {
                    // Success! We got the access token
                    let decoder = JSONDecoder()
                    return try decoder.decode(AccessTokenResponse.self, from: data)
                }

                // Parse error response
                let decoder = JSONDecoder()
                let errorResponse = try decoder.decode(AccessTokenErrorResponse.self, from: data)

                switch errorResponse.error {
                case "authorization_pending":
                    // Continue polling
                    continue
                case "slow_down":
                    // Increase interval by 5 seconds and continue
                    pollInterval += 5
                    continue
                case "expired_token":
                    throw OAuthError.expiredToken
                case "access_denied":
                    throw OAuthError.accessDenied
                case "unsupported_grant_type":
                    throw OAuthError.unsupportedGrantType
                case "incorrect_client_credentials":
                    throw OAuthError.incorrectClientCredentials
                case "incorrect_device_code":
                    throw OAuthError.incorrectDeviceCode
                case "device_flow_disabled":
                    throw OAuthError.deviceFlowDisabled
                default:
                    throw OAuthError.unknown(errorResponse.error)
                }
            } catch let error as OAuthError {
                throw error
            } catch {
                // For other errors, continue polling unless it's a critical error
                print("Polling error: \(error)")
                continue
            }
        }
    }

    /// Complete OAuth flow: request device code and poll for token
    func authenticate() async throws -> String {
        // Step 1: Get device code
        let deviceCodeResponse = try await requestDeviceCode()

        // Step 2: Show code to user and open browser
        await showDeviceCodeToUser(
            userCode: deviceCodeResponse.userCode,
            verificationUri: deviceCodeResponse.verificationUri
        )

        // Step 3: Poll for access token
        let tokenResponse = try await pollForAccessToken(
            deviceCode: deviceCodeResponse.deviceCode,
            interval: deviceCodeResponse.interval
        )

        return tokenResponse.accessToken
    }

    @MainActor
    private func showDeviceCodeToUser(userCode: String, verificationUri: String) {
        // Copy code to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(userCode, forType: .string)

        // Show alert with code
        let alert = NSAlert()
        alert.messageText = "GitHub Authorization"
        alert.informativeText = """
        Your device code is:

        \(userCode)

        The code has been copied to your clipboard.
        Click "Open GitHub" to authorize this app.
        """
        alert.addButton(withTitle: "Open GitHub")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            // Open GitHub authorization page
            if let url = URL(string: verificationUri) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
