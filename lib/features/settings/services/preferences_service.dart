import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PreferencesService extends ChangeNotifier {
  PreferencesService(this.storage);
  final SharedPreferences storage;
  String? get language => storage.getString('language');
  ThemeMode get theme => ThemeMode.values[storage.getInt('theme') ?? 0];
  bool get onboardingDone => storage.getBool('onboarding_done') ?? false;
  String get startup => storage.getString('startup') ?? 'new';
  int get cpu => storage.getInt('cpu') ?? 0;
  int get ramGb => storage.getInt('ram_gb') ?? 0;
  bool get hardRam => storage.getBool('hard_ram') ?? false;
  String get gpu => storage.getString('gpu') ?? 'auto';
  bool get acceleration => storage.getBool('acceleration') ?? true;
  bool get graphicsCompatibility =>
      storage.getBool('graphics_compatibility') ?? false;
  bool get gameMode => storage.getBool('game_mode') ?? false;

  // Adapter selection is a launch policy, not a live measurement. Never
  // override an explicit adapter choice or opt-out of hardware acceleration.
  String launchGpu({required bool selectablePair}) =>
      gameMode && acceleration && gpu == 'auto' && selectablePair
      ? 'discrete'
      : gpu;
  int get idleMinutes => storage.getInt('idle_minutes') ?? 10;
  int get liveLimit => storage.getInt('live_limit') ?? 20;
  // Preserve the saved preference while game mode suspends speculation.
  bool get preload => !gameMode && (storage.getBool('preload') ?? true);
  int get preloadLimit => storage.getInt('preload_limit') ?? 2;
  bool get blocking => storage.getBool('blocking') ?? true;
  List<String> get allowlist => storage.getStringList('allowlist') ?? [];
  bool get mouseNavigation => storage.getBool('mouse_navigation') ?? true;
  Future<void> set(String key, Object value) async {
    if (value is bool) {
      await storage.setBool(key, value);
    } else if (value is int) {
      await storage.setInt(key, value);
    } else if (value is String) {
      await storage.setString(key, value);
    } else if (value is List<String>) {
      await storage.setStringList(key, value);
    }
    notifyListeners();
  }

  Map<String, Object> get resourceSettings => {
    'cpu': cpu,
    'ramGb': ramGb,
    'hardRam': hardRam,
    'gpu': gpu,
    'acceleration': acceleration,
    'graphicsCompatibility': graphicsCompatibility,
    'gameMode': gameMode,
  };
  String get resourceFingerprint => jsonEncode(resourceSettings);
}
