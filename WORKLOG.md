# System status completion

## Scope

Local review base: fc06bc60f621913f55f99920729bad2faf6e0b77.
The in-progress symbol changes in main.swift belong to this task and are preserved.
At this stage there was no remote, and no push or PR was planned.
Review command for all rounds: `git diff fc06bc60f621913f55f99920729bad2faf6e0b77 -- main.swift .gitignore README.md build.sh Tests WORKLOG.md`, plus untracked files.

## Tasks

- [x] Inspect the current state and uncommitted symbol changes
- [x] Update the network baseline after successful samples
- [x] Make CPU/RAM values optional when data is missing
- [x] Design the popover with system symbols, separators and a small quit action
- [x] Run regression, formatting and construction checks
- [x] Build a standalone app bundle and validate its plist
- [x] Launch the new version (Systemstatus.app, PID 90040 before the final rebuild)
- [x] Verify layout geometry with native offscreen construction (300 × 260 pt)
- [x] Complete Sol review
- [x] Build and restart the final version
- [x] Prepare the final state for a local commit

## Validation and limitations

Swift typecheck, compiled checks and build passed. Native offscreen construction confirms geometry but does not prove click, Escape, outside-click or live popover behavior. Computer Use could not select the bundle (timeoutReached); the standalone binary was not a valid app target. No live UI verification claimed. The user authorized replacing the old instance without backing up its binary. No system settings or startup entries were created.

## Sol ledger

Budget: at most 3 rounds. Model from capabilities: codex / gpt-6.1-sol.
Round 1: APPROVE, no blocker, should or nit findings. No review fixes or declined findings. Model gpt-6.1-sol, medium effort per tool metadata. Usage not returned. No push.
Only this log changed after review; behavior diff stayed unchanged. Final typecheck, checks, optimized build and plist lint passed. Exactly one final app instance confirmed; startup log empty.
Pre-review diff: 3 tracked files, +175/-247; new build, test and log files recorded separately before round 1. Review diff stayed unchanged; new files added 106 lines before review, followed by completion notes in this log.

# Direct menu bar indicators

Base: 9e48a65b316ab85b71d19354326dc7b12c1fbe88. No remote.
Intent: three monochrome fill bars (CPU/GPU/RAM) plus two lines of download/upload rates in a fixed 120 pt menu bar item. Sampling and popover unchanged. No settings or history.
Review command: `git diff 9e48a65b316ab85b71d19354326dc7b12c1fbe88 -- main.swift Tests/checks.swift README.md WORKLOG.md`.

- [x] Implement indicators and compact byte rates
- [x] Distinguish missing values from measured zero
- [x] Include full network rates in tooltip and accessibility values
- [x] Check types, existing tests, rasterization and text widths
- [x] Render and inspect the native graphic at menu bar size
- [x] Complete Sol review (at most 3 rounds)
- [x] Build, launch and prepare the final version for a local commit

Graphic: 108 × 22 pt plus 12 pt button padding. Three 7 × 16 pt bars, without tiny unreadable letters. Empty track for zero, dash for missing data. Decimal B/K/M/G per second; ≥1T from 1 TB/s. No normalization against connection capacity. Live click test still pending after the earlier Computer Use timeout.

## Indicator review ledger

Round 1: APPROVE, codex / gpt-6.1-sol, medium effort. No findings, fixes or declined findings. Usage not returned. No push. Reviewer ran typecheck and diff-check. Only completion notes added afterward. Behavior diff unchanged: 3 files, +98/-9 excluding this log.
Final checks and build passed. Exactly one instance (PID 92757), empty startup log at /tmp/hsb-systemstatus-indicators.log. Live click test remained open.

# Menu bar design council

Trigger: user screenshot showed wasted horizontal space and indistinguishable CPU/GPU/RAM bars. Explore replacements before changing the renderer. Base db78c68; clean working tree.

- [x] Resolve requested models: Opus 5.5, Gemini 4 Argon, GPT 6.1 Sol
- [x] Read and combine three independent proposals
- [x] Implement and check a compact, distinguishable design
- [x] Submit the implementation to the council
- [x] Evaluate results and save locally
- [ ] Launch superseded by the user's notch-integration idea

Council was read-only, all three models at high reasoning. No PR/CI.

## Council results and implementation

| Model | Initial design | Implementation |
| --- | --- | --- |
| Opus 5.5 | 5/10 | 8/10 SATISFIED |
| Gemini 4 Argon | 4/10 | 9/10 SATISFIED |
| GPT 6.1 Sol | 4/10 | 9/10 SATISFIED |

Shared diagnosis: identical bars lacked labels; about 42 pt of empty space beside 1K. Opus proposed C/G/R beside bars at about 100 pt. Gemini proposed monograms under bars at 86 pt. Sol proposed full CPU/GPU/RAM labels over horizontal bars at 110 pt. The user confirmed C/G/R was sufficient. Chose the Opus direction, measured actual fonts: 88 × 22 pt image, 8 pt button padding, 96 pt total. Three 17 pt columns, 11 pt semibold initials, 5 × 14 pt bars, 36 pt network block. At least 2 pt between arrows and the widest rate. SF 9 text “999M” measures 26.06 pt, more than the earlier 22 pt estimate. Tests cover de_DE and en_US, maximum strings and font widths.

No minimum fill, extra warning threshold or color coding; values remain proportional. Zero uses an empty track; unknown uses a dash instead of a track. Tooltip and accessibility use full names, units and “Not available”. Fixed rounding from 999.5 GB/s to 1T so five-character 1000G cannot overflow.

Round 2 native offscreen sheets: /tmp/hsb-council-light.png and /tmp/hsb-council-dark.png. Five states: screenshot values, typical, zero/low/100%, unknown, longest text. Inspected visually; no collisions. Native live UI remained unverified. Typecheck, Tests/run.sh, build and diff-check passed. No PR/CI.
All three reviewers SATISFIED, no blockers. Declined Opus's R-to-network spacing nit: reducing columns from 17 to 16 pt worsens spacing within the three groups. Kept the reviewed layout. User switched to the notch idea before restart; committed the 96 pt version as the fallback base without losing changes.

# Notch prototype

User chose right-adjacent to the real notch, white on black; normal menu bar on a primary display without a notch. Used an explicitly authorized shared Opus 5.5 builder because T3 could not create a cross-project worktree. Base af1f697, builder commit 3548266. Only main.swift and checks changed; parent read the full diff. Sampling unchanged.

- [x] Inspect display geometry (1470 × 956, notch edge 824.5, height 32 pt)
- [x] Build notch overlay and menu bar fallback
- [x] Add a checkbox to switch back when space conflicts occur
- [x] Check geometry, shape, color mask, checkbox and build locally
- [x] Inspect the native offscreen graphic
- [ ] Verify live launch and interaction
- [x] Complete Sol review
- [x] Prepare the final state for a local commit

Public AppKit APIs, no new permissions. Notch frame on this Mac: (824.5, 924, 108, 32). Monochrome, only right outer corners rounded by 8 pt. Status item hidden in notch mode; nonactivating panel, still one timer. Both modes share the details view and a way back to the menu bar.
Limitations: space beside the notch is not reserved; no automatic detection of free areas around foreign status items. Primary display determines the mode. Fullscreen, autohide and multiple displays were not live-tested. Tests prove geometry and offscreen rendering, not live interaction.
Live launch: PID 10896; /tmp/hsb-notch.log empty. Computer Use could capture neither Systemstatus nor Finder windows (cgWindowNotFound). Position, clicks and keyboard remained unverified; a running process is not UI proof.

## Notch review ledger

Base af1f6970139abc700359e38038cd2a10178b0c5e; at most 3 rounds. Round 1 prepared with gpt-6.1-sol/high. Usage recorded only when returned. Diff command: `git diff af1f6970139abc700359e38038cd2a10178b0c5e -- main.swift Tests/checks.swift README.md WORKLOG.md`.
Round 1: APPROVE, no blocker/should findings. S1 nit: the 300 ms guard may swallow an independent reopening attempt immediately after Escape or an outside click. Deferred for the prototype: rare fast click sequence, no observed failure in the normal opening path. Track event-specific suppression as a follow-up; no change without a live reproduction. No review code changes or second round. Usage not returned.
Review diff unchanged: +330/-8 across 4 files, followed only by completion notes. Code and tests unchanged at +274/-7.
The reviewed version remained PID 10896, empty startup log. No source changes after build, so no restart needed. Branch feat/notch-status. No remote, push, PR, CI or publication. Asked the user to confirm live position and click behavior because Computer Use reported cgWindowNotFound.

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

Starting state, checked before assuming anything: the first screenshot (3e13ee25) came from the menu bar fallback. At that time the primary display was the external LEN P27h-10 (2560×1440 @1x, menu bar 30 pt, no notch). The details window list showed 300×268 at CG y 25, and the old 6 pt "chimney" stuck up into the transparent blue bar. The second screenshot (f1321328) came from notch mode after the built-in display became primary: 1470×956 @2x, housing 645.5…824.5 × 32 pt, wing window at 824 (AppKit had rounded 824.5 down). `showAtNotch` is unset, so it is true by registration. Safari's German menus overflow right of the housing, and the old wing covered the Window menu and the start of the Help menu. The geometry confirms the screenshot shows this collision.

User acceptance criteria, fixed in geometry and checks:
- Upper-right of the wing: concave reverse curve (7 pt) into the display's top edge, no convex radius. The path checks this, and so do rendered pixels.
- Lower-left of the wing: continues straight into the housing's lower edge. The wing window reaches 36 pt behind the housing and paints its lower edge through the housing's unknown lower-right rounding. No hardware radius is assumed; the composites only simulate one (r = 8 pt) for viewing.
- Upload ↑ on top and download ↓ below in the menu bar indicator. In the details the reading order is upload, then download, also for VoiceOver, tooltip and summary. Every row keeps its own measured rate (checks).

Design decisions:
- One silhouette rule: concave where black attaches to the bezel, housing or bar; convex where it ends freely.
- Notch mode: the details hang under housing and wing as one black island. Its right edge continues the wing; the wing's lower-right corner squares off as the island attaches. Its left edge meets the housing's straight lower edge with a concave 10 pt fillet, 18 pt from the housing's own corner, so it does not depend on that corner. Width = housing + wing − 28 pt (255 pt here), at least 248 pt for large-text scaling. No overlap with the wing window, so source clicks always reach the wing.
- Fallback: the island hangs from the bar's lower edge (visibleFrame top, never above the button), centred under the item, 272 pt wide, with concave fillets on both sides and the native status-item highlight. It is clamped to the screen and honours secondary-screen origins. This is different geometry because there is no black source in the bar.
- Window frames lie on whole points, because AppKit rounds window origins. The drawing uses sub-point offsets, so the 824.5/928.5 edges stay exact on 2x.
- Content: three columns (caption, SF Rounded 24 pt value with a smaller %, a 3 pt proportional meter: empty track for 0, dotted for missing, "—" for missing values). Below them a quiet upload/download tray with no capacity bar, then a footer with the tinyStats wordmark, a monochrome "Notch" switch (only shown with a housing) and "Quit" (⌘Q). Tabular digits and fixed frames mean 1 Hz samples never re-layout.
- Motion: one spring on the display link (opening response 0.42 s, damping 0.8, about 1 % overshoot; closing 0.26 s, critically damped). Width leads height, and the content fades in and drops 8 pt only once the body has room, clipped to the body. Reversal retargets in flight. Reduce Motion: 150 ms crossfade. Stalled frames are capped at 1/15 s.
- Interaction: non-activating key panel, so the front app and its menus stay. Escape (local monitor and cancelOperation), ⌘Q, outside click (global and local), clicks in transparent window parts and another app's activation all close it. Our own activation is ignored. The routing is pure and tested. During closing the panel ignores mouse events.
- Branding: tinyStats (wordmark, accessibility labels, README). The bundle is renamed to tinyStats.app with executable tinyStats. The bundle id stays local.hsb.systemstatus, so the notch preference carries over. LSMinimumSystemVersion is 14.0 (display link and clipsToBounds).
- Removed: NSPopover-era StatusViewController table, AttachedSurface/DetailsPanel/AttachedDetails (rectangular bridge), NotchOverlay* and NotchGeometry. There is one presenter (IslandPresenter).

Known constraint, not solved by design: macOS reserves no space beside the housing, and public APIs do not report where app menus end. Overflow menus can sit under the wing. The documented remedy is the "Notch" switch, which uses the system-placed status item. No hiding of foreign UI, no fake reservation, no Accessibility permission.

Evidence (this session):
- `swiftc -typecheck main.swift` ok. `./Tests/run.sh`: 9 PASS blocks (live samples; formatting; indicator order; wing geometry and the concave/seamless criteria in path and pixels; island attach and bounds for p 0…1.03; spring opening, closing, reversal and stalls; content fits 248/255/272 with no re-layout; routing for Escape, ⌘Q, inside, outside and source; island render monochrome). The CPU live check now waits up to 2 s for a tick delta instead of assuming one within 50 ms; the value is still range-checked and measurement code is unchanged. `./build.sh` ok, `plutil -lint` ok, `git diff --check` ok.
- Native offscreen renders of the real WingView, IslandView and IslandContentView, composited over the user's two screenshots (housing simulated, r = 8 assumed), saved in /private/tmp/claude-501/-Users-ts--t3-scratch-2026-11-08-ich-habe-von-einem-lokalen-298c78ca/f1f97544-a6ff-4630-b8ce-2f12a87679de/scratchpad/render/out/: notch-open-{0..3}-{dark,light}.png (typical/0/high/nil), notch-closed-*.png, *-contour.png, zoom-*.png, fallback-open-{0..3}.png, motion-*-60fps.png, motion-open-close-50fps(@2x).gif, motion-keyframes.png. These are offscreen evidence, not a live capture.
- Runtime probe: the real IslandPresenter on this Mac's window server and display link. The island window measured X 663, Y 32, 266×154 (CG). Opening took 38–39 ticks at about 16.9 ms (60 Hz) and reached 95 % at 243–253 ms, with the largest step 0.11 per frame. The panel was key while the front app stayed Preview. Escape (via NSApp.sendEvent and the local monitor) closed it in 28 ticks. Reversal (open, close at 120 ms, reopen at 220 ms) stayed continuous (largest step 0.106) and ended open and key. ⌘Q reached applicationWillTerminate. One earlier run was closed by a real Terminal activation (an observed notification, not caused by tinyStats).
- Live app: the old exact executable /Users/ts/HSB-MenuBar/Systemstatus.app/Contents/MacOS/Systemstatus (PID 18961) was stopped. /Users/ts/HSB-MenuBar/tinyStats.app/Contents/MacOS/tinyStats runs as a single instance and its log is empty. The stale generated bundle Systemstatus.app (ignored build output from 03d0164) was moved to /private/tmp/claude-501/-Users-ts--t3-scratch-2026-11-08-ich-habe-von-einem-lokalen-298c78ca/f1f97544-a6ff-4630-b8ce-2f12a87679de/scratchpad/old-Systemstatus.app, so it can no longer start a duplicate instance. It can be rebuilt from git. The wing window is on screen at CG X 788, Y 0, 148×32, layer 25 (matches the computed frame).

Limitations: this session has no CUA tool, and `screencapture` is denied (no Screen Recording permission). So there is no live screenshot, and no live mouse test of wing or status item clicks, hover or fallback highlight. The visual proof is offscreen plus window-server geometry plus runtime timing. Whether transparent window regions pass clicks through is unverified, so treat them as captured: they close the island. The fallback composite's button position is estimated from the screenshot. The housing contour is simulated.

Single instance (follow-up request): main.swift now exits before creating a status item when another process with bundle id local.hsb.systemstatus is running. The earlier launch wins; if launch dates are unknown, the new launch yields, so duplicates are avoided. This is checked against the identifier that build.sh writes. Live on this Mac with PID 39220 running: a direct second exec printed "tinyStats is already running (PID 39220)." and exited 0; `open -n` and plain `open` left exactly one instance. Launcher files (install.sh, bin/tinystats, Tests/install.sh) belong to the parent and were not touched.

### Follow-up 2026-11-09: flush lower edge, letter-free indicator

Lower edge (user: "The bottom of tinyStats is not perfectly aligned with the bottom of the notch"):
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

## Separate menu-bar presentation from notch presentation
User rejects integrated notch shoulders in normal menu bar mode. Add explicit floating presentation only for menuBar layout:6pt gap, convex rounded top corners matching bottom, content masked at all4corners, same compact content and interruptible source-centred motion. Notch layout/cap/wingunchanged. Focused geometry and real raster regression tests cover gap, rounded-top transparency and unchanged notch mode.

Floating-menu Sol R1 APPROVE, no findings, gpt-6.1-sol/high; usage not returned. Typecheck/native geometry+raster tests/diffcheck re-run by reviewer pass; ownbuild pass. No behaviorchangesafterreview. Normalmenu now floating card only; notchshapeuntouched. Update and liveverificationfollow.

## Distribution completion (full-send + sol-loop)
- [x] Audit private GitHub main, installer, CLI, documentation.
- [x] Fix installed version provenance after failed update; lock complete update including fetch.
- [x] Add regressions for failed remote update/version preservation and concurrent-update rejection.
- [x] Clarify prerequisites, troubleshooting, uninstall paths, full local checks and current notch contour.
- [x] Complete local gates and Sol review.
- [x] Publish reviewed change, update real installation and verify CLI/runtime.

Distribution Sol R1 APPROVE (gpt-6.1-sol/high), no findings, no declined findings, usage not exposed. Diff before/after review: 6 files, +70/-11 (plus this review record). Native tests, typecheck, build, installer regression and diff-check pass.

Delivered behavior commit 20cd416 to GitHub main, retaining the user-requested direct-main/no-PR path. Real installed CLI update from private GitHub succeeded; a second update exercised the new parent-owned lock and updated installer handoff successfully. New zsh login resolves ~/.local/bin/tinystats; version reports installed 20cd416, repeated start retained PID63238, update restarted successfully. No UI behavior changed in this distribution pass. No PR/CI invocation, no visibility change.

## English repository
- [x] Translate README, installation guide, historical work log, app labels, tooltips, accessibility text and CLI/installer messages.
- [x] Update language assertions and regenerate all README renderings with an English locale.
- [x] Native tests, installer tests, rendering and build passed. Numeric formatting in the app still follows the system locale.
Historical commit messages and stable bundle identifiers are preserved.
