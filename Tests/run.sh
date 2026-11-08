#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
task_tmp=$(mktemp -d)
trap 'rm -rf "$task_tmp"' EXIT
# Compile the real app definitions and checks in one source file so the
# same-file test extension can inspect the private network baseline.
sed '/^let app = NSApplication.shared/,$d' main.swift > "$task_tmp/main.swift"
cat Tests/checks.swift >> "$task_tmp/main.swift"
swiftc "$task_tmp/main.swift" -o "$task_tmp/checks"
"$task_tmp/checks"
