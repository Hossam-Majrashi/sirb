import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Sirb'**
  String get appName;

  /// No description provided for @intro.
  ///
  /// In en, this message translates to:
  /// **'A lighter workspace for the web and video. Your tabs, your resources.'**
  String get intro;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get next;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @arabic.
  ///
  /// In en, this message translates to:
  /// **'العربية'**
  String get arabic;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get theme;

  /// No description provided for @dark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get dark;

  /// No description provided for @light.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get light;

  /// No description provided for @system.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get system;

  /// No description provided for @start.
  ///
  /// In en, this message translates to:
  /// **'Start browsing'**
  String get start;

  /// No description provided for @fullscreen.
  ///
  /// In en, this message translates to:
  /// **'Full screen'**
  String get fullscreen;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @general.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get general;

  /// No description provided for @performance.
  ///
  /// In en, this message translates to:
  /// **'Performance'**
  String get performance;

  /// No description provided for @ads.
  ///
  /// In en, this message translates to:
  /// **'Ad blocker'**
  String get ads;

  /// No description provided for @privacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy and data'**
  String get privacy;

  /// No description provided for @developer.
  ///
  /// In en, this message translates to:
  /// **'Developer'**
  String get developer;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @website.
  ///
  /// In en, this message translates to:
  /// **'Website'**
  String get website;

  /// No description provided for @launchFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to open this link.'**
  String get launchFailed;

  /// No description provided for @newTab.
  ///
  /// In en, this message translates to:
  /// **'New tab'**
  String get newTab;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search DuckDuckGo or enter an address'**
  String get searchHint;

  /// No description provided for @addressHint.
  ///
  /// In en, this message translates to:
  /// **'Search or enter an address'**
  String get addressHint;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @mostVisited.
  ///
  /// In en, this message translates to:
  /// **'Most visited'**
  String get mostVisited;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @forward.
  ///
  /// In en, this message translates to:
  /// **'Forward'**
  String get forward;

  /// No description provided for @reload.
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get reload;

  /// No description provided for @stop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stop;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @find.
  ///
  /// In en, this message translates to:
  /// **'Find in page'**
  String get find;

  /// No description provided for @findNext.
  ///
  /// In en, this message translates to:
  /// **'Next match'**
  String get findNext;

  /// No description provided for @findPrevious.
  ///
  /// In en, this message translates to:
  /// **'Previous match'**
  String get findPrevious;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @zoomIn.
  ///
  /// In en, this message translates to:
  /// **'Zoom in'**
  String get zoomIn;

  /// No description provided for @zoomOut.
  ///
  /// In en, this message translates to:
  /// **'Zoom out'**
  String get zoomOut;

  /// No description provided for @zoomReset.
  ///
  /// In en, this message translates to:
  /// **'Reset zoom'**
  String get zoomReset;

  /// No description provided for @downloads.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get downloads;

  /// No description provided for @openBatch.
  ///
  /// In en, this message translates to:
  /// **'Open multiple links'**
  String get openBatch;

  /// No description provided for @openBatchHint.
  ///
  /// In en, this message translates to:
  /// **'Enter links (one per line):'**
  String get openBatchHint;

  /// No description provided for @openTabs.
  ///
  /// In en, this message translates to:
  /// **'Open tabs'**
  String get openTabs;

  /// No description provided for @empty.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet'**
  String get empty;

  /// No description provided for @history.
  ///
  /// In en, this message translates to:
  /// **'Page history'**
  String get history;

  /// No description provided for @tabHistory.
  ///
  /// In en, this message translates to:
  /// **'Closed tab history'**
  String get tabHistory;

  /// No description provided for @restore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restore;

  /// No description provided for @restoreSession.
  ///
  /// In en, this message translates to:
  /// **'Restore your previous session?'**
  String get restoreSession;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In en, this message translates to:
  /// **'New page'**
  String get no;

  /// No description provided for @startup.
  ///
  /// In en, this message translates to:
  /// **'At startup'**
  String get startup;

  /// No description provided for @startupNew.
  ///
  /// In en, this message translates to:
  /// **'New page'**
  String get startupNew;

  /// No description provided for @startupRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore last session'**
  String get startupRestore;

  /// No description provided for @startupAsk.
  ///
  /// In en, this message translates to:
  /// **'Ask each time'**
  String get startupAsk;

  /// No description provided for @searchEngine.
  ///
  /// In en, this message translates to:
  /// **'Search engine'**
  String get searchEngine;

  /// No description provided for @duckduckgo.
  ///
  /// In en, this message translates to:
  /// **'DuckDuckGo'**
  String get duckduckgo;

  /// No description provided for @searchTabs.
  ///
  /// In en, this message translates to:
  /// **'Search tabs'**
  String get searchTabs;

  /// No description provided for @collapse.
  ///
  /// In en, this message translates to:
  /// **'Collapse tabs'**
  String get collapse;

  /// No description provided for @expand.
  ///
  /// In en, this message translates to:
  /// **'Expand tabs'**
  String get expand;

  /// No description provided for @pin.
  ///
  /// In en, this message translates to:
  /// **'Pin / unpin'**
  String get pin;

  /// No description provided for @mute.
  ///
  /// In en, this message translates to:
  /// **'Mute / unmute'**
  String get mute;

  /// No description provided for @duplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get duplicate;

  /// No description provided for @closeOthers.
  ///
  /// In en, this message translates to:
  /// **'Close other tabs'**
  String get closeOthers;

  /// No description provided for @closeAfter.
  ///
  /// In en, this message translates to:
  /// **'Close tabs after this'**
  String get closeAfter;

  /// No description provided for @closeAll.
  ///
  /// In en, this message translates to:
  /// **'Close all tabs'**
  String get closeAll;

  /// No description provided for @sleep.
  ///
  /// In en, this message translates to:
  /// **'Sleep tab'**
  String get sleep;

  /// No description provided for @sleeping.
  ///
  /// In en, this message translates to:
  /// **'Sleeping'**
  String get sleeping;

  /// No description provided for @live.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get live;

  /// No description provided for @background.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get background;

  /// No description provided for @playing.
  ///
  /// In en, this message translates to:
  /// **'Playing media — protected from sleep'**
  String get playing;

  /// No description provided for @tabCount.
  ///
  /// In en, this message translates to:
  /// **'{count} tabs'**
  String tabCount(int count);

  /// No description provided for @operation.
  ///
  /// In en, this message translates to:
  /// **'{count} closed tabs · {time}'**
  String operation(int count, String time);

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @deleteAll.
  ///
  /// In en, this message translates to:
  /// **'Delete all'**
  String get deleteAll;

  /// No description provided for @deleteRange.
  ///
  /// In en, this message translates to:
  /// **'Delete time range'**
  String get deleteRange;

  /// No description provided for @lastHour.
  ///
  /// In en, this message translates to:
  /// **'Last hour'**
  String get lastHour;

  /// No description provided for @lastDay.
  ///
  /// In en, this message translates to:
  /// **'Last day'**
  String get lastDay;

  /// No description provided for @lastWeek.
  ///
  /// In en, this message translates to:
  /// **'Last week'**
  String get lastWeek;

  /// No description provided for @clearHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear page history'**
  String get clearHistory;

  /// No description provided for @clearCookies.
  ///
  /// In en, this message translates to:
  /// **'Clear cookies'**
  String get clearCookies;

  /// No description provided for @clearCache.
  ///
  /// In en, this message translates to:
  /// **'Clear cache and restart'**
  String get clearCache;

  /// No description provided for @dataCleared.
  ///
  /// In en, this message translates to:
  /// **'Data cleared'**
  String get dataCleared;

  /// No description provided for @confirmDelete.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes the selected data. Continue?'**
  String get confirmDelete;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @cpu.
  ///
  /// In en, this message translates to:
  /// **'Maximum CPU cores'**
  String get cpu;

  /// No description provided for @ram.
  ///
  /// In en, this message translates to:
  /// **'Maximum RAM'**
  String get ram;

  /// No description provided for @gpu.
  ///
  /// In en, this message translates to:
  /// **'Graphics adapter'**
  String get gpu;

  /// No description provided for @automatic.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get automatic;

  /// No description provided for @discrete.
  ///
  /// In en, this message translates to:
  /// **'Discrete'**
  String get discrete;

  /// No description provided for @integrated.
  ///
  /// In en, this message translates to:
  /// **'Integrated'**
  String get integrated;

  /// No description provided for @acceleration.
  ///
  /// In en, this message translates to:
  /// **'Hardware acceleration'**
  String get acceleration;

  /// No description provided for @unlimited.
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get unlimited;

  /// No description provided for @idleMinutes.
  ///
  /// In en, this message translates to:
  /// **'Idle sleep timeout'**
  String get idleMinutes;

  /// No description provided for @disabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get disabled;

  /// No description provided for @minutes.
  ///
  /// In en, this message translates to:
  /// **'{count} minutes'**
  String minutes(int count);

  /// No description provided for @liveLimit.
  ///
  /// In en, this message translates to:
  /// **'Maximum live tabs'**
  String get liveLimit;

  /// No description provided for @preload.
  ///
  /// In en, this message translates to:
  /// **'Preload hovered video links'**
  String get preload;

  /// No description provided for @preloadLimit.
  ///
  /// In en, this message translates to:
  /// **'Concurrent preloads'**
  String get preloadLimit;

  /// No description provided for @restart.
  ///
  /// In en, this message translates to:
  /// **'Apply and restart'**
  String get restart;

  /// No description provided for @restartRequired.
  ///
  /// In en, this message translates to:
  /// **'CPU, RAM and GPU changes take effect after restart. Your session will be restored.'**
  String get restartRequired;

  /// No description provided for @cpuUnavailable.
  ///
  /// In en, this message translates to:
  /// **'CPU affinity is unavailable on this operating system.'**
  String get cpuUnavailable;

  /// No description provided for @gpuUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The operating system manages GPU selection, or no suitable pair of adapters was detected.'**
  String get gpuUnavailable;

  /// No description provided for @hardRamUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Hard RAM limits are unavailable here. Tab sleeping still enforces a soft budget.'**
  String get hardRamUnavailable;

  /// No description provided for @hardRam.
  ///
  /// In en, this message translates to:
  /// **'Strict operating-system RAM limit'**
  String get hardRam;

  /// No description provided for @device.
  ///
  /// In en, this message translates to:
  /// **'Detected device'**
  String get device;

  /// No description provided for @cores.
  ///
  /// In en, this message translates to:
  /// **'{count} logical cores'**
  String cores(int count);

  /// No description provided for @gigabytes.
  ///
  /// In en, this message translates to:
  /// **'{value} GB'**
  String gigabytes(String value);

  /// No description provided for @usage.
  ///
  /// In en, this message translates to:
  /// **'Process-tree RAM: {value}'**
  String usage(String value);

  /// No description provided for @unknownHardware.
  ///
  /// In en, this message translates to:
  /// **'Hardware information unavailable'**
  String get unknownHardware;

  /// No description provided for @resourceError.
  ///
  /// In en, this message translates to:
  /// **'Resource setting failed: {error}'**
  String resourceError(String error);

  /// No description provided for @resourcePressure.
  ///
  /// In en, this message translates to:
  /// **'Memory budget is tight. Playing tabs will not be interrupted.'**
  String get resourcePressure;

  /// No description provided for @blockEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enable ad blocking'**
  String get blockEnabled;

  /// No description provided for @siteBlocking.
  ///
  /// In en, this message translates to:
  /// **'Toggle blocking on this site'**
  String get siteBlocking;

  /// No description provided for @blocked.
  ///
  /// In en, this message translates to:
  /// **'{count} requests blocked'**
  String blocked(int count);

  /// No description provided for @allowlist.
  ///
  /// In en, this message translates to:
  /// **'Sites with blocking disabled'**
  String get allowlist;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @adNotice.
  ///
  /// In en, this message translates to:
  /// **'YouTube changes frequently. Rules may need updating; server-inserted ads cannot be guaranteed to be removed.'**
  String get adNotice;

  /// No description provided for @codecNotice.
  ///
  /// In en, this message translates to:
  /// **'Codec support depends on the bundled CEF build. Twitch and Kick commonly require H.264 and AAC via MSE. Check both in diagnostics; if unavailable, use a matching, legally licensed codec-enabled CEF distribution. Ad-block settings cannot add decoders. Native HLS and DRM are separate capabilities.'**
  String get codecNotice;

  /// No description provided for @streamCodecUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This engine lacks H.264 or AAC support commonly required by Twitch and Kick. A codec-enabled engine build is needed; changing ad-block settings cannot add these decoders.'**
  String get streamCodecUnavailable;

  /// No description provided for @engineError.
  ///
  /// In en, this message translates to:
  /// **'Chromium could not start: {error}'**
  String engineError(String error);

  /// No description provided for @pageError.
  ///
  /// In en, this message translates to:
  /// **'This page could not load: {error}'**
  String pageError(String error);

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @downloadComplete.
  ///
  /// In en, this message translates to:
  /// **'Complete'**
  String get downloadComplete;

  /// No description provided for @downloadCanceled.
  ///
  /// In en, this message translates to:
  /// **'Canceled'**
  String get downloadCanceled;

  /// No description provided for @downloadProgress.
  ///
  /// In en, this message translates to:
  /// **'{value}%'**
  String downloadProgress(int value);

  /// No description provided for @openFile.
  ///
  /// In en, this message translates to:
  /// **'Open downloaded file'**
  String get openFile;

  /// No description provided for @devtools.
  ///
  /// In en, this message translates to:
  /// **'Developer tools'**
  String get devtools;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading'**
  String get loading;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Persistent browser profile'**
  String get profile;

  /// No description provided for @mediaTests.
  ///
  /// In en, this message translates to:
  /// **'Audio and graphics diagnostics'**
  String get mediaTests;

  /// No description provided for @runMediaTests.
  ///
  /// In en, this message translates to:
  /// **'Check codecs, audio and graphics'**
  String get runMediaTests;

  /// No description provided for @testResult.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics: {value}'**
  String testResult(String value);

  /// No description provided for @openLinkInNewTab.
  ///
  /// In en, this message translates to:
  /// **'Open link in new tab'**
  String get openLinkInNewTab;

  /// No description provided for @copyLinkAddress.
  ///
  /// In en, this message translates to:
  /// **'Copy link address'**
  String get copyLinkAddress;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @paste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get paste;

  /// No description provided for @cut.
  ///
  /// In en, this message translates to:
  /// **'Cut'**
  String get cut;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get selectAll;

  /// No description provided for @errorLogs.
  ///
  /// In en, this message translates to:
  /// **'Error logs'**
  String get errorLogs;

  /// No description provided for @adErrorLogs.
  ///
  /// In en, this message translates to:
  /// **'Ad error logs'**
  String get adErrorLogs;

  /// No description provided for @copyAll.
  ///
  /// In en, this message translates to:
  /// **'Copy all'**
  String get copyAll;

  /// No description provided for @copiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get copiedToClipboard;

  /// No description provided for @clearLogs.
  ///
  /// In en, this message translates to:
  /// **'Clear logs'**
  String get clearLogs;

  /// No description provided for @confirmDeleteLogs.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete all error logs? This cannot be undone.'**
  String get confirmDeleteLogs;

  /// No description provided for @exportTxt.
  ///
  /// In en, this message translates to:
  /// **'Export TXT'**
  String get exportTxt;

  /// No description provided for @logsExported.
  ///
  /// In en, this message translates to:
  /// **'Logs exported to {path}'**
  String logsExported(String path);

  /// No description provided for @allLogs.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get allLogs;

  /// No description provided for @adLogs.
  ///
  /// In en, this message translates to:
  /// **'Ad errors'**
  String get adLogs;

  /// No description provided for @networkLogs.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get networkLogs;

  /// No description provided for @crashLogs.
  ///
  /// In en, this message translates to:
  /// **'Crashes'**
  String get crashLogs;

  /// No description provided for @systemLogs.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get systemLogs;

  /// No description provided for @logUrl.
  ///
  /// In en, this message translates to:
  /// **'Site URL: {url}'**
  String logUrl(String url);

  /// No description provided for @errorDetails.
  ///
  /// In en, this message translates to:
  /// **'Details: {details}'**
  String errorDetails(String details);

  /// No description provided for @totalLogs.
  ///
  /// In en, this message translates to:
  /// **'{count} log entries'**
  String totalLogs(int count);

  /// No description provided for @openGameWindow.
  ///
  /// In en, this message translates to:
  /// **'Open in native game window'**
  String get openGameWindow;

  /// No description provided for @gameWindowNotice.
  ///
  /// In en, this message translates to:
  /// **'Reload this page in a separate Sirb Chromium window for real mouse capture. Normal permission prompts remain enabled; press Esc to release the mouse. The current tab is released only after the window opens to avoid loading the game twice. One game window at a time; it closes with Sirb and is not restored after restart.'**
  String get gameWindowNotice;

  /// No description provided for @javascriptLogs.
  ///
  /// In en, this message translates to:
  /// **'JavaScript / console'**
  String get javascriptLogs;

  /// No description provided for @performanceLogs.
  ///
  /// In en, this message translates to:
  /// **'Performance hints'**
  String get performanceLogs;

  /// No description provided for @compatibilityLogs.
  ///
  /// In en, this message translates to:
  /// **'Compatibility and protection notices'**
  String get compatibilityLogs;

  /// No description provided for @compatibilityLogsNotice.
  ///
  /// In en, this message translates to:
  /// **'These notices retain YouTube\'s optional WebGPU capability probe and blocked sandbox-script attempts. They do not by themselves establish playback failure or success. Real media, network, graphics-device and user-permission failures remain in Errors. Frame protection and GPU settings were not weakened.'**
  String get compatibilityLogsNotice;

  /// No description provided for @graphicsLogs.
  ///
  /// In en, this message translates to:
  /// **'Graphics'**
  String get graphicsLogs;

  /// No description provided for @mediaLogs.
  ///
  /// In en, this message translates to:
  /// **'Audio / video'**
  String get mediaLogs;

  /// No description provided for @permissionLogs.
  ///
  /// In en, this message translates to:
  /// **'Permissions / mouse'**
  String get permissionLogs;

  /// No description provided for @flutterLogs.
  ///
  /// In en, this message translates to:
  /// **'Flutter'**
  String get flutterLogs;

  /// No description provided for @loadMoreLogs.
  ///
  /// In en, this message translates to:
  /// **'Load older logs'**
  String get loadMoreLogs;

  /// No description provided for @errorCaptureNotice.
  ///
  /// In en, this message translates to:
  /// **'Captures console warnings/errors, uncaught JavaScript and promise failures, resource failures, and observed mouse/audio/graphics API failures. Errors hidden inside a site or some workers may remain invisible; an empty log does not prove there are no errors. Logs may contain private URLs or page messages.'**
  String get errorCaptureNotice;

  /// No description provided for @preferredGpu.
  ///
  /// In en, this message translates to:
  /// **'Preferred'**
  String get preferredGpu;

  /// No description provided for @gameMode.
  ///
  /// In en, this message translates to:
  /// **'Game mode'**
  String get gameMode;

  /// No description provided for @gameModeNotice.
  ///
  /// In en, this message translates to:
  /// **'Suspend speculative video preloads. With Automatic graphics and hardware acceleration enabled, prefer the discrete GPU on supported dual-GPU systems after restart. Explicit adapter choices, CPU/RAM limits and playing tabs remain unchanged. GPU selection is not a live switch or an FPS guarantee.'**
  String get gameModeNotice;

  /// No description provided for @graphicsCompatibility.
  ///
  /// In en, this message translates to:
  /// **'Graphics compatibility (WebGL)'**
  String get graphicsCompatibility;

  /// No description provided for @graphicsCompatibilityNotice.
  ///
  /// In en, this message translates to:
  /// **'Disable WebGPU so compatible games can fall back to hardware WebGL. Try this after a WebGPU device-loss error. Requires restart; WebGPU-only sites will not work.'**
  String get graphicsCompatibilityNotice;

  /// No description provided for @gpuSchedulingNotice.
  ///
  /// In en, this message translates to:
  /// **'The OS and driver select the rendering adapter. The browser cannot combine integrated and discrete GPU memory or force 100% utilization. Low usage can indicate a CPU, frame-rate or frame-copy bottleneck.'**
  String get gpuSchedulingNotice;

  /// No description provided for @focusLoading.
  ///
  /// In en, this message translates to:
  /// **'Load visible content first'**
  String get focusLoading;

  /// No description provided for @focusLoadingNotice.
  ///
  /// In en, this message translates to:
  /// **'Suspend speculative video preloads and hint off-screen images and visible-content frames to load lazily. Identifiable hidden YouTube comment/recommendation continuations wait until you approach them (up to 15 seconds). Playback requests are not delayed. Sites may bundle content or start requests before hints apply; this is not a complete network filter. Disable if a site has trouble.'**
  String get focusLoadingNotice;

  /// No description provided for @youtube.
  ///
  /// In en, this message translates to:
  /// **'YouTube'**
  String get youtube;

  /// No description provided for @youtubeOriginalTitles.
  ///
  /// In en, this message translates to:
  /// **'Prefer original video titles'**
  String get youtubeOriginalTitles;

  /// No description provided for @youtubeOriginalTitlesNotice.
  ///
  /// In en, this message translates to:
  /// **'Use YouTube public metadata for visible video titles, including search results, without changing your search or interface language. Up to two small lookups at once; no hidden-card lookups. If metadata is unavailable or itself localized, the original title cannot be guaranteed. Does not translate audio or change subtitles. Changes apply immediately; reload to reset site-managed titles if needed.'**
  String get youtubeOriginalTitlesNotice;

  /// No description provided for @mouseNavigation.
  ///
  /// In en, this message translates to:
  /// **'Mouse side buttons'**
  String get mouseNavigation;

  /// No description provided for @mouseNavigationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Navigate back and forward using mouse side buttons'**
  String get mouseNavigationSubtitle;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
