import 'package:flutter/services.dart';
import 'package:webview_cef/webview_cef.dart';
import '../../features/ads/services/ad_blocker.dart';
import '../../features/home/services/document_scripts.dart';

class BrowserEngine {
  BrowserEngine({required this.profile, required this.blocker});
  final String profile;
  final AdBlocker blocker;
  static const channel = MethodChannel('webview_cef');
  String colorScheme = 'light dark';
  Future<void> configure() => channel.invokeMethod(
    'sirbConfigure',
    blocker.configuration(
      profile,
      documentTelemetry(
        preload: blocker.preferences.preload,
        colorScheme: colorScheme,
      ),
    ),
  );
  Future<void> initialize() async {
    await configure();
    await WebviewManager().initialize();
  }

  Future<int> openGameWindow(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw ArgumentError.value(url, 'url');
    }
    final id = await channel.invokeMethod<int>('openGameWindow', url);
    if (id == null || id < 0) {
      throw StateError('Native game window creation failed');
    }
    return id;
  }

  Future<void> clearCookies() => channel.invokeMethod('sirbClearCookies');
  Future<void> shutdown() => WebviewManager().quit();
}
