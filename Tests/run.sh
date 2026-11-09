#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
task_tmp=$(mktemp -d)
trap 'rm -rf "$task_tmp"' EXIT
# The checks replace the app's entry point; top-level code must live in main.swift.
cp Tests/checks.swift "$task_tmp/main.swift"
swiftc $(ls Sources/*.swift | grep -v '/main.swift$') "$task_tmp/main.swift" -o "$task_tmp/checks"
"$task_tmp/checks"
