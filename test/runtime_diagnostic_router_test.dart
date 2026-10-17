import 'package:flutter_test/flutter_test.dart';
import 'package:sirb/features/home/services/runtime_diagnostic_router.dart';

void main() {
  late RuntimeDiagnosticRouter router;
  late List<Map<String, dynamic>> records;
  late DateTime clock;
  const source = 'https://static.doubleclick.net/instream/ad_status.js';
  const page = 'https://www.youtube.com/watch?v=fixture';
  Map<String, dynamic> resource([String url = source]) => {
    'category': 'network',
    'message': 'Document resource failed',
    'source': url,
    'resourceTag': 'SCRIPT',
  };
  Map<String, dynamic> resize({bool console = false}) => {
    'category': 'javascript',
    'message': 'ResizeObserver loop completed with undelivered notifications.',
    'source': page,
    'line': 0,
    if (console) 'severity': 4,
  };
  void record(Map<String, dynamic> event, [String scope = 'tab-1']) =>
      router.record(event, scope: scope, fallbackUrl: page);

  setUp(() {
    records = [];
    clock = DateTime(2026, 10, 17);
    router = RuntimeDiagnosticRouter(
      emit: (event, _) => records.add(event),
      now: () => clock,
      resourceDelay: const Duration(milliseconds: 10),
    );
  });
  tearDown(() => router.dispose());

  String preloadMessage(String resource) =>
      'The resource $resource was preloaded using link preload but not used within a few seconds '
      "from the window's load event. Please make sure it has an appropriate `as` value and it is preloaded intentionally.";

  test('unused preload is an advisory, coalesced per host/page/resource', () {
    final warning = {
      'category': 'javascript',
      'severity': 3,
      'message': preloadMessage('https://i.ytimg.com/generate_204'),
    };
    record(warning);
    clock = clock.add(const Duration(seconds: 6));
    record(warning);
    expect(records, hasLength(1));
    expect(records.single['category'], 'performance');
    expect(records.single['resource'], 'https://i.ytimg.com/generate_204');
    expect(records.single['advisory'], true);
    record(warning, 'tab-2');
    record({...warning, 'url': 'https://www.youtube.com/watch?v=other'});
    record({
      ...warning,
      'message': preloadMessage('https://i.ytimg.com/vi/fixture/hqdefault.jpg'),
    });
    expect(records, hasLength(4));
    clock = clock.add(const Duration(seconds: 30));
    record(warning);
    expect(records, hasLength(5));
    router.resetScope('tab-1');
    record(warning);
    expect(records, hasLength(6));
  });

  test('preload advice cannot hide real errors or near-matching messages', () {
    final message = preloadMessage('https://i.ytimg.com/generate_204');
    record({'category': 'javascript', 'severity': 4, 'message': message});
    record({
      'category': 'javascript',
      'severity': 3,
      'message': '$message Additional failure',
    });
    record({'category': 'network', 'message': message, 'httpStatus': 403});
    record({
      'category': 'network',
      'message': 'Resource request failed',
      'httpStatus': 200,
      'code': -2,
      'requestStatus': 4,
      'receivedBytes': 128,
      'diagnostic': 'responseBodyTransferFailed',
    });
    expect(records, hasLength(4));
    expect(records.take(2).every((r) => r['category'] == 'javascript'), true);
    expect(records.last['category'], 'network');
    expect(records.last['diagnostic'], 'responseBodyTransferFailed');
    expect(records.last['receivedBytes'], 128);
  });

  test('known YouTube probes retain original diagnostics as visible notices', () {
    record({
      'category': 'javascript',
      'message': 'No available adapters.',
      'source': page,
      'severity': 3,
      'line': 0,
    });
    record({
      'category': 'javascript',
      'message':
          "Blocked script execution in 'about:blank' because the document's frame is sandboxed and the 'allow-scripts' permission is not set.",
      'source': 'https://www.youtube.com/s/_/ytmainappweb/_/js/test-module',
      'severity': 4,
      'line': 17593,
    });
    expect(records.map((r) => r['category']), [
      'compatibility',
      'compatibility',
    ]);
    expect(records.map((r) => r['originalCategory']), [
      'graphics',
      'permission',
    ]);
    expect(records[0]['capabilityProbe'], true);
    expect(records[1]['expectedProtection'], true);
    expect(records[1]['line'], 17593);
    expect(records.every((r) => r['advisory'] == true), true);
  });

  test(
    'notice scope cannot downgrade unrelated sites, scripts or real failures',
    () {
      for (final url in [
        'https://game.test/watch',
        'https://youtube.com.evil.test/watch',
        'http://www.youtube.com/watch',
        'file:///youtube.com/watch',
        'https://www.youtube.com/playables',
      ]) {
        record({
          'category': 'javascript',
          'message': 'No available adapters.',
          'source': url,
          'url': url,
          'severity': 3,
        });
      }
      record({
        'category': 'javascript',
        'message': 'No available adapters.',
        'source': 'https://www.youtube.com/game-worker.js',
        'severity': 3,
      });
      record({
        'category': 'javascript',
        'message': 'No available adapters.',
        'source': page,
        'severity': 4,
      });
      for (final source in [
        'chrome-extension://test/script.js',
        'https://evil.test/script.js',
        'https://www.youtube.com/unrelated-script.js',
        '',
      ]) {
        record({
          'category': 'javascript',
          'message':
              "Blocked script execution in 'about:blank' because the document's frame is sandboxed and the 'allow-scripts' permission is not set.",
          'source': source,
          'severity': 4,
        });
      }
      record({
        'category': 'graphics',
        'message': 'No available adapters.',
        'source': page,
        'severity': 3,
        'operation': 'GPUAdapter.requestDevice',
      });
      record({
        'category': 'graphics',
        'message': 'GPU device lost',
        'source': page,
      });
      record({
        'category': 'permission',
        'message': 'Pointer lock denied',
        'source': page,
      });
      record({
        'category': 'network',
        'message': 'Resource request failed',
        'httpStatus': 403,
      });
      expect(records, hasLength(15));
      expect(records.every((r) => r['category'] != 'compatibility'), true);
      expect(records.last['httpStatus'], 403);
    },
  );

  test(
    'observer/console resize echo coalesces, real repeated loops remain',
    () {
      record(resize());
      record(resize(console: true));
      expect(records, hasLength(1));
      expect(
        records.single['diagnostic'],
        'resizeObserverDeferredNotifications',
      );
      expect(records.single['recoverable'], true);
      record(resize());
      expect(
        records,
        hasLength(2),
        reason: 'Same capture path can be a new real loop',
      );
      clock = clock.add(const Duration(seconds: 2));
      record(resize(console: true));
      record(resize());
      expect(
        records,
        hasLength(3),
        reason: 'Reverse capture order also coalesces',
      );
      record(resize(), 'tab-2');
      record({...resize(), 'source': 'https://other.test/frame'});
      expect(
        records,
        hasLength(5),
        reason: 'Do not merge hosts or source documents',
      );
    },
  );

  test(
    'native-confirmed ad cancellation keeps only its native ad record',
    () async {
      router.blocked('tab-1', source);
      record(resource());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(records, isEmpty);
    },
  );

  test(
    'DOM error can precede native cancellation; unconfirmed failures survive',
    () async {
      record(resource());
      router.blocked('tab-1', source);
      record(resource('https://real.test/missing.js'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(records, hasLength(1));
      expect(records.single['source'], 'https://real.test/missing.js');
    },
  );

  test(
    'ad URLs alone and other-host evidence cannot hide a failed resource',
    () async {
      router.blocked('tab-2', source);
      record(resource());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(records, hasLength(1));
    },
  );

  test('expired or reset evidence cannot suppress a later failure', () async {
    router.blocked('tab-1', source);
    clock = clock.add(const Duration(seconds: 3));
    record(resource());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    router.blocked('tab-1', source);
    router.resetScope('tab-1');
    record(resource());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(records, hasLength(2));
  });

  test(
    'HTTP, media and fetch failures survive even with matching evidence',
    () {
      router.blocked('tab-1', source);
      record({...resource(), 'httpStatus': 403});
      record({...resource(), 'code': -2});
      record({
        ...resource(),
        'message': 'Resource request failed',
        'operation': 'GET',
      });
      record({...resource(), 'category': 'media'});
      expect(records, hasLength(4));
    },
  );

  test(
    'reset/shutdown flushes genuine pending errors instead of losing them',
    () {
      record(resource());
      router.resetScope('tab-1');
      expect(records, hasLength(1));
      record(resource());
      router.dispose();
      expect(records, hasLength(2));
      record(resource());
      expect(records, hasLength(2));
    },
  );

  test(
    'GPU capability and frame permission warnings remain visible and typed',
    () {
      record({
        'category': 'javascript',
        'message': 'No available adapters.',
        'severity': 3,
      });
      record({
        'category': 'javascript',
        'message':
            "Blocked script execution in 'about:blank' because the document's frame is sandboxed and the 'allow-scripts' permission is not set.",
      });
      expect(records[0]['category'], 'graphics');
      expect(records[0]['capabilityProbe'], true);
      expect(records[1]['category'], 'permission');
      expect(records[1]['expectedProtection'], true);
      record({
        'category': 'javascript',
        'message': 'No available adapters.',
        'severity': 4,
      });
      record({'category': 'graphics', 'message': 'GPU device lost'});
      record({'category': 'javascript', 'message': 'A real script exception'});
      expect(records.skip(2).map((r) => r['category']), [
        'javascript',
        'graphics',
        'javascript',
      ]);
    },
  );

  test(
    'retained fields are bounded and arbitrary payloads discarded',
    () async {
      record({
        ...resource(),
        'details': 'x' * 20000,
        'untrustedObject': {'nested': 'x' * 20000},
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect((records.single['details'] as String).length, 8192);
      expect(records.single.containsKey('untrustedObject'), false);
      record(resource(source + 'x' * 9000));
      expect(
        records,
        hasLength(2),
        reason: 'Oversized source must not enter correlation',
      );
      expect((records.last['source'] as String).length, 8192);
    },
  );

  test(
    'bounded resource queue fails open to recording rather than dropping',
    () {
      for (var i = 0; i < 300; i++) {
        record(resource('https://real.test/missing-$i.js'));
      }
      router.dispose();
      expect(records, hasLength(300));
    },
  );
}
