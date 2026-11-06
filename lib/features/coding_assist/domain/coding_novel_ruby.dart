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
