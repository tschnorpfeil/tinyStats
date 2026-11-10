#!/bin/sh
# Builds a distributable tinyStats-<version>.dmg: universal (arm64 + x86_64),
# Developer ID signed, notarized and stapled.
#
# Usage: release.sh [--unsigned]
#   --unsigned  ad-hoc build, DMG without signature or notarization (for local
#               tests only; Gatekeeper blocks that DMG on other Macs)
#
# Environment:
#   TINYSTATS_SIGN_IDENTITY  signing identity; default: the one "Developer ID
#                            Application" identity in the keychain
#   TINYSTATS_NOTARY_PROFILE notarytool keychain profile (default: tinystats-notary)
#
# One-time setup:
#   1. Join the Apple Developer Program, create a "Developer ID Application"
#      certificate (Xcode > Settings > Accounts > Manage Certificates, or
#      developer.apple.com > Certificates) and install it in the login keychain.
#      Check: security find-identity -v -p codesigning
#   2. Create an app-specific password at account.apple.com, then store the
#      notarization credentials once in the keychain:
#        xcrun notarytool store-credentials tinystats-notary \
#            --apple-id <apple-id> --team-id <team-id> --password <app-specific-password>
set -eu
cd "$(dirname "$0")"
task_unsigned=false
case "${1:-}" in
    "") ;;
    --unsigned) task_unsigned=true ;;
    *) echo "Usage: release.sh [--unsigned]" >&2; exit 2 ;;
esac
[ $# -le 1 ] || { echo "Usage: release.sh [--unsigned]" >&2; exit 2; }
for task_tool in swiftc lipo hdiutil codesign; do
    command -v "$task_tool" >/dev/null || { echo "Missing tool: $task_tool" >&2; exit 1; }
done

task_identity=
if [ "$task_unsigned" = true ]; then
    echo 'WARNING: --unsigned: ad-hoc signature, no notarization. Gatekeeper blocks this DMG on other Macs; use it for local tests only.' >&2
else
    task_identity=${TINYSTATS_SIGN_IDENTITY:-}
    if [ -z "$task_identity" ]; then
        task_found=$(security find-identity -v -p codesigning | sed -n 's/^.*"\(Developer ID Application:.*\)"$/\1/p' | sort -u)
        task_count=$(printf '%s' "$task_found" | grep -c . || true)
        if [ "$task_count" -eq 0 ]; then
            echo 'No "Developer ID Application" identity in the keychain.' >&2
            echo 'Install the certificate (see the setup in the header of release.sh), set TINYSTATS_SIGN_IDENTITY, or use --unsigned for a local test build.' >&2
            exit 1
        elif [ "$task_count" -gt 1 ]; then
            printf 'Several "Developer ID Application" identities found; set TINYSTATS_SIGN_IDENTITY to one of:\n%s\n' "$task_found" >&2
            exit 1
        fi
        task_identity=$task_found
    fi
fi

# The version lives in build.sh only; the built Info.plist must agree with it.
task_version=$(sed -n 's|.*<key>CFBundleShortVersionString</key><string>\(.*\)</string>.*|\1|p' build.sh)
[ -n "$task_version" ] || { echo 'Version not found in build.sh.' >&2; exit 1; }
if [ "$task_unsigned" = true ]; then
    TINYSTATS_UNIVERSAL=1 TINYSTATS_SIGN_IDENTITY= ./build.sh "tinyStats $task_version"
else
    TINYSTATS_UNIVERSAL=1 TINYSTATS_SIGN_IDENTITY="$task_identity" ./build.sh "tinyStats $task_version"
fi
task_app="tinyStats.app"
task_built=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$task_app/Contents/Info.plist")
[ "$task_built" = "$task_version" ] || { echo "Built version $task_built differs from $task_version." >&2; exit 1; }
codesign --verify --deep --strict "$task_app"

task_dmg="tinyStats-$task_version.dmg"
task_tmp=$(mktemp -d)
trap 'rm -rf "$task_tmp"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
mkdir "$task_tmp/stage"
ditto "$task_app" "$task_tmp/stage/tinyStats.app"
ln -s /Applications "$task_tmp/stage/Applications"
hdiutil create -quiet -volname tinyStats -srcfolder "$task_tmp/stage" -fs HFS+ -format UDZO -imagekey zlib-level=9 "$task_tmp/$task_dmg"

if [ "$task_unsigned" = false ]; then
    task_profile=${TINYSTATS_NOTARY_PROFILE:-tinystats-notary}
    codesign --force --sign "$task_identity" --timestamp "$task_tmp/$task_dmg"
    codesign --verify --strict "$task_tmp/$task_dmg"
    xcrun notarytool submit "$task_tmp/$task_dmg" --keychain-profile "$task_profile" --wait --output-format json > "$task_tmp/notary.json"
    task_status=$(plutil -extract status raw -o - "$task_tmp/notary.json" 2>/dev/null || true)
    if [ "$task_status" != Accepted ]; then
        task_id=$(plutil -extract id raw -o - "$task_tmp/notary.json" 2>/dev/null || true)
        echo "Notarization status: ${task_status:-unknown} (not Accepted)." >&2
        cat "$task_tmp/notary.json" >&2
        if [ -n "$task_id" ]; then xcrun notarytool log "$task_id" --keychain-profile "$task_profile" >&2 || true; fi
        exit 1
    fi
    xcrun stapler staple "$task_tmp/$task_dmg"
    xcrun stapler validate "$task_tmp/$task_dmg"
    spctl -a -t open --context context:primary-signature -v "$task_tmp/$task_dmg"
fi

# Publish only a finished image.
mv -f "$task_tmp/$task_dmg" "$task_dmg"
task_bytes=$(wc -c < "$task_dmg" | tr -d ' ')
printf 'DMG:    %s/%s\nSize:   %s bytes\nSHA256: %s\n' "$PWD" "$task_dmg" "$task_bytes" "$(shasum -a 256 "$task_dmg" | cut -d' ' -f1)"
if [ "$task_unsigned" = true ]; then echo 'WARNING: unsigned test DMG; do not distribute.' >&2; fi
