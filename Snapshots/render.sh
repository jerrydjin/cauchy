#!/bin/bash
# Renders the citation hover with ImageRenderer. The app-hosted tests cannot
# launch here: the runner is macOS 26 and the app requires macOS 27.
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
