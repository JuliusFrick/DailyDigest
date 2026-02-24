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

### Pre-commit: Release-Build-Check

Vor dem Commit wird der Release-Build lokal getestet (verhindert CI-Fehler):

```bash
./scripts/install-hooks.sh   # einmalig: Hook installieren
```

Danach läuft bei jedem Commit automatisch `./scripts/pre-commit-check.sh`. Manuell testen:

```bash
./scripts/pre-commit-check.sh        # Build + App-Bundle + DMG
./scripts/pre-commit-check.sh --no-dmg   # schneller, ohne DMG
```

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

3) Rebuild the app/DMG (the scripts will automatically include the icon if `assets/AppIcon.icns` exists).
   The run/packaging scripts also auto-refresh icons from these defaults when present:
   - `/Users/julius.frick/Downloads/Gemini_Generated_Image_qvpmarqvpmarqvpm.png` (square app icon)
   - `/Users/julius.frick/Downloads/VERT_Gemini_Generated_Image_z36h4wz36h4wz36h.png` (vertical marketing icon)
   You can override with `SOURCE_ICON_PNG` and `SOURCE_ICON_VERTICAL_PNG`.

```bash
VERSION=0.1.0 BUILD_NUMBER=1 ./scripts/package-dmg.sh
```

### Configuration (OAuth)

OAuth secrets are injected at build time (so they don't live in Git). The app looks for a bundled `oauth_clients.json` inside the app bundle.

You can provide it in three ways:

1) **Path to JSON file** (recommended):
```bash
OAUTH_CLIENTS_JSON_PATH="/secure/path/oauth_clients.json" ./scripts/run-app.sh
```

2) **Inline JSON**:
```bash
OAUTH_CLIENTS_JSON='{"google":{"clientId":"...","clientSecret":"..."},"slack":{"clientId":"...","clientSecret":"..."},"jira":{"clientId":"...","clientSecret":"..."}}' ./scripts/package-release.sh
```

3) **Per-provider env vars**:
```bash
OAUTH_GOOGLE_CLIENT_ID="..." OAUTH_GOOGLE_CLIENT_SECRET="..." \
OAUTH_SLACK_CLIENT_ID="..." OAUTH_SLACK_CLIENT_SECRET="..." \
OAUTH_JIRA_CLIENT_ID="..." OAUTH_JIRA_CLIENT_SECRET="..." \
./scripts/package-release.sh
```

Template (do not commit secrets): `DailyBriefing/Sources/Resources/oauth_clients.template.json`

LLM/TTS provider API keys are stored in the system keychain by the app (see Settings).

### Automatic Releases via GitHub Actions

The repository includes a GitHub Actions workflow that automatically:

1. **Builds the app** when you push a tag (e.g., `v1.0.0`) or trigger manually
2. **Creates a DMG** installer
3. **Generates appcast.xml** for Sparkle updates
4. **Creates a GitHub Release** with the DMG and ZIP files
5. **Updates GitHub Pages** with the new appcast.xml

#### Creating a Release

**Option 1: Push a tag (recommended)**
```bash
# Make sure you're on main branch with latest changes
git checkout main
git pull origin main

# Create and push a tag
git tag v1.0.0
git push origin v1.0.0
```

The workflow will automatically:
- Build the app
- Create DMG and ZIP files
- Create a GitHub Release
- Update the appcast.xml on GitHub Pages

**Option 2: Manual trigger**
1. Go to Actions → Release → Run workflow
2. Enter version (e.g., `1.0.0`) and build number (e.g., `1`)
3. Click "Run workflow"

**Note:** Tags can be created from any branch, but it's recommended to create releases from the `main` branch to ensure you're releasing stable code.

#### GitHub Pages Setup

For automatic updates to work, you need to enable GitHub Pages:

1. Go to Settings → Pages in your GitHub repository
2. Source: Deploy from a branch
3. Branch: `gh-pages` (will be created automatically by the workflow)
4. Folder: `/ (root)`
5. Save

The appcast.xml will be available at:
`https://juliusfrick.github.io/DailyDigest/appcast.xml`

Make sure this URL matches the `SPARKLE_FEED_URL` in your build scripts.

#### GitHub Secrets Setup

For Sparkle updates to work properly, you need to configure the following GitHub Secrets:

1. **SPARKLE_PUBLIC_ED_KEY**: Your public Ed25519 key (starts with `+` or base64 encoded)
   - This is embedded in the app's Info.plist
   - Users' apps use this to verify update signatures

2. **SPARKLE_PRIVATE_ED_KEY**: Your private Ed25519 key (keep this secret!)
   - Used by the CI workflow to sign DMG files
   - Never commit this to the repository

To generate these keys, you can use Sparkle's `generate_keys` tool:

```bash
# Download Sparkle release
curl -L -o sparkle.tar.xz https://github.com/sparkle-project/Sparkle/releases/download/2.8.1/Sparkle-2.8.1.tar.xz
tar -xf sparkle.tar.xz

# Generate keys
./Sparkle-2.8.1/bin/generate_keys

# This will output:
# Private key: <your-private-key>
# Public key: <your-public-key>
```

Then add these as GitHub Secrets:
- Go to Settings → Secrets and variables → Actions
- Add `SPARKLE_PUBLIC_ED_KEY` with your public key
- Add `SPARKLE_PRIVATE_ED_KEY` with your private key

**Important**: Without these secrets, updates will fail with a signature verification error.

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

