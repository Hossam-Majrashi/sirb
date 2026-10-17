// Observe failures without granting permissions, spoofing pointer lock, forcing
// playback or swallowing the website's exceptions/rejected promises.
const runtimeErrorTelemetry = r'''(() => {
  const debug=console.debug.bind(console);
  const text=(value,max=8192)=>{try{return String(value??'').slice(0,max);}catch(_){return '[unprintable]';}};
  const reported=new WeakSet();
  const expectedPlayback=reason=>
    (reason?.name==='NotAllowedError' && reason.message==='Sirb requires player interaction before playback') ||
    (reason?.name==='AbortError' && /^The play\(\) request was interrupted by (?:a call to pause\(\)|a new load request)/.test(reason.message??''));
  const error=(category,reason,extra={})=>{
    // Expected policy denials and play/pause/load races are not decoder faults.
    // Keep the rejection intact so the website's own catch still runs.
    if(expectedPlayback(reason))return;
    if(reason && (typeof reason==='object' || typeof reason==='function')){
      if(reported.has(reason))return;
      reported.add(reason);
    }
    try{debug('__sirb__'+JSON.stringify({type:'runtimeError',category,
      message:text(reason?.message??reason,4096),details:text(reason?.stack),
      url:location.href,frameUrl:location.href,main:window===window.top,...extra}));}catch(_){}
  };
  addEventListener('error',e=>{
    if(e instanceof ErrorEvent)error('javascript',e.error??e.message,{source:e.filename,line:e.lineno,column:e.colno});
    else if(e.target instanceof HTMLMediaElement)error('media',e.target.error?.message??'Media element failed',
      {source:e.target.currentSrc,code:e.target.error?.code});
    else {
      // Empty/missing src properties can resolve to the page URL, falsely
      // labelling the document as the failed resource (e.g. a removed image).
      const target=e.target;
      const attribute=target?.getAttribute?.('src')||target?.getAttribute?.('href');
      if(attribute?.trim())error('network','Document resource failed',
        {source:target.currentSrc||target.src||target.href,resourceTag:target.tagName});
    }
  },true);
  addEventListener('unhandledrejection',e=>error('javascript',e.reason,{operation:'unhandledrejection'}));
  document.addEventListener('webglcontextlost',e=>error('graphics',e.statusMessage||'WebGL context lost'),true);
  document.addEventListener('pointerlockerror',()=>error('permission','Pointer lock failed',{operation:'pointerlockerror'}),true);
  document.addEventListener('fullscreenerror',()=>error('permission','Fullscreen request failed',{operation:'fullscreenerror'}),true);
  const observe=(owner,key,category)=>{
    const original=owner?.[key];if(typeof original!=='function')return;
    try{owner[key]=function(...args){
      try{
        const result=Reflect.apply(original,this,args);
        if(result&&typeof result.then==='function')return result.catch(reason=>{
          error(category,reason,{operation:key});throw reason;
        });
        return result;
      }catch(reason){error(category,reason,{operation:key});throw reason;}
    };}catch(_){}
  };
  observe(Element.prototype,'requestPointerLock','permission');
  observe(Element.prototype,'requestFullscreen','permission');
  observe(HTMLMediaElement.prototype,'play','media');
  const audioBases=new Set();
  for(const name of ['AudioContext','webkitAudioContext']) {
    const Base=window[name];if(Base&&!audioBases.has(Base)){
      observe(Base.prototype,'resume','media');audioBases.add(Base);
    }
  }
  if(window.AudioWorklet)observe(AudioWorklet.prototype,'addModule','media');
  if(window.GPUAdapter){
    const original=GPUAdapter.prototype.requestDevice;
    if(typeof original==='function')try{GPUAdapter.prototype.requestDevice=function(...args){
      return Reflect.apply(original,this,args).then(device=>{
        try{
          device.lost.then(info=>{if(info.reason!=='destroyed')error('graphics',info.message||'WebGPU device lost',{operation:'GPUDevice.lost',reason:info.reason});});
          device.addEventListener('uncapturederror',e=>error('graphics',e.error,{operation:'GPUDevice.uncapturederror'}));
        }catch(_){}
        return device;
      },reason=>{error('graphics',reason,{operation:'GPUAdapter.requestDevice'});throw reason;});
    };}catch(_){}
  }
  if(window.Worker){
    const Base=window.Worker;
    try{window.Worker=class extends Base{constructor(...args){super(...args);
      this.addEventListener('error',e=>error('javascript',e.message||'Worker failed',
        {operation:'Worker.error',source:e.filename,line:e.lineno,column:e.colno}));
      this.addEventListener('messageerror',()=>error('javascript','Worker message could not be deserialized',{operation:'Worker.messageerror'}));
    }};}catch(_){}
  }
})();''';
