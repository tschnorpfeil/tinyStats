#!/bin/sh
set -eu
cd "$(dirname "$0")"
task_bundle="Systemstatus.app"
mkdir -p "$task_bundle/Contents/MacOS"
swiftc -O main.swift -o "$task_bundle/Contents/MacOS/Systemstatus-next"
mv "$task_bundle/Contents/MacOS/Systemstatus-next" "$task_bundle/Contents/MacOS/Systemstatus"
cat > "$task_bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Systemstatus</string>
<key>CFBundleIdentifier</key><string>local.hsb.systemstatus</string>
<key>CFBundleName</key><string>Systemstatus</string>
<key>CFBundleDisplayName</key><string>Systemstatus</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
PLIST
printf 'Built %s/%s\n' "$PWD" "$task_bundle"
