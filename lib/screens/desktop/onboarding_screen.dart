import 'package:flutter/material.dart';
import '../../core/l10n/app_localizations.dart';
import '../../features/onboarding/services/onboarding_service.dart';
import '../../features/onboarding/widgets/onboarding_logo.dart';
import '../../features/settings/services/preferences_service.dart';
import '../../shared/widgets/bounded_page.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.preferences});
  final PreferencesService preferences;
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final progress = OnboardingService(widget.preferences)
    ..addListener(refresh);
  int get step => progress.step.index;
  void refresh() => setState(() {});
  @override
  void dispose() {
    progress.removeListener(refresh);
    progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context), p = widget.preferences;
    return Scaffold(
      body: SingleChildScrollView(
        child: BoundedPage(
          width: 680,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 56),
              const OnboardingLogo(),
              const SizedBox(height: 32),
              Text(
                switch (step) {
                  0 => l.appName,
                  1 => l.language,
                  _ => l.theme,
                },
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 24),
              if (step == 0)
                Text(
                  l.intro,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              if (step == 1) ...[
                RadioGroup<String>(
                  groupValue:
                      p.language ??
                      Localizations.localeOf(context).languageCode,
                  onChanged: (value) {
                    if (value != null) p.set('language', value);
                  },
                  child: Column(
                    children: [
                      RadioListTile(value: 'ar', title: Text(l.arabic)),
                      RadioListTile(value: 'en', title: Text(l.english)),
                    ],
                  ),
                ),
              ],
              if (step == 2)
                RadioGroup<int>(
                  groupValue: p.theme.index,
                  onChanged: (v) {
                    if (v != null) p.set('theme', v);
                  },
                  child: Column(
                    children: [
                      RadioListTile(
                        value: ThemeMode.dark.index,
                        title: Text(l.dark),
                      ),
                      RadioListTile(
                        value: ThemeMode.light.index,
                        title: Text(l.light),
                      ),
                      RadioListTile(
                        value: ThemeMode.system.index,
                        title: Text(l.system),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () async {
                  await progress.advance();
                },
                child: Text(step == 2 ? l.start : l.next),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
