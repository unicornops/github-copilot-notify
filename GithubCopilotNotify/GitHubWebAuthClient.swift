import Foundation
import AppKit
import WebKit

class GitHubWebAuthClient: NSObject, WKNavigationDelegate {
    private var window: NSWindow?
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<[String: String], Error>?
    private var didCompleteAuthentication = false
    private var isWindowClosing = false
    private let cookieRetryLimit = 30
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

        // Use default data store for reliable cookie access.
        // Clear GitHub cookies before login to get a fresh session.
        let dataStore = WKWebsiteDataStore.default()
        clearGitHubCookies(from: dataStore)

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1024, height: 768), configuration: configuration)
        webView.navigationDelegate = self
        webView.customUserAgent = "GithubCopilotNotify/1.0 (macOS; WebKit)"

        self.webView = webView

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1024, height: 768),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = "Sign in to GitHub"
        window.contentView = webView
        window.minSize = NSSize(width: 800, height: 600)
        window.center()
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        window.makeKeyAndOrderFront(nil)
        window.delegate = self
        self.window = window

        if let url = URL(string: "https://github.com/login") {
            webView.load(URLRequest(url: url))
        }
    }

    private func clearGitHubCookies(from dataStore: WKWebsiteDataStore) {
        dataStore.httpCookieStore.getAllCookies { cookies in
            for cookie in cookies where cookie.domain.contains("github.com") {
                dataStore.httpCookieStore.delete(cookie)
            }
        }
    }

    // Allow all HTTPS navigations during the login flow.
    // GitHub login may require external domains for CAPTCHA challenges (Turnstile),
    // SSO/SAML providers, and device verification flows.
    // Security is maintained by only extracting github.com cookies after login.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        // Allow all HTTPS navigations
        if url.scheme == "https" {
            decisionHandler(.allow)
            return
        }

        // Allow about:blank (used internally by WebKit)
        if url.scheme == "about" {
            decisionHandler(.allow)
            return
        }

        #if DEBUG
        print("Blocked non-HTTPS navigation: \(url)")
        #endif

        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url,
              let host = url.host,
              host == "github.com" || host.hasSuffix(".github.com"),
              url.scheme == "https" else { return }

        #if DEBUG
        print("Navigated to GitHub path: \(url.path)")
        #endif

        // Don't start extraction on the initial login page load,
        // but always retry on any page (including /sessions pages after 2FA etc.)
        let path = url.path
        let isInitialLoginPage = path == "/login" || path == "/login/"

        if !isInitialLoginPage {
            extractCookies(retryCount: 0)
        }
    }

    private func extractCookies(retryCount: Int) {
        guard !didCompleteAuthentication else { return }

        guard let webView = webView else {
            DispatchQueue.main.async { [weak self] in
                self?.completeAuthentication(with: .failure(AuthError.cookieExtractionFailed))
            }
            return
        }

        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore

        cookieStore.getAllCookies { [weak self] cookies in
            guard let self = self, !self.didCompleteAuthentication else { return }
            self.processCookies(cookies, retryCount: retryCount)
        }
    }

    private func processCookies(_ cookies: [HTTPCookie], retryCount: Int) {
        var cookieDict: [String: String] = [:]
        for cookie in cookies where cookie.domain.contains("github.com") {
            cookieDict[cookie.name] = cookie.value
        }

        #if DEBUG
        print("Cookie check #\(retryCount): found \(cookieDict.count) GitHub cookies")
        #endif

        if hasAuthenticatedSessionCookie(cookieDict) {
            saveAndComplete(cookies: cookies, cookieDict: cookieDict)
        } else {
            scheduleRetry(retryCount: retryCount)
        }
    }

    private func saveAndComplete(cookies: [HTTPCookie], cookieDict: [String: String]) {
        #if DEBUG
        print("Successfully extracted session cookies")
        #endif

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
    }

    private func scheduleRetry(retryCount: Int) {
        #if DEBUG
        print("Session cookie not ready (attempt \(retryCount)/\(cookieRetryLimit))")
        #endif

        guard retryCount < cookieRetryLimit else {
            #if DEBUG
            print("Retry limit reached, waiting for next navigation")
            #endif
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + cookieRetryDelay) { [weak self] in
            guard let self, !self.didCompleteAuthentication else { return }
            self.extractCookies(retryCount: retryCount + 1)
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

    private func closeWindowSync() {
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
