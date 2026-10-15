import 'dart:convert';

import '../ad_rules.dart';

// Pure policy builder shared by native document-start injection and fixtures.
String adDocumentScript(List<String> exceptions) =>
    '''(() => {
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
    document.getElementById('sirb-cosmetic')?.remove();
    const style=document.createElement('style'); style.id='sirb-cosmetic';
    // An ad-labelled wrapper must never hide the actual media player.
    const safe=selectors.map(s=>s+':not(video):not(audio):not(:has(video,audio))');
    style.textContent=safe.join(',')+'{display:none!important;visibility:hidden!important}';
    document.documentElement.appendChild(style);
  }; install();
  ${youtubeScripts.join('\n')}
})();''';
