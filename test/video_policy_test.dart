import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sirb/features/ads/ad_rules.dart';
import 'package:sirb/features/ads/services/ad_blocker.dart';
import 'package:sirb/features/ads/sites/kick_ad_rules.dart';
import 'package:sirb/features/ads/sites/twitch_ad_rules.dart';
import 'package:sirb/features/ads/sites/youtube_ad_rules.dart';
import 'package:sirb/features/home/services/document_scripts.dart';
import 'package:sirb/features/settings/services/preferences_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('independent platform rules compose without blocking content CDNs', () {
    expect(blockedDomains, containsAll(youtubeBlockedDomains));
    expect(blockedDomains, containsAll(twitchBlockedDomains));
    expect(blockedUrlPatterns, containsAll(kickBlockedUrlPatterns));
    expect(cosmeticSelectorsBySite['kick.com'], kickCosmeticSelectors);
    expect(cosmeticSelectorsBySite['twitch.tv'], twitchCosmeticSelectors);
    final patterns = blockedUrlPatterns.map(RegExp.new).toList();
    for (final url in [
      'https://r1.googlevideo.com/videoplayback?itag=248',
      'https://usher.ttvnw.net/api/channel/hls/fixture.m3u8',
      'https://video-edge.ttvnw.net/vod/fixture/segment.ts',
      'https://gql.twitch.tv/gql',
      'https://fixture.playback.live-video.net/api/video/v1/fixture.m3u8',
      'https://kick.com/api/v2/channels/fixture',
      'https://kick.com/video/fixture',
      'https://notyoutube.com/pagead/probe',
    ]) {
      final host = Uri.parse(url).host;
      expect(
        blockedDomains.any((d) => host == d || host.endsWith('.$d')),
        false,
        reason: url,
      );
      expect(patterns.any((p) => p.hasMatch(url)), false, reason: url);
    }
    for (final url in [
      'https://www.youtube.com/pagead/probe',
      'https://www.twitch.tv/ads/probe',
      'https://kick.com/api/v2/ads/probe',
    ]) {
      expect(patterns.any((p) => p.hasMatch(url)), true, reason: url);
    }
  });

  test(
    'shield off and per-site exceptions preserve the shared video policy',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = PreferencesService(
        await SharedPreferences.getInstance(),
      );
      final blocker = AdBlocker(preferences);
      for (final site in ['youtube.com', 'twitch.tv', 'kick.com']) {
        await blocker.toggleSite('https://$site/channel');
        expect(blocker.enabledFor('https://www.$site/channel'), false);
      }
      await preferences.set('blocking', false);
      expect(blocker.documentScript, isEmpty);
      final script = documentTelemetry(
        preload: false,
        colorScheme: 'light dark',
      );
      expect(script, contains('__sirbVideoPriority'));
      expect(script, contains('kick'));
      expect(youtubeScripts.join(), isNot(contains('triggerFlexyUpdate')));
      expect(youtubeScripts.join(), isNot(contains('setInterval')));
    },
  );
}
