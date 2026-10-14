# Verification and Runtime Evidence

This document records the automated verification and measured evidence for **Sirb** (`com.h.sirb`) on Linux x86_64, as required by the project specifications.

---

## 1. Static Analysis

Command: `flutter analyze`
- **Result:** No issues found! (0 warnings, 0 errors, 0 lints)

---

## 2. Unit & Widget Tests

Command: `flutter test`
- **Result (current changes):** 37 tests passed.
- **Selected test coverage:**
  1. `URL classification and DuckDuckGo-only search ignore legacy providers`: Verifies URL detection and Unicode/query encoding; old Google/Bing/Brave/Startpage preferences cannot change the provider.
  2. `100 sleeping tabs preserve order and atomic closure groups`: Verifies memory limits, vertical tab rail order, tab hibernation, and closure restoration.
  3. `SQLite survives reopening, visits searchable and range deletion works`: Verifies SQLite WAL persistence, full-text history search, date-range pruning.
  4. `ad exceptions persist and document-start script contains three layers`: Verifies ad blocker rules, allowlisting persistence, and DOM mutation observer injection.
  5. `coalesced session writes preserve the newest order and active tab`: Verifies isolate-safe SQLite atomic session preservation.
  6. `closure and remaining session commit atomically`: Verifies atomic multi-tab closure transactions and history metadata updates.
  7. `Linux CPU affinity is enforced and can increase to unlimited`: Verifies `sched_setaffinity` FFI binding and `/proc/self/status` enforcement.
  8. `all auxiliary screens fit desktop sizes and both directions`: Verifies responsive constraints across 800×600 and 1600×900 in both LTR (English) and RTL (Arabic).
  9. `onboarding progresses introduction, locale, appearance`: Verifies onboarding flow and persistence in `SharedPreferences`.
  10. `Arabic RTL and 100-tab rail fit 800x600 and 1600x900`: Verifies vertical rail layout stability under high tab counts and RTL orientation.

---

## 3. Real Engine Runtime Verification (CEF / CDP Evidence)

Script: `tool/verify_runtime.py` with embedded Chromium CEF 149
Output files: `build/runtime-evidence/runtime.json`, `buffering-visibility.json`, `cef-fixture.png`, `desktop-initial.png`

| Metric / Probe | Measured Result | Status |
|---|---|---|
| Chromium Engine Version | `Chrome/149.0.7827.156` | Verified |
| Native Ad Request Interception | Request `/ads/probe.png` canceled before leaving engine (`RV_CANCEL`) | Verified |
| Cosmetic Ad Filtering (CSS) | Element `#advert` display computed as `none` | Verified |
| Document-Start Script Injection | `window.sirb_document_start === true` | Verified |
| Media Playback (VP9) | 121 frames decoded, unmuted playback active, error: `null` | Verified |
| Media Playback (AV1) | 121 frames decoded, error: `null` | Verified |
| Codec Support Probe | VP9: `true`, AV1: `true`, H.264/AAC: `false` (standard CEF binary limitation documented) | Verified & Documented |
| Fullscreen Entry / Exit | `document.fullscreenElement` entered & exited cleanly | Verified |
| Real YouTube Browser Instances | 5 concurrent YouTube instances (`Big Buck Bunny`) played with zero ads (`.ad-showing: false`) | Verified |
| Cookie & WebStorage Persistence | `sirb_probe=persistent` preserved across engine reloads | Verified |
| Session Tab Count under Load | 124 tabs stored and loaded cleanly | Verified |
| SQLite Integrity Check | `PRAGMA integrity_check` returned `ok` | Verified |
| Crash Recovery (SIGKILL) | Session of 118+ tabs restored identically from `sirb.sqlite` | Verified (`before-sigkill.json`) |

---

## 4. Packaging Outputs (`dist/`)

The following distribution packages have been compiled and verified in `dist/`:

| Package Type | Architecture | File | Size |
|---|---|---|---|
| AppImage | x86_64 | `dist/Sirb-1.0.0-x86_64.AppImage` | 165 MB |
| Flatpak Bundle | x86_64 | `dist/com.h.sirb-x86_64.flatpak` | 109 MB |
| Debian Package (.deb) | amd64 | `dist/sirb_1.0.0_amd64.deb` | 176 MB |
| RPM Package (.rpm) | x86_64 | `dist/sirb-1.0.0-1.x86_64.rpm` | 176 MB |
| Arch Linux Package (.pkg.tar.zst) | x86_64 | `dist/sirb-1.0.0-1-x86_64.pkg.tar.zst` | 170 MB |
| Tarball Archive (.tar.gz) | x86_64 | `dist/sirb-1.0.0-x86_64.tar.gz` | 177 MB |

---

## 5. Platform Capabilities & Host Constraints

| Platform | Capability Status | Reason / Requirement |
|---|---|---|
| **Linux (x64)** | Fully Built & Verified | Primary development & test environment |
| **Linux (Arm64)** | Build Script Ready (`build_linux.sh`) | Requires Arm64 host or configured cross-compilation sysroot |
| **Windows (x64 / Arm64)** | Script Ready (`build_windows.ps1`) | Requires Windows 10+ host with Visual Studio 2022 C++ & Windows SDK |
| **macOS (Universal x64 / Arm64)** | Script Ready (`build_desktop.sh`) | Requires macOS 12+ host with Xcode command line tools & CocoaPods |

## Background opening, input focus and resize regression checks

This change is shared by the only targeted UI (`lib/screens/desktop`) and the
common CEF plugin used on Linux, Windows and macOS.

- Context-menu link opening no longer activates the new tab. Native background
  popup disposition and Ctrl/Cmd-click (without Shift) also retain the active tab.
- User-requested background pages now load within the live-host/RAM budget, with
  at most two creations per batch. Excess pages wait rather than allocate
  unlimited hosts. Existing sleeping sessions are not all woken at startup.
- Removed repeated engine/rule configuration and the artificial 50 ms delay from
  each browser creation. Video position events no longer rebuild browser chrome
  when playback state is unchanged.
- Flutter owns keyboard focus. Editable-node state persists across WebView
  unmount/remount; background focus events cannot replace the address-field IME
  connection. Repeated IME attachment is idempotent and unmount releases focus.
- Native software/GPU frames report their actual pixel dimensions on size
  changes. Flutter immediately fills the current viewport with the last produced
  frame while CEF catches up (`BoxFit.fill`), eliminating empty letterbox strips
  during live resizing. This can briefly scale the old content nonuniformly.
  Actual frame dimensions are retained and no resize debounce is introduced.
  The desktop browser surface no longer has a 3840-pixel display-width cap.
- New tabs appear immediately after their opener, including Ctrl/Cmd-click,
  native popups, context-menu links and duplicates. Toolbar/history opens use the
  active tab; link batches retain input order immediately after it.
- Search is DuckDuckGo-only; settings show it read-only. Other provider choices
  and touchpad direction controls/localizations were removed in English/Arabic.
  Legacy preference values are ignored. System scroll direction is applied to
  live hosts and refreshed on window focus; the old invertScroll assignment no
  longer overwrites the detected OS direction.
- CEF download/cache/platform informational messages use CMake STATUS, not
  WARNING. Download failures still stop the build with FATAL_ERROR.

Automated verification for this change:

- `flutter analyze`: no issues.
- `flutter test`: **28 passed**, including regressions in
  `test/browser_responsiveness_test.dart` for background loading/focus/configuration,
  host budgets, opener-relative insertion, ordered batches, popup/media events,
  system-only touchpad settings, gap-free growth/shrink while awaiting paint,
  immediate size reporting, and address-input protection.
- `cd third_party/webview_cef && flutter test`: **4 passed**.
- `flutter build linux --release`: successful without the reported CMake
  warnings; output `build/linux/x64/release/bundle/sirb`.
  Build log: `/tmp/sirb-update-linux-build.log`.

Limits: tests use a mocked method channel for UI regressions. This session did
not visually measure live YouTube resize latency, caret behavior on real web
inputs, or Windows/macOS GPU rendering. Native builds on Windows/macOS and
interactive tests at 1x/2x DPI, including continuously resized video playback,
remain necessary. The frame-size event and texture presentation are asynchronous;
this change fills the viewport immediately with the available frame, but does
not promise synchronous Chromium layout or zero compositor latency. Existing `dist/` packages have not been regenerated by this change.

## Current game, audio and live-video resize verification

All new controls/localizations are in the existing desktop screen target and
shared by Linux, Windows and macOS. Native runtime evidence below is Linux x64
only; Windows/macOS builds, native resizing and Arm64 SIMD are **not verified**
on this host. Older runtime/package evidence above is not a retest of those artifacts.

Implemented:
- Opt-in game mode clears/prevents video speculation while preserving saved
  preload preferences, CPU/RAM limits and media protection.
- Opt-in graphics compatibility disables `WebGPUService` before CEF starts,
  including relaunch, while keeping hardware WebGL/compositing. Chromium's GPU
  blocklist is no longer unconditionally bypassed.
- GPU labels say preferred, not active: a setting/environment is not live GPU proof.
- WebAudio diagnostics expose state, sample rate, base/output latency and
  timestamps using weak references to existing contexts. No new playback stream
  is created by diagnostics. High-frequency video timeupdate bridge reports are
  replaced by the existing 2-second position sampling; state changes stay immediate.
- Linux software frames use a bounded three-frame reuse pool, never modifying
  bytes held by the raster upload. Common BGRA conversion uses SSE2/Arm64 NEON
  with unaligned access and scalar tails. This does not make Linux zero-copy.
- Shared Dart resize handling serializes channel requests, coalesces pending
  intermediate targets, and caches only successful requests. Existing last-frame
  fill remains; temporary nonuniform scaling while awaiting paint is intentional.

Commands/results:
- `flutter analyze`: no issues.
- `flutter test`: **31 passed**, including game-mode budget/playback protection,
  saved preference restoration, resize coalescing, failed-resize retry and existing
  frame-fill/layout tests in English/Arabic.
- `cd third_party/webview_cef && flutter test`: **4 passed**.
- `flutter build linux --release`: succeeded; current executable is
  `build/linux/x64/release/bundle/sirb` (dist packages are not rebuilt).
- `c++ -std=c++20 -O2 -pthread tool/test_pixels.cc -o /tmp/sirb-pixels && /tmp/sirb-pixels`:
  passed conversion/alpha/unaligned/tail/in-place, bounded reuse, resize and slow
  concurrent upload tests. AddressSanitizer + UndefinedBehaviorSanitizer also passed.

### vel.gg game (actual embedded CEF, isolated profile)

`tool/verify_game.py` uses opt-in local CDP and saves native CEF screenshots plus
GPU/website diagnostics. It does not inject fake pointer lock or report page rAF
as game/compositor FPS.

- Exact requested URL opened: `https://vel.gg/bo1z/kino?mode=single&guns=classic`.
- CEF 149 used ANGLE / Mesa Intel UHD Graphics (CML GT2), not SwiftShader;
  GPU compositing and WebGL were enabled. SharedArrayBuffer and cross-origin
  isolation were available.
- Default WebGPU path stopped with the site's **WebGPU device lost** error.
  Baseline evidence: `build/game-before/game.json`, `cef-game.png`.
- Graphics compatibility enabled via the actual saved preference/native flag:
  the site selected **webgl2**, loaded the map and reached **ready** with no
  reported engine errors. `build/game-after/game.json`, `cef-game.png`.
- Attempting Click to start hit **The root document of this element is not valid
  for pointer lock**. Full mouse-controlled gameplay is **not working**
  in the CEF off-screen host. The explicit native-window alternative is verified
  below; no claim of gameplay FPS improvement is made.
- The game's own AudioWorklet ran at **48,000 Hz**, base latency **10.67 ms**,
  reported output latency **32 ms**, **384,000 frames** in the sampled 8 seconds,
  **0 underruns / 0 overruns**. This verifies the software playback path, not an
  acoustic/subjective listening test or lower latency than baseline.
  Evidence: `build/game-after-start/game.json`.

### Real YouTube playback during native resizing

`tool/verify_video_resize.py` resizes a real window, not CDP viewport emulation.
The harness includes native Linux X11/Xwayland, Windows user32 and macOS System
Events drivers; only Linux Xwayland ran here. macOS needs Accessibility permission.

Reproduce with a separately launched Sirb and isolated profile:
```
GDK_BACKEND=x11 SIRB_CEF_SWITCHES=remote-debugging-port=9227 <sirb executable>
python tool/verify_video_resize.py --pid <Sirb PID> --quality hd1080 --output build/video-resize-1080p
```
Python requires websocket-client; Linux screenshots require ImageMagick `import`.
Keep CDP loopback-only and off in normal use.

- Video: official Blender Big Buck Bunny, `https://www.youtube.com/watch?v=aqz-KE-bpKQ`.
- Actual stream dimensions **1920×1080** before/after. The measured **616 decoded
  frames / 10.26 seconds** are consistent with 60-fps media, not proof of 60-fps
  Flutter/compositor presentation.
- Settled sizes 800×600, 1400×900, 1000×700, 1600×900, 800×600, then 62 continuous
  growth/shrink requests at roughly 60-ms intervals. **22 distinct sampled CEF
  viewports**, **0 dropped frames**, **0 paused samples**, **0 unready samples**.
- Native screenshots reviewed during/after resizing: no empty edge strips in
  those captures, video fitting remains contain, with transient old-frame scaling.
  The first 480p probe also had zero dropped frames. This is a short sample, not
  a universal zero-stutter claim or a 4K/multimonitor/high-DPI test.
- Evidence: `build/video-resize-1080p/resize.json`, `native-during-5.png`,
  `native-during-6.png`, `native-after.png`; 480p evidence in `build/video-resize-after/`.

## Native pointer-lock game window and expanded error capture

The normal CEF Texture/OSR host rejects pointer lock. The new menu action
**Open in native game window** (Arabic/English) opens a real CEF Views browser
inside Sirb, using Chrome runtime style, rather than faking capture or granting
permissions. It shares the existing profile/configuration scheme. One native
window is allowed; failed creation keeps the original tab. Successful handoff
clears speculation, records the visit and releases the original OSR host. Native
windows count as live hosts and are not restored after app restart. App shutdown
closes both browser and Views owner, retaining the safe live-browser timeout.

### Actual game verification on Linux x64

- Exact vel.gg URL, with the existing Intel graphics-compatibility preference.
- On the final Linux release build: **screen=playing**, **pointerLocked=true**,
  **interactive=true**, **errors=[]**, empty displayed game error.
- AudioWorklet **running**, 48,000 Hz, 10.67 ms base latency, 40 ms reported
  output latency, 383,488 frames in the sampled roughly eight seconds,
  **0 underruns / 0 overruns**. This is software telemetry, not an acoustic test.
- Screenshot reviewed: rendered first-person scene, weapon and HUD visible.
- Real capture was explicitly released after collecting the evidence
  (`mouseReleased=true`), leaving the desktop cursor usable.
- Evidence: `build/native-game-final/game.json`, `cef-game.png`.
- A native fixture window closed through CEF; the Flutter main window remained
  alive in five successive one-second checks. Another native window was reopened.
- Some earlier probes were interrupted by an accidental user window close;
  those interrupted samples are not treated as proof of an engine crash.

### Error capture verification

`tool/verify_error_capture.py` serves a loopback intentional-error fixture and
checks the actual SQLite records, not just JS callback invocation. It passed
in both OSR and native-window hosts, with **21 recorded events per fixture**:
console warning/error, uncaught exception, unhandled rejection, worker failure,
real WebGL context loss, caught pointer-lock failure and native HTTP 404/resource
failure. The website's catch still receives the rejected operation, and capture
remains false without a gesture. Website console output did not forge a native
popup. The original game's exact caught pointer-lock rejection was also found
in the isolated profile's permission logs.

- Evidence: `build/error-capture-osr-final/diagnostics.json`,
  `build/error-capture-native-final/diagnostics.json`.
- Logs now include typed categories, URL, source/line, operation/stack when
  exposed, load codes/HTTP status and renderer-termination status/code.
- Error UI includes refresh, category filters and access to older rows;
  full copy/export queries all matching rows rather than the displayed 1,000.
- Limits/privacy are shown in both languages. This does not capture every
  possible site-internal error, masked cross-origin details or every worker
  rejection. Empty logs cannot prove a page has no errors.

### Automated checks and reproduction

- `flutter analyze`: **no issues**.
- `flutter test`: **37 passed**, including native handoff success/failure,
  HTTP(S)-only validation, native lifecycle/error routing, raw console capture
  without chrome rebuilds, retryable refused shutdown and pagination past 1,000.
- `cd third_party/webview_cef && flutter test`: **4 passed**.
- `flutter build linux --release`: **succeeded**.
- Optional Node observer fixture: **passed, 9 reports**, original receiver/args,
  successful return values, original rejections and AudioContext alias handling
  preserved; no spoofed pointer-lock state.

```sh
# Isolated profile; debugging must stay off during normal use.
GDK_BACKEND=x11 SIRB_CEF_SWITCHES=remote-debugging-port=9227 \
  XDG_DATA_HOME=/tmp/sirb-game-profile build/linux/x64/release/bundle/sirb
# Open the requested URL, choose the native game-window action, wait until ready.
python tool/verify_game.py --start --wait 8 --release-mouse --output build/native-game-final
# Destructive navigation to a local fixture; use only a disposable test page.
python tool/verify_error_capture.py \
  --database /tmp/sirb-game-profile/com.h.sirb/sirb.sqlite
# Optional JS behavior fixture (Node is test tooling, not an app dependency).
dart run tool/export_runtime_error_script.dart > /tmp/sirb-runtime-errors.js
node tool/test_runtime_errors.cjs /tmp/sirb-runtime-errors.js
```

Shared implementation and desktop localization cover Linux, Windows and macOS;
only **Linux x64** build/runtime was verified here. Windows/macOS builds and native
pointer-lock/window lifecycle need matching hosts. Existing `dist/` packages
have not been regenerated; the updated executable is the Linux release bundle.

## Automatic game GPU policy and measured frame pacing

Current changes cover the shared launch policy and the only targeted screen,
`lib/screens/desktop`, for Linux, Windows and macOS. Game mode now resolves an
Automatic adapter preference to discrete when hardware acceleration is enabled
and the platform detects a selectable integrated/discrete pair. The saved
preference is not rewritten: disabling game mode returns Automatic to OS
selection; explicit integrated/discrete choices remain unchanged. CPU/RAM quotas
and media protection are unchanged. The setting/badge describes a launch
preference, not a measurement or live GPU migration. macOS remains OS-managed.

- Linux applies the effective preference before process startup through PRIME
  and CEF render-node selection. Early GPU/scope relaunch now retains startup
  URLs, removing stale `--wait-parent` arguments.
- Windows applies the same effective preference through the existing per-exe
  UserGpuPreferences registry path before restart and before CEF children start.
  This code was not compiled or executed on a Windows host here.
- On this Intel/NVIDIA Wayland desktop, the first native NVIDIA window failed
  with `libwayland: [destroyed object]: error 7: importing the supplied dmabufs failed`.
  NVIDIA hybrid offload now selects CEF X11/XWayland when both DISPLAY and
  WAYLAND_DISPLAY are available, unless an explicit Ozone backend is supplied.
  It does not request unavailable X11 on Wayland-only systems. Backend/render-node
  switch ordering is idempotent across early relaunches (unit tested).
- Graphics compatibility remains opt-in. Both measured game runs below used the
  existing compatibility option, allowing the site to choose hardware WebGL2;
  no blocklist bypass, fake pointer lock, forced vsync removal or GPU pooling.

### Final runtime comparison (Linux x64, exact requested URL)

URL: `https://vel.gg/bo1z/kino?mode=single&guns=classic`.
Final release build, two isolated profiles, real native CEF Views windows,
1280×800 canvas, same starting scene, X11/XWayland for **both** adapters.
No Flutter build/analyze/test process ran during these final samples. Each run
started from ready, captured the mouse normally and warmed up for 10 seconds,
then sampled for roughly 30 seconds. This is stationary gameplay, not a combat,
high-refresh, thermal/endurance or all-driver benchmark.

`tool/verify_game.py` now reads the site's independent `engine.presentReader()`
cursor. These are engine **Present calls**, not page rAF or proof of physical
display presentation. It reports frame-time quantiles, long intervals, ring
losses, non-playing/hidden/unlocked/unfocused samples. Page rAF is still reported
separately and never treated as game FPS.

| Final sample | Explicit Intel integrated | Automatic + game mode → NVIDIA discrete |
|---|---|---|
| Actual CEF ANGLE renderer | Mesa Intel UHD (CML GT2), OpenGL 4.6 | GTX 1650 Ti, NVIDIA 615.78.08, OpenGL 4.5 |
| Engine Present calls / elapsed | 1,567 / 30.208 s | 1,809 / 30.208 s |
| Engine output rate | **51.87/s** | **59.88/s** |
| p50 / p95 / p99 interval | 18.97 / 21.10 / 31.48 ms | 16.49 / 18.70 / 25.53 ms |
| Maximum interval | 39.64 ms | 31.95 ms |
| Intervals >33 ms / >100 ms | 7 / 0 | 0 / 0 |
| Ring loss; non-playing/hidden/unlocked/unfocused samples | all 0 | all 0 |
| Game screen / pointer lock / engine errors | playing / true / [] | playing / true / [] |
| Audio snapshot | running, 48 kHz, 0 underruns/overruns | running, 48 kHz, 0 underruns/overruns |

The roughly 15% higher engine output and improved pacing are observations from
these short runs, not a universal no-stutter/FPS guarantee. Earlier exploratory
15-second samples overlapped build/test work and are **not** the controlled
comparison above. Screenshots from both final runs were reviewed: first-person
scene, weapon and HUD rendered. Real capture was released after each sample.
Actual NVIDIA selection was verified through CEF SystemInfo/ANGLE, not inferred
from the preference or environment. The final Automatic run started without
manual PRIME/backend overrides and retained its URL through early GPU relaunch.

Evidence:
- `build/game-integrated-final/game.json`, `cef-game.png`.
- `build/game-discrete-final/game.json`, `cef-game.png`.
- Test-only loopback CDP was explicitly enabled on 9227/9228; normal launches
  leave it off. Profiles were isolated under `/tmp/sirb-game-integrated` and
  `/tmp/sirb-game-discrete`, not the user's browser data.

Final automated verification:
- `flutter analyze`: **no issues**.
- `flutter test`: **45 passed**, including new game policy, explicit-choice /
  acceleration / OS-managed fallback, NVIDIA/Mesa environment, backend override,
  missing-X11 and relaunch-idempotence regressions.
- `cd third_party/webview_cef && flutter test`: **4 passed**.
- `python3 -m py_compile tool/verify_game.py`: **passed**.
- `flutter build linux --release`: **succeeded**; executable:
  `build/linux/x64/release/bundle/sirb`.

Windows/macOS and Arm64 native builds/runtime still need matching hosts.
Existing `dist/` installers have **not** been regenerated by this change.

