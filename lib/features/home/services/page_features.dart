import '../../youtube/services/focus_requests_script.dart';
import '../../youtube/services/original_titles_script.dart';
import 'focus_loading_script.dart';

// Shared by document-start injection and live preference updates on every
// desktop platform. Independent of the ad shield and its per-site exceptions.
String pageFeatures({
  required bool focusLoading,
  required bool youtubeOriginalTitles,
}) =>
    '''
window.__sirbFocusLoading=$focusLoading;
window.__sirbOriginalTitles=$youtubeOriginalTitles;
$focusLoadingScript
$youtubeFocusRequestsScript
$youtubeOriginalTitlesScript
window.__sirbUpdateFocusLoading?.();
window.__sirbFlushYoutubeRequests?.();
window.__sirbUpdateOriginalTitles?.();
''';
