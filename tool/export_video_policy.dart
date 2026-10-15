import 'dart:convert';
import 'dart:io';

import 'package:sirb/features/ads/ad_rules.dart';
import 'package:sirb/features/ads/services/ad_document_script.dart';
import 'package:sirb/features/home/services/video_priority_script.dart';
import 'package:sirb/features/home/services/stream_compatibility_script.dart';

void main() => stdout.writeln(
  jsonEncode({
    'ads': adDocumentScript([]),
    'excepted': adDocumentScript(['youtube.com', 'twitch.tv', 'kick.com']),
    'priority': videoPriorityScript,
    'streamCompatibility': streamCompatibilityScript,
    'domains': blockedDomains,
    'patterns': blockedUrlPatterns,
  }),
);
