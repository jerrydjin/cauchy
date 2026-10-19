#!/bin/bash
# Renders the Cmd-F named-result list with ImageRenderer. The app-hosted
# tests cannot launch here: the runner is macOS 26 and the app requires macOS 27.
set -euo pipefail
cd "$(dirname "$0")/.."
out="${1:-Snapshots/out}"
mkdir -p "$out"
sdk="$(xcrun --show-sdk-path)"
target="$(uname -m)-apple-macosx26.0"
xcrun swiftc -parse-as-library -O \
  -sdk "$sdk" \
  -target "$target" \
  -framework SwiftUI \
  -framework AppKit \
  -framework PDFKit \
  Cauchy/Models/ReferenceKind.swift \
  Cauchy/Services/DocumentFind.swift \
  Cauchy/ViewModels/PDFFindModel.swift \
  Cauchy/Views/Design/GlassIconButton.swift \
  Cauchy/Views/PDF/FindBarView.swift \
  Snapshots/LinkStubs.swift \
  Snapshots/RenderFindList.swift \
  -o "$out/render-find-list"
"$out/render-find-list" "$(pwd)" "$out"
