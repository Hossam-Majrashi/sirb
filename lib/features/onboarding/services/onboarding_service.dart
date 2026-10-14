import 'package:flutter/foundation.dart';
import '../../settings/services/preferences_service.dart';
import '../models/onboarding_step.dart';

class OnboardingService extends ChangeNotifier {
  OnboardingService(this.preferences);
  final PreferencesService preferences;
  OnboardingStep step = OnboardingStep.introduction;
  Future<void> advance() async {
    if (step == OnboardingStep.appearance) {
      await preferences.set('onboarding_done', true);
    } else {
      step = OnboardingStep.values[step.index + 1];
      notifyListeners();
    }
  }
}
