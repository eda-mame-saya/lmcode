import 'package:flutter/foundation.dart';

import '../domain/ai_debug_log_entry.dart';

/// 生成AIまわりのデバッグログ（メモリ上・最大件数リング）。
///
/// 取得経路（`info` / `warn` / `error` / `entries` / `exportAll`）は従来どおり。
/// UI は [ChangeNotifier] で一覧を購読する。
class AiDebugLogStore extends ChangeNotifier {
  static const maxEntries = 200;

  final List<AiDebugLogEntry> _entries = <AiDebugLogEntry>[];

  List<AiDebugLogEntry> get entries =>
      List<AiDebugLogEntry>.unmodifiable(_entries);

  int get length => _entries.length;

  void clear() {
    if (_entries.isEmpty) return;
    _entries.clear();
    notifyListeners();
  }

  void info(
    String source,
    String message, {
    Map<String, String>? details,
  }) {
    _add(
      level: AiDebugLogLevel.info,
      source: source,
      message: message,
      details: details,
    );
  }

  void warn(
    String source,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, String>? details,
  }) {
    _add(
      level: AiDebugLogLevel.warn,
      source: source,
      message: message,
      error: error,
      stackTrace: stackTrace,
      details: details,
    );
  }

  void error(
    String source,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, String>? details,
  }) {
    _add(
      level: AiDebugLogLevel.error,
      source: source,
      message: message,
      error: error,
      stackTrace: stackTrace,
      details: details,
    );
  }

  void _add({
    required AiDebugLogLevel level,
    required String source,
    required String message,
    Object? error,
    StackTrace? stackTrace,
    Map<String, String>? details,
  }) {
    _entries.insert(
      0,
      AiDebugLogEntry(
        at: DateTime.now(),
        level: level,
        source: source,
        message: message,
        error: error?.toString(),
        stackTrace: stackTrace?.toString(),
        details: details == null
            ? const {}
            : Map<String, String>.unmodifiable(details),
      ),
    );
    while (_entries.length > maxEntries) {
      _entries.removeLast();
    }
    notifyListeners();
  }

  String exportAll() {
    if (_entries.isEmpty) return '（ログはありません）';
    return _entries.map((e) => e.toExportBlock()).join('\n\n---\n\n');
  }
}
