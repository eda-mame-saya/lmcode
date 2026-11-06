import 'coding_novel_settings.dart';

/// 小説原稿（`.txt`）の整形。
///
/// - 地の文とセリフのあいだに空行を1つ入れる
/// - 行頭インデントを設定どおりに揃える（セリフは設定次第）
abstract final class CodingNovelFormatter {
  /// [settings] に従って整形する。
  static String format(
    String text, {
    required CodingNovelSettings settings,
    int? startLineIndex,
    int? endLineIndex,
  }) {
    final endsWithNewline = text.endsWith('\n');
    final lines = text.split('\n');
    if (endsWithNewline && lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }
    if (lines.isEmpty) return text;

    final start = (startLineIndex ?? 0).clamp(0, lines.length);
    final end =
        (endLineIndex ?? (lines.length - 1)).clamp(start, lines.length - 1);

    final normalized = <String>[
      for (var i = 0; i < lines.length; i++)
        if (i >= start && i <= end)
          _normalizeLine(lines[i], settings)
        else
          lines[i],
    ];

    final withGaps = _ensureNarrativeDialogueGaps(
      normalized,
      settings: settings,
      start: start,
      end: end,
    );

    var out = withGaps.join('\n');
    if (endsWithNewline) out = '$out\n';
    return out;
  }

  /// 改行直後に入れるインデント（Enter 用）。
  static String newlineIndent(CodingNovelSettings settings) =>
      settings.newlineIndent;

  /// セリフ行か。字下げを除いた1行の先頭と末尾が、登録した開き／閉じの組と一致するとき。
  static bool isDialogueLine(
    String line, {
    required CodingNovelSettings settings,
  }) {
    final body = _stripLeadingIndent(line).trimRight();
    if (body.isEmpty) return false;
    for (final d in settings.effectiveDialogueDelimiters) {
      if (body.startsWith(d.open) && body.endsWith(d.close)) {
        // 開きと閉じが同じ文字のとき、1文字だけではペアにならない
        if (d.open == d.close && body.length < d.open.length * 2) {
          continue;
        }
        return true;
      }
    }
    return false;
  }

  /// セリフ行でインデント不要なら字下げを外す。
  static String maybeStripDialogueIndent(
    String line, {
    required CodingNovelSettings settings,
  }) {
    if (settings.indentDialogue) return line;
    if (!isDialogueLine(line, settings: settings)) return line;
    return _stripLeadingIndent(line);
  }

  static String _normalizeLine(String line, CodingNovelSettings settings) {
    if (line.trim().isEmpty) return '';
    final body = _stripLeadingIndent(line);
    if (body.isEmpty) return '';
    final dialogue = isDialogueLine(body, settings: settings);
    if (dialogue && !settings.indentDialogue) return body;
    final indent = settings.newlineIndent;
    if (indent.isEmpty) return body;
    return '$indent$body';
  }

  static String _stripLeadingIndent(String line) {
    var i = 0;
    while (i < line.length) {
      final c = line.codeUnitAt(i);
      if (c == 0x20 || c == 0x09 || c == 0x3000) {
        i++;
        continue;
      }
      break;
    }
    return line.substring(i);
  }

  /// 地の文 ↔ セリフの境に空行を1つ入れる。
  static List<String> _ensureNarrativeDialogueGaps(
    List<String> lines, {
    required CodingNovelSettings settings,
    required int start,
    required int end,
  }) {
    if (lines.isEmpty) return lines;
    final out = <String>[];
    String? prevKind; // 'empty' | 'dialogue' | 'narrative'
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final inRange = i >= start && i <= end;
      final kind = line.isEmpty
          ? 'empty'
          : (isDialogueLine(line, settings: settings)
              ? 'dialogue'
              : 'narrative');

      if (inRange &&
          prevKind != null &&
          prevKind != 'empty' &&
          kind != 'empty' &&
          prevKind != kind) {
        if (out.isEmpty || out.last.isNotEmpty) {
          out.add('');
        }
      }
      out.add(line);
      prevKind = kind;
    }
    return out;
  }
}
