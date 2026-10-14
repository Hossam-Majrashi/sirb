import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'core/l10n/app_localizations.dart';
import 'core/theme/app_theme.dart';
import 'features/ads/services/ad_blocker.dart';
import 'features/home/services/browser_controller.dart';
import 'features/settings/services/preferences_service.dart';
import 'platform/linux/linux_resources.dart';
import 'platform/macos/macos_resources.dart';
import 'platform/windows/windows_resources.dart';
import 'screens/desktop/browser_screen.dart';
import 'screens/desktop/onboarding_screen.dart';
import 'shared/models/device_info.dart';
import 'shared/services/app_runtime.dart';
import 'shared/services/browser_engine.dart';
import 'shared/services/browser_store.dart';
import 'shared/services/resource_service.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (arguments.contains('--trace-input')) {
    HardwareKeyboard.instance.addHandler((event) {
      stderr.writeln(
        'Sirb Flutter key ${event.runtimeType} ${event.logicalKey.keyLabel} ctrl=${HardwareKeyboard.instance.isControlPressed}',
      );
      return false;
    });
  }
  final parent = arguments
      .where((a) => a.startsWith('--wait-parent='))
      .firstOrNull;
  if (parent != null) {
    await AppRuntime.waitForParent(int.parse(parent.split('=').last));
  }
  final preferences = PreferencesService(await SharedPreferences.getInstance());
  if (arguments.contains('--stress')) {
    await preferences.set('onboarding_done', true);
  }
  final support = await getApplicationSupportDirectory();
  await support.create(recursive: true);
  final ResourceService resources = Platform.isLinux
      ? LinuxResources()
      : Platform.isWindows
      ? WindowsResources()
      : MacosResources();
  final device = await resources.detect();
  final engine = BrowserEngine(
    profile: path.join(support.path, 'chromium'),
    blocker: AdBlocker(preferences),
  );
  await Directory(engine.profile).create(recursive: true);
  final runtime = AppRuntime(preferences, resources, engine);
  String? startupError;
  try {
    await runtime.prepare(arguments: arguments);
  } catch (e) {
    startupError = e.toString();
  }
  final store = await BrowserStore.open(path.join(support.path, 'sirb.sqlite'));
  if (startupError != null) {
    store.recordErrorLog(
      type: 'system',
      message: startupError,
      details: 'Startup error during runtime.prepare',
    );
  }
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    store.recordErrorLog(
      type: 'flutter',
      message: details.exceptionAsString(),
      details: details.stack?.toString(),
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    store.recordErrorLog(
      type: 'flutter',
      message: error.toString(),
      details: stack.toString(),
    );
    return false;
  };
  final browser = BrowserController(
    store: store,
    engine: engine,
    preferences: preferences,
    resources: resources,
  )..error = startupError;
  runtime.browser = browser;
  await windowManager.ensureInitialized();
  await windowManager.setMinimumSize(const Size(800, 600));
  await windowManager.setPreventClose(true);
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(1280, 800),
      minimumSize: Size(800, 600),
      center: true,
    ),
  );
  runApp(
    SirbApp(
      preferences: preferences,
      browser: browser,
      runtime: runtime,
      device: device,
      arguments: arguments,
    ),
  );
  await windowManager.show();
  await windowManager.focus();
}

class SirbApp extends StatelessWidget {
  const SirbApp({
    super.key,
    required this.preferences,
    required this.browser,
    required this.runtime,
    required this.device,
    this.arguments = const [],
  });
  final PreferencesService preferences;
  final BrowserController browser;
  final AppRuntime runtime;
  final DeviceInfo device;
  final List<String> arguments;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: preferences,
    builder: (context, child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      locale: preferences.language == null
          ? null
          : Locale(preferences.language!),
      localeResolutionCallback: (locale, supported) =>
          locale != null && ['ar', 'en'].contains(locale.languageCode)
          ? Locale(locale.languageCode)
          : const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.build(Brightness.light),
      darkTheme: AppTheme.build(Brightness.dark),
      themeMode: preferences.theme,
      home: preferences.onboardingDone
          ? BrowserScreen(
              browser: browser,
              runtime: runtime,
              device: device,
              arguments: arguments,
            )
          : OnboardingScreen(preferences: preferences),
      builder: (context, child) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        final title = AppLocalizations.of(context).appName;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          windowManager.setTitle(title);
          browser.applyTheme(dark ? 'dark' : 'light');
        });
        return child!;
      },
    ),
  );
}
