// YouTube-only, same-origin public metadata. No translation service, API key,
// language override, background-card crawl, or authenticated player API calls.
const youtubeOriginalTitlesScript = r'''(() => {
  if(!/(^|\.)youtube\.com$/.test(location.hostname) || window.__sirbOriginalTitlesInstalled)return;
  window.__sirbOriginalTitlesInstalled=true;
  const selector='a#video-title,a#video-title-link,a.yt-lockup-metadata-view-model__title,ytd-watch-metadata h1 yt-formatted-string';
  const cache=new Map(),queue=new Map(),inFlight=new Map(),states=new WeakMap(),observed=new Set();
  const intersecting=new WeakSet();
  const nativeFetch=window.fetch;
  let active=0,scanTimer;
  const videoId=element=>{
    try{
      const url=new URL(element.closest('a[href]')?.href || location.href,location.href);
      if(!/(^|\.)youtube\.com$/.test(url.hostname))return null;
      const id=url.pathname==='/watch'?url.searchParams.get('v'):
        /^\/(shorts|live)\/([^/]+)/.exec(url.pathname)?.[2];
      return /^[\w-]{11}$/.test(id || '')?id:null;
    }catch(_){return null;}
  };
  const visible=element=>{
    if(document.hidden || !element.isConnected || !intersecting.has(element))return false;
    const box=element.getBoundingClientRect();
    return box.width>0 && box.height>0 && box.bottom>0 && box.top<innerHeight && box.right>0 && box.left<innerWidth;
  };
  const apply=(element,id,title)=>{
    if(!window.__sirbOriginalTitles || !title || !visible(element) || videoId(element)!==id)return;
    let state=states.get(element);
    if(!state || state.id!==id){
      state={id,text:element.textContent,tooltip:element.getAttribute('title'),pageTitle:document.title,replacement:title};states.set(element,state);
    }
    if(element.textContent!==title)element.textContent=title;
    if(element.getAttribute('title')!==title)element.setAttribute('title',title);
    if(element.closest('ytd-watch-metadata') && location.pathname==='/watch'){
      const pageTitle=title+' - YouTube';if(document.title!==pageTitle)document.title=pageTitle;
    }
  };
  const remember=(id,title)=>{
    cache.set(id,title);if(cache.size>256)cache.delete(cache.keys().next().value);
  };
  const drain=()=>{
    if(!window.__sirbOriginalTitles || document.hidden)return;
    while(active<2 && queue.size){
      const [id,elements]=queue.entries().next().value;queue.delete(id);
      const live=[...elements].filter(element=>visible(element) && videoId(element)===id);
      if(!live.length)continue;
      active++;inFlight.set(id,new Set(live));
      const controller=new AbortController();const timer=setTimeout(()=>controller.abort(),5000);
      const url=new URL('/oembed',location.origin);
      url.searchParams.set('url','https://www.youtube.com/watch?v='+id);url.searchParams.set('format','json');
      nativeFetch.call(window,url.href,{credentials:'omit',signal:controller.signal,priority:'low'})
        .then(response=>response.ok?response.json():null)
        .then(data=>{
          const title=typeof data?.title==='string'?data.title.trim().slice(0,1000):null;
          remember(id,title);for(const element of inFlight.get(id))apply(element,id,title);
        }).catch(()=>remember(id,null)).finally(()=>{clearTimeout(timer);inFlight.delete(id);active--;drain();});
    }
  };
  const request=element=>{
    if(!window.__sirbOriginalTitles || !visible(element))return;
    const id=videoId(element);if(!id)return;
    if(cache.has(id)){apply(element,id,cache.get(id));return;}
    if(inFlight.has(id)){inFlight.get(id).add(element);return;}
    if(queue.size>=64 && !queue.has(id))return;
    if(!queue.has(id))queue.set(id,new Set());queue.get(id).add(element);drain();
  };
  const observer=new IntersectionObserver(entries=>{
    for(const entry of entries){
      if(entry.isIntersecting && entry.intersectionRatio>=0.01){intersecting.add(entry.target);request(entry.target);}
      else intersecting.delete(entry.target);
    }
  },{threshold:0.01});
  const scan=()=>{
    scanTimer=null;
    for(const element of observed)if(!element.isConnected){observer.unobserve(element);observed.delete(element);}
    if(!window.__sirbOriginalTitles)return;
    for(const candidate of document.querySelectorAll(selector)){
      // Keep YouTube's link/component structure and event handlers intact.
      const element=candidate.querySelector('yt-formatted-string#video-title,span.yt-core-attributed-string') || candidate;
      if(!observed.has(element)){observer.observe(element);observed.add(element);}
      request(element);
    }
  };
  const schedule=()=>{if(!scanTimer)scanTimer=setTimeout(scan,180);};
  new MutationObserver(records=>{
    if(!window.__sirbOriginalTitles)return;
    // Player clocks, live chat and comments are not title changes. Avoid a
    // document-wide card scan on every unrelated YouTube mutation.
    for(const record of records){
      const target=record.target instanceof Element?record.target:record.target.parentElement;
      if(target?.closest(selector)){schedule();return;}
      if(record.type==='childList' && [...record.addedNodes,...record.removedNodes].some(node=>
        node instanceof Element && (node.matches(selector) || node.querySelector(selector)))){schedule();return;}
    }
  }).observe(document,{subtree:true,childList:true,characterData:true,attributes:true,attributeFilter:['href']});
  for(const event of ['yt-navigate-finish','visibilitychange'])addEventListener(event,schedule);
  window.__sirbUpdateOriginalTitles=()=>{
    if(!window.__sirbOriginalTitles){
      queue.clear();
      for(const element of observed){
        const state=states.get(element);
        if(state && videoId(element)===state.id && element.textContent===state.replacement){
          element.textContent=state.text;
          if(state.tooltip===null)element.removeAttribute('title');else element.setAttribute('title',state.tooltip);
          if(element.closest('ytd-watch-metadata') && document.title===state.replacement+' - YouTube')document.title=state.pageTitle;
        }
        states.delete(element);
      }
    }else schedule();
  };
  schedule();
})();''';
