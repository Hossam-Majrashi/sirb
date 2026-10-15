import 'ad_document_script.dart';
import '../ad_rules.dart';
import '../models/native_ad_configuration.dart';
import '../../settings/services/preferences_service.dart';

class AdBlocker {
  AdBlocker(this.preferences);
  final PreferencesService preferences;
  List<String> get exceptions =>
      {...allowedDomains, ...preferences.allowlist}.toList();
  bool enabledFor(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    return preferences.blocking &&
        !exceptions.any((d) => host == d || host.endsWith('.$d'));
  }

  Future<void> toggleSite(String url) async {
    final host = Uri.tryParse(url)?.host ?? '';
    if (host.isEmpty) return;
    final list = preferences.allowlist.toList();
    if (list.contains(host)) {
      list.remove(host);
    } else {
      list.add(host);
    }
    await preferences.set('allowlist', list);
  }

  Map<String, Object> configuration(String profile, String telemetry) =>
      NativeAdConfiguration(
        profile: profile,
        enabled: preferences.blocking,
        domains: blockedDomains,
        patterns: blockedUrlPatterns,
        allowed: exceptions,
        script: '$telemetry\n$documentScript',
      ).toMap();
  String get documentScript =>
      preferences.blocking ? adDocumentScript(exceptions) : '';
}
