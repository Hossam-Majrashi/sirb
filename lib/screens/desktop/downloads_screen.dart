import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:url_launcher/url_launcher.dart';
import '../../core/l10n/app_localizations.dart';
import '../../shared/services/browser_store.dart';
import '../../shared/widgets/bounded_page.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key, required this.store});
  final BrowserStore store;
  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  late Future<List<Map<String, dynamic>>> downloads;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    downloads = widget.store.downloads();
    timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() => downloads = widget.store.downloads());
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> open(String file) async {
    try {
      if (!File(file).existsSync() || !await launchUrl(Uri.file(file))) {
        throw StateError(file);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).launchFailed)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.downloads)),
      body: BoundedPage(
        child: FutureBuilder(
          future: downloads,
          builder: (context, s) {
            final rows = s.data ?? [];
            if (rows.isEmpty) return Center(child: Text(l.empty));
            return ListView(
              children: rows.map((d) {
                final file = d['path'] as String;
                return ListTile(
                  leading: Icon(
                    d['complete'] == true
                        ? Icons.download_done
                        : Icons.downloading,
                  ),
                  title: Text(
                    file.isEmpty ? d['url'] as String : path.basename(file),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    d['complete'] == true
                        ? l.downloadComplete
                        : d['canceled'] == true
                        ? l.downloadCanceled
                        : l.downloadProgress(d['percent'] as int),
                  ),
                  trailing: d['complete'] == true
                      ? IconButton(
                          tooltip: l.openFile,
                          onPressed: () => open(file),
                          icon: const Icon(Icons.folder_open),
                        )
                      : null,
                );
              }).toList(),
            );
          },
        ),
      ),
    );
  }
}
