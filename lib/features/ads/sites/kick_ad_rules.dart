// Kick-only client-side ad rules; intentionally no player/stream interception.
// Never block *.live-video.net, *.playback.live-video.net, Kick API/auth or
// all /video routes: these can serve the desired live stream and recorded clips.
// Same-stream/server-inserted advertising cannot safely be removed by these
// rules. Add new endpoints only after verifying content playback on the site.
const kickBlockedDomains = <String>[];
const kickBlockedUrlPatterns = <String>[
  r'^https?://(?:[^/]+\.)?kick\.com/(?:api/v[0-9]+/)?(?:ads|advertisements|adserver)(?:[/?#]|$)',
];
const kickCosmeticSelectors = <String>[
  '[data-testid="ad-banner"]',
  '[data-testid="ad-slot"]',
];
