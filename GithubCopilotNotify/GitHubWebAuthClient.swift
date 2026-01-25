import Foundation
import AppKit
import WebKit

class GitHubWebAuthClient: NSObject, WKNavigationDelegate {
    private var window: NSWindow?
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<[String: String], Error>?

    enum AuthError: Error, LocalizedError {
        case userCancelled
        case cookieExtractionFailed
        case windowCreationFailed

        var errorDescription: String? {
            switch self {
            case .userCancelled:
                return "Authentication was cancelled"
            case .cookieExtractionFailed:
                return "Failed to extract session cookies"
            case .windowCreationFailed:
                return "Failed to create authentication window"
            }
        }
    }

    @MainActor
    func authenticate() async throws -> [String: String] {
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.showLoginWindow()
        }
    }

    @MainActor
    private func showLoginWindow() {
        // Create WebView configuration
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent() // Use fresh session each time

        // Create WebView
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        webView.navigationDelegate = self
        self.webView = webView

        // Create window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sign in to GitHub"
        window.contentView = webView
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.delegate = self
        self.window = window

        // Load GitHub login page
        if let url = URL(string: "https://github.com/login") {
            webView.load(URLRequest(url: url))
        }
    }

    // Called when navigation completes
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Check if we're on a GitHub authenticated page
        guard let url = webView.url?.absoluteString else { return }

        print("📍 Navigated to: \(url)")

        // If user successfully logged in and reached GitHub.com
        if url.hasPrefix("https://github.com/") && !url.contains("/login") && !url.contains("/sessions") {
            print("✅ Login detected, extracting cookies...")
            extractCookies()
        }
    }

    private func extractCookies() {
        guard let webView = webView else {
            DispatchQueue.main.async { [weak self] in
                self?.continuation?.resume(throwing: AuthError.cookieExtractionFailed)
                self?.continuation = nil
                self?.closeWindowSync()
            }
            return
        }

        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore

        cookieStore.getAllCookies { [weak self] cookies in
            guard let self = self else { return }

            var cookieDict: [String: String] = [:]

            for cookie in cookies where cookie.domain.contains("github.com") {
                cookieDict[cookie.name] = cookie.value
                print("🍪 Found cookie: \(cookie.name)")
            }

            // Check for required cookies
            if cookieDict["user_session"] != nil {
                print("✅ Successfully extracted session cookies")

                // Save cookies to persistent store for future use
                self.saveCookiesToPersistentStore(cookies: cookies)

                DispatchQueue.main.async {
                    self.continuation?.resume(returning: cookieDict)
                    self.continuation = nil
                    self.closeWindowSync()
                }
            } else {
                print("⚠️ No user_session cookie found, waiting for login...")
            }
        }
    }

    private func saveCookiesToPersistentStore(cookies: [HTTPCookie]) {
        // Save cookies to default cookie storage so they persist
        let cookieStorage = HTTPCookieStorage.shared

        for cookie in cookies where cookie.domain.contains("github.com") {
            cookieStorage.setCookie(cookie)
            print("💾 Saved cookie to persistent store: \(cookie.name)")
        }
    }

    private func closeWindowSync() {
        // Must be called from main thread
        assert(Thread.isMainThread, "closeWindowSync must be called from main thread")
        window?.close()
        window = nil
        webView = nil
    }
}

// Window delegate to handle window closure
extension GitHubWebAuthClient: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        if continuation != nil {
            continuation?.resume(throwing: AuthError.userCancelled)
            continuation = nil
        }
    }
}
