import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/developer_info.dart';
import '../../core/l10n/app_localizations.dart';
import '../../features/settings/widgets/preference_choice.dart';
import '../../features/home/services/browser_controller.dart';
import '../../shared/models/device_info.dart';
import '../../shared/services/app_runtime.dart';
import '../../shared/widgets/bounded_page.dart';
import 'error_logs_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.browser,
    required this.runtime,
    required this.device,
  });
  final BrowserController browser;
  final AppRuntime runtime;
  final DeviceInfo device;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool hardAvailable = false;
  String? diagnostics;

  @override
  void initState() {
    super.initState();
    widget.runtime.resources.hardRamSupported.then((v) {
      if (mounted) setState(() => hardAvailable = v);
    });
  }

  Widget _choice<T>(
    String label,
    T value,
    Map<T, String> options,
    ValueChanged<T?>? onChanged, {
    String? hint,
  }) => PreferenceChoice<T>(
    label: label,
    value: value,
    options: options,
    onChanged: onChanged,
    hint: hint,
  );
  Future<void> _launchUrl(String value) async {
    try {
      if (!await launchUrl(
        Uri.parse(value),
        mode: LaunchMode.externalApplication,
      )) {
        throw StateError(value);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).launchFailed)),
        );
      }
    }
  }

  Widget _buildContactItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
    title: Text(label),
    subtitle: Text(value, softWrap: true, textDirection: TextDirection.ltr),
    onTap: onTap,
  );
  Future<void> _clear(Future<void> Function() action) async {
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
            child: Text(l.confirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.dataCleared)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.resourceError(e.toString()))));
      }
    }
  }

  Future<void> _diagnose() async {
    final c = widget.browser.active?.controller;
    if (c == null) {
      await widget.browser.navigate('https://www.youtube.com');
    }
    final controller = widget.browser.active?.controller;
    final result = await controller?.evaluateJavascript('''JSON.stringify({
      vp9:MediaSource.isTypeSupported('video/webm; codecs="vp9,opus"'),
      av1:MediaSource.isTypeSupported('video/webm; codecs="av01.0.05M.08,opus"'),
      h264:MediaSource.isTypeSupported('video/mp4; codecs="avc1.42E01E"'),
      aac:MediaSource.isTypeSupported('audio/mp4; codecs="mp4a.40.2"'),
      h264aac:MediaSource.isTypeSupported('video/mp4; codecs="avc1.42E01E,mp4a.40.2"'),
      media:Array.from(document.querySelectorAll('video,audio')).map(v=>({playing:!v.paused,currentTime:v.currentTime,readyState:v.readyState,error:v.error&&v.error.code})),
      audio:window.__sirbAudioDiagnostics?.() ?? [],
      graphics:{webgpu:!!navigator.gpu,isolated:crossOriginIsolated,
        sharedArrayBuffer:typeof SharedArrayBuffer==='function',
        pointerLocked:!!document.pointerLockElement,
        canvases:Array.from(document.querySelectorAll('canvas')).map(c=>({width:c.width,height:c.height}))},
      url:location.href
    })''');
    if (mounted) setState(() => diagnostics = jsonEncode(result));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context),
        b = widget.browser,
        p = b.preferences,
        r = widget.runtime.resources,
        d = widget.device;
    return AnimatedBuilder(
      animation: Listenable.merge([p, b]),
      builder: (context, child) => Scaffold(
        appBar: AppBar(title: Text(l.settings)),
        body: BoundedPage(
          child: ListView(
            children: [
              ExpansionTile(
                initiallyExpanded: true,
                title: Text(l.general),
                children: [
                  _choice(
                    l.language,
                    p.language ?? Localizations.localeOf(context).languageCode,
                    {'ar': l.arabic, 'en': l.english},
                    (v) {
                      if (v != null) p.set('language', v);
                    },
                  ),
                  _choice(
                    l.theme,
                    p.theme.index,
                    {
                      ThemeMode.dark.index: l.dark,
                      ThemeMode.light.index: l.light,
                      ThemeMode.system.index: l.system,
                    },
                    (v) {
                      if (v != null) p.set('theme', v);
                    },
                  ),
                  ListTile(
                    title: Text(l.searchEngine),
                    subtitle: Text(l.duckduckgo),
                  ),
                  _choice(
                    l.startup,
                    p.startup,
                    {
                      'new': l.startupNew,
                      'restore': l.startupRestore,
                      'ask': l.startupAsk,
                    },
                    (v) {
                      if (v != null) p.set('startup', v);
                    },
                  ),
                  SwitchListTile(
                    title: Text(l.mouseNavigation),
                    subtitle: Text(l.mouseNavigationSubtitle),
                    value: p.mouseNavigation,
                    onChanged: (v) => p.set('mouse_navigation', v),
                  ),
                ],
              ),
              ExpansionTile(
                title: Text(l.performance),
                children: [
                  ListTile(
                    title: Text(l.device),
                    subtitle: Text(
                      '${l.cores(d.cores)} · ${l.gigabytes((d.ramBytes / 1073741824).toStringAsFixed(1))}',
                    ),
                  ),
                  ...d.gpus.map((g) {
                    // A saved preference is not proof of the live CEF adapter.
                    final isPreferred = widget.runtime.launchGpu == g.kind;
                    final kindLabel = switch (g.kind) {
                      'integrated' => l.integrated,
                      'discrete' => l.discrete,
                      _ => l.unknownHardware,
                    };
                    return ListTile(
                      leading: const Icon(Icons.memory),
                      title: Text(g.name),
                      subtitle: Text(
                        isPreferred
                            ? '$kindLabel · ${l.preferredGpu}'
                            : kindLabel,
                      ),
                      trailing: isPreferred
                          ? Chip(
                              label: Text(l.preferredGpu),
                              visualDensity: VisualDensity.compact,
                            )
                          : null,
                    );
                  }),
                  ListTile(
                    title: Text(
                      l.usage(
                        l.gigabytes(
                          (b.usage.ramBytes / 1073741824).toStringAsFixed(2),
                        ),
                      ),
                    ),
                    subtitle: Text('${b.usage.cpuPercent.toStringAsFixed(1)}%'),
                  ),
                  _choice(
                    l.cpu,
                    p.cpu,
                    {
                      0: l.unlimited,
                      for (var n = 1; n <= d.cores; n++) n: l.cores(n),
                    },
                    r.affinitySupported
                        ? (v) {
                            if (v != null) p.set('cpu', v);
                          }
                        : null,
                    hint: r.affinitySupported ? null : l.cpuUnavailable,
                  ),
                  _choice(
                    l.ram,
                    p.ramGb,
                    {
                      0: l.unlimited,
                      for (final n in {
                        1,
                        2,
                        4,
                        8,
                        16,
                        32,
                        64,
                        128,
                        p.ramGb,
                      }.where((n) => n > 0))
                        n: l.gigabytes(n.toString()),
                    },
                    (v) {
                      if (v != null) p.set('ram_gb', v);
                    },
                  ),
                  SwitchListTile(
                    title: Text(l.hardRam),
                    subtitle: hardAvailable ? null : Text(l.hardRamUnavailable),
                    value: p.hardRam && hardAvailable,
                    onChanged: hardAvailable
                        ? (v) => p.set('hard_ram', v)
                        : null,
                  ),
                  _choice(
                    l.gpu,
                    p.gpu,
                    {
                      'auto': l.automatic,
                      'discrete': l.discrete,
                      'integrated': l.integrated,
                    },
                    r.gpuSupported
                        ? (v) {
                            if (v != null) {
                              p.set('gpu', v);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(l.restartRequired),
                                  action: SnackBarAction(
                                    label: l.restart,
                                    onPressed: () async {
                                      try {
                                        await widget.runtime.restart();
                                      } catch (e) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                l.resourceError(e.toString()),
                                              ),
                                            ),
                                          );
                                        }
                                      }
                                    },
                                  ),
                                ),
                              );
                            }
                          }
                        : null,
                    hint: r.gpuSupported ? null : l.gpuUnavailable,
                  ),
                  ListTile(subtitle: Text(l.gpuSchedulingNotice)),
                  SwitchListTile(
                    title: Text(l.gameMode),
                    subtitle: Text(l.gameModeNotice),
                    value: p.gameMode,
                    onChanged: (v) async {
                      final previousGpu = widget.runtime.launchGpu;
                      await p.set('game_mode', v);
                      await b.reconfigure();
                      if (context.mounted &&
                          previousGpu != widget.runtime.launchGpu) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l.restartRequired)),
                        );
                      }
                    },
                  ),
                  SwitchListTile(
                    title: Text(l.graphicsCompatibility),
                    subtitle: Text(l.graphicsCompatibilityNotice),
                    value: p.graphicsCompatibility,
                    onChanged: (v) async {
                      await p.set('graphics_compatibility', v);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l.restartRequired)),
                        );
                      }
                    },
                  ),
                  SwitchListTile(
                    title: Text(l.acceleration),
                    value: p.acceleration,
                    onChanged: (v) => p.set('acceleration', v),
                  ),
                  _choice(
                    l.idleMinutes,
                    p.idleMinutes,
                    {
                      0: l.disabled,
                      1: l.minutes(1),
                      5: l.minutes(5),
                      10: l.minutes(10),
                      20: l.minutes(20),
                      30: l.minutes(30),
                      60: l.minutes(60),
                    },
                    (v) {
                      if (v != null) p.set('idle_minutes', v);
                    },
                  ),
                  _choice(
                    l.liveLimit,
                    p.liveLimit,
                    {
                      for (final n in [5, 10, 20, 35, 50, 100, 200])
                        n: l.tabCount(n),
                    },
                    (v) {
                      if (v != null) p.set('live_limit', v);
                    },
                  ),
                  SwitchListTile(
                    title: Text(l.focusLoading),
                    subtitle: Text(l.focusLoadingNotice),
                    value: p.focusLoading,
                    onChanged: (v) async {
                      await p.set('focus_loading', v);
                      await b.reconfigure();
                    },
                  ),
                  SwitchListTile(
                    title: Text(l.preload),
                    value: p.preload,
                    onChanged: p.gameMode || p.focusLoading
                        ? null
                        : (v) async {
                            await p.set('preload', v);
                            await b.reconfigure();
                          },
                  ),
                  _choice(
                    l.preloadLimit,
                    p.preloadLimit,
                    {
                      for (final n in [1, 2, 3, 4]) n: l.tabCount(n),
                    },
                    p.preload
                        ? (v) {
                            if (v != null) p.set('preload_limit', v);
                          }
                        : null,
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(l.restartRequired),
                  ),
                  FilledButton.icon(
                    onPressed: () async {
                      try {
                        await widget.runtime.restart();
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(l.resourceError(e.toString())),
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.restart_alt),
                    label: Text(l.restart),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
              ExpansionTile(
                title: Text(l.youtube),
                children: [
                  SwitchListTile(
                    title: Text(l.youtubeOriginalTitles),
                    subtitle: Text(l.youtubeOriginalTitlesNotice),
                    value: p.youtubeOriginalTitles,
                    onChanged: (v) async {
                      await p.set('youtube_original_titles', v);
                      await b.reconfigure();
                    },
                  ),
                ],
              ),
              ExpansionTile(
                title: Text(l.ads),
                children: [
                  SwitchListTile(
                    title: Text(l.blockEnabled),
                    value: p.blocking,
                    onChanged: (v) async {
                      await p.set('blocking', v);
                      await b.reconfigure();
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(l.adNotice),
                  ),
                  if (p.allowlist.isNotEmpty)
                    ListTile(title: Text(l.allowlist)),
                  ...p.allowlist.map(
                    (host) => ListTile(
                      title: Text(host),
                      trailing: IconButton(
                        tooltip: l.remove,
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          final list = p.allowlist.toList()..remove(host);
                          await p.set('allowlist', list);
                          await b.reconfigure();
                        },
                      ),
                    ),
                  ),
                  ListTile(
                    title: Text(l.adErrorLogs),
                    leading: const Icon(Icons.shield_outlined),
                    subtitle: FutureBuilder<int>(
                      future: b.store.errorLogCount(type: 'ad'),
                      builder: (context, snapshot) =>
                          Text(l.totalLogs(snapshot.data ?? 0)),
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => ErrorLogsScreen(
                          store: b.store,
                          initialFilter: 'ad',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              ExpansionTile(
                title: Text(l.errorLogs),
                children: [
                  ListTile(
                    title: Text(l.errorLogs),
                    leading: const Icon(Icons.list_alt),
                    subtitle: FutureBuilder<int>(
                      future: b.store.errorLogCount(type: 'errors'),
                      builder: (context, snapshot) =>
                          Text(l.totalLogs(snapshot.data ?? 0)),
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => ErrorLogsScreen(
                          store: b.store,
                          initialFilter: 'errors',
                        ),
                      ),
                    ),
                  ),
                  ListTile(
                    title: Text(l.adErrorLogs),
                    leading: const Icon(Icons.shield_outlined),
                    subtitle: FutureBuilder<int>(
                      future: b.store.errorLogCount(type: 'ad'),
                      builder: (context, snapshot) =>
                          Text(l.totalLogs(snapshot.data ?? 0)),
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => ErrorLogsScreen(
                          store: b.store,
                          initialFilter: 'ad',
                        ),
                      ),
                    ),
                  ),
                  ListTile(
                    title: Text(l.copyAll),
                    leading: const Icon(Icons.copy_all),
                    onTap: () async {
                      final logs = await b.store.errorLogs();
                      if (logs.isNotEmpty) {
                        final text = logs
                            .map((e) => e.toFormattedString())
                            .join('\n---\n');
                        await Clipboard.setData(ClipboardData(text: text));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(l.copiedToClipboard)),
                          );
                        }
                      } else if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text(l.empty)));
                      }
                    },
                  ),
                  ListTile(
                    title: Text(l.exportTxt),
                    leading: const Icon(Icons.file_download_outlined),
                    onTap: () async {
                      final logs = await b.store.errorLogs();
                      if (logs.isEmpty) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text(l.empty)));
                        }
                        return;
                      }
                      try {
                        final home =
                            Platform.environment['HOME'] ??
                            Platform.environment['USERPROFILE'] ??
                            '.';
                        final downloadsDir = Directory(
                          path.join(home, 'Downloads'),
                        );
                        final targetDir = downloadsDir.existsSync()
                            ? downloadsDir
                            : Directory(home);
                        final timestamp = DateTime.now()
                            .toIso8601String()
                            .replaceAll(':', '-')
                            .split('.')
                            .first;
                        final file = File(
                          path.join(
                            targetDir.path,
                            'sirb_error_logs_$timestamp.txt',
                          ),
                        );
                        final buffer = StringBuffer();
                        buffer.writeln(
                          '========================================',
                        );
                        buffer.writeln('Sirb Error Logs Export');
                        buffer.writeln(
                          'Timestamp: ${DateTime.now().toIso8601String()}',
                        );
                        buffer.writeln('Total Entries: ${logs.length}');
                        buffer.writeln(
                          '========================================\n',
                        );
                        for (final entry in logs) {
                          buffer.writeln(entry.toFormattedString());
                          buffer.writeln(
                            '----------------------------------------',
                          );
                        }
                        await file.writeAsString(buffer.toString());
                        if (context.mounted) {
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
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(l.resourceError(e.toString())),
                            ),
                          );
                        }
                      }
                    },
                  ),
                  ListTile(
                    title: Text(l.clearLogs),
                    leading: const Icon(Icons.delete_sweep_outlined),
                    onTap: () => _clear(() => b.store.clearErrorLogs()),
                  ),
                ],
              ),
              ExpansionTile(
                title: Text(l.privacy),
                children: [
                  ListTile(
                    title: Text(l.profile),
                    subtitle: SelectableText(b.engine.profile),
                  ),
                  ListTile(
                    title: Text(l.clearHistory),
                    leading: const Icon(Icons.history),
                    onTap: () => _clear(() => b.store.clearVisits()),
                  ),
                  ListTile(
                    title: Text(l.clearCookies),
                    leading: const Icon(Icons.cookie_outlined),
                    onTap: () => _clear(b.engine.clearCookies),
                  ),
                  ListTile(
                    title: Text(l.clearCache),
                    leading: const Icon(Icons.cleaning_services_outlined),
                    onTap: () =>
                        _clear(() => widget.runtime.restart(clearCache: true)),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(l.codecNotice),
                  ),
                  ListTile(
                    title: Text(l.mediaTests),
                    subtitle: diagnostics == null
                        ? null
                        : SelectableText(l.testResult(diagnostics!)),
                    trailing: IconButton(
                      tooltip: l.runMediaTests,
                      onPressed: _diagnose,
                      icon: const Icon(Icons.play_circle_outline),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Divider(),
              Padding(
                padding: const EdgeInsets.only(top: 24, bottom: 16),
                child: Text(
                  l.developer,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Text(
                DeveloperInfo.name,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 16),
              _buildContactItem(
                context,
                icon: Icons.alternate_email_rounded,
                label: l.email,
                value: DeveloperInfo.email,
                onTap: () => _launchUrl('mailto:${DeveloperInfo.email}'),
              ),
              const SizedBox(height: 16),
              _buildContactItem(
                context,
                icon: Icons.public_rounded,
                label: l.website,
                value: 'hossam-majrashi.github.io/Works/',
                onTap: () => _launchUrl(DeveloperInfo.websiteUrl),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
