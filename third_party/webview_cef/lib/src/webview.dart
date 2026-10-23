import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'webview_manager.dart';
import 'webview_events_listener.dart';
import 'webview_javascript.dart';
import 'webview_textinput.dart';
import 'webview_tooltip.dart';

// CEF key event types
const int keyEventRawKeyDown = 0;
const int keyEventKeyDown = 1;
const int keyEventKeyUp = 2;
const int keyEventChar = 3;

// CEF event flags
const int eventFlagNone = 0;
const int eventFlagCapsLockOn = 1 << 0;
const int eventFlagShiftDown = 1 << 1;
const int eventFlagControlDown = 1 << 2;
const int eventFlagAltDown = 1 << 3;
const int eventFlagLeftMouseButton = 1 << 4;
const int eventFlagMiddleMouseButton = 1 << 5;
const int eventFlagRightMouseButton = 1 << 6;
const int eventFlagCommandDown = 1 << 7;
const int eventFlagNumLockOn = 1 << 8;
const int eventFlagIsKeyPad = 1 << 9;
const int eventFlagIsLeft = 1 << 10;
const int eventFlagIsRight = 1 << 11;

class WebViewController extends ValueNotifier<bool> {
  WebViewController(this._pluginChannel, this._index,
      {Widget? loading, this.speculative = false})
      : super(false) {
    _loadingWidget = loading;
  }
  final MethodChannel _pluginChannel;
  final bool speculative;
  Widget? _loadingWidget;

  late WebView _webviewWidget;
  Widget get webviewWidget => _webviewWidget;
  Widget get loadingWidget => _loadingWidget ?? const SizedBox.shrink();

  late Completer<void> _creatingCompleter;
  Future<void> get ready => _creatingCompleter.future;
  bool _isDisposed = false;
  bool _focusEditable = false;
  bool? _clientFocus;
  final _frameSize = ValueNotifier<Size>(Size.zero);

  void updateFrameSize(int width, int height) {
    if (!_isDisposed && width > 0 && height > 0) {
      _frameSize.value = Size(width.toDouble(), height.toDouble());
    }
  }

  void updateEditableFocus(bool editable) {
    _focusEditable = editable;
    _onFocusedNodeChangeMessage?.call(editable);
  }

  bool touchpadNaturalScroll = true;
  bool get invertScroll => !touchpadNaturalScroll;
  set invertScroll(bool value) {
    touchpadNaturalScroll = !value;
  }

  final int _index;
  late int _browserId;
  int get browserId => _browserId;
  Future<void> hostControl(String action, Object value) async {
    await ready;
    if (!_isDisposed) {
      await _pluginChannel
          .invokeMethod('sirbControl', [_browserId, action, value.toString()]);
    }
  }

  late int _textureId;
  final Map<String, JavascriptChannel> _javascriptChannels =
      <String, JavascriptChannel>{};
  Map<String, JavascriptChannel> get javascriptChannels => _javascriptChannels;
  WebviewEventsListener? _listener;
  WebviewEventsListener? get listener => _listener;

  Null Function(
          String channelName, String message, String callbackId, String frameId)
      get onJavascriptChannelMessage => (final String channelName,
              final String message,
              final String callbackId,
              final String frameId) {
            if (_javascriptChannels.containsKey(channelName)) {
              _javascriptChannels[channelName]!.onMessageReceived(
                  JavascriptMessage(message, callbackId, frameId));
            } else {
              debugPrint('Channel "$channelName" is not exists');
            }
          };

  dynamic Function(String)? get onToolTip => _onToolTip;
  dynamic Function(int)? get onCursorChanged => _onCursorChanged;
  dynamic Function(bool editable)? get onFocusedNodeChangeMessage =>
      _onFocusedNodeChangeMessage;
  dynamic Function(int, int, int)? get onImeCompositionRangeChangedMessage =>
      _onImeCompositionRangeChangedMessage;

  /// Initializes the underlying platform view.
  Future<void> initialize(String url) async {
    if (_isDisposed) {
      return Future<void>.value();
    }
    _creatingCompleter = Completer<void>();
    try {
      await WebviewManager().ready;
      List args =
          await _pluginChannel.invokeMethod('create', [url, speculative]);
      _browserId = args[0] as int;
      _textureId = args[1] as int;
      WebviewManager().onBrowserCreated(_index, _browserId);
      _webviewWidget = WebView(this, key: ValueKey('cef_browser_$_browserId'));
      value = true;
      _creatingCompleter.complete();
    } on PlatformException catch (e) {
      _creatingCompleter.completeError(e);
    }
    return _creatingCompleter.future;
  }

  void setWebviewListener(WebviewEventsListener listener) {
    _listener = listener;
  }

  @override
  Future<void> dispose() async {
    await _creatingCompleter.future;
    if (_isDisposed) return;
    _isDisposed = true;
    WebviewManager().removeWebView(_browserId);
    await _pluginChannel.invokeMethod('close', _browserId);
    _frameSize.dispose();
    super.dispose();
  }

  /// Loads the given [url].
  Future<void> loadUrl(String url) async {
    if (_isDisposed) {
      return;
    }
    assert(value);
    return _pluginChannel.invokeMethod('loadUrl', [_browserId, url]);
  }

  /// Reloads the current document.
  Future<void> reload() async {
    if (_isDisposed) {
      return;
    }
    assert(value);
    return _pluginChannel.invokeMethod('reload', _browserId);
  }

  Future<void> goForward() async {
    if (_isDisposed) {
      return;
    }
    assert(value);
    return _pluginChannel.invokeMethod('goForward', _browserId);
  }

  Future<void> goBack() async {
    if (_isDisposed) {
      return;
    }
    assert(value);
    return _pluginChannel.invokeMethod('goBack', _browserId);
  }

  Future<void> openDevTools() async {
    if (_isDisposed) {
      return;
    }
    assert(value);
    return _pluginChannel.invokeMethod('openDevTools', _browserId);
  }

  Future<void> imeSetComposition(String composingText) async {
    if (_isDisposed) {
      return;
    }
    assert(value);
    return _pluginChannel
        .invokeMethod('imeSetComposition', [_browserId, composingText]);
  }

  Future<void> imeCommitText(String composingText) async {
    if (_isDisposed) {
      return;
    }
    assert(value);
    return _pluginChannel
        .invokeMethod('imeCommitText', [_browserId, composingText]);
  }

  Future<void> setClientFocus(bool focus) async {
    await ready;
    if (_isDisposed || _clientFocus == focus) return;
    _clientFocus = focus;
    return _pluginChannel.invokeMethod('setClientFocus', [_browserId, focus]);
  }

  /// Sends a key event to CEF. Used on platforms without native key support (eLinux).
  Future<void> sendKeyEvent(int type, int keyCode, int modifiers, int character,
      int unmodifiedCharacter) async {
    if (_isDisposed) {
      return;
    }
    assert(value);
    return _pluginChannel.invokeMethod('sendKeyEvent',
        [_browserId, type, keyCode, modifiers, character, unmodifiedCharacter]);
  }

  Future<void> setJavaScriptChannels(Set<JavascriptChannel> channels) async {
    if (_isDisposed) {
      return;
    }
    assert(value);
    _assertJavascriptChannelNamesAreUnique(channels);

    for (var channel in channels) {
      _javascriptChannels[channel.name] = channel;
    }

    return _pluginChannel.invokeMethod('setJavaScriptChannels',
        [_browserId, _extractJavascriptChannelNames(channels).toList()]);
  }

  Future<void> sendJavaScriptChannelCallBack(
      bool error, String result, String callbackId, String frameId) async {
    if (_isDisposed) {
      return;
    }
    assert(value);
    return _pluginChannel.invokeMethod('sendJavaScriptChannelCallBack',
        [error, result, callbackId, _browserId, frameId]);
  }

  Future<void> executeJavaScript(String code) async {
    if (_isDisposed) {
      return;
    }
    assert(value);
    return _pluginChannel.invokeMethod('executeJavaScript', [_browserId, code]);
  }

  Future<dynamic> evaluateJavascript(String code) async {
    if (_isDisposed) {
      return;
    }
    assert(value);
    return _pluginChannel
        .invokeMethod('evaluateJavascript', [_browserId, code]);
  }

  /// Moves the virtual cursor to [position].
  Future<void> _cursorMove(Offset position) async {
    if (_isDisposed) {
      return;
    }
    assert(value);
    return _pluginChannel.invokeMethod(
        'cursorMove', [_browserId, position.dx.round(), position.dy.round()]);
  }

  Future<void> _cursorDragging(Offset position) async {
    if (_isDisposed) {
      return;
    }
    assert(value);
    return _pluginChannel.invokeMethod('cursorDragging',
        [_browserId, position.dx.round(), position.dy.round()]);
  }

  Future<void> _cursorClickDown(Offset position, {int button = 0}) async {
    if (_isDisposed) {
      return;
    }
    assert(value);
    return _pluginChannel.invokeMethod('cursorClickDown',
        [_browserId, position.dx.round(), position.dy.round(), button]);
  }

  Future<void> _cursorClickUp(Offset position, {int button = 0}) async {
    if (_isDisposed) {
      return;
    }
    assert(value);
    return _pluginChannel.invokeMethod('cursorClickUp',
        [_browserId, position.dx.round(), position.dy.round(), button]);
  }

  /// Sets the horizontal and vertical scroll delta.
  Future<void> _setScrollDelta(Offset position, int dx, int dy) async {
    if (_isDisposed) {
      return;
    }
    assert(value);
    return _pluginChannel.invokeMethod('setScrollDelta',
        [_browserId, position.dx.round(), position.dy.round(), dx, dy]);
  }

  double? _appliedDpi;
  double? _appliedWidth;
  double? _appliedHeight;
  ({double dpi, Size size})? _pendingSize;
  Completer<void>? _sizeUpdate;

  /// Sets the surface size to the provided [size].
  Future<void> setSize(double dpi, Size size) async {
    await ready;
    return _setSize(dpi, size);
  }

  Future<void> _setSize(double dpi, Size size) {
    if (_isDisposed) return Future<void>.value();
    assert(value);
    _pendingSize = (dpi: dpi, size: size);
    final running = _sizeUpdate;
    if (running != null) return running.future;
    final update = Completer<void>();
    _sizeUpdate = update;
    unawaited(_flushSize(update));
    return update.future;
  }

  Future<void> _flushSize(Completer<void> update) async {
    try {
      // A live window drag can change layout faster than the native channel
      // responds. Keep only its latest target instead of queueing stale sizes.
      // The last texture still fills the viewport while CEF catches up.
      while (!_isDisposed && _pendingSize != null) {
        final target = _pendingSize!;
        _pendingSize = null;
        if (_appliedDpi == target.dpi &&
            _appliedWidth == target.size.width &&
            _appliedHeight == target.size.height) {
          continue;
        }
        await _pluginChannel.invokeMethod('setSize',
            [_browserId, target.dpi, target.size.width, target.size.height]);
        // Cache only acknowledged sizes so a failed resize remains retryable.
        _appliedDpi = target.dpi;
        _appliedWidth = target.size.width;
        _appliedHeight = target.size.height;
      }
      _sizeUpdate = null;
      update.complete();
    } catch (error, stack) {
      _pendingSize = null;
      _sizeUpdate = null;
      update.completeError(error, stack);
    }
  }

  Set<String> _extractJavascriptChannelNames(Set<JavascriptChannel> channels) {
    final Set<String> channelNames =
        channels.map((JavascriptChannel channel) => channel.name).toSet();
    return channelNames;
  }

  void _assertJavascriptChannelNamesAreUnique(
      final Set<JavascriptChannel>? channels) {
    if (channels == null || channels.isEmpty) {
      return;
    }
    assert(_extractJavascriptChannelNames(channels).length == channels.length);
  }

  Function(String)? _onToolTip;
  Function(int)? _onCursorChanged;
  Function(bool editable)? _onFocusedNodeChangeMessage;
  Function(int, int, int)? _onImeCompositionRangeChangedMessage;
}

class WebView extends StatefulWidget {
  final WebViewController controller;

  const WebView(this.controller, {super.key});

  @override
  WebViewState createState() => WebViewState();
}

class WebViewState extends State<WebView> with WebeViewTextInput {
  final GlobalKey _key = GlobalKey();
  String _composingText = '';
  late final _focusNode = FocusNode();
  bool isPrimaryFocus = false;
  WebviewTooltip? _tooltip;
  MouseCursor _mouseType = SystemMouseCursors.basic;
  bool? _hasNativeKeySupport;

  WebViewController get _controller => widget.controller;

  @override
  updateEditingValueWithDeltas(List<TextEditingDelta> textEditingDeltas) {
    /// Handles IME composition only
    for (var d in textEditingDeltas) {
      if (d is TextEditingDeltaInsertion) {
        // composing text
        if (d.composing.isValid) {
          _composingText += d.textInserted;
          _controller.imeSetComposition(_composingText);
        } else {
          // Directly committed text (e.g. English typing, or a commit delivered
          // as a plain insertion). Must run on every platform, including Windows.
          _controller.imeCommitText(d.textInserted);
        }
      } else if (d is TextEditingDeltaDeletion) {
        if (d.composing.isValid) {
          if (_composingText == d.textDeleted) {
            _composingText = "";
          }
          _controller.imeSetComposition(_composingText);
        }
      } else if (d is TextEditingDeltaReplacement) {
        if (d.composing.isValid) {
          // Composition is still ongoing (preedit revised).
          _composingText = d.replacementText;
          _controller.imeSetComposition(_composingText);
        } else {
          // Composition finished (a candidate was selected): commit the final
          // text. Without this the selected text was dropped and never shown.
          _controller.imeCommitText(d.replacementText);
          _composingText = '';
        }
      } else if (d is TextEditingDeltaNonTextUpdate) {
        if (_composingText.isNotEmpty) {
          _controller.imeCommitText(_composingText);
          _composingText = '';
        }
      }
    }
  }

  double? _lastWidth;
  double? _lastHeight;
  double? _lastDpi;
  int _lastClickButton = -1;

  @override
  void initState() {
    super.initState();
    _bindController(_controller);

    // Check if platform has native key support (e.g., GTK on desktop Linux)
    WebviewManager().hasNativeKeySupport.then((value) {
      if (mounted) _hasNativeKeySupport = value;
    });

    // Report initial surface size
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _reportSurfaceSize(context));
  }

  @override
  void didUpdateWidget(WebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _tooltip?.dismiss();
      _tooltip = null;
      _unbindController(oldWidget.controller);
      _bindController(widget.controller);
      _hasNativeKeySupport = null;
      WebviewManager().hasNativeKeySupport.then((value) {
        if (mounted) _hasNativeKeySupport = value;
      });
      _lastWidth = null;
      _lastHeight = null;
      _lastDpi = null;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _reportSurfaceSize(context));
    }
  }

  @override
  void dispose() {
    _tooltip?.dismiss();
    _tooltip = null;
    _unbindController(_controller);
    detachTextInputClient();
    // Unmounting must relinquish native keyboard ownership as well as Flutter
    // focus (e.g. a settings route replaces the browser).
    unawaited(_controller.setClientFocus(false));
    _focusNode.dispose();
    super.dispose();
  }

  void _bindController(WebViewController controller) {
    controller._onFocusedNodeChangeMessage = (editable) {
      if (!mounted) return;
      _composingText = '';
      // A document can focus an input while Flutter's address bar or a menu
      // owns focus. Never replace their text-input connection in that case.
      if (editable && _focusNode.hasFocus) {
        attachTextInputClient();
      } else {
        detachTextInputClient();
      }
    };

    controller._onImeCompositionRangeChangedMessage = (x, y, height) {
      final box = _key.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        updateIMEComposionPosition(x.toDouble(), y.toDouble(),
            height.toDouble(), box.localToGlobal(Offset.zero));
      }
    };

    controller._onToolTip = (final String text) {
      if (!mounted) return;
      if (text.isEmpty) {
        _tooltip?.dismiss();
        return;
      }
      if (_key.currentContext != null) {
        _tooltip ??= WebviewTooltip(_key.currentContext!);
        _tooltip?.showToolTip(text);
      }
    };

    controller._onCursorChanged = (int type) {
      switch (type) {
        case 0:
          _mouseType = SystemMouseCursors.basic;
          break;
        case 1:
          _mouseType = SystemMouseCursors.precise;
          break;
        case 2:
          _mouseType = SystemMouseCursors.click;
          break;
        case 3:
          _mouseType = SystemMouseCursors.text;
          break;
        case 4:
          _mouseType = SystemMouseCursors.wait;
          break;
        default:
          _mouseType = SystemMouseCursors.basic;
          break;
      }
      if (mounted) setState(() {});
    };
  }

  void _unbindController(WebViewController controller) {
    _tooltip?.dismiss();
    _tooltip = null;
    controller._onFocusedNodeChangeMessage = null;
    controller._onImeCompositionRangeChangedMessage = null;
    controller._onToolTip = null;
    controller._onCursorChanged = null;
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    // Only handle keys on platforms without native key support (eLinux)
    // Treat null as "don't handle yet" to prevent double-delivery during async gap
    if (_hasNativeKeySupport != false) {
      return KeyEventResult.ignored;
    }

    // Map Flutter key event to CEF key event
    final logicalKey = event.logicalKey;
    final character = event.character;

    // Convert logical key to Windows keycode
    int keyCode = _logicalKeyToWindowsKeyCode(logicalKey);
    if (keyCode == 0) {
      keyCode = _physicalKeyToWindowsKeyCode(event.physicalKey);
    }

    // Build modifiers
    int modifiers = 0;
    if (HardwareKeyboard.instance.isShiftPressed) {
      modifiers |= eventFlagShiftDown;
    }
    if (HardwareKeyboard.instance.isControlPressed) {
      modifiers |= eventFlagControlDown;
    }
    if (HardwareKeyboard.instance.isAltPressed) {
      modifiers |= eventFlagAltDown;
    }

    // Determine event type
    int type;
    if (event is KeyDownEvent) {
      type = keyEventRawKeyDown;
    } else if (event is KeyUpEvent) {
      type = keyEventKeyUp;
    } else {
      return KeyEventResult.ignored;
    }

    // Send key event to CEF
    _controller.sendKeyEvent(
      type,
      keyCode,
      modifiers,
      character?.codeUnitAt(0) ?? 0,
      character?.codeUnitAt(0) ?? 0,
    );

    // Send CHAR event after RAWKEYDOWN when character is present (required for text entry)
    if (event is KeyDownEvent &&
        character != null &&
        !HardwareKeyboard.instance.isControlPressed) {
      _controller.sendKeyEvent(
        keyEventChar,
        keyCode,
        modifiers,
        character.codeUnitAt(0),
        character.codeUnitAt(0),
      );
    }
    return KeyEventResult.handled;
  }

  int _physicalKeyToWindowsKeyCode(PhysicalKeyboardKey key) {
    if (key == PhysicalKeyboardKey.keyA) return 0x41;
    if (key == PhysicalKeyboardKey.keyB) return 0x42;
    if (key == PhysicalKeyboardKey.keyC) return 0x43;
    if (key == PhysicalKeyboardKey.keyD) return 0x44;
    if (key == PhysicalKeyboardKey.keyE) return 0x45;
    if (key == PhysicalKeyboardKey.keyF) return 0x46;
    if (key == PhysicalKeyboardKey.keyG) return 0x47;
    if (key == PhysicalKeyboardKey.keyH) return 0x48;
    if (key == PhysicalKeyboardKey.keyI) return 0x49;
    if (key == PhysicalKeyboardKey.keyJ) return 0x4A;
    if (key == PhysicalKeyboardKey.keyK) return 0x4B;
    if (key == PhysicalKeyboardKey.keyL) return 0x4C;
    if (key == PhysicalKeyboardKey.keyM) return 0x4D;
    if (key == PhysicalKeyboardKey.keyN) return 0x4E;
    if (key == PhysicalKeyboardKey.keyO) return 0x4F;
    if (key == PhysicalKeyboardKey.keyP) return 0x50;
    if (key == PhysicalKeyboardKey.keyQ) return 0x51;
    if (key == PhysicalKeyboardKey.keyR) return 0x52;
    if (key == PhysicalKeyboardKey.keyS) return 0x53;
    if (key == PhysicalKeyboardKey.keyT) return 0x54;
    if (key == PhysicalKeyboardKey.keyU) return 0x55;
    if (key == PhysicalKeyboardKey.keyV) return 0x56;
    if (key == PhysicalKeyboardKey.keyW) return 0x57;
    if (key == PhysicalKeyboardKey.keyX) return 0x58;
    if (key == PhysicalKeyboardKey.keyY) return 0x59;
    if (key == PhysicalKeyboardKey.keyZ) return 0x5A;
    return 0;
  }

  int _logicalKeyToWindowsKeyCode(LogicalKeyboardKey key) {
    // Map Flutter logical keys to Windows key codes
    // This is a simplified mapping - may need to be expanded
    if (key == LogicalKeyboardKey.f12) return 0x7B;
    if (key == LogicalKeyboardKey.f1) return 0x70;
    if (key == LogicalKeyboardKey.f2) return 0x71;
    if (key == LogicalKeyboardKey.f3) return 0x72;
    if (key == LogicalKeyboardKey.f4) return 0x73;
    if (key == LogicalKeyboardKey.f5) return 0x74;
    if (key == LogicalKeyboardKey.f6) return 0x75;
    if (key == LogicalKeyboardKey.f7) return 0x76;
    if (key == LogicalKeyboardKey.f8) return 0x77;
    if (key == LogicalKeyboardKey.f9) return 0x78;
    if (key == LogicalKeyboardKey.f10) return 0x79;
    if (key == LogicalKeyboardKey.f11) return 0x7A;
    if (key == LogicalKeyboardKey.enter) return 0x0D;
    if (key == LogicalKeyboardKey.escape) return 0x1B;
    if (key == LogicalKeyboardKey.tab) return 0x09;
    if (key == LogicalKeyboardKey.backspace) return 0x08;
    if (key == LogicalKeyboardKey.delete) return 0x2E;
    if (key == LogicalKeyboardKey.insert) return 0x2D;
    if (key == LogicalKeyboardKey.home) return 0x24;
    if (key == LogicalKeyboardKey.end) return 0x23;
    if (key == LogicalKeyboardKey.pageUp) return 0x21;
    if (key == LogicalKeyboardKey.pageDown) return 0x22;
    if (key == LogicalKeyboardKey.arrowUp) return 0x26;
    if (key == LogicalKeyboardKey.arrowDown) return 0x28;
    if (key == LogicalKeyboardKey.arrowLeft) return 0x25;
    if (key == LogicalKeyboardKey.arrowRight) return 0x27;

    // Explicit A-Z
    if (key == LogicalKeyboardKey.keyA) return 0x41;
    if (key == LogicalKeyboardKey.keyB) return 0x42;
    if (key == LogicalKeyboardKey.keyC) return 0x43;
    if (key == LogicalKeyboardKey.keyD) return 0x44;
    if (key == LogicalKeyboardKey.keyE) return 0x45;
    if (key == LogicalKeyboardKey.keyF) return 0x46;
    if (key == LogicalKeyboardKey.keyG) return 0x47;
    if (key == LogicalKeyboardKey.keyH) return 0x48;
    if (key == LogicalKeyboardKey.keyI) return 0x49;
    if (key == LogicalKeyboardKey.keyJ) return 0x4A;
    if (key == LogicalKeyboardKey.keyK) return 0x4B;
    if (key == LogicalKeyboardKey.keyL) return 0x4C;
    if (key == LogicalKeyboardKey.keyM) return 0x4D;
    if (key == LogicalKeyboardKey.keyN) return 0x4E;
    if (key == LogicalKeyboardKey.keyO) return 0x4F;
    if (key == LogicalKeyboardKey.keyP) return 0x50;
    if (key == LogicalKeyboardKey.keyQ) return 0x51;
    if (key == LogicalKeyboardKey.keyR) return 0x52;
    if (key == LogicalKeyboardKey.keyS) return 0x53;
    if (key == LogicalKeyboardKey.keyT) return 0x54;
    if (key == LogicalKeyboardKey.keyU) return 0x55;
    if (key == LogicalKeyboardKey.keyV) return 0x56;
    if (key == LogicalKeyboardKey.keyW) return 0x57;
    if (key == LogicalKeyboardKey.keyX) return 0x58;
    if (key == LogicalKeyboardKey.keyY) return 0x59;
    if (key == LogicalKeyboardKey.keyZ) return 0x5A;

    // Digits
    if (key == LogicalKeyboardKey.digit0) return 0x30;
    if (key == LogicalKeyboardKey.digit1) return 0x31;
    if (key == LogicalKeyboardKey.digit2) return 0x32;
    if (key == LogicalKeyboardKey.digit3) return 0x33;
    if (key == LogicalKeyboardKey.digit4) return 0x34;
    if (key == LogicalKeyboardKey.digit5) return 0x35;
    if (key == LogicalKeyboardKey.digit6) return 0x36;
    if (key == LogicalKeyboardKey.digit7) return 0x37;
    if (key == LogicalKeyboardKey.digit8) return 0x38;
    if (key == LogicalKeyboardKey.digit9) return 0x39;

    // For alphanumeric keys, use the key label
    final keyLabel = key.keyLabel;
    if (keyLabel.length == 1) {
      final charCode = keyLabel.codeUnitAt(0);
      if (charCode >= 0x41 && charCode <= 0x5A) {
        // A-Z
        return charCode;
      }
      if (charCode >= 0x30 && charCode <= 0x39) {
        // 0-9
        return charCode;
      }
    }

    // Default fallback
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      focusNode: _focusNode,
      canRequestFocus: true,
      debugLabel: "webview_cef",
      onFocusChange: (focused) {
        _composingText = '';
        if (focused) {
          _controller.setClientFocus(true);
          if (_controller._focusEditable) {
            attachTextInputClient();
          }
        } else {
          _controller.setClientFocus(false);
          if (_controller._focusEditable) {
            detachTextInputClient();
          }
        }
      },
      onKeyEvent: _onKeyEvent,
      child: SizedBox.expand(key: _key, child: _buildInner()),
    );
  }

  Widget _buildInner() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        if (width > 0 && height > 0 && width.isFinite && height.isFinite) {
          final dpi = MediaQuery.of(context).devicePixelRatio;
          if (_lastWidth != width || _lastHeight != height || _lastDpi != dpi) {
            _lastWidth = width;
            _lastHeight = height;
            _lastDpi = dpi;
            if (_controller.value) {
              unawaited(_controller._setSize(dpi, Size(width, height)));
            } else {
              _controller.ready.then((_) {
                if (mounted && _controller.value) {
                  unawaited(_controller._setSize(dpi, Size(width, height)));
                }
              });
            }
          }
        }
        return Listener(
          onPointerHover: (ev) {
            _controller._cursorMove(ev.localPosition);
            _tooltip?.cursorOffset = ev.position;
          },
          onPointerDown: (ev) {
            _tooltip?.dismiss();
            final buttons = ev.buttons;
            // Ignore mouse navigation / auxiliary buttons (Back: 0x08, Forward: 0x10) or any non-standard button.
            // These buttons are dedicated to page navigation and must never trigger clicks, selection, or focus in CEF.
            if ((buttons & kBackMouseButton) != 0 ||
                (buttons & kForwardMouseButton) != 0) {
              _lastClickButton = -1;
              return;
            }
            if ((buttons & kPrimaryMouseButton) != 0) {
              _lastClickButton = 0;
            } else if ((buttons & kMiddleMouseButton) != 0) {
              _lastClickButton = 1;
            } else if ((buttons & kSecondaryMouseButton) != 0) {
              _lastClickButton = 2;
            } else {
              _lastClickButton = -1;
              return;
            }

            if (!_focusNode.hasFocus) {
              _controller._onImeCompositionRangeChangedMessage?.call(0, 0, 0);
              _focusNode.requestFocus();
              // Focus is applied by Flutter at the end of this frame. No
              // delayed retry: it could steal focus back from an address field.
            }
            _controller._cursorClickDown(ev.localPosition,
                button: _lastClickButton);
          },
          onPointerUp: (ev) {
            if (_lastClickButton != -1) {
              _controller._cursorClickUp(ev.localPosition,
                  button: _lastClickButton);
              _lastClickButton = -1;
            }
          },
          onPointerMove: (ev) {
            // A secondary-button move must not masquerade as a left drag.
            if (_lastClickButton == 0) {
              _controller._cursorDragging(ev.localPosition);
            } else {
              _controller._cursorMove(ev.localPosition);
            }
          },
          onPointerCancel: (ev) {
            if (_lastClickButton != -1) {
              _controller._cursorClickUp(ev.localPosition,
                  button: _lastClickButton);
              _lastClickButton = -1;
            }
          },
          onPointerSignal: (signal) {
            _tooltip?.dismiss();
            if (signal is PointerScrollEvent) {
              final isTrackpad = signal.kind == PointerDeviceKind.trackpad;
              double dx = -signal.scrollDelta.dx;
              double dy = -signal.scrollDelta.dy;
              if (isTrackpad && !_controller.touchpadNaturalScroll) {
                dx = -dx;
                dy = -dy;
              }
              _controller._setScrollDelta(
                signal.localPosition,
                dx.round(),
                dy.round(),
              );
            }
          },
          onPointerPanZoomUpdate: (event) {
            _tooltip?.dismiss();
            final double dx;
            final double dy;
            if (_controller.touchpadNaturalScroll) {
              dx = event.panDelta.dx;
              dy = event.panDelta.dy;
            } else {
              dx = -event.panDelta.dx;
              dy = -event.panDelta.dy;
            }
            _controller._setScrollDelta(
              event.localPosition,
              dx.round(),
              dy.round(),
            );
          },
          child: MouseRegion(
            cursor: _mouseType,
            onExit: (_) {
              _tooltip?.dismiss();
            },
            child: ValueListenableBuilder<Size>(
              valueListenable: _controller._frameSize,
              builder: (context, frameSize, _) {
                if (frameSize.isEmpty) return const SizedBox.expand();
                // CEF paints asynchronously. Fill the current viewport with
                // the last real frame immediately, without letterbox gaps while
                // Chromium produces the resized frame. Keep actual frame sizes
                // for the texture; never clear it on a resize request.
                return ClipRect(
                  child: FittedBox(
                    fit: BoxFit.fill,
                    alignment: Alignment.topLeft,
                    child: SizedBox.fromSize(
                      size: frameSize,
                      child: Texture(textureId: _controller._textureId),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _reportSurfaceSize(BuildContext context) async {
    final dpi = MediaQuery.of(context).devicePixelRatio;
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box != null &&
        box.hasSize &&
        box.size.width > 0 &&
        box.size.height > 0) {
      final size = box.size;
      if (_lastWidth != size.width ||
          _lastHeight != size.height ||
          _lastDpi != dpi) {
        _lastWidth = size.width;
        _lastHeight = size.height;
        _lastDpi = dpi;
        await _controller.ready;
        if (mounted) {
          unawaited(_controller._setSize(dpi, size));
        }
      }
    }
  }
}
