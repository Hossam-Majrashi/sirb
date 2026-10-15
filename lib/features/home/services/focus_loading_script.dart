// Document-start native lazy-loading hints. Never remove a source or interfere
// with scripts, styles, media segments, authentication, or site fetches.
const focusLoadingScript = r'''(() => {
  if(window.__sirbFocusLoadingInstalled)return;
  window.__sirbFocusLoadingInstalled=true;
  const hint=element=>{
    if(!window.__sirbFocusLoading || !(element instanceof Element))return;
    if(element.tagName!=='IMG' && element.tagName!=='IFRAME')return;
    // Honour explicit site/user priorities. Chromium decides visibility using
    // layout, including scroll containers, and automatically resumes on scroll.
    if(element.hasAttribute('loading') || element.getAttribute('fetchpriority')==='high')return;
    // Only known large content frames qualify. Hidden/unknown-size utility
    // frames (login, payment, etc.) must never wait for visibility.
    if(element.tagName==='IFRAME'){
      if(element.hidden)return;
      const width=Number(element.getAttribute('width')),height=Number(element.getAttribute('height'));
      if(!Number.isFinite(width) || !Number.isFinite(height) || width<100 || height<100)return;
    }
    element.setAttribute('loading','lazy');
    element.setAttribute('data-sirb-lazy','');
  };
  // Dynamic src/srcset writes get the hint BEFORE starting the request. Parser
  // requests can start before MutationObserver runs; those cannot be undone.
  for(const [type,names] of [[HTMLImageElement,['src','srcset']],[HTMLIFrameElement,['src']]]){
    for(const name of names){
      const descriptor=Object.getOwnPropertyDescriptor(type.prototype,name);
      if(!descriptor?.set || !descriptor.configurable)continue;
      Object.defineProperty(type.prototype,name,{...descriptor,set(value){
        hint(this);return descriptor.set.call(this,value);
      }});
    }
  }
  const nativeSetAttribute=Element.prototype.setAttribute;
  Element.prototype.setAttribute=function(name,value){
    if(typeof name==='string' && /^(src|srcset)$/i.test(name))hint(this);
    return nativeSetAttribute.call(this,name,value);
  };
  const scan=node=>{
    if(!window.__sirbFocusLoading || !(node instanceof Element))return;
    hint(node);node.querySelectorAll('img,iframe').forEach(hint);
  };
  new MutationObserver(records=>{
    if(!window.__sirbFocusLoading)return;
    for(const record of records){
      if(record.type==='attributes')hint(record.target);
      else record.addedNodes.forEach(scan);
    }
  }).observe(document,{subtree:true,childList:true,attributes:true,attributeFilter:['src','srcset']});
  window.__sirbUpdateFocusLoading=()=>{
    if(window.__sirbFocusLoading)scan(document.documentElement);
    else document.querySelectorAll('[data-sirb-lazy]').forEach(element=>{
      // Do not overwrite a subsequent site change to loading=eager.
      if(element.getAttribute('loading')==='lazy')element.removeAttribute('loading');
      element.removeAttribute('data-sirb-lazy');
    });
  };
  window.__sirbUpdateFocusLoading();
})();''';
