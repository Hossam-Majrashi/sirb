import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sirb/core/l10n/app_localizations.dart';
import 'package:sirb/core/theme/app_theme.dart';
import 'package:sirb/features/ads/services/ad_blocker.dart';
import 'package:sirb/features/home/services/browser_controller.dart';
import 'package:sirb/features/home/widgets/new_tab_page.dart';
import 'package:sirb/features/home/widgets/tab_rail.dart';
import 'package:sirb/features/settings/services/preferences_service.dart';
import 'package:sirb/platform/linux/linux_resources.dart';
import 'package:sirb/platform/macos/macos_resources.dart';
import 'package:sirb/platform/windows/windows_resources.dart';
import 'package:sirb/shared/services/resource_service.dart';
import 'package:sirb/shared/services/app_runtime.dart';
import 'package:sirb/screens/desktop/settings_screen.dart';
import 'package:sirb/screens/desktop/history_screen.dart';
import 'package:sirb/screens/desktop/downloads_screen.dart';
import 'package:sirb/screens/desktop/error_logs_screen.dart';
import 'package:sirb/screens/desktop/onboarding_screen.dart';
import 'package:sirb/shared/models/browser_tab.dart';
import 'package:sirb/shared/services/browser_engine.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:sirb/shared/services/browser_store.dart';
import 'package:sirb/shared/widgets/bounded_page.dart';
import 'package:sirb/screens/desktop/browser_screen.dart';

void main() {
  ResourceService resources() => Platform.isLinux
      ? LinuxResources()
      : Platform.isWindows
      ? WindowsResources()
      : MacosResources();
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late BrowserStore store;
  late PreferencesService preferences;
  late BrowserController browser;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('sirb-test-');
    SharedPreferences.setMockInitialValues({});
    preferences = PreferencesService(await SharedPreferences.getInstance());
    store = await BrowserStore.open('${temp.path}/test.sqlite');
    browser = BrowserController(
      store: store,
      engine: BrowserEngine(
        profile: '${temp.path}/profile',
        blocker: AdBlocker(preferences),
      ),
      preferences: preferences,
      resources: resources(),
    );
  });
  tearDown(() async {
    browser.dispose();
    await store.close();
    await temp.delete(recursive: true);
  });
  Widget app(Widget child, {String language = 'en'}) => MaterialApp(
    locale: Locale(language),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    theme: AppTheme.build(Brightness.light),
    darkTheme: AppTheme.build(Brightness.dark),
    home: Scaffold(body: child),
  );
  test(
    'URL classification and DuckDuckGo-only search ignore legacy providers',
    () async {
      expect(browser.resolve('example.com/path'), 'https://example.com/path');
      expect(
        browser.resolve('a video').startsWith('https://duckduckgo.com/'),
        true,
      );
      expect(
        browser
            .resolve('javascript:alert(1)')
            .startsWith('https://duckduckgo.com/'),
        true,
      );
      for (final engine in ['google', 'bing', 'brave', 'startpage']) {
        await preferences.set('search_engine', engine);
        final target = Uri.parse(browser.resolve('video lesson & عربي'));
        expect(target.host, 'duckduckgo.com');
        expect(target.queryParameters['q'], 'video lesson & عربي');
      }
    },
  );
  test('100 sleeping tabs preserve order and atomic closure groups', () async {
    for (var i = 0; i < 100; i++) {
      browser.tabs.add(
        BrowserTab(
          id: 'tab-$i',
          url: 'https://example.com/$i',
          title: 'Page $i',
          icon: 'https://example.com/favicon.ico',
          videoPosition: i.toDouble(),
        ),
      );
    }
    browser.activeId = 'tab-17';
    await store.saveSession(browser.tabs, browser.activeId);
    final saved = await store.session();
    expect((saved!['tabs'] as List).length, 100);
    expect(saved['active'], 'tab-17');
    final group = browser.tabs.take(5).toList();
    await store.recordClosure(group);
    final closures = await store.closures();
    expect(closures.length, 1);
    final restored = (jsonDecode(closures.single['snapshot'] as String) as List)
        .map((t) => BrowserTab.fromMap(Map<String, dynamic>.from(t as Map)))
        .toList();
    expect(restored.map((t) => t.id), group.map((t) => t.id));
    expect(restored.last.videoPosition, 4);
    browser.reorder(0, 99);
    expect(browser.tabs.last.id, 'tab-0');
  });
  test(
    'openBatch creates tabs in sequential order and handles empty tab',
    () async {
      browser.tabs.add(BrowserTab(id: 'initial', url: 'sirb:new'));
      browser.activeId = 'initial';
      await browser.openBatch([
        'https://www.youtube.com/watch?v=1',
        'https://www.youtube.com/watch?v=2',
        'https://www.youtube.com/watch?v=3',
      ], activateFirst: false);
      expect(browser.tabs.length, 3);
      expect(browser.tabs[0].url, 'https://www.youtube.com/watch?v=1');
      expect(browser.tabs[1].url, 'https://www.youtube.com/watch?v=2');
      expect(browser.tabs[2].url, 'https://www.youtube.com/watch?v=3');
    },
  );
  test(
    'SQLite survives reopening, visits searchable and range deletion works',
    () async {
      final tab = BrowserTab(
        id: 'a',
        url: 'https://example.com',
        title: 'Example',
      );
      await store.saveSession([tab], 'a');
      await store.recordVisit(tab);
      expect((await store.visits('Example')).length, 1);
      await store.close();
      store = await BrowserStore.open('${temp.path}/test.sqlite');
      browser = BrowserController(
        store: store,
        engine: browser.engine,
        preferences: preferences,
        resources: resources(),
      );
      expect((await store.session())!['active'], 'a');
      await store.clearVisits(
        since: DateTime.now().subtract(const Duration(hours: 1)),
      );
      expect(await store.visits(), isEmpty);
    },
  );
  test(
    'ad exceptions persist and document-start script contains three layers',
    () async {
      final blocker = browser.engine.blocker;
      expect(blocker.enabledFor('https://youtube.com'), true);
      await blocker.toggleSite('https://youtube.com/watch?v=1');
      expect(blocker.enabledFor('https://www.youtube.com'), false);
      final config = blocker.configuration('/profile', 'telemetry');
      expect(config['domains'], isNotEmpty);
      expect(config['patterns'], isNotEmpty);
      expect(config['script'].toString(), contains('MutationObserver'));
    },
  );
  test(
    'coalesced session writes preserve the newest order and active tab',
    () async {
      final tabs = <BrowserTab>[], writes = <Future<void>>[];
      for (var i = 0; i < 100; i++) {
        tabs.add(BrowserTab(id: '$i'));
        writes.add(store.saveSession(tabs, '$i'));
      }
      await Future.wait(writes);
      final saved = (await store.session())!;
      expect((saved['tabs'] as List).length, 100);
      expect(saved['active'], '99');
    },
  );
  test('closure and remaining session commit atomically', () async {
    final tabs = List.generate(
      100,
      (i) => BrowserTab(id: '$i', url: 'https://example.com/$i'),
    );
    await store.saveSession(tabs, '99');
    await store.commitClosure(tabs.sublist(1), [tabs.first], '0');
    final session = (await store.session())!;
    expect((session['tabs'] as List).length, 1);
    expect(session['active'], '0');
    expect(
      (jsonDecode((await store.closures()).single['snapshot'] as String)
              as List)
          .length,
      99,
    );
    tabs.first.title = 'Updated title';
    await store.recordVisit(tabs.first);
    tabs.first.title = 'Latest title';
    await store.updateVisitMetadata(tabs.first);
    expect((await store.mostVisited()).single['title'], 'Latest title');
  });
  test(
    'Linux CPU affinity is enforced and can increase to unlimited',
    () async {
      final r = LinuxResources();
      await r.detect();
      String allowed() => RegExp(
        r'Cpus_allowed_list:\s*([^\n]+)',
      ).firstMatch(File('/proc/self/status').readAsStringSync())!.group(1)!;
      try {
        await r.applyCpu(1);
        expect(allowed(), matches(RegExp(r'^\d+$')));
      } finally {
        await r.applyCpu(0);
      }
      expect(allowed(), isNotEmpty);
    },
    skip: !Platform.isLinux,
  );
  testWidgets('all auxiliary screens fit desktop sizes and both directions', (
    tester,
  ) async {
    final device = (await tester.runAsync(() async {
      await browser.resources.hardRamSupported;
      return browser.resources.detect();
    }))!;
    final runtime = AppRuntime(preferences, browser.resources, browser.engine)
      ..browser = browser;
    for (final language in ['en', 'ar']) {
      for (final size in [const Size(800, 600), const Size(1600, 900)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        for (final screen in [
          SettingsScreen(browser: browser, runtime: runtime, device: device),
          HistoryScreen(browser: browser),
          HistoryScreen(browser: browser, closedTabs: true),
          DownloadsScreen(store: store),
          ErrorLogsScreen(store: store),
        ]) {
          await tester.runAsync(() async {
            await tester.pumpWidget(app(screen, language: language));
            await Future<void>.delayed(const Duration(milliseconds: 150));
          });
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (screen is SettingsScreen) {
            expect(find.text('DuckDuckGo'), findsOneWidget);
            for (final removed in [
              'Google',
              'Bing',
              'Brave Search',
              'Startpage',
              'Touchpad two-finger scrolling',
              'التمرير بالتتش باد بإصبعين',
            ]) {
              expect(find.text(removed), findsNothing);
            }
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      }
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  testWidgets('onboarding progresses introduction, locale, appearance', (
    tester,
  ) async {
    await tester.pumpWidget(app(OnboardingScreen(preferences: preferences)));
    await tester.pumpAndSettle();
    expect(find.text('Sirb'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Language'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsOneWidget);
    await tester.tap(find.text('Start browsing'));
    await tester.pumpAndSettle();
    expect(preferences.onboardingDone, true);
  });
  testWidgets('Arabic RTL and 100-tab rail fit 800x600 and 1600x900', (
    tester,
  ) async {
    for (var i = 0; i < 100; i++) {
      browser.tabs.add(BrowserTab(id: '$i', url: 'sirb:new'));
    }
    browser.activeId = '0';
    for (final size in [const Size(800, 600), const Size(1600, 900)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        app(
          Row(
            children: [
              SizedBox(
                width: 260,
                child: TabRail(
                  browser: browser,
                  collapsed: false,
                  onCollapse: () {},
                ),
              ),
              Expanded(child: NewTabPage(browser: browser)),
            ],
          ),
          language: 'ar',
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        Directionality.of(tester.element(find.byType(NewTabPage))),
        TextDirection.rtl,
      );
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  test(
    'Linux GPU detection populates render nodes and discrete preference overrides render node',
    () async {
      if (!Platform.isLinux) return;
      final lr = LinuxResources();
      final info = await lr.detect();
      expect(info.gpus, isNotEmpty);
      if (lr.gpuSupported) {
        final env = lr.launchEnvironment('discrete', true);
        expect(env['SIRB_GPU_ACCELERATION'], '1');
        expect(env['__NV_PRIME_RENDER_OFFLOAD'], '1');
        expect(env['__GLX_VENDOR_LIBRARY_NAME'], 'nvidia');
        expect(env['SIRB_CEF_SWITCHES'], contains('render-node-override='));
      }
    },
  );
  test(
    'BrowserController updates viewport and dispatches contextMenu',
    () async {
      browser.updateViewport(const Size(1920, 1080), 1.25);
      expect(browser.viewportSize, const Size(1920, 1080));
      expect(browser.viewportDpi, 1.25);

      Map<String, dynamic>? receivedEvent;
      browser.onContextMenu = (tab, event) => receivedEvent = event;
      final tab = BrowserTab(id: 't1', url: 'https://example.com');
      browser.tabs.add(tab);
      browser.activeId = tab.id;

      browser.onContextMenu?.call(tab, {
        'type': 'contextMenu',
        'x': 100,
        'y': 200,
        'link': 'https://example.com/video',
      });
      expect(receivedEvent, isNotNull);
      expect(receivedEvent!['link'], 'https://example.com/video');
    },
  );
  test(
    'Error logs store recording, filtering, deleting, and clearing',
    () async {
      await store.recordErrorLog(
        type: 'ad',
        message: 'Blocked ad request',
        url: 'https://example.com',
        details: 'https://adservice.google.com/ad.js',
      );
      await store.recordErrorLog(
        type: 'network',
        message: 'Failed to load',
        url: 'https://broken.com',
        details: 'ERR_NAME_NOT_RESOLVED',
      );
      expect(await store.errorLogCount(), 2);
      expect(await store.errorLogCount(type: 'ad'), 1);
      expect(await store.errorLogCount(type: 'network'), 1);
      expect(await store.errorLogCount(type: 'errors'), 1);

      final adLogs = await store.errorLogs(type: 'ad');
      expect(adLogs.length, 1);
      expect(adLogs.first.url, 'https://example.com');
      expect(adLogs.first.details, 'https://adservice.google.com/ad.js');
      expect(adLogs.first.toFormattedString(), contains('https://example.com'));

      final errorLogsOnly = await store.errorLogs(type: 'errors');
      expect(errorLogsOnly.length, 1);
      expect(errorLogsOnly.first.type, 'network');
      expect(errorLogsOnly.first.message, 'Failed to load');

      final allLogs = await store.errorLogs();
      expect(allLogs.length, 2);

      await store.deleteErrorLog(adLogs.first.id);
      expect(await store.errorLogCount(type: 'ad'), 0);
      expect(await store.errorLogCount(type: 'errors'), 1);
      expect(await store.errorLogCount(), 1);

      await store.clearErrorLogs(type: 'errors');
      expect(await store.errorLogCount(type: 'errors'), 0);
      expect(await store.errorLogCount(), 0);
    },
  );

  test(
    'touchpad scrolling follows the system despite legacy overrides',
    () async {
      final natural = await resources().isTouchpadNaturalScrolling();
      for (final legacy in ['bottom_to_top', 'top_to_bottom', 'system']) {
        await preferences.set('touchpad_direction', legacy);
        await browser.updateTouchpadSettings();
        expect(browser.systemTouchpadNatural, natural);
      }
    },
  );

  test(
    'UniversalActivator accepts key events across layouts and respects predicate',
    () {
      var allowShortcut = true;
      final activator = UniversalActivator(
        PhysicalKeyboardKey.keyC,
        LogicalKeyboardKey.keyC,
        control: true,
        predicate: () => allowShortcut,
      );
      expect(activator.triggers, isNull);
      expect(activator.debugDescribeKeys(), contains('Control'));
      expect(activator.debugDescribeKeys(), contains('Key C'));

      // When predicate is false (e.g. text field focused), shortcut must not be accepted
      allowShortcut = false;
      expect(
        activator.accepts(
          const KeyDownEvent(
            physicalKey: PhysicalKeyboardKey.keyC,
            logicalKey: LogicalKeyboardKey.keyC,
            timeStamp: Duration.zero,
          ),
          HardwareKeyboard.instance,
        ),
        false,
      );
    },
  );

  test('mouseNavigation preference defaults to true and toggles', () async {
    final prefs = await SharedPreferences.getInstance();
    final preferences = PreferencesService(prefs);
    expect(preferences.mouseNavigation, isTrue);
    await preferences.set('mouse_navigation', false);
    expect(preferences.mouseNavigation, isFalse);
    await preferences.set('mouse_navigation', true);
    expect(preferences.mouseNavigation, isTrue);
  });

  test(
    'BrowserController goBack and goForward safely handle null or active controllers',
    () async {
      await expectLater(browser.goBack(), completes);
      await expectLater(browser.goForward(), completes);
    },
  );

  testWidgets('BoundedPage pops route when kBackMouseButton is clicked', (
    tester,
  ) async {
    var popped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              Navigator.of(context)
                  .push(
                    MaterialPageRoute<void>(
                      builder: (_) => const Scaffold(
                        body: BoundedPage(child: Text('Modal Content')),
                      ),
                    ),
                  )
                  .then((_) => popped = true);
            },
            child: const Text('Open Modal'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Modal'));
    await tester.pumpAndSettle();
    expect(find.text('Modal Content'), findsOneWidget);

    final event = PointerDownEvent(
      position: tester.getCenter(find.text('Modal Content')),
      buttons: kBackMouseButton,
    );
    await tester.sendEventToBinding(event);
    await tester.pumpAndSettle();

    expect(popped, isTrue);
    expect(find.text('Modal Content'), findsNothing);
  });
}
