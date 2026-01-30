import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var sessionAPIClient: CopilotSessionAPIClient!
    private var webAuthClient: GitHubWebAuthClient!
    private var updateTimer: Timer?
    private let updateInterval: TimeInterval = 300 // 5 minutes

    func applicationDidFinishLaunching(_ notification: Notification) {
        sessionAPIClient = CopilotSessionAPIClient()
        webAuthClient = GitHubWebAuthClient()
        setupMenuBar()
        startUpdating()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.title = "🔀 --"
        }

        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Sign in to GitHub", action: #selector(signIn), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Sign Out", action: #selector(signOut), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "View on GitHub", action: #selector(openGitHubSettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    private func startUpdating() {
        stopUpdating() // Clear any existing timer

        // Only start timer if authenticated
        guard sessionAPIClient.hasCookies() else {
            updateStatusBar(text: "Not Signed In")
            return
        }

        Task {
            await updateUsage()
        }

        updateTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            Task {
                await self?.updateUsage()
            }
        }
    }

    private func stopUpdating() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    private func updateUsage() async {
        // Check if we have cookies
        guard sessionAPIClient.hasCookies() else {
            updateStatusBar(text: "Not Signed In")
            return
        }

        do {
            let percentage = try await sessionAPIClient.fetchUsagePercentage()
            updateStatusBar(text: String(format: "%.0f%%", percentage))
        } catch let error as URLError {
            // Handle specific URL errors for better user feedback
            switch error.code {
            case .userAuthenticationRequired:
                updateStatusBar(text: "Session Expired")
                stopUpdating()  // Stop polling when session is expired
            case .notConnectedToInternet, .networkConnectionLost:
                updateStatusBar(text: "Offline")
            case .timedOut:
                updateStatusBar(text: "Timeout")
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                updateStatusBar(text: "No Connection")
            case .secureConnectionFailed, .serverCertificateUntrusted:
                updateStatusBar(text: "Security Error")
            default:
                updateStatusBar(text: "Error")
            }
            #if DEBUG
            print("API error (\(error.code.rawValue)): \(error.localizedDescription)")
            #endif
        } catch {
            // Handle non-URLError cases (e.g., JSON decoding errors)
            updateStatusBar(text: "Error")
            #if DEBUG
            print("Failed to fetch usage: \(error)")
            #endif
        }
    }

    private func updateStatusBar(text: String) {
        DispatchQueue.main.async { [weak self] in
            if let button = self?.statusItem.button {
                button.title = "🔀 \(text)"
            }
        }
    }

    @objc private func refreshNow() {
        Task {
            await updateUsage()
        }
    }

    @objc private func signIn() {
        Task {
            await performWebAuth()
        }
    }

    @objc private func signOut() {
        stopUpdating() // Stop timer when signing out
        sessionAPIClient.clearCookies()
        updateStatusBar(text: "Signed Out")

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Signed Out"
            alert.informativeText = "You have been signed out of GitHub. Sign in again to view your Copilot usage."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    @objc private func openGitHubSettings() {
        if let url = URL(string: "https://github.com/settings/copilot/features") {
            NSWorkspace.shared.open(url)
        }
    }

    private func performWebAuth() async {
        do {
            updateStatusBar(text: "Signing In...")

            let cookies = try await webAuthClient.authenticate()

            print("✅ Received \(cookies.count) cookies from authentication")

            // Cookies are automatically saved to Keychain by GitHubWebAuthClient
            // Restart the timer and fetch usage
            startUpdating()

            DispatchQueue.main.async {
                self.showSuccess(message: "Successfully signed in to GitHub!")
            }
        } catch {
            print("Web auth error: \(error)")
            updateStatusBar(text: "Sign In Failed")

            DispatchQueue.main.async {
                self.showError(message: "Failed to sign in: \(error.localizedDescription)")
            }
        }
    }

    private func showError(message: String) {
        let alert = NSAlert()
        alert.messageText = "Error"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showSuccess(message: String) {
        let alert = NSAlert()
        alert.messageText = "Success"
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopUpdating()
    }
}
