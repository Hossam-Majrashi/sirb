import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:window_manager/window_manager.dart';
import '../../features/home/services/browser_controller.dart';
import '../../features/settings/services/preferences_service.dart';
import 'browser_engine.dart';
import 'resource_service.dart';

class AppRuntime {
  AppRuntime(this.preferences, this.resources, this.engine);
  final PreferencesService preferences;
  final ResourceService resources;
  final BrowserEngine engine;
  BrowserController? browser;
  bool closing = false;
  String get launchGpu =>
      preferences.launchGpu(selectablePair: resources.gpuSupported);
  static Future<void> waitForParent(int parent) async {
    if (Platform.isWindows) {
      final library = DynamicLibrary.open('kernel32.dll');
      final handle = library
          .lookupFunction<
            Pointer<Void> Function(Uint32, Int32, Uint32),
            Pointer<Void> Function(int, int, int)
          >('OpenProcess')(0x100000, 0, parent);
      if (handle != nullptr) {
        library.lookupFunction<
          Uint32 Function(Pointer<Void>, Uint32),
          int Function(Pointer<Void>, int)
        >('WaitForSingleObject')(handle, 0xffffffff);
        library.lookupFunction<
          Int32 Function(Pointer<Void>),
          int Function(Pointer<Void>)
        >('CloseHandle')(handle);
      }
    } else {
      final library = Platform.isMacOS
          ? DynamicLibrary.process()
          : DynamicLibrary.open('libc.so.6');
      final exists = library
          .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
            'kill',
          );
      while (exists(parent, 0) == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  }

  void setEnvironment(String key, String value) {
    if (Platform.isWindows) {
      final k = key.toNativeUtf16(), v = value.toNativeUtf16();
      try {
        final set = DynamicLibrary.open('kernel32.dll')
            .lookupFunction<
              Int32 Function(Pointer<Utf16>, Pointer<Utf16>),
              int Function(Pointer<Utf16>, Pointer<Utf16>)
            >('SetEnvironmentVariableW');
        if (set(k, v) == 0) throw StateError('SetEnvironmentVariableW failed');
      } finally {
        calloc.free(k);
        calloc.free(v);
      }
    } else {
      final k = key.toNativeUtf8(), v = value.toNativeUtf8();
      try {
        final libc = Platform.isMacOS
            ? DynamicLibrary.process()
            : DynamicLibrary.open('libc.so.6');
        final set = libc
            .lookupFunction<
              Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Int32),
              int Function(Pointer<Utf8>, Pointer<Utf8>, int)
            >('setenv');
        if (set(k, v, 1) != 0) throw StateError('setenv failed');
      } finally {
        calloc.free(k);
        calloc.free(v);
      }
    }
  }

  Future<void> prepare({List<String> arguments = const []}) async {
    final env = resources.launchEnvironment(
      launchGpu,
      preferences.acceleration,
    );
    final gpuChange =
        Platform.isLinux &&
        launchGpu != 'auto' &&
        env.entries.any(
          (e) =>
              e.key != 'SIRB_GPU_ACCELERATION' &&
              Platform.environment[e.key] != e.value,
        );
    final scopeNeeded =
        Platform.isLinux &&
        preferences.hardRam &&
        preferences.ramGb > 0 &&
        Platform.environment['SIRB_MEMORY_SCOPE'] !=
            preferences.ramGb.toString();
    if (gpuChange || scopeNeeded) {
      await _spawn(restore: false, startupArguments: arguments);
      exit(0);
    }
    for (final entry in env.entries) {
      setEnvironment(entry.key, entry.value);
    }
    setEnvironment(
      'SIRB_WEBGPU_ENABLED',
      preferences.graphicsCompatibility ? '0' : '1',
    );
    // CEF children start after prepare; Windows reads this per-executable
    // preference when creating their graphics devices. Flutter may already
    // have a device, so the settings UI still requires a full restart.
    if (Platform.isWindows) await resources.applyGpu(launchGpu);
    await resources.applyCpu(resources.affinitySupported ? preferences.cpu : 0);
    if (preferences.hardRam &&
        preferences.ramGb > 0 &&
        await resources.hardRamSupported) {
      await resources.applyHardRam(preferences.ramGb * 1073741824);
    }
    if (preferences.storage.getBool('clear_cache_next') ?? false) {
      final cache = Directory('${engine.profile}/Default/Cache');
      if (cache.existsSync()) await cache.delete(recursive: true);
      for (final folder in [
        'Code Cache',
        'GPUCache',
        'Service Worker/CacheStorage',
      ]) {
        final d = Directory('${engine.profile}/Default/$folder');
        if (d.existsSync()) await d.delete(recursive: true);
      }
      await preferences.set('clear_cache_next', false);
    }
  }

  Future<void> _spawn({
    required bool restore,
    List<String> startupArguments = const [],
  }) async {
    final env = Map<String, String>.from(Platform.environment)
      ..remove('DRI_PRIME')
      ..remove('__NV_PRIME_RENDER_OFFLOAD')
      ..remove('__GLX_VENDOR_LIBRARY_NAME')
      ..remove('__VK_LAYER_NV_optimus')
      ..remove('SIRB_CEF_SWITCHES')
      ..addAll(resources.launchEnvironment(launchGpu, preferences.acceleration))
      ..['SIRB_WEBGPU_ENABLED'] = preferences.graphicsCompatibility ? '0' : '1';
    if (restore) await preferences.set('force_restore', true);
    if (Platform.isWindows) await resources.applyGpu(launchGpu);
    String executable =
        Platform.environment['APPIMAGE'] ?? Platform.resolvedExecutable;
    if (Platform.isLinux && Platform.environment['APPIMAGE'] == null) {
      final launcher = File('${File(executable).parent.path}/launcher');
      if (launcher.existsSync()) {
        executable = launcher.path;
      }
    }
    final arguments = [
      '--wait-parent=$pid',
      // Do not carry an old wait-parent into another early GPU/scope relaunch.
      ...startupArguments.where((a) => !a.startsWith('--wait-parent=')),
    ];
    if (Platform.isWindows) {
      final command = '"$executable" ${arguments.join(' ')}'.replaceAll(
        "'",
        "''",
      );
      final workingDirectory = File(
        executable,
      ).parent.path.replaceAll("'", "''");
      final process = await Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        "\$r=Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{CommandLine='$command';CurrentDirectory='$workingDirectory'}; exit \$r.ReturnValue",
      ]);
      if (process.exitCode != 0) {
        throw StateError('Win32_Process.Create failed: ${process.stderr}');
      }
      return;
    }
    if (Platform.isLinux && preferences.hardRam && preferences.ramGb > 0) {
      if (!await resources.hardRamSupported) {
        throw UnsupportedError('systemd user memory delegation is unavailable');
      }
      env['SIRB_MEMORY_SCOPE'] = preferences.ramGb.toString();
      await Process.start(
        'systemd-run',
        [
          '--user',
          '--scope',
          '-p',
          'MemoryMax=${preferences.ramGb * 1073741824}',
          executable,
          ...arguments,
        ],
        environment: env,
        mode: ProcessStartMode.detached,
      );
    } else if (Platform.environment.containsKey('FLATPAK_ID')) {
      await Process.start(
        '/app/bin/sirb',
        arguments,
        environment: env,
        mode: ProcessStartMode.detached,
      );
    } else if (Platform.isLinux &&
        Platform.environment.containsKey('SIRB_MEMORY_SCOPE')) {
      env.remove('SIRB_MEMORY_SCOPE');
      await Process.start(
        'systemd-run',
        [
          '--user',
          '--scope',
          '-p',
          'MemoryMax=infinity',
          executable,
          ...arguments,
        ],
        environment: env,
        mode: ProcessStartMode.detached,
      );
    } else {
      env.remove('SIRB_MEMORY_SCOPE');
      await Process.start(
        executable,
        arguments,
        environment: env,
        workingDirectory: File(executable).parent.path,
        mode: ProcessStartMode.detached,
      );
    }
  }

  Future<void> restart({bool clearCache = false}) async {
    if (closing) return;
    if (clearCache) await preferences.set('clear_cache_next', true);
    if (browser != null) {
      await browser!.store.saveSession(browser!.tabs, browser!.activeId);
    }
    // The child waits for this PID to exit. Spawn failures leave the current
    // browser intact, and the child cannot race the persistent-profile lock.
    await _spawn(restore: true);
    closing = true;
    await browser?.shutdown();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await engine.shutdown();
    await windowManager.destroy();
    exit(0);
  }

  Future<void> close() async {
    if (closing) return;
    closing = true;
    try {
      await browser?.shutdown();
      await engine.shutdown();
      await windowManager.destroy();
      exit(0);
    } catch (_) {
      // A refused CEF shutdown must stay safe and retryable, not permanently
      // swallow subsequent window-close requests. The global error hook logs it.
      closing = false;
      rethrow;
    }
  }
}
