# tinyStats

Kleines natives macOS-Werkzeug für CPU, GPU, RAM und Netzwerk, weiß auf
schwarz. Ohne externe Abhängigkeiten, Konten oder Datenuploads.

## Installieren und starten

Das private Repository benötigt GitHub-Zugriff (`gh auth login`). Installation:

```sh
gh repo clone tschnorpfeil/tinyStats && ./tinyStats/install.sh
```

Danach genügt im Terminal:

```sh
tinystats          # starten
tinystats update   # main abrufen, bauen und neu starten
tinystats status
tinystats stop
tinystats version
```

Die App liegt unter `~/Applications/tinyStats.app`, der Befehl unter
`~/.local/bin/tinystats`. Details zu Voraussetzungen, PATH und Updates:
[INSTALL.md](INSTALL.md).

## Aus dem Quellcode bauen

Mit den installierten Xcode Command Line Tools:

```sh
./build.sh
open tinyStats.app
```

Die App hat kein Dock-Symbol und richtet keinen Autostart ein. Sie läuft je
Sitzung nur einmal: Ein weiterer Start (auch direkt über das Binary, mit
`open -n` oder eine ältere `Systemstatus.app`) beendet sich sofort mit
„tinyStats läuft bereits (PID …)“. Für eine neue Version daher erst die
laufende beenden. Die Bundle-ID bleibt `local.hsb.systemstatus`, damit die
gespeicherte Notch-Einstellung erhalten bleibt.

Alternativ als einzelnes Binary: `swiftc -O main.swift -o tinystats`, dann `./tinystats`.

## Anzeige

**Notch-Flügel.** Hat das primäre Display eine Kameraaussparung, sitzt rechts
daneben ein schmaler schwarzer Flügel mit den Indikatoren: drei Füllbalken
ohne Beschriftung, fest von links nach rechts CPU, GPU, RAM (Tooltip und
VoiceOver nennen Namen und Werte), daneben zweizeilig Upload (↑, oben) und
Download (↓, unten) in B/K/M/G pro Sekunde. Die Unterkante liegt auf der
tatsächlichen Unterkante des Gehäuses und läuft gerade aus der Notch heraus;
dafür reicht die Fläche 36 pt hinter das Gehäuse und schließt dessen untere
Rundung. Oben rechts geht der Flügel mit einer konkaven Gegenkrümmung in die
Displaykante über, unten rechts endet er mit einer konvexen Rundung.

**Normale Menüleiste.** Ohne Notch (etwa an einem externen Hauptdisplay) oder
wenn „Notch“ ausgeschaltet ist, erscheint dieselbe Grafik als normales
Menüleistensymbol.

**Details.** Ein Klick auf Flügel oder Symbol lässt die Details als schwarze
Insel aus der Quelle wachsen: an der Notch genau auf die Gesamtbreite aus
Gehäuse und Flügel. Links schließt sie bündig mit der Notch ab, rechts mit dem
unverändert breiten Flügel. Im normalen Menüleistenmodus schwebt die Karte
zentriert unter dem Symbol, mit 6 pt Abstand und rundum gerundeten Ecken.
Die Notch-Anschlussform wird dort nicht verwendet. Inhalt:

- CPU, GPU und RAM ≈ nebeneinander mit großem Wert und schmalem Balken,
- Upload und Download in einer ruhigen Leiste darunter (Leserichtung wie in
  der Menüleiste: erst Upload, dann Download),
- Fußzeile mit „tinyStats“, Schalter „Notch“ (nur mit Notch) und „Beenden“.

Die Bewegung läuft über eine gedämpfte Feder: Die Form spreizt sich aus der
Quelle, sinkt nach unten und blendet den Inhalt erst ein, wenn Platz ist.
Erneutes Klicken während der Bewegung kehrt sie aus der aktuellen Lage um.
Bei „Bewegung reduzieren“ wird nur kurz überblendet. Die sekündlichen Werte
ändern nur Text und Balken, nie das Layout.

Klick auf Flügel oder Symbol, Klick daneben, Escape oder ein App-Wechsel
schließen die Insel. ⌘Q oder „Beenden“ beenden die App. Die Insel ist ein
nicht aktivierendes Panel: Die vordere App bleibt aktiv, ihre Menüs bleiben
sichtbar.

## Messwerte

- CPU: Anteil aktiver CPU-Ticks zwischen zwei Messungen.
- GPU: „Device Utilization %“ aus IOAccelerator. Auf dem vorhandenen Apple
  M5 beobachtet; auf anderer Hardware möglicherweise nicht verfügbar.
- RAM ≈: aktive + verdrahtete + komprimierte Seiten relativ zum physischen
  Speicher. Näherung, kein Speicherdruck und kein zugesicherter Gleichlauf
  mit der Aktivitätsanzeige. Erklärung auch als Tooltip an der RAM-Spalte.
- Netzwerk: getrennte Empfangs-/Senderaten aller `en`-Interfaces in dezimalen
  B/s, KB/s, MB/s oder GB/s. VPN-/Tunnel-Interfaces werden nicht separat
  mitgezählt. Kein Maß für die Kapazität der Internetverbindung; die Raten
  werden deshalb nicht als Balken gegen eine erfundene Obergrenze gezeigt.

Aktualisierung jede Sekunde. „—“ bedeutet fehlende Daten oder eine neue
Baseline (Start bzw. Interface-/Zählerwechsel); 0 ist eine gültige Messung.
In der Menüleiste steht ein Strich statt der Balkenspur für fehlende Daten,
eine leere Spur für gemessene 0 %. In den Details ist die Spur bei fehlenden
Daten gepunktet, bei 0 % leer. Tooltip und VoiceOver enthalten die
beschrifteten Werte und vollständigen Netzwerkeinheiten.

## Grenzen der Notch-Integration

- Der Modus richtet sich nach dem primären Display (erstes NSScreen). Bei
  Änderungen an der Display-Anordnung wird die Position neu bestimmt.
- macOS reserviert neben der Notch keinen Platz für fremde Fenster. Apps mit
  vielen Menüs (etwa Safari auf Deutsch) legen „Fenster“ und „Hilfe“ rechts
  neben die Notch; der Flügel verdeckt sie dann. Öffentliche APIs melden
  diese Belegung nicht. In dem Fall in den Details „Notch“ ausschalten: Das
  normale Menüleistensymbol wird vom System platziert und überdeckt nichts.
- Öffentlich meldet macOS das Gehäuse nur in ganzen Punkten
  (`auxiliaryTopLeftArea`, `auxiliaryTopRightArea`, `safeAreaInsets.top`,
  hier 32 pt). Die tatsächliche Unterkante liegt bei 32,17 pt (Pixelzeile 56
  des Panels). tinyStats liest sie aus AppKits eigenem Displayumriss
  (`bezelPath` von NSScreen, nicht dokumentiert, nur gelesen) und nutzt ihn
  nur, wenn er auf einen Punkt genau mit den öffentlichen Werten
  übereinstimmt; sonst gilt die Safe Area. Die untere rechte Gehäuserundung
  (hier 14,6 pt) liegt innerhalb der Überlappung. Die linke Rundung der Insel
  setzt 18 pt neben der linken Gehäuseecke an der geraden Unterkante an.
- In skalierten Auflösungen (etwa „1470 × 956“ auf dem 2560 × 1664-Panel)
  rechnet macOS das Bild auf das Panel herunter. Die gezeichnete Unterkante
  des Flügels liegt dann an derselben Stelle wie die Gehäusekante, bleibt
  aber weicher (Übergang über etwa zwei Panelpixel), während die Gehäusekante
  hart ist.
- Automatisch ausgeblendete Menüleisten, Vollbild-Spaces und der Wechsel
  zwischen mehreren echten Displays sind nicht live geprüft; die Panels
  erzwingen keine Anzeige über Vollbild-Apps.

## Prüfen

```sh
swiftc -typecheck main.swift
./Tests/run.sh
git diff --check
```

Die Checks verwenden echte lokale CPU-/RAM-/Netzwerkproben (mindestens ein
`en`-Interface nötig) und prüfen außerdem Formatierung, die
Menüleisten-Grafik in Pixeln (drei Balken ohne Buchstaben, fehlend gegenüber
0 %), Flügel- und Inselgeometrie mit den echten Notch-Werten dieses Macs, die
Unterkante aus dem Displayumriss samt Rückfall auf die Safe Area, die beiden
Formvorgaben (konkave Ecke oben rechts, gerade Unterkante in die Notch),
Federverlauf inklusive Umkehr, festes Layout bei Wertänderungen,
Event-Routing (Escape, ⌘Q, Klick innen/außen/auf die Quelle) und native
Offscreen-Renderings auf reine Schwarz-Weiß-Pixel. Offscreen-Renderings sind
kein Nachweis der Live-Darstellung.
