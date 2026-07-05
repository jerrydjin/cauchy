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
