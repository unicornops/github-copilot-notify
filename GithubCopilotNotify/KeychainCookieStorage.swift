import Foundation
import Security

/// Serializable cookie representation using only simple types for reliable JSON encoding
private struct SerializableCookie: Codable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let secure: Bool
    let expiresDate: String?  // ISO 8601

    init(from cookie: HTTPCookie) {
        self.name = cookie.name
        self.value = cookie.value
        self.domain = cookie.domain
        self.path = cookie.path
        self.secure = cookie.isSecure
        if let expires = cookie.expiresDate {
            self.expiresDate = ISO8601DateFormatter().string(from: expires)
        } else {
            self.expiresDate = nil
        }
    }

    func toHTTPCookie() -> HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path
        ]
        if secure {
            properties[.secure] = "TRUE"
        }
        if let expiresDate, let date = ISO8601DateFormatter().date(from: expiresDate) {
            properties[.expires] = date
        }
        return HTTPCookie(properties: properties)
    }
}

/// Secure Keychain-based storage for GitHub session cookies
class KeychainCookieStorage {
    static let shared = KeychainCookieStorage()

    private let serviceIdentifier = "ie.unicornops.GithubCopilotNotify"
    private let cookiesAccountKey = "github-session-cookies"  // pragma: allowlist secret

    private init() {}

    /// Save cookies to the Keychain
    /// - Parameter cookies: Array of HTTPCookie objects to store
    func saveCookies(_ cookies: [HTTPCookie]) throws {
        let githubCookies = cookies.filter { $0.domain.contains("github.com") }

        guard !githubCookies.isEmpty else { return }

        let serializableCookies = githubCookies.map { SerializableCookie(from: $0) }
        let cookieData = try JSONEncoder().encode(serializableCookies)

        // Delete any existing entry first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: cookiesAccountKey
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new entry
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: cookiesAccountKey,
            kSecValueData as String: cookieData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)

        if status != errSecSuccess && status != errSecDuplicateItem {
            throw KeychainError.unableToStore(status: status)
        }

        #if DEBUG
        print("Saved \(githubCookies.count) cookies to Keychain")
        #endif
    }

    /// Load cookies from the Keychain
    /// - Returns: Array of HTTPCookie objects, or empty array if none found
    func loadCookies() -> [HTTPCookie] {
        guard let data = loadCookieDataFromKeychain() else {
            return []
        }

        // Try JSON format first (current)
        if let cookies = parseCookiesFromJSON(data), !cookies.isEmpty {
            #if DEBUG
            print("Loaded \(cookies.count) cookies from Keychain")
            #endif
            return cookies
        }

        // Fall back to legacy NSKeyedArchiver format for migration
        if let cookies = parseCookiesFromArchive(data), !cookies.isEmpty {
            #if DEBUG
            print("Migrated \(cookies.count) cookies from legacy format")
            #endif
            // Re-save in new format
            try? saveCookies(cookies)
            return cookies
        }

        return []
    }

    private func loadCookieDataFromKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: cookiesAccountKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            #if DEBUG
            if status != errSecItemNotFound {
                print("Keychain load failed with status: \(status)")
            }
            #endif
            return nil
        }

        return data
    }

    private func parseCookiesFromJSON(_ data: Data) -> [HTTPCookie]? {
        guard let serializableCookies = try? JSONDecoder().decode([SerializableCookie].self, from: data) else {
            return nil
        }

        let cookies = serializableCookies.compactMap { serialized -> HTTPCookie? in
            guard let cookie = serialized.toHTTPCookie() else { return nil }
            // Filter expired cookies
            if let expiresDate = cookie.expiresDate, expiresDate <= Date() {
                return nil
            }
            return cookie
        }

        return cookies
    }

    /// Legacy format support for migration from NSKeyedArchiver
    private func parseCookiesFromArchive(_ data: Data) -> [HTTPCookie]? {
        guard let rawProperties = try? NSKeyedUnarchiver.unarchivedObject(
            ofClasses: [NSArray.self, NSDictionary.self, NSString.self, NSNumber.self, NSDate.self, NSURL.self],
            from: data
        ) as? [Any] else {
            return nil
        }

        return rawProperties.compactMap { rawDict -> HTTPCookie? in
            guard let dict = rawDict as? [AnyHashable: Any] else { return nil }
            var cookieProps: [HTTPCookiePropertyKey: Any] = [:]
            for (key, value) in dict {
                if let stringKey = key as? String {
                    cookieProps[HTTPCookiePropertyKey(stringKey)] = value
                } else if let propKey = key as? HTTPCookiePropertyKey {
                    cookieProps[propKey] = value
                }
            }
            guard let cookie = HTTPCookie(properties: cookieProps) else { return nil }
            if let expiresDate = cookie.expiresDate, expiresDate <= Date() {
                return nil
            }
            return cookie
        }
    }

    /// Delete all stored cookies from the Keychain
    func clearCookies() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: cookiesAccountKey
        ]

        let status = SecItemDelete(query as CFDictionary)

        #if DEBUG
        if status == errSecSuccess {
            print("Cleared cookies from Keychain")
        } else if status != errSecItemNotFound {
            print("Keychain delete returned status: \(status)")
        }
        #endif
    }

    /// Check if we have a valid user_session cookie stored
    func hasValidSession() -> Bool {
        let cookies = loadCookies()
        return hasAuthenticatedSessionCookie(cookies)
    }

    /// Get cookies formatted for URL request
    /// - Parameter url: The URL to get cookies for
    /// - Returns: Dictionary of cookie header fields
    func cookieHeaderFields(for url: URL) -> [String: String] {
        let cookies = loadCookies()
        return HTTPCookie.requestHeaderFields(with: cookies)
    }

    private func hasAuthenticatedSessionCookie(_ cookies: [HTTPCookie]) -> Bool {
        let hasUserSession = cookies.contains { cookie in
            cookie.name == "user_session" || cookie.name.contains("user_session")
        }
        let hasGitHubSession = cookies.contains { $0.name == "_gh_sess" }
        let hasLoggedInMarker = cookies.contains { cookie in
            guard cookie.name == "logged_in" else { return false }
            let value = cookie.value.lowercased()
            return value == "yes" || value == "true" || value == "1"
        }
        return hasUserSession || (hasGitHubSession && hasLoggedInMarker)
    }
}

enum KeychainError: Error, LocalizedError {
    case unableToStore(status: OSStatus)
    case unableToLoad(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .unableToStore(let status):
            return "Unable to store in Keychain (status: \(status))"
        case .unableToLoad(let status):
            return "Unable to load from Keychain (status: \(status))"
        }
    }
}
