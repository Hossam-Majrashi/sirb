import 'dart:convert';
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
  String get documentScript {
    if (!preferences.blocking) return '';
    return '''(() => {
      window.__sirbBlocking=false;
      const host=location.hostname;
      const exceptions=${jsonEncode(exceptions)};
      const ancestors=location.ancestorOrigins;
      const topHost=ancestors&&ancestors.length?new URL(ancestors[ancestors.length-1]).hostname:host;
      if(exceptions.some(d=>[host,topHost].some(h=>h===d||h.endsWith('.'+d)))) return;
      window.__sirbBlocking=true;
      let selectors=${jsonEncode(cosmeticSelectorsGlobal)};
      const sites=${jsonEncode(cosmeticSelectorsBySite)};
      for(const [site,rules] of Object.entries(sites)) if(host===site||host.endsWith('.'+site)) selectors=selectors.concat(rules);
      const install=()=>{
        if(!document.documentElement) { setTimeout(install,0);return; }
        const style=document.createElement('style'); style.id='sirb-cosmetic';
        style.textContent=selectors.join(',')+'{display:none!important;visibility:hidden!important}';
        document.documentElement.appendChild(style);
      }; install();
      ${youtubeScripts.join('\n')}
    })();''';
  }
}
