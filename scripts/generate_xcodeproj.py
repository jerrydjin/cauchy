#!/usr/bin/env python3
import hashlib
import os
import subprocess
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT_DIR = os.path.join(ROOT, "Cauchy")


def gid(s: str) -> str:
    return hashlib.md5(("cauchy2_" + s).encode()).hexdigest()[:24].upper()


swift_files = []
for dirpath, _, filenames in os.walk(PROJECT_DIR):
    for f in sorted(filenames):
        if f.endswith(".swift"):
            rel = os.path.relpath(os.path.join(dirpath, f), PROJECT_DIR)
            swift_files.append(rel.replace("\\", "/"))
swift_files.sort()

files_by_dir = defaultdict(list)
dirs_by_dir = defaultdict(set)
for sf in swift_files:
    d, f = os.path.split(sf)
    files_by_dir[d].append(f)
    if d:
        parts = d.split("/")
        for i in range(len(parts)):
            parent = "/".join(parts[:i])
            dirs_by_dir[parent].add(parts[i])

IDS = {k: gid(k) for k in [
    "project", "target", "sources", "resources", "frameworks", "product",
    "cl_project", "cl_target", "debug_p", "release_p", "debug_t", "release_t",
    "assets", "assets_build", "entitlements", "root", "cauchy_group", "products",
    "fm_build", "fm_ref", "swiftmath_build", "swiftmath_ref", "swiftmath_pkg",
    "swiftmath_product",
]}

group_ids = {}

def group_id(path: str) -> str:
    key = path or "__root__"
    if key not in group_ids:
        group_ids[key] = gid("group_" + key)
    return group_ids[key]

file_ref_ids = {sf: gid("file_" + sf) for sf in swift_files}
build_file_ids = {sf: gid("build_" + sf) for sf in swift_files}

all_dirs = set()
for sf in swift_files:
    d = os.path.dirname(sf)
    if not d:
        continue
    parts = d.split("/")
    for i in range(1, len(parts) + 1):
        all_dirs.add("/".join(parts[:i]))

lines = []

def emit(s=""):
    lines.append(s)

emit("// !$*UTF8*$!")
emit("{")
emit("\tarchiveVersion = 1;")
emit("\tclasses = {};")
emit("\tobjectVersion = 56;")
emit("\tobjects = {\n")

emit("/* Begin PBXBuildFile section */")
for sf in swift_files:
    bn = os.path.basename(sf)
    emit(f'\t\t{build_file_ids[sf]} /* {bn} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref_ids[sf]} /* {bn} */; }};')
emit(f'\t\t{IDS["fm_build"]} /* FoundationModels.framework in Frameworks */ = {{isa = PBXBuildFile; fileRef = {IDS["fm_ref"]} /* FoundationModels.framework */; }};')
emit(f'\t\t{IDS["swiftmath_build"]} /* SwiftMath in Frameworks */ = {{isa = PBXBuildFile; productRef = {IDS["swiftmath_product"]} /* SwiftMath */; }};')
emit(f'\t\t{IDS["assets_build"]} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {IDS["assets"]} /* Assets.xcassets */; }};')
emit("/* End PBXBuildFile section */\n")

emit("/* Begin PBXFileReference section */")
emit(f'\t\t{IDS["product"]} /* Cauchy.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Cauchy.app; sourceTree = BUILT_PRODUCTS_DIR; }};')
for sf in swift_files:
    bn = os.path.basename(sf)
    emit(f'\t\t{file_ref_ids[sf]} /* {bn} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {bn}; sourceTree = "<group>"; }};')
emit(f'\t\t{IDS["assets"]} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; }};')
emit(f'\t\t{IDS["entitlements"]} /* Cauchy.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = Cauchy.entitlements; sourceTree = "<group>"; }};')
emit(f'\t\t{IDS["fm_ref"]} /* FoundationModels.framework */ = {{isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = FoundationModels.framework; path = System/Library/Frameworks/FoundationModels.framework; sourceTree = SDKROOT; }};')
emit("/* End PBXFileReference section */\n")

emit("/* Begin PBXFrameworksBuildPhase section */")
emit(f'\t\t{IDS["frameworks"]} /* Frameworks */ = {{ isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({IDS["fm_build"]} /* FoundationModels.framework in Frameworks */, {IDS["swiftmath_build"]} /* SwiftMath in Frameworks */,); runOnlyForDeploymentPostprocessing = 0; }};')
emit("/* End PBXFrameworksBuildPhase section */\n")

emit("/* Begin PBXGroup section */")
emit(f'\t\t{IDS["products"]} /* Products */ = {{ isa = PBXGroup; children = ({IDS["product"]} /* Cauchy.app */,); name = Products; sourceTree = "<group>"; }};')
emit(f'\t\t{IDS["cauchy_group"]} /* Cauchy */ = {{ isa = PBXGroup; children = (')
for sub in sorted(dirs_by_dir[""]):
    emit(f'\t\t\t{group_id(sub)} /* {sub} */,')
emit(f'\t\t\t{IDS["assets"]} /* Assets.xcassets */, {IDS["entitlements"]} /* Cauchy.entitlements */,')
emit('\t\t); path = Cauchy; sourceTree = "<group>"; };')

for d in sorted(all_dirs):
    name = os.path.basename(d)
    emit(f'\t\t{group_id(d)} /* {name} */ = {{ isa = PBXGroup; children = (')
    for sub in sorted(dirs_by_dir.get(d, [])):
        emit(f'\t\t\t{group_id(f"{d}/{sub}")} /* {sub} */,')
    for f in sorted(files_by_dir.get(d, [])):
        sf = f"{d}/{f}" if d else f
        emit(f'\t\t\t{file_ref_ids[sf]} /* {f} */,')
    emit(f'\t\t); path = {name}; sourceTree = "<group>"; }};')

emit(f'\t\t{IDS["root"]} = {{ isa = PBXGroup; children = ({IDS["cauchy_group"]} /* Cauchy */, {IDS["products"]} /* Products */,); sourceTree = "<group>"; }};')
emit("/* End PBXGroup section */\n")

emit("/* Begin PBXNativeTarget section */")
emit(f'\t\t{IDS["target"]} /* Cauchy */ = {{ isa = PBXNativeTarget; buildConfigurationList = {IDS["cl_target"]}; buildPhases = ({IDS["sources"]}, {IDS["frameworks"]}, {IDS["resources"]},); buildRules = (); dependencies = (); name = Cauchy; packageProductDependencies = ({IDS["swiftmath_product"]} /* SwiftMath */,); productName = Cauchy; productReference = {IDS["product"]}; productType = "com.apple.product-type.application"; }};')
emit("/* End PBXNativeTarget section */\n")

emit("/* Begin PBXProject section */")
emit(f'\t\t{IDS["project"]} /* Project object */ = {{ isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = 1; LastSwiftUpdateCheck = 2700; LastUpgradeCheck = 2700; }}; buildConfigurationList = {IDS["cl_project"]}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base,); mainGroup = {IDS["root"]}; packageReferences = ({IDS["swiftmath_pkg"]} /* XCLocalSwiftPackageReference "SwiftMath" */,); productRefGroup = {IDS["products"]}; projectDirPath = ""; projectRoot = ""; targets = ({IDS["target"]},); }};')
emit("/* End PBXProject section */\n")

emit("/* Begin PBXResourcesBuildPhase section */")
emit(f'\t\t{IDS["resources"]} /* Resources */ = {{ isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({IDS["assets_build"]},); runOnlyForDeploymentPostprocessing = 0; }};')
emit("/* End PBXResourcesBuildPhase section */\n")

emit("/* Begin PBXSourcesBuildPhase section */")
emit(f'\t\t{IDS["sources"]} /* Sources */ = {{ isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (')
for sf in swift_files:
    emit(f'\t\t\t{build_file_ids[sf]},')
emit('\t\t); runOnlyForDeploymentPostprocessing = 0; };')
emit("/* End PBXSourcesBuildPhase section */\n")

def target_settings(cid, name):
    emit(f'\t\t{cid} /* {name} */ = {{ isa = XCBuildConfiguration; buildSettings = {{')
    emit('\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;')
    emit('\t\t\tCODE_SIGN_ENTITLEMENTS = Cauchy/Cauchy.entitlements;')
    emit('\t\t\tCODE_SIGN_STYLE = Automatic;')
    emit('\t\t\tCOMBINE_HIDPI_IMAGES = YES;')
    emit('\t\t\tCURRENT_PROJECT_VERSION = 1;')
    emit('\t\t\tENABLE_APP_SANDBOX = YES;')
    emit('\t\t\tENABLE_HARDENED_RUNTIME = YES;')
    emit('\t\t\tENABLE_USER_SELECTED_FILES = readwrite;')
    emit('\t\t\tGENERATE_INFOPLIST_FILE = YES;')
    emit('\t\t\tINFOPLIST_KEY_CFBundleDisplayName = "cauchy";')
    emit('\t\t\tINFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.productivity";')
    emit('\t\t\tLD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/../Frameworks");')
    emit('\t\t\tMACOSX_DEPLOYMENT_TARGET = 27.0;')
    emit('\t\t\tMARKETING_VERSION = 1.0;')
    emit('\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.cauchy.app;')
    emit('\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";')
    emit('\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;')
    emit('\t\t\tSWIFT_VERSION = 6.0;')
    emit('\t\t}; name = %s; };' % name)

emit("/* Begin XCBuildConfiguration section */")
emit(f'\t\t{IDS["debug_p"]} /* Debug */ = {{ isa = XCBuildConfiguration; buildSettings = {{ ALWAYS_SEARCH_USER_PATHS = NO; CLANG_ENABLE_MODULES = YES; COPY_PHASE_STRIP = NO; DEBUG_INFORMATION_FORMAT = dwarf; ENABLE_STRICT_OBJC_MSGSEND = YES; GCC_DYNAMIC_NO_PIC = NO; MACOSX_DEPLOYMENT_TARGET = 27.0; MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE; ONLY_ACTIVE_ARCH = YES; SDKROOT = macosx; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG; SWIFT_OPTIMIZATION_LEVEL = "-Onone"; }}; name = Debug; }};')
emit(f'\t\t{IDS["release_p"]} /* Release */ = {{ isa = XCBuildConfiguration; buildSettings = {{ ALWAYS_SEARCH_USER_PATHS = NO; CLANG_ENABLE_MODULES = YES; COPY_PHASE_STRIP = NO; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym"; ENABLE_STRICT_OBJC_MSGSEND = YES; MACOSX_DEPLOYMENT_TARGET = 27.0; MTL_ENABLE_DEBUG_INFO = NO; SDKROOT = macosx; SWIFT_COMPILATION_MODE = wholemodule; }}; name = Release; }};')
target_settings(IDS["debug_t"], "Debug")
target_settings(IDS["release_t"], "Release")
emit("/* End XCBuildConfiguration section */\n")

emit("/* Begin XCConfigurationList section */")
emit(f'\t\t{IDS["cl_project"]} = {{ isa = XCConfigurationList; buildConfigurations = ({IDS["debug_p"]}, {IDS["release_p"]},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};')
emit(f'\t\t{IDS["cl_target"]} = {{ isa = XCConfigurationList; buildConfigurations = ({IDS["debug_t"]}, {IDS["release_t"]},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};')
emit("/* End XCConfigurationList section */")

emit("\n/* Begin XCLocalSwiftPackageReference section */")
emit(f'\t\t{IDS["swiftmath_pkg"]} /* XCLocalSwiftPackageReference "SwiftMath" */ = {{')
emit('\t\t\tisa = XCLocalSwiftPackageReference;')
emit('\t\t\trelativePath = Packages/SwiftMath;')
emit('\t\t};')
emit("/* End XCLocalSwiftPackageReference section */")

emit("\n/* Begin XCSwiftPackageProductDependency section */")
emit(f'\t\t{IDS["swiftmath_product"]} /* SwiftMath */ = {{')
emit('\t\t\tisa = XCSwiftPackageProductDependency;')
emit(f'\t\t\tpackage = {IDS["swiftmath_pkg"]} /* XCLocalSwiftPackageReference "SwiftMath" */;')
emit('\t\t\tproductName = SwiftMath;')
emit('\t\t};')
emit("/* End XCSwiftPackageProductDependency section */")

emit("\t};")
emit(f'\trootObject = {IDS["project"]} /* Project object */;')
emit("}")

project_path = os.path.join(ROOT, "Cauchy.xcodeproj")
out = os.path.join(project_path, "project.pbxproj")
with open(out, "w") as f:
    f.write("\n".join(lines) + "\n")

scheme_path = os.path.join(ROOT, "Cauchy.xcodeproj", "xcshareddata", "xcschemes", "Cauchy.xcscheme")
if os.path.exists(scheme_path):
    with open(scheme_path) as f:
        scheme = f.read()
    import re
    scheme = re.sub(r'BlueprintIdentifier = "[A-F0-9]+"', f'BlueprintIdentifier = "{IDS["target"]}"', scheme)
    with open(scheme_path, "w") as f:
        f.write(scheme)

print(f"Wrote {out}")
print(f"Target ID: {IDS['target']}")
print(f"Swift files: {len(swift_files)}")

resolve = subprocess.run(
    [
        "xcodebuild",
        "-resolvePackageDependencies",
        "-project",
        project_path,
    ],
    cwd=ROOT,
    capture_output=True,
    text=True,
)
if resolve.returncode != 0:
    print(resolve.stderr or resolve.stdout)
    raise SystemExit(resolve.returncode)
print("Resolved Swift package dependencies.")
