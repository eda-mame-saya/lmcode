import 'dart:io';

import 'package:path/path.dart' as p;

import 'coding_text_file.dart';
import 'coding_workspace_kind.dart';

/// 小説キーワード登録（Markdown ファイル＋見出しツリー）。
abstract final class CodingNovelKeywords {
  /// ワークスペースルート基準の相対パス。
  static const relativePath = 'keywords.md';

  static const defaultTemplate = '''
# 登場人物

## 主人公（名前：）

物語の主人公

### 所持スキル

- （ここに書く）

# 地名

## （地名）

（説明）
''';

  static String absolutePath(String workspaceRoot) =>
      p.join(workspaceRoot, relativePath);

  /// 小説 WS のとき、無ければテンプレで作成し本文を返す。
  static Future<String> ensureFile(String workspaceRoot) async {
    final file = File(absolutePath(workspaceRoot));
    if (await file.exists()) {
      return CodingTextFile.read(file);
    }
    await file.parent.create(recursive: true);
    await file.writeAsString(defaultTemplate, flush: true);
    return defaultTemplate;
  }

  static bool isKeywordsPath(String? relativePath) {
    if (relativePath == null || relativePath.isEmpty) return false;
    return relativePath.replaceAll('\\', '/') == CodingNovelKeywords.relativePath;
  }

  /// 小説 WS かつキーワードペインを出すか。
  static bool paneVisible(CodingWorkspaceKind? kind) =>
      kind == CodingWorkspaceKind.novel;
}

/// キーワード Markdown の見出しノード。
final class CodingNovelKeywordNode {
  CodingNovelKeywordNode({
    required this.level,
    required this.title,
    this.body = '',
    List<CodingNovelKeywordNode>? children,
  }) : children = children ?? <CodingNovelKeywordNode>[];

  /// 1〜6（`#` の数）。
  final int level;
  final String title;

  /// 次の見出しまでの本文（Markdown）。
  String body;
  final List<CodingNovelKeywordNode> children;

  bool get hasBody => body.trim().isNotEmpty;
}

/// `#`〜`######` 見出しで階層化し、間の行を body に載せる。
abstract final class CodingNovelKeywordParser {
  static final _heading = RegExp(r'^(#{1,6})\s+(.*)$');

  static List<CodingNovelKeywordNode> parse(String markdown) {
    final lines = markdown.replaceAll('\r\n', '\n').split('\n');
    final roots = <CodingNovelKeywordNode>[];
    final stack = <CodingNovelKeywordNode>[];
    final bodyBuf = StringBuffer();

    void flushBody() {
      if (stack.isEmpty) {
        bodyBuf.clear();
        return;
      }
      final text = bodyBuf.toString().trimRight();
      bodyBuf.clear();
      if (text.trim().isEmpty) return;
      final node = stack.last;
      if (node.body.isEmpty) {
        node.body = text;
      } else {
        node.body = '${node.body}\n$text';
      }
    }

    for (final line in lines) {
      final match = _heading.firstMatch(line);
      if (match != null) {
        flushBody();
        final level = match.group(1)!.length;
        final title = (match.group(2) ?? '').trim();
        final node = CodingNovelKeywordNode(level: level, title: title);
        while (stack.isNotEmpty && stack.last.level >= level) {
          stack.removeLast();
        }
        if (stack.isEmpty) {
          roots.add(node);
        } else {
          stack.last.children.add(node);
        }
        stack.add(node);
        continue;
      }
      if (stack.isEmpty) continue;
      if (bodyBuf.isNotEmpty) bodyBuf.writeln();
      bodyBuf.write(line);
    }
    flushBody();
    return roots;
  }
}
