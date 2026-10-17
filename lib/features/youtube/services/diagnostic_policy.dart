// Only the two known YouTube console diagnostics are compatibility notices.
// Do not downgrade missing-GPU failures in games, denied user API operations,
// extension injections, other sites, or unrelated scripts on a YouTube page.
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
  if (!youtube(page) ||
      !youtube(script) ||
      !const {'/', '/watch'}.contains(page!.path)) {
    return false;
  }
  return switch (diagnostic) {
    'webgpuAdapterUnavailable' => severity == 3 && script!.path == page.path,
    'frameSandboxBlockedScript' =>
      severity == 4 && script!.path.startsWith('/s/_/ytmainappweb/_/js/'),
    _ => false,
  };
}
