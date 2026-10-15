// Twitch maintenance is independent of YouTube and Kick.
// Client-side ads only: SSAI segments can share the content playlist/CDN.
// Do not block usher.ttvnw.net, *.ttvnw.net, gql.twitch.tv or rewrite tokens,
// workers/playlists: doing so can stall both live streams and VOD seeking.
const twitchBlockedDomains = <String>['ads.twitch.tv'];
const twitchBlockedUrlPatterns = <String>[
  r'^https?://(?:[^/]+\.)?twitch\.tv/(?:ads|advertisements|adserver)(?:[/?#]|$)',
];
const twitchCosmeticSelectors = <String>[
  '.stream-display-ad',
  '[data-a-target="stream-display-ad"]',
];
// Keep video-ad-label/countdown and player controls visible: hiding an SSAI
// indicator does not remove an ad and makes playback look frozen instead.
