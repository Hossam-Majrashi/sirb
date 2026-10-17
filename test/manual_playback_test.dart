import 'package:flutter_test/flutter_test.dart';
import 'package:sirb/features/home/services/document_scripts.dart';
import 'package:sirb/features/home/services/runtime_error_policy.dart';

void main() {
  test(
    'manual media policy is independent of speculation and shield settings',
    () {
      for (final preload in [false, true]) {
        final script = documentTelemetry(
          preload: preload,
          colorScheme: 'light',
        );
        expect(script, contains('__sirbManualPlayback'));
        expect(script, contains('!navigator.userActivation.hasBeenActive'));
        expect(
          script,
          contains('Sirb requires player interaction before playback'),
        );
        expect(
          script,
          isNot(contains('Speculative tab requires user activation')),
        );
      }
    },
  );

  test('expected playback races are not faults, genuine failures remain', () {
    for (final message in [
      'Sirb requires player interaction before playback',
      'Uncaught (in promise) NotAllowedError: Sirb requires player interaction before playback',
      'The play() request was interrupted by a call to pause(). https://goo.gl/LdLk22',
      'Uncaught (in promise) AbortError: The play() request was interrupted by a new load request.',
    ]) {
      expect(isExpectedPlaybackDiagnostic(message), true, reason: message);
    }
    for (final message in [
      'NotAllowedError: play() failed because the user did not interact',
      'AbortError: Failed to fetch media',
      'NotSupportedError: The element has no supported sources.',
      'DEMUXER_ERROR_NO_SUPPORTED_STREAMS',
      'Resource request failed',
      "Blocked script execution in 'about:blank' because the document's frame is sandboxed",
      'Custom error: The play() request was interrupted by a call to pause().',
    ]) {
      expect(isExpectedPlaybackDiagnostic(message), false, reason: message);
    }
  });
}
