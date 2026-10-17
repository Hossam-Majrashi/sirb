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
  if(exceptions.some(d=>[host,topHost].some(h=>h===d||h.endsWith('.'+d)))) {
    document.getElementById('sirb-cosmetic')?.remove();return;
  }
  window.__sirbBlocking=true;
  let selectors=${jsonEncode(cosmeticSelectorsGlobal)};
  const sites=${jsonEncode(cosmeticSelectorsBySite)};
  for(const [site,rules] of Object.entries(sites)) if(host===site||host.endsWith('.'+site)) selectors=selectors.concat(rules);
  const install=()=>{
    if(!document.documentElement) { setTimeout(install,0);return; }
    // Reuse the sheet: remove/reinsert on every activation/load-end temporarily
    // unhides slots and makes the site's layout observers redo the same work.
    let style=document.getElementById('sirb-cosmetic');
    // An ad-labelled wrapper must never hide the actual media player.
    const safe=selectors.map(s=>s+':not(video):not(audio):not(:has(video,audio))');
    const css=safe.join(',')+'{display:none!important;visibility:hidden!important}';
    if(!style){
      style=document.createElement('style');style.id='sirb-cosmetic';
      style.textContent=css;document.documentElement.appendChild(style);
    }else if(style.textContent!==css)style.textContent=css;
  }; install();
  ${youtubeScripts.join('\n')}
})();''';
