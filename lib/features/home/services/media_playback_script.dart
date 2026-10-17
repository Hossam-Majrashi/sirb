// Chromium's activation policy still permits muted autoplay. Enforce the same
// manual-start rule for media in HTTP(S) documents/frames, including promoted
// speculative hosts. Opening/focusing a tab or clicking a link is not consent.
// Only trusted local player interaction unlocks that media element; thereafter
// leave site playback/playlist controls untouched.
const mediaPlaybackScript = r'''(() => {
  if(window.__sirbManualPlayback)return;
  window.__sirbManualPlayback=true;
  const allowed=new WeakSet();
  const waiting=media=>!navigator.userActivation.hasBeenActive || !allowed.has(media);
  const intent=event=>{
    if(!event.isTrusted || event.button>0)return;
    if(event.type==='keydown' && ![' ','Enter','k','K'].includes(event.key))return;
    let target=event.composedPath?.()[0] || event.target;
    if(!(target instanceof Element) || target.closest('a[href]'))return;
    if(event.type==='keydown' && target.matches('input,textarea,[contenteditable]:not([contenteditable="false"])'))return;
    // SVG/icon children are part of their button, not extra player ancestry.
    // Custom bottom controls commonly sit four or five levels below the media.
    target=target.closest('button,[role="button"]') || target;
    let media=target.closest('video,audio');
    // Custom controls can be siblings of the media. Stay within a small local
    // ancestry, never unlock all players in a feed or on unrelated page clicks.
    for(let depth=0;!media && target && depth<6;depth++,target=target.parentElement){
      if(target===document.body || target===document.documentElement)break;
      const candidates=target.querySelectorAll('video,audio');
      if(candidates.length===1)media=candidates[0];
      else if(candidates.length>1)break;
    }
    // Common player keyboard shortcuts work when the page body has focus,
    // but only for one visible video, never while typing or on arbitrary keys.
    if(!media && event.type==='keydown' && event.target===document.body && event.key!=='Enter'){
      const videos=Array.from(document.querySelectorAll('video')).slice(0,32)
        .filter(video=>video.getClientRects().length>0);
      if(videos.length===1)media=videos[0];
    }
    if(media)allowed.add(media);
  };
  for(const name of ['pointerdown','click','keydown'])document.addEventListener(name,intent,{capture:true,passive:true});
  const nativePlay=HTMLMediaElement.prototype.play;
  HTMLMediaElement.prototype.play=function(...args){
    if(waiting(this))return Promise.reject(new DOMException('Sirb requires player interaction before playback','NotAllowedError'));
    return Reflect.apply(nativePlay,this,args);
  };
  // The HTML autoplay attribute does not call the JavaScript play() method.
  // Catch that native path too; never start media on behalf of the user.
  document.addEventListener('play',event=>{
    if(event.target instanceof HTMLMediaElement && waiting(event.target))event.target.pause();
  },true);
})();''';
