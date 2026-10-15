// Only identifiable watch-page continuation fetches may wait. Initial /next,
// /player, googlevideo, mixed/unknown requests and Request bodies pass untouched.
const youtubeFocusRequestsScript = r'''(() => {
  if(!/(^|\.)youtube\.com$/.test(location.hostname) || window.__sirbYoutubeFocusInstalled)return;
  window.__sirbYoutubeFocusInstalled=true;
  const nativeFetch=window.fetch;
  const pending=new Set();
  const visible=element=>{
    if(!element || document.hidden)return false;
    const box=element.getBoundingClientRect();
    return box.width>0 && box.height>=0 && box.bottom>0 && box.right>0 &&
      box.top<innerHeight+160 && box.left<innerWidth;
  };
  // Search only known component data, bounded to avoid walking a page-sized
  // object graph. Never guess from opaque continuation-token contents.
  const hasToken=(root,token)=>{
    const queue=[root],seen=new Set();let budget=2000;
    while(queue.length && budget-->0){
      const value=queue.pop();
      if(!value || typeof value!=='object' || seen.has(value))continue;
      seen.add(value);
      if(value.continuationCommand?.token===token || value.nextContinuationData?.continuation===token)return true;
      for(const key of Object.keys(value).slice(0,100)){
        if(queue.length>=2000)break;
        if(value[key] && typeof value[key]==='object')queue.push(value[key]);
      }
    }
    return false;
  };
  const targetFor=token=>{
    const initial=window.ytInitialData?.contents?.twoColumnWatchNextResults;
    const comments=document.querySelector('ytd-comments#comments');
    const initialComments=initial?.results?.results?.contents?.find(item=>
      item.itemSectionRenderer?.targetId==='comments-section' ||
      item.itemSectionRenderer?.sectionIdentifier==='comment-item-section')?.itemSectionRenderer;
    if(comments && (hasToken(comments.data,token) || hasToken(initialComments,token)))return comments;
    const secondary=document.querySelector('ytd-watch-flexy #secondary');
    const items=secondary?.querySelector('ytd-watch-next-secondary-results-renderer');
    if(secondary && (hasToken(items?.data,token) || hasToken(initial?.secondaryResults,token)))return secondary;
    return null;
  };
  const pump=()=>{for(const entry of [...pending])entry.check();};
  for(const event of ['scroll','resize','visibilitychange','yt-navigate-finish'])
    addEventListener(event,pump,{passive:true,capture:true});
  window.__sirbFlushYoutubeRequests=pump;
  window.fetch=function(input,options){
    let target=null;
    try{
      const url=new URL(typeof input==='string'?input:input.url,location.href);
      if(window.__sirbFocusLoading && location.pathname==='/watch' &&
        url.origin===location.origin && url.pathname==='/youtubei/v1/next' &&
        typeof options?.body==='string'){
        const body=JSON.parse(options.body);
        if(typeof body.continuation==='string')target=targetFor(body.continuation);
      }
    }catch(_){}
    if(!target || visible(target) || pending.size>=16)return nativeFetch.apply(this,arguments);
    const receiver=this,args=arguments,page=location.href;
    const signal=options?.signal || (typeof input==='object'?input.signal:null);
    return new Promise((resolve,reject)=>{
      let done=false,timer;
      const cleanup=()=>{done=true;clearTimeout(timer);pending.delete(entry);signal?.removeEventListener('abort',abort);};
      const start=()=>{
        if(done)return;cleanup();
        if(location.href!==page){reject(new DOMException('Navigation changed','AbortError'));return;}
        try{resolve(nativeFetch.apply(receiver,args));}catch(error){reject(error);}
      };
      const abort=()=>{if(done)return;cleanup();reject(signal.reason || new DOMException('Aborted','AbortError'));};
      const entry={cancel:()=>{if(done)return;cleanup();reject(new DOMException('Page closed','AbortError'));},check:()=>{
        if(location.href!==page){cleanup();reject(new DOMException('Navigation changed','AbortError'));return;}
        if(!window.__sirbFocusLoading || !target.isConnected || visible(target))start();
      }};
      pending.add(entry);
      signal?.addEventListener('abort',abort,{once:true});
      // Fail open: a changed YouTube component must not leave a spinner forever.
      timer=setTimeout(start,15000);
      if(signal?.aborted)abort();
    });
  };
  addEventListener('pagehide',()=>{
    // Do not send stale continuation requests while leaving the document.
    for(const entry of [...pending])entry.cancel();
  },{once:true});
})();''';
