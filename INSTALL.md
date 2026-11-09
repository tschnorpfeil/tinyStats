# Install and update tinyStats

## Homebrew

```sh
brew tap tschnorpfeil/tinystats https://github.com/tschnorpfeil/tinyStats
brew install tschnorpfeil/tinystats/tinystats
```

The full formula name marks it as trusted, which Homebrew requires for third-party taps. The app lives in Homebrew's Cellar and `tinystats` is linked into Homebrew's `bin`. `tinystats update` runs `brew upgrade tschnorpfeil/tinystats/tinystats` and restarts the app. After a plain `brew upgrade`, run `tinystats stop && tinystats` to switch to the new version. Remove with `tinystats stop && brew uninstall tinystats && brew untap tschnorpfeil/tinystats`.

Coming from the Git installer? Remove that installation first (see Remove below), otherwise `~/.local/bin/tinystats` shadows the Homebrew command.

## Git installer

Requires macOS 14+, Git and Xcode Command Line Tools (`xcode-select --install`). No GitHub account needed.

```sh
git clone https://github.com/tschnorpfeil/tinyStats.git && ./tinyStats/install.sh
```

From an existing checkout, run `./install.sh`. The installer builds locally and creates:

- `~/Applications/tinyStats.app` — the app
- `~/.local/bin/tinystats` — the terminal command
- `~/.local/share/tinystats/source` — the managed source checkout used for updates

You no longer need the original download folder. If needed, the installer adds `~/.local/bin` to `~/.zprofile` for new zsh terminals. It won't overwrite an unrelated `tinystats` command. No sudo, extra runtime dependencies or automatic startup.

```sh
tinystats          # start
tinystats status   # check whether the installed app is running
tinystats stop     # quit the installed app and wait until it has
tinystats version  # commit of the installed app
tinystats update   # fetch main, build, install and restart
```

If the command isn't on your current PATH, open a new terminal or run the `export PATH=…` line printed by the installer.

## Updates

Updates fast-forward from `origin/main`. Local changes in the managed checkout stop the update; they aren't discarded. The app is built before replacing the installed version. If the build fails, the old app stays in place. Starting an already running app doesn't launch another instance.

The update lock covers fetching through installation. `tinystats version` reads metadata from the installed app, even if a failed update has advanced the source checkout. For older installations without this metadata, run `tinystats update` once.

## Troubleshooting

- **`command not found: tinystats`:** Open a new terminal, or use `~/.local/bin/tinystats` directly.
- **Build failed:** Check the Swift error. Install Apple's tools with `xcode-select --install` if needed, then retry `tinystats update`. The installed app remains intact.
- **Local changes in the installation checkout:** Review and back up or commit your changes under `~/.local/share/tinystats/source` before updating.
- **Installation already running:** Let it finish. After a crash, an empty `~/.local/share/tinystats/install.lock` directory may remain. Only when no installer or updater is running, remove it with `rmdir ~/.local/share/tinystats/install.lock`.
- **App not visible:** Run `tinystats status`. Quit any running development copy first; tinyStats prevents multiple instances. On a notched display, look to the right of the camera housing.

## Remove

Run `tinystats stop`, then remove `~/Applications/tinyStats.app`, `~/.local/bin/tinystats` and `~/.local/share/tinystats`. Back up any source changes first. You may remove the PATH entry marked `# tinyStats CLI` in `~/.zprofile`, but other tools may use the same directory. There is no background service or startup entry.

## Test the installer

```sh
./Tests/install.sh
```

This uses an isolated installation. Override paths with `TINYSTATS_HOME`, `TINYSTATS_APP_DIR` and `TINYSTATS_BIN_DIR`; use the same variables for later CLI calls.
