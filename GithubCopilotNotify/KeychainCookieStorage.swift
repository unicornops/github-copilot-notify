import Foundation
import Security

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

        // Convert cookies to archivable data
        var cookieProperties: [[HTTPCookiePropertyKey: Any]] = []
        for cookie in githubCookies {
            if let properties = cookie.properties {
                cookieProperties.append(properties)
            }
        }

        let cookieData = try NSKeyedArchiver.archivedData(
            withRootObject: cookieProperties,
            requiringSecureCoding: false
        )

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

        guard let cookies = parseCookiesFromData(data) else {
            return []
        }

        #if DEBUG
        print("Loaded \(cookies.count) cookies from Keychain")
        #endif

        return cookies
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

    private func parseCookiesFromData(_ data: Data) -> [HTTPCookie]? {
        do {
            guard let rawProperties = try NSKeyedUnarchiver.unarchivedObject(
                ofClasses: [NSArray.self, NSDictionary.self, NSString.self, NSNumber.self, NSDate.self],
                from: data
            ) as? [Any] else {
                return nil
            }

            return rawProperties.compactMap { rawDict -> HTTPCookie? in
                guard let dict = rawDict as? [AnyHashable: Any] else { return nil }
                let cookieProps = convertToCookieProperties(dict)
                return createValidCookie(from: cookieProps)
            }
        } catch {
            #if DEBUG
            print("Failed to unarchive cookies: \(error)")
            #endif
            return nil
        }
    }

    private func convertToCookieProperties(_ dict: [AnyHashable: Any]) -> [HTTPCookiePropertyKey: Any] {
        var cookieProps: [HTTPCookiePropertyKey: Any] = [:]
        for (key, value) in dict {
            if let stringKey = key as? String {
                cookieProps[HTTPCookiePropertyKey(stringKey)] = value
            } else if let propKey = key as? HTTPCookiePropertyKey {
                cookieProps[propKey] = value
            }
        }
        return cookieProps
    }

    private func createValidCookie(from properties: [HTTPCookiePropertyKey: Any]) -> HTTPCookie? {
        guard let cookie = HTTPCookie(properties: properties) else { return nil }

        // Session cookies (no expiry) are always valid
        guard let expiresDate = cookie.expiresDate else { return cookie }

        // Check if cookie is not expired
        return expiresDate > Date() ? cookie : nil
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
        return cookies.contains { $0.name == "user_session" }
    }

    /// Get cookies formatted for URL request
    /// - Parameter url: The URL to get cookies for
    /// - Returns: Dictionary of cookie header fields
    func cookieHeaderFields(for url: URL) -> [String: String] {
        let cookies = loadCookies()
        return HTTPCookie.requestHeaderFields(with: cookies)
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
