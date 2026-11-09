#!/bin/sh
set -eu
task_repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
task_tmp=$(mktemp -d)
trap 'rm -rf "$task_tmp"' EXIT
mkdir -p "$task_tmp/repository" "$task_tmp/tools" "$task_tmp/home"
cp "$task_repo/install.sh" "$task_tmp/repository/install.sh"
mkdir -p "$task_tmp/repository/bin"
cp "$task_repo/bin/tinystats" "$task_tmp/repository/bin/tinystats"
cat > "$task_tmp/repository/build.sh" <<'BUILD'
#!/bin/sh
set -eu
cd "$(dirname "$0")"
[ ! -f fail-build ] || exit 19
mkdir -p tinyStats.app/Contents/MacOS
printf '#!/bin/sh\nexit 0\n' > tinyStats.app/Contents/MacOS/tinyStats
chmod +x tinyStats.app/Contents/MacOS/tinyStats
BUILD
chmod +x "$task_tmp/repository/build.sh"
printf '/tinyStats.app/\n/fail-build\n' > "$task_tmp/repository/.gitignore"
git -C "$task_tmp/repository" init -q -b main
git -C "$task_tmp/repository" add .
git -C "$task_tmp/repository" -c user.name=Test -c user.email=test@example.invalid commit -qm initial
cat > "$task_tmp/tools/open" <<'MOCK'
#!/bin/sh
printf '%s\n' "$*" >> "$HOME/open-calls"
MOCK
cat > "$task_tmp/tools/ps" <<'MOCK'
#!/bin/sh
[ ! -f "$HOME/processes" ] || cat "$HOME/processes"
MOCK
cat > "$task_tmp/tools/swiftc" <<'MOCK'
#!/bin/sh
exit 0
MOCK
cat > "$task_tmp/tools/gh" <<'MOCK'
#!/bin/sh
exit 0
MOCK
chmod +x "$task_tmp/tools/"*
export HOME="$task_tmp/home"
export PATH="$task_tmp/tools:/usr/bin:/bin:/usr/sbin:/sbin"
unset TINYSTATS_HOME TINYSTATS_APP_DIR TINYSTATS_BIN_DIR
"$task_tmp/repository/install.sh"
task_source="$HOME/.local/share/tinystats/source"
task_cli="$HOME/.local/bin/tinystats"
task_exe="$HOME/Applications/tinyStats.app/Contents/MacOS/tinyStats"
[ -x "$task_exe" ] && [ -x "$task_cli" ]
[ "$(wc -l < "$HOME/open-calls" | tr -d ' ')" = 1 ]
"$task_cli" --version | grep 'tinyStats '
# A running owned process must not cause a second launch.
printf '123 %s\n' "$task_exe" > "$HOME/processes"
"$task_cli"
[ "$(wc -l < "$HOME/open-calls" | tr -d ' ')" = 1 ]
: > "$HOME/processes"
# A failed build leaves the installed executable intact.
printf '\n# installed sentinel\n' >> "$task_exe"
touch "$task_source/fail-build"
if "$task_source/install.sh"; then echo 'Expected build failure' >&2; exit 1; fi
grep -q 'installed sentinel' "$task_exe"
[ ! -d "$HOME/.local/share/tinystats/install.lock" ]
rm "$task_source/fail-build"
# Updates fast-forward from main, compile, install and start.
git -C "$task_source" remote set-url origin "$task_tmp/repository"
printf 'update fixture\n' > "$task_tmp/repository/revision"
git -C "$task_tmp/repository" add revision
git -C "$task_tmp/repository" -c user.name=Test -c user.email=test@example.invalid commit -qm update
"$task_cli" update
[ "$(cat "$task_source/revision")" = 'update fixture' ]
[ -x "$task_exe" ]
[ "$(git -C "$task_source" config --get-all credential.https://github.com.helper | wc -l | tr -d ' ')" = 2 ]
[ "$(git -C "$task_source" config --get-all credential.https://github.com.helper | tail -1)" = '!gh auth git-credential' ]
# User edits in managed source prevent update instead of being overwritten.
printf 'local edit\n' >> "$task_source/build.sh"
if "$task_cli" update; then echo 'Expected dirty checkout rejection' >&2; exit 1; fi
printf 'PASS: install, launcher single-instance check, build failure preservation, update, dirty checkout protection\n'
