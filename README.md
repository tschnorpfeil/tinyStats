# tinyStats

CPU, GPU, RAM and network activity beside your MacBook's notch. On displays without a notch, it lives in the menu bar. Click to open the details.

<img src="docs/images/notch-collapsed.png" alt="tinyStats collapsed beside the notch" width="480">

| With a notch | Without a notch |
| :---: | :---: |
| ![tinyStats beside the notch with details open](docs/images/notch.png) | ![tinyStats in the menu bar with details open](docs/images/menu-bar.png) |

*Native renderings with sample values.*

The three bars show CPU, GPU and RAM, from left to right. Upload ↑ and download ↓ sit alongside them. RAM usage is an estimate; GPU readings aren't available on all hardware.

## Install

Requires macOS 14+ and Xcode Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/tschnorpfeil/tinyStats.git && ./tinyStats/install.sh
```

Then open a new terminal:

```sh
tinystats          # start
tinystats stop     # quit
tinystats update   # update
tinystats status   # check whether the app is running
tinystats version  # installed version
```

No automatic startup. No Dock icon. If the widget covers other menus, turn off “Notch” in the details.

[Installation, troubleshooting and removal](INSTALL.md)

## Develop

```sh
./build.sh
open tinyStats.app
./Tests/run.sh
./Tests/install.sh
```
