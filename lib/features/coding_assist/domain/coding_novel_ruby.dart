/// 小説家になろう系のルビ記法: `|漢字《かんじ》`（先頭 `|` は全角 `｜` も可）。
abstract final class CodingNovelRuby {
  /// なろう記法のルビ。
  static final pattern = RegExp(
    r'[|｜]([^|｜《》\n]{1,30})《([^《》\n]{1,30})》',
  );

  /// 挿入用のなろう記法文字列。
  static String wrap({required String base, required String ruby}) {
    final b = base.trim();
    final r = ruby.trim();
    if (b.isEmpty && r.isEmpty) return '|《》';
    return '|$b《$r》';
  }

  /// 強調ルビ（傍点）の文字。
  static const emphasisMark = '・';

  /// 強調ルビ。なろう記法ではズレを防ぐため **一文字ずつ** `|字《・》` にする。
  ///
  /// 空白・改行はそのまま残す。既にルビ記法になっている範囲は二重に振らず、
  /// 親文字だけを一文字ずつ強調に置き換える。
  static String emphasize(String text) {
    if (text.isEmpty) return text;
    final buf = StringBuffer();
    for (final span in parse(text)) {
      final plain = switch (span) {
        CodingNovelPlainSpan(:final text) => text,
        CodingNovelRubySpan(:final baseString) => baseString,
      };
      for (final rune in plain.runes) {
        final ch = String.fromCharCode(rune);
        if (_isSkippable(ch)) {
          buf.write(ch);
        } else {
          buf.write('|$ch《$emphasisMark》');
        }
      }
    }
    return buf.toString();
  }

  static bool _isSkippable(String ch) =>
      ch == '\n' || ch == '\r' || ch == '\t' || ch == ' ' || ch == '\u3000';

  /// 本文をルビ付きのインライン要素へ分解する。
  static List<CodingNovelInlineSpan> parse(String text) {
    if (text.isEmpty) return const [];
    final out = <CodingNovelInlineSpan>[];
    var start = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > start) {
        out.add(CodingNovelPlainSpan(text.substring(start, match.start)));
      }
      out.add(
        CodingNovelRubySpan(
          baseString: match.group(1) ?? '',
          ruby: match.group(2) ?? '',
        ),
      );
      start = match.end;
    }
    if (start < text.length) {
      out.add(CodingNovelPlainSpan(text.substring(start)));
    }
    return out;
  }
}

sealed class CodingNovelInlineSpan {
  const CodingNovelInlineSpan();
}

final class CodingNovelPlainSpan extends CodingNovelInlineSpan {
  const CodingNovelPlainSpan(this.text);
  final String text;
}

final class CodingNovelRubySpan extends CodingNovelInlineSpan {
  const CodingNovelRubySpan({required this.baseString, required this.ruby});
  final String baseString;
  final String ruby;
}
