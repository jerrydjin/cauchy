# cauchy

Native macOS PDF reader for dense technical textbooks, mathematics papers, and academic problem sets.

## Requirements

- macOS 27.0 (Golden Gate) or later
- **Xcode 27 beta** (or later) with the macOS 27 SDK — Command Line Tools alone cannot build this app

Point `xcode-select` at your Xcode install if needed:

```bash
sudo xcode-select -s /Users/jerryjin/Downloads/Xcode-beta.app/Contents/Developer
```

## Features

- **Dual-pane PDF workspace** — primary reading canvas with synchronized secondary viewport (split or floating Liquid Glass panel)
- **Reference pins** — drag-select regions and pin theorems, proofs, exercises, and solutions to a persistent sidebar
- **Bidirectional links** — map exercises to solutions with lock-sync navigation
- **On-device OCR** — Vision framework text recognition with LaTeX formatting assist

## Open in Xcode

```bash
open Cauchy.xcodeproj
```

Build and run the **Cauchy** scheme (⌘R).

If source files show as missing in Xcode, regenerate the project:

```bash
python3 scripts/generate_xcodeproj.py
```

This also resolves the local SwiftMath package under `Packages/SwiftMath`. If that folder is missing, run once:

```bash
git clone --depth 1 --branch 1.7.3 https://github.com/mgriebling/SwiftMath.git Packages/SwiftMath
```

Or use the all-in-one script:

```bash
./scripts/run.sh
```

After regenerating, **close and reopen** the Xcode project if you see “Missing package product 'SwiftMath'”.

## Project Structure

```
Cauchy/
├── App/              Entry point and environment
├── Models/           DocumentWorkspace, ReferencePin, ViewportState
├── ViewModels/       Workspace, viewport coordinator, reference engine
├── Views/            SwiftUI + Liquid Glass UI
├── PDFKitBridge/     AppKit PDFView representable and selection overlay
├── Services/         Persistence, OCR, PDF region rendering
└── Utilities/        Normalized coordinates, debouncing
```

## Persistence

Workspace state is saved under Application Support at `~/Library/Application Support/Cauchy/workspaces/<id>/` (pins, viewport, thumbnails). Legacy sidecars beside the PDF are migrated automatically on open.

## Sandbox

The app uses App Sandbox with user-selected file read/write access. Open PDFs via **Open PDF…** (⌘O) to grant security-scoped access.

## Releases & Distribution

The project includes a GitHub Actions workflow (`.github/workflows/release.yml`) that automatically builds an unsigned `.dmg` file whenever a new tag (e.g., `v1.0.0`) is pushed to the repository.

### Updating for Apple Notarization (macOS Gatekeeper)

Currently, the GitHub Action generates an **unsigned** `.dmg`. When users download the app, macOS Gatekeeper will warn them that the app is from an unidentified developer. To resolve this and fully follow Apple's guidelines, you need to sign and notarize the app using an Apple Developer account.

Here is what you need to do once you enroll in the Apple Developer Program:

1. **Create a Developer ID Certificate:**
   Generate a "Developer ID Application" certificate in your Apple Developer account and export it as a `.p12` file.

2. **Add Secrets to GitHub:**
   In your GitHub repository settings under **Secrets and variables > Actions**, add the following:
   - `BUILD_CERTIFICATE_BASE64`: The base64-encoded string of your `.p12` certificate.
   - `P12_PASSWORD`: The password for your `.p12` certificate.
   - `APPLE_ID`: Your Apple ID email address.
   - `APPLE_ID_PASSWORD`: An App-Specific Password for your Apple ID.
   - `TEAM_ID`: Your Apple Developer Team ID.

3. **Update the GitHub Actions Workflow:**
   Modify `.github/workflows/release.yml` to:
   - Install the Apple certificate into the macOS runner's keychain.
   - Change `CODE_SIGN_IDENTITY` to your Developer ID Application certificate name in the `xcodebuild` step.
   - Set `CODE_SIGNING_REQUIRED=YES` and `CODE_SIGNING_ALLOWED=YES`.
   - Add a step after the build to run `xcrun notarytool submit build/Cauchy.xcarchive/Products/Applications/Cauchy.app --apple-id $APPLE_ID --password $APPLE_ID_PASSWORD --team-id $TEAM_ID --wait`.
   - Run `xcrun stapler staple` on the app or the `.dmg`.
