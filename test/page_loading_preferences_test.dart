import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sirb/features/ads/services/ad_blocker.dart';
import 'package:sirb/features/home/services/page_features.dart';
import 'package:sirb/features/settings/services/preferences_service.dart';
import 'package:sirb/shared/services/browser_engine.dart';
import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PreferencesService preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = PreferencesService(await SharedPreferences.getInstance());
  });
  tearDown(() => preferences.dispose());

  test('focus loading and original titles default on and persist', () async {
    expect(preferences.focusLoading, true);
    expect(preferences.youtubeOriginalTitles, true);
    expect(preferences.preload, false);
    await preferences.set('focus_loading', false);
    await preferences.set('youtube_original_titles', false);
    final restored = PreferencesService(await SharedPreferences.getInstance());
    expect(restored.focusLoading, false);
    expect(restored.youtubeOriginalTitles, false);
    restored.dispose();
  });

  test(
    'focus and game modes preserve the saved speculative preload choice',
    () async {
      final fingerprint = preferences.resourceFingerprint;
      await preferences.set('preload', true);
      await preferences.set('focus_loading', false);
      expect(preferences.preload, true);
      await preferences.set('focus_loading', true);
      expect(preferences.preload, false);
      expect(preferences.resourceFingerprint, fingerprint);
      expect(preferences.storage.getBool('preload'), true);
      await preferences.set('game_mode', true);
      await preferences.set('focus_loading', false);
      expect(preferences.preload, false);
      await preferences.set('game_mode', false);
      expect(preferences.preload, true);
      await preferences.set('preload', false);
      await preferences.set('focus_loading', true);
      await preferences.set('focus_loading', false);
      expect(preferences.preload, false);
    },
  );

  test(
    'page features are independent of ad blocking on all desktop hosts',
    () async {
      Object? configuration;
      const channel = MethodChannel('webview_cef');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'sirbConfigure') configuration = call.arguments;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await preferences.set('blocking', false);
      await BrowserEngine(
        profile: '/test',
        blocker: AdBlocker(preferences),
      ).configure();
      final script = (configuration as Map)['script'] as String;
      expect(script, contains('window.__sirbFocusLoading=true;'));
      expect(script, contains('window.__sirbOriginalTitles=true;'));
      expect(script, contains('window.__sirbPreload=false;'));
      expect(script, contains('/oembed'));
      final updated = pageFeatures(
        focusLoading: false,
        youtubeOriginalTitles: false,
      );
      expect(updated, contains('window.__sirbFocusLoading=false;'));
      expect(updated, contains('window.__sirbOriginalTitles=false;'));
      expect(updated, contains('__sirbFlushYoutubeRequests?.()'));
      expect(updated, contains('__sirbUpdateOriginalTitles?.()'));
    },
  );
}
