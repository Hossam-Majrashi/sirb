import 'package:flutter/material.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../ads/widgets/site_shield.dart';
import '../services/browser_controller.dart';

class AddressBar extends StatefulWidget {
  const AddressBar({
    super.key,
    required this.browser,
    required this.addressFocus,
    required this.onMenu,
    this.onToggleTabs,
    this.tabsCollapsed = false,
  });
  final BrowserController browser;
  final FocusNode addressFocus;
  final ValueChanged<String> onMenu;
  final VoidCallback? onToggleTabs;
  final bool tabsCollapsed;
  @override
  State<AddressBar> createState() => _AddressBarState();
}

class _AddressBarState extends State<AddressBar> {
  final text = TextEditingController();
  String last = '';
  bool _selectAllOnFocus = true;

  @override
  void initState() {
    super.initState();
    widget.addressFocus.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!widget.addressFocus.hasFocus) {
      _selectAllOnFocus = true;
    }
  }

  @override
  void dispose() {
    widget.addressFocus.removeListener(_onFocusChange);
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context), b = widget.browser, t = b.active;
    final url = t?.url == 'sirb:new' ? '' : t?.url ?? '';
    if (last != url && !widget.addressFocus.hasFocus) {
      last = url;
      text.text = url;
    }
    return LayoutBuilder(
      builder: (context, c) => Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            if (widget.onToggleTabs != null)
              IconButton(
                tooltip: widget.tabsCollapsed ? l.expand : l.collapse,
                onPressed: widget.onToggleTabs,
                icon: Icon(
                  widget.tabsCollapsed
                      ? Icons.view_sidebar_outlined
                      : Icons.view_sidebar,
                  size: 20,
                ),
              ),
            IconButton(
              tooltip: l.back,
              onPressed: t?.canBack == true
                  ? () => t?.controller?.goBack()
                  : null,
              icon: const Icon(Icons.arrow_back, size: 20),
            ),
            IconButton(
              tooltip: l.forward,
              onPressed: t?.canForward == true
                  ? () => t?.controller?.goForward()
                  : null,
              icon: const Icon(Icons.arrow_forward, size: 20),
            ),
            IconButton(
              tooltip: t?.loading == true ? l.stop : l.reload,
              onPressed: () => t?.loading == true
                  ? t?.controller?.hostControl('stop', '')
                  : b.reload(),
              icon: Icon(
                t?.loading == true ? Icons.close : Icons.refresh,
                size: 20,
              ),
            ),
            IconButton(
              tooltip: l.newTab,
              onPressed: () => b.add(),
              icon: const Icon(Icons.add, size: 20),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: RawAutocomplete<String>(
                textEditingController: text,
                focusNode: widget.addressFocus,
                optionsBuilder: (value) async {
                  if (value.text.isEmpty) return const Iterable<String>.empty();
                  final rows = await b.store.visits(value.text);
                  return rows.map((r) => r['url'] as String).toSet().take(8);
                },
                onSelected: (s) {
                  widget.addressFocus.unfocus();
                  b.navigate(s);
                },
                fieldViewBuilder: (context, controller, focus, submit) =>
                    TextField(
                      controller: controller,
                      focusNode: focus,
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: l.addressHint,
                        prefixIcon: Icon(
                          Uri.tryParse(url)?.scheme == 'https'
                              ? Icons.lock_outline
                              : Icons.search,
                          size: 18,
                        ),
                      ),
                      onTap: () {
                        if (_selectAllOnFocus) {
                          _selectAllOnFocus = false;
                          controller.selection = TextSelection(
                            baseOffset: 0,
                            extentOffset: controller.text.length,
                          );
                        }
                      },
                      onSubmitted: (s) {
                        submit();
                        focus.unfocus();
                        b.navigate(s);
                      },
                    ),
                optionsViewBuilder: (context, select, options) => Align(
                  alignment: AlignmentDirectional.topStart,
                  child: Material(
                    elevation: 8,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxHeight: 300,
                        maxWidth: 560,
                      ),
                      child: ListView(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        children: options
                            .map(
                              (s) => ListTile(
                                title: Text(
                                  s,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textDirection: TextDirection.ltr,
                                ),
                                onTap: () => select(s),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SiteShield(
              enabled: b.engine.blocker.enabledFor(url),
              blocked: t?.blocked ?? 0,
              onToggle: url.isEmpty
                  ? null
                  : () async {
                      await b.engine.blocker.toggleSite(url);
                      await b.reconfigure();
                    },
            ),
            PopupMenuButton<String>(
              tooltip: l.settings,
              onSelected: widget.onMenu,
              itemBuilder: (context) => [
                PopupMenuItem(value: 'settings', child: Text(l.settings)),
                PopupMenuItem(value: 'history', child: Text(l.history)),
                PopupMenuItem(value: 'closures', child: Text(l.tabHistory)),
                PopupMenuItem(value: 'batch', child: Text(l.openBatch)),
                PopupMenuItem(value: 'downloads', child: Text(l.downloads)),
                PopupMenuItem(value: 'logs', child: Text(l.errorLogs)),
                PopupMenuItem(value: 'find', child: Text(l.find)),
                PopupMenuItem(value: 'zoomIn', child: Text(l.zoomIn)),
                PopupMenuItem(value: 'zoomOut', child: Text(l.zoomOut)),
                PopupMenuItem(value: 'zoomReset', child: Text(l.zoomReset)),
                PopupMenuItem(value: 'fullscreen', child: Text(l.fullscreen)),
                PopupMenuItem(
                  value: 'gameWindow',
                  enabled:
                      b.gameWindowId == null &&
                      (url.startsWith('https://') || url.startsWith('http://')),
                  child: Text(l.openGameWindow),
                ),
                PopupMenuItem(value: 'devtools', child: Text(l.devtools)),
              ],
              icon: const Icon(Icons.more_vert),
            ),
          ],
        ),
      ),
    );
  }
}
