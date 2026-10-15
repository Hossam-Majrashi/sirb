// Hint buffering for one large visible video with no explicit site preload
// policy, and for the locally selected video on user intent. Never auto-play,
// seek, focus, choose quality, call load(), or intercept media requests.
// Applies to HTML5 sites/frames on Linux, Windows and macOS; MSE players still
// own their segment buffering. Explicit site preload policies are honoured
// until the user interacts with that player.
const videoPriorityScript = r'''(() => {
  if(window.__sirbVideoPriority)return;
  window.__sirbVideoPriority=true;
  // Bound automatic buffering: not every thumbnail/feed player. Intersection
  // honours clipped/scroll-container visibility; save-data/speculation opt out.
  let selected=false, suspended=false, intersection, discovery;
  const observed=new Set();
  const stop=()=>{intersection?.disconnect();discovery?.disconnect();observed.clear();};
  const scan=node=>{
    if(selected || suspended || !(node instanceof Element))return;
    for(const video of [...(node.matches('video')?[node]:[]),...node.querySelectorAll('video')]){
      if(observed.size>=32)break;
      if(!observed.has(video)){observed.add(video);intersection.observe(video);}
    }
  };
  if(typeof IntersectionObserver==='function' && !navigator.connection?.saveData){
    intersection=new IntersectionObserver(entries=>{
      if(selected || suspended || window.__sirbSpeculative)return;
      const candidates=entries.filter(entry=>entry.isIntersecting && entry.intersectionRatio>=.5 &&
        entry.boundingClientRect.width>=240 && entry.boundingClientRect.height>=135 &&
        !entry.target.hasAttribute('preload') && !entry.target.error);
      candidates.sort((a,b)=>(b.intersectionRect.width*b.intersectionRect.height)-(a.intersectionRect.width*a.intersectionRect.height));
      if(candidates.length){selected=true;candidates[0].target.preload='auto';stop();}
    },{threshold:[.5]});
    discovery=new MutationObserver(records=>{
      for(const video of observed)if(!video.isConnected){intersection.unobserve(video);observed.delete(video);}
      for(const record of records)for(const node of record.addedNodes)scan(node);
    });
    const resume=()=>{
      suspended=false;if(selected)return;
      discovery.observe(document,{childList:true,subtree:true});scan(document.documentElement);
    };
    addEventListener('pagehide',()=>{suspended=true;stop();});
    addEventListener('pageshow',resume);
    resume();
  }
  const prioritize=event=>{
    if(window.__sirbSpeculative || event.button>0)return;
    let target=event.composedPath?.()[0] || event.target;
    if(!(target instanceof Element))return;
    let video=target.closest('video');
    // Custom player controls are often siblings of the video. Search only a
    // small local ancestry, never the whole page or a multi-video feed.
    for(let depth=0;!video && target && depth<3;depth++,target=target.parentElement){
      if(target===document.body || target===document.documentElement)break;
      const candidates=target.querySelectorAll('video');
      if(candidates.length===1)video=candidates[0];
      else if(candidates.length>1)break;
    }
    if(!video || video.error || video.preload==='auto')return;
    // This is a hint only; Chromium/site MSE buffering remains authoritative.
    video.preload='auto';
  };
  document.addEventListener('pointerdown',prioritize,{capture:true,passive:true});
  document.addEventListener('focusin',prioritize,true);
})();''';
