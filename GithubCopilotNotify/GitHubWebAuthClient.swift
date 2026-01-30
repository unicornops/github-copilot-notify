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

        // Create WebView with larger default size for better visibility of security indicators
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1024, height: 768), configuration: configuration)
        webView.navigationDelegate = self

        // Set custom user agent to identify the app for GitHub security monitoring
        webView.customUserAgent = "GithubCopilotNotify/1.0 (macOS; WebKit)"

        self.webView = webView

        // Create window with resizable and miniaturizable styles for accessibility
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1024, height: 768),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sign in to GitHub"
        window.contentView = webView
        window.minSize = NSSize(width: 800, height: 600)  // Minimum size for usability
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.delegate = self
        self.window = window

        // Load GitHub login page
        if let url = URL(string: "https://github.com/login") {
            webView.load(URLRequest(url: url))
        }
    }

    // Restrict navigation to GitHub-owned domains only to prevent malicious redirects
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url,
              let host = url.host else {
            decisionHandler(.cancel)
            return
        }

        // Allow only GitHub-owned domains
        let allowedHosts = ["github.com", "github.githubassets.com", "avatars.githubusercontent.com"]
        let isAllowed = allowedHosts.contains(host) || host.hasSuffix(".github.com")

        #if DEBUG
        if !isAllowed {
            print("Blocked navigation to non-GitHub domain: \(host)")
        }
        #endif

        decisionHandler(isAllowed ? .allow : .cancel)
    }

    // Called when navigation completes
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Check if we're on a GitHub authenticated page using proper URL parsing
        guard let url = webView.url,
              let host = url.host,
              host == "github.com" || host.hasSuffix(".github.com"),
              url.scheme == "https" else { return }

        let path = url.path

        #if DEBUG
        print("Navigated to GitHub path: \(path)")
        #endif

        // If user successfully logged in and reached GitHub.com (not login/sessions pages)
        if !path.hasPrefix("/login") && !path.hasPrefix("/sessions") {
            #if DEBUG
            print("Login detected, extracting cookies...")
            #endif
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
            }

            #if DEBUG
            print("Found \(cookieDict.count) GitHub cookies")
            #endif

            // Check for required cookies
            if cookieDict["user_session"] != nil {
                #if DEBUG
                print("Successfully extracted session cookies")
                #endif

                // Save cookies to persistent store for future use
                self.saveCookiesToPersistentStore(cookies: cookies)

                DispatchQueue.main.async {
                    self.continuation?.resume(returning: cookieDict)
                    self.continuation = nil
                    self.closeWindowSync()
                }
            } else {
                #if DEBUG
                print("No user_session cookie found, waiting for login...")
                #endif
            }
        }
    }

    private func saveCookiesToPersistentStore(cookies: [HTTPCookie]) {
        // Save cookies to Keychain for secure persistence
        do {
            try KeychainCookieStorage.shared.saveCookies(cookies)
            #if DEBUG
            let savedCount = cookies.filter { $0.domain.contains("github.com") }.count
            print("Saved \(savedCount) cookies to Keychain")
            #endif
        } catch {
            #if DEBUG
            print("Failed to save cookies to Keychain: \(error)")
            #endif
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
