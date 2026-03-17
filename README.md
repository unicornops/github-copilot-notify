# GitHub Copilot Usage Notifier

> A lightweight native macOS menu bar app that shows your GitHub
> Copilot premium request usage at a glance.

## Screenshot

![GitHub Copilot Usage Notifier showing 11% usage in the macOS menu bar](screenshots/menu-bar-screenshot.png)

## Features

- 🔀 Displays your Copilot premium request usage percentage right in the menu bar
- 🔐 Sign in with your GitHub account — no OAuth app or API tokens needed
- ♻️ Auto-refreshes every 5 minutes
- 🖱️ Manual refresh available any time from the menu
- 🪶 Lightweight and runs quietly in the background

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15 or later (to build from source)
- A GitHub account with an active Copilot subscription

## Getting Started

### 1. Build the App

Open the project in Xcode and press **Cmd+B**, or build from the command line:

```bash
xcodebuild -project GithubCopilotNotify.xcodeproj \
  -scheme GithubCopilotNotify -configuration Release build
```

### 2. Run the App

Launch from Xcode with **Cmd+R**, or open the built bundle directly:

```bash
open ~/Library/Developer/Xcode/DerivedData/GithubCopilotNotify-*/Build/Products/Release/GithubCopilotNotify.app
```

### 3. Sign in to GitHub

On first launch the menu bar will show **🔀 Not Signed In**:

1. Click the menu bar icon
2. Select **Sign in to GitHub**
3. A native window opens with the standard GitHub login page
4. Sign in with your credentials — 2FA, passkeys, and SSO are all supported
5. The window closes automatically once sign-in is complete
6. The menu bar updates to show your usage (e.g. **🔀 11%**)

You can sign out and back in at any time from the menu.

## Usage

Once signed in, the app displays **🔀 XX%** in your menu bar — the
percentage of your monthly Copilot premium requests that have been used.
It refreshes automatically every 5 minutes.

### Menu Options

| Option | Description |
| --- | --- |
| **Refresh Now** | Manually fetch the latest usage data |
| **Sign in to GitHub** | Open the GitHub login window |
| **Sign Out** | Clear your session and stop refreshing |
| **View on GitHub** | Open your Copilot usage page on GitHub |
| **Quit** | Exit the application |

## Launch at Login (Optional)

To start the app automatically when you log in:

1. Open **System Settings → General → Login Items**
2. Click **+** under "Open at Login"
3. Select `GithubCopilotNotify.app`

## Privacy & Security

- 🔒 Session cookies are stored securely by macOS — no passwords or
  tokens are ever stored by the app
- 🌐 Only GitHub's own API is used — no data is sent to any third-party services
- ✅ Authentication uses the standard GitHub login UI via WebKit (2FA,
  passkeys, and SSO all work)
- 🔐 All network requests are made over HTTPS

## Troubleshooting

### "Not Signed In" in the menu bar

Click the menu bar icon and select **Sign in to GitHub**, then complete
the login in the window that appears.

### "Session Expired" in the menu bar

Your GitHub session cookies have expired. Click the menu bar icon and
select **Sign in to GitHub** to re-authenticate.

### "Error" in the menu bar

- Check your internet connection
- Verify your Copilot subscription is active on
  [github.com/settings/copilot](https://github.com/settings/copilot)
- Open **Console.app** and filter by process
  `GithubCopilotNotify` for detailed error messages

## Development

### Project Structure

```text
GithubCopilotNotify/
├── main.swift                  # Application entry point
├── AppDelegate.swift           # Menu bar UI and app logic
├── CopilotSessionAPI.swift     # GitHub entitlement API client
└── GitHubWebAuthClient.swift   # WebKit-based browser login flow
```

### Building a Universal Binary

```bash
xcodebuild -project GithubCopilotNotify.xcodeproj \
  -scheme GithubCopilotNotify -configuration Release \
  -arch arm64 -arch x86_64 build
```

## License

GNU General Public License v3.0 — see the [LICENSE](LICENSE) file for details.
