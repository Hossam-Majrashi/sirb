// Shared rule registry; site-specific maintenance lives in sites/.
// Bare domains include subdomains. URL patterns use ECMAScript syntax.
// Keep desired media CDNs, player APIs, playlists and auth available.
import 'sites/kick_ad_rules.dart';
import 'sites/twitch_ad_rules.dart';
import 'sites/youtube_ad_rules.dart';

export 'sites/youtube_ad_rules.dart' show youtubeScripts;

const blockedDomains = <String>[
  'doubleclick.net',
  'googlesyndication.com',
  'googleadservices.com',
  'adservice.google.com',
  ...youtubeBlockedDomains,
  ...twitchBlockedDomains,
  ...kickBlockedDomains,
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
  ...youtubeBlockedUrlPatterns,
  ...twitchBlockedUrlPatterns,
  ...kickBlockedUrlPatterns,
  r'^https?://[^/]+/(ads|advertisements|adserver)/',
  r'^https?://(?:[^/]+\.)?dailymotion\.com/[^#]*/ads/',
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
  'youtube.com': youtubeCosmeticSelectors,
  'twitch.tv': twitchCosmeticSelectors,
  'kick.com': kickCosmeticSelectors,
  'vimeo.com': ['.vp-ad', '.ad-container'],
  'dailymotion.com': ['.ad-container', '[data-testid="ad-banner"]'],
};
