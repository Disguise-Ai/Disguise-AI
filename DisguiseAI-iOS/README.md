# Disguise.AI iOS Keyboard Extension

This is the native iOS app with keyboard extension and share extension for Disguise.AI.

## Prerequisites

1. **Xcode 15+** - Download from Mac App Store
2. **Apple Developer Account** - $99/year for testing on physical devices
3. **Your Mac's IP address** - The server must be accessible from your iPhone

## Project Setup in Xcode

### Step 1: Create New Xcode Project

1. Open Xcode
2. File → New → Project
3. Select **iOS → App**
4. Configure:
   - Product Name: `DisguiseAI`
   - Team: Your Apple Developer Team
   - Organization Identifier: `com.yourname` (e.g., `com.rashaad`)
   - Interface: **SwiftUI**
   - Language: **Swift**
5. Save to the `DisguiseAI-iOS` folder

### Step 2: Add App Group Capability

1. Select the **DisguiseAI** target
2. Go to **Signing & Capabilities**
3. Click **+ Capability**
4. Add **App Groups**
5. Create group: `group.com.disguiseai.shared`

### Step 3: Add Keyboard Extension

1. File → New → Target
2. Select **iOS → Keyboard Extension**
3. Name it: `DisguiseKeyboard`
4. Activate the scheme when prompted

### Step 4: Add Share Extension

1. File → New → Target
2. Select **iOS → Share Extension**
3. Name it: `DisguiseShare`
4. Activate the scheme when prompted

### Step 5: Configure Extensions

For BOTH extensions (DisguiseKeyboard and DisguiseShare):

1. Select the extension target
2. Go to **Signing & Capabilities**
3. Add **App Groups** capability
4. Select the same group: `group.com.disguiseai.shared`

### Step 6: Copy Source Files

Copy these files into your Xcode project:

**Main App (DisguiseAI folder):**
- `DisguiseAIApp.swift` → Replace the generated App file
- `ContentView.swift` → Replace the generated ContentView

**Shared (Create a "Shared" group in Xcode):**
- `Shared/APIService.swift`
- `Shared/SharedDefaults.swift`

**Keyboard Extension (DisguiseKeyboard folder):**
- `DisguiseKeyboard/KeyboardViewController.swift` → Replace generated controller
- `DisguiseKeyboard/Info.plist` → Replace generated plist

**Share Extension (DisguiseShare folder):**
- `DisguiseShare/ShareViewController.swift` → Replace generated controller
- `DisguiseShare/Info.plist` → Replace generated plist

### Step 7: Add Shared Files to All Targets

1. Select `APIService.swift` in Xcode
2. In the File Inspector (right panel), under **Target Membership**
3. Check ALL THREE targets: DisguiseAI, DisguiseKeyboard, DisguiseShare
4. Do the same for `SharedDefaults.swift`

### Step 8: Update Server URL

In `Shared/APIService.swift`, update the `baseURL`:

```swift
// For local testing, use your Mac's IP:
private let baseURL = "http://YOUR_MAC_IP:3000"

// For production, use your deployed server:
private let baseURL = "https://your-server.com"
```

Find your Mac's IP: System Settings → Network → Wi-Fi → Details → IP Address

### Step 9: Update App Group ID

In `Shared/SharedDefaults.swift`, make sure the `suiteName` matches:

```swift
private let suiteName = "group.com.disguiseai.shared"
```

### Step 10: Build & Run

1. Connect your iPhone via USB
2. Select your iPhone as the run destination
3. Select the **DisguiseAI** scheme
4. Click Run (⌘R)
5. Trust the developer certificate on your iPhone:
   - Settings → General → VPN & Device Management → Your Developer App → Trust

## Enabling the Keyboard

After installing the app:

1. Open **Settings** on your iPhone
2. Go to **General → Keyboard → Keyboards**
3. Tap **Add New Keyboard**
4. Select **Disguise**
5. Tap on **Disguise** in your keyboards list
6. Enable **Allow Full Access** (required for AI features)

## Using the Keyboard

1. Open any app (Tinder, iMessage, Instagram, etc.)
2. Tap the text field to bring up the keyboard
3. Tap the 🌐 globe icon to switch to Disguise keyboard
4. Either:
   - Type/paste context and tap "Get Ideas"
   - Or tap "Paste Context" to paste their message
5. Tap any suggestion to insert it

## Using the Share Extension

1. Take a screenshot of a conversation
2. Tap the screenshot to open it
3. Tap the Share button
4. Select **Disguise.AI**
5. Wait for analysis
6. Tap any suggestion to copy it
7. Go back to your app and paste

## Troubleshooting

**Keyboard doesn't appear:**
- Make sure you added it in Settings → General → Keyboard → Keyboards
- Try restarting your iPhone

**"Allow Full Access" warning:**
- This is required for network access (to call our AI)
- We do NOT store or log your keystrokes

**Suggestions not loading:**
- Check that your server is running
- Make sure your iPhone and Mac are on the same WiFi
- Verify the IP address in APIService.swift

**Share extension not appearing:**
- Make sure the app is installed (not just run from Xcode)
- Check that you're sharing an image

## File Structure

```
DisguiseAI-iOS/
├── DisguiseAI/           # Main app
│   ├── DisguiseAIApp.swift
│   └── ContentView.swift
├── DisguiseKeyboard/     # Keyboard extension
│   ├── KeyboardViewController.swift
│   └── Info.plist
├── DisguiseShare/        # Share extension
│   ├── ShareViewController.swift
│   └── Info.plist
└── Shared/               # Shared code
    ├── APIService.swift
    └── SharedDefaults.swift
```
