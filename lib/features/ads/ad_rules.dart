// قواعد الحجب فقط — لا تضف منطق Dart إلى هذا الملف.
// لإضافة نطاق: أضف اسم النطاق دون https إلى blockedDomains؛ يشمل النطاقات الفرعية.
// لإضافة رابط: أضف تعبيرًا نمطيًا متوافقًا مع ECMAScript إلى blockedUrlPatterns.
// للاستثناء: أضف نطاقًا إلى allowedDomains. استثناء المستخدم يُحفظ في الإعدادات.
// للإخفاء: أضف CSS selector عامًا أو تحت نطاق الموقع في cosmeticSelectorsBySite.
// لتحديث YouTube: عدّل السكربت الدفاعي واختبر تشغيل المحتوى والصوت بعد التغيير.
// لا تحجب googlevideo.com بالكامل؛ فهو ينقل الفيديو الأساسي أيضًا.
const blockedDomains = <String>[
  'doubleclick.net',
  'googlesyndication.com',
  'googleadservices.com',
  'adservice.google.com',
  'ads.youtube.com',
  'ads.twitch.tv',
  'ads.vimeo.com',
  'ads.dailymotion.com',
  'adnxs.com',
  'taboola.com',
  'outbrain.com',
  'adsrvr.org',
  'advertising.com',
  'pubmatic.com',
];
const blockedUrlPatterns = <String>[
  r'^https?://[^/]*youtube\.com/(pagead|api/stats/ads|youtubei/v1/log_interaction\?[^#]*ad_type)',
  r'^https?://[^/]*googlevideo\.com/[^#]*[?&](oad|adformat)=',
  r'^https?://[^/]+/(ads|advertisements|adserver)/',
  r'^https?://[^/]*dailymotion\.com/[^#]*/ads/',
];
const allowedDomains = <String>[];
const cosmeticSelectorsGlobal = <String>[
  '[data-ad-slot]',
  '[data-ad-client]',
  '.adsbygoogle',
  '[aria-label="Advertisement"]',
  '[aria-label="إعلان"]',
  '.advertisement',
  '.ad-banner',
  '.ad-overlay',
];
const cosmeticSelectorsBySite = <String, List<String>>{
  'youtube.com': [
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
  ],
  'vimeo.com': ['.vp-ad', '.ad-container'],
  'dailymotion.com': ['.ad-container', '[data-testid="ad-banner"]'],
  'twitch.tv': ['[data-a-target="video-ad-label"]', '.stream-display-ad'],
};
const youtubeScripts = <String>[
  r'''(() => {
    if (!/(^|\.)youtube\.com$/.test(location.hostname)) return;
    if (window.__sirbYouTube) return;
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
      }); clean(response);
    } catch (_) {}
    const handle = () => {
      if (window.__sirbBlocking === false) return;
      try {
        const player = document.querySelector('#movie_player');
        if (!player) return;
        for (const button of player.querySelectorAll('.ytp-ad-skip-button,.ytp-ad-skip-button-modern,.ytp-skip-ad-button,.ytp-ad-overlay-close-button')) {
          if (button.offsetParent && !button.disabled) button.click();
        }
        if (player.classList.contains('ad-showing') || player.classList.contains('ad-interrupting')) {
          const video = player.querySelector('video');
          // Seek only when the player explicitly identifies the clip as an ad.
          if (video && Number.isFinite(video.duration) && video.duration > 0 && video.duration < 180) {
            video.currentTime = Math.max(0, video.duration - .05);
          }
        }
      } catch (_) {}
    };
    const triggerFlexyUpdate = () => {
      try {
        const flexy = document.querySelector('ytd-watch-flexy');
        if (flexy) {
          if (typeof flexy.calculateFlexy_ === 'function') flexy.calculateFlexy_();
          if (typeof flexy.handleResize_ === 'function') flexy.handleResize_();
          if (typeof flexy.calculateCurrentPlayerSize_ === 'function') flexy.calculateCurrentPlayerSize_();
        }
        const player = document.querySelector('#movie_player');
        if (player) {
          if (typeof player.setInternalSize === 'function') player.setInternalSize();
          if (typeof player.setSize === 'function') player.setSize();
        }
      } catch (_) {}
    };
    const injectResizeStyle = () => {
      try {
        if (document.getElementById('sirb-yt-resize-fix')) return;
        const s = document.createElement('style');
        s.id = 'sirb-yt-resize-fix';
        s.textContent = 'ytd-watch-flexy,ytd-watch-flexy #primary,ytd-watch-flexy #primary-inner,ytd-watch-flexy #player,ytd-watch-flexy #player-container,ytd-watch-flexy #player-container-outer,ytd-watch-flexy #player-container-inner,ytd-watch-flexy #movie_player,ytd-watch-flexy .html5-video-player,ytd-watch-flexy .html5-main-video,ytd-watch-flexy video{transition:none!important;animation:none!important;}' +
          'video,.html5-main-video,.html5-video-player video,ytd-watch-flexy video{object-fit:contain!important;object-position:center!important;}';
        (document.head || document.documentElement).appendChild(s);
      } catch (_) {}
    };
    const attach = () => {
      if (!document.documentElement) { setTimeout(attach,0); return; }
      injectResizeStyle();
      const observer = new MutationObserver(handle);
      observer.observe(document.documentElement,{childList:true,subtree:true,attributes:true,attributeFilter:['class']});
      handle();
      const interval=setInterval(handle,500);
      let resizeObserver;
      try {
        resizeObserver = new ResizeObserver(() => {
          injectResizeStyle();
          triggerFlexyUpdate();
        });
        resizeObserver.observe(document.documentElement);
      } catch (_) {}
      const onResize = () => {
        injectResizeStyle();
        triggerFlexyUpdate();
        requestAnimationFrame(triggerFlexyUpdate);
        setTimeout(triggerFlexyUpdate, 50);
      };
      window.addEventListener('resize', onResize, { passive: true });
      addEventListener('pagehide',()=>{observer.disconnect();if(resizeObserver)resizeObserver.disconnect();clearInterval(interval);},{once:true});
    }; attach();
  })();''',
];
