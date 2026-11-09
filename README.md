# Systemstatus

Kleines natives macOS-Menüleisten-Tool für CPU, GPU, RAM und Netzwerk.
Drei beschriftete Füllbalken (C = CPU, G = GPU, R = RAM) zeigen Werte direkt in
der Menüleiste. Daneben stehen Download (↓) und Upload (↑), kompakt in
B/K/M/G pro Sekunde (dezimal, Bytes). Klick öffnet die Detailansicht. Ohne
externe Abhängigkeiten, Konten oder Datenuploads.

## Bauen und starten

Mit den installierten Xcode Command Line Tools:

```sh
./build.sh
open Systemstatus.app
```

Die App hat kein Dock-Symbol. Auf einem Hauptdisplay mit Notch schließt
sie rechts an die Kameraaussparung an: schwarz, weiße Indikatoren, rechts
gerundet. Ohne Notch erscheint die normale Menüleistenanzeige.
Klick auf die Indikatoren öffnet die Werte;
Außenklick oder Escape schließt die Ansicht. „Beenden“ oder ⌘Q im Popover
beendet die App. Vor dem Wechsel von einer alten Version diese beenden,
damit nur eine Instanz läuft. Autostart wird nicht eingerichtet.

Alternativ als einzelnes Binary: `swiftc -O main.swift -o hsb-mb`, dann `./hsb-mb`.

## Messwerte

- CPU: Anteil aktiver CPU-Ticks zwischen zwei Messungen.
- GPU: „Device Utilization %“ aus IOAccelerator. Auf dem vorhandenen Apple
  M5 beobachtet; auf anderer Hardware möglicherweise nicht verfügbar.
- RAM ≈: aktive + verdrahtete + komprimierte Seiten relativ zum physischen
  Speicher. Näherung, kein Speicherdruck und kein zugesicherter Gleichlauf
  mit der Aktivitätsanzeige. Erklärung auch als Tooltip an der RAM-Zeile.
- Netzwerk: getrennte Empfangs-/Senderaten aller `en`-Interfaces in dezimalen
  B/s, KB/s, MB/s oder GB/s. VPN-/Tunnel-Interfaces werden nicht separat
  mitgezählt. Kein Maß für die Kapazität der Internetverbindung.

Aktualisierung jede Sekunde. „—“ bedeutet fehlende Daten oder eine neue
Baseline (Start bzw. Interface-/Zählerwechsel); 0 ist eine gültige Messung.

## Prüfen

```sh
swiftc -typecheck main.swift
./Tests/run.sh
git diff --check
```

Die Checks verwenden echte lokale CPU-/RAM-/Netzwerkproben, prüfen den
Netzwerk-Baseline-Regressionsfall, Formatierung und Popover-Konstruktion.
Sie setzen mindestens ein `en`-Interface auf diesem Mac voraus.

Die Balken sind monochrom und füllen sich von unten nach oben. Die
Kürzel C, G und R stehen lesbar neben dem jeweiligen Balken. Ein Strich
in der Spur bedeutet fehlende Daten; eine leere Spur bedeutet gemessene 0 %.
Die Gesamtbreite bleibt bei wechselnden Werten konstant bei 96 pt. Tooltip und VoiceOver
enthalten die beschrifteten Werte und vollständigen Netzwerkeinheiten.

## Notch-Anzeige

Der Modus richtet sich nach dem primären Display (erstes NSScreen). Ein
externes Hauptdisplay ohne Notch verwendet daher die normale Menüleiste,
auch wenn das interne MacBook-Display angeschlossen bleibt. Bei Änderungen
an der Display-Anordnung wird die Position neu bestimmt.

„An Notch anzeigen“ in der Detailansicht schaltet zwischen Notch-Overlay und
normaler Menüleiste um; die Wahl wird lokal gespeichert. Auf einem Display
ohne nutzbare Notch wird die Option ausgeblendet. Messwerte und Details
bleiben in beiden Modi gleich.

macOS reserviert neben der Notch keinen Platz für dieses Overlay. Falls
andere Menüleistensymbole dort liegen, können sie verdeckt werden; dann
„An Notch anzeigen“ ausschalten. Es werden keine zusätzlichen Rechte oder
Systemänderungen benötigt. Automatisch ausgeblendete Menüleisten,
Vollbild-Spaces und der Wechsel zwischen mehreren echten Displays sind
noch nicht live geprüft; die Panel-Konfiguration erzwingt keine Anzeige
über Vollbild-Apps.
