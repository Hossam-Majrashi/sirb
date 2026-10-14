import 'package:flutter_test/flutter_test.dart';
import 'package:sirb/platform/linux/linux_gpu_environment.dart';
import 'package:sirb/shared/models/device_info.dart';

void main() {
  final nvidia = GpuInfo(
    'NVIDIA GeForce GTX 1650 Ti',
    'discrete',
    prime: 'pci-0000_01_00_0',
    renderNode: '/dev/dri/renderD129',
  );
  final intel = GpuInfo(
    'Intel UHD',
    'integrated',
    prime: 'pci-0000_00_02_0',
    renderNode: '/dev/dri/renderD128',
  );
  const hybrid = {'DISPLAY': ':0', 'WAYLAND_DISPLAY': 'wayland-0'};

  test('NVIDIA offload prefers XWayland and replaces stale render node', () {
    final env = linuxGpuEnvironment(
      adapter: nvidia,
      acceleration: true,
      inherited: {
        ...hybrid,
        'SIRB_CEF_SWITCHES':
            'remote-debugging-port=9227;render-node-override=/dev/dri/renderD128',
      },
    );
    expect(env['SIRB_GPU_ACCELERATION'], '1');
    expect(env['__NV_PRIME_RENDER_OFFLOAD'], '1');
    expect(env['__GLX_VENDOR_LIBRARY_NAME'], 'nvidia');
    expect(env['__VK_LAYER_NV_optimus'], 'NVIDIA_only');
    expect(env.containsKey('DRI_PRIME'), false);
    expect(env['SIRB_CEF_SWITCHES']!.split(';'), [
      'remote-debugging-port=9227',
      'ozone-platform=x11',
      'render-node-override=/dev/dri/renderD129',
    ]);
    final next = linuxGpuEnvironment(
      adapter: nvidia,
      acceleration: true,
      inherited: {...hybrid, ...env},
    );
    expect(next, env); // Early relaunch must converge instead of looping.
  });

  test('honors explicit Ozone backend and does not require missing X11', () {
    for (final inherited in <Map<String, String>>[
      {'WAYLAND_DISPLAY': 'wayland-0'},
      {'DISPLAY': ':0'},
      {},
      {...hybrid, 'SIRB_CEF_SWITCHES': 'ozone-platform=wayland'},
    ]) {
      final env = linuxGpuEnvironment(
        adapter: nvidia,
        acceleration: true,
        inherited: inherited,
      );
      expect(env['SIRB_CEF_SWITCHES'], isNot(contains('ozone-platform=x11')));
      if (inherited.containsKey('SIRB_CEF_SWITCHES')) {
        expect(env['SIRB_CEF_SWITCHES'], contains('ozone-platform=wayland'));
      }
    }
  });

  test('Mesa adapter retains PCI selection without NVIDIA workaround', () {
    for (final adapter in [
      intel,
      GpuInfo(
        'AMD Radeon RX',
        'discrete',
        prime: 'pci-0000_03_00_0',
        renderNode: '/dev/dri/renderD130',
      ),
    ]) {
      final env = linuxGpuEnvironment(
        adapter: adapter,
        acceleration: true,
        inherited: hybrid,
      );
      expect(env['DRI_PRIME'], adapter.prime);
      expect(env['__NV_PRIME_RENDER_OFFLOAD'], '0');
      expect(env['__GLX_VENDOR_LIBRARY_NAME'], 'mesa');
      expect(
        env['SIRB_CEF_SWITCHES'],
        'render-node-override=${adapter.renderNode}',
      );
    }
  });

  test('OS automatic selection introduces no adapter or backend switches', () {
    expect(
      linuxGpuEnvironment(
        adapter: null,
        acceleration: false,
        inherited: hybrid,
      ),
      {'SIRB_GPU_ACCELERATION': '0'},
    );
  });
}
