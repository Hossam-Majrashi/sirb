import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import '../../shared/models/device_info.dart';
import '../../shared/services/resource_service.dart';

final class _BasicLimit extends Struct {
  @Int64()
  external int processTime;
  @Int64()
  external int jobTime;
  @Uint32()
  external int flags;
  @UintPtr()
  external int minimumWorkingSet;
  @UintPtr()
  external int maximumWorkingSet;
  @Uint32()
  external int activeProcesses;
  @UintPtr()
  external int affinity;
  @Uint32()
  external int priority;
  @Uint32()
  external int scheduling;
}

final class _IoCounters extends Struct {
  @Uint64()
  external int readOperations;
  @Uint64()
  external int writeOperations;
  @Uint64()
  external int otherOperations;
  @Uint64()
  external int readBytes;
  @Uint64()
  external int writeBytes;
  @Uint64()
  external int otherBytes;
}

final class _ExtendedLimit extends Struct {
  external _BasicLimit basic;
  external _IoCounters io;
  @UintPtr()
  external int processMemory;
  @UintPtr()
  external int jobMemory;
  @UintPtr()
  external int peakProcessMemory;
  @UintPtr()
  external int peakJobMemory;
}

class WindowsResources implements ResourceService {
  final _kernel = DynamicLibrary.open('kernel32.dll');
  Pointer<Void>? _job;
  int _affinity = 0, _ram = 0;
  List<GpuInfo> _gpus = [];
  @override
  bool get affinitySupported => Platform.numberOfProcessors <= 64;
  @override
  bool get gpuSupported =>
      _gpus.any((g) => g.kind == 'integrated') &&
      _gpus.any((g) => g.kind == 'discrete');
  @override
  Future<bool> get hardRamSupported async => true;
  @override
  Future<bool> isTouchpadNaturalScrolling() async {
    try {
      final res = await Process.run('reg.exe', [
        'query',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\PrecisionTouchPad',
        '/v',
        'ScrollDirection',
      ]);
      if (res.exitCode == 0) {
        final out = res.stdout.toString();
        if (out.contains('0x0') || RegExp(r'\b0\b').hasMatch(out)) return false;
        if (out.contains('0x1') || RegExp(r'\b1\b').hasMatch(out)) return true;
      }
    } catch (_) {}
    return true;
  }
  Future<dynamic> _powershell(String script) async {
    final result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      script,
    ]);
    if (result.exitCode != 0) throw StateError(result.stderr.toString());
    return jsonDecode(result.stdout.toString().trim());
  }

  @override
  Future<DeviceInfo> detect() async {
    final data =
        await _powershell(
              r'$ram=(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory; $gpu=@(Get-CimInstance Win32_VideoController | Select-Object Name,AdapterRAM); @{ram=$ram; gpu=$gpu} | ConvertTo-Json -Depth 4',
            )
            as Map;
    _gpus = (data['gpu'] as List).map((g) {
      final name = g['Name'].toString(),
          lower = g['Name'].toString().toLowerCase();
      final kind = lower.contains('intel') || lower.contains('radeon graphics')
          ? 'integrated'
          : lower.contains('nvidia') || lower.contains('radeon rx')
          ? 'discrete'
          : 'unknown';
      return GpuInfo(name, kind);
    }).toList();
    return DeviceInfo(
      cores: Platform.numberOfProcessors,
      ramBytes: (data['ram'] as num).toInt(),
      gpus: _gpus,
    );
  }

  Future<void> _limits() async {
    final current = _kernel
        .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
          'GetCurrentProcess',
        )();
    if (_job == null) {
      _job = _kernel
          .lookupFunction<
            Pointer<Void> Function(Pointer<Void>, Pointer<Utf16>),
            Pointer<Void> Function(Pointer<Void>, Pointer<Utf16>)
          >('CreateJobObjectW')(nullptr, nullptr);
      if (_job == nullptr ||
          _kernel.lookupFunction<
                Int32 Function(Pointer<Void>, Pointer<Void>),
                int Function(Pointer<Void>, Pointer<Void>)
              >('AssignProcessToJobObject')(_job!, current) ==
              0) {
        throw StateError('AssignProcessToJobObject failed');
      }
    }
    final limits = calloc<_ExtendedLimit>();
    try {
      if (_affinity != 0) {
        limits.ref.basic.flags |= 0x10;
        limits.ref.basic.affinity = _affinity;
      }
      if (_ram != 0) {
        limits.ref.basic.flags |= 0x200;
        limits.ref.jobMemory = _ram;
      }
      final set = _kernel
          .lookupFunction<
            Int32 Function(Pointer<Void>, Int32, Pointer<Void>, Uint32),
            int Function(Pointer<Void>, int, Pointer<Void>, int)
          >('SetInformationJobObject');
      if (set(_job!, 9, limits.cast(), sizeOf<_ExtendedLimit>()) == 0) {
        throw StateError('SetInformationJobObject failed');
      }
    } finally {
      calloc.free(limits);
    }
  }

  @override
  Future<void> applyCpu(int count) async {
    if (count == 0) return;
    if (!affinitySupported) {
      throw UnsupportedError(
        'Processor groups require a different affinity policy',
      );
    }
    final process = _kernel
        .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
          'GetCurrentProcess',
        )();
    final allowed = calloc<UintPtr>(), system = calloc<UintPtr>();
    try {
      final get = _kernel
          .lookupFunction<
            Int32 Function(Pointer<Void>, Pointer<UintPtr>, Pointer<UintPtr>),
            int Function(Pointer<Void>, Pointer<UintPtr>, Pointer<UintPtr>)
          >('GetProcessAffinityMask');
      if (get(process, allowed, system) == 0) {
        throw StateError('GetProcessAffinityMask failed');
      }
      _affinity = 0;
      var selected = 0;
      for (var i = 0; i < 64 && selected < count; i++) {
        if ((system.value & (1 << i)) != 0) {
          _affinity |= 1 << i;
          selected++;
        }
      }
      final set = _kernel
          .lookupFunction<
            Int32 Function(Pointer<Void>, UintPtr),
            int Function(Pointer<Void>, int)
          >('SetProcessAffinityMask');
      if (set(process, _affinity) == 0) {
        throw StateError('SetProcessAffinityMask failed');
      }
      await _limits();
    } finally {
      calloc.free(allowed);
      calloc.free(system);
    }
  }

  @override
  Future<void> applyHardRam(int bytes) async {
    _ram = bytes;
    if (bytes > 0) await _limits();
  }

  @override
  Future<void> applyGpu(String preference) async {
    final value = preference == 'discrete'
        ? 2
        : preference == 'integrated'
        ? 1
        : 0;
    final result = await Process.run('reg.exe', [
      'add',
      r'HKCU\Software\Microsoft\DirectX\UserGpuPreferences',
      '/v',
      Platform.resolvedExecutable,
      '/t',
      'REG_SZ',
      '/d',
      'GpuPreference=$value;',
      '/f',
    ]);
    if (result.exitCode != 0) throw StateError(result.stderr.toString());
  }

  @override
  Map<String, String> launchEnvironment(String gpu, bool acceleration) => {
    'SIRB_GPU_ACCELERATION': acceleration ? '1' : '0',
  };
  DateTime? _previous;
  double _cpu = 0;
  @override
  Future<ResourceUsage> usage() async {
    final data =
        await _powershell(
              '\$root=$pid; \$all=@(Get-CimInstance Win32_Process); \$ids=New-Object System.Collections.Generic.HashSet[int]; [void]\$ids.Add(\$root); do { \$change=\$false; foreach(\$p in \$all) { if(\$ids.Contains([int]\$p.ParentProcessId)) { if(\$ids.Add([int]\$p.ProcessId)) { \$change=\$true } } } } while(\$change); \$ram=0; \$cpu=0; foreach(\$i in \$ids) { \$p=Get-Process -Id \$i -ErrorAction SilentlyContinue; \$ram+=\$p.WorkingSet64; \$cpu+=\$p.CPU }; @{ram=\$ram;cpu=\$cpu}|ConvertTo-Json',
            )
            as Map;
    final now = DateTime.now(), cpu = (data['cpu'] as num).toDouble();
    final elapsed = _previous == null
        ? 0
        : now.difference(_previous!).inMilliseconds / 1000;
    final percent = elapsed > 0
        ? (cpu - _cpu).clamp(0, double.infinity) / elapsed * 100
        : 0.0;
    _cpu = cpu;
    _previous = now;
    return ResourceUsage((data['ram'] as num).toInt(), percent);
  }
}
