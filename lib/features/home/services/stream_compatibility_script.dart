// Observe real MSE capability. Never spoof isTypeSupported/canPlayType, install
// decoders in JS, rewrite playlists, or force the site's playback decisions.
const streamCompatibilityScript = r'''(() => {
  if(window!==window.top || !/(^|\.)(twitch\.tv|kick\.com)$/.test(location.hostname))return;
  const supports=type=>{try{return !!window.MediaSource?.isTypeSupported(type);}catch(_){return false;}};
  const h264=supports('video/mp4;codecs="avc1.42E01E"');
  const aac=supports('audio/mp4;codecs="mp4a.40.2"');
  console.debug('__sirb__'+JSON.stringify({type:'streamCompatibility',main:true,
    url:location.href,h264,aac}));
})();''';
