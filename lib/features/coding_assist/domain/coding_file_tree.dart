import 'package:path/path.dart' as p;

/// 相対パス一覧から作る展開可能なファイルツリー。
final class CodingFileTreeNode {
  CodingFileTreeNode({
    required this.name,
    required this.relativePath,
    required this.isDirectory,
    List<CodingFileTreeNode>? children,
  }) : children = children ?? <CodingFileTreeNode>[];

  final String name;

  /// ディレクトリは末尾スラッシュなしの相対パス。ファイルは相対パス。
  final String relativePath;
  final bool isDirectory;
  final List<CodingFileTreeNode> children;

  /// [relativeFiles]／[relativeDirectories]（ワークスペース相対）からツリーを構築。
  static List<CodingFileTreeNode> fromRelativeFiles(
    List<String> relativeFiles, {
    List<String> relativeDirectories = const [],
  }) {
    final root = CodingFileTreeNode(
      name: '',
      relativePath: '',
      isDirectory: true,
    );

    CodingFileTreeNode ensureDir(CodingFileTreeNode parent, String pathSoFar) {
      final name = p.basename(pathSoFar);
      final existing = parent.children
          .where((c) => c.isDirectory && c.name == name)
          .firstOrNull;
      if (existing != null) return existing;
      final created = CodingFileTreeNode(
        name: name,
        relativePath: pathSoFar,
        isDirectory: true,
      );
      parent.children.add(created);
      return created;
    }

    void ensurePath({
      required String rel,
      required bool asDirectory,
    }) {
      final normalized = rel.replaceAll('\\', '/').trim();
      if (normalized.isEmpty) return;
      final parts = normalized.split('/').where((e) => e.isNotEmpty).toList();
      if (parts.isEmpty) return;
      var current = root;
      var pathSoFar = '';
      for (var i = 0; i < parts.length; i++) {
        final part = parts[i];
        pathSoFar = pathSoFar.isEmpty ? part : '$pathSoFar/$part';
        final isLast = i == parts.length - 1;
        if (isLast && !asDirectory) {
          if (current.children.any((c) => !c.isDirectory && c.name == part)) {
            return;
          }
          current.children.add(
            CodingFileTreeNode(
              name: part,
              relativePath: pathSoFar,
              isDirectory: false,
            ),
          );
        } else {
          current = ensureDir(current, pathSoFar);
        }
      }
    }

    for (final dir in relativeDirectories) {
      ensurePath(rel: dir, asDirectory: true);
    }
    for (final file in relativeFiles) {
      ensurePath(rel: file, asDirectory: false);
    }
    _sortRecursive(root);
    return root.children;
  }

  static void _sortRecursive(CodingFileTreeNode node) {
    node.children.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    for (final child in node.children) {
      if (child.isDirectory) _sortRecursive(child);
    }
  }

  /// 既定で開いておくフォルダ。
  bool get preferInitiallyExpanded {
    if (!isDirectory) return false;
    final base = p.basename(relativePath);
    return base == 'lib' ||
        base == 'test' ||
        base == 'ios' ||
        base == 'android' ||
        relativePath.isEmpty;
  }

  /// Agent下書きへ入れるブロック。
  ///
  /// LLMが最も読み取りやすい一般的なtreeコマンド形式で出力する。
  String toAgentStructureBlock() {
    final buf = StringBuffer()
      ..writeln('【プロジェクトのフォルダ構造】')
      ..writeln('```text')
      ..writeln(name.isEmpty ? '.' : name);

    _writeTree(buf, '', this);

    buf.writeln('```');
    return buf.toString().trimRight();
  }

  /// 再帰的にツリー構造の文字列を構築する。
  void _writeTree(StringBuffer buf, String prefix, CodingFileTreeNode node) {
    for (var i = 0; i < node.children.length; i++) {
      final child = node.children[i];
      final isLast = i == node.children.length - 1;
      
      final connector = isLast ? '└── ' : '├── ';
      final childPrefix = isLast ? '    ' : '│   ';
      
      final displayName = child.isDirectory ? '${child.name}/' : child.name;
      buf.writeln('$prefix$connector$displayName');

      if (child.isDirectory && child.children.isNotEmpty) {
        _writeTree(buf, '$prefix$childPrefix', child);
      }
    }
  }

  /// [directory] 配下のファイル相対パス。[directory] が空なら一覧をそのまま返す。
  static List<String> filesUnderDirectory(
    Iterable<String> relativeFiles,
    String directory,
  ) {
    final dir = directory.replaceAll('\\', '/').trim();
    final normalized = (dir == '.' ? '' : dir).replaceAll(RegExp(r'/+$'), '');
    if (normalized.isEmpty) {
      return [
        for (final file in relativeFiles) file.replaceAll('\\', '/'),
      ];
    }
    final prefix = '$normalized/';
    return [
      for (final raw in relativeFiles)
        if (raw.replaceAll('\\', '/').startsWith(prefix))
          raw.replaceAll('\\', '/'),
    ];
  }

  /// ファイル相対パスの祖先ディレクトリ一覧（浅い順）。
  static List<String> ancestorDirectories(String relativeFilePath) {
    final parts = relativeFilePath
        .replaceAll('\\', '/')
        .split('/')
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.length <= 1) return const [];
    final out = <String>[];
    var acc = '';
    for (var i = 0; i < parts.length - 1; i++) {
      acc = acc.isEmpty ? parts[i] : '$acc/${parts[i]}';
      out.add(acc);
    }
    return out;
  }
}