#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
task_render=$(mktemp -d)
trap 'rm -rf "$task_render"' EXIT
sed '/^let app = NSApplication.shared/,$d' main.swift > "$task_render/main.swift"
cat docs/render.swift >> "$task_render/main.swift"
swiftc "$task_render/main.swift" -o "$task_render/render"
"$task_render/render" -AppleLocale en_US
