import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import '../../core/l10n/app_localizations.dart';
import '../../features/home/services/browser_controller.dart';
import '../../features/home/widgets/address_bar.dart';
import '../../features/home/widgets/new_tab_page.dart';
import '../../features/home/widgets/tab_rail.dart';
import '../../shared/models/browser_tab.dart';
import '../../shared/models/device_info.dart';
import '../../shared/services/app_runtime.dart';
import '../../shared/widgets/desktop_context_menu.dart';
import 'downloads_screen.dart';
import 'error_logs_screen.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({
    super.key,
    required this.browser,
    required this.runtime,
    required this.device,
    this.arguments = const [],
  });
  final BrowserController browser;
  final AppRuntime runtime;
  final DeviceInfo device;
  final List<String> arguments;
  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> with WindowListener {
  final addressFocus = FocusNode(), findFocus = FocusNode();
  final findText = TextEditingController();
  final _webviewKey = GlobalKey();
  bool ready = false, collapsed = false, findOpen = false;
  String? failure;
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    widget.browser.onFullscreen = (value) => windowManager.setFullScreen(value);
    widget.browser.onContextMenu = (tab, event) =>
        unawaited(_showContextMenu(tab, event));
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      final p = widget.browser.preferences,
          force = p.storage.getBool('force_restore') ?? false;
      await p.set('force_restore', false);
      final ask = await widget.browser.initialize(forceRestore: force);
      if (!mounted) return;
      setState(() => ready = true);
      if (ask) {
        final l = AppLocalizations.of(context);
        final answer = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Text(l.restoreSession),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l.no),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l.yes),
              ),
            ],
          ),
        );
        await widget.browser.answerRestore(answer == true);
      }
      for (final url in widget.arguments.where(
        (a) => a.startsWith('https://') || a.startsWith('http://'),
      )) {
        await widget.browser.add(url: url);
      }
      if (widget.arguments.contains('--stress')) {
        await widget.browser.closeTabs(widget.browser.tabs.toList());
        for (var i = 0; i < 100; i++) {
          final url = i < 5
              ? 'https://www.youtube.com/watch?v=aqz-KE-bpKQ'
              : 'https://example.com/?sirb=$i';
          if (i == 0) {
            await widget.browser.navigate(url);
          } else {
            await widget.browser.add(url: url);
          }
        }
      }
    } catch (e) {
      if (mounted) setState(() => failure = e.toString());
    }
  }

  @override
  void onWindowFocus() {
    unawaited(widget.browser.updateTouchpadSettings());
  }

  @override
  void onWindowClose() {
    unawaited(widget.runtime.close());
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    addressFocus.dispose();
    findFocus.dispose();
    findText.dispose();
    super.dispose();
  }

  void _find() {
    setState(() => findOpen = true);
    findFocus.requestFocus();
  }

  Future<void> _fullscreen() async {
    await windowManager.setFullScreen(!await windowManager.isFullScreen());
  }

  Future<void> _showBatchDialog() async {
    final l = AppLocalizations.of(context);
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.playlist_play, size: 24),
            const SizedBox(width: 8),
            Text(l.openBatch),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.openBatchHint,
                style: Theme.of(dialogContext).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 8,
                minLines: 4,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  hintText:
                      'https://www.youtube.com/watch?v=...\nhttps://www.youtube.com/watch?v=...',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l.cancel),
          ),
          FilledButton.icon(
            onPressed: () {
              final lines = controller.text
                  .split(RegExp(r'[\r\n]+'))
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList();
              Navigator.pop(dialogContext);
              if (lines.isNotEmpty) {
                unawaited(widget.browser.openBatch(lines));
              }
            },
            icon: const Icon(Icons.open_in_browser, size: 18),
            label: Text(l.openTabs),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Future<void> _menu(String action) async {
    final b = widget.browser;
    switch (action) {
      case 'settings':
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => SettingsScreen(
              browser: b,
              runtime: widget.runtime,
              device: widget.device,
            ),
          ),
        );
      case 'history':
        await Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => HistoryScreen(browser: b)),
        );
      case 'closures':
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => HistoryScreen(browser: b, closedTabs: true),
          ),
        );
      case 'batch':
        await _showBatchDialog();
      case 'downloads':
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => DownloadsScreen(store: b.store),
          ),
        );
      case 'logs':
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) =>
                ErrorLogsScreen(store: b.store, initialFilter: 'errors'),
          ),
        );
      case 'find':
        _find();
      case 'fullscreen':
        await _fullscreen();
      case 'gameWindow':
        final l = AppLocalizations.of(context);
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l.openGameWindow),
            content: Text(l.gameWindowNotice),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l.confirm),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        try {
          await b.openGameWindow();
        } catch (error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l.resourceError(error.toString()))),
            );
          }
        }
      case 'devtools':
        await b.active?.controller?.openDevTools();
      case 'zoomIn':
      case 'zoomOut':
      case 'zoomReset':
        final tab = b.active;
        if (tab == null) return;
        tab.zoom = action == 'zoomReset'
            ? 0
            : (tab.zoom + (action == 'zoomIn' ? 0.5 : -0.5)).clamp(-5, 5);
        await tab.controller?.hostControl('zoom', tab.zoom);
        b.changed();
    }
  }

  void _closeFind() {
    widget.browser.active?.controller?.hostControl('stopFind', '');
    setState(() => findOpen = false);
  }

  Map<ShortcutActivator, VoidCallback> get _shortcuts {
    final b = widget.browser, cmd = Platform.isMacOS;
    ShortcutActivator key(
      PhysicalKeyboardKey p,
      LogicalKeyboardKey l, {
      bool shift = false,
      bool alt = false,
      bool checkFocus = false,
    }) => UniversalActivator(
      p,
      l,
      control: !cmd && !alt,
      meta: cmd && !alt,
      shift: shift,
      alt: alt,
      predicate: checkFocus
          ? () => !addressFocus.hasFocus && !findFocus.hasFocus
          : null,
    );

    return {
      key(PhysicalKeyboardKey.keyT, LogicalKeyboardKey.keyT): () => b.add(),
      key(PhysicalKeyboardKey.keyW, LogicalKeyboardKey.keyW): () {
        final a = b.active;
        if (a != null) b.closeTabs([a]);
      },
      key(PhysicalKeyboardKey.keyT, LogicalKeyboardKey.keyT, shift: true): () =>
          b.restoreLast(),
      key(PhysicalKeyboardKey.keyL, LogicalKeyboardKey.keyL): () =>
          addressFocus.requestFocus(),
      key(PhysicalKeyboardKey.keyF, LogicalKeyboardKey.keyF): _find,
      key(PhysicalKeyboardKey.keyR, LogicalKeyboardKey.keyR): () =>
          b.active?.controller?.reload(),
      key(PhysicalKeyboardKey.keyR, LogicalKeyboardKey.keyR, shift: true): () =>
          b.active?.controller?.reload(),
      key(
        PhysicalKeyboardKey.keyA,
        LogicalKeyboardKey.keyA,
        checkFocus: true,
      ): () {
        final tab = b.active;
        if (tab == null || tab.controller == null) return;
        unawaited(tab.controller!.hostControl('selectAll', ''));
        tab.controller!.executeJavaScript(
          '(() => {'
          '  const a = document.activeElement;'
          '  if (a && (a.tagName === "INPUT" || a.tagName === "TEXTAREA")) {'
          '    a.select();'
          '  } else {'
          '    document.execCommand("selectAll");'
          '  }'
          '})();',
        );
      },
      key(
        PhysicalKeyboardKey.keyC,
        LogicalKeyboardKey.keyC,
        checkFocus: true,
      ): () async {
        final tab = b.active;
        if (tab == null || tab.controller == null) return;
        unawaited(tab.controller!.hostControl('copy', ''));
        final selected = await tab.controller!.evaluateJavascript(
          '(() => {'
          '  const a = document.activeElement;'
          '  if (a && (a.tagName === "INPUT" || a.tagName === "TEXTAREA")) {'
          '    const s = a.selectionStart ?? 0, e = a.selectionEnd ?? 0;'
          '    return a.value.substring(s, e);'
          '  }'
          '  return window.getSelection() ? window.getSelection().toString() : "";'
          '})();',
        );
        if (selected is String && selected.isNotEmpty) {
          await Clipboard.setData(ClipboardData(text: selected));
        }
        await tab.controller!.executeJavaScript(
          'document.execCommand("copy");',
        );
      },
      key(
        PhysicalKeyboardKey.keyX,
        LogicalKeyboardKey.keyX,
        checkFocus: true,
      ): () async {
        final tab = b.active;
        if (tab == null || tab.controller == null) return;
        unawaited(tab.controller!.hostControl('cut', ''));
        final selected = await tab.controller!.evaluateJavascript(
          '(() => {'
          '  const a = document.activeElement;'
          '  if (a && (a.tagName === "INPUT" || a.tagName === "TEXTAREA")) {'
          '    const s = a.selectionStart ?? 0, e = a.selectionEnd ?? 0;'
          '    return a.value.substring(s, e);'
          '  }'
          '  return window.getSelection() ? window.getSelection().toString() : "";'
          '})();',
        );
        if (selected is String && selected.isNotEmpty) {
          await Clipboard.setData(ClipboardData(text: selected));
        }
        await tab.controller!.executeJavaScript('document.execCommand("cut");');
      },
      key(
        PhysicalKeyboardKey.keyV,
        LogicalKeyboardKey.keyV,
        checkFocus: true,
      ): () async {
        final tab = b.active;
        if (tab == null || tab.controller == null) return;
        unawaited(tab.controller!.hostControl('paste', ''));
        final clip = await Clipboard.getData(Clipboard.kTextPlain);
        final text = clip?.text ?? '';
        if (text.isNotEmpty) {
          await tab.controller!.executeJavaScript(
            '(() => {'
            '  const a = document.activeElement;'
            '  if (a && (a.tagName === "INPUT" || a.tagName === "TEXTAREA")) {'
            '    const s = a.selectionStart ?? a.value.length;'
            '    const e = a.selectionEnd ?? a.value.length;'
            '    const val = a.value;'
            '    a.value = val.substring(0, s) + ${jsonEncode(text)} + val.substring(e);'
            '    a.selectionStart = a.selectionEnd = s + ${jsonEncode(text)}.length;'
            '    a.dispatchEvent(new Event("input", { bubbles: true }));'
            '    a.dispatchEvent(new Event("change", { bubbles: true }));'
            '  } else {'
            '    document.execCommand("insertText", false, ${jsonEncode(text)});'
            '  }'
            '})();',
          );
        }
      },
      key(
        PhysicalKeyboardKey.keyZ,
        LogicalKeyboardKey.keyZ,
        checkFocus: true,
      ): () {
        final tab = b.active;
        if (tab == null || tab.controller == null) return;
        unawaited(tab.controller!.hostControl('undo', ''));
        tab.controller!.executeJavaScript('document.execCommand("undo");');
      },
      key(
        PhysicalKeyboardKey.keyY,
        LogicalKeyboardKey.keyY,
        checkFocus: true,
      ): () {
        final tab = b.active;
        if (tab == null || tab.controller == null) return;
        unawaited(tab.controller!.hostControl('redo', ''));
        tab.controller!.executeJavaScript('document.execCommand("redo");');
      },
      key(
        PhysicalKeyboardKey.keyZ,
        LogicalKeyboardKey.keyZ,
        shift: true,
        checkFocus: true,
      ): () {
        final tab = b.active;
        if (tab == null || tab.controller == null) return;
        unawaited(tab.controller!.hostControl('redo', ''));
        tab.controller!.executeJavaScript('document.execCommand("redo");');
      },
      key(PhysicalKeyboardKey.keyH, LogicalKeyboardKey.keyH): () =>
          _menu('history'),
      key(PhysicalKeyboardKey.keyJ, LogicalKeyboardKey.keyJ): () =>
          _menu('downloads'),
      key(PhysicalKeyboardKey.keyD, LogicalKeyboardKey.keyD): () {
        final a = b.active;
        if (a != null) b.pin(a);
      },
      key(PhysicalKeyboardKey.equal, LogicalKeyboardKey.equal): () =>
          _menu('zoomIn'),
      key(PhysicalKeyboardKey.numpadAdd, LogicalKeyboardKey.add): () =>
          _menu('zoomIn'),
      key(PhysicalKeyboardKey.minus, LogicalKeyboardKey.minus): () =>
          _menu('zoomOut'),
      key(
        PhysicalKeyboardKey.numpadSubtract,
        LogicalKeyboardKey.numpadSubtract,
      ): () =>
          _menu('zoomOut'),
      key(PhysicalKeyboardKey.digit0, LogicalKeyboardKey.digit0): () =>
          _menu('zoomReset'),
      key(PhysicalKeyboardKey.numpad0, LogicalKeyboardKey.numpad0): () =>
          _menu('zoomReset'),
      const UniversalActivator(
        PhysicalKeyboardKey.f5,
        LogicalKeyboardKey.f5,
      ): () =>
          b.active?.controller?.reload(),
      const UniversalActivator(PhysicalKeyboardKey.f11, LogicalKeyboardKey.f11):
          _fullscreen,
      const UniversalActivator(
        PhysicalKeyboardKey.escape,
        LogicalKeyboardKey.escape,
      ): () {
        if (findOpen) {
          _closeFind();
        } else if (b.fullscreen) {
          _fullscreen();
        }
      },
      key(
        PhysicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowLeft,
        alt: true,
      ): () =>
          b.goBack(),
      key(
        PhysicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowRight,
        alt: true,
      ): () =>
          b.goForward(),
      key(PhysicalKeyboardKey.tab, LogicalKeyboardKey.tab): () {
        if (b.tabs.isNotEmpty) {
          b.activate(
            b
                .tabs[(b.tabs.indexWhere((t) => t.id == b.activeId) + 1) %
                    b.tabs.length]
                .id,
          );
        }
      },
      for (var i = 0; i < 9; i++)
        key(
          [
            PhysicalKeyboardKey.digit1,
            PhysicalKeyboardKey.digit2,
            PhysicalKeyboardKey.digit3,
            PhysicalKeyboardKey.digit4,
            PhysicalKeyboardKey.digit5,
            PhysicalKeyboardKey.digit6,
            PhysicalKeyboardKey.digit7,
            PhysicalKeyboardKey.digit8,
            PhysicalKeyboardKey.digit9,
          ][i],
          [
            LogicalKeyboardKey.digit1,
            LogicalKeyboardKey.digit2,
            LogicalKeyboardKey.digit3,
            LogicalKeyboardKey.digit4,
            LogicalKeyboardKey.digit5,
            LogicalKeyboardKey.digit6,
            LogicalKeyboardKey.digit7,
            LogicalKeyboardKey.digit8,
            LogicalKeyboardKey.digit9,
          ][i],
        ): () {
          if (b.tabs.isNotEmpty) {
            b.activate(
              b
                  .tabs[i == 8
                      ? b.tabs.length - 1
                      : i.clamp(0, b.tabs.length - 1)]
                  .id,
            );
          }
        },
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context),
        b = widget.browser,
        p = widget.browser.preferences;
    if (failure != null) {
      return Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l.engineError(failure!)),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    setState(() => failure = null);
                    _initialize();
                  },
                  child: Text(l.retry),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (!ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return CallbackShortcuts(
      bindings: _shortcuts,
      child: Focus(
        autofocus: true,
        child: Listener(
          onPointerDown: (event) {
            if (p.mouseNavigation) {
              if (event.buttons & kBackMouseButton != 0) {
                unawaited(b.goBack());
              } else if (event.buttons & kForwardMouseButton != 0) {
                unawaited(b.goForward());
              }
            }
          },
          child: AnimatedBuilder(
            animation: b,
            builder: (context, child) => Scaffold(
              body: LayoutBuilder(
                builder: (context, c) {
                  return Row(
                    children: [
                      if (!b.fullscreen && !collapsed)
                        SizedBox(
                          width: 260,
                          child: TabRail(
                            browser: b,
                            collapsed: false,
                            onCollapse: () => setState(() => collapsed = true),
                          ),
                        ),
                      Expanded(
                        child: Column(
                          children: [
                            if (!b.fullscreen)
                              AddressBar(
                                browser: b,
                                addressFocus: addressFocus,
                                onMenu: _menu,
                                onToggleTabs: () =>
                                    setState(() => collapsed = !collapsed),
                                tabsCollapsed: collapsed,
                              ),
                            if (b.error != null && !b.fullscreen)
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        l.resourceError(b.error!),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: l.close,
                                      onPressed: () {
                                        b.error = null;
                                        b.changed();
                                      },
                                      icon: const Icon(Icons.close),
                                    ),
                                  ],
                                ),
                              ),
                            if (b.pressure && !b.fullscreen)
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text(l.resourcePressure),
                              ),
                            if (findOpen && !b.fullscreen)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: findText,
                                        focusNode: findFocus,
                                        decoration: InputDecoration(
                                          hintText: l.find,
                                          isDense: true,
                                        ),
                                        onChanged: (s) => b.active?.controller
                                            ?.hostControl('find', s),
                                        onSubmitted: (s) => b.active?.controller
                                            ?.hostControl('findNext', s),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: l.findPrevious,
                                      onPressed: () =>
                                          b.active?.controller?.hostControl(
                                            'findPrevious',
                                            findText.text,
                                          ),
                                      icon: const Icon(Icons.keyboard_arrow_up),
                                    ),
                                    IconButton(
                                      tooltip: l.findNext,
                                      onPressed: () =>
                                          b.active?.controller?.hostControl(
                                            'findNext',
                                            findText.text,
                                          ),
                                      icon: const Icon(
                                        Icons.keyboard_arrow_down,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: l.close,
                                      onPressed: () {
                                        b.active?.controller?.hostControl(
                                          'stopFind',
                                          '',
                                        );
                                        setState(() => findOpen = false);
                                      },
                                      icon: const Icon(Icons.close),
                                    ),
                                  ],
                                ),
                              ),
                            Expanded(
                              child: b.active?.loadError != null
                                  ? Center(
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 640,
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              l.pageError(b.active!.loadError!),
                                            ),
                                            const SizedBox(height: 16),
                                            FilledButton(
                                              onPressed: () => b
                                                  .active
                                                  ?.controller
                                                  ?.reload(),
                                              child: Text(l.retry),
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                  : b.active?.url == 'sirb:new'
                                  ? NewTabPage(
                                      key: ValueKey(b.activeId),
                                      browser: b,
                                    )
                                  : b.active?.controller == null
                                  ? const Center(
                                      child: CircularProgressIndicator(),
                                    )
                                  : LayoutBuilder(
                                      builder: (context, constraints) {
                                        final w = constraints.maxWidth;
                                        final h = constraints.maxHeight;
                                        if (w > 0 &&
                                            h > 0 &&
                                            w.isFinite &&
                                            h.isFinite) {
                                          final dpi = MediaQuery.of(
                                            context,
                                          ).devicePixelRatio;
                                          b.updateViewport(Size(w, h), dpi);
                                        }
                                        return ValueListenableBuilder<bool>(
                                          key: ValueKey(
                                            'active_tab_${b.activeId}',
                                          ),
                                          valueListenable:
                                              b.active!.controller!,
                                          builder: (context, ready, child) =>
                                              SizedBox.expand(
                                                key: _webviewKey,
                                                child: ready
                                                    ? b
                                                          .active!
                                                          .controller!
                                                          .webviewWidget
                                                    : b
                                                          .active!
                                                          .controller!
                                                          .loadingWidget,
                                              ),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showContextMenu(
    BrowserTab tab,
    Map<String, dynamic> event,
  ) async {
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    final link = event['link'] as String?;
    final selection = event['selection'] as String?;
    final isEditable = event['editable'] as bool? ?? false;
    final hasSelection = selection != null && selection.isNotEmpty;
    final x = (event['x'] as num?)?.toDouble() ?? 0.0;
    final y = (event['y'] as num?)?.toDouble() ?? 0.0;

    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final webviewBox =
        _webviewKey.currentContext?.findRenderObject() as RenderBox?;
    final Offset globalPos;
    if (webviewBox != null && webviewBox.hasSize) {
      globalPos = webviewBox.localToGlobal(Offset(x, y));
    } else {
      globalPos = Offset(x, y);
    }

    final position = RelativeRect.fromRect(
      Rect.fromLTWH(globalPos.dx, globalPos.dy, 1, 1),
      Offset.zero & overlay.size,
    );

    final selected = await showDesktopContextMenu<String>(
      context: context,
      position: position,
      items: [
        if (link != null && link.isNotEmpty) ...[
          PopupMenuItem(
            value: 'open_new_tab',
            child: Row(
              children: [
                const Icon(Icons.open_in_new, size: 18),
                const SizedBox(width: 8),
                Text(l.openLinkInNewTab),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'copy_link',
            child: Row(
              children: [
                const Icon(Icons.copy, size: 18),
                const SizedBox(width: 8),
                Text(l.copyLinkAddress),
              ],
            ),
          ),
          const PopupMenuDivider(),
        ],
        if (hasSelection) ...[
          PopupMenuItem(
            value: 'copy',
            child: Row(
              children: [
                const Icon(Icons.copy, size: 18),
                const SizedBox(width: 8),
                Text(l.copy),
              ],
            ),
          ),
        ],
        if (isEditable) ...[
          PopupMenuItem(
            value: 'paste',
            child: Row(
              children: [
                const Icon(Icons.paste, size: 18),
                const SizedBox(width: 8),
                Text(l.paste),
              ],
            ),
          ),
          if (hasSelection)
            PopupMenuItem(
              value: 'cut',
              child: Row(
                children: [
                  const Icon(Icons.cut, size: 18),
                  const SizedBox(width: 8),
                  Text(l.cut),
                ],
              ),
            ),
        ],
        PopupMenuItem(
          value: 'select_all',
          child: Row(
            children: [
              const Icon(Icons.select_all, size: 18),
              const SizedBox(width: 8),
              Text(l.selectAll),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'reload',
          child: Row(
            children: [
              const Icon(Icons.refresh, size: 18),
              const SizedBox(width: 8),
              Text(l.reload),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'back',
          enabled: tab.canBack,
          child: Row(
            children: [
              const Icon(Icons.arrow_back, size: 18),
              const SizedBox(width: 8),
              Text(l.back),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'forward',
          enabled: tab.canForward,
          child: Row(
            children: [
              const Icon(Icons.arrow_forward, size: 18),
              const SizedBox(width: 8),
              Text(l.forward),
            ],
          ),
        ),
      ],
    );

    if (selected == 'open_new_tab' && link != null) {
      await widget.browser.add(url: link, activateTab: false, openerId: tab.id);
    } else if (selected == 'copy_link' && link != null) {
      await Clipboard.setData(ClipboardData(text: link));
    } else if (selected == 'copy') {
      unawaited(tab.controller?.hostControl('copy', ''));
      if (hasSelection) {
        await Clipboard.setData(ClipboardData(text: selection));
      }
      await tab.controller?.executeJavaScript('document.execCommand("copy");');
    } else if (selected == 'cut') {
      unawaited(tab.controller?.hostControl('cut', ''));
      if (hasSelection) {
        await Clipboard.setData(ClipboardData(text: selection));
      }
      await tab.controller?.executeJavaScript('document.execCommand("cut");');
    } else if (selected == 'paste') {
      unawaited(tab.controller?.hostControl('paste', ''));
      final clip = await Clipboard.getData(Clipboard.kTextPlain);
      final text = clip?.text ?? '';
      if (text.isNotEmpty) {
        await tab.controller?.executeJavaScript(
          '(() => {'
          '  const active = document.activeElement;'
          '  if (active && (active.tagName === "INPUT" || active.tagName === "TEXTAREA")) {'
          '    const start = active.selectionStart ?? active.value.length;'
          '    const end = active.selectionEnd ?? active.value.length;'
          '    const val = active.value;'
          '    active.value = val.substring(0, start) + ${jsonEncode(text)} + val.substring(end);'
          '    active.selectionStart = active.selectionEnd = start + ${jsonEncode(text)}.length;'
          '    active.dispatchEvent(new Event("input", { bubbles: true }));'
          '    active.dispatchEvent(new Event("change", { bubbles: true }));'
          '  } else {'
          '    document.execCommand("insertText", false, ${jsonEncode(text)});'
          '  }'
          '})();',
        );
      }
    } else if (selected == 'select_all') {
      await tab.controller?.executeJavaScript(
        '(() => {'
        '  const active = document.activeElement;'
        '  if (active && (active.tagName === "INPUT" || active.tagName === "TEXTAREA")) {'
        '    active.select();'
        '  } else {'
        '    document.execCommand("selectAll");'
        '  }'
        '})();',
      );
    } else if (selected == 'reload') {
      await tab.controller?.reload();
    } else if (selected == 'back') {
      await tab.controller?.goBack();
    } else if (selected == 'forward') {
      await tab.controller?.goForward();
    }
  }
}

class UniversalActivator extends ShortcutActivator {
  const UniversalActivator(
    this.physicalKey,
    this.logicalKey, {
    this.control = false,
    this.shift = false,
    this.alt = false,
    this.meta = false,
    this.predicate,
  });

  final PhysicalKeyboardKey physicalKey;
  final LogicalKeyboardKey logicalKey;
  final bool control;
  final bool shift;
  final bool alt;
  final bool meta;
  final bool Function()? predicate;

  @override
  Iterable<LogicalKeyboardKey>? get triggers => null;

  @override
  bool accepts(KeyEvent event, HardwareKeyboard state) {
    if (event is! KeyDownEvent) return false;
    if (predicate != null && !predicate!()) return false;
    if (event.physicalKey != physicalKey && event.logicalKey != logicalKey) {
      return false;
    }
    return state.isControlPressed == control &&
        state.isShiftPressed == shift &&
        state.isAltPressed == alt &&
        state.isMetaPressed == meta;
  }

  @override
  String debugDescribeKeys() {
    final keys = <String>[
      if (control) 'Control',
      if (alt) 'Alt',
      if (meta) 'Meta',
      if (shift) 'Shift',
      logicalKey.debugName ?? logicalKey.keyLabel,
    ];
    return keys.join(' + ');
  }
}
