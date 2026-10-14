import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/l10n/app_localizations.dart';
import '../../features/home/services/browser_controller.dart';
import '../../shared/widgets/bounded_page.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.browser,
    this.closedTabs = false,
  });
  final BrowserController browser;
  final bool closedTabs;
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String query = '';
  late Future<List<Map<String, Object?>>> rows;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  void refresh() {
    rows = widget.closedTabs
        ? widget.browser.store.closures()
        : widget.browser.store.visits(query);
  }

  Future<void> _deleteAll() async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.confirmDelete),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (widget.closedTabs) {
      await widget.browser.store.clearClosures();
    } else {
      await widget.browser.store.clearVisits();
    }
    if (mounted) setState(refresh);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context), b = widget.browser;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.closedTabs ? l.tabHistory : l.history),
        actions: [
          if (!widget.closedTabs)
            PopupMenuButton<int>(
              tooltip: l.deleteRange,
              onSelected: (hours) async {
                await b.store.clearVisits(
                  since: DateTime.now().subtract(Duration(hours: hours)),
                );
                if (mounted) setState(refresh);
              },
              itemBuilder: (context) => [
                PopupMenuItem(value: 1, child: Text(l.lastHour)),
                PopupMenuItem(value: 24, child: Text(l.lastDay)),
                PopupMenuItem(value: 168, child: Text(l.lastWeek)),
              ],
              icon: const Icon(Icons.date_range),
            ),
          IconButton(
            tooltip: l.deleteAll,
            onPressed: _deleteAll,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: BoundedPage(
        child: Column(
          children: [
            if (!widget.closedTabs)
              TextField(
                decoration: InputDecoration(
                  hintText: l.search,
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged: (s) => setState(() {
                  query = s;
                  refresh();
                }),
              ),
            const SizedBox(height: 16),
            Expanded(
              child: FutureBuilder(
                future: rows,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final items = snapshot.data ?? [];
                  if (items.isEmpty) return Center(child: Text(l.empty));
                  return ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index], id = item['id'] as int;
                      final time = DateTime.fromMillisecondsSinceEpoch(
                        item['time'] as int,
                      );
                      final date =
                          '${MaterialLocalizations.of(context).formatShortDate(time)} ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(time))}';
                      if (widget.closedTabs) {
                        final tabs =
                            jsonDecode(item['snapshot'] as String) as List;
                        return ExpansionTile(
                          title: Text(l.operation(tabs.length, date)),
                          trailing: Wrap(
                            children: [
                              IconButton(
                                tooltip: l.restore,
                                icon: const Icon(Icons.restore),
                                onPressed: () async {
                                  await b.restore(tabs);
                                  await b.store.removeClosure(id);
                                  if (mounted) setState(refresh);
                                },
                              ),
                              IconButton(
                                tooltip: l.delete,
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () async {
                                  await b.store.removeClosure(id);
                                  if (mounted) setState(refresh);
                                },
                              ),
                            ],
                          ),
                          children: List.generate(
                            tabs.length,
                            (i) => ListTile(
                              title: Text(
                                (tabs[i]['title'] as String).isEmpty
                                    ? tabs[i]['url'] as String
                                    : tabs[i]['title'] as String,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                tabs[i]['url'] as String,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: IconButton(
                                tooltip: l.restore,
                                icon: const Icon(Icons.restore),
                                onPressed: () async {
                                  await b.restore([tabs[i]]);
                                  tabs.removeAt(i);
                                  if (tabs.isEmpty) {
                                    await b.store.removeClosure(id);
                                  } else {
                                    await b.store.db.update(
                                      'closures',
                                      {'snapshot': jsonEncode(tabs)},
                                      where: 'id=?',
                                      whereArgs: [id],
                                    );
                                  }
                                  if (mounted) setState(refresh);
                                },
                              ),
                            ),
                          ),
                        );
                      }
                      return ListTile(
                        leading: SizedBox(
                          width: 24,
                          height: 24,
                          child: (item['icon'] as String).isEmpty
                              ? const Icon(Icons.public)
                              : Image.network(
                                  item['icon'] as String,
                                  errorBuilder: (_, error, stack) =>
                                      const Icon(Icons.public),
                                ),
                        ),
                        title: Text(
                          (item['title'] as String).isEmpty
                              ? item['url'] as String
                              : item['title'] as String,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${item['url']} · $date',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () {
                          b.add(url: item['url'] as String);
                          Navigator.pop(context);
                        },
                        trailing: IconButton(
                          tooltip: l.delete,
                          onPressed: () async {
                            await b.store.deleteVisit(id);
                            if (mounted) setState(refresh);
                          },
                          icon: const Icon(Icons.delete_outline),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
