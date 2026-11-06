import 'package:path/path.dart' as p;

/// インデント幅（空白 2 / 4）に揃える／構造に沿って付け直す。
abstract final class CodingIndentAligner {
  /// [indentSize] は 2 または 4。
  ///
  /// C 系（Dart／JS／…）は `{` `}` `[` `]` `(` `)` の深さで再インデントする。
  /// Python／YAML 等は先頭空白を幅の倍数に正規化するだけ（段数は変えない）。
  ///
  /// [startLineIndex]〜[endLineIndex] を指定した場合も深さは全文から計算し、
  /// 書き換えは範囲内のみ。
  static String align(
    String text, {
    required int indentSize,
    String? relativePath,
    int? startLineIndex,
    int? endLineIndex,
  }) {
    final size = indentSize == 2 ? 2 : 4;
    final endsWithNewline = text.endsWith('\n');
    final lines = text.split('\n');
    if (endsWithNewline && lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }
    if (lines.isEmpty) return text;

    final start = (startLineIndex ?? 0).clamp(0, lines.length);
    final end =
        (endLineIndex ?? (lines.length - 1)).clamp(start, lines.length - 1);

    if (_usesBraceIndent(relativePath)) {
      final levels = _braceLevels(
        lines,
        indentCaseBody: !_isSwift(relativePath),
      );
      for (var i = start; i <= end; i++) {
        lines[i] = _applyLevel(lines[i], levels[i], size);
      }
    } else {
      for (var i = start; i <= end; i++) {
        lines[i] = _normalizeLeading(lines[i], size);
      }
    }

    var out = lines.join('\n');
    if (endsWithNewline) out = '$out\n';
    return out;
  }

  static bool _usesBraceIndent(String? relativePath) {
    if (relativePath == null || relativePath.isEmpty) return true;
    final name = p.basename(relativePath).toLowerCase();
    final ext = p.extension(relativePath).toLowerCase().replaceFirst('.', '');
    if (name == 'podfile' || name == 'gemfile' || name == 'rakefile') {
      return false;
    }
    if (name == 'dockerfile' || name == 'makefile' || name == 'cmakelists.txt') {
      return false;
    }
    return switch (ext) {
      'py' ||
      'yaml' ||
      'yml' ||
      'sh' ||
      'bash' ||
      'zsh' ||
      'rb' ||
      'toml' ||
      'md' ||
      'markdown' ||
      'mdx' ||
      'txt' ||
      'gitignore' ||
      'env' =>
        false,
      _ => true,
    };
  }

  static bool _isSwift(String? relativePath) {
    if (relativePath == null) return false;
    return p.extension(relativePath).toLowerCase() == '.swift';
  }

  /// 各行の表示インデント段数（0 始まり）。
  ///
  /// 括弧の深さに加えて `:` による継続行を 1 段下げる:
  /// - 行末が `:`（`child:` など）→ 次の行から、その式が終わるまで +1
  /// - 行頭が `:` / `?`（三項演算子・初期化子リスト）→ その行（と続く括弧内）を +1
  /// - [indentCaseBody] のとき `case` / `default` ラベル配下を +1
  static List<int> _braceLevels(
    List<String> lines, {
    required bool indentCaseBody,
  }) {
    final levels = List<int>.filled(lines.length, 0);
    var depth = 0;
    var inBlockComment = false;
    // 継続行の基準となる括弧深さ。要素ごとに +1 段。
    final continuations = <int>[];
    // case ラベルが置かれた括弧深さ。要素ごとに +1 段。
    final caseDepths = <int>[];

    for (var i = 0; i < lines.length; i++) {
      final raw = lines[i];
      final trimmed = raw.trimLeft();
      if (trimmed.isEmpty) {
        levels[i] = depth + continuations.length + caseDepths.length;
        continue;
      }

      // 行頭の閉じ括弧ぶんだけこの行の段を下げる
      final leadClose = _leadingCloserCount(trimmed, inBlockComment);
      var lineLevel = depth - leadClose;
      if (lineLevel < 0) lineLevel = 0;

      while (continuations.isNotEmpty && continuations.last > lineLevel) {
        continuations.removeLast();
      }
      while (caseDepths.isNotEmpty && caseDepths.last > lineLevel) {
        caseDepths.removeLast();
      }

      final isLabel = !inBlockComment && _isCaseLabel(trimmed);
      if (!inBlockComment &&
          _startsWithContinuationOperator(trimmed) &&
          (continuations.isEmpty || continuations.last != lineLevel)) {
        continuations.add(lineLevel);
      }

      var caseExtra = indentCaseBody ? caseDepths.length : 0;
      if (indentCaseBody &&
          isLabel &&
          caseDepths.isNotEmpty &&
          caseDepths.last == lineLevel) {
        caseExtra--;
      }
      levels[i] = lineLevel + caseExtra + continuations.length;

      final delta = _bracketDelta(trimmed, inBlockComment: inBlockComment);
      inBlockComment = delta.inBlockComment;
      depth += delta.net;
      if (depth < 0) depth = 0;

      final endsWithColon = delta.lastCodeChar == 0x3a /* : */;
      // 式が基準の深さまで戻ったら継続を終える（行末 `:` で続く場合は維持）
      if (!endsWithColon || isLabel) {
        while (continuations.isNotEmpty && continuations.last >= depth) {
          continuations.removeLast();
        }
      }
      if (endsWithColon && isLabel) {
        if (indentCaseBody &&
            (caseDepths.isEmpty || caseDepths.last != lineLevel)) {
          caseDepths.add(lineLevel);
        }
      } else if (endsWithColon && !_isAccessSpecifier(trimmed)) {
        if (continuations.isEmpty || continuations.last != depth) {
          continuations.add(depth);
        }
      }
    }
    return levels;
  }

  static final _caseLabelPattern = RegExp(r'^(case\b|default\s*:)');
  static final _accessSpecifierPattern =
      RegExp(r'^(public|private|protected)\s*:\s*$');

  static bool _isCaseLabel(String trimmed) =>
      _caseLabelPattern.hasMatch(trimmed);

  static bool _isAccessSpecifier(String trimmed) =>
      _accessSpecifierPattern.hasMatch(trimmed);

  /// 行頭の `:`（三項の else・初期化子リスト）と三項の `?`。
  /// `::` `?.` `??` `?[` `?..` は対象外。
  static bool _startsWithContinuationOperator(String trimmed) {
    if (trimmed.isEmpty) return false;
    final c = trimmed.codeUnitAt(0);
    final next = trimmed.length > 1 ? trimmed.codeUnitAt(1) : 0;
    if (c == 0x3a /* : */) return next != 0x3a;
    if (c == 0x3f /* ? */) {
      return next != 0x2e /* . */ && next != 0x3f && next != 0x5b /* [ */;
    }
    return false;
  }

  static String _applyLevel(String line, int level, int indentSize) {
    final trimmed = line.trimLeft();
    if (trimmed.isEmpty) return '';
    final safe = level < 0 ? 0 : level;
    return '${' ' * (safe * indentSize)}$trimmed';
  }

  /// 行頭から続く `}` `]` `)` の数（文字列外・コメント外）。
  static int _leadingCloserCount(String trimmed, bool inBlockComment) {
    if (inBlockComment) return 0;
    var n = 0;
    var i = 0;
    while (i < trimmed.length) {
      final c = trimmed.codeUnitAt(i);
      if (c == 0x7d /* } */ || c == 0x5d /* ] */ || c == 0x29 /* ) */) {
        n++;
        i++;
        continue;
      }
      break;
    }
    return n;
  }

  /// [lastCodeChar] はコメント・空白を除いた行末の文字（無ければ 0）。
  static ({int net, bool inBlockComment, int lastCodeChar}) _bracketDelta(
    String line, {
    required bool inBlockComment,
  }) {
    var depth = 0;
    var lastCodeChar = 0;
    var i = 0;
    var block = inBlockComment;
    var inString = false;
    var stringQuote = 0; // ' " or `
    var rawString = false;

    while (i < line.length) {
      final c = line.codeUnitAt(i);
      final next = i + 1 < line.length ? line.codeUnitAt(i + 1) : 0;

      if (block) {
        if (c == 0x2a /* * */ && next == 0x2f /* / */) {
          block = false;
          i += 2;
          continue;
        }
        i++;
        continue;
      }

      if (inString) {
        if (!rawString && c == 0x5c /* \ */) {
          i += 2;
          continue;
        }
        if (c == stringQuote) {
          // Dart の三重引用は簡易対応: 同じ引用が3つ続くときだけ閉じる
          if (i + 2 < line.length &&
              line.codeUnitAt(i + 1) == stringQuote &&
              line.codeUnitAt(i + 2) == stringQuote) {
            i += 3;
          } else {
            i++;
          }
          inString = false;
          lastCodeChar = stringQuote;
          continue;
        }
        i++;
        continue;
      }

      // 行コメント
      if (c == 0x2f /* / */ && next == 0x2f /* / */) break;
      // ブロックコメント開始
      if (c == 0x2f /* / */ && next == 0x2a /* * */) {
        block = true;
        i += 2;
        continue;
      }

      // 文字列開始（r' / r" / ' / " / `）
      if (c == 0x72 /* r */ &&
          (next == 0x27 || next == 0x22) &&
          (i == 0 || !_isIdentChar(line.codeUnitAt(i - 1)))) {
        rawString = true;
        stringQuote = next;
        inString = true;
        i += 2;
        continue;
      }
      if (c == 0x27 /* ' */ || c == 0x22 /* " */ || c == 0x60 /* ` */) {
        rawString = false;
        stringQuote = c;
        inString = true;
        // 三重引用
        if (i + 2 < line.length &&
            line.codeUnitAt(i + 1) == c &&
            line.codeUnitAt(i + 2) == c) {
          i += 3;
        } else {
          i++;
        }
        continue;
      }

      if (c == 0x7b /* { */ || c == 0x5b /* [ */ || c == 0x28 /* ( */) {
        depth++;
      } else if (c == 0x7d /* } */ || c == 0x5d /* ] */ || c == 0x29 /* ) */) {
        depth--;
      }
      if (c != 0x20 && c != 0x09 && c != 0x0d) lastCodeChar = c;
      i++;
    }

    if (inString) lastCodeChar = stringQuote;
    return (net: depth, inBlockComment: block, lastCodeChar: lastCodeChar);
  }

  static bool _isIdentChar(int c) {
    return (c >= 0x41 && c <= 0x5a) ||
        (c >= 0x61 && c <= 0x7a) ||
        (c >= 0x30 && c <= 0x39) ||
        c == 0x5f;
  }

  /// 有意インデント言語向け: 段数は変えず空白幅だけ揃える。
  static String _normalizeLeading(String line, int indentSize) {
    if (line.isEmpty) return line;
    var i = 0;
    var columns = 0;
    while (i < line.length) {
      final c = line.codeUnitAt(i);
      if (c == 0x09) {
        columns += indentSize - (columns % indentSize);
        i++;
      } else if (c == 0x20) {
        columns++;
        i++;
      } else {
        break;
      }
    }
    if (i == 0) return line;
    final levels = (columns + indentSize ~/ 2) ~/ indentSize;
    return '${' ' * (levels * indentSize)}${line.substring(i)}';
  }
}
