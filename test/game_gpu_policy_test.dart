import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sirb/features/settings/services/preferences_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PreferencesService preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = PreferencesService(await SharedPreferences.getInstance());
  });

  tearDown(() => preferences.dispose());

  test(
    'automatic game launch prefers discrete without rewriting saved GPU',
    () async {
      final fingerprint = preferences.resourceFingerprint;
      expect(preferences.launchGpu(selectablePair: true), 'auto');
      await preferences.set('game_mode', true);
      expect(preferences.resourceFingerprint, isNot(fingerprint));
      expect(preferences.launchGpu(selectablePair: true), 'discrete');
      expect(preferences.gpu, 'auto');
      expect(preferences.cpu, 0);
      expect(preferences.ramGb, 0);
      expect(preferences.hardRam, false);
      await preferences.set('game_mode', false);
      expect(preferences.launchGpu(selectablePair: true), 'auto');
    },
  );

  test(
    'single GPU and OS-managed platforms keep automatic selection',
    () async {
      await preferences.set('game_mode', true);
      expect(preferences.launchGpu(selectablePair: false), 'auto');
    },
  );

  test(
    'explicit integrated and discrete preferences survive game mode',
    () async {
      await preferences.set('game_mode', true);
      for (final gpu in ['integrated', 'discrete']) {
        await preferences.set('gpu', gpu);
        expect(preferences.launchGpu(selectablePair: true), gpu);
        expect(preferences.launchGpu(selectablePair: false), gpu);
        expect(preferences.gpu, gpu);
      }
    },
  );

  test(
    'software rendering never implicitly requests the discrete GPU',
    () async {
      await preferences.set('game_mode', true);
      await preferences.set('acceleration', false);
      expect(preferences.launchGpu(selectablePair: true), 'auto');
      await preferences.set('acceleration', true);
      expect(preferences.launchGpu(selectablePair: true), 'discrete');
    },
  );
}
