class NativeAdConfiguration {
  const NativeAdConfiguration({
    required this.profile,
    required this.enabled,
    required this.domains,
    required this.patterns,
    required this.allowed,
    required this.script,
  });
  final String profile, script;
  final bool enabled;
  final List<String> domains, patterns, allowed;
  Map<String, Object> toMap() => {
    'profile': profile,
    'enabled': enabled,
    'domains': domains,
    'patterns': patterns,
    'allowed': allowed,
    'script': script,
  };
}
