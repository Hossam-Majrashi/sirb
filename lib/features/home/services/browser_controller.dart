import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_cef/webview_cef.dart';
import '../../../shared/models/browser_tab.dart';
import '../../../shared/models/device_info.dart';
import '../../../shared/services/browser_engine.dart';
import '../../../shared/services/browser_store.dart';
import '../../../shared/services/resource_service.dart';
import '../../settings/services/preferences_service.dart';
import '../../settings/models/search_engine.dart';
import '../models/address_target.dart';
import 'page_features.dart';
import 'runtime_error_policy.dart';
import 'runtime_diagnostic_router.dart';

class BrowserController extends ChangeNotifier {
  BrowserController({
    required this.store,
    required this.engine,
    required this.preferences,
    required this.resources,
  }) {
    unawaited(updateTouchpadSettings());
  }
  final BrowserStore store;
  final BrowserEngine engine;
  final PreferencesService preferences;
  final ResourceService resources;
  final List<BrowserTab> tabs = [];
  final Map<String, BrowserTab> _preloads = {};
  final Map<String, Timer> _expiry = {};
  late final _diagnostics = RuntimeDiagnosticRouter(
    emit: (event, url) => _persistRuntimeError(event, fallbackUrl: url),
  );
  final Set<String> _creating = {};
  final Map<String, Future<void>> _wakeTasks = {}, _sleepTasks = {};
  int _activationEpoch = 0;
  int? gameWindowId;
  bool _openingGameWindow = false;
  String activeId = '';
  bool pressure = false, fullscreen = false;
  ResourceUsage usage = const ResourceUsage(0, 0);
  String? error;
  Size viewportSize = const Size(1280, 720);
  double viewportDpi = 1.0;
  Timer? _timer;
  bool _ticking = false, _closing = false, _mutating = false;
  bool _loadingBackground = false;
  final Set<String> _backgroundQueue = {};
  int _sequence = 0;
  Future<void> Function(bool)? onFullscreen;
  void Function(BrowserTab tab, Map<String, dynamic> event)? onContextMenu;
  BrowserTab? get active => tabs.where((t) => t.id == activeId).firstOrNull;
  int get liveCount =>
      tabs
          .where((t) => t.controller != null || _creating.contains(t.id))
          .length +
      _preloads.length +
      (gameWindowId == null ? 0 : 1);
  String _id() => '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';

  void detectInitialViewport() {
    final view = WidgetsBinding.instance.platformDispatcher.views.firstOrNull;
    if (view != null &&
        view.physicalSize.width > 0 &&
        view.physicalSize.height > 0) {
      final dpi = view.devicePixelRatio > 0 ? view.devicePixelRatio : 1.0;
      final w = (view.physicalSize.width / dpi) - 260.0;
      final h = (view.physicalSize.height / dpi) - 50.0;
      viewportDpi = dpi;
      viewportSize = Size(w.clamp(400.0, 3840.0), h.clamp(300.0, 2160.0));
    }
  }

  void updateViewport(Size size, double dpi) {
    if (size.width > 0 &&
        size.height > 0 &&
        (viewportSize != size || viewportDpi != dpi)) {
      viewportSize = size;
      viewportDpi = dpi;
      final current = active;
      if (current != null &&
          current.controller != null &&
          current.controller!.value) {
        unawaited(current.controller!.setSize(dpi, size));
      }
    }
  }

  String resolve(String text) {
    final target = AddressTarget.parse(text);
    if (target.kind != AddressKind.search) return target.value;
    return SearchEngine.duckduckgo.search(target.value).toString();
  }

  Future<bool> initialize({bool forceRestore = false}) async {
    detectInitialViewport();
    WebviewManager().onNativeEvent = _nativeEvent;
    await engine.initialize();
    _engineReady = true;
    await preferences.set('clean_shutdown', false);
    final saved = await store.session();
    final restore = forceRestore || preferences.startup == 'restore';
    if (saved != null) {
      final savedList = (saved['tabs'] as List)
          .map(
            (item) =>
                BrowserTab.fromMap(Map<String, dynamic>.from(item as Map)),
          )
          .where((t) => t.url.isNotEmpty && t.url != 'sirb:new')
          .toList();
      if (savedList.isNotEmpty) {
        await store.recordClosure(savedList);
      }
      if (restore || preferences.startup == 'ask') {
        for (final item in saved['tabs'] as List) {
          tabs.add(BrowserTab.fromMap(Map<String, dynamic>.from(item as Map)));
        }
        activeId = saved['active'] as String;
        if (tabs.isNotEmpty && active == null) activeId = tabs.first.id;
      }
    }
    if (tabs.isEmpty) {
      tabs.add(BrowserTab(id: _id()));
      activeId = tabs.first.id;
    }
    if (restore || preferences.startup != 'ask' || saved == null) {
      await activate(activeId);
    }
    _timer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_tick()),
    );
    return saved != null && preferences.startup == 'ask' && !forceRestore;
  }

  Future<void> answerRestore(bool restore) async {
    if (!restore) {
      await store.recordClosure(tabs);
      tabs.clear();
      tabs.add(BrowserTab(id: _id()));
      activeId = tabs.first.id;
    }
    await activate(activeId);
  }

  void changed() {
    if (_closing) return;
    notifyListeners();
    if (!_closing && !_mutating) {
      unawaited(
        store.saveSession(tabs, activeId).catchError((Object e) {
          error = e.toString();
          notifyListeners();
        }),
      );
    }
  }

  Future<void> add({
    String url = 'sirb:new',
    bool activateTab = true,
    String? openerId,
  }) async {
    final resolved = resolve(url);
    final cached = _preloads.remove(resolved);
    _expiry.remove(resolved)?.cancel();
    final tab = cached ?? BrowserTab(id: _id(), url: resolved);
    final openerIndex = tabs.indexWhere((t) => t.id == (openerId ?? activeId));
    tabs.insert(openerIndex < 0 ? tabs.length : openerIndex + 1, tab);
    if (activateTab) {
      await activate(tab.id);
    } else {
      _backgroundQueue.add(tab.id);
      changed();
      unawaited(_loadBackground());
    }
  }

  // User-requested background pages load without focus and within the same
  // host/RAM budget as foreground and speculative pages. Limit creation bursts.
  Future<void> _loadBackground() async {
    if (_loadingBackground || _closing || _mutating || !_engineReady) return;
    _loadingBackground = true;
    try {
      // Explicit user opens take priority over hover speculation.
      if (_backgroundQueue.isNotEmpty && _preloads.isNotEmpty) {
        await clearPreloads();
      }
      while (_backgroundQueue.isNotEmpty &&
          !_closing &&
          !_mutating &&
          !pressure) {
        _backgroundQueue.removeWhere((id) => !tabs.any((t) => t.id == id));
        final slots = preferences.liveLimit - liveCount;
        if (slots <= 0) break;
        final batch = tabs
            .where((t) => _backgroundQueue.contains(t.id))
            .take(slots.clamp(0, 2))
            .toList();
        if (batch.isEmpty) break;
        for (final tab in batch) {
          _backgroundQueue.remove(tab.id);
        }
        await Future.wait(
          batch.where((t) => t.url != 'sirb:new').map((t) => _wake(t)),
        );
      }
    } finally {
      _loadingBackground = false;
    }
  }

  bool _engineReady = false;

  Future<void> openBatch(
    List<String> links, {
    bool activateFirst = true,
  }) async {
    final validLinks = links
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (validLinks.isEmpty) return;

    bool firstReplaced = false;
    if (tabs.length == 1 && active?.url == 'sirb:new') {
      final first = tabs.first;
      first.url = resolve(validLinks.first);
      firstReplaced = true;
      if (!activateFirst) _backgroundQueue.add(first.id);
      if (activateFirst) {
        if (first.controller != null) {
          await first.controller!.loadUrl(first.url);
        } else {
          await _wake(first);
        }
      }
    }

    final toAdd = firstReplaced ? validLinks.skip(1) : validLinks;
    String? firstAddedId;
    final openerIndex = tabs.indexWhere((t) => t.id == activeId);
    var insertIndex = openerIndex < 0 ? tabs.length : openerIndex + 1;
    for (final link in toAdd) {
      final tab = BrowserTab(id: _id(), url: resolve(link));
      tabs.insert(insertIndex++, tab);
      _backgroundQueue.add(tab.id);
      firstAddedId ??= tab.id;
    }

    if (activateFirst && !firstReplaced && firstAddedId != null) {
      await activate(firstAddedId);
    } else {
      changed();
    }
    unawaited(_loadBackground());
  }

  Future<void> navigate(String text) async {
    final tab = active;
    if (tab == null) {
      await add(url: text);
      return;
    }
    final url = resolve(text);
    final cached = _preloads.remove(url);
    _expiry.remove(url)?.cancel();
    if (cached != null) {
      final index = tabs.indexOf(tab);
      await tab.controller?.dispose();
      cached.pinned = tab.pinned;
      cached.phase = TabPhase.active;
      tabs[index] = cached;
      activeId = cached.id;
      await activate(cached.id);
      return;
    }
    tab.url = url;
    tab.title = '';
    tab.icon = '';
    tab.blocked = 0;
    tab.missingStreamCodecs = false;
    tab.videoPosition = 0;
    if (url == 'sirb:new') {
      await tab.controller?.dispose();
      tab.controller = null;
      tab.phase = TabPhase.active;
    } else if (tab.controller == null) {
      await _wake(tab);
    } else {
      await tab.controller!.setSize(viewportDpi, viewportSize);
      await tab.controller!.loadUrl(url);
    }
    changed();
  }

  Future<void> activate(String id) async {
    final next = tabs.where((t) => t.id == id).firstOrNull;
    if (next == null) return;
    final epoch = ++_activationEpoch;
    bool current() =>
        !_closing && epoch == _activationEpoch && tabs.contains(next);
    _backgroundQueue.remove(id);
    activeId = id;
    next.lastUsed = DateTime.now();
    next.phase = TabPhase.active;
    // Show selection/loading immediately, even while another hidden renderer's
    // media snapshot or native host initialization is still in flight.
    notifyListeners();
    for (final tab in tabs.toList()) {
      if (tab == next) continue;
      if (tab.controller != null) {
        tab.phase = TabPhase.background;
        await tab.controller!.hostControl('hidden', !tab.media);
        if (!current()) return;
        await tab.controller?.setClientFocus(false);
        if (!current()) return;
      }
    }
    if (next.url != 'sirb:new') await _wake(next);
    if (!current()) return;
    await _updateScripts(next);
    if (!current()) return;
    if (next.controller != null && next.controller!.value) {
      await next.controller!.setSize(viewportDpi, viewportSize);
    }
    if (!current()) return;
    await next.controller?.hostControl('hidden', false);
    if (!current()) return;
    await next.controller?.hostControl('muted', next.muted);
    if (!current()) return;
    // The mounted WebView's Flutter Focus node grants keyboard focus. Do not
    // claim it here while the address bar/find field may still be in use.
    await _enforce();
    if (current()) changed();
  }

  /// Reload must also work for a sleeping/failed host. Do not send Reload to a
  /// retired controller or leave the error UI mounted over a recovered page.
  Future<void> reload({BrowserTab? tab}) async {
    final target = tab ?? active;
    if (_closing ||
        target == null ||
        target.url == 'sirb:new' ||
        !tabs.contains(target)) {
      return;
    }
    final reuse = target.controller != null && !target.rendererTerminated;
    await _wake(target);
    final c = target.controller;
    if (_closing || !tabs.contains(target) || c == null) return;
    target.loadError = null;
    target.loading = true;
    changed();
    await c.setSize(viewportDpi, viewportSize);
    if (!identical(target.controller, c) || _closing) return;
    await c.hostControl('hidden', target.id != activeId && !target.media);
    if (reuse && identical(target.controller, c)) await c.reload();
  }

  Future<void> _wake(BrowserTab tab, {bool speculative = false}) {
    final pending = _wakeTasks[tab.id];
    if (pending != null) return pending;
    if (tab.controller != null && !tab.rendererTerminated) {
      return tab.controller!.ready;
    }
    late final Future<void> task;
    task = _createTab(tab, speculative: speculative).whenComplete(() {
      if (identical(_wakeTasks[tab.id], task)) _wakeTasks.remove(tab.id);
    });
    _wakeTasks[tab.id] = task;
    return task;
  }

  Future<void> _createTab(BrowserTab tab, {required bool speculative}) async {
    // A tab may have been selected after sleep detached its controller but
    // before its close request completed. Join retirement before allocating
    // the replacement; CEF may still deliver late callbacks until OnBeforeClose.
    await _sleepTasks[tab.id];
    if (_closing || (!tabs.contains(tab) && !_preloads.containsValue(tab))) {
      return;
    }
    final retired = tab.controller;
    if (retired != null) {
      tab.controller = null;
      await retired.dispose();
    }
    if (_closing || (!tabs.contains(tab) && !_preloads.containsValue(tab))) {
      return;
    }
    _creating.add(tab.id);
    final targetUrl = tab.url;
    var restorePosition = tab.videoPosition;
    final c = WebviewManager().createWebView(
      loading: const Center(child: CircularProgressIndicator()),
      speculative: speculative,
    );
    c.touchpadNaturalScroll = _systemTouchpadNatural;
    tab.controller = c;
    tab.rendererTerminated = false;
    tab.loadError = null;
    tab.loading = true;
    bool ownsHost() =>
        !_closing &&
        identical(tab.controller, c) &&
        (tabs.contains(tab) || _preloads.containsValue(tab));
    notifyListeners();
    c.setWebviewListener(
      WebviewEventsListener(
        onUrlChanged: (url) {
          if (!ownsHost()) return;
          if (url != 'about:blank') {
            final changedUrl = tab.url != url;
            tab.url = url;
            if (changedUrl) tab.videoPosition = 0;
            if (changedUrl && !tab.loading && c.value && tabs.contains(tab)) {
              unawaited(store.recordVisit(tab));
            }
            changed();
          }
        },
        onTitleChanged: (title) {
          if (!ownsHost()) return;
          tab.title = title;
          if (tabs.contains(tab)) unawaited(store.updateVisitMetadata(tab));
          changed();
        },
        onLoadStart: (_, url) {
          if (!ownsHost()) return;
          _diagnostics.resetScope(tab.id);
          tab.loading = true;
          tab.loadError = null;
          tab.missingStreamCodecs = false;
          tab.mediaFrames.clear();
          tab.media = false;
          tab.blocked = 0;
          unawaited(_updateScripts(tab));
          changed();
        },
        onLoadEnd: (_, url) {
          if (!ownsHost() || url == 'about:blank') return;
          tab.loading = false;
          unawaited(_updateScripts(tab));
          if (restorePosition > 0) {
            final position = restorePosition;
            restorePosition = 0;
            unawaited(
              c.executeJavaScript(
                '''(() => { const position=$position; let tries=0;
            const restore=()=>{const video=document.querySelector('video');if(video&&video.readyState>0){try{video.currentTime=position;}catch(_){}}else if(++tries<40)setTimeout(restore,250);};restore();})();''',
              ),
            );
          }
          if (tabs.contains(tab)) unawaited(store.recordVisit(tab));
          changed();
        },
        onConsoleMessage: (level, message, source, line) {
          if (!ownsHost()) return;
          if (!message.startsWith('__sirb__')) {
            if (level >= 3 && level <= 5) {
              _recordRuntimeError(
                {
                  'category': 'javascript',
                  'message': message,
                  'source': source,
                  'line': line,
                  'severity': level,
                },
                fallbackUrl: tab.url,
                scope: tab.id,
              );
            }
            return;
          }
          try {
            final event = jsonDecode(message.substring(8));
            if (event is Map<String, dynamic>) _event(tab, event);
          } on FormatException {
            return;
          } on TypeError {
            // Malformed website telemetry must not break browser chrome.
            return;
          }
        },
      ),
    );
    var initialized = false;
    try {
      await c.initialize('about:blank');
      initialized = true;
      await c.setSize(viewportDpi, viewportSize);
      await c.hostControl('theme', engine.colorScheme);
      await c.hostControl('muted', speculative || tab.muted);
      final shouldHide = tab.id != activeId && (speculative || !tab.media);
      await c.hostControl('hidden', shouldHide);
      if (!ownsHost()) {
        await c.dispose();
        if (identical(tab.controller, c)) tab.controller = null;
        return;
      }
      await c.loadUrl(targetUrl);
      tab.phase = tab.id == activeId ? TabPhase.active : TabPhase.background;
    } catch (e) {
      error = e.toString();
      if (identical(tab.controller, c)) {
        tab.controller = null;
        tab.loading = false;
        tab.loadError = e.toString();
      }
      if (initialized) await c.dispose();
      unawaited(
        store.recordErrorLog(
          type: 'system',
          message: e.toString(),
          url: targetUrl,
          details: 'Failed to create browser tab',
        ),
      );
    } finally {
      _creating.remove(tab.id);
      if (!_closing && tab.id == activeId && tab.controller != null) {
        unawaited(tab.controller!.hostControl('hidden', false));
        unawaited(tab.controller!.hostControl('muted', tab.muted));
      }
    }
    changed();
  }

  Future<void> openGameWindow() async {
    final tab = active;
    if (_closing || _openingGameWindow || tab == null || gameWindowId != null) {
      throw StateError('Only one native game window can be open');
    }
    final url = tab.url;
    _openingGameWindow = true;
    try {
      await clearPreloads();
      gameWindowId = await engine.openGameWindow(url);
      // Release the OSR game heap/workers after a successful handoff, not
      // before: if window creation fails the original tab remains usable.
      if (tabs.contains(tab) && tab.url == url) {
        await store.recordVisit(tab);
        await tab.controller?.dispose();
        tab.controller = null;
        tab.url = 'sirb:new';
        tab.title = '';
        tab.icon = '';
        tab.blocked = 0;
        tab.canBack = false;
        tab.canForward = false;
        tab.zoom = 0;
        tab.media = false;
        tab.mediaFrames.clear();
        tab.loading = false;
        tab.loadError = null;
        tab.missingStreamCodecs = false;
        tab.videoPosition = 0;
        tab.phase = TabPhase.sleeping;
      }
      changed();
    } finally {
      _openingGameWindow = false;
    }
  }

  void _recordRuntimeError(
    Map<String, dynamic> event, {
    String? fallbackUrl,
    String? scope,
  }) {
    if (_closing) return;
    _diagnostics.record(
      event,
      scope:
          scope ?? 'native:${event['windowId'] ?? gameWindowId ?? 'unknown'}',
      fallbackUrl: fallbackUrl,
    );
  }

  void _persistRuntimeError(Map<String, dynamic> event, {String? fallbackUrl}) {
    if (event['message'] is! String) return;
    String bounded(String value, int max) =>
        value.length <= max ? value : value.substring(0, max);
    final message = bounded(event['message'] as String, 4096);
    if (message.trim().isEmpty) return;
    const categories = {
      'javascript',
      'graphics',
      'media',
      'permission',
      'performance',
      'compatibility',
      'network',
      'crash',
    };
    final category = categories.contains(event['category'])
        ? event['category'] as String
        : 'javascript';
    if ((category == 'javascript' || category == 'media') &&
        isExpectedPlaybackDiagnostic(message)) {
      return;
    }
    final details = <String, Object>{};
    for (final key in [
      'operation',
      'source',
      'line',
      'column',
      'severity',
      'code',
      'status',
      'httpStatus',
      'requestStatus',
      'receivedBytes',
      'resource',
      'advisory',
      'originalCategory',
      'coalescingWindowSeconds',
      'resourceTag',
      'diagnostic',
      'recoverable',
      'capabilityProbe',
      'expectedProtection',
      'reason',
      'main',
      'frameUrl',
      'details',
    ]) {
      final value = event[key];
      if (value is String) details[key] = bounded(value, 8192);
      if (value is num && value.isFinite || value is bool) {
        details[key] = value as Object;
      }
    }
    final url = event['url'] is String ? event['url'] as String : fallbackUrl;
    unawaited(
      store
          .recordErrorLog(
            type: category,
            message: message,
            url: url == null ? null : bounded(url, 8192),
            details: details.isEmpty
                ? null
                : bounded(jsonEncode(details), 16384),
          )
          .catchError((Object error) {
            debugPrint('Sirb diagnostic storage failed: $error');
          }),
    );
  }

  void _nativeEvent(Map<String, dynamic> event) {
    if (_closing) return;
    switch (event['type']) {
      case 'gameWindowOpened':
        if (event['windowId'] is int) {
          gameWindowId = event['windowId'] as int;
          changed();
        }
      case 'gameWindowClosed':
        _diagnostics.resetScope('native:${event['windowId']}');
        if (gameWindowId == event['windowId']) {
          gameWindowId = null;
          changed();
        }
      case 'runtimeError':
        _recordRuntimeError(event);
      case 'loadError':
      case 'renderCrash':
        _recordRuntimeError({
          ...event,
          'category': event['type'] == 'loadError' ? 'network' : 'crash',
          'message': event['error'] is String
              ? event['error']
              : 'Native game renderer failed',
        });
      case 'blocked':
      case 'adError':
        if (event['type'] == 'blocked' && event['url'] is String) {
          _diagnostics.blocked(
            'native:${event['windowId'] ?? gameWindowId ?? 'unknown'}',
            event['url'] as String,
          );
        }
        unawaited(
          store.recordErrorLog(
            type: 'ad',
            message: event['message'] as String? ?? 'Blocked ad request',
            url: event['page'] as String? ?? event['url'] as String?,
            details: event['url'] as String?,
          ),
        );
      case 'popup':
        if (event['url'] is String) {
          unawaited(
            add(
              url: event['url'] as String,
              activateTab: event['background'] != true,
            ),
          );
        }
    }
  }

  void _event(BrowserTab tab, Map<String, dynamic> event) {
    if (_closing) return;
    switch (event['type']) {
      case 'runtimeError':
        _recordRuntimeError(event, fallbackUrl: tab.url, scope: tab.id);
        return;
      case 'loadError':
        tab.loadError = event['error'] as String;
        tab.loading = false;
        unawaited(
          store.recordErrorLog(
            type: 'network',
            message: tab.loadError!,
            url: event['url'] as String? ?? tab.url,
            details: jsonEncode({
              'code': event['code'],
              'details': event['details'],
            }),
          ),
        );
      case 'renderCrash':
        tab.loadError = event['error'] as String;
        tab.rendererTerminated = true;
        tab.loading = false;
        tab.media = false;
        tab.mediaFrames.clear();
        unawaited(
          store.recordErrorLog(
            type: 'crash',
            message: tab.loadError!,
            url: tab.url,
            details: jsonEncode({
              'status': event['status'],
              'code': event['code'],
            }),
          ),
        );
      case 'blocked':
        tab.blocked++;
        final blockedUrl = event['url'] as String? ?? '';
        _diagnostics.blocked(tab.id, blockedUrl);
        final pageUrl = (event['page'] as String?)?.isNotEmpty == true
            ? event['page'] as String
            : tab.url;
        unawaited(
          store.recordErrorLog(
            type: 'ad',
            message: 'Blocked ad request',
            url: pageUrl,
            details: blockedUrl.isNotEmpty ? blockedUrl : 'Ad rule matched',
          ),
        );
      case 'adError':
        unawaited(
          store.recordErrorLog(
            type: 'ad',
            message:
                event['message'] as String? ?? 'Ad blocking issue detected',
            url: tab.url,
            details: event['details'] as String?,
          ),
        );
      case 'favicon':
        tab.icon = event['url'] as String;
        if (tabs.contains(tab)) unawaited(store.updateVisitMetadata(tab));
      case 'navigation':
        tab.loading = event['loading'] as bool;
        tab.canBack = event['back'] as bool;
        tab.canForward = event['forward'] as bool;
      case 'streamCompatibility':
        final host = Uri.tryParse(tab.url)?.host ?? '';
        if (event['main'] != true ||
            ![
              'twitch.tv',
              'kick.com',
            ].any((site) => host == site || host.endsWith('.$site')) ||
            event['h264'] is! bool ||
            event['aac'] is! bool) {
          return;
        }
        final missing = event['h264'] != true || event['aac'] != true;
        if (tab.missingStreamCodecs == missing) return;
        tab.missingStreamCodecs = missing;
        if (missing) {
          _recordRuntimeError({
            'category': 'media',
            'message': 'This CEF engine lacks H.264 or AAC MSE support',
            'operation': 'streamCodecProbe',
            'details': jsonEncode({'h264': event['h264'], 'aac': event['aac']}),
          }, fallbackUrl: tab.url);
        }
      case 'media':
        final wasPlaying = tab.media;
        tab.mediaFrames[event['frame'] as String? ?? 'main'] =
            event['playing'] as bool;
        tab.media = tab.mediaFrames.values.any((playing) => playing);
        if (event['main'] == true && event['playing'] == true) {
          tab.videoPosition = (event['position'] as num).toDouble();
        }
        if (tab.media && !wasPlaying && tab.controller != null) {
          unawaited(tab.controller!.hostControl('hidden', false));
          if (_preloads.containsValue(tab)) {
            unawaited(_discardPreload(tab.url));
          }
        }
        // Position snapshots don't alter the chrome. Avoid rebuilding the
        // entire workspace for every video timeupdate (several times/second).
        if (tab.media == wasPlaying) return;
        if (!tab.media && tab.id != activeId) {
          unawaited(tab.controller?.hostControl('hidden', true));
        }
      case 'fullscreen':
        if (tab.id == activeId) {
          fullscreen = event['value'] as bool;
          unawaited(onFullscreen?.call(fullscreen));
        }
      case 'hover':
        unawaited(preload(event['url'] as String));
      case 'navigate':
        if (event['newTab'] == true) {
          unawaited(
            add(
              url: event['url'] as String,
              activateTab: event['background'] != true,
              openerId: tab.id,
            ),
          );
        } else if (tab.id == activeId) {
          unawaited(navigate(event['url'] as String));
        }
      case 'popup':
        unawaited(
          add(
            url: event['url'] as String,
            activateTab: event['background'] != true,
            openerId: tab.id,
          ),
        );
      case 'download':
        unawaited(store.saveDownload(event));
      case 'contextMenu':
        if (tab.id == activeId) {
          onContextMenu?.call(tab, event);
        }
    }
    notifyListeners();
  }

  Future<void> sleep(BrowserTab tab) {
    final pending = _sleepTasks[tab.id];
    if (pending != null) return pending;
    late final Future<void> task;
    task = _sleep(tab).whenComplete(() {
      if (identical(_sleepTasks[tab.id], task)) _sleepTasks.remove(tab.id);
    });
    _sleepTasks[tab.id] = task;
    return task;
  }

  Future<void> _sleep(BrowserTab tab) async {
    if (tab.media ||
        tab.id == activeId ||
        tab.controller == null ||
        _creating.contains(tab.id)) {
      return;
    }
    final c = tab.controller!;
    // Re-check immediately before destruction: a new playback event can arrive during snapshotting.
    try {
      final state = await c
          .evaluateJavascript(
            "JSON.stringify(Array.from(document.querySelectorAll('video,audio')).map(v=>({playing:!v.paused&&!v.ended,position:v.currentTime})))",
          )
          .timeout(const Duration(seconds: 2));
      if (!identical(tab.controller, c) || state is! String) return;
      final items = jsonDecode(state) as List;
      if (items.any((v) => v['playing'] == true)) {
        tab.media = true;
        return;
      }
      if (items.isNotEmpty) {
        tab.videoPosition = (items.first['position'] as num).toDouble();
      }
    } catch (_) {
      return;
    }
    if (tab.media ||
        tab.id == activeId ||
        !identical(tab.controller, c) ||
        !tabs.contains(tab)) {
      return;
    }
    tab.controller = null;
    tab.phase = TabPhase.sleeping;
    tab.loading = false;
    changed();
    await c.dispose();
    // Do not write tab state after close: activation may already be waiting
    // to recreate it. All late callbacks are rejected by host identity.
  }

  Future<void> _enforce() async {
    final lru =
        tabs
            .where((t) => t.id != activeId && !t.media && t.controller != null)
            .toList()
          ..sort((a, b) => a.lastUsed.compareTo(b.lastUsed));
    if (pressure || liveCount > preferences.liveLimit) await clearPreloads();
    for (final tab in lru) {
      final idle =
          preferences.idleMinutes > 0 &&
          DateTime.now().difference(tab.lastUsed).inMinutes >=
              preferences.idleMinutes;
      if (idle || pressure || liveCount > preferences.liveLimit) {
        await sleep(tab);
        if (pressure) {
          usage = await resources.usage();
          pressure =
              preferences.ramGb > 0 &&
              usage.ramBytes >= preferences.ramGb * 1073741824 * .85;
        }
      }
    }
  }

  Future<void> _tick() async {
    if (_ticking || _closing || _mutating) return;
    _ticking = true;
    try {
      usage = await resources.usage();
      if (_mutating || _closing) return;
      pressure =
          preferences.ramGb > 0 &&
          usage.ramBytes >= preferences.ramGb * 1073741824 * .85;
      await _enforce();
      unawaited(_loadBackground());
      if (_mutating || _closing) return;
      await store.saveSession(tabs, activeId);
      notifyListeners();
    } catch (e) {
      error = e.toString();
      notifyListeners();
    } finally {
      _ticking = false;
    }
  }

  Future<void> preload(String url) async {
    if (!preferences.preload ||
        pressure ||
        liveCount >= preferences.liveLimit ||
        _preloads.length >= preferences.preloadLimit ||
        _preloads.containsKey(url)) {
      return;
    }
    final parsed = Uri.tryParse(url);
    if (parsed == null || !['http', 'https'].contains(parsed.scheme)) return;
    if (tabs.any((t) => t.url == url && t.controller != null)) return;
    final tab = BrowserTab(id: _id(), url: url);
    _preloads[url] = tab;
    await _wake(tab, speculative: true);
    if (_preloads[url] == tab) {
      _expiry[url] = Timer(
        const Duration(seconds: 25),
        () => unawaited(_discardPreload(url)),
      );
    }
  }

  Future<void> _discardPreload(String url) async {
    _expiry.remove(url)?.cancel();
    final tab = _preloads.remove(url);
    if (tab != null) _diagnostics.resetScope(tab.id);
    await tab?.controller?.dispose();
  }

  Future<void> clearPreloads() async {
    for (final url in _preloads.keys.toList()) {
      await _discardPreload(url);
    }
  }

  Future<void> closeTabs(List<BrowserTab> selection) async {
    if (selection.isEmpty) return;
    final ordered = tabs.where(selection.contains).toList();
    if (_mutating) return;
    _mutating = true;
    final oldIndex = tabs.indexWhere((t) => t.id == activeId);
    final remaining = tabs.where((t) => !ordered.contains(t)).toList();
    if (remaining.isEmpty) remaining.add(BrowserTab(id: _id()));
    final next = remaining.any((t) => t.id == activeId)
        ? activeId
        : remaining[oldIndex.clamp(0, remaining.length - 1)].id;
    try {
      await store.commitClosure(ordered, remaining, next);
    } catch (e) {
      _mutating = false;
      error = e.toString();
      notifyListeners();
      return;
    }
    for (final tab in ordered) {
      _diagnostics.resetScope(tab.id);
      tabs.remove(tab);
      await tab.controller?.dispose();
    }
    if (tabs.isEmpty) tabs.add(remaining.first);
    _mutating = false;
    if (active == null) await activate(next);
    changed();
    unawaited(_loadBackground());
  }

  Future<void> restore(List<dynamic> snapshot) async {
    BrowserTab? last;
    for (final m in snapshot) {
      final map = Map<String, dynamic>.from(m as Map)..['id'] = _id();
      last = BrowserTab.fromMap(map);
      tabs.add(last);
    }
    if (last != null) await activate(last.id);
    changed();
  }

  Future<void> restoreLast() async {
    final rows = await store.closures();
    if (rows.isEmpty) return;
    await restore(jsonDecode(rows.first['snapshot'] as String) as List);
    await store.removeClosure(rows.first['id'] as int);
  }

  Future<void> mute(BrowserTab tab) async {
    tab.muted = !tab.muted;
    await tab.controller?.hostControl('muted', tab.muted);
    changed();
  }

  void pin(BrowserTab tab) {
    tab.pinned = !tab.pinned;
    tabs.sort(
      (a, b) => a.pinned == b.pinned
          ? 0
          : a.pinned
          ? -1
          : 1,
    );
    changed();
  }

  void reorder(int oldIndex, int newIndex) {
    final tab = tabs.removeAt(oldIndex);
    tabs.insert(newIndex, tab);
    changed();
  }

  bool _systemTouchpadNatural = true;
  bool get systemTouchpadNatural => _systemTouchpadNatural;

  Future<void> updateTouchpadSettings() async {
    try {
      _systemTouchpadNatural = await resources.isTouchpadNaturalScrolling();
    } catch (_) {
      _systemTouchpadNatural = true;
    }
    for (final tab in [...tabs, ..._preloads.values]) {
      tab.controller?.touchpadNaturalScroll = _systemTouchpadNatural;
    }
  }

  Future<void> goBack() async {
    final c = active?.controller;
    if (c != null && c.value) {
      unawaited(
        c.executeJavaScript('window.getSelection()?.removeAllRanges();'),
      );
      await c.goBack();
    }
  }

  Future<void> goForward() async {
    final c = active?.controller;
    if (c != null && c.value) {
      unawaited(
        c.executeJavaScript('window.getSelection()?.removeAllRanges();'),
      );
      await c.goForward();
    }
  }

  Future<void> applyTheme(String scheme) async {
    if (engine.colorScheme == scheme) return;
    engine.colorScheme = scheme;
    await engine.configure();
    for (final tab in [...tabs, ..._preloads.values]) {
      await tab.controller?.hostControl('theme', scheme);
      await _updateScripts(tab);
    }
  }

  Future<void> _updateScripts(BrowserTab tab) async {
    final c = tab.controller;
    if (c == null || !c.value) return;
    final speculative = _preloads.containsValue(tab);
    final enabled = engine.blocker.enabledFor(tab.url);
    final flags =
        'window.__sirbSpeculative=$speculative;window.__sirbBlocking=$enabled;window.__sirbPreload=${preferences.preload};'
        '${pageFeatures(focusLoading: preferences.focusLoading, youtubeOriginalTitles: preferences.youtubeOriginalTitles)}';
    await c.hostControl(
      'scripts',
      jsonEncode({
        'speculative': speculative,
        'runtime':
            "${flags}if(document.documentElement && document.documentElement.style.colorScheme!==${jsonEncode(engine.colorScheme)})document.documentElement.style.colorScheme=${jsonEncode(engine.colorScheme)};${enabled ? engine.blocker.documentScript : "document.getElementById('sirb-cosmetic')?.remove();"}",
      }),
    );
  }

  Future<void> reconfigure() async {
    _diagnostics.reset();
    await engine.configure();
    await clearPreloads();
    for (final tab in tabs) {
      await _updateScripts(tab);
    }
  }

  Future<void> shutdown() async {
    _diagnostics.dispose();
    _closing = true;
    _timer?.cancel();
    // Host creation/retirement may still be in flight even with a null tab
    // controller. Do not let engine shutdown overtake those native operations.
    await Future.wait([..._wakeTasks.values, ..._sleepTasks.values]);
    await store.saveSession(tabs, activeId);
    await store.recordClosure(tabs);
    await preferences.set('clean_shutdown', true);
    await clearPreloads();
    for (final tab in tabs) {
      await tab.controller?.dispose();
      tab.controller = null;
    }
  }

  @override
  void dispose() {
    WebviewManager().onNativeEvent = null;
    _diagnostics.dispose();
    _closing = true;
    _backgroundQueue.clear();
    _timer?.cancel();
    super.dispose();
  }
}
