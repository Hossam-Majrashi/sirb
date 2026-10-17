import 'dart:convert';
import 'runtime_error_script.dart';
import 'media_playback_script.dart';
import 'video_priority_script.dart';
import 'stream_compatibility_script.dart';

String documentTelemetry({
  required bool preload,
  required String colorScheme,
}) =>
    '''(() => {
  if(window.__sirbTelemetry) return; window.__sirbTelemetry=true;
  window.__sirbPreload=${preload ? 'true' : 'false'};
  $mediaPlaybackScript
  const frame=location.href+':'+Math.random().toString(36).slice(2);
  const main=window===window.top;
  const send=data=>console.debug('__sirb__'+JSON.stringify(data));
  $runtimeErrorTelemetry
  $videoPriorityScript
  $streamCompatibilityScript
  let audioContexts=0,rtcTracks=0;
  const audioRefs=new Set();
  window.__sirbAudioDiagnostics=()=>{
    const result=[];
    for(const ref of audioRefs){
      const c=ref.deref();if(!c){audioRefs.delete(ref);continue;}
      result.push({state:c.state,sampleRate:c.sampleRate,
        baseLatency:c.baseLatency,outputLatency:c.outputLatency,
        currentTime:c.currentTime,outputTimestamp:c.getOutputTimestamp?.()});
    }
    return result;
  };
  const report=()=>{
    try {
      const elements=Array.from(document.querySelectorAll('video,audio'));
      const media=audioContexts>0||rtcTracks>0||elements.some(v=>!v.paused&&!v.ended);
      const video=elements.find(v=>v.tagName==='VIDEO'&&!v.paused)||elements.find(v=>v.tagName==='VIDEO');
      send({type:'media',frame,main,playing:media,position:video&&Number.isFinite(video.currentTime)?video.currentTime:0});
    }catch(_){}
  };
  for(const name of ['AudioContext','webkitAudioContext']) {
    const Base=window[name]; if(!Base) continue;
    try { window[name]=class extends Base {
      constructor(...args) { super(...args); let active=false;
        // Observe existing contexts only: no extra device/stream, resampling or
        // forced resume. Weak references do not keep discarded game audio alive.
        if(typeof WeakRef==='function')audioRefs.add(new WeakRef(this));
        const update=()=>{const playing=this.state==='running'; if(active!==playing){audioContexts+=playing?1:-1;active=playing;report();}};
        this.addEventListener('statechange',update);update();
      }
    }; } catch(_) {}
  }
  if(window.RTCPeerConnection) {
    const Base=window.RTCPeerConnection;
    try {window.RTCPeerConnection=class extends Base {
      constructor(...args){super(...args);this.addEventListener('track',event=>{
        rtcTracks++;report();event.track.addEventListener('ended',()=>{rtcTracks--;report();},{once:true});
      });}
    };}catch(_){}
  }
  // Position is sampled by the 2s timer. Per-element timeupdate events can
  // flood the bridge on games/video-heavy pages without changing media state.
  for(const event of ['play','pause','ended','loadedmetadata']) document.addEventListener(event,report,true);
  const timer=setInterval(report,2000);
  addEventListener('pagehide',()=>{clearInterval(timer);send({type:'media',frame,main,playing:false,position:0});},{once:true});
  let hover;
  const videoLink=target=>{
    const link=target.closest&&target.closest('a[href]');if(!link)return null;
    let url;try{url=new URL(link.href);}catch(_){return null;}
    if(!/^https?:\$/.test(url.protocol))return null;
    const isVideo = /(^|\\.)youtu\\.be\$/.test(url.hostname) ||
      (/(^|\\.)youtube\\.com\$/.test(url.hostname) && /^\\/(watch|shorts)/.test(url.pathname)) ||
      (/(^|\\.)vimeo\\.com\$/.test(url.hostname) && /^\\/\\d+/.test(url.pathname)) ||
      (/(^|\\.)dailymotion\\.com\$/.test(url.hostname) && /^\\/video\\//.test(url.pathname)) ||
      (/(^|\\.)twitch\\.tv\$/.test(url.hostname) && url.pathname.length > 1) ||
      (/(^|\\.)kick\\.com\$/.test(url.hostname) && url.pathname.length > 1);
    if(!isVideo)return null;
    return url.href;
  };
  document.addEventListener('pointerover',event=>{
    clearTimeout(hover);if(!window.__sirbPreload)return;const url=videoLink(event.target);if(!url)return;
    hover=setTimeout(()=>send({type:'hover',url}),300);
  },true);
  document.addEventListener('pointerout',()=>clearTimeout(hover),true);
  document.addEventListener('click',event=>{
    if(event.button!==0 || event.altKey)return;
    const url=videoLink(event.target);if(!url)return;
    const link=event.target.closest('a[href]');
    const newTab=event.ctrlKey||event.metaKey||(link&&link.target==='_blank');
    if(newTab){
      event.preventDefault();event.stopImmediatePropagation();
      send({type:'navigate',url,newTab:true,background:(event.ctrlKey||event.metaKey)&&!event.shiftKey});
    }
  },true);
  document.addEventListener('contextmenu',event=>{
    event.preventDefault();
    event.stopPropagation();
    event.stopImmediatePropagation();
    const link=event.target&&event.target.closest?event.target.closest('a[href]'):null;
    let linkUrl=null;
    if(link){try{linkUrl=new URL(link.href).href;}catch(_){linkUrl=link.href;}}
    const selection=(event.target&&(event.target.tagName==='INPUT'||event.target.tagName==='TEXTAREA'))?event.target.value.substring(event.target.selectionStart||0,event.target.selectionEnd||0):(window.getSelection()?window.getSelection().toString():'');
    const isEditable=!!(event.target&&(event.target.isContentEditable||event.target.tagName==='INPUT'||event.target.tagName==='TEXTAREA'));
    send({type:'contextMenu',x:event.clientX,y:event.clientY,link:linkUrl,selection,editable:isEditable});
  },true);
  if(window.__sirbPreload) {
    const install=()=>{
      if(!document.documentElement){setTimeout(install,0);return;}
      for(const host of ['https://www.youtube.com','https://i.ytimg.com','https://www.googlevideo.com','https://vimeo.com','https://www.twitch.tv']) {
        for(const rel of ['preconnect','dns-prefetch']) {const link=document.createElement('link');link.rel=rel;link.href=host;document.documentElement.appendChild(link);}
      }
    };install();
  }
  const ensureVideoFit=()=>{
    try {
      if(document.getElementById('sirb-global-video-fit')) return;
      if(!document.head && !document.documentElement) return;
      const s=document.createElement('style');
      s.id='sirb-global-video-fit';
      s.textContent='video{object-fit:contain!important;object-position:center!important;}';
      (document.head||document.documentElement).appendChild(s);
    }catch(_){}
  };
  ensureVideoFit();
  if(document.readyState!=='complete') addEventListener('DOMContentLoaded',ensureVideoFit,{once:true});
  const theme=()=>{if(!document.documentElement){setTimeout(theme,0);return;}document.documentElement.style.colorScheme=${jsonEncode(colorScheme)};};theme();
})();''';
