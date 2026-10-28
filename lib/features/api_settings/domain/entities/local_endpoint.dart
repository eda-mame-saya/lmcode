/// localhost サイドカー用のホスト／ポート組み立て。
abstract final class LocalEndpoint {
  /// `http://127.0.0.1:8765` → host=`http://127.0.0.1`, port=`8765`
  static ({String host, int port}) split(
    String raw, {
    required int defaultPort,
    String defaultHost = 'http://127.0.0.1',
  }) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return (host: defaultHost, port: defaultPort);
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.host.isEmpty) {
      // ポートだけ・ホストだけのフォールバック
      final asInt = int.tryParse(trimmed);
      if (asInt != null && asInt > 0 && asInt <= 65535) {
        return (host: defaultHost, port: asInt);
      }
      return (host: trimmed.replaceAll(RegExp(r'/+$'), ''), port: defaultPort);
    }
    final port = uri.hasPort ? uri.port : defaultPort;
    final host = uri.hasScheme
        ? '${uri.scheme}://${uri.host}'
        : 'http://${uri.host}';
    return (host: host, port: port);
  }

  /// host=`http://127.0.0.1` + port=`8765` → `http://127.0.0.1:8765`
  static String compose(String host, int port) {
    final trimmed = host.trim().replaceAll(RegExp(r'/+$'), '');
    if (trimmed.isEmpty) {
      return 'http://127.0.0.1:$port';
    }
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.host.isNotEmpty) {
      final scheme = uri.hasScheme ? uri.scheme : 'http';
      return Uri(
        scheme: scheme,
        host: uri.host,
        port: port,
      ).toString();
    }
    // 既に :port 付きなら付け替え
    final withoutTrailingSlash = trimmed.replaceAll(RegExp(r'/+$'), '');
    final match = RegExp(r'^(.*):(\d+)$').firstMatch(withoutTrailingSlash);
    if (match != null) {
      return '${match.group(1)}:$port';
    }
    return '$withoutTrailingSlash:$port';
  }

  static int? parsePort(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final value = int.tryParse(trimmed);
    if (value == null || value < 1 || value > 65535) return null;
    return value;
  }
}
