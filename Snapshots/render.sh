#!/bin/bash
# Renders the citation hover, the plain Cmd-F bar, and the Cmd-K jump palette.
# cmd-k-jump.png is the reserved-height panel: the same 420pt glass for a hit
# list and for no matches, with the shared selection and hover fill.
# The app-hosted tests cannot launch here: the runner is macOS 26 and the app
# requires macOS 27.
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
  Cauchy/Services/ReferenceParsing.swift \
  Cauchy/Services/BibliographyIndex.swift \
  Snapshots/CitationHoverPopover.swift \
  Snapshots/RenderCitationHover.swift \
  -o "$out/render-citation-hover"
"$out/render-citation-hover" "$(pwd)" "$out"

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
