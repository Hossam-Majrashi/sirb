import 'dart:convert';
import 'dart:io';
import '../../shared/models/device_info.dart';
import '../../shared/services/resource_service.dart';

class MacosResources implements ResourceService {
  @override
  bool get affinitySupported => false;
  @override
  bool get gpuSupported => false;
  @override
  Future<bool> get hardRamSupported async => false;
  @override
  Future<bool> isTouchpadNaturalScrolling() async {
    try {
      final res = await Process.run('defaults', [
        'read',
        '-g',
        'com.apple.swipescrolldirection',
      ]);
      if (res.exitCode == 0) {
        final out = res.stdout.toString().trim();
        if (out == '0' || out.toLowerCase() == 'false') return false;
        if (out == '1' || out.toLowerCase() == 'true') return true;
      }
    } catch (_) {}
    return true;
  }
  @override
  Future<DeviceInfo> detect() async {
    final memory = await Process.run('sysctl', ['-n', 'hw.memsize']);
    final graphics = await Process.run('system_profiler', [
      'SPDisplaysDataType',
      '-json',
    ]);
    final data = jsonDecode(graphics.stdout.toString()) as Map;
    final gpus = (data['SPDisplaysDataType'] as List)
        .map(
          (g) => GpuInfo(
            g['sppci_model'].toString(),
            g['sppci_bus'] == 'spdisplays_builtin' ? 'integrated' : 'discrete',
          ),
        )
        .toList();
    return DeviceInfo(
      cores: Platform.numberOfProcessors,
      ramBytes: int.parse(memory.stdout.toString().trim()),
      gpus: gpus,
    );
  }

  @override
  Future<void> applyCpu(int count) async {
    if (count != 0) throw UnsupportedError('macOS has no CPU affinity API');
  }

  @override
  Future<void> applyHardRam(int bytes) async {
    if (bytes != 0) {
      throw UnsupportedError('macOS has no process-tree hard memory limit');
    }
  }

  @override
  Future<void> applyGpu(String preference) async {
    if (preference != 'auto') {
      throw UnsupportedError('macOS manages GPU selection');
    }
  }

  @override
  Map<String, String> launchEnvironment(String gpu, bool acceleration) => {
    'SIRB_GPU_ACCELERATION': acceleration ? '1' : '0',
  };
  @override
  Future<ResourceUsage> usage() async {
    final result = await Process.run('ps', ['-axo', 'pid=,ppid=,rss=,%cpu=']);
    final rows = result.stdout
        .toString()
        .trim()
        .split('\n')
        .map((l) => l.trim().split(RegExp(r'\s+')))
        .where((r) => r.length == 4)
        .toList();
    final ids = <int>{pid};
    var changed = true;
    while (changed) {
      changed = false;
      for (final r in rows) {
        if (ids.contains(int.parse(r[1])) && ids.add(int.parse(r[0]))) {
          changed = true;
        }
      }
    }
    var bytes = 0;
    var cpu = 0.0;
    for (final r in rows) {
      if (ids.contains(int.parse(r[0]))) {
        bytes += int.parse(r[2]) * 1024;
        cpu += double.parse(r[3]);
      }
    }
    return ResourceUsage(bytes, cpu);
  }
}
