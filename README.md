## Daily Briefing

macOS app (SwiftUI + SwiftPM) that generates a daily briefing from connected sources (e.g. Google Calendar, Gmail, Jira, Slack) and can optionally speak it via TTS.

### Dev run (important: run as `.app`)

Some macOS APIs (notably User Notifications) behave differently when the process is not running from a proper `.app` bundle. For local development, use:

```bash
./scripts/run-app.sh
```

This script:

- builds via SwiftPM (`swift build`)
- wraps the debug executable into a minimal `DailyBriefing.app`
- launches it via `open` so macOS treats it as a real app bundle

### Release packaging (unsigned)

Create a release-style `.app` bundle and a zip in `./dist`:

```bash
VERSION=0.1.0 BUILD_NUMBER=1 ./scripts/package-release.sh
```

Outputs:

- `dist/DailyBriefing.app`
- `dist/DailyBriefing-${VERSION}.zip`

### DMG packaging (unsigned)

Create a simple “drag to Applications” DMG in `./dist`:

```bash
VERSION=0.1.0 BUILD_NUMBER=1 ./scripts/package-dmg.sh
```

Output:

- `dist/DailyBriefing-${VERSION}.dmg`

### App icon (macOS `.icns`)

1) Save your square icon image somewhere (e.g. `~/Downloads/icon.png`)

2) Generate `assets/AppIcon.icns`:

```bash
./scripts/generate-app-icon.sh ~/Downloads/icon.png
```

3) Rebuild the app/DMG (the scripts will automatically include the icon if `assets/AppIcon.icns` exists):

```bash
VERSION=0.1.0 BUILD_NUMBER=1 ./scripts/package-dmg.sh
```

### Configuration

Integrations currently read OAuth client configuration from `UserDefaults` keys (you can set them via the app’s Settings UI where available, or via `defaults write` during development).

- **Google (Calendar/Gmail)**:
  - `google_client_id`
  - `google_client_secret` (optional for PKCE flows)
- **Slack**:
  - `slack_client_id`
  - `slack_client_secret`
- **Jira**:
  - `jira_client_id`
  - `jira_client_secret`

LLM/TTS provider API keys are stored in the system keychain by the app (see Settings).

### Signing + notarization checklist (Developer ID)

This repo’s packaging script intentionally does not sign/notarize. A typical flow:

```bash
# 1) Sign the .app
codesign --force --options runtime --timestamp --sign "Developer ID Application: <YOUR NAME> (<TEAMID>)" "dist/DailyBriefing.app"

# 2) Verify signature
codesign --verify --deep --strict --verbose=2 "dist/DailyBriefing.app"

# 3) Zip (keep parent folder)
ditto -c -k --sequesterRsrc --keepParent "dist/DailyBriefing.app" "dist/DailyBriefing-notarize.zip"

# 4) Notarize
xcrun notarytool submit "dist/DailyBriefing-notarize.zip" --keychain-profile "<PROFILE_NAME>" --wait

# 5) Staple ticket
xcrun stapler staple "dist/DailyBriefing.app"
```

If you add entitlements, hardened runtime exceptions, or additional bundled resources, adjust signing accordingly.

