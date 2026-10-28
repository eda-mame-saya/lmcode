import 'coding_harness_settings.dart';

/// Agent から呼ぶシンボル探索。言語サーバが無いときは [isReady] が false。
abstract class CodingSymbolIndex {
  bool get isReady;

  /// 記号の件数上限。言語サーバを持たない実装は何もしない。
  void applyHarness(CodingHarnessSettings settings) {}

  Future<String> fileOutline({
    required String relativePath,
    String? bufferText,
  });

  Future<String> workspaceSymbol({required String query});

  Future<String> goToDefinition({
    required String relativePath,
    required int line,
    int? column,
    String? symbol,
    String? bufferText,
    Map<String, String> openBuffers = const {},
  });

  Future<String> findReferences({
    required String relativePath,
    required int line,
    int? column,
    String? symbol,
    String? bufferText,
    Map<String, String> openBuffers = const {},
  });

  /// 開いているタブと取り込み中ファイルのシグネチャ。ツール呼び出しには依存しない。
  Future<String> signatureMap(
    List<({String relativePath, String content})> files,
  );
}
