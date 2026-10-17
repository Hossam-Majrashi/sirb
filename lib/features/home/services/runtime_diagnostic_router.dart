import 'dart:async';

import '../../youtube/services/diagnostic_policy.dart';

const resizeObserverDiagnostics = {
  'ResizeObserver loop completed with undelivered notifications.',
  'ResizeObserver loop limit exceeded',
};

// Diagnostic routing only: never patch website observers, permissions or GPU
// APIs. Preserve actual failures; correlate only the DOM echo of a confirmed
// native ad cancellation in the same host, with bounded short-lived evidence.
class RuntimeDiagnosticRouter {
  RuntimeDiagnosticRouter({
    required this.emit,
    DateTime Function()? now,
    this.resourceDelay = const Duration(milliseconds: 150),
  }) : _now = now ?? DateTime.now;

  final void Function(Map<String, dynamic>, String?) emit;
  final DateTime Function() _now;
  final Duration resourceDelay;
  final _blocks = <(String, String), DateTime>{};
  final _resize =
      <(String, String, String, num), ({DateTime at, bool console})>{};
  final _preloads = <(String, String, String), DateTime>{};
  static final _unusedPreload = RegExp(
    r'^The resource (https?://\S+) was preloaded using link preload but not used '
    r"within a few seconds from the window's load event\. Please make sure it has "
    r'an appropriate `as` value and it is preloaded intentionally\.$',
  );
  final _pending = <int, _PendingResource>{};
  int _sequence = 0;
  bool _disposed = false;

  void blocked(String scope, String source) {
    if (_disposed || source.isEmpty || source.length > 8192) return;
    _blocks.removeWhere((_, at) => _now().difference(at).inSeconds >= 2);
    _blocks[(scope, source)] = _now();
    while (_blocks.length > 256) {
      _blocks.remove(_blocks.keys.first);
    }
  }

  bool _confirmed((String, String) key) {
    final at = _blocks[key];
    return at != null && _now().difference(at) < const Duration(seconds: 2);
  }

  void record(
    Map<String, dynamic> input, {
    required String scope,
    String? fallbackUrl,
  }) {
    if (_disposed || input['message'] is! String) return;
    // Bound retained payloads before they enter the asynchronous resource
    // queue. Website telemetry must not keep arbitrary nested objects alive.
    final event = <String, dynamic>{};
    for (final key in const [
      'category',
      'message',
      'url',
      'source',
      'operation',
      'line',
      'column',
      'severity',
      'code',
      'status',
      'httpStatus',
      'requestStatus',
      'receivedBytes',
      'diagnostic',
      'resourceTag',
      'reason',
      'main',
      'frameUrl',
      'details',
    ]) {
      final value = input[key];
      if (value is String) {
        final limit = key == 'message' ? 4096 : 8192;
        event[key] = value.length > limit ? value.substring(0, limit) : value;
      } else if (value is bool || value is num && value.isFinite) {
        event[key] = value;
      }
    }
    final message = event['message'] as String;
    if (event['category'] == 'javascript') {
      final preload = event['severity'] == 3
          ? _unusedPreload.firstMatch(message)
          : null;
      if (preload != null) {
        final resource = preload.group(1)!;
        final url = event['url'] is String
            ? event['url'] as String
            : fallbackUrl ?? '';
        if (url.length <= 8192) {
          final key = (scope, url, resource);
          final at = _now();
          final previous = _preloads[key];
          // Keep a real diagnostic per resource/document, not a warning every few
          // seconds while the user intentionally leaves playback paused.
          if (previous != null &&
              !at.difference(previous).isNegative &&
              at.difference(previous) < const Duration(seconds: 30)) {
            return;
          }
          _preloads.removeWhere(
            (_, time) => at.difference(time).inSeconds >= 30,
          );
          _preloads[key] = at;
          while (_preloads.length > 256) {
            _preloads.remove(_preloads.keys.first);
          }
        }
        event.addAll({
          'category': 'performance',
          'diagnostic': 'unusedPreload',
          'advisory': true,
          'resource': resource,
          'coalescingWindowSeconds': 30,
          'reason':
              'A site preload was not consumed promptly; this is not proof of a failed download. Playback and site preload policies were not changed.',
        });
      } else if (resizeObserverDiagnostics.contains(message)) {
        event.addAll({
          'diagnostic': 'resizeObserverDeferredNotifications',
          'recoverable': true,
          'reason':
              'Notifications deferred to a later frame; repeated events can indicate a layout loop.',
        });
        final url = event['url'] is String
            ? event['url'] as String
            : fallbackUrl ?? '';
        final source =
            event['source'] is String && (event['source'] as String).isNotEmpty
            ? event['source'] as String
            : url;
        final line = event['line'] is num ? event['line'] as num : 0;
        if (url.length <= 8192 && source.length <= 8192) {
          final key = (scope, url, source, line);
          final at = _now();
          final console = event['severity'] is num;
          final previous = _resize[key];
          // Only coalesce the two capture paths, not successive real observer
          // events from the same path. Keep the first event and its metadata.
          if (previous != null &&
              previous.console != console &&
              at.difference(previous.at) < const Duration(seconds: 1)) {
            return;
          }
          _resize.removeWhere(
            (_, value) => at.difference(value.at).inSeconds >= 1,
          );
          _resize[key] = (at: at, console: console);
          while (_resize.length > 256) {
            _resize.remove(_resize.keys.first);
          }
        }
      } else if (message == 'No available adapters.' &&
          event['severity'] == 3) {
        event.addAll({
          'category': 'graphics',
          'diagnostic': 'webgpuAdapterUnavailable',
          'capabilityProbe': true,
          'reason':
              'Chromium exposed no WebGPU adapter; this alone does not establish a WebGL or video-decoder failure.',
        });
        _compatibilityNotice(event, fallbackUrl);
      } else if (message ==
          "Blocked script execution in 'about:blank' because the document's frame is sandboxed and the 'allow-scripts' permission is not set.") {
        event.addAll({
          'category': 'permission',
          'diagnostic': 'frameSandboxBlockedScript',
          'expectedProtection': true,
          'reason':
              'The frame intentionally disallows scripts; its sandbox permissions were not changed.',
        });
        _compatibilityNotice(event, fallbackUrl);
      }
    }
    // Do not infer ad cancellation from a hostname or current rule match.
    // HTTP errors, fetches, media failures and unconfirmed DOM errors remain.
    final source = event['source'];
    if (event['category'] == 'network' &&
        message == 'Document resource failed' &&
        event['resourceTag'] is String &&
        source is String &&
        source.isNotEmpty &&
        (input['source'] as String).length <= 8192 &&
        !event.containsKey('httpStatus') &&
        !event.containsKey('code')) {
      final key = (scope, source);
      if (_confirmed(key)) {
        return; // The native 'blocked' ad record is retained.
      }
      if (_pending.length < 128) {
        final id = _sequence++;
        final pending = _PendingResource(scope, key, event, fallbackUrl);
        _pending[id] = pending;
        pending.timer = Timer(resourceDelay, () => _finish(id));
        return;
      }
    }
    emit(event, fallbackUrl);
  }

  void _compatibilityNotice(Map<String, dynamic> event, String? fallbackUrl) {
    if (!isYouTubeCompatibilityNotice(
      diagnostic: event['diagnostic'] as String,
      pageUrl: event['url'] is String
          ? event['url'] as String
          : fallbackUrl ?? '',
      source: event['source'] is String ? event['source'] as String : '',
      severity: event['severity'],
    )) {
      return;
    }
    // Retain the original message, severity, category and source. A notice
    // neither grants permissions nor proves that playback/graphics is healthy.
    event['originalCategory'] = event['category'];
    event['category'] = 'compatibility';
    event['advisory'] = true;
  }

  void _finish(int id) {
    final pending = _pending.remove(id);
    if (pending == null) return;
    pending.timer.cancel();
    if (!_confirmed(pending.key)) emit(pending.event, pending.url);
  }

  // Flush genuine pending failures before dropping a document's evidence.
  void resetScope(String scope) {
    for (final id in _pending.keys.toList()) {
      if (_pending[id]!.scope == scope) _finish(id);
    }
    _blocks.removeWhere((key, _) => key.$1 == scope);
    _resize.removeWhere((key, _) => key.$1 == scope);
    _preloads.removeWhere((key, _) => key.$1 == scope);
  }

  void reset() {
    for (final id in _pending.keys.toList()) {
      _finish(id);
    }
    _blocks.clear();
    _resize.clear();
    _preloads.clear();
  }

  void dispose() {
    if (_disposed) return;
    reset();
    _disposed = true;
  }
}

class _PendingResource {
  _PendingResource(this.scope, this.key, this.event, this.url);
  final String scope;
  final (String, String) key;
  final Map<String, dynamic> event;
  final String? url;
  late final Timer timer;
}
