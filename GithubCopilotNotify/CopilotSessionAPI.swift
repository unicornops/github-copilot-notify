import Foundation
import Network
import CryptoKit

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

enum CertificatePinningError: Error, LocalizedError {
    case failedToConnect
    case trustEvaluationFailed
    case pinMismatch
    case connectionCancelled

    var errorDescription: String? {
        switch self {
        case .failedToConnect:
            return "Failed to establish TLS connection for pin validation"
        case .trustEvaluationFailed:
            return "TLS trust evaluation failed"
        case .pinMismatch:
            return "Certificate pin validation failed"
        case .connectionCancelled:
            return "TLS connection was cancelled"
        }
    }
}

final class GitHubCertificatePinner {
    // GitHub certificate chain SPKI pins (SHA-256, base64) captured from live chain.
    // Includes leaf + intermediate + root; any chain key match is accepted.
    private let allowedSPKISHA256Base64: Set<String> = [
        // github.com leaf key (2026-03-01)
        "HKlrX9VOPI9IC6usNi99M9wgWigfPdJmPCF7IPg0BVE=", // pragma: allowlist secret
        // Sectigo Public Server Authentication CA DV E36
        "ZSagvDzjltLkewXEBuDxIzpW/dpVw1Juvvmd0hhkzdY=", // pragma: allowlist secret
        // Sectigo Public Server Authentication Root E46
        "sLVjNUaFYfW7n6EtgBeEpjOlcnBdNPMrZDRF36iwBdE=" // pragma: allowlist secret
    ]

    private let host = "github.com"
    private let validationTTL: TimeInterval = 600 // 10 minutes
    private let stateQueue = DispatchQueue(label: "ie.unicornops.githubcopilotnotify.pinning.state")
    private var lastValidationAt: Date?

    private final class CompletionGate: @unchecked Sendable {
        private let lock = NSLock()
        private var isCompleted = false

        func markIfNeeded() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !isCompleted else { return false }
            isCompleted = true
            return true
        }
    }

    func validateIfNeeded() async throws {
        if isValidationFresh() {
            return
        }

        try await validateTLSConnection()
        markValidationSuccess()
    }

    private func isValidationFresh() -> Bool {
        stateQueue.sync {
            guard let lastValidationAt else { return false }
            return Date().timeIntervalSince(lastValidationAt) < validationTTL
        }
    }

    private func markValidationSuccess() {
        stateQueue.sync {
            lastValidationAt = Date()
        }
    }

    private func validateTLSConnection() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let completionQueue = DispatchQueue(label: "ie.unicornops.githubcopilotnotify.pinning.verify")
            let tlsOptions = NWProtocolTLS.Options()
            let secOptions = tlsOptions.securityProtocolOptions

            sec_protocol_options_set_verify_block(secOptions, { [weak self] _, trust, complete in
                guard let self else {
                    complete(false)
                    return
                }
                let trustRef = sec_trust_copy_ref(trust).takeRetainedValue()

                if self.isTrustValidAndPinned(trust: trustRef) {
                    complete(true)
                } else {
                    complete(false)
                }
            }, completionQueue)

            let parameters = NWParameters(tls: tlsOptions, tcp: NWProtocolTCP.Options())
            let connection = NWConnection(host: NWEndpoint.Host(host), port: 443, using: parameters)
            let completionGate = CompletionGate()

            @Sendable func completeOnce(_ result: Result<Void, Error>) {
                guard completionGate.markIfNeeded() else { return }
                connection.cancel()
                continuation.resume(with: result)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    completeOnce(.success(()))
                case .failed(let error):
                    #if DEBUG
                    print("Pinning connection failed: \(error)")
                    #endif
                    completeOnce(.failure(CertificatePinningError.failedToConnect))
                case .cancelled:
                    completeOnce(.failure(CertificatePinningError.connectionCancelled))
                default:
                    break
                }
            }

            connection.start(queue: completionQueue)
        }
    }

    private func isTrustValidAndPinned(trust: SecTrust) -> Bool {
        let sslPolicy = SecPolicyCreateSSL(true, host as CFString)
        SecTrustSetPolicies(trust, sslPolicy)

        var error: CFError?
        guard SecTrustEvaluateWithError(trust, &error) else {
            #if DEBUG
            print("Pinning trust evaluation failed: \(String(describing: error))")
            #endif
            return false
        }

        let chain = (SecTrustCopyCertificateChain(trust) as? [SecCertificate]) ?? []
        guard !chain.isEmpty else { return false }

        for certificate in chain {
            guard let key = SecCertificateCopyKey(certificate),
                  let keyData = SecKeyCopyExternalRepresentation(key, nil) as Data?
            else {
                continue
            }

            let hash = Data(SHA256.hash(data: keyData)).base64EncodedString()
            if allowedSPKISHA256Base64.contains(hash) {
                return true
            }
        }

        return false
    }
}

class CopilotSessionAPIClient {
    private let keychainStorage: KeychainCookieStorage
    private let entitlementURL = "https://github.com/github-copilot/chat/entitlement"
    private let certificatePinner: GitHubCertificatePinner

    init() {
        self.keychainStorage = KeychainCookieStorage.shared
        self.certificatePinner = GitHubCertificatePinner()
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
        try await certificatePinner.validateIfNeeded()
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
