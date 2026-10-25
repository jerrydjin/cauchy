#!/usr/bin/env python3
"""Profile the actual Learn review projection in an isolated authored test host."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile

REPO = Path(__file__).resolve().parents[1]
SWIFT_MATH = "fa8244ed032f4a1ade4cb0571bf87d2f1a9fd2d7"
SOURCES = [
    "Cauchy/Models/LearningStudyMap.swift", "Cauchy/ViewModels/LearningLibraryStore.swift",
    "Cauchy/ViewModels/LearningViewModel.swift", "Cauchy/ViewModels/LearningStudyMapViewModel.swift",
    "Cauchy/Views/Learning/LearningWorkspaceView.swift",
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--package-cache", required=True, type=Path)
    parser.add_argument("--derived-data", type=Path)
    parser.add_argument("--revision", default="HEAD")
    parser.add_argument("--working-tree", action="store_true", help="Overlay the declared Learn source files from the current checkout")
    args = parser.parse_args()
    if sys.version_info < (3, 12):
        parser.error("Python 3.12 or newer is required for safe archive extraction")
    output = args.output.resolve()
    roots = [Path("/tmp").resolve(), Path(tempfile.gettempdir()).resolve()]
    if not any(output.is_relative_to(root) and output != root for root in roots):
        parser.error("output must be a new directory inside temporary storage")
    if output.exists():
        parser.error("output directory already exists; use a new location")
    if not args.package_cache.is_dir():
        parser.error("provide an existing resolved package cache")
    output.mkdir(parents=True)
    revision = subprocess.check_output(["git", "rev-parse", args.revision], cwd=REPO, text=True).strip()
    archive = subprocess.check_output(["git", "archive", revision], cwd=REPO)
    with tarfile.open(fileobj=io.BytesIO(archive)) as bundle:
        bundle.extractall(output, filter="data")
    archive = subprocess.check_output(["git", "-C", "Packages/SwiftMath", "archive", SWIFT_MATH], cwd=REPO)
    with tarfile.open(fileobj=io.BytesIO(archive)) as bundle:
        bundle.extractall(output / "Packages/SwiftMath", filter="data")
    if args.working_tree:
        for name in SOURCES:
            shutil.copy2(REPO / name, output / name)
    harness = (REPO / "scripts/fixtures/learning_review_profile.swift").read_bytes()
    with (output / "CauchyTests/LearningTests.swift").open("ab") as target:
        target.write(b"\n" + harness)
    manifest = {"revision": revision, "swiftMath": SWIFT_MATH, "workingTreeOverlay": args.working_tree,
                "harnessSHA256": hashlib.sha256(harness).hexdigest(),
                "sources": {name: hashlib.sha256((output / name).read_bytes()).hexdigest() for name in SOURCES}}
    (output / "profile-inputs.json").write_text(json.dumps(manifest, indent=2) + "\n")
    command = ["xcodebuild", "test", "-project", "Cauchy.xcodeproj", "-scheme", "Cauchy", "-configuration", "Debug",
               "-destination", "platform=macOS", "-derivedDataPath", str(args.derived_data.resolve() if args.derived_data else output / "DerivedData"),
               "-clonedSourcePackagesDirPath", str(args.package_cache.resolve()), "-disableAutomaticPackageResolution",
               "-resultBundlePath", str(output / "results.xcresult"),
               "-only-testing:CauchyTests/LearningUIFixtureTests/testProfileLearningReviewOverview"]
    env = dict(os.environ, DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer")
    with (output / "build.log").open("w") as log:
        try:
            subprocess.run(command, cwd=output, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
        except subprocess.CalledProcessError as error:
            raise SystemExit(f"Profile failed (exit {error.returncode}); inspect {output / 'build.log'} and results.xcresult") from None
    print((output / "learning-review-profile.json").read_text())


if __name__ == "__main__":
    main()
