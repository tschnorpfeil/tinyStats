# tinyStats

CPU, GPU, RAM, battery, disk and network activity beside your MacBook's notch. On displays without a notch, it lives in the menu bar. Click to open the details.

<img src="docs/images/notch-collapsed.png" alt="tinyStats collapsed beside the notch" width="480">

| With a notch | Without a notch |
| :---: | :---: |
| ![tinyStats beside the notch with details open](docs/images/notch.png) | ![tinyStats in the menu bar with details open](docs/images/menu-bar.png) |

*Native renderings with sample values.*

The three bars match the three tiles in the details: CPU, GPU and RAM by default, from left to right. Upload ↑ and download ↓ sit alongside them. Below the tiles, the other metrics are grouped under Power (battery charge, power usage, charging rate), Storage (free space, disk activity) and System (swap). RAM usage is an estimate; GPU readings aren't available on all hardware. Macs without a battery don't show the battery metrics.

To customize, click the gear in the details. Each tile can show CPU, GPU, RAM, Battery or Disk, and the menu bar can show any one metric instead of network activity.

## Install

Requires macOS 14+. With [Homebrew](https://brew.sh):

```sh
brew tap tschnorpfeil/tinystats https://github.com/tschnorpfeil/tinyStats
brew install tschnorpfeil/tinystats/tinystats
```

Homebrew builds the app on your Mac, so no signed download is needed. The full name `tschnorpfeil/tinystats/tinystats` also marks the formula as trusted, which Homebrew requires for third-party taps. Without Homebrew, install Xcode Command Line Tools (`xcode-select --install`) and run:

```sh
git clone https://github.com/tschnorpfeil/tinyStats.git && ./tinyStats/install.sh
```

Then open a new terminal:

```sh
tinystats          # start
tinystats stop     # quit
tinystats update   # update and restart (also after brew upgrade)
tinystats status   # check whether the app is running
tinystats version  # installed version
```

No automatic startup. No Dock icon. If the widget covers other menus, click the gear in the details and turn off “Show Beside Notch”.

[Installation, troubleshooting and removal](INSTALL.md)

## Develop

```sh
./build.sh
open tinyStats.app
./Tests/run.sh
./Tests/install.sh
```

To release, raise `CFBundleShortVersionString` in `build.sh` and the `tag:` in `Formula/tinystats.rb`, merge, then push the matching tag, e.g. `git tag v2.0 && git push origin v2.0`.
