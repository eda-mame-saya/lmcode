/// 生成AIデバッグログの深刻度。
enum AiDebugLogLevel {
  info,
  warn,
  error;

  String get label => switch (this) {
        AiDebugLogLevel.info => 'INFO',
        AiDebugLogLevel.warn => 'WARN',
        AiDebugLogLevel.error => 'ERROR',
      };
}

/// 生成AIデバッグログの1件。
class AiDebugLogEntry {
  AiDebugLogEntry({
    required this.at,
    required this.level,
    required this.source,
    required this.message,
    this.error,
    this.stackTrace,
    this.details = const {},
  });

  final DateTime at;
  final AiDebugLogLevel level;
  final String source;
  final String message;
  final String? error;
  final String? stackTrace;
  final Map<String, String> details;

  String get formattedTimestamp {
    final local = at.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    String three(int n) => n.toString().padLeft(3, '0');
    return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}.${three(local.millisecond)}';
  }

  String toExportBlock() {
    final buffer = StringBuffer()
      ..writeln('[$formattedTimestamp] ${level.label} / $source')
      ..writeln(message);
    if (error != null && error!.isNotEmpty) {
      buffer.writeln('error: $error');
    }
    if (details.isNotEmpty) {
      for (final e in details.entries) {
        buffer.writeln('${e.key}: ${e.value}');
      }
    }
    if (stackTrace != null && stackTrace!.isNotEmpty) {
      buffer.writeln('stack:');
      buffer.writeln(stackTrace);
    }
    return buffer.toString().trimRight();
  }
}
