/// Gemma 4 の MTP 下書き係（`gemma4-assistant`）と本体 GGUF の対応。
///
/// 下書き係は単体では会話できない。本体と同じディレクトリに置き、
/// ファイル名の系統が一致するときだけ `llama-server` の `--model-draft` に渡す。
class GemmaMtpDraft {
  const GemmaMtpDraft._();

  /// 12B の下書きは深いほど当たりが落ちるため、試験の先読みは 2 トークン。
  static const specDraftNMax = 2;

  static bool isDraftFileName(String fileName) {
    final stem = _stem(fileName);
    if (stem == null) return false;
    return stem.startsWith('mtp-') || stem.contains('-mtp');
  }

  /// [siblingFileNames] から、[targetFileName] に対応する下書き係を1つ返す。
  static String? selectDraftFileName({
    required String targetFileName,
    required Iterable<String> siblingFileNames,
  }) {
    final targetKey = familyKey(targetFileName);
    if (targetKey == null || isDraftFileName(targetFileName)) return null;

    final matches = <String>[];
    for (final name in siblingFileNames) {
      if (!isDraftFileName(name)) continue;
      if (familyKey(name) != targetKey) continue;
      matches.add(name);
    }
    if (matches.isEmpty) return null;
    matches.sort((a, b) {
      final aRoot = _stem(a)!.startsWith('mtp-');
      final bRoot = _stem(b)!.startsWith('mtp-');
      if (aRoot != bRoot) return aRoot ? -1 : 1;
      final byLength = a.length.compareTo(b.length);
      if (byLength != 0) return byLength;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });
    return matches.first;
  }

  /// 量子化名を外したモデル系統。`gemma-4-12b-it-Q4_K_M` と
  /// `mtp-gemma-4-12b-it` はどちらも `gemma-4-12b-it`。
  static String? familyKey(String fileName) {
    var stem = _stem(fileName);
    if (stem == null) return null;
    if (stem.startsWith('mtp-')) stem = stem.substring(4);
    final quant = RegExp(
      r'-(?:ud-)?(?:iq\d+_[a-z0-9]+|q\d+(?:_[a-z0-9]+)*|bf16|f16|f32)$',
    );
    while (true) {
      final withoutMtp = stem!.replaceAll(RegExp(r'-mtp(?=-|$)'), '');
      final withoutQuant = withoutMtp.replaceFirst(quant, '');
      if (withoutQuant == stem) return withoutQuant;
      stem = withoutQuant;
    }
  }

  static String? _stem(String fileName) {
    final base = fileName.replaceAll(r'\', '/').split('/').last.trim();
    final lower = base.toLowerCase();
    if (!lower.endsWith('.gguf')) return null;
    return lower.substring(0, lower.length - 5);
  }
}
