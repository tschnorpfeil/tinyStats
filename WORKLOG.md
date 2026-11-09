# Systemstatus Fertigstellung

## Umfang

Basis für den lokalen Review: fc06bc60f621913f55f99920729bad2faf6e0b77.
Der bereits begonnene Symbol-Umbau in main.swift gehört zur Aufgabe und
wird erhalten. Kein Remote vorhanden, kein Push oder PR vorgesehen.
Review-Diff in allen Runden: `git diff fc06bc60f621913f55f99920729bad2faf6e0b77 -- main.swift .gitignore README.md build.sh Tests WORKLOG.md`, dazu untracked Dateien lesen.

## Aufgaben

- [x] Istzustand und uncommittierten Symbol-Umbau prüfen
- [x] Netzwerk-Baseline nach erfolgreicher Probe aktualisieren
- [x] CPU/RAM bei fehlenden Daten optional darstellen
- [x] Popover mit Systemsymbolen, Trennlinien, kleiner Beenden-Aktion gestalten
- [x] Regressionstest und Formatierungs-/Konstruktionschecks ausführen
- [x] Eigenständiges App-Bundle bauen und Plist prüfen
- [x] Neue Version starten (Systemstatus.app, PID 90040 vor finalem Neubau)
- [x] Layout-Geometrie per nativer Offscreen-Konstruktion prüfen (300 × 260 pt)
- [x] Sol-Review abschließen
- [x] Finale Version bauen und neu starten
- [x] Abschlussstand lokal zum Commit vorbereiten

## Prüfungen und Grenzen

Swift-Typprüfung, kompilierte Checks und Build erfolgreich. Native
Offscreen-Konstruktion bestätigt die Geometrie; sie ersetzt keinen Test
von Klick, Escape, Außenklick oder der Live-Darstellung im Popover.
Computer Use kann das Bundle nicht auswählen (timeoutReached); das lose
Binary ist kein gültiges App-Ziel. Daher keine behauptete Live-UI-Prüfung.
Auf Wunsch des Nutzers darf die alte Instanz ohne Binary-Sicherung ersetzt
werden. Keine Systemeinstellungen oder Autostart-Einträge angelegt.

## Sol Ledger

Budget: maximal 3 Runden. Modell aus Capabilities: codex / gpt-6.1-sol.
Runde 1: APPROVE, keine blocker/should/nit-Findings. Keine Review-Fixes
notwendig, keine Findings abgelehnt. Modell gpt-6.1-sol, Effort medium
laut Tool-Metadaten. Usage nicht zurückgegeben. Kein Push.
Nach dem Review nur dieses Arbeitsprotokoll aktualisiert; Verhaltens-Diff
unverändert. Finale Typprüfung, Checks, optimierter Build und Plist-Lint
bestanden. Genau eine finale App-Instanz bestätigt, Startlog leer.
Diff vor Review: 3 tracked Dateien, 175 Einfügungen / 247 Löschungen;
neue Build-/Test-/Arbeitsdateien zusätzlich, vor Round 1 separat erfasst.

Review-Diff vor/nach der einen Runde unverändert: tracked Code/Dokumentation
175 Einfügungen / 247 Löschungen; neue Dateien vor Review 106 Zeilen,
dieses Protokoll danach um Abschlussdaten ergänzt.

# Direkte Menüleistenindikatoren

Basis: 9e48a65b316ab85b71d19354326dc7b12c1fbe88. Kein Remote.
Intent: drei monochrome Füllbalken (CPU/GPU/RAM) plus zweizeilige
Download-/Upload-Raten direkt in der Menüleiste, fest 120 pt breit.
Messlogik und Popover unverändert. Keine Einstellungen oder Historien.
Review-Diff für alle Runden:
`git diff 9e48a65b316ab85b71d19354326dc7b12c1fbe88 -- main.swift Tests/checks.swift README.md WORKLOG.md`.

- [x] Indikatoren und kompakte Byte-Raten implementieren
- [x] Fehlende Werte von gemessener Null unterscheiden
- [x] Tooltip und Accessibility um vollständige Netzwerkraten ergänzen
- [x] Typprüfung, bestehende Checks, Rasterisierung und Textbreiten prüfen
- [x] Native Grafik in Menüleistengröße offscreen rendern und ansehen
- [x] Sol-Review (maximal 3 Runden) abschließen
- [x] Finale Version bauen, starten und für lokalen Commit vorbereiten

Grafik: 108 × 22 pt, 12 pt zusätzliche Button-Ränder. Drei 7 × 16 pt
Balken; darunter keine unlesbaren Buchstaben. Leere Spur für Null,
Strich für fehlende Messung. Netzwerk dezimal B/K/M/G pro Sekunde;
ab 1 TB/s kompakt ≥1T. Keine Normierung auf Leitungskapazität.
Live-Klicktest weiterhin nicht ausgeführt (Computer Use zuvor Timeout).

## Sol Ledger Indikatoren

Runde 1: APPROVE. Modell: codex / gpt-6.1-sol, Effort medium.
Keine Findings, keine Review-Fixes, keine abgelehnten Findings.
Usage nicht zurückgegeben. Kein Push. Reviewer führte Typprüfung und
Diff-Check selbst aus. Nach Review nur Abschlussprotokoll ergänzt.
Verhaltens-Diff unverändert: +98 / -9 Zeilen ohne Arbeitsprotokoll.
Diff vor Review ohne Protokoll: 3 Dateien, +98 / -9 Zeilen.

Finale Checks und Build bestanden. Genau eine App-Instanz (PID 92757)
läuft, Startlog leer: /tmp/hsb-systemstatus-indicators.log. Live-Klicktest bleibt offen.

# Council Designrunde Menüleiste

Auslöser: Screenshot des Nutzers zeigt verschwendeten Horizontalraum und
nicht unterscheidbare CPU-/GPU-/RAM-Balken. Exploration eines Ersatzdesigns,
daher vor der Designrunde keine Änderungen am zu ersetzenden Renderer.
Basis db78c68. Arbeitsbaum vor Beginn sauber.

- [x] Gewünschte Modelle auflösen: Opus 5.5, Gemini 4 Argon, GPT 6.1 Sol
- [x] Drei unabhängige Designvorschläge lesen und zusammenführen
- [x] Kompaktes, unterscheidbares Design umsetzen und prüfen
- [x] Umsetzung dem Council erneut vorlegen
- [x] Council-Ergebnis bewerten und Stand lokal sichern
- [ ] Start durch neue Nutzeridee Notch-Integration abgelöst

Council arbeitet lesend. Alle drei Modelle mit high reasoning. Keine PR/CI.

## Council Runde 1 Ergebnisse und Umsetzung

| Modell | Ist-Design Runde 1 | Umsetzung Runde 2 |
| --- | --- | --- |
| Opus 5.5 | 5/10 | 8/10 SATISFIED |
| Gemini 4 Argon | 4/10 | 9/10 SATISFIED |
| GPT 6.1 Sol | 4/10 | 9/10 SATISFIED |

Gemeinsame Diagnose: gleiche Balken nicht zuordenbar; ~42 pt Loch bei 1K.
Opus: C/G/R neben Balken, ca.100pt. Gemini: kleine Monogramme unter Balken,
86pt. Sol: volle CPU/GPU/RAM über Querbalken,110pt. Der Nutzer hat danach
C/G/R ausdrücklich als ausreichend bestätigt. Daher Opus-Richtung gewählt,
aber Geometrie anhand echter Fontmessungen statt Schätzung: 88×22pt Bild,
8pt Button-Ränder, insgesamt96pt. Drei17pt-Spalten,11pt Semibold-Kürzel,
5×14pt-Füllbalken,36pt Netzwerkblock. ≥2pt Abstand zwischen Pfeil und
breitester Rate. SF9-Netzwerkschrift: 999M misst tatsächlich26.06pt;
die früheren Schätzungen von ca.22pt waren zu klein. Tests nun für de_DE
ausgeführt sowie en_US, jede maximale Zeichenfolge und Fontbreite.
Keine künstliche Mindestfüllung, keine zusätzliche Warnschwelle, keine
Farbcodierung; proportionale Werte. Null: leere Spur. Unbekannt: Strich
statt Spur. Vollständige Namen/Einheiten und „Nicht verfügbar“ im Tooltip
und Accessibility-Wert. Format-Rundung bei999.5GB/s auf1T korrigiert,
damit kein fünfstelliges1000G den Netzwerkblock sprengt.

Native Offscreen-Renderings für Runde2:
/tmp/hsb-council-light.png und /tmp/hsb-council-dark.png.
Fünf Zustände: Screenshot-Werte, normal,0/niedrig/100%,unbekannt,Maximaltext.
Renderings visuell geprüft, keine Kollisionen. Native Live-UI weiter offen.
Checks: Typprüfung,Tests/run.sh,Build,Diff-Check erfolgreich. Keine PR/CI.

Alle drei Reviewer SATISFIED; keine Blocker. Opus' Hinweis zum Abstand
R→Netz als optischen Nit eingeordnet:17→16pt verschlechtert die Abstände
zwischen den drei Gruppen. Unverändertes geprüftes Layout beibehalten.
Nutzerwechsel auf Notch-Idee vor dem Neustart. Der96pt-Stand wird als
Fallback-Basis committet; keine Änderungen gehen verloren.


# Notch-Prototyp

Nutzerentscheidung: rechts an echter Notch, weiß auf schwarz; auf primärem
Display ohne Notch normale Menüleiste. Dirigent-Bau mit explizit erlaubtem
shared Opus5.5-Builder, weil T3 keinen projektübergreifenden Worktree zuließ.
Basis af1f697, Buildercommit3548266. Änderungen nur main.swift und Checks,
kompletten Diff selbst gelesen. Keine Messlogikänderung.

- [x] Display-Geometrie lesen (1470×956,Notchrand824.5,32pt hoch)
- [x] Notch-Overlay und Menüleisten-Fallback bauen
- [x] Checkbox zum Zurückwechseln bei Platzkonflikten
- [x] Geometrie, Form, Farbmaske, Checkbox und Build lokal prüfen
- [x] Native Offscreen-Grafik selbst ansehen
- [ ] Live-Start und Bedienung prüfen
- [x] Sol-Review abschließen
- [x] Abschlussstand für lokalen Commit vorbereiten

Öffentliche AppKit-APIs, keine neuen Berechtigungen. Notch-Frame auf diesem
Mac: (824.5,924,108,32). Mono, nur rechteAußenecken8pt rund. Statusitem
im Notchmodus unsichtbar, Panel nicht aktivierend, eineTimerquelle bleibt.
Die Detailansicht ist in beiden Modi identisch und bietet die Rückkehr.

Grenzen: Platz neben der Notch ist nicht reserviert. Kein automatischer
Nachweis freier fremder Statusitem-Flächen. Primäres Display bestimmt Modus.
Vollbild/Autohide/MultiDisplay noch nicht live geprüft. Testausgaben belegen
Geometrie und Offscreen-Rendering, keine Live-Bedienung.

Live-Start: PID10896,Log /tmp/hsb-notch.log leer. ComputerUse kann weder
Systemstatus noch Finder-Fenster erfassen: cgWindowNotFound. Daher Live-
Position,Klicks undTastatur weiter offen; gestarteterProzess ist keinUI-Beleg.

## Sol Ledger Notch

Basis af1f6970139abc700359e38038cd2a10178b0c5e, maximal3Runden.
Runde1 vorbereitet; gpt-6.1-sol/high. Noch keine Findings. Usage nur falls
zurückgegeben. GleicherDiff für alleRunden:
`git diff af1f6970139abc700359e38038cd2a10178b0c5e -- main.swift Tests/checks.swift README.md WORKLOG.md`.

Sol-Notch-Runde1: APPROVE, gpt-6.1-sol/high. Keine blocker/should.
S1 nit:300ms-Sperre kann sehr schnelle eigenständigeWiederöffnungsversuche
nachEscape/Außenklick unterdrücken. FürPrototyp zurückgestellt; seltene
Schnellklickfolge,kein belegterFehler im normalenÖffnungspfad. Ereignisgenaue
Unterdrückung alsFollow-up vormerken,nicht ohneLive-Reproduktion umbauen.
KeineReview-Codeänderung,keinezweiteRunde nötig. Usage nicht zurückgegeben.
Review-Diff vor/nach unverändert:+330/-8 über4Dateien; nur diesesProtokoll
wird danach umAbschlussdaten ergänzt. Code+Tests:+274/-7 unverändert.

LaufendeVersion nachReview weiterPID10896,Startlogleer. KeineQuelländerung
nachBuild,keinNeustart nötig. Branch feat/notch-status. KeinRemote,keinPush,
keinPR/CI,keineVeröffentlichung. Nutzer wird umBestätigung vonLive-Position
undKlick gebeten,daComputerUse cgWindowNotFound meldet.


## 2026-11-09 — Attached details and animation
- [x] User confirmed notch display and click work on the preceding build.
- [x] Replace NSPopover and blanket 300-ms click suppression with an arrowless black attached panel.
- [x] Fixed window geometry, 140-ms opacity animation, Reduce Motion respected, transition token prevents stale close completions hiding a reopened panel.
- [x] Outside click, Escape and app deactivation close; source click toggles without a delay.
- [x] Left-aligned title and forced dark appearance; existing metrics and primary-display fallback retained.
- [x] Local checks, render inspection, two-round review and restart.

Review R1: CHANGES, S1 should: top 6pt overlap intercepted clicks in the source. Fixed by lowering panel exactly 6pt, so its top meets source bottom without overlap. Updated geometry assertions and regression assertion of disjoint frames. No other findings; usage not returned. R2 checks changed geometry and S1 only.

R2: APPROVE; S1 resolved, no remaining findings. Reviewed with gpt-6.1-sol/high, 2 rounds; usage not returned. Diff R1 +171/-21, after focused fix +174/-21 (before final documentation). No declined findings. One local check run failed at existing CPU live-sample assertion after 50 ms; CPU may return nil when no tick delta exists or host query fails. Exact cause was not captured. Reviewer rerun and own subsequent complete rerun passed; UI code does not change sampling. Not claiming the existing timing-dependent test is deterministic. No measurement/test-scope expansion in this UI change.

Installed build started as PID 18961; preceding exact executable PID 10896 terminated. /tmp/hsb-attached.log empty after startup. Live UI retry through cua.getApp(local.hsb.systemstatus) failed timeoutReached (-10005). Therefore actual interaction/animation remains unverified; offscreen render and review are not live proof. No push, PR, CI or remote (none configured).

## 2026-11-09 — Full-send redesign with Opus 5.5
User rejects 03d0164 screenshot: black rectangular utility table, visible rectangular attachment and no convincing integrated expansion. Requested ownership of UI, UX, layout, design, animation and integration with Opus 5.5.
- [x] Opus redesign and implementation, including rendered visual iteration and runtime proof where available.
- [ ] Parent visual assessment and local checks. (Local checks done by Opus, see below; parent assessment pending.)
- [ ] Sol review and focused corrections.
- [x] Build, install/restart and verify one process; document actual proof and any limitations. (Opus build; repeat after review fixes.)
Existing scope: monochrome white on black; right-adjacent notch on supported primary display, native menu bar fallback without notch; preserve CPU/GPU/RAM/network measurement semantics. No remote configured; no GitHub destination exists to file/merge a PR. Do not invent one.

### Opus implementation notes (tinyStats)

Starting state, checked before assuming anything: the first screenshot (3e13ee25) came from the menu bar fallback. At that time the primary display was the external LEN P27h-10 (2560×1440 @1x, menu bar 30 pt, no notch). The details window list showed 300×268 at CG y 25, and the old 6 pt "chimney" stuck up into the transparent blue bar. The second screenshot (f1321328) came from notch mode after the built-in display became primary: 1470×956 @2x, housing 645.5…824.5 × 32 pt, wing window at 824 (AppKit had rounded 824.5 down). `showAtNotch` is unset, so it is true by registration. Safari's German menus overflow right of the housing, and the old wing covered "Fenster" and the start of "Hilfe". The geometry confirms the screenshot shows this collision.

User acceptance criteria, fixed in geometry and checks:
- Upper-right of the wing: concave reverse curve (7 pt) into the display's top edge, no convex radius. The path checks this, and so do rendered pixels.
- Lower-left of the wing: continues straight into the housing's lower edge. The wing window reaches 36 pt behind the housing and paints its lower edge through the housing's unknown lower-right rounding. No hardware radius is assumed; the composites only simulate one (r = 8 pt) for viewing.
- Upload ↑ on top and download ↓ below in the menu bar indicator. In the details the reading order is upload, then download, also for VoiceOver, tooltip and summary. Every row keeps its own measured rate (checks).

Design decisions:
- One silhouette rule: concave where black attaches to the bezel, housing or bar; convex where it ends freely.
- Notch mode: the details hang under housing and wing as one black island. Its right edge continues the wing; the wing's lower-right corner squares off as the island attaches. Its left edge meets the housing's straight lower edge with a concave 10 pt fillet, 18 pt from the housing's own corner, so it does not depend on that corner. Width = housing + wing − 28 pt (255 pt here), at least 248 pt for large-text scaling. No overlap with the wing window, so source clicks always reach the wing.
- Fallback: the island hangs from the bar's lower edge (visibleFrame top, never above the button), centred under the item, 272 pt wide, with concave fillets on both sides and the native status-item highlight. It is clamped to the screen and honours secondary-screen origins. This is different geometry because there is no black source in the bar.
- Window frames lie on whole points, because AppKit rounds window origins. The drawing uses sub-point offsets, so the 824.5/928.5 edges stay exact on 2x.
- Content: three columns (caption, SF Rounded 24 pt value with a smaller %, a 3 pt proportional meter: empty track for 0, dotted for missing, "—" for missing values). Below them a quiet upload/download tray with no capacity bar, then a footer with the tinyStats wordmark, a monochrome "Notch" switch (only shown with a housing) and "Beenden" (⌘Q). Tabular digits and fixed frames mean 1 Hz samples never re-layout.
- Motion: one spring on the display link (opening response 0.42 s, damping 0.8, about 1 % overshoot; closing 0.26 s, critically damped). Width leads height, and the content fades in and drops 8 pt only once the body has room, clipped to the body. Reversal retargets in flight. Reduce Motion: 150 ms crossfade. Stalled frames are capped at 1/15 s.
- Interaction: non-activating key panel, so the front app and its menus stay. Escape (local monitor and cancelOperation), ⌘Q, outside click (global and local), clicks in transparent window parts and another app's activation all close it. Our own activation is ignored. The routing is pure and tested. During closing the panel ignores mouse events.
- Branding: tinyStats (wordmark, accessibility labels, README). The bundle is renamed to tinyStats.app with executable tinyStats. The bundle id stays local.hsb.systemstatus, so the notch preference carries over. LSMinimumSystemVersion is 14.0 (display link and clipsToBounds).
- Removed: NSPopover-era StatusViewController table, AttachedSurface/DetailsPanel/AttachedDetails (rectangular bridge), NotchOverlay* and NotchGeometry. There is one presenter (IslandPresenter).

Known constraint, not solved by design: macOS reserves no space beside the housing, and public APIs do not report where app menus end. Overflow menus can sit under the wing. The documented remedy is the "Notch" switch, which uses the system-placed status item. No hiding of foreign UI, no fake reservation, no Accessibility permission.

Evidence (this session):
- `swiftc -typecheck main.swift` ok. `./Tests/run.sh`: 9 PASS blocks (live samples; formatting; indicator order; wing geometry and the concave/seamless criteria in path and pixels; island attach and bounds for p 0…1.03; spring opening, closing, reversal and stalls; content fits 248/255/272 with no re-layout; routing for Escape, ⌘Q, inside, outside and source; island render monochrome). The CPU live check now waits up to 2 s for a tick delta instead of assuming one within 50 ms; the value is still range-checked and measurement code is unchanged. `./build.sh` ok, `plutil -lint` ok, `git diff --check` ok.
- Native offscreen renders of the real WingView, IslandView and IslandContentView, composited over the user's two screenshots (housing simulated, r = 8 assumed), saved in /private/tmp/claude-501/-Users-ts--t3-scratch-2026-11-08-ich-habe-von-einem-lokalen-298c78ca/f1f97544-a6ff-4630-b8ce-2f12a87679de/scratchpad/render/out/: notch-open-{0..3}-{dark,light}.png (typical/0/high/nil), notch-closed-*.png, *-contour.png, zoom-*.png, fallback-open-{0..3}.png, motion-*-60fps.png, motion-open-close-50fps(@2x).gif, motion-keyframes.png. These are offscreen evidence, not a live capture.
- Runtime probe: the real IslandPresenter on this Mac's window server and display link. The island window measured X 663, Y 32, 266×154 (CG). Opening took 38–39 ticks at about 16.9 ms (60 Hz) and reached 95 % at 243–253 ms, with the largest step 0.11 per frame. The panel was key while the front app stayed "Vorschau". Escape (via NSApp.sendEvent and the local monitor) closed it in 28 ticks. Reversal (open, close at 120 ms, reopen at 220 ms) stayed continuous (largest step 0.106) and ended open and key. ⌘Q reached applicationWillTerminate. One earlier run was closed by a real Terminal activation (an observed notification, not caused by tinyStats).
- Live app: the old exact executable /Users/ts/HSB-MenuBar/Systemstatus.app/Contents/MacOS/Systemstatus (PID 18961) was stopped. /Users/ts/HSB-MenuBar/tinyStats.app/Contents/MacOS/tinyStats runs as a single instance and its log is empty. The stale generated bundle Systemstatus.app (ignored build output from 03d0164) was moved to /private/tmp/claude-501/-Users-ts--t3-scratch-2026-11-08-ich-habe-von-einem-lokalen-298c78ca/f1f97544-a6ff-4630-b8ce-2f12a87679de/scratchpad/old-Systemstatus.app, so it can no longer start a duplicate instance. It can be rebuilt from git. The wing window is on screen at CG X 788, Y 0, 148×32, layer 25 (matches the computed frame).

Limitations: this session has no CUA tool, and `screencapture` is denied (no Screen Recording permission). So there is no live screenshot, and no live mouse test of wing or status item clicks, hover or fallback highlight. The visual proof is offscreen plus window-server geometry plus runtime timing. Whether transparent window regions pass clicks through is unverified, so treat them as captured: they close the island. The fallback composite's button position is estimated from the screenshot. The housing contour is simulated.

Single instance (follow-up request): main.swift now exits before creating a status item when another process with bundle id local.hsb.systemstatus is running. The earlier launch wins; if launch dates are unknown, the new launch yields, so duplicates are avoided. This is checked against the identifier that build.sh writes. Live on this Mac with PID 39220 running: a direct second exec printed "tinyStats läuft bereits (PID 39220)." and exited 0; `open -n` and plain `open` left exactly one instance. Launcher files (install.sh, bin/tinystats, Tests/install.sh) belong to the parent and were not touched.

### Follow-up 2026-11-09: flush lower edge, letter-free indicator

Lower edge (user: "Unterkante von tinystats nicht perfekt bündig mit Unterkante notch"):
- Measured on this Mac (MacBook Air 13.6", 2560×1664 panel, mode 1470×956 at 2x, so 1 pt ≈ 1.741 panel px): safe area 32 pt, auxiliary areas 32 pt high, menu bar 33 pt.
- AppKit's own display outline (`-[NSScreen bezelPath]`, undocumented) puts the housing's straight lower edge at y 923.834, i.e. 32.166 pt below the top. That is panel row 56 (housing 312 × 56 panel px). Lower corner radius 14.6 pt; top shoulders are about 6.9 pt concave.
- The public values are whole points, so the wing ended 0.166 pt (0.29 panel px) above the housing.
- Not the cause: shadow (hasShadow false), path inset, and window position (CG bounds 788/0 148×32 matched the code).
- Panel simulation (box filter 2940→2560 on real renders), last wing row below the bar colour 0.84: before, row 55 at brightness 0.25 next to black housing; now, row 55 at 0.17 and row 56 at 0.68, so the edge centroid sits on row 56.
- Fix: the wing reads the outline's lowest vertex inside the housing span. It is used only within 1 pt of the safe area and when the outline matches the screen frame (global or screen-local); otherwise the safe area applies.
- Wing frame is 788/923 120×33, with the lower edge 0.834 pt above the window bottom.
- The island keeps its top on the first whole point above the housing edge (924). It is hidden behind the housing and the wing and overlaps the wing's antialiased edge instead of abutting it. Abutting fractional AA edges from two windows would leave a ~22 % seam row. Content stays on whole points.
- The two windows now overlap by 1 pt below the visible wing edge. The routing is unchanged; the test asserts the overlap stays under half a point of visible wing.

Indicator without letters (user: "C,G,R weg lassen?"):
- Three 4 pt bars with 3 pt gaps, then a 6 pt gap, then the unchanged 36 pt rate column. Image 60×22 (was 88), status item 68 (was 96), wing 76 (was 104), closed wing window 120 wide (was 148).
- Upload stays on top, download below. nil (dash) vs 0 (empty track) is checked in pixels; full names stay in tooltip and VoiceOver.
- The details still need 255 pt under the housing, which the compact wing no longer reaches. The wing window takes the open width (148) as the details start and returns to 120 once they are gone. The wing's right edge follows the body's right edge with the same `widthProgress`, so the open silhouette is the approved one (island 663/770 266×154 unchanged).

Evidence:
- Checks: 10 PASS blocks, including the outline parser (vertices only, local/global, rejects), the raster lower edge (coverage sum within 0.05 pt of the outline), three bar runs of 8 px each, and the shared right edge for p 0…1.03.
- Offscreen renders (real views, real outline as housing): scratchpad render/out, notch-*, zoom-*, motion-*, junction-lower-edge-panel-before-after.png.
- Live (this display, real panels, window-server bounds via CGWindowList):
  - App PID 50298: wing 788/0 120×33.
  - Probe with the same panels: closed 120×33, open wing 148×33 plus island 663/32 266×154, closed again 120×33. 37 ticks; right-edge mismatch 1e-13 pt.
- No live pixel capture: CGWindowListCreateImage is obsoleted in macOS 15+, and Screen Recording is denied.

## Final integration: UI and command-line install
- [x] Parent inspected real offscreen closed/open notch renders; broad continuous island, concave upper-right and three unlabeled bars.
- [x] Completed Opus source plus last arrow rendering refinement retained; interrupted queued follow-up after final handover to ensure one writer.
- [x] Typecheck, native view/geometry/motion/routing tests and isolated installer tests pass.
- [x] Installer/CLI: private source checkout, local build, staged app replacement, source main fast-forward update, dirty checkout refusal, installed-process-only stop/start, no duplicate launch.
- [x] CLI docs and top-level README instructions.
- [x] Combined Sol review (2 completed rounds; superseded review cancelled).
- [x] Commit installer; create private tinyStats GitHub repo and push main; install and verify actual terminal command/update.
Known proof boundary: no live pixel capture available. Opus ran real panels and sampled window-server bounds through37animationticks; parent inspected native rendered views, not a screen recording. User previously confirmed live display/click and said general new direction is better; latest subtle lower-edge alignment remains visually unconfirmed. Undocumented read-only bezelPath uses guarded fallback; no dependency or runtime patch. No PR is required for the explicitly requested new repository + main delivery.

## Latest user geometry correction
The wing must never widen when opening. Expanded island now spans notch.minX...wingMaxX exactly, with no left inset or outward fillet. Removed wing spread state and dynamic window resizing entirely. Content fits the real253pt width; insufficient combined widths fall back to the normal menu bar instead of clipping text. Regression checks both exact expanded boundaries and invariant wing/window geometry across every sampled animation progress. Superseded combined Sol R1 cancelled before applying this behavior change; new review follows.

Combined Sol R1: CHANGES, S1 should accepted. Repeated installer run with gh available failed because setting an already multi-valued credential helper without --replace-all returns Git exit5. Changed only that setter to --replace-all and added available mock-gh to installer fixtures plus exact two-helper assertion after update. No UI behavior change after review. R2 only S1 and changed installer/test code. Usage not returned.

Final combined Sol R2 APPROVE: S1 closed, no remaining findings. gpt-6.1-sol/high, 2 completed rounds, usage not returned. Installer test with gh present passes and diffcheck passes. No declined findings. Final combined diff from03d0164 spans app redesign, fixed-wing correction, installer/CLI and documentation; late behavioral change only credentialhelper idempotency. Publish/install follows with user-authorized private repository and direct main push; no PR or CI invocation.

## Delivered: GitHub main, installed CLI and runtime proof
- Private repository https://github.com/tschnorpfeil/tinyStats created with default branch main. Source local main and remote main matchedf679541 before this documentation commit. No PR, no CI trigger, no force push.
- Installed ~/Applications/tinyStats.app and ~/.local/bin/tinystats, maintained source ~/.local/share/tinystats/source. Development source instancePID76104 terminated; installed instancePID91138 after successful real `tinystats update` from privateGitHub.
- Actual new zsh login: command-vtinystats resolves ~/.local/bin/tinystats; status/version pass. Repeated start keeps samePID; process inventory confirms exactly one installed instance. Real update fetchedmain, built, replacedapp and restarted successfully with gh present.
- CUA now works for installedapp: clicked sourcebutton, observed actual liveexpandednativeUI with CPU/GPU/RAM and upload/download; direct open→Escape sequence removedcontentcontrols from AXtree. This is live UI proof, not offscreen proof. The screenshot is scoped to the panel and does not include the wholephysicalnotch; precise fullsilhouette alignment still needs user confirmation, requested through questiontool after all independent work completed.
- Fixed-wing on-screen window bounds measured118×33pt at788/0. Native current checks assert fullanimationexactleft/rightboundaries andinvariantwingwidth, reducedmotion/routing/raster/contentfit. Parentinspectednew253ptcontentrender /tmp/tinystats-fixed-width-expanded.png.
- Read-only undocumented AppKitbezelPath guarded fallback remains a known compatibility limit. Foreignmenuoverlap remains possible, recoverablewithNotchtoggle. No autostart, modeldownloads or telemetry introduced.

## Expanded lower-left housing gap correction
User screenshot shows the physical housing's rounded lower-left cutout exposed above the island. Add a black cap behind the housing ONLY while expanding/expanded; cap constrained to notch.minX...notch.maxX. Island window reaches display top, content stays at the old attachment line and total outer width stays identical. Menu bar mode has no cap; collapsed path is empty. Path-bound and full-motion tests pass plus focused gap-point and outside-boundary regressions. Overlapped wing's transparent region still routes source clicks to close via existing panel shape routing; no blanket delay. Review before publish/install.

Corner-gap Sol R1 APPROVE (gpt-6.1-sol/high), no findings or declined items, usage not returned. Typecheck, native test suite and diff-check pass; build succeeded. Reviewer records10PASS blocks; no claim depends on block count. No behavior changes after review. Push and installed CLI update follow; live pixel proof separate from code/routing proof.
