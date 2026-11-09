#!/bin/sh
set -eu
cd "$(dirname "$0")"
task_bundle="tinyStats.app"
mkdir -p "$task_bundle/Contents/MacOS"
swiftc -O Sources/*.swift -o "$task_bundle/Contents/MacOS/tinyStats-next"
mv "$task_bundle/Contents/MacOS/tinyStats-next" "$task_bundle/Contents/MacOS/tinyStats"
# The bundle identifier stays the same as before the rename, so the stored
# notch preference carries over.
cat > "$task_bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>tinyStats</string>
<key>CFBundleIdentifier</key><string>local.hsb.systemstatus</string>
<key>CFBundleName</key><string>tinyStats</string>
<key>CFBundleDisplayName</key><string>tinyStats</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>2.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PLIST
printf 'Built %s/%s\n' "$PWD" "$task_bundle"
