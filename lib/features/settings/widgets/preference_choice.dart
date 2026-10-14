import 'package:flutter/material.dart';

class PreferenceChoice<T> extends StatelessWidget {
  const PreferenceChoice({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    this.onChanged,
    this.hint,
  });
  final String label;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T?>? onChanged;
  final String? hint;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: DropdownButtonFormField<T>(
      initialValue: options.containsKey(value) ? value : options.keys.first,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        helperText: hint,
        helperMaxLines: 3,
      ),
      items: options.entries
          .map(
            (e) => DropdownMenuItem(
              value: e.key,
              child: Text(
                e.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: onChanged,
    ),
  );
}
