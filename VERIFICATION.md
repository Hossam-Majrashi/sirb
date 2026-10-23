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

## Visible-content-first loading and YouTube original-title preference

Implemented in shared document-start/runtime Dart scripts and the only targeted
screen directory, `lib/screens/desktop`. The YouTube-specific implementation is
isolated under `lib/features/youtube/services`. Settings are localized in Arabic
and English and default on. Ad rules and native platform restrictions are unchanged.

Verification for this change:

- `flutter analyze`: **no issues**.
- `flutter test`: **49 passed**. Includes persisted defaults, preservation of the
  saved preload preference under both game/focus modes, policy injection with
  ad blocking disabled, and live-host updates without reloading playing media.
- `flutter build linux --release`: **succeeded**;
  `build/linux/x64/release/bundle/sirb`.
- `dart run tool/export_page_features.dart > /tmp/sirb-page-features.js` then
  `python3 tool/verify_page_features.py /tmp/sirb-page-features.js`: **passed**.
  The hermetic HTTPS fixture uses Chromium/ChromeDriver and the production host
  guards, not live YouTube schemas. It checks actual withheld/resumed image and
  continuation requests, explicit eager priority, utility frames, initial/unknown
  requests and player pass-through, abort and SPA navigation, live opt-out,
  15-second fail-open, visible-card-only public metadata, duplicate lookup
  coalescing, stale-card protection, fallback and title restoration. No cookies
  are sent to the public metadata endpoint.
- Actual rebuilt **CEF 149.0.7827.156** smoke test in an isolated profile under
  `/tmp/sirb-focus-cef-nzyY0w`: the page's first inline script observed both
  feature flags/installations with speculative preload disabled. An off-screen
  dynamic image did **not** reach the local HTTP server before scrolling;
  the explicit eager control did. Scrolling resumed the deferred request.
  Result: `/tmp/sirb-focus-cef-nzyY0w/result.json`. Opt-in CDP was loopback-only
  on 9239; the test application was stopped afterwards. User data was untouched.
- A public logged-out YouTube oEmbed probe returned HTTP **200** and
  `Big Buck Bunny 60fps 4K - Official Blender Foundation Short Film` for
  `aqz-KE-bpKQ`. This verifies endpoint availability for that public video only,
  not universal original-language metadata or logged-in playback.

Limits: parser-started requests may precede lazy hints; bundled descriptions,
comments and recommendations cannot safely be separated. Only positively
identified continuation fetches are delayed, not arbitrary fetch/XHR calls,
media segments or the initial watch response. Original-title metadata may be
missing or localized by YouTube. Live logged-in/logged-out YouTube UI/playback
coverage and Windows/macOS/Arm64 runtime verification remain pending. Existing
`dist/` installers have **not** been regenerated.

## Video priority, bounded YouTube handling and independent Twitch/Kick rules

Applied in shared Dart injection/configuration on Linux, Windows and macOS;
reviewed the only existing UI target, `lib/screens/desktop`. No new UI controls,
platform-specific rule copies or changes to user CPU/RAM budgets were added.

- `lib/features/ads/sites/youtube_ad_rules.dart`, `twitch_ad_rules.dart` and
  `kick_ad_rules.dart` own their platform rules; `ad_rules.dart` composes them
  into the existing native interception configuration.
- Removed YouTube document-wide class observation, repeated ad seeks, constant
  normal-playback polling and private player resize calls. Ad work is coalesced;
  seeking is bounded per finite ad source/episode, skip clicks are rate-limited,
  and pagehide/pageshow plus shield toggles are handled.
- Cosmetic filtering no longer hides video/audio or wrappers containing them.
  Twitch countdowns remain visible; hiding a label is not removing an SSAI ad.
- One large intersecting HTML5 video without an explicit preload policy receives
  a buffering hint; off-screen players and speculative/save-data automatic work
  are excluded. Local user interaction can upgrade a player's preload hint.
  No forced play, focus, load/reset, quality changes or media-request deferral.
  Site MSE buffering remains authoritative. Kick links are recognized alongside
  the existing video-link sites for explicit opening/speculation policy.

Verification:

- `flutter analyze`: **no issues**.
- `flutter test`: **51 passed**, including independent rule composition, content
  CDN/API pass-through, hostname boundaries, exceptions and disabled-shield policy.
- `dart run tool/export_video_policy.dart > /tmp/sirb-video-policy.json` then
  `python3 tool/verify_video_policy.py /tmp/sirb-video-policy.json`: **passed**.
  Hermetic HTTPS Chromium fixtures run the exact production script builder at
  document start under YouTube/Twitch/Kick/unrelated hostnames. Actual VP9 media
  played, paused, sought and resumed without media errors in each fixture.
  Synthetic ad-state tests check one seek per source, rate-limited skipping,
  normal/live media untouched, opt-out/re-enable and pagehide/pageshow handling.
  Also checks visible-only bounded automatic preload hints, no forced autoplay,
  speculative opt-out, cosmetic player safety and idempotent style installation.
  Result: `build/video-policy-evidence/result.json`.
- `flutter build linux --release`: **blocked** during CMake generation by missing
  third-party source `third_party/webview_cef/third/cef/libcef_dll/base/cef_atomic_flag.cc`.
  Log: `/tmp/sirb-video-update-build.log`. No native executable or installers were
  produced by this change; restore the complete matching CEF distribution first.

Limits: local Chromium fixtures are not live YouTube/Twitch/Kick service tests,
real-account/region coverage, nor a native CEF stutter/latency measurement.
Twitch/Kick rules are conservative client-side endpoint/slot filters, not verified
removal of server-inserted live/VOD ads. Do not block shared media CDNs, rewrite
playlists or spoof playback tokens to imply universal ad-free streaming. Live
logged-in/out playback, seek/fullscreen tests and Windows/macOS native builds
still need matching hosts. Existing `dist/` packages remained unchanged at this
stage; the CEF cache repair and Linux x64 repackaging below supersede that build blocker.

## Automatic repair of incomplete CEF distributions

Reported failure: CMake could not find `libcef_dll/base/cef_atomic_flag.cc`,
although `third/cef/version.txt` matched the pinned CEF release. Inspection found
empty nested source/header directories. The old preparer checked only the stamp
and ignored the extraction exit code, so it could silently reuse incomplete data.

Fix in `third_party/webview_cef/third/download.cmake` and `validate_cef.cmake`:
- Check required nonempty runtime/resource files and common/target-specific
  wrapper/header inventory from CEF's generated source lists before cache reuse.
- Repair automatically using a pinned official archive over verified TLS, checked
  against the CDN's published SHA-1. This is transfer-integrity verification,
  not an independently signed artifact guarantee.
- Stage download/extraction separately; check extraction status, archive root and
  required contents before stamping/promoting. Keep existing data on failures.
- Serialize preparation with a lock, recover interrupted cache promotion and
  replace the cache cleanly instead of merging into incomplete old directories.
- Preserve Linux aarch64 handling without calling host `sed`. Ignore managed
  staging/rollback/lock paths in git; never modify tracked CEF fork sources.

Verification (Linux x86_64):
- `python3 tool/test_cef_download.py`: **14 passed**. Hermetic local archives cover
  matching-stamp damaged caches, nested wrapper/header/resource loss, empty files,
  clean version updates, warm-cache no-download behavior, download/checksum/tar/
  layout/validation failures, previous-cache preservation, interrupted promotion,
  concurrent preparation, Linux Arm64 and Windows Arm64 package selection, and
  Linux/Windows/macOS-specific source inventories. No network or native Windows/
  macOS toolchain is involved in those simulated-platform cases.
- Standalone validation of the repaired actual CEF distribution: **passed**.
- `flutter analyze`: **no issues**; `flutter test`: **51 passed**.
- `bash ./build_linux.sh`: **succeeded end-to-end**, including automatic CEF cache
  replacement and native release build. Executable:
  `build/linux/x64/release/bundle/sirb`.
  Full log: `/tmp/sirb-cef-repair-build.log`.
- Linux x64 outputs regenerated successfully:
  `dist/sirb_1.0.0_amd64.deb`, `dist/sirb-1.0.0-1.x86_64.rpm`,
  `dist/sirb-1.0.0-1-x86_64.pkg.tar.zst`, `dist/sirb-1.0.0-x86_64.tar.gz`,
  `dist/Sirb-1.0.0-x86_64.AppImage`.
  Non-fatal packaging warnings remain about Debian staging ownership, the RPM
  absolute launcher symlink and AppImage's preferred AppStream filename.

Scope check: `lib/screens/desktop` is still the sole targeted screen directory;
this build-infrastructure fix adds no UI. Windows uses the same preparation code
but needs a native build on Windows; macOS retains its CocoaPods preparation path.
No Arm64 outputs were fabricated, and Flatpak was not regenerated. This native
build does not by itself add live Twitch/Kick ad-removal or playback-latency evidence.

## Twitch/Kick H.264/AAC diagnosis and compatible-engine integration

**Status: actual Twitch/Kick playback repair remains blocked by missing decoder
binaries. No codec-enabled CEF artifact was supplied, built or verified.**

Measured on the rebuilt real Linux x64 **CEF 149.0.7827.156**, not system Chromium:
- Isolated profile: `/tmp/sirb-codecs-Rixola`; loopback-only CDP explicitly enabled
  on 9241. The test processes were stopped and that endpoint closed afterwards.
  `GTK_THEME=Adwaita` was needed on this host after an initial host GTK theme crash.
- `build/stream-codecs-shield-off/result.json` confirms Sirb document-start policy,
  blocking=false, focusLoading=false, speculative=false. Both H.264 and AAC MSE
  capability queries returned false; VP9/Opus returned true.
- The local `/clip.mp4` request reached the fixture server, but actual playback
  rejected with NotSupportedError and media error code 4,
  `DEMUXER_ERROR_NO_SUPPORTED_STREAMS`. Zero MP4/MSE frames decoded. The VP9/Opus
  control advanced from ~0.96 to ~1.96 seconds and decoded 33 frames in that sample.
  This rules out an ad-rule cancellation as the cause of this local codec failure.
- `tool/verify_stream_codecs.py --require-h264-aac` **correctly failed** (exit 1)
  against this official engine. Evidence: `build/stream-codecs-release-gate/result.json`.
  This is an expected unsupported-codec result, **not a passing playback test**.
- Public logged-out visits to `https://www.twitch.tv/monstercat` and
  `https://kick.com/xqc` with blocking disabled returned both codec queries false.
  The updated native bridge recorded one scoped `streamCodecProbe` media log for
  each site. Both channels were offline at probe time; these visits are **not**
  live-stream/VOD playback verification or reproduction of every Twitch #4000.

Implemented across the shared desktop UI/policy and all native build paths:
- Read-only main-frame Twitch/Kick codec reports, an Arabic/English missing-codec
  notice with a media-log action, ephemeral per-tab state and separate AVC/AAC
  fields in Settings diagnostics. No media API spoofing, forced play, token/
  playlist rewriting, ad-rule changes or automatic external browsing.
- Optional `SIRB_CEF_ARCHIVE_DIR`: trusted local, exact-version full CEF archives
  and bare SHA-256 sidecars for Linux/Windows x64/Arm64 and both macOS slices.
  Both cache paths use artifact digest identities; an official build at the same
  version cannot satisfy a custom request. Copies are hashed before extraction;
  version/inventory validation precedes promotion, and configured missing/bad
  artifacts fail without fallback. macOS reuses the shared CMake preparer before
  its existing native wrapper/framework/helper build.
- Source-build/integration and licensing notes: `docs/STREAM_CODECS.md`. That
  documentation is not evidence that a large Chromium codec build was performed.

Automated verification:
- `flutter analyze`: **no issues**; `flutter test`: **53 passed**, including scoped,
  typed/deduplicated codec events, navigation reset and localized notice layout
  at narrow/wide desktop content widths in Arabic and English.
- `python3 tool/test_cef_download.py`: **18 passed**, including same-version source
  switching, hash/version failure preserving old cache, missing configured assets
  refusing fallback, and both macOS archive/identity selections (simulated).
- `dart run tool/export_video_policy.dart > /tmp/sirb-stream-policy.json` then
  `node tool/test_stream_compatibility.cjs /tmp/sirb-stream-policy.json`: **passed**;
  scoped main-frame reporting preserves the native support function and results.
- `bash -n third_party/webview_cef/macos/scripts/download_cef.sh`: **passed**.
- `flutter build linux --release`: **succeeded** with the unchanged codec-limited
  official runtime. Log: `/tmp/sirb-stream-engine-build.log`.

Windows/macOS native builds, codec-enabled decoding and real live/VOD/clip tests
still need suitable artifacts/hosts. Existing `dist/` installers were not
regenerated by this codec-integration change and still contain the official
codec-limited CEF from the preceding packaging run. Rebuilding the application
alone does not install decoders or establish an ad-free/live-playback fix.

## Manual playback and sandbox-injection repair

Shared Dart document policy and `common/webview_app.cc` apply to Linux, Windows
and macOS. No new UI or screen target was introduced; `lib/screens/desktop`
remains the sole targeted screen directory. Windows/macOS native builds still
need their matching hosts; no installers or Arm64 builds were fabricated.
Existing `dist/` installers were not regenerated in this change.

Changes:
- New HTTP(S) documents require trusted local player intent for each media
  element; foreground/background opens, speculative promotion, unrelated page
  clicks and synthetic events do not authorize autoplay. HTML autoplay's native
  path is paused too. After consent, playback/playlist behavior remains the site's.
- Initial and live policy Eval skip non-HTTP(S) utility contexts, including
  `about:blank`/srcdoc. No frame sandbox permission is added or relaxed.
- An isolated profile reproduced the exact logged extension source as **Plasma
  Integration 2.2**, auto-installed by the system. Disable Chrome extensions at
  Sirb engine launch (no extension consent/management surface); retain the CEF V8
  bridge. This eliminates that extension's protected-frame injection without
  suppressing site-authored sandbox warnings. Requires restarting Sirb.
- Exclude only exact policy denials/documented play-pause/new-load cancellations
  from fault telemetry, preserve rejected promises, and avoid duplicate reporting
  of a rejection object. Actual decoder/permission/network failures remain.
  Empty src/href no longer falsely identifies the page as a failed resource.

Verification on this Linux x64 host:
- `flutter analyze`: **no issues**; `flutter test`: **55 passed**.
- `flutter build linux --release`: **passed**; executable:
  `build/linux/x64/release/bundle/sirb`.
- `tool/test_manual_playback.cjs` with `tool/export_media_policy.dart`: **passed**
  foreground/speculative promotion, native HTML autoplay fallback, synthetic/
  unrelated events, trusted player interaction and unchanged successful results.
- `tool/test_runtime_errors.cjs`: **passed** (13 reports), including preserved
  real media failures, suppressed expected races, rejection identity/permission
  semantics, duplicate rejection reports and empty-resource-source handling.
- Actual rebuilt **CEF 149.0.7827.156**, isolated profile
  `/tmp/sirb-manual-check`, explicitly opt-in loopback CDP 9243:
  `tool/verify_manual_playback.py`: **passed**. Top/child documents stayed paused,
  synthetic and unrelated clicks could not unlock playback, trusted player input
  advanced VP9 to ~1 second, pause/reload were respected, and a real target=_blank
  Sirb popup/tab opened paused with no inherited activation. Utility iframe
  sandbox remained empty; **zero diagnostic records** for this valid fixture.
  Native autoplay fallback can advance the clock by sub-millisecond amounts
  before its play event is paused; this is not a network-preload prohibition.
  Evidence: `build/manual-playback-evidence/manual-playback.json`.
- `tool/verify_error_capture.py`: **passed** against the same engine (18 records),
  including real uncaught/worker/console/HTTP failures, denied pointer lock with
  website catch preserved, WebGL loss and no forged native popup.
  Evidence: `build/manual-playback-error-regression/diagnostics.json`.
- Codec probe now uses trusted player input rather than treating CDP's evaluate
  userGesture flag as media consent. Rechecked: VP9/Opus advanced ~1.03 → ~2.03s;
  MP4 still rejected with **NotSupportedError / DEMUXER_ERROR_NO_SUPPORTED_STREAMS**,
  and H.264/AAC MSE remains unsupported. These real errors are not hidden.
  Evidence: `build/manual-playback-codec-regression/result.json`.
- Live logged-out open of the user's exact YouTube URL
  `https://www.youtube.com/watch?v=n1RgvUm3Ki4`: manual policy installed,
  activation=false, video paused at **0:00**, no media-element error. Two initial
  **site-script** sandbox warnings remained; Googlevideo requests returned real
  **403** errors, and intentionally blocked ad_status.js still reports a failed
  ad resource. This is not a claim that CDN/account/network failures were repaired
  or that manual playback/seek on that live video was verified.
  Evidence: `build/manual-playback-evidence/youtube-open.json`.

No YouTube ad rules, codec binaries, signed playback URLs or site sandbox flags
were changed. Genuine site/network warnings are retained, not relabelled as a
successful fix. The isolated test window was closed through WM_DELETE_WINDOW,
all its CEF processes exited, and port 9243 was confirmed closed afterwards.
CDP is not enabled in ordinary launches.

## Follow-up: ResizeObserver and resource-diagnostic routing

Shared changes cover Linux, Windows and macOS through the common Dart desktop
controller/scripts. `lib/screens/desktop` remains the only screen target; no UI
text, colors, platform-only workaround, or new dependency was introduced.

- Cosmetic updates now reuse the live style node and skip unchanged CSS/theme
  assignments instead of removing/reinserting styles on activation/load-end.
  Exceptions and shield-off still remove the sheet. This removes avoidable
  Sirb-induced layout churn; it does not replace/defer website ResizeObserver
  callbacks or guarantee elimination of YouTube's own layout loops.
- Cross-capture ResizeObserver echoes are coalesced (one-second, bounded,
  host/page/source scoped). First diagnostics and genuine repeated same-path
  events remain, annotated as deferred/recoverable notifications.
- A DOM resource-failure echo is omitted only when the same host/source has a
  recent native cancellation already represented by an ad log. Evidence expires
  after two seconds; a bounded 150ms/128-entry pending queue accommodates either
  bridge arrival order. Navigation, reconfiguration and closure clear evidence
  while flushing unconfirmed errors. Unconfirmed failures, shield-off 404s,
  explicit HTTP/code/fetch/media failures remain visible.
- Exact `No available adapters.` warnings remain visible under **graphics** with
  capability metadata; this does not make WebGPU available or force unsafe GPU
  flags. The protected about:blank script warning remains under **permission**
  with its source and protection metadata. No sandbox permissions are relaxed.

Verification:
- `flutter analyze`: **no issues**; `flutter test`: **67 passed**, including
  bounded routing, both capture orders, evidence expiry/reset/host separation,
  pending-error flushing, bounded/sanitized queued payloads, actual HTTP errors,
  and ordinary/native-window bridges.
- `flutter build linux --release`: **passed**. Existing `dist/` installers are
  not regenerated. Windows/macOS native builds still require their native hosts.
- `tool/verify_video_policy.py` with the actual exported policy: **passed** on
  local Chromium YouTube/Twitch/Kick/unrelated-host fixtures. Reapplication kept
  the identical sheet node with **zero cosmetic-sheet mutations**; site exceptions
  removed it. VP9 playback/seek, visible controls and bounded ad seeking passed.
  This is not live-service ad-removal verification.
- Actual rebuilt CEF 149, isolated `/tmp/sirb-diagnostics-on` and
  `/tmp/sirb-diagnostics-off`, opt-in loopback CDP 9251/9252:
  `tool/verify_diagnostic_routing.py`: **passed with shields on and off**.
  A real ResizeObserver fixture produced two browser error events and exactly
  two retained records (not four). A deliberate script injection into a protected
  frame remained blocked and logged as permission; its sandbox stayed unchanged.
  With shield on the ad URL never reached the server and only native ad records
  remained (Chromium may issue multiple parser/speculative-parser attempts).
  With shield off the same URL reached the server and its real 404/DOM failure
  remained. GPU warning classification used an intentionally generated console
  warning, not a claim of physical adapter availability.
  Evidence: `build/diagnostic-routing-{on,off}/diagnostics.json`.
- Existing actual-CEF error-capture regression: **passed** (18 retained records,
  caught permission denial semantics intact). Manual-playback regression:
  **passed**, including new-tab opens, unrelated/synthetic input, real playback,
  pause/reload, and zero failures for its valid fixture.
  Evidence: `build/diagnostic-routing-error-regression/diagnostics.json` and
  `build/diagnostic-routing-media-regression/manual-playback.json`.
- Node runtime-error and manual-playback fixtures: **passed** unchanged.
- Live logged-out user's YouTube URL opened and its viewport was reflowed at
  three widths: video remained paused at **0:00**, **zero** extra ad_status.js
  network-failure records, sandbox warnings retained as permission, no-adapter
  warning retained as graphics, one retained ResizeObserver diagnostic.
  Evidence: `build/diagnostic-routing-youtube/diagnostics.json`.
  This verifies improved routing and manual-start behavior, not repair of all
  site-origin errors or proof of successful live video/CDN playback.

Both isolated test windows were closed through WM_DELETE_WINDOW; their CEF
processes exited and CDP ports 9251/9252 were confirmed closed. Ordinary launches
still do not enable CDP.

## Unused-preload advisories and random public-browsing smoke

Implemented in the shared Dart/CEF policy for Linux, Windows and macOS; the
sole desktop screen has a new localized **Performance hints / تلميحات الأداء**
filter. No mobile/web screen targets exist. Native Windows/macOS/Arm64 runtime
verification still needs matching hosts, and `dist/` installers were not rebuilt.

Fixes and diagnostic behavior:
- Reproduced an actual manual-start regression on the user's YouTube page:
  trusted input on the **bottom play button** rejected with Sirb's NotAllowedError
  and left the video at zero. Its player root is beyond the old four-level scan.
  Normalize SVG/icon children to their button, and search at most six local
  ancestors, never body/root or multi-media feed containers. Consent remains
  per-element/trusted input; opening a tab and unrelated/synthetic actions do
  not authorize playback. No automatic play or codec advertising was added.
- Match only the exact Chromium severity-3 unused-preload warning. Preserve the
  first original message/resource per host/page/resource in a bounded 30-second
  window, classified as performance advice rather than a JS exception. Real
  failures and near-matching/error-level messages remain unchanged. Site preload
  URLs/attributes are not removed, rewritten or fetched merely to avoid warnings.
- Performance hints remain in All, their own localized filter, search and full
  export/copy. Error-only queries/counts/deletion exclude both performance and ad
  records consistently. Existing historical rows are not relabelled/deleted.
- Native network diagnostics now include CEF request status and received bytes,
  and mark failed transfers after successful 2xx headers. HTTP 200 alone is not
  successful stream completion. No signed URL retries, API spoofing or broad
  googlevideo exemptions/blocks were introduced.

Verification:
- `flutter gen-l10n`, `flutter analyze`: **passed / no issues**.
- `flutter test`: **71 passed**, including advice scoping/expiry/severity,
  network metadata preservation, storage filters and localized performance rows
  at 800x600/1600x900 in Arabic and English. Node media/runtime fixtures passed;
  the media fixture now covers deeply nested SVG/button controls.
- `flutter build linux --release`: **passed**. Executable:
  `build/linux/x64/release/bundle/sirb`.
- Actual rebuilt CEF 149 with isolated `/tmp/sirb-browsing-check` and
  `/tmp/sirb-browsing-off`, loopback CDP 9255/9256 explicitly opted in:
  - Updated diagnostic routing fixture **passed, shield on and off**. A real
    successful-but-unused fetch preload produced a retained performance advisory
    while its `as=fetch` link remained intact; repeated identical console echoes
    were coalesced. A deliberately truncated HTTP **200** response retained a
    genuine network failure with code **-354**, requestStatus **4**, receivedBytes
    **12**, and responseBodyTransferFailed metadata. Actual shield-off 404s and
    sandbox/graphics/ResizeObserver diagnostics remained visible.
    Evidence: `build/preload-routing-native{,-off}/diagnostics.json`.
  - Nested-control manual-playback fixture **passed**: synthetic/unrelated input
    still denied, deep local controls accepted, VP9 progressed, pause/reload and
    new-tab manual start preserved, sandbox unchanged, zero fixture faults.
    Evidence: `build/nested-controls-native/manual-playback.json`.
  - Existing error-capture regression **passed** (17 records), retaining real
    uncaught/worker/HTTP/GPU/permission failures and website rejection semantics.
    Evidence: `build/browsing-error-capture-regression/diagnostics.json`.

Public browsing, not just fixtures:
- Added `tool/verify_browsing_smoke.py`: seeded safe public-page sampling,
  logged-out isolated CEF, real trusted media-control input, screenshots and
  bounded CDP/network/SQLite evidence. Signed resource queries are stripped from
  network evidence. The test does not grant permissions or sign in.
- Seed **20261017** opened MDN's play() documentation, Wikipedia, Flutter's GitHub
  repository and Python.org, plus the user's **b57bk2wt3LE** and **I5IhWpEXNVE**,
  **aqz-KE-bpKQ** (Big Buck Bunny), and MDN's public **flower.webm**.
- Final run: all four videos stayed paused at open; all four decoded and
  advanced after trusted player input. The three YouTube videos reached about
  **5.97–5.99 seconds** with increasing decoded frame counts, then respected
  pause. The 5.059-second WebM completed normally (150 decoded frames).
  These are short muted video-progression checks, not an audio/DRM/quality or
  universal live-service guarantee.
- Evidence and screenshots: `build/browsing-smoke-after/results.json` and
  `build/browsing-smoke-after/00.png` through `07.png`.
- A second run with seed **20261018** also passed the strict smoke gate, adding
  **docs.flutter.dev** and **w3.org** to the page sample (six distinct general
  sites across both runs). All four video checks passed again, pause was
  respected, and there were no autoplay/policy/main-navigation violations.
  The user's two YouTube pages each retained three unused-preload records under
  **performance**, not JavaScript faults. Font/cache-resource failures and the
  known unsupported MDN MP4 remained visible rather than being suppressed.
  Evidence: `build/browsing-smoke-rotated/results.json` and its screenshots.
- The initial smoke harness selected overlapping video elements rather than
  prioritizing actual controls, and mislabelled a normally completed short WebM
  as failed. Both harness checks were corrected; do not interpret all four
  earlier false results as four proven application faults. The bottom-control
  NotAllowedError regression was independently reproduced with direct input and
  a pass-through play-rejection observer, then fixed and covered by fixtures.
- Remaining observed external/engine limits are retained: GitHub README image
  redirects returned CEF ERR_INVALID_ARGUMENT, a GitHub endpoint returned 404,
  MDN's MP4 example lacks supported decoders, and site-authored sandbox/WebGPU
  capability warnings still occur. Main page content loaded, but this is not a
  claim that every resource or codec was repaired. The user's intermittent
  googlevideo POST -2/HTTP-200 failure was **not reproduced** in the successful
  playback sample; added metadata diagnoses recurrence, not proof of a CDN fix.

Both isolated test windows were normally closed, all their CEF processes exited,
and loopback ports 9255/9256 were confirmed closed. No normal app launch has CDP
enabled, and no user profile was used for these visits.

## YouTube sandbox/WebGPU notices: scoped classification, not an engine repair

Follow-up for the reported **CgtL5aZtCwY** and **nFOeEPrPt8g** messages:
- The earlier `permission`/`graphics` classification preserved these messages but
  still included them in the error-only view. Added localized **Compatibility
  and protection notices / تنبيهات التوافق والحماية**, with explanatory text
  that neither playback success nor failure follows from these notices alone.
- Classification is deliberately narrow: exact existing Chromium messages,
  HTTPS youtube.com/www.youtube.com home/watch pages, matching warning severity
  and known YouTube source context. WebGPU no-adapter severity **3** requires a
  YouTube page-path source; sandbox-about:blank severity **4** requires the
  `/s/_/ytmainappweb/_/js/` script prefix. Keep the original message, line,
  severity, source, diagnostic and **originalCategory** in retained details.
- These new records remain in All, their own filter, search, full copy/export;
  error-only query/count/delete consistently excludes them alongside ad and
  performance records. No historical rows were changed/deleted. Real network,
  codec, GPU-device, API/permission failures, unrelated script sources, other
  sites, extensions and YouTube Playables are not downgraded.
- The UI test exposed a long-label log-card header overflow at 800x600. Category
  text now wraps within Expanded instead of using an unconstrained label/Spacer.
  Arabic/English notice/filter switching at 800x600 and 1600x900 is covered.
- No GPU, sandbox, extension, permission or media policy was changed in this
  follow-up. This fixes diagnostic presentation, not WebGPU adapter support or
  YouTube's site-authored sandbox attempts. Manual-start policy remains intact.

Validation:
- `flutter gen-l10n`: **passed**; `flutter analyze`: **no issues**.
- `flutter test`: **75 passed**. Includes notice scope/host/source/severity
  counterexamples, retained genuine failures, ordinary/native bridge metadata,
  consistent store filtering/deletion and localized UI/layout regression tests.
- `flutter build linux --release`: **passed**;
  `build/linux/x64/release/bundle/sirb`. Python smoke-tool compilation and
  `git diff --check` passed. Only the shared desktop screen target exists and
  was updated; Windows/macOS runtime/build verification still requires matching
  hosts, and no `dist/` installers were regenerated.
- Smoke helper now accepts repeated `--video-url` and bounded `--page-count`
  arguments, so user-reported public URLs can be measured without editing its
  default video sample. Explicit URLs must be credential-free HTTP(S).

Actual rebuilt CEF 149, isolated logged-out profiles, muted trusted player input:
- **Shield on, strict smoke passed:** both supplied videos stayed paused at
  time zero until player input, advanced to **5.987695 / 5.991714 seconds** and
  **184 decoded frames** each, and respected pause. Both reported diagnostics
  were reproduced and retained as compatibility notices (3/2 notices per page,
  including a repeated sandbox block on the first page), preserving original
  graphics/permission categories and severity. Genuine font/network failure
  **-400** and an accounts.google.com **401** stayed in network, not notices.
  Evidence: `build/youtube-notices-on/results.json` and screenshots.
- **Shield off, partial result; strict smoke failed:** both pages stayed paused
  on open, and both exact diagnostics again routed to retained notices. First
  video progressed to **6.004822 seconds / 185 frames** and respected pause.
  The second video had a six-second **1-of-2 preroll advertisement**, not verified
  main-content playback: it progressed to **5.987221 seconds / 150 frames**,
  then the next advertisement began around the pause check and `pauseRespected`
  was **false** (time reset to 0.032169). Do not count this run as a full playback
  pass or assert that cross-ad pause behavior is fixed. CORS/HTTP/ad-network
  failures remained visible. No site/ad/permission workaround was applied.
  Evidence: `build/youtube-notices-off/results.json` and screenshots.
- Tests used `/tmp/sirb-youtube-notices-{on,off}` and opt-in loopback CDP
  **9257/9258**, not the user profile. Both windows closed normally; all processes
  inheriting either isolated profile exited and both ports were confirmed closed.

Known limits remain: no real WebGPU adapter was added; sandbox violations remain
blocked; official CEF H.264/AAC limitations and intermittent transport failures
are not repaired by reclassifying these notices. Live-service availability and
advertisement transitions are not guaranteed by short video-progression checks.

## Clipboard single-dispatch and reported history/chat diagnostics

- Removed parallel CEF + JavaScript editing paths from keyboard shortcuts and
  website context-menu actions. Native focused-frame commands now preserve
  selection, paste events, rich editing, undo and cross-origin frame ownership.
- Edit accelerators require positive focus in the CEF subtree, not merely absence
  of address/find focus. Flutter new-tab search, address/find, tab-search and
  dialogs keep Flutter editing. Native Windows hooks no longer echo editing
  chords/control characters into CEF; Linux/macOS reserve redo too, and macOS
  reserves physical editing keys on non-Latin layouts.
- Real Linux verification exposed a second issue: automatic CEF OSR kept copied
  text inside CEF while GTK/Flutter still saw the previous desktop clipboard.
  An explicit X11 CEF backend passed the same round-trip. CEF now selects X11
  when DISPLAY is set and ozone-platform was not explicitly chosen. No GPU
  blocklist/permission override or unavailable X11 is forced. Restart required;
  Wayland-only and explicitly selected non-X11 backends remain unverified.
- Exact known YouTube console notices now cover `/feed/history` and WebGPU probes
  from the exact `/live_chat_replay` utility source beneath `/watch`. Tests retain
  original evidence and exclude other routes, origins, error severities and
  failures. ResizeObserver repeats, failed transfers after 200/204 headers,
  googlevideo/timedtext errors, oEmbed 401 and offline errors remain diagnostics;
  none are claimed repaired, silently retried or converted to success.

Verification:
- `flutter test`: **91 passed**, including full BrowserScreen focus/clipboard and
  context-menu regression tests, plus history/chat positive and negative scope.
- `flutter analyze`: **no issues**; `flutter build linux --release`: **passed**.
- `/tmp/sirb-clipboard-venv/bin/python tool/verify_clipboard.py`: **passed** against
  that rebuilt CEF 149 executable, isolated profile and local HTTP fixture,
  opt-in loopback CDP **9268**, real XTest input and actual OS clipboard. Verified
  exactly one paste into input/textarea/contenteditable, one undo/redo, focused
  cross-origin iframe, Flutter new-tab search and address-bar navigation. The
  tool requests GTK X11 for input automation, but supplies **no CEF Ozone switch**:
  this run verifies the new default CEF launch policy. It checks copied fixture
  text in the OS clipboard before submitting, never submits unknown clipboard
  contents, and uses no user profile. It takes window focus and changes the
  desktop clipboard to local fixture text. Evidence:
  `build/clipboard-evidence/clipboard.json` and `sirb.log`.
- `python3 -m py_compile tool/verify_clipboard.py` and `git diff --check`: passed.
- Checked `lib/screens/`: desktop is still the sole screen target. Shared changes
  and all three native key paths were updated; Windows/macOS builds/runtime,
  pure Wayland clipboard and live YouTube/network rechecks are **not verified**.
  Existing historical log rows and `dist/` installers are not regenerated.

## Background tab idle/wake and refresh recovery

Shared `BrowserController` lifecycle and the only screen target,
`lib/screens/desktop`, cover Linux, Windows and macOS. No sleep setting, media
consent, RAM/CPU budget, sandbox or native engine permission was relaxed.

Reproduced regressions before the fix (all five initial lifecycle tests failed):
- An older asynchronous activation could continue its loop and hide the tab
  selected by a newer activation. Epoch checks after awaits and a snapshot of
  the tab collection prevent stale visibility work and concurrent-list mutation.
- Activation could return at CEF creation readiness while background theme,
  visibility and navigation setup was still pending. Per-tab wake futures now
  represent the entire initialization, not just creation.
- Activation during native close could create a replacement too early; the old
  sleep operation then overwrote its phase with sleeping. Retirement requests
  are joined before recreation and no state is written after close. CEF close
  itself remains asynchronous; controller identity rejects late callbacks.
- Retired-host URL/crash callbacks could corrupt the replacement's state.
  URL/title/load/console handlers now require the exact current controller.
- A renderer termination was recorded but the dead controller was reused.
  Selection/retry recreates it, preserving its URL and the genuine diagnostic.

All refresh paths (toolbar, Retry, Ctrl/Cmd+R, shifted chord, F5 and page context
menu) now use the shared recovery method. Healthy reloads retain their controller
and navigation history; missing/terminated hosts are recreated, error UI is
cleared, size/visibility are restored and fresh hosts load their saved URL once.
A late bootstrap about:blank completion no longer completes the real page's
loading state. Media snapshots have a two-second bound; unknown/stalled or
playing state retains the host. Shutdown joins pending wake/retirement requests.
There is no white-page heuristic, periodic forced reload or forced media start.

The real termination probe found an additional native failure not covered by a
mocked channel: replacement hung in retired-controller disposal. The common
native close path held the paint-map mutex across CEF close/texture destruction,
which can wait on another thread needing that mutex. It also retained browser-map
iterators across CloseBrowser/OnBeforeClose callbacks. Close now detaches its
texture under lock, releases the lock before native close/unregistration, and
uses strong-reference snapshots before potentially reentrant close callbacks.
The focused native termination/retry probe then passed, with a fresh CEF target
and visibly rendered Flutter texture rather than merely an accepted Reload call.

Automated verification:
- `flutter test`: **101 passed**, including nine lifecycle tests in
  `test/tab_lifecycle_test.dart` and full-screen Retry/Ctrl+R recovery in
  `test/browser_editing_test.dart`, as well as existing focus/clipboard, media,
  budget, diagnostics and Arabic/English layout regressions.
- `flutter analyze`: **no issues**.
- `cd third_party/webview_cef && flutter test`: **4 passed**.
- `flutter build linux --release`: **passed**;
  `build/linux/x64/release/bundle/sirb`.
- `python3 -m py_compile tool/verify_tab_lifecycle.py`: **passed**.

Native Linux x64 / CEF 149 evidence (isolated profiles, local fixtures, opt-in
loopback CDP 9269 and real XTest input):
- An initial **five-real-minute** idle probe passed host retirement, fresh-host
  wake/navigation, a native Flutter-window pixel check and normal reload. The
  before-idle/after-wake screenshots are **301.304 seconds** apart. Evidence:
  `build/tab-lifecycle-five-minute-evidence/{before-idle,after-wake,after-reload}.png`.
  Its later experimental Page.crash step was not confirmed, so that run is not
  counted as a complete termination/retry pass. Other exploratory fixture runs
  were rejected when they navigated the opener or changed the selected tab.
- The actual termination test uses browser CDP process roles and `/proc` ancestry
  to SIGKILL only renderers descended from the isolated Sirb, never the browser
  process or user applications. The pre-native-fix probe hung in dispose; the
  corrected native close path recreated and rendered the page successfully.
- **Final clean release, full probe passed:**
  `/tmp/sirb-clipboard-venv/bin/python tool/verify_tab_lifecycle.py --idle-minutes 1 --minimize-idle --output build/tab-lifecycle-release`.
  The explicit one-minute threshold was observed after **59.556 seconds** from
  the post-creation timer (lastUsed was set slightly earlier). Verified idle
  host disappearance without a crash log, a different target on wake, actual
  Flutter-window fixture pixels, Ctrl+R after wake, then toolbar refresh after
  deliberately killing **two renderer children**. A fresh target and blue
  fixture pixels returned, and Sirb itself was alive before intentional cleanup.
  Evidence: `build/tab-lifecycle-release/lifecycle.json`, `sirb.log`,
  `after-wake.png`, `after-reload.png`, `after-intentional-crash.png` and
  `after-crash-retry.png`. This is not a claim of live-site/media endurance.
- A separate final five-minute rerun was **not a pass**: the main window underwent
  GTK teardown before the threshold and aborted with SIGABRT in
  `g_mutex_clear`, with FlutterEngineRemoveView complaining about the implicit
  view. Host coredump **1036853** confirms the GTK/Flutter destruction stack;
  `build/tab-lifecycle-final/sirb.log` retains the messages. The initiating close
  is not established and that teardown abort is **not claimed repaired** by the
  idle-tab fix. It must not be misreported as successful tab retirement or
  dismissed as an intentional test SIGTERM. The later minimized one-minute run
  above completed all checks on the same clean executable.

The probe defaults to five real minutes; `--crash-only` explicitly skips the idle
checks (recorded as null), and `--minimize-idle` minimizes only its own window
while waiting and restores it for input checks. It requires websocket-client,
XTest and ImageMagick, and assumes the standard unscaled English desktop fixture
layout for toolbar/tab input. It uses no user profile and closes only its own
process group. Do not run it without warning about test-window/focus changes.

Windows/macOS builds/runtime, Arm64 and Wayland-only presentation require matching
hosts. No `dist/` installers were regenerated by this change.

## YouTube context menus, comment editing and JSON ad-response coverage

This follow-up preserves the existing uncommitted clipboard/lifecycle fixes above.
The only targeted screen remains `lib/screens/desktop`; native menu handling and
Dart/JavaScript policy are common to Linux, Windows and macOS.

Changes:
- Website menus now originate in `CefContextMenuHandler`, with Chromium's actual
  link/selection/editability and view-relative coordinates. A document-start
  **window** capture listener stops trusted events reaching site handlers but
  does not cancel Chromium's default menu action. There is no second JS menu.
  Closed shadow roots and cross-origin frames no longer rely on DOM `closest` or
  frame-local event coordinates. Windowed game hosts retain their native menu.
- Menu actions reject background tabs and replaced controllers. Secondary-button
  movement no longer generates a left drag. Editing still uses exactly one native
  focused-frame command, preserving paste handlers and rich editing/undo.
- YouTube ad cleanup also covers successful same-origin exact player/next API
  `Response.json()` and XHR JSON results, which bypass page `JSON.parse`. Known
  player envelopes, including serialized `args.player_response`, are bounded to
  three wrapper levels. Content metadata/streams, native parsing/abort errors,
  request/response metadata, credentials and opt-out remain intact. No signed
  media URLs, broad CDN blocks, fetch/XHR replacement or permission bypass added.

Automated and native verification:
- `flutter analyze`: **no issues**; `flutter test`: **102 passed**, including
  rejection of a menu from a background tab and a paste after host replacement.
- `cd third_party/webview_cef && flutter test`: **4 passed**.
- Exported production policy + `python3 tool/verify_video_policy.py`: **passed**.
  Tests actual fetch/XHR JSON on player/next, legacy serialized player envelopes,
  initial response, preserved streaming data, unrelated/error endpoints, invalid
  JSON/AbortError, shield off/on, bounded ad seek, media seek/play/pause and site
  exceptions. These are hermetic Chromium fixtures, not universal live ad proof.
- `GTK_THEME=Adwaita /tmp/sirb-update-venv/bin/python tool/verify_clipboard.py
  --output build/context-clipboard-update`: **passed** on real release CEF 149,
  isolated profile, explicit loopback CDP 9268 and real XTest input/OS clipboard.
  All eleven checks passed: input/textarea/rich paste once, undo/redo, nested rich
  context-menu paste and selection copy to the real OS clipboard, focused
  cross-origin frame keyboard/context-menu paste,
  actual iframe menu positioning, site window-handler/closed-shadow link menus,
  background opening and Flutter new-tab/address editing. Native screenshot:
  `build/context-clipboard-update/iframe-menu.png`.
  Early fixture iterations counted the nested paste target incorrectly and
  clicked outside right-aligned menus; those harness errors were corrected before
  the passing run, not treated as application fixes.
- Live **logged-out YouTube** in an isolated profile, opt-in loopback CDP 9273:
  right-clicked a visible recommendation, opened a background tab, used real input
  to navigate the source page via SPA, then repeated successfully on the next
  page. Both source URLs stayed selected when their background links opened.
  Initial page remained paused at zero, shields on, no observed anti-adblock
  warning. Evidence: `build/youtube-menu-update/result.json`, `menu-{0,1}.png`,
  `after.png`. A preliminary harness selected a non-hit-testable player overlay;
  the final probe requires visible hit-tested recommendation anchors.
- Final packaged engine: `tool/verify_browsing_smoke.py --page-count 0` with
  `aqz-KE-bpKQ`, shields **on and off**, isolated profiles and opt-in loopback CDP
  9274/9275: **both strict gates passed**. Manual start, increasing decoded frames
  and position, and trusted pause verified. Evidence:
  `build/youtube-playback-update-{on,off}/results.json` and `00.png`.
  All test processes were stopped; no normal launch enables CDP.
- `bash ./build_linux.sh`: **succeeded**, rebuilding Linux x86_64 release and
  `.deb`, `.rpm`, `.pkg.tar.zst`, `.tar.gz`, `.AppImage` in `dist/`.
  Build log: `/tmp/sirb-update-packages.log`. An initial relocated CMake cache
  referenced `/home/hossam/StudioProjects/sirb`; moving only generated
  `build/linux` aside allowed a clean successful native build. CEF fork/cache
  sources were not deleted. Existing packaging ownership/symlink/AppStream
  advisory warnings remain non-fatal.
- `bash ./flatpak_linux.sh`: **blocked**, missing `flatpak-builder`; the existing
  `dist/com.h.sirb-x86_64.flatpak` is old and **not this update**. No Windows,
  macOS or Arm64 builds were fabricated.

Limits: authenticated YouTube comment submission, logged-in ad delivery,
YouTube live/Shorts transitions and Windows/macOS/Wayland-only clipboard still
need matching account/host verification. Nested contenteditable paste is verified
without signing in, not a claim of authenticated comment submission. A short
logged-out sample cannot prove that every ad or anti-adblock warning is removed,
nor Brave-equivalent protection. Existing H.264/AAC limitations are unchanged.
Python compilation, `git diff --check` and the sole desktop target check passed.

## GitHub Actions native build and release pipeline

Added `.github/workflows/build.yml` and a commit-pinned native Flutter bootstrap.
Main/PR/manual runs build native Linux x86_64/aarch64, Windows x64/arm64 and
macOS Intel/ARM64/universal packages. Tagged or explicitly requested releases
require a matching pubspec version, immutable source/tag identity, every native
job and the exact 23-package inventory. Linux names now match the requested
`-linux-<arch>` convention and add AppImage zsync metadata; Windows generates
MSI/setup EXE/portable ZIP; macOS checks/thins all Mach-O payloads and creates DMGs.
The merged release has `SHA256SUMS.txt`. Old/stale/empty/wrong-architecture outputs
are rejected. GitHub asset sizes/digests are checked before a draft is published.
Published releases/tags are never silently overwritten or retargeted.

Security/scope:
- No PAT or certificate is committed. Only the collector has contents-write
  permission, using `github.token`. Actions and Flutter source are commit pinned;
  AppImage tool/runtime downloads have pinned versions and SHA-256 digests.
- Native ARM Dart bootstrap URLs were checked successfully (HTTP 200 for pinned
  engine's Linux/Windows ARM64 SDKs). No official Linux/Windows ARM64 release SDK
  archive exists for Flutter 3.47.7, so the workflow bootstraps its pinned source
  instead. Windows uses batch/PowerShell, not the x64-only MINGW bootstrap. The
  obsolete Windows `--target-platform` option was removed: native Dart ABI and
  PE header validation determine the actual target.
- macOS public releases require the six documented Developer ID/notarization
  secrets, nested signing, app/DMG notarization and stapling. Non-publish CI DMGs
  are ad-hoc development artifacts only. Windows installers remain unsigned.
  No platform security bypass or fabricated signing success is added.
- Linux armv7/i686 and Windows x86 are unsupported; there are no fake builds.
- `docs/RELEASE_AUTOMATION.md` explains downloads, signing setup, new version/tag
  publication, retention, local commands and limitations. Existing v1.0.0 assets
  are not replaced. Desktop remains the only targeted screen; this is build-only
  work with no UI changes.

Local verification:
- `flutter analyze`: **no issues**; `flutter test`: **102 passed**.
- `cd third_party/webview_cef && flutter test`: **4 passed**.
- `python3 tool/test_cef_download.py`: **18 passed**.
- `python3 -m unittest discover -s tool -p test_release.py -v`: **6 passed**,
  covering exact names/inventory, checksum completeness/order, stale/empty files,
  wrong ELF/PE architectures, both Windows installer manifests/portable payloads,
  stable GUIDs/XML escaping, unsafe versions and mismatching tags.
- `actionlint 1.7.11` (verified published SHA-256): **passed** workflow validation.
- Bash syntax checks, Python compilation and `git diff --check`: **passed**.

These local tests do not compile Windows/macOS or certify native installers,
notarization or ARM runtime behavior. No claim of a successful remote CI build
is made until the new workflow actually completes. Existing local dist packages
and the manually published v1.0.0 release remain the earlier builds, not new
cross-platform CI outputs. Check the workflow run for actual native results.

The first actual Actions run (`39890173532`) reached the native Flutter bootstrap
but failed pub resolution: a shallow SHA-only Flutter checkout reported
`0.0.0-unknown` despite the correct framework/engine revision. The bootstrap now
fetches exactly the `3.47.7` release tag and verifies its peeled commit against
the pinned SHA before invoking Flutter. This preserves SDK version metadata
without trusting a movable tag or fetching the entire SDK history. Native jobs
were skipped in that first run; it is not a successful build.

The subsequent run (`39890467661`) passed the complete validation job on GitHub
and started all seven native targets. It exposed two additional preparation
issues: hosted Windows compiler discovery/version checks rejected Inno Setup,
and all macOS helper links referenced CEF's debug-only ref-counted destructor
while using a Release wrapper. CI now installs SHA-256-verified Inno 6.7.3;
macOS standalone helper compilation matches the wrapper's Release/RelWithDebInfo/
MinSizeRel `NDEBUG` setting, retaining Debug semantics for Debug builds. No CEF
source stubs or missing-source exclusions were added. Those failed jobs are not
claimed successful; follow the latest workflow for the retest.

Native Linux aarch64 **completed all seven package formats and artifact upload**
in run `39890467661` (`packages-linux-aarch64`, about 1.02 GB). The obsolete run
was cancelled only after that successful upload, while x64 was still downloading
Ubuntu packages from a slow Azure mirror. This is real ARM64 build evidence, not
interactive ARM64 runtime verification.

Run `39891962354` again passed GitHub validation. Both Windows hosts installed
the pinned installer toolchain; macOS Release helper linking also passed. The
next native checks exposed three more portability issues, now addressed:
- Explicit `flutter precache --macos` before manually invoking CocoaPods, so its
  post-install hook can find FlutterMacOS.xcframework in a cold SDK checkout.
- Canonicalize CEF cache parent paths before locking/staging/extraction. Windows
  libarchive rejected a Flutter plugin-symlink ancestor; no extraction safety
  option was disabled. A new hermetic symlink-parent/lock/cache-reuse regression
  passes, bringing `tool/test_cef_download.py` to **19 passed**.
- Qualify `CefLifeSpanHandler::WindowOpenDisposition` in declaration/definition:
  MSVC rejected the unqualified inherited typedef as ambiguous, although Linux
  accepted it. No popup behavior or native API signature changes.

These subsequent failures are retained as failures, not successful Windows/macOS
packages. Check the latest run for the cold native retests.

Run `39893036201` hit an existing test timing race before native jobs: 101 Flutter
tests passed, but the native-window diagnostic test queried SQLite before its
unawaited writes cleared the session queue. Its fixed 150ms sleep was sufficient
on earlier runs/local host but not this cold worker. Native diagnostic assertions
now wait (bounded to five seconds) for the required persisted row count, then
perform the same category/payload assertions. No production diagnostics are
suppressed and no assertion is skipped or relaxed. Both native-window store
checks use this persistence condition instead of a fixed sleep.

Run `39893467417` passed validation and **both Linux native jobs**: x86_64 and
aarch64 each uploaded all seven requested supported formats (including genuine
AppImage zsync metadata and Flatpak). Collection correctly skipped because the
other targets failed. Windows got through extraction to the compiler but /WX
rejected deprecated getenv calls and a shadowed mutex guard. Shared environment
reads now use owned `_dupenv_s` copies on Windows (same launch flag semantics),
and the guard was renamed; warning enforcement remains enabled. macOS standalone
helpers linked, but the CocoaPod itself also needed the wrapper's NDEBUG setting;
its evaluated target definitions now match all four supported CMake build types.
The universal job separately hit a CDN partial-transfer error; CEF download now
makes up to three fresh, TLS-verified attempts, deleting partial responses before
retry, with unchanged checksum/staging/promotion protection. A new loopback-only
503 regression verifies retry, while all previous failure/integrity tests remain.

Latest local checks: Linux release rebuild **passed**, Flutter **102 passed**,
release helpers **8 passed** (including fully mocked draft POST/upload/digest
verification and refusal to replace published releases), CEF downloader **20
passed**, actionlint/diff checks passed. Added a Ruby-only podspec ABI configuration
fixture to CI (Ruby is not installed on the local host; native CI retest pending).
Draft creation uses the POST response directly, not draft-by-tag lookup. Platform
packages now explicitly include Sirb/CEF/plugin licenses. Markdown-only branch/PR
changes skip expensive rebuilds; version tags still always trigger release jobs.
No Windows/macOS packaging success was claimed before the next actual native run.

Run `39895818328` passed shared validation (including the Ruby podspec fixture),
**both Linux jobs and both Windows jobs**. All 14 Linux artifacts and six genuine
Windows MSI/setup EXE/portable ZIP packages were built and uploaded with native
x64/ARM64 toolchains. This is build/package proof, not Windows runtime/SmartScreen
verification. macOS CEF helpers and plugin linked after the ABI correction, but
the Runner link exposed CocoaPods' known spaced-framework aggregate flag bug
([CocoaPods #11493](https://github.com/CocoaPods/CocoaPods/issues/11493),
[upstream #27](https://github.com/hlwhl/webview_cef/issues/27)): `Chromium` becomes
one framework and `Embedded Framework` stray arguments. The existing post-install
hook now repairs only that exact structured Xcodeproj signature and saves the
aggregate xcconfig, preserving all other frameworks/libraries/-ObjC/inheritance.
It never renames CEF's framework/install name or clears OTHER_LDFLAGS wholesale.
The Ruby fixture also checks preservation, idempotence and non-CEF Chromium flags.
Mac DMGs and complete merged checksums still required the next successful run.

Run `39898594098` passed shared validation and **all three macOS jobs**, both
Windows jobs and Linux aarch64. The three real DMGs passed native Mach-O/helper
architecture and ad-hoc signature verification and uploaded successfully; no
runtime/Gatekeeper/notarization success is inferred. Only Linux x86_64 failed:
its Azure HTTP Ubuntu mirror downloaded recommended multimedia dependencies at
about 100KB/s and exhausted the 15-minute setup budget before compilation. A
same-commit job-only rerun was attempted; the mirror remained slow. The CI-only
APT bootstrap now selects the same signed official Ubuntu archive over HTTPS,
sets bounded retries/connection timeouts, and avoids unrelated recommended
packages (all explicit build/runtime dependencies remain). ARM ports and other
vendor repositories, APT signature/TLS checks and app sandbox policy are unchanged.
The bootstrap refuses non-GitHub hosts. Native/merged artifacts now expire after
one day to limit multi-GB Actions storage; public releases are separate.

Run `39901498319` confirmed the new APT setup proceeds within budget and all
three macOS targets passed again. Omitting recommended packages exposed that
Ubuntu lists Flatpak's required `eu-strip`/`eu-elfcompress` as recommended rather
than hard dependencies: ARM64 reached actual Flatpak packaging, then failed on
missing `eu-strip`. Added explicit `elfutils`, `desktop-file-utils` and `optipng`
packaging tools instead of reinstalling FFmpeg/desktop portal recommendations or
skipping strip/debug-symbol processing. Full same-commit collection is pending
one final native rerun after this dependency correction.

