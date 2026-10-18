import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sirb/features/ads/services/ad_blocker.dart';
import 'package:sirb/features/home/services/browser_controller.dart';
import 'package:sirb/features/settings/services/preferences_service.dart';
import 'package:sirb/platform/linux/linux_resources.dart';
import 'package:sirb/shared/services/browser_engine.dart';
import 'package:sirb/shared/services/browser_store.dart';
import 'package:sirb/shared/services/app_runtime.dart';
import 'package:webview_cef/webview_cef.dart';

class _TouchpadResources extends LinuxResources {
  bool natural = true;

  @override
  Future<bool> isTouchpadNaturalScrolling() async => natural;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('webview_cef');
  final calls = <MethodCall>[];
  late Directory temp;
  late BrowserStore store;
  late BrowserController browser;
  late _TouchpadResources resources;
  int nextId = 100;

  Future<void> drain() async {
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  setUp(() async {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'create') {
            final id = nextId++;
            return [id, id];
          }
          if (call.method == 'hasNativeKeySupport') return true;
          return null;
        });
    SharedPreferences.setMockInitialValues({'live_limit': 3});
    final preferences = PreferencesService(
      await SharedPreferences.getInstance(),
    );
    temp = await Directory.systemTemp.createTemp('sirb-response-');
    store = await BrowserStore.open('${temp.path}/test.sqlite');
    resources = _TouchpadResources();
    browser = BrowserController(
      store: store,
      engine: BrowserEngine(
        profile: temp.path,
        blocker: AdBlocker(preferences),
      ),
      preferences: preferences,
      resources: resources,
    );
  });

  tearDown(() async {
    await browser.shutdown();
    browser.dispose();
    await store.close();
    await temp.delete(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'console and caught API errors are recorded without chrome rebuilds',
    () async {
      await browser.initialize();
      await browser.add(url: 'https://example.com/game');
      await drain();
      final listener = browser.active!.controller!.listener!.onConsoleMessage!;
      var rebuilds = 0;
      browser.addListener(() => rebuilds++);
      listener(
        4,
        'Uncaught test exception',
        'https://example.com/script.js',
        12,
      );
      listener(3, 'Test warning', 'https://example.com/worker.js', 7);
      listener(2, 'Informational console output', '', 0);
      listener(
        0,
        '__sirb__${jsonEncode({'type': 'runtimeError', 'category': 'permission', 'message': 'The root document of this element is not valid for pointer lock.', 'operation': 'requestPointerLock', 'details': 'stack trace'})}',
        '',
        0,
      );
      listener(0, '__sirb__[1,2]', '', 0);
      listener(0, '__sirb__not-json', '', 0);
      listener(
        0,
        '__sirb__${jsonEncode({'type': 'runtimeError', 'message': false})}',
        '',
        0,
      );
      await drain();
      final logs = await store.errorLogs();
      expect(logs, hasLength(3));
      expect(
        logs.where((e) => e.type == 'permission').single.details,
        contains('requestPointerLock'),
      );
      expect(logs.every((e) => e.url == 'https://example.com/game'), true);
      expect(rebuilds, 0);
    },
  );

  test('search-page notices persist without hiding real failures', () async {
    await browser.initialize();
    await browser.add(
      url: 'https://www.youtube.com/results?search_query=fixture',
    );
    await drain();
    final listener = browser.active!.controller!.listener!.onConsoleMessage!;
    void event(Map<String, Object?> value) =>
        listener(0, '__sirb__${jsonEncode(value)}', '', 0);
    const resize =
        'ResizeObserver loop completed with undelivered notifications.';
    const source = 'https://static.doubleclick.net/instream/ad_status.js';
    listener(4, resize, browser.active!.url, 0);
    event({
      'type': 'runtimeError',
      'category': 'javascript',
      'message': resize,
      'source': browser.active!.url,
      'line': 0,
      'column': 0,
    });
    event({
      'type': 'runtimeError',
      'category': 'network',
      'message': 'Document resource failed',
      'source': source,
      'resourceTag': 'SCRIPT',
    });
    event({'type': 'blocked', 'url': source});
    event({
      'type': 'runtimeError',
      'category': 'network',
      'message': 'Resource request failed',
      'source': source,
      'httpStatus': 403,
    });
    listener(3, 'No available adapters.', browser.active!.url, 0);
    listener(
      4,
      "Blocked script execution in 'about:blank' because the document's frame is sandboxed and the 'allow-scripts' permission is not set.",
      'https://www.youtube.com/s/_/ytmainappweb/_/js/test-module',
      17593,
    );
    await drain();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final logs = await store.errorLogs();
    expect(logs.where((r) => r.message == resize), hasLength(1));
    expect(
      logs.singleWhere((r) => r.message == resize).details,
      contains('recoverable'),
    );
    expect(logs.where((r) => r.type == 'ad'), hasLength(1));
    expect(logs.where((r) => r.type == 'network'), hasLength(1));
    expect(
      logs.singleWhere((r) => r.type == 'network').details,
      contains('403'),
    );
    final notices = logs.where((r) => r.type == 'compatibility');
    expect(notices, hasLength(2));
    final details = notices.map((r) => jsonDecode(r.details!)).toList();
    expect(
      details.map((d) => d['diagnostic']),
      containsAll(['webgpuAdapterUnavailable', 'frameSandboxBlockedScript']),
    );
    expect(
      details.map((d) => d['originalCategory']),
      containsAll(['graphics', 'permission']),
    );
    expect(details.every((d) => d['advisory'] == true), true);
    expect(await store.errorLogCount(type: 'errors'), 2);
  });

  test(
    'stream codec reports are scoped, deduplicated and reset on navigation',
    () async {
      await browser.initialize();
      await browser.add(url: 'https://www.twitch.tv/fixture');
      await drain();
      final tab = browser.active!;
      final listener = tab.controller!.listener!.onConsoleMessage!;
      void report(Object h264, Object aac, {bool main = true}) => listener(
        0,
        '__sirb__${jsonEncode({'type': 'streamCompatibility', 'main': main, 'h264': h264, 'aac': aac})}',
        '',
        0,
      );
      report(false, false, main: false);
      report('no', false);
      expect(tab.missingStreamCodecs, false);
      report(false, false);
      expect(tab.missingStreamCodecs, true);
      report(false, false);
      await drain();
      expect((await store.errorLogs(type: 'media')).length, 1);
      expect(
        calls.where((c) => c.method == 'loadUrl').last.arguments.toString(),
        contains('twitch.tv/fixture'),
      );
      report(true, true);
      expect(tab.missingStreamCodecs, false);
      report(true, false);
      expect(tab.missingStreamCodecs, true);
      await browser.navigate('sirb:new');
      expect(tab.missingStreamCodecs, false);
      await browser.add(url: 'https://notkick.com/fixture');
      await drain();
      browser.active!.controller!.listener!.onConsoleMessage!(
        0,
        '__sirb__${jsonEncode({'type': 'streamCompatibility', 'main': true, 'h264': false, 'aac': false})}',
        '',
        0,
      );
      expect(browser.active!.missingStreamCodecs, false);
    },
  );

  test(
    'native game diagnostics and lifecycle reach the shared store',
    () async {
      await browser.initialize();
      Future<void> event(Map<String, Object?> value) => WebviewManager()
          .methodCallhandler(MethodCall('sirbNativeEvent', jsonEncode(value)));
      await event({'type': 'gameWindowOpened', 'windowId': 701});
      expect(browser.gameWindowId, 701);
      expect(browser.liveCount, 1);
      await event({
        'type': 'runtimeError',
        'category': 'graphics',
        'message': 'Device lost',
        'url': 'https://example.com/native',
        'operation': 'GPUDevice.lost',
      });
      await event({
        'type': 'renderCrash',
        'error': 'Native renderer terminated',
        'status': 3,
        'code': 137,
        'url': 'https://example.com/native',
      });
      await event({'type': 'gameWindowClosed', 'windowId': 701});
      await drain();
      expect(browser.gameWindowId, null);
      final logs = await store.errorLogs();
      expect(logs.map((e) => e.type), containsAll(['graphics', 'crash']));
      expect(
        logs.firstWhere((e) => e.type == 'crash').details,
        contains('137'),
      );
    },
  );

  test('native-window ad evidence uses the same diagnostic routing', () async {
    await browser.initialize();
    Future<void> event(Map<String, Object?> value) => WebviewManager()
        .methodCallhandler(MethodCall('sirbNativeEvent', jsonEncode(value)));
    const source = 'https://static.doubleclick.net/instream/ad_status.js';
    await event({'type': 'gameWindowOpened', 'windowId': 701});
    await event({
      'type': 'runtimeError',
      'windowId': 701,
      'category': 'network',
      'message': 'Document resource failed',
      'source': source,
      'resourceTag': 'SCRIPT',
    });
    await event({'type': 'blocked', 'windowId': 701, 'url': source});
    await event({
      'type': 'runtimeError',
      'windowId': 701,
      'category': 'network',
      'message': 'Resource request failed',
      'source': source,
      'httpStatus': 403,
    });
    await event({
      'type': 'runtimeError',
      'windowId': 701,
      'category': 'javascript',
      'message': 'No available adapters.',
      'severity': 3,
      'url': 'https://www.youtube.com/watch?v=fixture',
      'source': 'https://www.youtube.com/watch?v=fixture',
    });
    await event({'type': 'gameWindowClosed', 'windowId': 701});
    await drain();
    final logs = await store.errorLogs();
    expect(
      jsonDecode(
        logs.singleWhere((r) => r.type == 'compatibility').details!,
      )['originalCategory'],
      'graphics',
    );
    expect(await store.errorLogCount(type: 'errors'), 1);
    expect(logs.where((r) => r.type == 'ad'), hasLength(1));
    expect(logs.where((r) => r.type == 'network'), hasLength(1));
    expect(
      logs.singleWhere((r) => r.type == 'network').details,
      contains('403'),
    );
  });

  test(
    'native handoff releases the OSR heap only after successful creation',
    () async {
      await browser.initialize();
      await browser.add(url: 'https://example.com/game');
      await drain();
      final tab = browser.active!;
      final source = tab.controller;
      var allowed = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'openGameWindow') {
              if (!allowed) throw PlatformException(code: 'creation_failed');
              return 701;
            }
            return null;
          });
      await expectLater(
        browser.openGameWindow(),
        throwsA(isA<PlatformException>()),
      );
      expect(tab.controller, same(source));
      expect(tab.url, 'https://example.com/game');
      allowed = true;
      await browser.openGameWindow();
      expect(browser.gameWindowId, 701);
      expect(tab.controller, null);
      expect(tab.url, 'sirb:new');
      expect(browser.liveCount, 1);
      await expectLater(browser.openGameWindow(), throwsStateError);
    },
  );

  test(
    'game windows reject internal and file URLs before reaching native code',
    () async {
      await expectLater(
        browser.engine.openGameWindow('file:///tmp/game.html'),
        throwsArgumentError,
      );
      await expectLater(
        browser.engine.openGameWindow('javascript:alert(1)'),
        throwsArgumentError,
      );
      expect(calls.where((c) => c.method == 'openGameWindow'), isEmpty);
    },
  );

  test(
    'older diagnostics remain accessible beyond the default 1000 rows',
    () async {
      await store.db.transaction((tx) async {
        for (var i = 0; i < 1005; i++) {
          await tx.insert('error_logs', {
            'time': i,
            'type': 'javascript',
            'message': 'probe $i',
          });
        }
      });
      expect(await store.errorLogs(), hasLength(1000));
      expect(await store.errorLogs(limit: null), hasLength(1005));
      final older = await store.errorLogs(offset: 1000, limit: 10);
      expect(older, hasLength(5));
      expect(older.first.message, 'probe 4');
      expect(
        await store.errorLogs(query: 'probe 1004', limit: null),
        hasLength(1),
      );
    },
  );

  test('refused native shutdown remains safe and retryable', () async {
    await browser.initialize();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'quit') {
            throw PlatformException(code: 'shutdown_refused');
          }
          return null;
        });
    final runtime = AppRuntime(
      browser.preferences,
      browser.resources,
      browser.engine,
    )..browser = browser;
    for (var attempt = 0; attempt < 2; attempt++) {
      await expectLater(runtime.close(), throwsA(isA<PlatformException>()));
      expect(runtime.closing, false);
    }
    expect(calls.where((c) => c.method == 'quit'), hasLength(2));
  });

  test(
    'game mode clears speculation without changing budgets or playback',
    () async {
      await browser.preferences.set('focus_loading', false);
      await browser.initialize();
      await browser.add(url: 'https://example.com/game');
      await drain();
      final game = browser.active!;
      game.media = true;
      await browser.preload('https://www.youtube.com/watch?v=fixture');
      expect(browser.liveCount, 2);
      final controller = game.controller;
      await browser.preferences.set('game_mode', true);
      await browser.reconfigure();
      expect(browser.preferences.preload, false);
      expect(browser.preferences.cpu, 0);
      expect(browser.preferences.ramGb, 0);
      expect(game.media, true);
      expect(game.controller, same(controller));
      expect(browser.liveCount, 1);
      await browser.preload('https://www.youtube.com/watch?v=other');
      expect(browser.liveCount, 1);
      await browser.preferences.set('game_mode', false);
      expect(browser.preferences.preload, true);
      await browser.preferences.set('preload', false);
      await browser.preferences.set('game_mode', true);
      await browser.preferences.set('game_mode', false);
      expect(browser.preferences.preload, false);
    },
  );

  test(
    'focus loading clears speculation and updates live hosts without reloading media',
    () async {
      await browser.preferences.set('focus_loading', false);
      await browser.initialize();
      await browser.add(url: 'https://www.youtube.com/watch?v=fixture');
      await drain();
      final tab = browser.active!;
      final controller = tab.controller;
      tab.media = true;
      await browser.preload('https://www.youtube.com/watch?v=other');
      expect(browser.liveCount, 2);
      calls.clear();
      await browser.preferences.set('focus_loading', true);
      await browser.preferences.set('youtube_original_titles', false);
      await browser.reconfigure();
      expect(browser.liveCount, 1);
      expect(tab.controller, same(controller));
      expect(tab.media, true);
      expect(calls.where((call) => call.method == 'loadUrl'), isEmpty);
      final controls = calls.where((call) => call.method == 'sirbControl');
      expect(
        controls.any(
          (call) => call.arguments.toString().contains(
            'window.__sirbFocusLoading=true;',
          ),
        ),
        true,
      );
      expect(
        controls.any(
          (call) => call.arguments.toString().contains(
            'window.__sirbOriginalTitles=false;',
          ),
        ),
        true,
      );
      await browser.preload('https://www.youtube.com/watch?v=third');
      expect(browser.liveCount, 1);
    },
  );

  test(
    'live resize coalesces pending sizes and retries failed requests',
    () async {
      await browser.initialize();
      await browser.add(url: 'https://example.com/video');
      await drain();
      final controller = browser.active!.controller!;
      final resizes = <List<dynamic>>[];
      final replies = <Completer<void>>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'setSize') {
              resizes.add(call.arguments as List<dynamic>);
              final reply = Completer<void>();
              replies.add(reply);
              await reply.future;
            }
            return null;
          });
      final first = controller.setSize(1, const Size(900, 600));
      await Future<void>.delayed(Duration.zero);
      final intermediate = controller.setSize(1, const Size(1000, 700));
      final latest = controller.setSize(2, const Size(1400, 900));
      await Future<void>.delayed(Duration.zero);
      expect(resizes, hasLength(1));
      replies[0].complete();
      await Future<void>.delayed(Duration.zero);
      expect(resizes, hasLength(2));
      expect(resizes.last, [controller.browserId, 2.0, 1400.0, 900.0]);
      replies[1].complete();
      await Future.wait([first, intermediate, latest]);
      await controller.setSize(2, const Size(1400, 900));
      expect(resizes, hasLength(2));
      final failed = controller.setSize(1, const Size(800, 600));
      final failure = expectLater(failed, throwsA(isA<PlatformException>()));
      await Future<void>.delayed(Duration.zero);
      replies[2].completeError(PlatformException(code: 'resize_failed'));
      await failure;
      final retry = controller.setSize(1, const Size(800, 600));
      await Future<void>.delayed(Duration.zero);
      expect(resizes, hasLength(4));
      replies[3].complete();
      await retry;
    },
  );

  test('graphics compatibility participates in restart settings', () async {
    final before = browser.preferences.resourceFingerprint;
    expect(browser.preferences.graphicsCompatibility, false);
    await browser.preferences.set('graphics_compatibility', true);
    expect(browser.preferences.graphicsCompatibility, true);
    expect(browser.preferences.resourceFingerprint, isNot(before));
    expect(browser.preferences.acceleration, true);
  });

  test(
    'background links load without activation, focus, or repeated configure',
    () async {
      await browser.initialize();
      final active = browser.activeId;
      final configurations = calls
          .where((c) => c.method == 'sirbConfigure')
          .length;
      await browser.add(
        url: 'https://example.com/background',
        activateTab: false,
      );
      await drain();
      final tab = browser.tabs.last;
      expect(browser.activeId, active);
      expect(tab.controller?.value, true);
      expect(calls.where((c) => c.method == 'loadUrl').last.arguments, [
        tab.controller!.browserId,
        tab.url,
      ]);
      expect(
        calls.where(
          (c) =>
              c.method == 'setClientFocus' &&
              (c.arguments as List).last == true,
        ),
        isEmpty,
      );
      expect(
        calls.where(
          (c) =>
              c.method == 'sirbControl' &&
              (c.arguments as List)[1] == 'hidden' &&
              (c.arguments as List)[2] == 'true',
        ),
        isNotEmpty,
      );
      expect(
        calls.where((c) => c.method == 'sirbConfigure').length,
        configurations,
      );
    },
  );

  test('batch background creation obeys the live host budget', () async {
    await browser.initialize();
    final active = browser.activeId;
    await browser.add(url: 'sirb:new', activateTab: false);
    await browser.openBatch(
      List.generate(10, (i) => 'https://example.com/$i'),
      activateFirst: false,
    );
    await drain();
    expect(browser.activeId, active);
    expect(browser.liveCount, browser.preferences.liveLimit);
    expect(calls.where((c) => c.method == 'create').length, 3);
    expect(
      browser.tabs.where((t) => t.controller == null).length,
      greaterThan(0),
    );
    await browser.closeTabs([
      browser.tabs.firstWhere((t) => t.controller != null),
    ]);
    await drain();
    expect(browser.liveCount, 3);
    expect(calls.where((c) => c.method == 'create').length, 4);
    expect(browser.activeId, active);
  });

  test(
    'background popup disposition and media snapshots preserve active UI',
    () async {
      await browser.initialize();
      final active = browser.activeId;
      await browser.add(url: 'https://example.com/source', activateTab: false);
      await drain();
      final source = browser.tabs.last;
      await browser.add(
        url: 'sirb:new',
        activateTab: false,
        openerId: source.id,
      );
      final trailing = browser.tabs.last;
      source.controller!.listener!.onConsoleMessage!(
        0,
        '__sirb__{"type":"popup","url":"https://example.com/next","background":true}',
        '',
        0,
      );
      await drain();
      expect(browser.activeId, active);
      final popup = browser.tabs[browser.tabs.indexOf(source) + 1];
      expect(popup.url, 'https://example.com/next');
      expect(popup.controller?.value, true);
      expect(browser.tabs.last, trailing);
      var rebuilds = 0;
      browser.addListener(() => rebuilds++);
      source.media = true;
      source.controller!.listener!.onConsoleMessage!(
        0,
        '__sirb__{"type":"media","frame":"main","main":true,"playing":true,"position":12}',
        '',
        0,
      );
      expect(source.videoPosition, 12);
      expect(rebuilds, 0);
    },
  );

  test('new tabs and batches are inserted after the active tab', () async {
    await browser.initialize();
    final opener = browser.active!;
    await browser.add(activateTab: false);
    final trailing = browser.tabs.last;
    await browser.add(activateTab: false);
    expect(browser.tabs[0], opener);
    expect(browser.tabs[2], trailing);
    final previous = browser.tabs[1];
    await browser.openBatch([
      'https://example.com/one',
      'https://example.com/two',
    ], activateFirst: false);
    expect(browser.activeId, opener.id);
    expect(browser.tabs.map((t) => t.url), [
      'sirb:new',
      'https://example.com/one',
      'https://example.com/two',
      'sirb:new',
      'sirb:new',
    ]);
    expect(browser.tabs[3], previous);
    expect(browser.tabs[4], trailing);
    await drain();
  });

  test(
    'Ctrl-click links are inserted after their source, not the active tab',
    () async {
      await browser.initialize();
      final active = browser.activeId;
      await browser.add(url: 'https://example.com/source', activateTab: false);
      await drain();
      final source = browser.tabs.last;
      await browser.add(activateTab: false, openerId: source.id);
      final trailing = browser.tabs.last;
      source.controller!.listener!.onConsoleMessage!(
        0,
        '__sirb__{"type":"navigate","url":"https://example.com/child","newTab":true,"background":true}',
        '',
        0,
      );
      await drain();
      expect(browser.activeId, active);
      expect(
        browser.tabs[browser.tabs.indexOf(source) + 1].url,
        'https://example.com/child',
      );
      expect(browser.tabs.last, trailing);
    },
  );

  test(
    'legacy touchpad overrides do not override the system on live hosts',
    () async {
      await browser.preferences.set('touchpad_direction', 'top_to_bottom');
      await browser.initialize();
      await browser.updateTouchpadSettings();
      await browser.add(url: 'https://example.com');
      final controller = browser.active!.controller!;
      expect(controller.touchpadNaturalScroll, isTrue);
      for (final systemValue in [false, true]) {
        resources.natural = systemValue;
        await browser.preferences.set('touchpad_direction', 'bottom_to_top');
        await browser.updateTouchpadSettings();
        expect(browser.systemTouchpadNatural, systemValue);
        expect(controller.touchpadNaturalScroll, systemValue);
      }
    },
  );

  testWidgets(
    'resize fills the viewport immediately while retaining the produced frame',
    (tester) async {
      await tester.runAsync(() => WebviewManager().initialize());
      final controller = WebviewManager().createWebView();
      await tester.runAsync(() => controller.initialize('about:blank'));
      controller.updateFrameSize(800, 600);
      Widget surface(Size size) => MaterialApp(
        home: Scaffold(
          body: SizedBox.fromSize(size: size, child: controller.webviewWidget),
        ),
      );
      await tester.pumpWidget(surface(const Size(800, 400)));
      final fit = tester.widget<FittedBox>(find.byType(FittedBox));
      expect(fit.fit, BoxFit.fill);
      final texture = tester.renderObject<RenderBox>(find.byType(Texture));
      final textureRect = MatrixUtils.transformRect(
        texture.getTransformTo(null),
        Offset.zero & texture.size,
      );
      final viewportRect = tester.getRect(find.byType(FittedBox));
      expect(textureRect, viewportRect);
      // Grow and shrink without a new CEF paint: no empty strips and no timer.
      for (final size in [const Size(600, 500), const Size(790, 350)]) {
        await tester.pumpWidget(surface(size));
        final box = tester.renderObject<RenderBox>(find.byType(Texture));
        expect(
          MatrixUtils.transformRect(
            box.getTransformTo(null),
            Offset.zero & box.size,
          ),
          tester.getRect(find.byType(FittedBox)),
        );
        await tester.runAsync(
          () async => await Future<void>.delayed(Duration.zero),
        );
        expect(calls.where((c) => c.method == 'setSize').last.arguments, [
          controller.browserId,
          tester.view.devicePixelRatio,
          size.width,
          size.height,
        ]);
        expect(box.size, const Size(800, 600));
      }
      final frame = tester.widget<SizedBox>(
        find
            .descendant(
              of: find.byType(FittedBox),
              matching: find.byType(SizedBox),
            )
            .first,
      );
      expect(frame.width, 800);
      expect(frame.height, 600);
      await WebviewManager().methodCallhandler(
        MethodCall('onFrameSize', {
          'browserId': controller.browserId,
          'width': 1600,
          'height': 800,
        }),
      );
      await tester.pump();
      final updated = tester.widget<SizedBox>(
        find
            .descendant(
              of: find.byType(FittedBox),
              matching: find.byType(SizedBox),
            )
            .first,
      );
      expect(updated.width, 1600);
      expect(updated.height, 800);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => controller.dispose());
    },
  );

  testWidgets('background editable events do not replace address text input', (
    tester,
  ) async {
    await tester.runAsync(() => WebviewManager().initialize());
    final controller = WebviewManager().createWebView();
    await tester.runAsync(() => controller.initialize('about:blank'));
    final focus = FocusNode();
    final text = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TextField(focusNode: focus, controller: text),
              Expanded(child: controller.webviewWidget),
            ],
          ),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    await WebviewManager().methodCallhandler(
      MethodCall('onFocusedNodeChangeMessage', {
        'browserId': controller.browserId,
        'editable': true,
      }),
    );
    await tester.enterText(find.byType(TextField), 'still typing');
    expect(focus.hasFocus, true);
    expect(text.text, 'still typing');
    expect(tester.testTextInput.isRegistered, true);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => controller.dispose());
    focus.dispose();
    text.dispose();
  });
}
