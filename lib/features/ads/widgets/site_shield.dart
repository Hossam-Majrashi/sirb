import 'package:flutter/material.dart';
import '../../../core/l10n/app_localizations.dart';

class SiteShield extends StatelessWidget {
  const SiteShield({
    super.key,
    required this.enabled,
    required this.blocked,
    this.onToggle,
  });
  final bool enabled;
  final int blocked;
  final VoidCallback? onToggle;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Badge(
      label: Text('$blocked'),
      isLabelVisible: blocked > 0,
      child: IconButton(
        tooltip: '${l.siteBlocking} · ${l.blocked(blocked)}',
        onPressed: onToggle,
        icon: Icon(
          enabled ? Icons.shield_outlined : Icons.shield_moon_outlined,
          size: 20,
        ),
      ),
    );
  }
}
