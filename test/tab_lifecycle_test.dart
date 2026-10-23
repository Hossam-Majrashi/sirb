import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sirb/features/ads/services/ad_blocker.dart';
import 'package:sirb/features/home/services/browser_controller.dart';
import 'package:sirb/features/settings/services/preferences_service.dart';
import 'package:sirb/platform/linux/linux_resources.dart';
import 'package:sirb/shared/models/browser_tab.dart';
import 'package:sirb/shared/services/browser_engine.dart';
import 'package:sirb/shared/services/browser_store.dart';
import 'package:webview_cef/webview_cef.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('webview_cef');
  final calls = <MethodCall>[];
  final hidden = <int, bool>{};
  Future<void> Function(MethodCall)? beforeCall;
  late Directory temp;
  late BrowserStore store;
  late BrowserController browser;
  var nextId = 100;

  setUp(() async {
    calls.clear();
    hidden.clear();
    beforeCall = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          await beforeCall?.call(call);
          if (call.method == 'create') {
            final id = nextId++;
            return [id, id];
          }
          if (call.method == 'evaluateJavascript') return '[]';
          if (call.method == 'sirbControl') {
            final args = call.arguments as List;
            if (args[1] == 'hidden') hidden[args[0] as int] = args[2] == 'true';
          }
          return null;
        });
    SharedPreferences.setMockInitialValues({
      'live_limit': 20,
      'idle_minutes': 5,
    });
    final preferences = PreferencesService(
      await SharedPreferences.getInstance(),
    );
    temp = await Directory.systemTemp.createTemp('sirb-lifecycle-');
    store = await BrowserStore.open('${temp.path}/test.sqlite');
    browser = BrowserController(
      store: store,
      engine: BrowserEngine(
        profile: temp.path,
        blocker: AdBlocker(preferences),
      ),
      preferences: preferences,
      resources: LinuxResources(),
    );
    await browser.initialize();
  });

  tearDown(() async {
    beforeCall = null;
    await browser.shutdown();
    browser.dispose();
    await store.close();
    await temp.delete(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<BrowserTab> background(String name) async {
    await browser.add(
      url: 'https://example.test/$name',
      activateTab: false,
      openerId: browser.tabs.last.id,
    );
    final tab = browser.tabs.last;
    // Join the existing background initialization, not only CEF creation.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    return tab;
  }

  void crash(
    WebViewController controller,
  ) => controller.listener!.onConsoleMessage!(
    0,
    '__sirb__${jsonEncode({'type': 'renderCrash', 'error': 'Renderer terminated', 'status': 3, 'code': 9})}',
    'sirb',
    0,
  );

  test('an obsolete activation cannot hide the newly selected tab', () async {
    final first = await background('first');
    final second = await background('second');
    final third = await background('third');
    final entered = Completer<void>(), release = Completer<void>();
    var held = false;
    beforeCall = (call) async {
      if (!held && call.method == 'sirbControl') {
        final args = call.arguments as List;
        if (args[0] == first.controller!.browserId && args[1] == 'hidden') {
          held = true;
          entered.complete();
          await release.future;
        }
      }
    };
    final oldSelection = browser.activate(second.id);
    await entered.future;
    await browser.activate(third.id);
    release.complete();
    await oldSelection;
    expect(browser.activeId, third.id);
    expect(hidden[third.controller!.browserId], false);
    expect(hidden[second.controller!.browserId], true);
    expect(third.phase, TabPhase.active);
  });

  test(
    'activation joins full background initialization before returning',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      var held = false;
      beforeCall = (call) async {
        if (!held &&
            call.method == 'sirbControl' &&
            (call.arguments as List)[1] == 'theme') {
          held = true;
          entered.complete();
          await release.future;
        }
      };
      await browser.add(
        url: 'https://example.test/initializing',
        activateTab: false,
      );
      final tab = browser.tabs.last;
      await entered.future;
      var finished = false;
      final activation = browser.activate(tab.id).then((_) => finished = true);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      final returnedTooEarly = finished;
      release.complete();
      await activation;
      expect(returnedTooEarly, false);
      // A late bootstrap about:blank completion is not completion of the
      // restored document and must not clear its loading state.
      tab.controller!.listener!.onLoadEnd!(tab.controller!, 'about:blank');
      expect(tab.loading, true);
      expect(calls.where((c) => c.method == 'create'), hasLength(1));
      expect(calls.where((c) => c.method == 'loadUrl').last.arguments, [
        tab.controller!.browserId,
        tab.url,
      ]);
      expect(hidden[tab.controller!.browserId], false);
    },
  );

  test(
    'five-minute idle sleep restores a fresh host and ignores retired callbacks',
    () async {
      final tab = await background('idle');
      final retired = tab.controller!;
      tab.lastUsed = DateTime.now().subtract(const Duration(minutes: 6));
      await browser.activate(
        browser.activeId,
      ); // Runs the same idle enforcement as the maintenance timer.
      expect(tab.phase, TabPhase.sleeping);
      expect(tab.controller, isNull);
      await browser.activate(tab.id);
      expect(tab.controller, isNot(same(retired)));
      expect(hidden[tab.controller!.browserId], false);
      retired.listener!.onUrlChanged!('https://example.test/stale');
      crash(retired);
      expect(tab.url, 'https://example.test/idle');
      expect(tab.loadError, isNull);
      expect(tab.phase, TabPhase.active);
    },
  );

  test(
    'activation during native retirement waits and cannot be marked sleeping afterwards',
    () async {
      final tab = await background('retiring');
      final retired = tab.controller!;
      final entered = Completer<void>(), release = Completer<void>();
      beforeCall = (call) async {
        if (call.method == 'close' && call.arguments == retired.browserId) {
          entered.complete();
          await release.future;
        }
      };
      final sleeping = browser.sleep(tab);
      await entered.future;
      final selection = browser.activate(tab.id);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final prematureCreate =
          calls.where((c) => c.method == 'create').length > 1;
      release.complete();
      await Future.wait([sleeping, selection]);
      expect(prematureCreate, false);
      expect(tab.phase, TabPhase.active);
      expect(tab.controller, isNotNull);
      expect(hidden[tab.controller!.browserId], false);
    },
  );

  test(
    'reload clears error UI, unhides healthy hosts and recreates failed hosts',
    () async {
      final tab = await background('reload');
      await browser.activate(tab.id);
      final healthy = tab.controller!;
      tab.loadError = 'Network error';
      calls.clear();
      await browser.reload();
      expect(tab.controller, same(healthy));
      expect(tab.loadError, isNull);
      expect(
        calls.where((c) => c.method == 'reload').single.arguments,
        healthy.browserId,
      );
      expect(hidden[healthy.browserId], false);
      crash(healthy);
      calls.clear();
      await browser.reload();
      expect(tab.controller, isNot(same(healthy)));
      expect(tab.rendererTerminated, false);
      expect(tab.loadError, isNull);
      expect(calls.where((c) => c.method == 'reload'), isEmpty);
      expect(calls.where((c) => c.method == 'loadUrl').single.arguments, [
        tab.controller!.browserId,
        tab.url,
      ]);
    },
  );

  test(
    'reload creates a host for a selected sleeping tab instead of doing nothing',
    () async {
      final tab = await background('sleep-reload');
      await browser.sleep(tab);
      browser.activeId = tab.id;
      await browser.reload();
      expect(tab.controller?.value, true);
      expect(tab.phase, TabPhase.active);
      expect(hidden[tab.controller!.browserId], false);
    },
  );

  test(
    'a stalled media snapshot is bounded and cannot stall tab selection forever',
    () async {
      final tab = await background('stalled');
      tab.lastUsed = DateTime.now().subtract(const Duration(minutes: 6));
      final release = Completer<void>();
      beforeCall = (call) async {
        if (call.method == 'evaluateJavascript') await release.future;
      };
      await browser
          .activate(browser.activeId)
          .timeout(const Duration(seconds: 3));
      expect(
        tab.controller,
        isNotNull,
        reason: 'Unknown media state must not be destroyed',
      );
      release.complete();
      await browser.activate(tab.id);
      expect(hidden[tab.controller!.browserId], false);
    },
  );

  test(
    'playing and newly selected tabs survive a pending sleep snapshot',
    () async {
      final tab = await background('protected');
      final controller = tab.controller!;
      tab.media = true;
      await browser.sleep(tab);
      expect(tab.controller, same(controller));
      tab.media = false;
      final entered = Completer<void>(), release = Completer<void>();
      beforeCall = (call) async {
        if (call.method == 'evaluateJavascript') {
          entered.complete();
          await release.future;
        }
      };
      final sleeping = browser.sleep(tab);
      await entered.future;
      await browser.activate(tab.id);
      release.complete();
      await sleeping;
      expect(tab.controller, same(controller));
      expect(tab.phase, TabPhase.active);
    },
  );

  test(
    'returning to a crashed background tab creates a replacement host',
    () async {
      final tab = await background('crashed');
      final retired = tab.controller!;
      crash(retired);
      await browser.activate(tab.id);
      expect(tab.controller, isNot(same(retired)));
      expect(tab.loadError, isNull);
      expect(tab.loading, true);
      expect(hidden[tab.controller!.browserId], false);
    },
  );
}
