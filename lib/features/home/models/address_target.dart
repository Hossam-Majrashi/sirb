enum AddressKind { newTab, navigation, search }

class AddressTarget {
  const AddressTarget._(this.kind, this.value);
  final AddressKind kind;
  final String value;
  factory AddressTarget.parse(String input) {
    final text = input.trim();
    if (text == 'sirb:new') return AddressTarget._(AddressKind.newTab, text);
    final uri = Uri.tryParse(text);
    if (uri != null &&
        ['http', 'https', 'file'].contains(uri.scheme) &&
        (uri.host.isNotEmpty || uri.scheme == 'file')) {
      return AddressTarget._(AddressKind.navigation, uri.toString());
    }
    if (!text.contains(RegExp(r'\s')) &&
        RegExp(
          r'^(localhost|(?:[\w-]+\.)+[\w-]{2,}|\d+\.\d+\.\d+\.\d+)(:\d+)?([/?#].*)?$',
        ).hasMatch(text)) {
      return AddressTarget._(AddressKind.navigation, 'https://$text');
    }
    return AddressTarget._(AddressKind.search, text);
  }
}
