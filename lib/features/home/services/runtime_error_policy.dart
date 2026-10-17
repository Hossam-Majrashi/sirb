// Chromium can echo an unhandled play rejection to the console as well as the
// document observer. Ignore only our own activation denial and the documented
// play/pause/load cancellation; decoder, network and real permission errors stay.
bool isExpectedPlaybackDiagnostic(String message) {
  final text = message.replaceFirst(
    RegExp(r'^Uncaught (?:\(in promise\) )?'),
    '',
  );
  if (text ==
          'NotAllowedError: Sirb requires player interaction before playback' ||
      text == 'Sirb requires player interaction before playback') {
    return true;
  }
  return RegExp(
    r'^(?:AbortError: )?The play\(\) request was interrupted by '
    r'(?:a call to pause\(\)|a new load request)(?:\.|$)',
  ).hasMatch(text);
}
