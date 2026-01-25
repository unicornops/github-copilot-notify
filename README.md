# GitHub Copilot Usage Notifier

A native macOS menu bar application that displays GitHub Copilot usage as a
percentage in the notification bar.

## Features

- Displays GitHub Copilot usage percentage in the macOS menu bar
- Auto-refreshes every 5 minutes
- Manual refresh option
- Easy configuration through UI dialog
- Lightweight and runs in the background

## Requirements

- macOS 13.0 or later
- Swift 5.9 or later
- GitHub account with access to a GitHub organization using Copilot

## Setup

### 1. Register a GitHub OAuth App (One-time Setup)

Before building the app, you need to register it as a GitHub OAuth App:

1. Go to [GitHub Settings > Developer settings > OAuth Apps][oauth-apps]
2. Click "New OAuth App"
3. Fill in the details:
   - **Application name**: GitHub Copilot Usage Notifier
   - **Homepage URL**: `https://github.com/unicornops/github-copilot-notify`
   - **Authorization callback URL**: Leave blank (not used for device flow)
   - **Enable Device Flow**: Make sure this is checked
4. Click "Register application"
5. Copy the **Client ID** - you'll need this in the next step

[oauth-apps]: https://github.com/settings/developers

### 2. Configure the Client ID

Open `Sources/AppDelegate.swift` and replace the placeholder Client ID
with yours:

```swift
private let githubClientId = "YOUR_CLIENT_ID_HERE"
```

### 3. Build the Application

```bash
swift build -c release
```

### 4. Run the Application

```bash
.build/release/GitHubCopilotNotify
```

Or copy the binary to a convenient location:

```bash
cp .build/release/GitHubCopilotNotify ~/Applications/
~/Applications/GitHubCopilotNotify
```

### 5. Authorize with GitHub

On first run, a configuration dialog will appear:

1. Enter your GitHub Organization name
2. Click "Authorize with GitHub"
3. A dialog will show an 8-digit device code (automatically copied to
   clipboard)
4. Click "Open GitHub" to open the authorization page in your browser
5. Paste the code and authorize the app
6. The app will automatically detect authorization and start displaying usage

You can re-authorize at any time by clicking the menu bar icon and selecting
"Configure".

## Usage

Once configured, the app will:

- Display "Copilot: XX%" in the menu bar showing the percentage of active
  Copilot seats
- Update automatically every 5 minutes
- Allow manual refresh via the menu

### Menu Options

- **Refresh Now**: Manually refresh the usage data
- **Configure**: Update your GitHub token and organization
- **Quit**: Exit the application

## Running at Login (Optional)

To have the app start automatically when you log in:

1. Open System Settings > General > Login Items
2. Click the "+" button under "Open at Login"
3. Navigate to and select the GitHubCopilotNotify binary

## API Endpoints Used

The app uses the following GitHub API endpoints:

- `/orgs/{org}/copilot/billing` (primary)
- `/orgs/{org}/copilot/seats` (fallback)

## Troubleshooting

### "Not Configured" in menu bar

- Click the menu bar icon and select "Configure"
- Verify your organization name is correct
- Re-authorize with GitHub

### "Error" in menu bar

- Check your internet connection
- Make sure you authorized the app on GitHub
- Ensure the organization name is correct
- Verify you have permissions to view Copilot billing data in your
  organization
- Check the Console app for detailed error messages

### Authorization Failed

- Make sure Device Flow is enabled in your OAuth App settings
- Check that the Client ID in the app matches your OAuth App
- Ensure you're pasting the correct device code on GitHub
- Try the authorization process again

### Permissions

You need to be an organization owner or have appropriate permissions to view
Copilot billing data for your organization.

## Development

### Project Structure

```text
Sources/
├── main.swift              # Application entry point
├── AppDelegate.swift       # Menu bar app and UI logic
├── CopilotAPI.swift        # GitHub API client
└── GitHubOAuthClient.swift # OAuth Device Flow implementation
```

### Building for Distribution

```bash
swift build -c release --arch arm64 --arch x86_64
```

## Privacy & Security

- OAuth tokens are stored locally in UserDefaults on your Mac
- Organization name is stored locally in UserDefaults
- No data is sent to any third-party services except GitHub's official API
- The app uses GitHub's official OAuth Device Flow for secure authentication
- Tokens are scoped to only `copilot` and `read:org` permissions

## License

MIT License - Feel free to use and modify as needed.
