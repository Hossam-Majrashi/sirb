import 'package:flutter/material.dart';

import '../../../core/l10n/app_localizations.dart';

class StreamCodecNotice extends StatelessWidget {
  const StreamCodecNotice({super.key, required this.onDetails});

  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(l.streamCodecUnavailable)),
          IconButton(
            tooltip: l.mediaTests,
            icon: const Icon(Icons.troubleshoot),
            onPressed: onDetails,
          ),
        ],
      ),
    );
  }
}
