import '../../shared/models/device_info.dart';

/// Builds a launch preference; it does not measure the active rendering GPU.
Map<String, String> linuxGpuEnvironment({
  required GpuInfo? adapter,
  required bool acceleration,
  required Map<String, String> inherited,
}) {
  final env = <String, String>{
    'SIRB_GPU_ACCELERATION': acceleration ? '1' : '0',
  };
  if (adapter == null) return env;
  final isNvidia =
      adapter.kind == 'discrete' &&
      (adapter.name.toLowerCase().contains('nvidia') ||
          adapter.name.contains('0x10de'));
  final switches = <String>[];
  if (adapter.renderNode != null) {
    switches.add('render-node-override=${adapter.renderNode}');
  }
  final current = inherited['SIRB_CEF_SWITCHES'] ?? '';
  if (isNvidia) {
    env['__NV_PRIME_RENDER_OFFLOAD'] = '1';
    env['__GLX_VENDOR_LIBRARY_NAME'] = 'nvidia';
    env['__VK_LAYER_NV_optimus'] = 'NVIDIA_only';
    // Native Views on a hybrid Wayland desktop can fail fatally when the
    // compositor imports NVIDIA dmabufs. PRIME's X11 presentation path
    // avoids that cross-adapter import; never replace an explicit backend
    // choice, and do not request X11 without an available X display.
    final explicitBackend = current
        .split(';')
        .any((s) => s.startsWith('ozone-platform='));
    if (!explicitBackend &&
        (inherited['DISPLAY'] ?? '').isNotEmpty &&
        (inherited['WAYLAND_DISPLAY'] ?? '').isNotEmpty) {
      // Keep the order stable when the child inherits this backend on restart.
      switches.insert(0, 'ozone-platform=x11');
    }
  } else {
    if (adapter.prime != null) env['DRI_PRIME'] = adapter.prime!;
    env['__NV_PRIME_RENDER_OFFLOAD'] = '0';
    env['__GLX_VENDOR_LIBRARY_NAME'] = 'mesa';
  }
  if (switches.isNotEmpty) {
    final cleaned = current
        .split(';')
        .where((s) => s.isNotEmpty && !s.startsWith('render-node-override='));
    env['SIRB_CEF_SWITCHES'] = [...cleaned, ...switches].join(';');
  }
  return env;
}
