import 'dart:convert';

import 'coding_patch.dart';

/// モデル応答から tool フェンスと Begin/End Patch を抽出する。
abstract final class CodingFenceParser {
  static final _toolFence = RegExp(
    r'```tool\s*\n([\s\S]*?)```',
    multiLine: true,
  );

  static final _patchBlock = RegExp(
    r'\*\*\* Begin Patch\s*\n([\s\S]*?)\*\*\* End Patch',
    multiLine: true,
  );

  /// Update/Add。コロン欠落も許容。
  static final _fileHeader = RegExp(
    r'^\*\*\* (Update|Add)\s+File:?\s*(.+)\s*$',
    multiLine: true,
    caseSensitive: false,
  );

  /// Patch 直前の「挿入行: 42」（半角／全角コロン）。
  static final _insertLineHint = RegExp(r'挿入行\s*[:：]\s*(\d+)');

  /// Patch 直前の「置換範囲: 10-18」（ハイフン・波ダッシュ）。
  static final _replaceRangeHint = RegExp(
    r'置換範囲\s*[:：]\s*(\d+)\s*[-–—~〜]\s*(\d+)',
  );

  static CodingFenceParseResult parse(String assistantText) {
    final tools = <CodingToolCall>[];
    for (final m in _toolFence.allMatches(assistantText)) {
      final body = m.group(1)?.trim() ?? '';
      if (body.isEmpty) continue;
      final call = CodingToolCall.tryParseJson(body);
      if (call != null) tools.add(call);
    }

    final found = <CodingProposedPatch>[];
    for (final m in _patchBlock.allMatches(assistantText)) {
      final body = m.group(1) ?? '';
      final fileMatch = _fileHeader.firstMatch(body);
      if (fileMatch == null) continue;
      final kind = (fileMatch.group(1) ?? '').toLowerCase();
      final isAdd = kind == 'add';
      var path = fileMatch.group(2)?.trim() ?? '';
      path = _normalizePatchPath(path);
      if (path.isEmpty) continue;
      final afterHeader = body.substring(fileMatch.end);
      final snippet = CodingPatchApplier.extractSnippets(afterHeader);
      final suggestedInsert = isAdd
          ? null
          : suggestedInsertLineBefore(assistantText, m.start);
      final suggestedReplace = isAdd
          ? null
          : suggestedReplaceRangeBefore(assistantText, m.start);
      found.add(
        CodingProposedPatch(
          id: 'p_${found.length}_${path.hashCode.abs()}',
          relativePath: path,
          rawDiff: body,
          oldSnippet: snippet.oldSnippet,
          newSnippet: snippet.newSnippet,
          isAddFile: isAdd,
          suggestedInsertLine: suggestedInsert,
          suggestedReplaceStart: suggestedReplace?.start,
          suggestedReplaceEnd: suggestedReplace?.end,
        ),
      );
    }
    // 同一応答内の重複（モデルが同じ Add File を2回書く）を1枚に畳む。
    final patches = mergePatches(const [], found);

    final display = assistantText
        .replaceAll(_toolFence, '')
        .replaceAll(_patchBlock, '')
        .trim();

    // パッチ／tool のみの応答では全文をチャットに戻さない（差分カード側で見せる）
    // tool 呼び出し要約は次ターンの API 履歴でも「何をしたか」が分かるように残す
    final toolSummary = tools.isEmpty ? null : _formatToolCallsSummary(tools);
    final String baseDisplay;
    if (display.isNotEmpty) {
      baseDisplay = display;
    } else if (patches.isNotEmpty && tools.isEmpty) {
      final onlyAdd = patches.every((p) => p.isAddFile);
      final onlyUpdate = patches.every((p) => !p.isAddFile);
      if (onlyAdd) {
        baseDisplay = 'ファイル作成案を提案しました（下のカードから作成／却下できます）';
      } else if (onlyUpdate) {
        baseDisplay = '変更案を提案しました（下のカードから適用／却下できます）';
      } else {
        baseDisplay = '変更案とファイル作成案を提案しました（下のカードから操作できます）';
      }
    } else if (tools.isNotEmpty && patches.isEmpty) {
      baseDisplay = 'ツールを実行します…';
    } else if (patches.isNotEmpty && tools.isNotEmpty) {
      baseDisplay = 'ツール実行と変更案を準備しました';
    } else {
      baseDisplay = assistantText.trim();
    }
    final displayText = toolSummary == null
        ? baseDisplay
        : '$baseDisplay\n（実行: $toolSummary）';

    return CodingFenceParseResult(
      toolCalls: tools,
      patches: patches,
      displayText: displayText,
    );
  }

  static String _formatToolCallsSummary(List<CodingToolCall> tools) {
    return tools
        .map((c) {
          final path = '${c.args['path'] ?? ''}'.trim();
          final pattern = '${c.args['pattern'] ?? ''}'.trim();
          final query = '${c.args['query'] ?? c.args['symbol'] ?? ''}'.trim();
          if (path.isNotEmpty && query.isNotEmpty) {
            return '${c.name}($path $query)';
          }
          if (path.isNotEmpty) return '${c.name}($path)';
          if (query.isNotEmpty) {
            final clipped = query.length > 40
                ? '${query.substring(0, 40)}…'
                : query;
            return '${c.name}($clipped)';
          }
          if (pattern.isNotEmpty) {
            final clipped = pattern.length > 40
                ? '${pattern.substring(0, 40)}…'
                : pattern;
            return '${c.name}($clipped)';
          }
          return c.name;
        })
        .join(', ');
  }

  /// 既存の提案へ新しい提案を足す。
  ///
  /// 本文が同じ提案は捨てる。Add File は同一相対パスにつき pending を1枚にし、
  /// 後から来た案で置き換える（ツール調査の前後で同じ作成カードが2枚出るのを防ぐ）。
  /// 別パス、および同一ファイルへの関数単位 Update は残す。
  static List<CodingProposedPatch> mergePatches(
    List<CodingProposedPatch> existing,
    List<CodingProposedPatch> incoming,
  ) {
    final merged = [...existing];
    for (final patch in incoming) {
      if (merged.any((current) => sameProposal(current, patch))) continue;
      if (patch.isAddFile && patch.status == CodingPatchStatus.pending) {
        final idx = merged.lastIndexWhere(
          (current) =>
              current.isAddFile &&
              current.status == CodingPatchStatus.pending &&
              current.relativePath == patch.relativePath,
        );
        if (idx >= 0) {
          merged[idx] = patch;
          continue;
        }
      }
      merged.add(patch);
    }
    return merged;
  }

  static bool sameProposal(CodingProposedPatch a, CodingProposedPatch b) {
    if (a.isAddFile != b.isAddFile) return false;
    if (a.relativePath != b.relativePath) return false;
    return proposalBody(a) == proposalBody(b);
  }

  static String proposalBody(CodingProposedPatch patch) {
    final snippet = (patch.newSnippet ?? '').replaceAll('\r\n', '\n').trim();
    if (snippet.isNotEmpty) return snippet;
    return patch.rawDiff.replaceAll('\r\n', '\n').trim();
  }

  /// パーサ時点の軽い正規化（WS ルートは Bloc 適用時に再正規化）。
  static String _normalizePatchPath(String raw) {
    var path = raw.replaceAll('`', '').replaceAll('"', '').replaceAll("'", '');
    path = path.replaceAll('\\', '/').trim();
    while (path.startsWith('./')) {
      path = path.substring(2);
    }
    if (path.endsWith('/') && path.length > 1) {
      path = path.substring(0, path.length - 1);
    }
    return path;
  }

  /// [patchStart] 直前のテキストから推奨挿入行（1-based）を取る。
  static int? suggestedInsertLineBefore(String fullText, int patchStart) {
    if (patchStart <= 0 || fullText.isEmpty) return null;
    final from = (patchStart - 240).clamp(0, patchStart);
    final window = fullText.substring(from, patchStart);
    final matches = _insertLineHint.allMatches(window);
    if (matches.isEmpty) return null;
    final n = int.tryParse(matches.last.group(1) ?? '');
    if (n == null || n < 1) return null;
    return n;
  }

  /// [patchStart] 直前のテキストから置換範囲（1-based、両端含む）を取る。
  static ({int start, int end})? suggestedReplaceRangeBefore(
    String fullText,
    int patchStart,
  ) {
    if (patchStart <= 0 || fullText.isEmpty) return null;
    final from = (patchStart - 240).clamp(0, patchStart);
    final window = fullText.substring(from, patchStart);
    final matches = _replaceRangeHint.allMatches(window);
    if (matches.isEmpty) return null;
    final start = int.tryParse(matches.last.group(1) ?? '');
    final end = int.tryParse(matches.last.group(2) ?? '');
    if (start == null || end == null || start < 1 || end < start) return null;
    return (start: start, end: end);
  }
}

final class CodingFenceParseResult {
  const CodingFenceParseResult({
    required this.toolCalls,
    required this.patches,
    required this.displayText,
  });

  final List<CodingToolCall> toolCalls;
  final List<CodingProposedPatch> patches;
  final String displayText;
}

final class CodingToolCall {
  const CodingToolCall({required this.name, required this.args});

  final String name;
  final Map<String, dynamic> args;

  static CodingToolCall? tryParseJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final name = '${map['name'] ?? ''}'.trim();
      if (name.isEmpty) return null;
      final argsRaw = map['args'] ?? map['arguments'] ?? const {};
      final args = argsRaw is Map
          ? Map<String, dynamic>.from(argsRaw)
          : <String, dynamic>{};
      return CodingToolCall(name: name, args: args);
    } catch (_) {
      return null;
    }
  }
}
