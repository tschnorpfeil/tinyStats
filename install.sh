#!/bin/sh
set -eu
case "${1:-}" in ""|--update) ;; *) echo "Aufruf: install.sh [--update]" >&2; exit 2 ;; esac
[ "$(uname -s)" = Darwin ] || { echo 'tinyStats benötigt macOS.' >&2; exit 1; }
command -v git >/dev/null || { echo 'Git fehlt. Installiere die Xcode Command Line Tools: xcode-select --install' >&2; exit 1; }
command -v swiftc >/dev/null || { echo 'Swift fehlt. Installiere die Xcode Command Line Tools: xcode-select --install' >&2; exit 1; }
task_source=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
task_data=${TINYSTATS_HOME:-"$HOME/.local/share/tinystats"}
task_apps=${TINYSTATS_APP_DIR:-"$HOME/Applications"}
task_bin=${TINYSTATS_BIN_DIR:-"$HOME/.local/bin"}
mkdir -p "$task_data" "$task_apps" "$task_bin"
if [ -e "$task_bin/tinystats" ] && ! grep -Fq "# tinyStats CLI" "$task_bin/tinystats"; then
    echo "Vorhandener fremder Befehl $task_bin/tinystats bleibt unverändert." >&2
    exit 1
fi
# One installation/update at a time; a stale lock is reported rather than removed blindly.
task_owns_lock=true
if [ "${TINYSTATS_INSTALL_LOCK_OWNER:-}" = "$PPID" ] && [ -d "$task_data/install.lock" ]; then
    task_owns_lock=false
else
    mkdir "$task_data/install.lock" 2>/dev/null || { echo "Installation läuft bereits (Lock: $task_data/install.lock)." >&2; exit 1; }
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
        echo 'Verwalteter Checkout vorhanden. Für Updates: tinystats update' >&2
        exit 1
    fi
fi
task_source="$task_data/source"
# Authenticate private-repo updates without storing tokens or changing global Git settings.
if command -v gh >/dev/null; then
    git -C "$task_source" config --replace-all credential.https://github.com.helper ""
    git -C "$task_source" config --add credential.https://github.com.helper "!gh auth git-credential"
fi
if [ "${1:-}" = --update ]; then
    [ -z "$(git -C "$task_source" status --porcelain)" ] || { echo 'Lokale Änderungen im Installations-Checkout; Update abgebrochen.' >&2; exit 1; }
    git -C "$task_source" fetch origin main
    git -C "$task_source" merge --ff-only origin/main
    # Run updated installer code, retaining the lock in this parent until it exits.
    TINYSTATS_INSTALL_LOCK_OWNER=$$ "$task_source/install.sh"
    exit $?
fi
# Compile before touching the installed app or its process.
"$task_source/build.sh"
task_stage=$(mktemp -d "$task_apps/.tinystats-install.XXXXXX")
ditto "$task_source/tinyStats.app" "$task_stage/tinyStats.app"
[ -x "$task_stage/tinyStats.app/Contents/MacOS/tinyStats" ] || { echo 'Build ist unvollständig.' >&2; exit 1; }
mkdir -p "$task_stage/tinyStats.app/Contents/Resources"
git -C "$task_source" log -1 --format='tinyStats %h (%cs)' > "$task_stage/tinyStats.app/Contents/Resources/version.txt"
# Identify only this installation's executable, never every similarly named process.
task_exe="$task_apps/tinyStats.app/Contents/MacOS/tinyStats"
task_pids=$(ps -ax -o pid= -o comm= | while read -r task_pid task_comm; do
    [ "$task_comm" != "$task_exe" ] || printf '%s\n' "$task_pid"
done)
for task_pid in $task_pids; do kill -TERM "$task_pid" 2>/dev/null || true; done
for task_pid in $task_pids; do
    task_tries=0
    while kill -0 "$task_pid" 2>/dev/null; do
        task_tries=$((task_tries + 1))
        [ "$task_tries" -le 50 ] || { echo 'App beendet sich nicht; Installation abgebrochen.' >&2; exit 1; }
        sleep 0.1
    done
done
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
        printf 'Für dieses Terminal: export PATH="%s:$PATH"\n' "$task_bin"
        ;;
esac
"$task_bin/tinystats" start
printf 'tinyStats installiert. Start: tinystats · Update: tinystats update\n'
