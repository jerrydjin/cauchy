# cauchy

Native macOS PDF reader for dense technical textbooks, mathematics papers, and academic problem sets.

## Requirements

- macOS 27.0 (Golden Gate) or later
- **Xcode 27 beta** (or later) with the macOS 27 SDK — Command Line Tools alone cannot build this app

Point `xcode-select` at your Xcode install if needed:

```bash
# If using the default App Store install:
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

# If using Xcode Beta:
sudo xcode-select -s /Applications/Xcode-beta.app/Contents/Developer
```

## Features

- **PDF reading workspace** — continuous, single-page, and two-up layouts, thumbnails/contents sidebar, dashboard of recent documents, in-document find (⌘F)
- **Highlights with AI threads** — select text or drag regions, save highlights, and ask questions about them; answers render LaTeX via SwiftMath
- **Reference hover previews** — an LLM-built index of theorems/lemmas/definitions/equations, indexed on-device with Apple Intelligence (Gemini only as fallback), lets you hover "Theorem 2.1" anywhere and see its statement
- **Ask-time retrieval** — a BM25 index over the document supplies relevant passages from other pages to the assistant
- **Multiple assistant providers** — on-device Apple Intelligence, Gemini (API key), or your own Claude Code / Codex CLI sign-ins
- **On-device OCR** — Vision framework text recognition with LaTeX formatting assist

Headless tooling: `Cauchy --benchmark-indexing <pdf> [--pages N]` benchmarks on-device reference indexing; `Cauchy --probe-retrieval <pdf> <query>` prints what retrieval would feed the assistant.

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

Workspace state is saved under Application Support at `~/Library/Application Support/Cauchy/workspaces/<id>/` (highlights, viewport, thumbnails). Reference-index caches live in `…/Cauchy/reference-index/`. Legacy sidecars beside the PDF are migrated automatically on open.

## Sandbox

The app ships **unsandboxed** — the Claude Code / Codex assistant providers spawn the user's locally installed CLIs, which App Sandbox forbids. Bookmarks fall back to plain (non-security-scoped) bookmarks accordingly.

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
