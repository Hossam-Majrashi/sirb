import '../models/device_info.dart';

abstract class ResourceService {
  Future<DeviceInfo> detect();
  Future<ResourceUsage> usage();
  bool get affinitySupported;
  bool get gpuSupported;
  Future<bool> get hardRamSupported;
  Future<bool> isTouchpadNaturalScrolling();
  Future<void> applyCpu(int count);
  Future<void> applyHardRam(int bytes);
  Future<void> applyGpu(String preference);
  Map<String, String> launchEnvironment(String gpu, bool acceleration);
}
