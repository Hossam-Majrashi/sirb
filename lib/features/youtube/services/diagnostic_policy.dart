// Only the two known YouTube console diagnostics are compatibility notices.
// Do not downgrade missing-GPU failures in games, denied user API operations,
// extension injections, other sites, or unrelated scripts on a YouTube page.
// Keep an explicit browsing-route allowlist: a YouTube origin alone also covers
// Playables and other applications where an unavailable adapter can be a fault.
final _shortsPage = RegExp(r'^/shorts/[\w-]{11}/?$');
final _channelPage = RegExp(
  r'^/@[^/]+(?:/(?:featured|videos|shorts|streams|playlists|community|about))?/?$',
);

bool _isBrowsingPage(String path) =>
    const {'/', '/watch', '/results', '/feed/subscriptions'}.contains(path) ||
    _shortsPage.hasMatch(path) ||
    _channelPage.hasMatch(path);

bool isYouTubeCompatibilityNotice({
  required String diagnostic,
  required String pageUrl,
  required String source,
  required Object? severity,
}) {
  final page = Uri.tryParse(pageUrl);
  final script = Uri.tryParse(source);
  bool youtube(Uri? url) =>
      url != null &&
      url.scheme == 'https' &&
      const {'youtube.com', 'www.youtube.com'}.contains(url.host);
  if (!youtube(page) || !youtube(script) || !_isBrowsingPage(page!.path)) {
    return false;
  }
  return switch (diagnostic) {
    'webgpuAdapterUnavailable' => severity == 3 && script!.path == page.path,
    'frameSandboxBlockedScript' =>
      severity == 4 && script!.path.startsWith('/s/_/ytmainappweb/_/js/'),
    _ => false,
  };
}
