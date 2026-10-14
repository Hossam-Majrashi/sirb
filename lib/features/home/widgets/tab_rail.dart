import 'package:flutter/material.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../shared/models/browser_tab.dart';
import '../../../shared/widgets/desktop_context_menu.dart';
import '../services/browser_controller.dart';

class TabRail extends StatefulWidget {
  const TabRail({
    super.key,
    required this.browser,
    required this.collapsed,
    required this.onCollapse,
  });
  final BrowserController browser;
  final bool collapsed;
  final VoidCallback onCollapse;
  @override
  State<TabRail> createState() => _TabRailState();
}

class _TabRailState extends State<TabRail> {
  String filter = '';
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context), b = widget.browser;
    final tabs = b.tabs
        .where(
          (t) => '${t.title} ${t.url}'.toLowerCase().contains(
            filter.toLowerCase(),
          ),
        )
        .toList();
    return LayoutBuilder(
      builder: (context, c) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(6),
            child: Wrap(
              alignment: WrapAlignment.center,
              children: [
                IconButton(
                  tooltip: widget.collapsed ? l.expand : l.collapse,
                  onPressed: widget.onCollapse,
                  icon: Icon(
                    widget.collapsed
                        ? Icons.view_sidebar_outlined
                        : Icons.chevron_left,
                  ),
                ),
                IconButton(
                  tooltip: l.newTab,
                  onPressed: () => b.add(),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
          if (!widget.collapsed)
            Padding(
              padding: const EdgeInsets.all(8),
              child: TextField(
                decoration: InputDecoration(
                  hintText: l.searchTabs,
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged: (s) => setState(() => filter = s),
              ),
            ),
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              itemCount: tabs.length,
              onReorderItem: (oldIndex, newIndex) {
                if (filter.isNotEmpty) return;
                b.reorder(oldIndex, newIndex);
              },
              itemBuilder: (context, index) {
                final t = tabs[index], selected = t.id == b.activeId;
                final title = t.title.isEmpty
                    ? (t.url == 'sirb:new' ? l.newTab : t.url)
                    : t.title;
                final phase = t.media
                    ? l.playing
                    : switch (t.phase) {
                        TabPhase.sleeping => l.sleeping,
                        TabPhase.active => l.live,
                        TabPhase.background => l.background,
                      };
                return ReorderableDragStartListener(
                  key: ValueKey(t.id),
                  index: index,
                  child: Tooltip(
                    message: '$title — $phase',
                    child: Card(
                      color: selected
                          ? Theme.of(context).colorScheme.primaryContainer
                          : null,
                      child: InkWell(
                        onTap: () => b.activate(t.id),
                        onSecondaryTapDown: (details) =>
                            _menu(context, t, details.globalPosition),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 8,
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 22,
                                height: 22,
                                child: t.phase == TabPhase.sleeping
                                    ? const Icon(
                                        Icons.bedtime_outlined,
                                        size: 20,
                                      )
                                    : t.icon.isEmpty
                                    ? const Icon(Icons.public, size: 20)
                                    : Image.network(
                                        t.icon,
                                        errorBuilder: (_, error, stack) =>
                                            const Icon(Icons.public, size: 20),
                                      ),
                              ),
                              if (!widget.collapsed) ...[
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (t.pinned)
                                  const Icon(Icons.push_pin, size: 14),
                                if (t.media || t.muted)
                                  IconButton(
                                    tooltip: l.mute,
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => b.mute(t),
                                    icon: Icon(
                                      t.muted
                                          ? Icons.volume_off
                                          : Icons.volume_up,
                                      size: 16,
                                    ),
                                  ),
                                IconButton(
                                  tooltip: l.close,
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => b.closeTabs([t]),
                                  icon: const Icon(Icons.close, size: 16),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (!widget.collapsed)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(l.tabCount(b.tabs.length)),
            ),
        ],
      ),
    );
  }

  Future<void> _menu(
    BuildContext context,
    BrowserTab tab,
    Offset position,
  ) async {
    final l = AppLocalizations.of(context), b = widget.browser;
    final result = await showDesktopContextMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem(value: 'pin', child: Text(l.pin)),
        PopupMenuItem(value: 'mute', child: Text(l.mute)),
        PopupMenuItem(value: 'duplicate', child: Text(l.duplicate)),
        PopupMenuItem(
          value: 'sleep',
          enabled: !tab.media && tab.id != b.activeId,
          child: Text(l.sleep),
        ),
        PopupMenuItem(value: 'others', child: Text(l.closeOthers)),
        PopupMenuItem(value: 'after', child: Text(l.closeAfter)),
        PopupMenuItem(value: 'all', child: Text(l.closeAll)),
        PopupMenuItem(value: 'close', child: Text(l.close)),
      ],
    );
    switch (result) {
      case 'pin':
        b.pin(tab);
      case 'mute':
        await b.mute(tab);
      case 'duplicate':
        await b.add(url: tab.url, openerId: tab.id);
      case 'sleep':
        await b.sleep(tab);
      case 'others':
        await b.closeTabs(b.tabs.where((t) => t != tab).toList());
      case 'after':
        await b.closeTabs(b.tabs.skip(b.tabs.indexOf(tab) + 1).toList());
      case 'all':
        await b.closeTabs(b.tabs.toList());
      case 'close':
        await b.closeTabs([tab]);
    }
  }
}
