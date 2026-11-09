#!/bin/sh
set -eu
case "${1:-}" in ""|--update) ;; *) echo "Usage: install.sh [--update]" >&2; exit 2 ;; esac
[ "$(uname -s)" = Darwin ] || { echo 'tinyStats requires macOS.' >&2; exit 1; }
command -v git >/dev/null || { echo 'Git is missing. Install Xcode Command Line Tools: xcode-select --install' >&2; exit 1; }
command -v swiftc >/dev/null || { echo 'Swift is missing. Install Xcode Command Line Tools: xcode-select --install' >&2; exit 1; }
task_source=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
task_data=${TINYSTATS_HOME:-"$HOME/.local/share/tinystats"}
task_apps=${TINYSTATS_APP_DIR:-"$HOME/Applications"}
task_bin=${TINYSTATS_BIN_DIR:-"$HOME/.local/bin"}
mkdir -p "$task_data" "$task_apps" "$task_bin"
if [ -e "$task_bin/tinystats" ] && ! grep -Fq "# tinyStats CLI" "$task_bin/tinystats"; then
    echo "Existing unrelated command $task_bin/tinystats will not be overwritten." >&2
    exit 1
fi
# One installation/update at a time; a stale lock is reported rather than removed blindly.
task_owns_lock=true
if [ "${TINYSTATS_INSTALL_LOCK_OWNER:-}" = "$PPID" ] && [ -d "$task_data/install.lock" ]; then
    task_owns_lock=false
else
    mkdir "$task_data/install.lock" 2>/dev/null || { echo "Installation is already running (lock: $task_data/install.lock)." >&2; exit 1; }
fi
task_stage=
cleanup() {
    [ -z "$task_stage" ] || rm -rf "$task_stage"
    if [ "$task_owns_lock" = true ]; then rmdir "$task_data/install.lock"; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
task_managed_source="$task_data/source"
if [ -d "$task_managed_source" ]; then task_managed_source=$(CDPATH= cd -- "$task_managed_source" && pwd -P); fi
if [ "$task_source" != "$task_managed_source" ]; then
    if [ ! -e "$task_data/source" ]; then
        git clone --no-hardlinks "$task_source" "$task_data/source"
        git -C "$task_data/source" remote set-url origin https://github.com/tschnorpfeil/tinyStats.git
    else
        echo 'Managed checkout already exists. To update: tinystats update' >&2
        exit 1
    fi
fi
task_source="$task_data/source"
# Earlier versions stored a gh credential helper here; the repository is public.
git -C "$task_source" config --unset-all credential.https://github.com.helper || true
if [ "${1:-}" = --update ]; then
    [ -z "$(git -C "$task_source" status --porcelain)" ] || { echo 'Local changes in the installation checkout; update aborted.' >&2; exit 1; }
    git -C "$task_source" fetch origin main
    git -C "$task_source" merge --ff-only origin/main
    # Run updated installer code, retaining the lock in this parent until it exits.
    TINYSTATS_INSTALL_LOCK_OWNER=$$ "$task_source/install.sh"
    exit $?
fi
# Compile before touching the installed app or its process.
"$task_source/build.sh" "$(git -C "$task_source" log -1 --format='tinyStats %h (%cs)')"
task_stage=$(mktemp -d "$task_apps/.tinystats-install.XXXXXX")
ditto "$task_source/tinyStats.app" "$task_stage/tinyStats.app"
[ -x "$task_stage/tinyStats.app/Contents/MacOS/tinyStats" ] || { echo 'Build is incomplete.' >&2; exit 1; }
# Stop only this installation's app (the CLI knows which processes are its own).
TINYSTATS_APP_DIR="$task_apps" "$task_source/bin/tinystats" stop
if [ -e "$task_apps/tinyStats.app" ]; then mv "$task_apps/tinyStats.app" "$task_stage/previous.app"; fi
if ! mv "$task_stage/tinyStats.app" "$task_apps/tinyStats.app"; then
    [ ! -d "$task_stage/previous.app" ] || mv "$task_stage/previous.app" "$task_apps/tinyStats.app"
    exit 1
fi
install -m 755 "$task_source/bin/tinystats" "$task_bin/tinystats"
case ":$PATH:" in
    *":$task_bin:"*) ;;
    *)
        # zsh is macOS's default shell. The current terminal can use the full path immediately.
        if [ "$task_bin" = "$HOME/.local/bin" ] && ! grep -Fq '# tinyStats CLI' "$HOME/.zprofile" 2>/dev/null; then
            printf '\n# tinyStats CLI\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$HOME/.zprofile"
        fi
        printf 'For this terminal: export PATH="%s:$PATH"\n' "$task_bin"
        ;;
esac
"$task_bin/tinystats" start
printf 'tinyStats installed. Start: tinystats · Update: tinystats update\n'
