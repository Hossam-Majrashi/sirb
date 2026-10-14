import 'package:flutter/material.dart';
import '../../../core/l10n/app_localizations.dart';

class OnboardingLogo extends StatelessWidget {
  const OnboardingLogo({super.key});
  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/icon/icon.png',
    height: 150,
    semanticLabel: AppLocalizations.of(context).appName,
  );
}
