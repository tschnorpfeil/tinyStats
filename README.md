# HSB-MenuBar

Natives macOS-Menüleisten-Tool, das Systemwerte (CPU, GPU, RAM, Netzwerk)
als Balken in der Menüleiste anzeigt. Implementiert in AppKit/Swift,
ohne externe Abhängigkeiten.

## Build

```sh
swiftc main.swift -o hsb-mb
```

## Start

```sh
./hsb-mb
```

## Hinweis

Bevor eine neue Instanz gestartet wird, muss eine bereits laufende
Instanz beendet werden. Keine zwei Instanzen gleichzeitig starten.
