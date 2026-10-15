// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Sirb';

  @override
  String get intro =>
      'A lighter workspace for the web and video. Your tabs, your resources.';

  @override
  String get next => 'Continue';

  @override
  String get language => 'Language';

  @override
  String get english => 'English';

  @override
  String get arabic => 'العربية';

  @override
  String get theme => 'Appearance';

  @override
  String get dark => 'Dark';

  @override
  String get light => 'Light';

  @override
  String get system => 'System';

  @override
  String get start => 'Start browsing';

  @override
  String get fullscreen => 'Full screen';

  @override
  String get settings => 'Settings';

  @override
  String get general => 'General';

  @override
  String get performance => 'Performance';

  @override
  String get ads => 'Ad blocker';

  @override
  String get privacy => 'Privacy and data';

  @override
  String get developer => 'Developer';

  @override
  String get email => 'Email';

  @override
  String get website => 'Website';

  @override
  String get launchFailed => 'Unable to open this link.';

  @override
  String get newTab => 'New tab';

  @override
  String get searchHint => 'Search DuckDuckGo or enter an address';

  @override
  String get addressHint => 'Search or enter an address';

  @override
  String get search => 'Search';

  @override
  String get mostVisited => 'Most visited';

  @override
  String get back => 'Back';

  @override
  String get forward => 'Forward';

  @override
  String get reload => 'Reload';

  @override
  String get stop => 'Stop';

  @override
  String get home => 'Home';

  @override
  String get find => 'Find in page';

  @override
  String get findNext => 'Next match';

  @override
  String get findPrevious => 'Previous match';

  @override
  String get close => 'Close';

  @override
  String get zoomIn => 'Zoom in';

  @override
  String get zoomOut => 'Zoom out';

  @override
  String get zoomReset => 'Reset zoom';

  @override
  String get downloads => 'Downloads';

  @override
  String get openBatch => 'Open multiple links';

  @override
  String get openBatchHint => 'Enter links (one per line):';

  @override
  String get openTabs => 'Open tabs';

  @override
  String get empty => 'Nothing here yet';

  @override
  String get history => 'Page history';

  @override
  String get tabHistory => 'Closed tab history';

  @override
  String get restore => 'Restore';

  @override
  String get restoreSession => 'Restore your previous session?';

  @override
  String get yes => 'Restore';

  @override
  String get no => 'New page';

  @override
  String get startup => 'At startup';

  @override
  String get startupNew => 'New page';

  @override
  String get startupRestore => 'Restore last session';

  @override
  String get startupAsk => 'Ask each time';

  @override
  String get searchEngine => 'Search engine';

  @override
  String get duckduckgo => 'DuckDuckGo';

  @override
  String get searchTabs => 'Search tabs';

  @override
  String get collapse => 'Collapse tabs';

  @override
  String get expand => 'Expand tabs';

  @override
  String get pin => 'Pin / unpin';

  @override
  String get mute => 'Mute / unmute';

  @override
  String get duplicate => 'Duplicate';

  @override
  String get closeOthers => 'Close other tabs';

  @override
  String get closeAfter => 'Close tabs after this';

  @override
  String get closeAll => 'Close all tabs';

  @override
  String get sleep => 'Sleep tab';

  @override
  String get sleeping => 'Sleeping';

  @override
  String get live => 'Active';

  @override
  String get background => 'Background';

  @override
  String get playing => 'Playing media — protected from sleep';

  @override
  String tabCount(int count) {
    return '$count tabs';
  }

  @override
  String operation(int count, String time) {
    return '$count closed tabs · $time';
  }

  @override
  String get delete => 'Delete';

  @override
  String get deleteAll => 'Delete all';

  @override
  String get deleteRange => 'Delete time range';

  @override
  String get lastHour => 'Last hour';

  @override
  String get lastDay => 'Last day';

  @override
  String get lastWeek => 'Last week';

  @override
  String get clearHistory => 'Clear page history';

  @override
  String get clearCookies => 'Clear cookies';

  @override
  String get clearCache => 'Clear cache and restart';

  @override
  String get dataCleared => 'Data cleared';

  @override
  String get confirmDelete =>
      'This permanently deletes the selected data. Continue?';

  @override
  String get cancel => 'Cancel';

  @override
  String get cpu => 'Maximum CPU cores';

  @override
  String get ram => 'Maximum RAM';

  @override
  String get gpu => 'Graphics adapter';

  @override
  String get automatic => 'Automatic';

  @override
  String get discrete => 'Discrete';

  @override
  String get integrated => 'Integrated';

  @override
  String get acceleration => 'Hardware acceleration';

  @override
  String get unlimited => 'Unlimited';

  @override
  String get idleMinutes => 'Idle sleep timeout';

  @override
  String get disabled => 'Disabled';

  @override
  String minutes(int count) {
    return '$count minutes';
  }

  @override
  String get liveLimit => 'Maximum live tabs';

  @override
  String get preload => 'Preload hovered video links';

  @override
  String get preloadLimit => 'Concurrent preloads';

  @override
  String get restart => 'Apply and restart';

  @override
  String get restartRequired =>
      'CPU, RAM and GPU changes take effect after restart. Your session will be restored.';

  @override
  String get cpuUnavailable =>
      'CPU affinity is unavailable on this operating system.';

  @override
  String get gpuUnavailable =>
      'The operating system manages GPU selection, or no suitable pair of adapters was detected.';

  @override
  String get hardRamUnavailable =>
      'Hard RAM limits are unavailable here. Tab sleeping still enforces a soft budget.';

  @override
  String get hardRam => 'Strict operating-system RAM limit';

  @override
  String get device => 'Detected device';

  @override
  String cores(int count) {
    return '$count logical cores';
  }

  @override
  String gigabytes(String value) {
    return '$value GB';
  }

  @override
  String usage(String value) {
    return 'Process-tree RAM: $value';
  }

  @override
  String get unknownHardware => 'Hardware information unavailable';

  @override
  String resourceError(String error) {
    return 'Resource setting failed: $error';
  }

  @override
  String get resourcePressure =>
      'Memory budget is tight. Playing tabs will not be interrupted.';

  @override
  String get blockEnabled => 'Enable ad blocking';

  @override
  String get siteBlocking => 'Toggle blocking on this site';

  @override
  String blocked(int count) {
    return '$count requests blocked';
  }

  @override
  String get allowlist => 'Sites with blocking disabled';

  @override
  String get remove => 'Remove';

  @override
  String get adNotice =>
      'YouTube changes frequently. Rules may need updating; server-inserted ads cannot be guaranteed to be removed.';

  @override
  String get codecNotice =>
      'Codec support depends on the bundled CEF build. Twitch and Kick commonly require H.264 and AAC via MSE. Check both in diagnostics; if unavailable, use a matching, legally licensed codec-enabled CEF distribution. Ad-block settings cannot add decoders. Native HLS and DRM are separate capabilities.';

  @override
  String get streamCodecUnavailable =>
      'This engine lacks H.264 or AAC support commonly required by Twitch and Kick. A codec-enabled engine build is needed; changing ad-block settings cannot add these decoders.';

  @override
  String engineError(String error) {
    return 'Chromium could not start: $error';
  }

  @override
  String pageError(String error) {
    return 'This page could not load: $error';
  }

  @override
  String get retry => 'Retry';

  @override
  String get downloadComplete => 'Complete';

  @override
  String get downloadCanceled => 'Canceled';

  @override
  String downloadProgress(int value) {
    return '$value%';
  }

  @override
  String get openFile => 'Open downloaded file';

  @override
  String get devtools => 'Developer tools';

  @override
  String get save => 'Save';

  @override
  String get loading => 'Loading';

  @override
  String get confirm => 'Confirm';

  @override
  String get profile => 'Persistent browser profile';

  @override
  String get mediaTests => 'Audio and graphics diagnostics';

  @override
  String get runMediaTests => 'Check codecs, audio and graphics';

  @override
  String testResult(String value) {
    return 'Diagnostics: $value';
  }

  @override
  String get openLinkInNewTab => 'Open link in new tab';

  @override
  String get copyLinkAddress => 'Copy link address';

  @override
  String get copy => 'Copy';

  @override
  String get paste => 'Paste';

  @override
  String get cut => 'Cut';

  @override
  String get selectAll => 'Select all';

  @override
  String get errorLogs => 'Error logs';

  @override
  String get adErrorLogs => 'Ad error logs';

  @override
  String get copyAll => 'Copy all';

  @override
  String get copiedToClipboard => 'Copied to clipboard';

  @override
  String get clearLogs => 'Clear logs';

  @override
  String get confirmDeleteLogs =>
      'Are you sure you want to delete all error logs? This cannot be undone.';

  @override
  String get exportTxt => 'Export TXT';

  @override
  String logsExported(String path) {
    return 'Logs exported to $path';
  }

  @override
  String get allLogs => 'All';

  @override
  String get adLogs => 'Ad errors';

  @override
  String get networkLogs => 'Network';

  @override
  String get crashLogs => 'Crashes';

  @override
  String get systemLogs => 'System';

  @override
  String logUrl(String url) {
    return 'Site URL: $url';
  }

  @override
  String errorDetails(String details) {
    return 'Details: $details';
  }

  @override
  String totalLogs(int count) {
    return '$count log entries';
  }

  @override
  String get openGameWindow => 'Open in native game window';

  @override
  String get gameWindowNotice =>
      'Reload this page in a separate Sirb Chromium window for real mouse capture. Normal permission prompts remain enabled; press Esc to release the mouse. The current tab is released only after the window opens to avoid loading the game twice. One game window at a time; it closes with Sirb and is not restored after restart.';

  @override
  String get javascriptLogs => 'JavaScript / console';

  @override
  String get graphicsLogs => 'Graphics';

  @override
  String get mediaLogs => 'Audio / video';

  @override
  String get permissionLogs => 'Permissions / mouse';

  @override
  String get flutterLogs => 'Flutter';

  @override
  String get loadMoreLogs => 'Load older logs';

  @override
  String get errorCaptureNotice =>
      'Captures console warnings/errors, uncaught JavaScript and promise failures, resource failures, and observed mouse/audio/graphics API failures. Errors hidden inside a site or some workers may remain invisible; an empty log does not prove there are no errors. Logs may contain private URLs or page messages.';

  @override
  String get preferredGpu => 'Preferred';

  @override
  String get gameMode => 'Game mode';

  @override
  String get gameModeNotice =>
      'Suspend speculative video preloads. With Automatic graphics and hardware acceleration enabled, prefer the discrete GPU on supported dual-GPU systems after restart. Explicit adapter choices, CPU/RAM limits and playing tabs remain unchanged. GPU selection is not a live switch or an FPS guarantee.';

  @override
  String get graphicsCompatibility => 'Graphics compatibility (WebGL)';

  @override
  String get graphicsCompatibilityNotice =>
      'Disable WebGPU so compatible games can fall back to hardware WebGL. Try this after a WebGPU device-loss error. Requires restart; WebGPU-only sites will not work.';

  @override
  String get gpuSchedulingNotice =>
      'The OS and driver select the rendering adapter. The browser cannot combine integrated and discrete GPU memory or force 100% utilization. Low usage can indicate a CPU, frame-rate or frame-copy bottleneck.';

  @override
  String get focusLoading => 'Load visible content first';

  @override
  String get focusLoadingNotice =>
      'Suspend speculative video preloads and hint off-screen images and visible-content frames to load lazily. Identifiable hidden YouTube comment/recommendation continuations wait until you approach them (up to 15 seconds). Playback requests are not delayed. Sites may bundle content or start requests before hints apply; this is not a complete network filter. Disable if a site has trouble.';

  @override
  String get youtube => 'YouTube';

  @override
  String get youtubeOriginalTitles => 'Prefer original video titles';

  @override
  String get youtubeOriginalTitlesNotice =>
      'Use YouTube public metadata for visible video titles, including search results, without changing your search or interface language. Up to two small lookups at once; no hidden-card lookups. If metadata is unavailable or itself localized, the original title cannot be guaranteed. Does not translate audio or change subtitles. Changes apply immediately; reload to reset site-managed titles if needed.';

  @override
  String get mouseNavigation => 'Mouse side buttons';

  @override
  String get mouseNavigationSubtitle =>
      'Navigate back and forward using mouse side buttons';
}
