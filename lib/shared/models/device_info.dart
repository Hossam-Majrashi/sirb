class GpuInfo {
  const GpuInfo(this.name, this.kind, {this.prime, this.renderNode});
  final String name;
  final String kind;
  final String? prime;
  final String? renderNode;
}

class DeviceInfo {
  const DeviceInfo({
    required this.cores,
    required this.ramBytes,
    required this.gpus,
  });
  final int cores, ramBytes;
  final List<GpuInfo> gpus;
}

class ResourceUsage {
  const ResourceUsage(this.ramBytes, this.cpuPercent);
  final int ramBytes;
  final double cpuPercent;
}
