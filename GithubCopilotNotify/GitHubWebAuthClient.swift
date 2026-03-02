import Foundation
import AppKit
import WebKit

class GitHubWebAuthClient: NSObject, WKNavigationDelegate {
    private var window: NSWindow?
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<[String: String], Error>?
    private var didCompleteAuthentication = false

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
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 1024, height: 768),
            configuration: configuration
        )
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

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url,
              let host = url.host else {
            decisionHandler(.cancel)
            return
        }

        let allowedHosts = [
            "github.com",
            "github.githubassets.com",
            "avatars.githubusercontent.com"
        ]
        let isAllowed = allowedHosts.contains(host)
            || host.hasSuffix(".github.com")

        #if DEBUG
        if !isAllowed {
            print("Blocked navigation to non-GitHub domain: \(host)")
        }
        #endif

        decisionHandler(isAllowed ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url,
              let host = url.host,
              host == "github.com" || host.hasSuffix(".github.com"),
              url.scheme == "https" else { return }

        let path = url.path

        #if DEBUG
        print("Navigated to GitHub path: \(path)")
        #endif

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
                self?.completeAuth(
                    with: .failure(AuthError.cookieExtractionFailed)
                )
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

            if cookieDict["user_session"] != nil {
                #if DEBUG
                print("Successfully extracted session cookies")
                #endif
                self.saveCookiesToKeychain(cookies: cookies)
                DispatchQueue.main.async {
                    self.completeAuth(with: .success(cookieDict))
                }
            } else {
                #if DEBUG
                print("No user_session cookie found, waiting...")
                #endif
            }
        }
    }

    private func saveCookiesToKeychain(cookies: [HTTPCookie]) {
        do {
            try KeychainCookieStorage.shared.saveCookies(cookies)
            #if DEBUG
            let count = cookies.filter { $0.domain.contains("github.com") }.count
            print("Saved \(count) cookies to Keychain")
            #endif
        } catch {
            #if DEBUG
            print("Failed to save cookies to Keychain: \(error)")
            #endif
        }
    }

    private func completeAuth(with result: Result<[String: String], Error>) {
        assert(Thread.isMainThread)
        guard !didCompleteAuthentication else { return }
        didCompleteAuthentication = true

        switch result {
        case .success(let cookies):
            continuation?.resume(returning: cookies)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
        continuation = nil

        window?.delegate = nil
        window?.close()
        webView?.navigationDelegate = nil
        window = nil
        webView = nil
    }
}

extension GitHubWebAuthClient: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        completeAuth(with: .failure(AuthError.userCancelled))
    }
}
