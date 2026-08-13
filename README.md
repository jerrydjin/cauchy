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

The project includes a GitHub Actions workflow (`.github/workflows/release.yml`) that builds a `.dmg` whenever a new tag (e.g., `v1.0.0`) is pushed to the repository.

The workflow signs the app either way, and picks the identity from what is configured:

| `MACOS_CERTIFICATE_P12` | Signature | What a user sees |
| --- | --- | --- |
| not set | ad-hoc | "Apple could not verify…" — installable via **System Settings > Privacy & Security > Open Anyway** |
| set | Developer ID, notarized and stapled | opens on double-click |

### Why the app must be signed even without a certificate

Building with `CODE_SIGNING_ALLOWED=NO` does not produce an unsigned app. It produces a **half-signed** one: `codesign` never runs over the bundle, so there is no `Contents/_CodeSignature`, but the linker still ad-hoc signs the arm64 executable on its own, because arm64 binaries cannot run unsigned at all. The executable therefore claims a resource seal that no `CodeResources` file backs:

```
Sealed Resources=none          # nothing sealed
CodeDirectory flags=0x20002(adhoc,linker-signed)
```

Gatekeeper treats that mismatch as corruption, not as a missing developer identity, and reports **"Cauchy is damaged and can't be opened. You should eject the disk image."** That message has no "Open Anyway" button — it blocks installation outright. Releases v1.0.0 through v1.0.2 shipped in this state.

The fix is the explicit `codesign` step in the workflow; ad-hoc is enough to make the bundle self-consistent, and downgrades the failure back to the ordinary approval prompt.

If a user hits the damaged error on one of those older releases, they can clear the quarantine flag by hand:

```bash
xattr -dr com.apple.quarantine /Applications/Cauchy.app
```

### Enabling notarization

Notarization needs a paid Apple Developer account. Once enrolled:

1. **Create a Developer ID certificate.** Generate a "Developer ID Application" certificate and export it as a `.p12`, then base64-encode it:

   ```bash
   base64 -i Certificates.p12 | pbcopy
   ```

2. **Create an app-specific password** for your Apple ID at [appleid.apple.com](https://appleid.apple.com).

3. **Add the secrets** under **Settings > Secrets and variables > Actions**:
   - `MACOS_CERTIFICATE_P12` — the base64 string from step 1.
   - `MACOS_CERTIFICATE_PASSWORD` — the `.p12` export password.
   - `APPLE_ID` — your Apple ID email.
   - `APPLE_APP_PASSWORD` — the app-specific password from step 2.
   - `APPLE_TEAM_ID` — your 10-character Developer Team ID.

No workflow edit is needed. The `Select signing identity` step switches paths on the presence of `MACOS_CERTIFICATE_P12`, and `Notarize DMG` activates with it.
