# GitHub Copilot Usage Notifier

A native macOS menu bar application that displays your GitHub Copilot premium
request usage as a percentage in the menu bar.

## Features

- Displays Copilot premium request usage percentage in the macOS menu bar
- Sign in directly with your GitHub account — no OAuth app or API tokens needed
- Auto-refreshes every 5 minutes
- Manual refresh option
- Lightweight and runs in the background

## Requirements

- macOS 13.0 or later
- Xcode 15 or later (to build from source)
- A GitHub account with an active Copilot subscription

## Setup

### 1. Build the Application

```bash
xcodebuild -project GithubCopilotNotify.xcodeproj \
  -scheme GithubCopilotNotify -configuration Release build
```

Or open the project in Xcode and press **Cmd+B**.

### 2. Run the Application

Launch the built app from Xcode (**Cmd+R**), or open the `.app` bundle from the
Xcode DerivedData folder:

```bash
open ~/Library/Developer/Xcode/DerivedData/GithubCopilotNotify-*/Build/Products/Release/GithubCopilotNotify.app
```

### 3. Sign in to GitHub

On first launch the menu bar will show **🔀 Not Signed In**:

1. Click the menu bar icon
2. Select **Sign in to GitHub**
3. A native window opens with the standard GitHub login page
4. Sign in with your GitHub credentials (supports 2FA, passkeys, and SSO)
5. The window closes automatically once sign-in is detected
6. The menu bar updates to show your current premium request usage (e.g.
   **🔀 7%**)

You can sign out and back in at any time from the menu.

## Usage

Once signed in, the app will:

- Display **🔀 XX%** in the menu bar showing the percentage of your monthly
  Copilot premium requests that have been used
- Update automatically every 5 minutes
- Allow manual refresh via the menu

### Menu Options

- **Refresh Now**: Manually refresh the usage data
- **Sign in to GitHub**: Open the GitHub login window
- **Sign Out**: Clear your session and stop refreshing
- **View on GitHub**: Open your Copilot usage page on GitHub
- **Quit**: Exit the application

## Running at Login (Optional)

To have the app start automatically when you log in:

1. Open **System Settings > General > Login Items**
2. Click the **+** button under "Open at Login"
3. Navigate to and select the `GithubCopilotNotify.app` bundle

## API Endpoint Used

The app calls GitHub's internal entitlement endpoint using your browser session
cookies:

- `GET https://github.com/github-copilot/chat/entitlement`

## Troubleshooting

### "Not Signed In" in menu bar

- Click the menu bar icon and select **Sign in to GitHub**
- Complete the login in the window that appears

### "Session Expired" in menu bar

- Your GitHub session cookies have expired
- Click the menu bar icon and select **Sign in to GitHub** to re-authenticate

### "Error" in menu bar

- Check your internet connection
- Verify your Copilot subscription is active
- Check the Console app for detailed error messages (filter by process
  `GithubCopilotNotify`)

## Development

### Project Structure

```text
GithubCopilotNotify/
├── main.swift                  # Application entry point
├── AppDelegate.swift           # Menu bar UI and app logic
├── CopilotSessionAPI.swift     # GitHub entitlement API client
└── GitHubWebAuthClient.swift   # WebKit-based browser login flow
```

### Building for Distribution

```bash
xcodebuild -project GithubCopilotNotify.xcodeproj \
  -scheme GithubCopilotNotify -configuration Release \
  -arch arm64 -arch x86_64 build
```

## Privacy & Security

- Session cookies are stored securely in the macOS Keychain
- No passwords or tokens are ever stored by the app
- No data is sent to any third-party services — only GitHub's official API is
  used
- Authentication uses the standard GitHub login UI via WebKit (supports 2FA,
  passkeys, and SSO)
- All network requests are made over HTTPS

## License

MIT License - Feel free to use and modify as needed.
