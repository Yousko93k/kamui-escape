#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

# Detect iOS SDK
if [ -z "${SDK:-}" ]; then
    if [ -d "/opt/theos/sdks/iPhoneOS14.5.sdk" ]; then
        SDK="/opt/theos/sdks/iPhoneOS14.5.sdk"
    elif command -v xcrun >/dev/null 2>&1; then
        SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
    else
        echo "[!] No iOS SDK found"
        exit 1
    fi
fi

APP_NAME="BQTool"
VERSION="2.5.2"
BID="${BID:-com.kamui.escape}"
BUILD="$ROOT/build"
APP="$BUILD/Payload/$APP_NAME.app"

echo "[*] SDK: $SDK"

if [ ! -d "$SDK" ]; then
    echo "[!] SDK directory not found: $SDK"
    exit 1
fi

# Check required tools
for tool in clang python3 zip; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "[!] Missing required tool: $tool"
        exit 1
    fi
done

# Check source files
SOURCES=(
    main.m
    AppDelegate.m
    SceneDelegate.m
    RootTabBarController.m
    GestaltVC.m
    CacheExtraEditVC.m
    PosterBoardVC.m
    TendiesExploreVC.m
    SettingsVC.m
    LogVC.m
    FilesVC.m
    BQUI.m
    BQCore.m
)

for source in "${SOURCES[@]}"; do
    if [ ! -f "$ROOT/src/$source" ]; then
        echo "[!] Missing source file: src/$source"
        exit 1
    fi
done

# Prepare output directory
rm -rf "$BUILD/Payload"
mkdir -p "$APP"

echo "[*] Compiling KAMUI..."

# Linker flags
LINKER_FLAGS=()
if [ "$(uname -s)" = "Linux" ]; then
    LINKER_FLAGS+=("-fuse-ld=lld")
fi

clang \
    -target arm64-apple-ios14.0 \
    -isysroot "$SDK" \
    ${LINKER_FLAGS[@]+"${LINKER_FLAGS[@]}"} \
    -fobjc-arc \
    -fblocks \
    -O2 \
    -Wall \
    -Wno-unused-parameter \
    -Wno-deprecated-declarations \
    -framework UIKit \
    -framework Foundation \
    -framework CoreFoundation \
    -framework CoreGraphics \
    -framework WebKit \
    -L"$SDK/usr/lib" \
    -lz \
    "${SOURCES[@]/#/$ROOT/src/}" \
    -o "$APP/$APP_NAME"

echo "[*] Configuring Info.plist..."

cp "$ROOT/src/Info.plist" "$APP/Info.plist"

python3 - "$APP/Info.plist" "$BID" <<'PY'
import plistlib
import sys

path, bundle_id = sys.argv[1:]

with open(path, "rb") as source:
    info = plistlib.load(source)

info["CFBundleIdentifier"] = bundle_id

with open(path, "wb") as target:
    plistlib.dump(info, target, fmt=plistlib.FMT_XML, sort_keys=False)
PY

# Copy application resources
cp "$ROOT/src/respring.html" "$APP/respring.html"
cp "$ROOT/src/AppIcon.png" "$APP/AppIcon.png"

for localization in "$ROOT"/src/*.lproj; do
    [ -d "$localization" ] || continue
    cp -R "$localization" "$APP/"
done

# Package IPA
echo "[*] Packaging IPA..."

(
    cd "$BUILD"
    zip -qry "KAMUI-$VERSION.ipa" Payload
)

echo "[+] Build completed successfully!"
echo "[+] IPA: $BUILD/KAMUI-$VERSION.ipa"
