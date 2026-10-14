import 'package:flutter_test/flutter_test.dart';
import 'package:webview_cef/webview_cef.dart';

void main() {
  test('InjectUserScripts filters scripts by injection time', () {
    final scripts = InjectUserScripts()
      ..add(UserScript('start-1', ScriptInjectTime.LOAD_START))
      ..add(UserScript('end-1', ScriptInjectTime.LOAD_END))
      ..add(UserScript('start-2', ScriptInjectTime.LOAD_START));

    expect(
      scripts.retrieveLoadStartInjectScripts().map((s) => s.script),
      ['start-1', 'start-2'],
    );
    expect(
      scripts.retrieveLoadEndInjectScripts().map((s) => s.script),
      ['end-1'],
    );
  });

  test('JavascriptChannel rejects invalid channel names', () {
    expect(
      () => JavascriptChannel(name: '1invalid', onMessageReceived: (_) {}),
      throwsA(isA<AssertionError>()),
    );
    expect(
      JavascriptChannel(name: 'validName', onMessageReceived: (_) {}).name,
      'validName',
    );
  });

  test('WebviewManager accepts an omitted injectUserScripts argument', () {
    final manager = WebviewManager();
    final browserIndex = manager.nextIndex;
    final browserId = browserIndex + 1000;

    expect(manager.createWebView(), isA<WebViewController>());
    expect(
      () => manager.onBrowserCreated(browserIndex, browserId),
      returnsNormally,
    );

    manager.removeWebView(browserId);
  });

  test('WebViewController touchpadNaturalScroll and invertScroll stay synchronized', () {
    final manager = WebviewManager();
    final controller = manager.createWebView();
    expect(controller.touchpadNaturalScroll, isTrue);
    expect(controller.invertScroll, isFalse);

    controller.touchpadNaturalScroll = false;
    expect(controller.touchpadNaturalScroll, isFalse);
    expect(controller.invertScroll, isTrue);

    controller.invertScroll = false;
    expect(controller.touchpadNaturalScroll, isTrue);
    expect(controller.invertScroll, isFalse);
  });
}
