class ErrorLogEntry {
  const ErrorLogEntry({
    required this.id,
    required this.time,
    required this.type,
    required this.message,
    this.url,
    this.details,
  });

  final int id;
  final DateTime time;
  final String type;
  final String message;
  final String? url;
  final String? details;

  Map<String, dynamic> toMap() => {
    if (id > 0) 'id': id,
    'time': time.millisecondsSinceEpoch,
    'type': type,
    'message': message,
    'url': url,
    'details': details,
  };

  factory ErrorLogEntry.fromMap(Map<String, dynamic> map) => ErrorLogEntry(
    id: (map['id'] as num?)?.toInt() ?? 0,
    time: DateTime.fromMillisecondsSinceEpoch(
      (map['time'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
    ),
    type: (map['type'] as String?) ?? 'system',
    message: (map['message'] as String?) ?? '',
    url: map['url'] as String?,
    details: map['details'] as String?,
  );

  String toFormattedString() {
    final buffer = StringBuffer();
    final timeStr = time.toIso8601String().replaceFirst('T', ' ').split('.').first;
    buffer.writeln('[$timeStr] [$type] $message');
    if (url != null && url!.isNotEmpty) {
      buffer.writeln('  URL: $url');
    }
    if (details != null && details!.isNotEmpty) {
      buffer.writeln('  Details: $details');
    }
    return buffer.toString().trimRight();
  }
}
