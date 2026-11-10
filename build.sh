#!/bin/sh
set -eu
cd "$(dirname "$0")"
task_bundle="tinyStats.app"
mkdir -p "$task_bundle/Contents/MacOS"
# Usage: build.sh [VERSION_LINE]; the line becomes Resources/version.txt.
# Optional environment (the defaults are host architecture and ad-hoc signature):
#   TINYSTATS_UNIVERSAL=1        build arm64 and x86_64 separately and merge them with lipo
#   TINYSTATS_SIGN_IDENTITY=...  sign with this identity (Hardened Runtime, secure timestamp)
if [ "${TINYSTATS_UNIVERSAL:-}" = 1 ]; then
    task_tmp=$(mktemp -d)
    trap 'rm -rf "$task_tmp"' EXIT
    swiftc -O -target arm64-apple-macos14.0 Sources/*.swift -o "$task_tmp/arm64"
    swiftc -O -target x86_64-apple-macos14.0 Sources/*.swift -o "$task_tmp/x86_64"
    lipo -create "$task_tmp/arm64" "$task_tmp/x86_64" -output "$task_bundle/Contents/MacOS/tinyStats-next"
else
    swiftc -O Sources/*.swift -o "$task_bundle/Contents/MacOS/tinyStats-next"
fi
mv "$task_bundle/Contents/MacOS/tinyStats-next" "$task_bundle/Contents/MacOS/tinyStats"
# The icon is optional: without Resources/AppIcon.icns the app builds as before.
task_icon=
rm -f "$task_bundle/Contents/Resources/AppIcon.icns"
if [ -f Resources/AppIcon.icns ]; then
    task_icon='<key>CFBundleIconFile</key><string>AppIcon</string>'
fi
# The bundle identifier stays the same as before the rename, so the stored
# notch preference carries over.
cat > "$task_bundle/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>tinyStats</string>
<key>CFBundleIdentifier</key><string>local.hsb.systemstatus</string>
<key>CFBundleName</key><string>tinyStats</string>
<key>CFBundleDisplayName</key><string>tinyStats</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>2.2</string>
<key>CFBundleVersion</key><string>4</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>LSMinimumSystemVersion</key><string>14.0</string>
$task_icon
</dict></plist>
PLIST
mkdir -p "$task_bundle/Contents/Resources"
if [ -n "$task_icon" ]; then cp Resources/AppIcon.icns "$task_bundle/Contents/Resources/AppIcon.icns"; fi
printf '%s\n' "${1:-tinyStats (local build)}" > "$task_bundle/Contents/Resources/version.txt"
# Seal the bundle last; later changes would invalidate the signature.
if [ -n "${TINYSTATS_SIGN_IDENTITY:-}" ]; then
    # Notarization requires the Hardened Runtime and a secure timestamp.
    codesign --force --sign "$TINYSTATS_SIGN_IDENTITY" --options runtime --timestamp "$task_bundle"
else
    codesign --force --sign - "$task_bundle"
fi
printf 'Built %s/%s\n' "$PWD" "$task_bundle"
