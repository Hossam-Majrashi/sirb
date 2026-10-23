import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sirb/core/l10n/app_localizations.dart';
import 'package:sirb/features/ads/services/ad_blocker.dart';
import 'package:sirb/features/home/services/browser_controller.dart';
import 'package:sirb/features/home/widgets/new_tab_page.dart';
import 'package:sirb/features/home/widgets/address_bar.dart';
import 'package:sirb/platform/linux/linux_resources.dart';
import 'package:sirb/screens/desktop/browser_screen.dart';
import 'package:sirb/features/settings/services/preferences_service.dart';
import 'package:sirb/shared/models/device_info.dart';
import 'package:sirb/shared/services/app_runtime.dart';
import 'package:sirb/shared/services/browser_engine.dart';
import 'package:sirb/shared/services/browser_store.dart';
import 'package:webview_cef/webview_cef.dart';

// Initialize the real controller outside FakeAsync (SQLite/Isolate.run), then
// let BrowserScreen mount without initializing the engine a second time.
class _ScreenBrowser extends BrowserController {
  _ScreenBrowser({
    required super.store,
    required super.engine,
    required super.preferences,
    required super.resources,
  });
  Future<bool> initializeEngine() => super.initialize();
  @override
  Future<bool> initialize({bool forceRestore = false}) async => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('webview_cef');
  final calls = <MethodCall>[];
  late Directory temp;
  late BrowserStore store;
  late BrowserController browser;
  var clipboard = '';
  var nextId = 100;

  setUp(() async {
    calls.clear();
    clipboard = 'one عربي';
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'create') {
        final id = nextId++;
        return [id, id];
      }
      if (call.method == 'hasNativeKeySupport') return true;
      return null;
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (call) async => false,
    );
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') return {'text': clipboard};
      if (call.method == 'Clipboard.hasStrings') {
        return {'value': clipboard.isNotEmpty};
      }
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    SharedPreferences.setMockInitialValues({'startup': 'new'});
    final preferences = PreferencesService(
      await SharedPreferences.getInstance(),
    );
    temp = await Directory.systemTemp.createTemp('sirb-editing-');
    store = await BrowserStore.open('${temp.path}/test.sqlite');
    browser = _ScreenBrowser(
      store: store,
      engine: BrowserEngine(
        profile: temp.path,
        blocker: AdBlocker(preferences),
      ),
      preferences: preferences,
      resources: LinuxResources(),
    );
    await (browser as _ScreenBrowser).initializeEngine();
  });

  tearDown(() async {
    await TestWidgetsFlutterBinding.instance.runAsync(() async {
      await browser.shutdown();
      browser.dispose();
      await store.close();
      await temp.delete(recursive: true);
    });
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      null,
    );
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }

  Future<void> launch(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BrowserScreen(
          browser: browser,
          runtime: AppRuntime(
            browser.preferences,
            browser.resources,
            browser.engine,
          ),
          device: const DeviceInfo(
            cores: 4,
            ramBytes: 8 * 1073741824,
            gpus: [],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 350));
    await settle(tester);
    await settle(tester);
    expect(find.byType(NewTabPage), findsOneWidget);
  }

  Future<void> chord(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool shift = false,
  }) async {
    final modifier = Platform.isMacOS
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(modifier);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(key);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(modifier);
    await tester.pump();
  }

  List<MethodCall> edits() => calls
      .where(
        (call) =>
            call.method == 'sirbControl' &&
            const {
              'copy',
              'cut',
              'paste',
              'selectAll',
              'undo',
              'redo',
            }.contains((call.arguments as List)[1]),
      )
      .toList();

  testWidgets('new-tab search and address editors own clipboard shortcuts', (
    tester,
  ) async {
    await launch(tester);
    final search = find.descendant(
      of: find.byType(NewTabPage),
      matching: find.byType(TextField),
    );
    await tester.tap(search);
    await chord(tester, LogicalKeyboardKey.keyV);
    expect(tester.widget<TextField>(search).controller!.text, clipboard);
    await chord(tester, LogicalKeyboardKey.keyA);
    await chord(tester, LogicalKeyboardKey.keyC);
    expect(clipboard, 'one عربي');
    await chord(tester, LogicalKeyboardKey.keyX);
    expect(tester.widget<TextField>(search).controller!.text, isEmpty);
    await chord(tester, LogicalKeyboardKey.keyV);
    expect(tester.widget<TextField>(search).controller!.text, 'one عربي');
    await chord(tester, LogicalKeyboardKey.keyL);
    await chord(tester, LogicalKeyboardKey.keyA);
    await chord(tester, LogicalKeyboardKey.keyV);
    final address = find.descendant(
      of: find.byType(AddressBar),
      matching: find.byType(TextField),
    );
    expect(
      tester
          .widget<EditableText>(
            find.descendant(of: address, matching: find.byType(EditableText)),
          )
          .controller
          .text,
      'one عربي',
    );
    expect(edits(), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Retry button and Ctrl+R recover a terminated page host', (
    tester,
  ) async {
    await launch(tester);
    await tester.runAsync(() => browser.navigate('https://example.test/retry'));
    await settle(tester);
    for (final keyboard in [false, true]) {
      final retired = browser.active!.controller!;
      retired.listener!.onConsoleMessage!(
        0,
        '__sirb__{"type":"renderCrash","error":"Renderer terminated","status":3,"code":9}',
        'sirb',
        0,
      );
      await tester.pump();
      expect(find.text('Retry'), findsOneWidget);
      await tester.runAsync(() async {
        if (keyboard) {
          await chord(tester, LogicalKeyboardKey.keyR);
        } else {
          await tester.tap(find.text('Retry'));
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await settle(tester);
      await settle(tester);
      expect(browser.active!.controller, isNot(same(retired)));
      expect(browser.active!.loadError, isNull);
      expect(find.text('Retry'), findsNothing);
      expect(find.byType(WebView), findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'web edits and context-menu paste issue one CEF command, no JS fallback',
    (tester) async {
      await launch(tester);
      await tester.runAsync(
        () => browser.navigate('https://example.test/editor'),
      );
      await settle(tester);
      // The mocked engine has no painted Texture to hit-test. Focus the real
      // WebView FocusNode, exactly as its native-surface pointer handler does.
      tester
          .widget<Focus>(
            find
                .descendant(
                  of: find.byType(WebView),
                  matching: find.byType(Focus),
                )
                .first,
          )
          .focusNode!
          .requestFocus();
      await tester.pump();
      expect(
        tester
            .widget<Focus>(
              find
                  .descendant(
                    of: find.byType(WebView),
                    matching: find.byType(Focus),
                  )
                  .first,
            )
            .focusNode!
            .hasPrimaryFocus,
        true,
      );
      for (final entry in {
        LogicalKeyboardKey.keyV: 'paste',
        LogicalKeyboardKey.keyC: 'copy',
        LogicalKeyboardKey.keyX: 'cut',
        LogicalKeyboardKey.keyA: 'selectAll',
        LogicalKeyboardKey.keyZ: 'undo',
        LogicalKeyboardKey.keyY: 'redo',
      }.entries) {
        calls.clear();
        await chord(tester, entry.key);
        await settle(tester);
        expect(edits().map((c) => (c.arguments as List)[1]), [entry.value]);
        expect(
          calls.where(
            (c) =>
                c.method == 'executeJavaScript' ||
                c.method == 'evaluateJavascript',
          ),
          isEmpty,
        );
      }
      calls.clear();
      await chord(tester, LogicalKeyboardKey.keyZ, shift: true);
      await settle(tester);
      expect(edits().map((c) => (c.arguments as List)[1]), ['redo']);

      for (final label in ['Paste', 'Cut', 'Copy', 'Select all']) {
        calls.clear();
        browser.onContextMenu!(browser.active!, {
          'editable': true,
          'selection': 'selected',
          'x': 10,
          'y': 10,
        });
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        await settle(tester);
        expect(edits(), hasLength(1));
        expect(
          calls.where(
            (c) =>
                c.method == 'executeJavaScript' ||
                c.method == 'evaluateJavascript',
          ),
          isEmpty,
        );
      }
      // Move ownership back to a Flutter editor while the web host is still live.
      calls.clear();
      await chord(tester, LogicalKeyboardKey.keyF);
      await chord(tester, LogicalKeyboardKey.keyV);
      expect(edits(), isEmpty);
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        clipboard,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('page menus reject background events and retired host actions', (
    tester,
  ) async {
    await launch(tester);
    await tester.runAsync(
      () => browser.navigate('https://example.test/editor'),
    );
    await settle(tester);
    final source = browser.active!;
    await tester.runAsync(() => browser.add());
    await settle(tester);
    browser.onContextMenu!(source, {'editable': true, 'x': 20, 'y': 20});
    await tester.pumpAndSettle();
    expect(find.text('Paste'), findsNothing);
    await tester.runAsync(() => browser.activate(source.id));
    await settle(tester);
    browser.onContextMenu!(source, {'editable': true, 'x': 20, 'y': 20});
    await tester.pumpAndSettle();
    expect(find.text('Paste'), findsOneWidget);
    final retired = source.controller!;
    retired.listener!.onConsoleMessage!(
      0,
      '__sirb__{"type":"renderCrash","error":"terminated","status":3,"code":9}',
      'sirb',
      0,
    );
    await tester.runAsync(() => browser.reload(tab: source));
    await settle(tester);
    expect(source.controller, isNot(same(retired)));
    calls.clear();
    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();
    expect(edits(), isEmpty, reason: 'do not paste into a replacement host');
    await tester.pumpWidget(const SizedBox());
  });
}
