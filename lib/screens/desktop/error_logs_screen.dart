import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:url_launcher/url_launcher.dart';
import '../../core/l10n/app_localizations.dart';
import '../../shared/models/error_log_entry.dart';
import '../../shared/services/browser_store.dart';
import '../../shared/widgets/bounded_page.dart';

class ErrorLogsScreen extends StatefulWidget {
  const ErrorLogsScreen({
    super.key,
    required this.store,
    this.initialFilter = 'errors',
  });

  final BrowserStore store;
  final String initialFilter;

  @override
  State<ErrorLogsScreen> createState() => _ErrorLogsScreenState();
}

class _ErrorLogsScreenState extends State<ErrorLogsScreen> {
  late String _activeFilter;
  final _searchController = TextEditingController();
  late Future<List<ErrorLogEntry>> _logsFuture;
  int _limit = 1000;

  Future<List<ErrorLogEntry>> _allMatchingLogs() => widget.store.errorLogs(
    type: _activeFilter == 'all' ? null : _activeFilter,
    query: _searchController.text,
    limit: null,
  );

  @override
  void initState() {
    super.initState();
    _activeFilter = widget.initialFilter;
    _logsFuture = widget.store.errorLogs(
      type: _activeFilter == 'all' ? null : _activeFilter,
      query: _searchController.text,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadLogs({bool resetLimit = true}) {
    setState(() {
      if (resetLimit) _limit = 1000;
      _logsFuture = widget.store.errorLogs(
        type: _activeFilter == 'all' ? null : _activeFilter,
        query: _searchController.text,
        limit: _limit,
      );
    });
  }

  Future<void> _copyLog(ErrorLogEntry entry) async {
    final l = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: entry.toFormattedString()));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.copiedToClipboard)));
    }
  }

  Future<void> _copyAll(List<ErrorLogEntry> entries) async {
    final l = AppLocalizations.of(context);
    entries = await _allMatchingLogs();
    if (entries.isEmpty) return;
    final text = entries.map((e) => e.toFormattedString()).join('\n---\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.copiedToClipboard)));
    }
  }

  Future<void> _clearLogs() async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.clearLogs),
        content: Text(l.confirmDeleteLogs),
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
    await widget.store.clearErrorLogs(
      type: _activeFilter == 'all' ? null : _activeFilter,
    );
    _loadLogs();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.dataCleared)));
    }
  }

  Future<void> _deleteLog(int id) async {
    await widget.store.deleteErrorLog(id);
    _loadLogs();
  }

  Future<void> _exportTxt(List<ErrorLogEntry> entries) async {
    final l = AppLocalizations.of(context);
    if (entries.isEmpty) return;
    try {
      entries = await _allMatchingLogs();
      final home =
          Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'] ??
          '.';
      final downloadsDir = Directory(path.join(home, 'Downloads'));
      final targetDir = downloadsDir.existsSync()
          ? downloadsDir
          : Directory(home);
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final file = File(
        path.join(targetDir.path, 'sirb_error_logs_$timestamp.txt'),
      );

      final buffer = StringBuffer();
      buffer.writeln('========================================');
      buffer.writeln('Sirb Error Logs Export');
      buffer.writeln('Timestamp: ${DateTime.now().toIso8601String()}');
      buffer.writeln('Category: $_activeFilter');
      buffer.writeln('Total Entries: ${entries.length}');
      buffer.writeln('========================================\n');
      for (final entry in entries) {
        buffer.writeln(entry.toFormattedString());
        buffer.writeln('----------------------------------------');
      }

      await file.writeAsString(buffer.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.logsExported(file.path)),
            action: SnackBarAction(
              label: l.openFile,
              onPressed: () => launchUrl(Uri.file(file.path)),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.resourceError(e.toString()))));
      }
    }
  }

  IconData _iconForType(String type) => switch (type) {
    'ad' => Icons.shield_outlined,
    'network' => Icons.cloud_off_outlined,
    'performance' => Icons.speed_outlined,
    'compatibility' => Icons.info_outline,
    'crash' => Icons.error_outline,
    'system' => Icons.settings_suggest_outlined,
    'flutter' => Icons.flutter_dash,
    _ => Icons.bug_report_outlined,
  };

  String _labelForType(AppLocalizations l, String type) => switch (type) {
    'ad' => l.adErrorLogs,
    'network' => l.networkLogs,
    'crash' => l.crashLogs,
    'system' => l.systemLogs,
    'flutter' => l.flutterLogs,
    'javascript' => l.javascriptLogs,
    'performance' => l.performanceLogs,
    'compatibility' => l.compatibilityLogs,
    'graphics' => l.graphicsLogs,
    'media' => l.mediaLogs,
    'permission' => l.permissionLogs,
    _ => type,
  };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.errorLogs),
        actions: [
          IconButton(
            tooltip: l.reload,
            onPressed: _loadLogs,
            icon: const Icon(Icons.refresh),
          ),
          FutureBuilder<List<ErrorLogEntry>>(
            future: _logsFuture,
            builder: (context, snapshot) {
              final entries = snapshot.data ?? [];
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: l.copyAll,
                    icon: const Icon(Icons.copy_all),
                    onPressed: entries.isNotEmpty
                        ? () => _copyAll(entries)
                        : null,
                  ),
                  IconButton(
                    tooltip: l.exportTxt,
                    icon: const Icon(Icons.file_download_outlined),
                    onPressed: entries.isNotEmpty
                        ? () => _exportTxt(entries)
                        : null,
                  ),
                  IconButton(
                    tooltip: l.clearLogs,
                    icon: const Icon(Icons.delete_sweep_outlined),
                    onPressed: entries.isNotEmpty ? _clearLogs : null,
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: BoundedPage(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(l.errorCaptureNotice),
            ),
            if (_activeFilter == 'compatibility')
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(l.compatibilityLogsNotice),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    FilterChip(
                      label: Text(l.errorLogs),
                      avatar: const Icon(Icons.error_outline, size: 16),
                      selected: _activeFilter == 'errors',
                      onSelected: (_) {
                        setState(() {
                          _activeFilter = 'errors';
                          _loadLogs();
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: Text(l.adErrorLogs),
                      avatar: const Icon(Icons.shield_outlined, size: 16),
                      selected: _activeFilter == 'ad',
                      onSelected: (_) {
                        setState(() {
                          _activeFilter = 'ad';
                          _loadLogs();
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: Text(l.allLogs),
                      selected: _activeFilter == 'all',
                      onSelected: (_) {
                        setState(() {
                          _activeFilter = 'all';
                          _loadLogs();
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: Text(l.networkLogs),
                      avatar: const Icon(Icons.cloud_off_outlined, size: 16),
                      selected: _activeFilter == 'network',
                      onSelected: (_) {
                        setState(() {
                          _activeFilter = 'network';
                          _loadLogs();
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: Text(l.crashLogs),
                      avatar: const Icon(Icons.error_outline, size: 16),
                      selected: _activeFilter == 'crash',
                      onSelected: (_) {
                        setState(() {
                          _activeFilter = 'crash';
                          _loadLogs();
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    for (final (category, label, icon) in [
                      ('javascript', l.javascriptLogs, Icons.code),
                      ('performance', l.performanceLogs, Icons.speed_outlined),
                      (
                        'compatibility',
                        l.compatibilityLogs,
                        Icons.info_outline,
                      ),
                      ('graphics', l.graphicsLogs, Icons.monitor),
                      ('media', l.mediaLogs, Icons.volume_up_outlined),
                      ('permission', l.permissionLogs, Icons.lock_outline),
                      ('flutter', l.flutterLogs, Icons.flutter_dash),
                    ]) ...[
                      FilterChip(
                        label: Text(label),
                        avatar: Icon(icon, size: 16),
                        selected: _activeFilter == category,
                        onSelected: (_) {
                          _activeFilter = category;
                          _loadLogs();
                        },
                      ),
                      const SizedBox(width: 8),
                    ],
                    FilterChip(
                      label: Text(l.systemLogs),
                      avatar: const Icon(
                        Icons.settings_suggest_outlined,
                        size: 16,
                      ),
                      selected: _activeFilter == 'system',
                      onSelected: (_) {
                        setState(() {
                          _activeFilter = 'system';
                          _loadLogs();
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: l.search,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            _loadLogs();
                          },
                        )
                      : null,
                  isDense: true,
                ),
                onChanged: (_) => _loadLogs(),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<ErrorLogEntry>>(
                future: _logsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(l.resourceError(snapshot.error.toString())),
                    );
                  }
                  final entries = snapshot.data ?? [];
                  if (entries.isEmpty) {
                    return Center(child: Text(l.empty));
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: entries.length + 1,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      if (index == entries.length) {
                        if (entries.length < _limit) {
                          return const SizedBox.shrink();
                        }
                        return TextButton(
                          onPressed: () {
                            _limit += 1000;
                            _loadLogs(resetLimit: false);
                          },
                          child: Text(l.loadMoreLogs),
                        );
                      }
                      final entry = entries[index];
                      final timeStr = entry.time
                          .toIso8601String()
                          .replaceFirst('T', ' ')
                          .split('.')
                          .first;
                      return Card(
                        elevation: 1,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    _iconForType(entry.type),
                                    size: 18,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _labelForType(l, entry.type),
                                      style: theme.textTheme.labelLarge
                                          ?.copyWith(
                                            color: theme.colorScheme.primary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    timeStr,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.outline,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    tooltip: l.copy,
                                    icon: const Icon(Icons.copy, size: 18),
                                    onPressed: () => _copyLog(entry),
                                  ),
                                  IconButton(
                                    tooltip: l.delete,
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      size: 18,
                                    ),
                                    onPressed: () => _deleteLog(entry.id),
                                  ),
                                ],
                              ),
                              if (entry.url != null &&
                                  entry.url!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.link, size: 16),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: SelectableText(
                                        entry.url!,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 6),
                              SelectableText(
                                entry.message,
                                style: theme.textTheme.bodyMedium,
                              ),
                              if (entry.details != null &&
                                  entry.details!.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: theme
                                        .colorScheme
                                        .surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: SelectableText(
                                    entry.details!,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
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
