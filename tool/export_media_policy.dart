import 'dart:convert';
import 'dart:io';
import 'package:sirb/features/home/services/media_playback_script.dart';
import 'package:sirb/features/home/services/runtime_error_script.dart';

void main() => stdout.write(
  jsonEncode({
    'playback': mediaPlaybackScript,
    'errors': runtimeErrorTelemetry,
  }),
);
