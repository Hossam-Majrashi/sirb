import 'package:webview_cef/webview_cef.dart';

enum TabPhase { active, background, sleeping }

class BrowserTab {
  BrowserTab({
    required this.id,
    this.url = 'sirb:new',
    this.title = '',
    this.icon = '',
    this.pinned = false,
    this.muted = false,
    DateTime? used,
    this.videoPosition = 0,
  }) : lastUsed = used ?? DateTime.now();
  final String id;
  String url, title, icon;
  bool pinned, muted;
  DateTime lastUsed;
  double videoPosition;
  final Map<String, bool> mediaFrames = {};
  String? loadError;
  // Runtime-only: a new/rebuilt engine must be probed again, not session-restored.
  bool missingStreamCodecs = false;
  // A terminated CEF renderer must be recreated on selection/retry, not reused.
  bool rendererTerminated = false;
  bool media = false, loading = false, canBack = false, canForward = false;
  int blocked = 0;
  double zoom = 0;
  TabPhase phase = TabPhase.sleeping;
  WebViewController? controller;
  Map<String, Object?> toMap() => {
    'id': id,
    'url': url,
    'title': title,
    'icon': icon,
    'pinned': pinned,
    'muted': muted,
    'used': lastUsed.millisecondsSinceEpoch,
    'video': videoPosition,
  };
  factory BrowserTab.fromMap(Map<String, dynamic> m) => BrowserTab(
    id: m['id'] as String,
    url: m['url'] as String,
    title: m['title'] as String? ?? '',
    icon: m['icon'] as String? ?? '',
    pinned: m['pinned'] as bool? ?? false,
    muted: m['muted'] as bool? ?? false,
    used: DateTime.fromMillisecondsSinceEpoch(m['used'] as int? ?? 0),
    videoPosition: (m['video'] as num? ?? 0).toDouble(),
  );
}
