// YouTube-only rules. Never block googlevideo.com as a whole.
const youtubeBlockedDomains = <String>['ads.youtube.com'];
const youtubeBlockedUrlPatterns = <String>[
  r'^https?://(?:[^/]+\.)?youtube\.com/(pagead|api/stats/ads|youtubei/v1/log_interaction\?[^#]*ad_type)',
  r'^https?://(?:[^/]+\.)?googlevideo\.com/[^#]*[?&](oad|adformat)=',
];
const youtubeCosmeticSelectors = <String>[
  'ytd-ad-slot-renderer',
  'ytd-display-ad-renderer',
  'ytd-promoted-sparkles-web-renderer',
  'ytd-promoted-video-renderer',
  'ytd-in-feed-ad-layout-renderer',
  'ytd-banner-promo-renderer',
  'ytd-action-companion-ad-renderer',
  'ytd-search-pyv-renderer',
  'ytd-rich-item-renderer:has(ytd-ad-slot-renderer)',
  '.ytp-ad-overlay-container',
  '#player-ads',
  '#masthead-ad',
];

const youtubeScripts = <String>[
  r'''(() => {
    if (!/(^|\.)youtube\.com$/.test(location.hostname)) return;
    if (window.__sirbYouTube) { window.__sirbUpdateYouTubeAds?.(); return; }
    window.__sirbYouTube = true;
    const clean = object => {
      if (!object || typeof object !== 'object') return object;
      for (const key of ['adPlacements','playerAds','adSlots','adBreakHeartbeatParams']) {
        try { if (Object.prototype.hasOwnProperty.call(object,key)) delete object[key]; } catch (_) {}
      }
      return object;
    };
    const originalParse = JSON.parse;
    JSON.parse = function(...args) {
      const value = Reflect.apply(originalParse, this, args);
      if (window.__sirbBlocking === false) return value;
      try { clean(value); if (value && value.playerResponse) clean(value.playerResponse); } catch (_) {}
      return value;
    };
    try {
      let response = window.ytInitialPlayerResponse;
      Object.defineProperty(window,'ytInitialPlayerResponse', {
        configurable:true, get:()=>response, set:value=>{response=window.__sirbBlocking === false ? value : clean(value);}
      }); if (window.__sirbBlocking !== false) clean(response);
    } catch (_) {}

    let player, timer=0, suspended=false;
    const clicked=new WeakMap(), sought=new WeakMap();
    const isAd=()=>player && (player.classList.contains('ad-showing') || player.classList.contains('ad-interrupting'));
    const schedule=()=>{
      if (!suspended && !timer && window.__sirbBlocking !== false) timer=setTimeout(handle,100);
    };
    const playerObserver=new MutationObserver(schedule);
    const controlsObserver=new MutationObserver(schedule);
    const bind=()=>{
      const next=document.querySelector('#movie_player');
      if (next===player) return;
      playerObserver.disconnect();controlsObserver.disconnect();player=next;
      if (player) {
        // Only the player's own ad-state class and added controls matter.
        // Do not observe class changes across the entire YouTube document.
        playerObserver.observe(player,{attributes:true,attributeFilter:['class']});
        controlsObserver.observe(player,{childList:true,subtree:true});
      }
    };
    const handle=()=>{
      timer=0;
      if (suspended || window.__sirbBlocking === false) return;
      try {
        if (!player?.isConnected) bind();
        if (!player) return;
        const video=player.querySelector('video');
        if (!isAd()) { if(video)sought.delete(video); return; }
        const now=performance.now();
        for (const button of player.querySelectorAll('.ytp-ad-skip-button,.ytp-ad-skip-button-modern,.ytp-skip-ad-button,.ytp-ad-overlay-close-button')) {
          if (button.getClientRects().length && !button.disabled && now-(clicked.get(button)??-Infinity)>=1000) {
            clicked.set(button,now);button.click();
          }
        }
        // At most one seek per explicitly marked, finite ad source/episode.
        // Never change playback rate, pause/play, mute, or seek a live stream.
        if (isAd() && video && !video.seeking && !video.ended && Number.isFinite(video.duration) && video.duration>0 && video.duration<180) {
          const source=video.currentSrc || video.getAttribute('src') || '';
          const end=Math.max(0,video.duration-.05);
          if (sought.get(video)!==source && video.currentTime<end-.25) {
            sought.set(video,source);video.currentTime=end;
          }
        }
        // Only poll during an ad, not throughout normal playback.
        if (isAd()) schedule();
      } catch (_) {}
    };
    const discover=new MutationObserver(()=>{
      if (!player?.isConnected) schedule();
      // A replaced SPA player is discovered after the old one is disconnected.
    });
    const resume=()=>{
      suspended=false;
      discover.observe(document,{childList:true,subtree:true});
      bind();schedule();
    };
    window.__sirbUpdateYouTubeAds=schedule;
    const metadata=event=>{if(event.target instanceof HTMLVideoElement){sought.delete(event.target);schedule();}};
    document.addEventListener('loadedmetadata',metadata,true);
    addEventListener('yt-navigate-finish',()=>{bind();schedule();});
    addEventListener('pagehide',()=>{
      suspended=true;clearTimeout(timer);timer=0;discover.disconnect();playerObserver.disconnect();controlsObserver.disconnect();player=null;
    });
    addEventListener('pageshow',resume);
    resume();
  })();''',
];
