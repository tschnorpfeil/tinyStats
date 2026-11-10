#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
task_render=$(mktemp -d)
trap 'rm -rf "$task_render"' EXIT
# The renderer replaces the app's entry point; top-level code must live in main.swift.
cp docs/render.swift "$task_render/main.swift"
swiftc $(ls Sources/*.swift | grep -v '/main.swift$') "$task_render/main.swift" -o "$task_render/render"
"$task_render/render" "$task_render/AppIcon.iconset" -AppleLocale en_US
mkdir -p Resources
iconutil -c icns "$task_render/AppIcon.iconset" -o Resources/AppIcon.icns
