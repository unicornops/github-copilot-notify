import Foundation
import AppKit
import WebKit

class GitHubWebAuthClient: NSObject, WKNavigationDelegate {
    private var window: NSWindow?
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<[String: String], Error>?
    private var didCompleteAuthentication = false
    private var isWindowClosing = false
    private let cookieRetryLimit = 20
    private let cookieRetryDelay: TimeInterval = 0.5

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
            self.didCompleteAuthentication = false
            self.showLoginWindow()
        }
    }

    @MainActor
    private func showLoginWindow() {
        isWindowClosing = false

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
        window.isReleasedWhenClosed = false
        window.title = "Sign in to GitHub"
        window.contentView = webView
        window.minSize = NSSize(width: 800, height: 600)  // Minimum size for usability
        window.center()
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
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
        let isSignInPage = path.hasPrefix("/login") || path.hasPrefix("/sessions")

        #if DEBUG
        print("Navigated to GitHub path: \(path)")
        #endif

        // Extract on all GitHub pages, but only retry on post-login pages.
        extractCookies(retryCount: 0, allowRetry: !isSignInPage)
    }

    private func extractCookies(retryCount: Int, allowRetry: Bool) {
        guard let webView = webView else {
            DispatchQueue.main.async { [weak self] in
                self?.completeAuthentication(with: .failure(AuthError.cookieExtractionFailed))
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

            if self.hasAuthenticatedSessionCookie(cookieDict) {
                #if DEBUG
                print("Successfully extracted session cookies")
                #endif

                // Save cookies to persistent store - fail auth if save fails
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
                    DispatchQueue.main.async {
                        self.completeAuthentication(with: .failure(AuthError.cookieExtractionFailed))
                    }
                    return
                }

                DispatchQueue.main.async {
                    self.completeAuthentication(with: .success(cookieDict))
                }
            } else {
                #if DEBUG
                let cookieNames = cookieDict.keys.sorted().joined(separator: ", ")
                print("Session cookie not ready yet. Names: [\(cookieNames)]")
                #endif
                self.retryCookieExtractionIfNeeded(retryCount: retryCount, allowRetry: allowRetry)
            }
        }
    }

    private func hasAuthenticatedSessionCookie(_ cookieDict: [String: String]) -> Bool {
        let hasUserSession = cookieDict.keys.contains { name in
            name == "user_session" || name.contains("user_session")
        }
        let hasGitHubSession = cookieDict["_gh_sess"] != nil
        let loggedInValue = cookieDict["logged_in"]?.lowercased()
        let hasLoggedInMarker = loggedInValue == "yes" || loggedInValue == "true" || loggedInValue == "1"
        return hasUserSession || (hasGitHubSession && hasLoggedInMarker)
    }

    private func retryCookieExtractionIfNeeded(retryCount: Int, allowRetry: Bool) {
        guard allowRetry, !didCompleteAuthentication else { return }
        guard retryCount < cookieRetryLimit else {
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.didCompleteAuthentication else { return }
                self.completeAuthentication(with: .failure(AuthError.cookieExtractionFailed))
            }
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + cookieRetryDelay) { [weak self] in
            guard let self, !self.didCompleteAuthentication else { return }
            self.extractCookies(retryCount: retryCount + 1, allowRetry: allowRetry)
        }
    }

    private func closeWindowSync() {
        // Must be called from main thread
        assert(Thread.isMainThread, "closeWindowSync must be called from main thread")
        guard let window else {
            cleanupWindowReferences()
            return
        }

        if isWindowClosing {
            cleanupWindowReferences()
            return
        }

        isWindowClosing = true
        window.delegate = nil
        window.orderOut(nil)
        window.close()
        cleanupWindowReferences()
    }

    private func cleanupWindowReferences() {
        window?.delegate = nil
        webView?.navigationDelegate = nil
        window = nil
        webView = nil
    }

    private func completeAuthentication(
        with result: Result<[String: String], Error>,
        shouldCloseWindow: Bool = true
    ) {
        assert(Thread.isMainThread, "completeAuthentication must be called from main thread")
        guard !didCompleteAuthentication else { return }
        didCompleteAuthentication = true

        switch result {
        case .success(let cookies):
            continuation?.resume(returning: cookies)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
        continuation = nil
        if shouldCloseWindow {
            closeWindowSync()
        } else {
            cleanupWindowReferences()
        }
    }
}

// Window delegate to handle window closure
extension GitHubWebAuthClient: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        isWindowClosing = true
        completeAuthentication(with: .failure(AuthError.userCancelled), shouldCloseWindow: false)
    }
}
