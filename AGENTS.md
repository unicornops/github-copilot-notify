# AGENTS.md - Repository Guide for AI Agents

This document provides comprehensive context for AI agents working with
this repository.

## Project Overview

**Repository**: GitHub Copilot Usage Notifier
**Type**: Native macOS Menu Bar Application
**Language**: Swift
**Platform**: macOS 13.0+
**Purpose**: Display GitHub Copilot premium request usage as a percentage
in the macOS menu bar

## Architecture

### Technology Stack

- **Language**: Swift 5.9+
- **Build System**: Xcode (xcodeproj)
- **UI Framework**: AppKit (Cocoa) + WebKit
- **API**: GitHub Internal API (session-based)
- **Storage**: HTTPCookieStorage for session cookies

### Project Structure

```text
github-copilot-notify/
├── GithubCopilotNotify.xcodeproj/  # Xcode project
├── GithubCopilotNotify/
│   ├── AppDelegate.swift           # Menu bar UI, timer, main app logic
│   ├── CopilotSessionAPI.swift     # GitHub session-based API client
│   ├── GitHubWebAuthClient.swift   # WebKit-based browser login flow
│   ├── CopilotAPI.swift            # Legacy OAuth-based API (unused)
│   ├── GitHubOAuthClient.swift     # Legacy OAuth flow (unused)
│   ├── main.swift                  # Application entry point
│   ├── Info.plist                  # App configuration
│   └── GithubCopilotNotify.entitlements  # App entitlements
├── Assets.xcassets/                # App icon and assets
├── README.md                       # User-facing documentation
├── AGENTS.md                       # This file - agent documentation
├── CLAUDE.md                       # Symlink/reference to AGENTS.md
└── .gitignore                      # Swift/macOS ignore patterns
```

### Key Components

#### 1. CopilotSessionAPI.swift

- **Purpose**: GitHub internal API integration using session cookies
- **Endpoint**: `GET https://github.com/github-copilot/chat/entitlement`
- **Authentication**: Uses HTTPCookieStorage with session cookies
- **Models**:
  - `CopilotEntitlement`: API response with license type, quotas, plan info
  - `CopilotQuotas`: Quota limits and remaining usage
  - `QuotaLimits`: Total premium interactions allowed
  - `QuotaRemaining`: Remaining premium interactions and percentages
- **Key Fields**:
  - `premiumInteractions`: Remaining premium requests
  - `premiumInteractionsPercentage`: Percentage of quota **remaining**
    (e.g., 92.9% means 92.9% left)
  - `resetDate`: When the quota resets (monthly)
  - `overagesEnabled`: Whether overages are enabled
- **Calculation**: `usedPercentage = 100.0 - premiumInteractionsPercentage`
  (API returns remaining, we display used)
- **Error Handling**: Returns 401/403 if cookies expired, user needs to
  re-sign in

#### 2. GitHubWebAuthClient.swift

- **Purpose**: WebKit-based browser authentication flow
- **Technology**: WKWebView for embedded browser
- **Flow**:
  1. Opens native macOS window with GitHub login page
  2. User signs in with username/password (supports 2FA, passkeys, etc.)
  3. Detects successful login by monitoring navigation
  4. Extracts session cookies (`user_session`, `_gh_sess`, etc.)
  5. Saves cookies to HTTPCookieStorage for persistence
  6. Closes window and returns control to app
- **User Experience**: Native macOS window, standard GitHub login UI
- **Security**: Uses nonPersistent WebView session, saves to system cookie
  store
- **Error Handling**: Handles user cancellation, cookie extraction failures

#### 3. AppDelegate.swift

- **Purpose**: Main application logic and UI
- **Responsibilities**:
  - Menu bar status item management
  - Timer-based auto-refresh (5-minute intervals)
  - Web authentication flow coordination
  - Cookie-based session management
- **Menu Items**:
  - "Refresh Now" - Manual refresh trigger
  - "Sign in to GitHub" - Opens WebKit login window
  - "Sign Out" - Clears session cookies
  - "View on GitHub" - Opens github.com/settings/copilot/features in browser
  - "Quit" - Terminate application
- **States**:
  - "Copilot: XX.X%" - Normal operation showing premium request usage
  - "Copilot: Not Signed In" - No session cookies found
  - "Copilot: Signing In..." - During WebKit authentication flow
  - "Copilot: Sign In Failed" - Authentication failure
  - "Copilot: Session Expired" - Cookies expired, need to re-sign in
  - "Copilot: Error" - API failure
  - "Copilot: --" - Initial state

#### 4. CopilotAPI.swift (Legacy - Not Currently Used)

- **Purpose**: OAuth-based organization seat tracking
- **Status**: Kept for reference, not used in current implementation
- **Note**: Organization seat data != individual premium request usage

#### 5. GitHubOAuthClient.swift (Legacy - Not Currently Used)

- **Purpose**: OAuth Device Flow implementation
- **Status**: Kept for reference, not used in current implementation
- **Note**: OAuth tokens cannot access the entitlement endpoint

## Configuration

### HTTPCookieStorage

- Session cookies are stored in `HTTPCookieStorage.shared`
- Key cookies:
  - `user_session`: Main GitHub session identifier
  - `_gh_sess`: GitHub session data
  - `logged_in`: Login status indicator
- Cookies persist between app launches
- Cookies are cleared on "Sign Out"

### Required Permissions

- **None** - Uses standard browser-based authentication
- No OAuth app registration required
- No API tokens required
- User authenticates directly with GitHub in WebKit view

### Environment Variables

None - all authentication via session cookies

## Build and Development

### Building

```bash
# Development build via command line
xcodebuild -project GithubCopilotNotify.xcodeproj \
  -scheme GithubCopilotNotify -configuration Debug build

# Release build via command line
xcodebuild -project GithubCopilotNotify.xcodeproj \
  -scheme GithubCopilotNotify -configuration Release build

# Via Xcode GUI
open GithubCopilotNotify.xcodeproj
# Then: Product -> Build (Cmd+B)
```

### Running

```bash
# From Xcode-built binary (Debug)
open ~/Library/Developer/Xcode/DerivedData/GithubCopilotNotify-*/Build/\
Products/Debug/GithubCopilotNotify.app

# From Xcode-built binary (Release)
open ~/Library/Developer/Xcode/DerivedData/GithubCopilotNotify-*/Build/\
Products/Release/GithubCopilotNotify.app

# Via Xcode GUI
# Product -> Run (Cmd+R)
```

### Testing Locally

1. Build the app with xcodebuild or Xcode
2. Run the app from Xcode or the built .app bundle
3. Click "Sign in to GitHub" from the menu bar
4. Sign in with your GitHub credentials in the WebKit window
5. Verify menu bar shows premium request percentage (e.g., "Copilot: 92.9%")
6. Check Console.app for debug logs if issues occur
   (look for emoji markers like 🔍, ✅, ❌, 🍪)

## API Integration Details

### GitHub Internal API

**Entitlement Endpoint**
(`https://github.com/github-copilot/chat/entitlement`):

- **Authentication**: Session cookies (user_session,_gh_sess)
- **Method**: GET
- **Headers**: `Accept: application/json`
- **Response**: JSON with quota and usage information

### API Response Structure

**Entitlement API Response**:

```json
{
  "licenseType": "licensed_full",
  "quotas": {
    "limits": {
      "premiumInteractions": 1000
    },
    "remaining": {
      "premiumInteractions": 929,
      "chatPercentage": 100.0,
      "premiumInteractionsPercentage": 92.9
    },
    "resetDate": "2026-02-01",
    "overagesEnabled": true
  },
  "plan": "enterprise",
  "trial": {
    "eligible": false
  }
}
```

**Key Fields**:

- `premiumInteractionsPercentage`: Percentage of premium requests
  **remaining** (API value)
- `premiumInteractions`: Absolute number of requests remaining
- `resetDate`: When quota resets (first of month)
- `overagesEnabled`: Whether organization allows overages

**Note**: The API returns percentage **remaining** (free), but the app
displays percentage **used**. The calculation is:
`usedPercentage = 100.0 - premiumInteractionsPercentage`. So if the API
returns 92.9% remaining, the menu bar shows "7.1%" used.

### Error Handling Strategy

1. Check for session cookies before making request
2. Display "Not Signed In" if no cookies found
3. Make entitlement API request with cookies
4. If 401/403 error, display "Session Expired" and prompt re-authentication
5. Display "Error" in menu bar for other failures
6. Log all API responses to console for debugging (with emoji markers)

## Common Tasks for Agents

### Adding New Features

**Add Menu Item**:

1. Add NSMenuItem in `setupMenuBar()` in `AppDelegate.swift`
2. Create `@objc` method for action
3. Connect action to menu item

**Change Refresh Interval**:

- Modify `updateInterval` constant in `AppDelegate.swift`
- Currently set to 300 seconds (5 minutes)

### Common Modifications

**Display Format**:

- Current: `"Copilot: XX.X%"` (shows premium request usage percentage)
- Change in `updateStatusBar(text:)` method
- Consider length (menu bar space is limited)

**Change Displayed Metric**:

- Current: Shows percentage **used** (`100.0 - premiumInteractionsPercentage`)
- Alternative: Show percentage **remaining**
  (`premiumInteractionsPercentage` directly)
- Alternative: Show absolute count (`premiumInteractions remaining`)
- Modify `fetchUsagePercentage()` in `CopilotSessionAPI.swift`

**Add Notification**:

```swift
import UserNotifications
// Request permission and send notification when usage drops below threshold
```

### Debugging Tips

**Check Console Logs**:

```bash
log stream --predicate 'process == "GitHubCopilotNotify"' --level debug
```

Look for emoji markers in logs:

- 🔍 API requests being made
- 📊 API response status codes
- ✅ Successful operations
- ❌ Errors
- ⚠️ Warnings
- 🍪 Cookie operations
- 📍 Navigation events

**Verify Session Cookies**:

```bash
# Check if cookies are stored
defaults read ~/Library/Cookies/Cookies.binarycookies
```

**Test API Manually with Session Cookie**:

```bash
curl -H "Cookie: user_session=YOUR_SESSION_COOKIE" \
     -H "Accept: application/json" \
     https://github.com/github-copilot/chat/entitlement
```

**Inspect Cookies in App**:
Add to `CopilotSessionAPI.swift`:

```swift
if let cookies = HTTPCookieStorage.shared.cookies(
    for: URL(string: "https://github.com")!
) {
    for cookie in cookies {
        print("🍪 \(cookie.name): \(cookie.value.prefix(20))...")
    }
}
```

## Architectural Decisions

### Why AppKit instead of SwiftUI?

- Menu bar apps are well-supported in AppKit
- More control over status item behavior
- Lighter weight for background application

### Why Xcode Project?

- Native macOS app development workflow
- Easy asset management (app icons, etc.)
- Built-in entitlements and code signing
- Better integration with macOS development tools

### Why Timer instead of Background Task?

- Simple refresh needs
- App is always running when user is logged in
- Predictable 5-minute intervals

### Why HTTPCookieStorage instead of Keychain?

- Automatic cookie management by system
- Cookies naturally expire and refresh
- Standard web authentication pattern
- No manual token management needed
- Built-in macOS integration

### Why WebKit instead of OAuth?

- GitHub's entitlement endpoint requires session cookies, not OAuth tokens
- OAuth tokens cannot access internal GitHub APIs
- WebKit provides native, secure browser experience
- Supports all GitHub auth methods (2FA, passkeys, SSO)
- Users trust standard GitHub login UI

## Security Considerations

### Cookie Storage

- **Current**: HTTPCookieStorage (system-managed)
- **Security**: Cookies stored in macOS keychain automatically
- **Expiration**: GitHub session cookies expire after period of inactivity
- **Isolation**: Cookies scoped to github.com domain only

### Authentication Flow

- Uses WebKit WKWebView with nonPersistent() configuration during login
- Cookies saved to persistent storage only after successful authentication
- No password or credentials stored by app
- User authenticates directly with GitHub (supports 2FA, passkeys, SSO)

### Network Security

- All requests over HTTPS
- Uses system URLSession (benefits from macOS security)
- No certificate pinning (trusts system CA)
- Session cookies provide authentication (no bearer tokens)

## Extension Points

### Future Feature Ideas

1. **Multiple Organizations**: Track multiple orgs with switcher
2. **Notifications**: Alert when usage exceeds threshold
3. **History Tracking**: Graph usage over time
4. **Menu Details**: Show breakdown of active vs. inactive seats
5. **Keychain Integration**: Secure token storage
6. **Export**: CSV export of historical data
7. **Themes**: Color-code percentage (green/yellow/red)
8. **Refresh Options**: Configurable refresh interval

### Adding Persistence Layer

If adding history/analytics:

```swift
// Consider Core Data or SQLite
import CoreData
// Create model for UsageSnapshot with timestamp
```

### Adding Charts

If adding visualization:

```swift
// Use Swift Charts (macOS 13+)
import Charts
// Create chart view in menu popover
```

## Dependencies

### Current

- None (pure Swift/AppKit)

### Potential Future Dependencies

- **KeychainAccess**: Secure token storage
- **Alamofire**: Enhanced networking (overkill for current needs)
- **SwiftUI**: If adding preference window
- **Charts**: Usage visualization

## Maintenance Notes

### GitHub API Changes

- Monitor GitHub API changelog: <https://github.blog/changelog/>
- API version pinned to 2022-11-28
- Both endpoints should remain stable

### macOS Compatibility

- Minimum: macOS 13.0 (Ventura)
- Uses standard AppKit APIs (good backwards compatibility)
- Test on major macOS updates

### Swift Version

- Current: 5.9
- Swift is ABI stable (5.0+)
- Package.swift tools version determines minimum

## Known Limitations

1. **Individual User Only**: Shows personal premium request usage,
   not organization metrics
2. **No History**: Only shows current usage snapshot
3. **Session-Based**: Requires periodic re-authentication when cookies expire
4. **Fixed Interval**: 5-minute refresh not configurable via UI
5. **No Offline Mode**: Requires internet connection
6. **macOS Only**: Not cross-platform
7. **Internal API**: Uses GitHub's internal API which may change without
   notice

## Troubleshooting Guide

### "Not Signed In" Shows

- Check if cookies exist: HTTPCookieStorage may be empty
- Click "Sign in to GitHub" to authenticate
- Check Console.app for cookie-related logs (🍪 emoji)

### "Session Expired" Shows

- GitHub session cookies have expired
- Click "Sign in to GitHub" to re-authenticate
- Sessions typically expire after 30-90 days of inactivity

### "Error" Shows

- Check Console.app for error logs (❌ emoji)
- Verify internet connection
- Test API endpoint manually with session cookie
- Check if GitHub is experiencing outages

### Menu Bar Not Showing

- Verify app is running (check Activity Monitor)
- Check menu bar isn't full (macOS hides overflow)
- Try manual refresh from menu

### Build Failures

- Ensure Xcode is installed with Command Line Tools
- Clean build folder: `xcodebuild clean` or Product -> Clean Build Folder
  in Xcode
- Check for missing files in Xcode project navigator
- Verify all Swift files are included in the target's Compile Sources
  build phase

## Code Style Guidelines

### Swift Conventions

- Follow Swift API Design Guidelines
- Use camelCase for properties/methods
- Use PascalCase for types
- Prefer `let` over `var`
- Use explicit types for public APIs

### Structure

- One type per file (with related nested types okay)
- Group related functionality with `// MARK:`
- Private by default, expose only what's needed

### Error Handling

- Use `throws` for recoverable errors
- Log errors with `print()` (consider os_log for production)
- Show user-friendly messages in UI

## Contributing Guidelines

### For Human Contributors

See README.md for user-facing documentation.

### For AI Agents

1. **Read existing code** before suggesting changes
2. **Maintain architectural consistency** with AppKit patterns
3. **Test API changes** with real GitHub organization
4. **Update documentation** when adding features
5. **Follow Swift conventions** outlined above
6. **Consider macOS HIG** for UI changes
7. **Preserve simplicity** - don't over-engineer

## Version History

### v1.0 (Current)

- Initial release
- Basic menu bar display
- 5-minute auto-refresh
- Configuration UI
- Dual API endpoint support

## Contact & Resources

### Documentation

- **Swift**: <https://swift.org/documentation/>
- **AppKit**: <https://developer.apple.com/documentation/appkit>
- **GitHub API**: <https://docs.github.com/en/rest/copilot>

### Repository

- **Issues**: Report bugs and feature requests via GitHub Issues
- **Discussions**: For questions and community support

---

**Last Updated**: 2026-01-13
**Agent Version**: For use with Claude Code and other AI coding assistants
