import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import '../../shared/models/device_info.dart';
import '../../shared/services/resource_service.dart';
import 'linux_gpu_environment.dart';

class LinuxResources implements ResourceService {
  final _libc = DynamicLibrary.open('libc.so.6');
  List<GpuInfo> _gpus = [];
  @override
  bool get affinitySupported => true;
  @override
  bool get gpuSupported =>
      _gpus.any((g) => g.kind == 'integrated') &&
      _gpus.any((g) => g.kind == 'discrete');
  @override
  Future<bool> get hardRamSupported async {
    if (Platform.environment.containsKey('FLATPAK_ID')) return false;
    if (!File('/sys/fs/cgroup/cgroup.controllers').existsSync()) return false;
    final check = await Process.run('systemd-run', [
      '--user',
      '--scope',
      '--quiet',
      '-p',
      'MemoryMax=1G',
      'true',
    ]);
    return check.exitCode == 0;
  }

  @override
  Future<bool> isTouchpadNaturalScrolling() async {
    try {
      final res = await Process.run('gsettings', [
        'get',
        'org.gnome.desktop.peripherals.touchpad',
        'natural-scroll',
      ]);
      if (res.exitCode == 0) {
        final out = res.stdout.toString().trim();
        if (out == 'true') return true;
        if (out == 'false') return false;
      }
    } catch (_) {}
    try {
      final res = await Process.run('kreadconfig5', [
        '--file',
        'kcminputrc',
        '--group',
        'Touchpad',
        '--key',
        'NaturalScroll',
      ]);
      if (res.exitCode == 0) {
        final out = res.stdout.toString().trim();
        if (out == 'true') return true;
        if (out == 'false') return false;
      }
    } catch (_) {}
    try {
      final res = await Process.run('kreadconfig6', [
        '--file',
        'kcminputrc',
        '--group',
        'Touchpad',
        '--key',
        'NaturalScroll',
      ]);
      if (res.exitCode == 0) {
        final out = res.stdout.toString().trim();
        if (out == 'true') return true;
        if (out == 'false') return false;
      }
    } catch (_) {}
    return true;
  }

  @override
  Future<DeviceInfo> detect() async {
    final mem = await File('/proc/meminfo').readAsString();
    final kb = int.parse(
      RegExp(r'MemTotal:\s+(\d+)').firstMatch(mem)!.group(1)!,
    );
    _gpus = [];
    final drm = Directory('/sys/class/drm');
    if (drm.existsSync()) {
      final renderNodes = <String, String>{};
      for (final entry in drm.listSync()) {
        if (RegExp(r'/renderD\d+$').hasMatch(entry.path)) {
          final dev = Directory('${entry.path}/device');
          if (dev.existsSync()) {
            try {
              final target = await dev.resolveSymbolicLinks();
              final nodeName = entry.path.split('/').last;
              renderNodes[target] = '/dev/dri/$nodeName';
            } catch (_) {}
          }
        }
      }
      for (final card in drm.listSync().where(
        (e) => RegExp(r'/card\d+$').hasMatch(e.path),
      )) {
        final device = Directory('${card.path}/device');
        if (!device.existsSync()) continue;
        final vendor = (await File(
          '${device.path}/vendor',
        ).readAsString()).trim();
        final id = (await File('${device.path}/device').readAsString()).trim();
        final resolved = await device.resolveSymbolicLinks();
        final pci = resolved.split('/').last;
        String name = '$vendor:$id';
        try {
          final r = await Process.run('lspci', ['-s', pci]);
          if (r.exitCode == 0 && (r.stdout as String).trim().isNotEmpty) {
            name = (r.stdout as String).trim();
          }
        } on ProcessException {
          /* sysfs identification remains available */
        }
        if (vendor == '0x10de' && !name.toLowerCase().contains('nvidia')) {
          name = 'NVIDIA ($name)';
        }
        String kind = 'unknown';
        if (vendor == '0x8086') kind = 'integrated';
        if (vendor == '0x10de') kind = 'discrete';
        if (vendor == '0x1002') {
          final vram = File('${device.path}/mem_info_vram_total');
          if (vram.existsSync() &&
              int.tryParse((await vram.readAsString()).trim()) != null) {
            kind = int.parse((await vram.readAsString()).trim()) > 1073741824
                ? 'discrete'
                : 'integrated';
          }
        }
        _gpus.add(
          GpuInfo(
            name,
            kind,
            prime: 'pci-${pci.replaceAll(':', '_').replaceAll('.', '_')}',
            renderNode: renderNodes[resolved],
          ),
        );
      }
    }
    return DeviceInfo(
      cores: (await _permittedCpus()).length,
      ramBytes: kb * 1024,
      gpus: _gpus,
    );
  }

  Future<List<int>> _permittedCpus() async {
    final cgroup = (await File(
      '/proc/self/cgroup',
    ).readAsString()).split('\n').where((l) => l.startsWith('0::')).firstOrNull;
    final effective = cgroup == null
        ? null
        : File('/sys/fs/cgroup${cgroup.substring(3)}/cpuset.cpus.effective');
    final text = effective != null && effective.existsSync()
        ? (await effective.readAsString()).trim()
        : (await File('/sys/devices/system/cpu/online').readAsString()).trim();
    final cpus = <int>[];
    for (final part in text.split(',')) {
      final range = part.split('-').map(int.parse).toList();
      for (var n = range.first; n <= range.last; n++) {
        cpus.add(n);
      }
    }
    return cpus;
  }

  @override
  Future<void> applyCpu(int count) async {
    final get = _libc
        .lookupFunction<
          Int32 Function(Int32, Size, Pointer<Uint8>),
          int Function(int, int, Pointer<Uint8>)
        >('sched_getaffinity');
    final set = _libc
        .lookupFunction<
          Int32 Function(Int32, Size, Pointer<Uint8>),
          int Function(int, int, Pointer<Uint8>)
        >('sched_setaffinity');
    final allowed = calloc<Uint8>(128), mask = calloc<Uint8>(128);
    try {
      if (get(pid, 128, allowed) != 0) {
        throw StateError('sched_getaffinity failed');
      }
      final permitted = await _permittedCpus();
      var selected = 0;
      for (final cpu in permitted) {
        if (cpu >= 1024 || (count > 0 && selected >= count)) break;
        mask[cpu ~/ 8] |= 1 << (cpu % 8);
        selected++;
      }
      if (selected == 0) throw StateError('No permitted CPU');
      // sched_setaffinity targets threads, not just the process leader.
      for (final task in Directory('/proc/$pid/task').listSync()) {
        final tid = int.parse(task.path.split('/').last);
        if (set(tid, 128, mask) != 0 && Directory(task.path).existsSync()) {
          throw StateError('sched_setaffinity failed for $tid');
        }
      }
    } finally {
      calloc.free(allowed);
      calloc.free(mask);
    }
  }

  @override
  Future<void> applyHardRam(int bytes) async {
    if (bytes == 0) return;
    // This operation runs in the early relaunch path; the new executable inherits the scope.
    final cgroup = (await File('/proc/self/cgroup').readAsString())
        .split('\n')
        .firstWhere((l) => l.startsWith('0::'))
        .substring(3);
    final file = File('/sys/fs/cgroup$cgroup/memory.max');
    if (!file.existsSync() ||
        (await file.readAsString()).trim() != bytes.toString()) {
      throw StateError('MemoryMax requires a delegated systemd user scope');
    }
  }

  @override
  Future<void> applyGpu(String preference) async {
    if (preference != 'auto' && !gpuSupported) {
      throw UnsupportedError('No selectable integrated/discrete adapter pair');
    }
  }

  @override
  Map<String, String> launchEnvironment(String gpu, bool acceleration) =>
      linuxGpuEnvironment(
        adapter: gpu != 'auto' && gpuSupported
            ? _gpus.firstWhere((g) => g.kind == gpu)
            : null,
        acceleration: acceleration,
        inherited: Platform.environment,
      );

  DateTime? _previous;
  int _ticks = 0;
  @override
  Future<ResourceUsage> usage() async {
    final stats = <int, ({int parent, int rss, int ticks})>{};
    for (final entry in Directory('/proc').listSync()) {
      final id = int.tryParse(entry.path.split('/').last);
      if (id == null) continue;
      try {
        final stat = await File('${entry.path}/stat').readAsString();
        final s = stat.substring(stat.lastIndexOf(')') + 2).split(' ');
        final rss = await File('${entry.path}/status').readAsString();
        final m = RegExp(r'VmRSS:\s+(\d+)').firstMatch(rss);
        stats[id] = (
          parent: int.parse(s[1]),
          rss: m == null ? 0 : int.parse(m.group(1)!) * 1024,
          ticks: int.parse(s[11]) + int.parse(s[12]),
        );
      } on FileSystemException {
        continue;
      }
    }
    final ids = <int>{pid};
    var changed = true;
    while (changed) {
      changed = false;
      for (final e in stats.entries) {
        if (ids.contains(e.value.parent) && ids.add(e.key)) changed = true;
      }
    }
    var bytes = 0, ticks = 0;
    for (final id in ids) {
      bytes += stats[id]?.rss ?? 0;
      ticks += stats[id]?.ticks ?? 0;
    }
    final now = DateTime.now();
    final hz = _libc.lookupFunction<Long Function(Int32), int Function(int)>(
      'sysconf',
    )(2);
    final elapsed = _previous == null
        ? 0
        : now.difference(_previous!).inMilliseconds / 1000;
    final percent = elapsed <= 0
        ? 0.0
        : ((ticks - _ticks).clamp(0, 1 << 60) / hz / elapsed * 100);
    _ticks = ticks;
    _previous = now;
    return ResourceUsage(bytes, percent);
  }
}
