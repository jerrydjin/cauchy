#!/bin/bash
# Renders the citation hover, the plain Cmd-F bar, the Cmd-K jump palette,
# and the RHS reference card. The app-hosted tests cannot launch here: the
# runner is macOS 26 and the app requires macOS 27.
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

# The reference card typesets with SwiftMath, whose fonts live in a resource
# bundle. A raw swiftc link does not assemble that bundle, so this target is
# a small SwiftPM executable. Its deployment target stays on macOS 14 so it
# still runs where the app (macOS 27) cannot.
if [ ! -f Packages/SwiftMath/Package.swift ]; then
  mkdir -p Packages
  rm -rf Packages/SwiftMath
  git clone --depth 1 --branch 1.7.3 https://github.com/mgriebling/SwiftMath.git Packages/SwiftMath
fi

stage="$out/reference-preview-build"
rm -rf "$stage"
mkdir -p "$stage/Sources/RenderReferencePreview"
ref_sources=(
  Snapshots/RenderReferencePreview.swift
  Snapshots/ReferencePreviewStubs.swift
  Snapshots/LinkStubs.swift
  Cauchy/Models/ReferenceKind.swift
  Cauchy/Utilities/NormalizedRect.swift
  Cauchy/Services/ReferenceParsing.swift
  Cauchy/Services/BibliographyIndex.swift
  Cauchy/Services/ReferenceDetector.swift
  Cauchy/Services/DocumentFind.swift
  Cauchy/Models/DocumentBlock.swift
  Cauchy/Services/AssistantResponseNormalizer.swift
  Cauchy/Services/LaTeXNormalizer.swift
  Cauchy/Services/MessageContentParser.swift
  Cauchy/Views/RichText/InlineFlowLayout.swift
  Cauchy/Views/RichText/MathSegmentView.swift
  Cauchy/Views/RichText/MessageContentView.swift
  Cauchy/Views/Context/ReadingBlockCard.swift
  Cauchy/Views/Context/ReferencePreviewStatement.swift
)
for src in "${ref_sources[@]}"; do
  cp "$src" "$stage/Sources/RenderReferencePreview/$(basename "$src")"
done

swiftmath_path="$(cd Packages/SwiftMath && pwd)"
cat > "$stage/Package.swift" <<EOF
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "RenderReferencePreview",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "${swiftmath_path}")
    ],
    targets: [
        .executableTarget(
            name: "RenderReferencePreview",
            dependencies: [
                .product(name: "SwiftMath", package: "SwiftMath")
            ],
            path: "Sources/RenderReferencePreview",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
EOF

MACOSX_DEPLOYMENT_TARGET=14.0 xcrun --sdk macosx swift build -c release --package-path "$stage"
ref_bin="$(MACOSX_DEPLOYMENT_TARGET=14.0 xcrun --sdk macosx swift build -c release --package-path "$stage" --show-bin-path)/RenderReferencePreview"
"$ref_bin" "$(pwd)" "$out"
