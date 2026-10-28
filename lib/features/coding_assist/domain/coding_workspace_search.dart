import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import 'coding_workspace_scan.dart';

/// ワークスペース内テキスト検索の1ヒット。
final class CodingSearchHit {
  const CodingSearchHit({
    required this.relativePath,
    required this.lineNumber,
    required this.matchStart,
    required this.matchLength,
    required this.snippet,
  });

  final String relativePath;

  /// 1-based
  final int lineNumber;

  /// 行内の一致開始（0-based）。
  final int matchStart;
  final int matchLength;
  final String snippet;
}

/// フォルダ内一括置換の結果。
final class CodingWorkspaceReplaceResult {
  const CodingWorkspaceReplaceResult({
    required this.filesChanged,
    required this.occurrenceCount,
    required this.updatedContents,
  });

  final int filesChanged;
  final int occurrenceCount;

  /// 相対パス → 置換後本文（変更があったファイルのみ）。
  final Map<String, String> updatedContents;
}

/// フォルダ内文言検索（除外ルールは走査と共通）。
abstract final class CodingWorkspaceSearch {
  static const maxHits = 200;
  static const contextChars = 10;
  static const maxReplaceFiles = 500;

  /// [query] を含む行を探す。既定は大文字小文字を無視する。
  /// [caseSensitive] が true のときは文字の大小も一致したものだけ。
  static Future<List<CodingSearchHit>> search({
    required String rootPath,
    required String query,
    bool caseSensitive = false,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];

    final root = Directory(rootPath);
    if (!await root.exists()) return const [];

    final needle = caseSensitive ? q : q.toLowerCase();
    final hits = <CodingSearchHit>[];

    Future<void> walk(Directory dir) async {
      if (hits.length >= maxHits) return;
      List<FileSystemEntity> kids;
      try {
        kids = await dir.list(followLinks: false).toList();
      } catch (_) {
        return;
      }
      kids.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
      for (final entity in kids) {
        if (hits.length >= maxHits) return;
        final name = p.basename(entity.path);
        if (entity is Directory) {
          if (CodingWorkspaceScan.isExcludedDirName(name)) continue;
          await walk(entity);
        } else if (entity is File) {
          if (!CodingWorkspaceScan.isTextFile(entity.path)) continue;
          String content;
          try {
            content = await entity.readAsString();
          } catch (_) {
            continue;
          }
          final rel = p
              .relative(entity.path, from: rootPath)
              .replaceAll('\\', '/');
          final lines = content.split('\n');
          for (var i = 0; i < lines.length; i++) {
            if (hits.length >= maxHits) return;
            final line = lines[i];
            final haystack = caseSensitive ? line : line.toLowerCase();
            final idx = haystack.indexOf(needle);
            if (idx < 0) continue;
            hits.add(
              CodingSearchHit(
                relativePath: rel,
                lineNumber: i + 1,
                matchStart: idx,
                matchLength: q.length,
                snippet: buildSnippet(
                  line: line,
                  matchStart: idx,
                  matchLength: q.length,
                ),
              ),
            );
          }
        }
      }
    }

    await walk(root);
    return hits;
  }

  /// 検索語を含み、前後おおよそ [contextChars] 文字のスニペット。
  static String buildSnippet({
    required String line,
    required int matchStart,
    required int matchLength,
  }) {
    final trimmed = line.replaceAll('\t', ' ');
    final start = math.max(0, matchStart - contextChars);
    final end = math.min(
      trimmed.length,
      matchStart + matchLength + contextChars,
    );
    var snippet = trimmed.substring(start, end);
    if (start > 0) snippet = '…$snippet';
    if (end < trimmed.length) snippet = '$snippet…';
    return snippet;
  }

  /// ワークスペース内テキストを一括置換（リテラル）。
  ///
  /// 既定は大文字小文字を無視する。[caseSensitive] が true のときは大小も一致した箇所だけ置換する。
  /// [contentOverrides] がある相対パスはディスクよりそちらを優先（開いているタブ）。
  /// 変更ファイルはディスクへ書き込み、[updatedContents] にも返す。
  static Future<CodingWorkspaceReplaceResult> replaceAll({
    required String rootPath,
    required String query,
    required String replacement,
    Map<String, String> contentOverrides = const {},
    bool caseSensitive = false,
  }) async {
    final q = query.trim();
    if (q.isEmpty) {
      return const CodingWorkspaceReplaceResult(
        filesChanged: 0,
        occurrenceCount: 0,
        updatedContents: {},
      );
    }

    final root = Directory(rootPath);
    if (!await root.exists()) {
      return const CodingWorkspaceReplaceResult(
        filesChanged: 0,
        occurrenceCount: 0,
        updatedContents: {},
      );
    }

    final updated = <String, String>{};
    var occurrenceCount = 0;
    var filesTouched = 0;

    Future<void> walk(Directory dir) async {
      if (filesTouched >= maxReplaceFiles) return;
      List<FileSystemEntity> kids;
      try {
        kids = await dir.list(followLinks: false).toList();
      } catch (_) {
        return;
      }
      kids.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
      for (final entity in kids) {
        if (filesTouched >= maxReplaceFiles) return;
        final name = p.basename(entity.path);
        if (entity is Directory) {
          if (CodingWorkspaceScan.isExcludedDirName(name)) continue;
          await walk(entity);
        } else if (entity is File) {
          if (!CodingWorkspaceScan.isTextFile(entity.path)) continue;
          final rel = p
              .relative(entity.path, from: rootPath)
              .replaceAll('\\', '/');
          String content;
          if (contentOverrides.containsKey(rel)) {
            content = contentOverrides[rel]!;
          } else {
            try {
              content = await entity.readAsString();
            } catch (_) {
              continue;
            }
          }
          final replaced = caseSensitive
              ? replaceLiteral(content, q, replacement)
              : replaceIgnoreCase(content, q, replacement);
          if (identical(replaced, content) || replaced == content) continue;
          final count = caseSensitive
              ? countLiteral(content, q)
              : countIgnoreCase(content, q);
          if (count == 0) continue;
          try {
            await entity.writeAsString(replaced);
          } catch (_) {
            continue;
          }
          updated[rel] = replaced;
          occurrenceCount += count;
          filesTouched++;
        }
      }
    }

    await walk(root);
    return CodingWorkspaceReplaceResult(
      filesChanged: updated.length,
      occurrenceCount: occurrenceCount,
      updatedContents: updated,
    );
  }

  /// 大文字小文字も一致するリテラル置換。
  static String replaceLiteral(
    String source,
    String query,
    String replacement,
  ) {
    if (query.isEmpty || !source.contains(query)) return source;
    return source.replaceAll(query, replacement);
  }

  /// 大文字小文字を無視したリテラル置換。
  static String replaceIgnoreCase(
    String source,
    String query,
    String replacement,
  ) {
    if (query.isEmpty) return source;
    final lowerSource = source.toLowerCase();
    final lowerQuery = query.toLowerCase();
    if (!lowerSource.contains(lowerQuery)) return source;

    final buf = StringBuffer();
    var start = 0;
    while (true) {
      final idx = lowerSource.indexOf(lowerQuery, start);
      if (idx < 0) {
        buf.write(source.substring(start));
        break;
      }
      buf.write(source.substring(start, idx));
      buf.write(replacement);
      start = idx + query.length;
    }
    return buf.toString();
  }

  static int countLiteral(String source, String query) {
    if (query.isEmpty) return 0;
    var count = 0;
    var start = 0;
    while (true) {
      final idx = source.indexOf(query, start);
      if (idx < 0) break;
      count++;
      start = idx + query.length;
    }
    return count;
  }

  static int countIgnoreCase(String source, String query) {
    if (query.isEmpty) return 0;
    final lowerSource = source.toLowerCase();
    final lowerQuery = query.toLowerCase();
    var count = 0;
    var start = 0;
    while (true) {
      final idx = lowerSource.indexOf(lowerQuery, start);
      if (idx < 0) break;
      count++;
      start = idx + query.length;
    }
    return count;
  }
}
