import 'dart:convert';

/// One structured, already-redacted diagnostic log line.
class DiagnosticEvent {
  DiagnosticEvent({
    required this.timestamp,
    required this.category,
    required this.message,
    this.properties = const {},
  });

  final DateTime timestamp;
  final String category;
  final String message;
  final Map<String, String> properties;

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'category': category,
    'message': message,
    'properties': properties,
  };

  String encode() => jsonEncode(toJson());
}
