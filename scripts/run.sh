#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ ! -d Packages/SwiftMath ]]; then
  mkdir -p Packages
  git clone --depth 1 --branch 1.7.3 https://github.com/mgriebling/SwiftMath.git Packages/SwiftMath
fi

python3 scripts/generate_xcodeproj.py
xcodebuild -project Cauchy.xcodeproj -scheme Cauchy -configuration Debug build
open "$(xcodebuild -project Cauchy.xcodeproj -scheme Cauchy -configuration Debug -showBuildSettings 2>/dev/null | awk -F ' = ' '/TARGET_BUILD_DIR/ {dir=$2} /FULL_PRODUCT_NAME/ {name=$2} END {print dir "/" name}')"
