/// カード差分プレビュー用（先頭 hunk の削除／追加行）。
final class CodingPatchDiffPreview {
  const CodingPatchDiffPreview({
    required this.deletedLines,
    required this.insertedLines,
  });

  final List<String> deletedLines;
  final List<String> insertedLines;

  bool get isEmpty => deletedLines.isEmpty && insertedLines.isEmpty;

  bool get isInsertOnly => deletedLines.isEmpty && insertedLines.isNotEmpty;
}

/// 提案中のパッチ（Apply 前）。
final class CodingProposedPatch {
  const CodingProposedPatch({
    required this.id,
    required this.relativePath,
    required this.rawDiff,
    this.oldSnippet,
    this.newSnippet,
    this.status = CodingPatchStatus.pending,
    this.errorMessage,
    this.isAddFile = false,
    this.suggestedInsertLine,
    this.suggestedReplaceStart,
    this.suggestedReplaceEnd,
  });

  final String id;
  final String relativePath;
  final String rawDiff;
  final String? oldSnippet;
  final String? newSnippet;
  final CodingPatchStatus status;
  final String? errorMessage;

  /// ヘッダが Add File（または同等）のとき true。
  final bool isAddFile;

  /// 新規挿入（+ のみ）の推奨挿入行（1-based）。その行の先頭に挿入する。
  final int? suggestedInsertLine;

  /// 既存修正の置換範囲（1-based、両端含む）。自動実行がこの行を + 側で置き換える。
  final int? suggestedReplaceStart;

  /// [suggestedReplaceStart] の終了行（1-based、両端含む）。
  final int? suggestedReplaceEnd;

  CodingProposedPatch copyWith({
    String? relativePath,
    CodingPatchStatus? status,
    String? errorMessage,
    bool clearError = false,
    bool? isAddFile,
    int? suggestedInsertLine,
    bool clearSuggestedInsertLine = false,
    int? suggestedReplaceStart,
    int? suggestedReplaceEnd,
    bool clearSuggestedReplaceRange = false,
  }) {
    return CodingProposedPatch(
      id: id,
      relativePath: relativePath ?? this.relativePath,
      rawDiff: rawDiff,
      oldSnippet: oldSnippet,
      newSnippet: newSnippet,
      status: status ?? this.status,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isAddFile: isAddFile ?? this.isAddFile,
      suggestedInsertLine: clearSuggestedInsertLine
          ? null
          : (suggestedInsertLine ?? this.suggestedInsertLine),
      suggestedReplaceStart: clearSuggestedReplaceRange
          ? null
          : (suggestedReplaceStart ?? this.suggestedReplaceStart),
      suggestedReplaceEnd: clearSuggestedReplaceRange
          ? null
          : (suggestedReplaceEnd ?? this.suggestedReplaceEnd),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'path': relativePath,
    'diff': rawDiff,
    'oldSnippet': oldSnippet,
    'newSnippet': newSnippet,
    'status': status.name,
    'isAddFile': isAddFile,
    if (suggestedInsertLine != null) 'suggestedInsertLine': suggestedInsertLine,
    if (suggestedReplaceStart != null)
      'suggestedReplaceStart': suggestedReplaceStart,
    if (suggestedReplaceEnd != null) 'suggestedReplaceEnd': suggestedReplaceEnd,
    if (errorMessage != null) 'errorMessage': errorMessage,
  };

  factory CodingProposedPatch.fromJson(Map<String, dynamic> json) {
    final statusName = '${json['status'] ?? 'pending'}';
    final status = CodingPatchStatus.values.firstWhere(
      (e) => e.name == statusName,
      orElse: () => CodingPatchStatus.pending,
    );
    final insertRaw = json['suggestedInsertLine'];
    final insertLine = insertRaw is int
        ? insertRaw
        : int.tryParse('${insertRaw ?? ''}');
    int? positiveInt(dynamic raw) {
      final n = raw is int ? raw : int.tryParse('${raw ?? ''}');
      if (n == null || n < 1) return null;
      return n;
    }

    final replaceStart = positiveInt(json['suggestedReplaceStart']);
    final replaceEnd = positiveInt(json['suggestedReplaceEnd']);
    final rangeOk =
        replaceStart != null &&
        replaceEnd != null &&
        replaceEnd >= replaceStart;
    return CodingProposedPatch(
      id: '${json['id'] ?? ''}',
      relativePath: '${json['path'] ?? json['relativePath'] ?? ''}',
      rawDiff: '${json['diff'] ?? json['rawDiff'] ?? ''}',
      oldSnippet: json['oldSnippet'] as String?,
      newSnippet: json['newSnippet'] as String?,
      status: status,
      errorMessage: json['errorMessage'] as String?,
      isAddFile: json['isAddFile'] == true,
      suggestedInsertLine: (insertLine != null && insertLine > 0)
          ? insertLine
          : null,
      suggestedReplaceStart: rangeOk ? replaceStart : null,
      suggestedReplaceEnd: rangeOk ? replaceEnd : null,
    );
  }
}

enum CodingPatchStatus { pending, applied, rejected }

/// ファイル作成案の作成先に、空でないファイルが既にある。
const codingAddFileExistsMessage =
    'このパスは既に内容があるため作成できません。既存の修正か、別パスでの作成を選んでください。';

/// 自動実行中、作成先が既存のときに Agent へ渡す再提案の冒頭。
/// 二択は書かない。対象ごとの指示は codingPlanAddFileConflict。
const codingAddFileExistsAutoReproposeLead =
    '作成先にファイルが既にあります。指示された1種類の Patch だけを出す。'
    '説明だけで終わらない。別案は書かない。';

/// 既存ファイルへの作成案で、人が選ぶ次の手段。
enum CodingAddFileConflictChoice { reviseExisting, chooseNewPath }

/// Apply の詳細結果（新規 Add の既存衝突を区別する）。
enum CodingPatchApplyStatus {
  applied,
  failed,

  /// Add／挿入のみだが、ベースに既に内容がある（上書きしない）。
  addExistsConflict,
}

final class CodingPatchApplyResult {
  const CodingPatchApplyResult._({required this.status, this.content});

  const CodingPatchApplyResult.applied(String content)
    : this._(status: CodingPatchApplyStatus.applied, content: content);

  const CodingPatchApplyResult.failed()
    : this._(status: CodingPatchApplyStatus.failed);

  const CodingPatchApplyResult.addExistsConflict()
    : this._(status: CodingPatchApplyStatus.addExistsConflict);

  final CodingPatchApplyStatus status;
  final String? content;
}

final class _PatchHunk {
  const _PatchHunk({
    required this.oldLines,
    required this.newLines,
    required this.deletedLines,
    required this.insertedLines,
  });

  final List<String> oldLines;
  final List<String> newLines;
  final List<String> deletedLines;
  final List<String> insertedLines;
}

/// Begin/End Patch 内の -/+ 行から置換を行う。
abstract final class CodingPatchApplier {
  /// 表示・互換用。複数 hunk は連結されるため Apply は [apply] 側で rawDiff を優先する。
  static ({String? oldSnippet, String? newSnippet}) extractSnippets(
    String patchBody,
  ) {
    final hunks = _parseHunks(patchBody);
    if (hunks.isEmpty) {
      return (oldSnippet: null, newSnippet: null);
    }
    final oldBuf = StringBuffer();
    final newBuf = StringBuffer();
    for (var i = 0; i < hunks.length; i++) {
      if (i > 0) {
        oldBuf.writeln();
        newBuf.writeln();
      }
      for (final line in hunks[i].oldLines) {
        oldBuf.writeln(line);
      }
      for (final line in hunks[i].newLines) {
        newBuf.writeln(line);
      }
    }
    final oldTrimmed = _trimTrailingNl(oldBuf.toString());
    final newTrimmed = _trimTrailingNl(newBuf.toString());
    if (oldTrimmed.isEmpty && newTrimmed.isEmpty) {
      return (oldSnippet: null, newSnippet: null);
    }
    return (
      oldSnippet: oldTrimmed.isEmpty ? null : oldTrimmed,
      newSnippet: newTrimmed.isEmpty ? '' : newTrimmed,
    );
  }

  static String? apply({
    required String baseContent,
    required CodingProposedPatch patch,
  }) {
    final result = applyDetailed(baseContent: baseContent, patch: patch);
    return result.status == CodingPatchApplyStatus.applied
        ? result.content
        : null;
  }

  /// Add 救済・既存衝突を含む詳細適用。
  static CodingPatchApplyResult applyDetailed({
    required String baseContent,
    required CodingProposedPatch patch,
  }) {
    final base = baseContent.replaceAll('\r\n', '\n');
    final insertOnly = patch.isAddFile || isInsertOnlyPatch(patch);

    // 1) rawDiff を hunk 単位で適用（複数箇所変更に対応）
    if (patch.rawDiff.trim().isNotEmpty) {
      final fromRaw = _applyRawDiff(
        base,
        patch.rawDiff,
        preferInsertOnly: insertOnly,
      );
      if (fromRaw != null) {
        return CodingPatchApplyResult.applied(fromRaw);
      }
    }

    // 2) 保存済み old/new スニペット
    final oldRaw = patch.oldSnippet?.replaceAll('\r\n', '\n');
    final newS = patch.newSnippet?.replaceAll('\r\n', '\n');
    if (oldRaw == null || oldRaw.isEmpty) {
      if (newS == null) {
        // fall through to insert-only recovery
      } else if (base.trim().isEmpty) {
        return CodingPatchApplyResult.applied(newS);
      } else if (insertOnly) {
        return const CodingPatchApplyResult.addExistsConflict();
      } else {
        return const CodingPatchApplyResult.failed();
      }
    } else {
      final replacement = newS ?? '';
      final byLines = _applyByLines(
        base,
        oldRaw,
        replacement,
        ignoreTrailingWs: false,
      );
      if (byLines != null) {
        return CodingPatchApplyResult.applied(byLines);
      }
      final soft = _applyByLines(
        base,
        oldRaw,
        replacement,
        ignoreTrailingWs: true,
      );
      if (soft != null) {
        return CodingPatchApplyResult.applied(soft);
      }
    }

    // 3) Add／挿入のみ: 文脈行を捨てて + 行だけ採用
    if (insertOnly) {
      final content = insertOnlyContent(patch);
      if (content == null) {
        return const CodingPatchApplyResult.failed();
      }
      if (base.trim().isEmpty) {
        return CodingPatchApplyResult.applied(content);
      }
      return const CodingPatchApplyResult.addExistsConflict();
    }

    return const CodingPatchApplyResult.failed();
  }

  /// 自動実行用。Agent が示した行範囲を、選択範囲置換と同じ + 側で置き換える。
  /// 範囲がファイル外、挿入専用、置換本文が空のときは null。
  static String? applyReplaceRange({
    required String baseContent,
    required CodingProposedPatch patch,
    int maxLines = 400,
  }) {
    final start = patch.suggestedReplaceStart;
    final end = patch.suggestedReplaceEnd;
    if (start == null || end == null || start < 1 || end < start) return null;
    if (end - start + 1 > maxLines) return null;
    if (patch.isAddFile || isInsertOnlyPatch(patch)) return null;
    final replacement =
        firstHunkInsertedContent(patch.rawDiff) ??
        patch.newSnippet?.replaceAll('\r\n', '\n');
    if (replacement == null || replacement.trim().isEmpty) return null;

    final base = baseContent.replaceAll('\r\n', '\n');
    final hadTrailingNl = base.endsWith('\n');
    var lines = base.split('\n');
    if (hadTrailingNl && lines.isNotEmpty && lines.last.isEmpty) {
      lines = lines.sublist(0, lines.length - 1);
    }
    if (lines.isEmpty || start > lines.length || end > lines.length) {
      return null;
    }
    var newLines = replacement.replaceAll('\r\n', '\n').split('\n');
    if (newLines.isNotEmpty && newLines.last.isEmpty) {
      newLines = newLines.sublist(0, newLines.length - 1);
    }
    final merged = [
      ...lines.sublist(0, start - 1),
      ...newLines,
      ...lines.sublist(end),
    ];
    final text = merged.join('\n');
    if (hadTrailingNl && text.isNotEmpty && !text.endsWith('\n')) {
      return '$text\n';
    }
    return text;
  }

  /// 自動実行用。`+` だけの Update を、`挿入行` の先頭へ入れる。
  /// Add File、挿入行が無い、本文が空のときは null。行がファイルより先なら末尾へ足す。
  static String? applyInsertAtLine({
    required String baseContent,
    required CodingProposedPatch patch,
  }) {
    if (patch.isAddFile) return null;
    final at = patch.suggestedInsertLine;
    if (at == null || at < 1) return null;
    if (!isInsertOnlyPatch(patch)) return null;
    final body = insertOnlyContent(patch);
    if (body == null || body.trim().isEmpty) return null;

    final base = baseContent.replaceAll('\r\n', '\n');
    final hadTrailingNl = base.endsWith('\n');
    var lines = base.split('\n');
    if (hadTrailingNl && lines.isNotEmpty && lines.last.isEmpty) {
      lines = lines.sublist(0, lines.length - 1);
    }
    var insertLines = body.replaceAll('\r\n', '\n').split('\n');
    if (insertLines.isNotEmpty && insertLines.last.isEmpty) {
      insertLines = insertLines.sublist(0, insertLines.length - 1);
    }
    if (insertLines.isEmpty) return null;

    final List<String> merged;
    if (lines.isEmpty) {
      merged = insertLines;
    } else if (at > lines.length) {
      merged = [...lines, ...insertLines];
    } else {
      merged = [
        ...lines.sublist(0, at - 1),
        ...insertLines,
        ...lines.sublist(at - 1),
      ];
    }
    final text = merged.join('\n');
    if (text.isEmpty) return text;
    return text.endsWith('\n') ? text : '$text\n';
  }

  /// 削除行がなく、追加行があるパッチ（Add や Update 誤用の + のみ）。
  static bool isInsertOnlyPatch(CodingProposedPatch patch) {
    if (patch.rawDiff.trim().isNotEmpty) {
      final hunks = _parseHunks(patch.rawDiff);
      if (hunks.isNotEmpty) {
        return hunks.every(
          (h) => h.deletedLines.isEmpty && h.insertedLines.isNotEmpty,
        );
      }
    }
    final oldRaw = patch.oldSnippet ?? '';
    final newS = patch.newSnippet;
    return oldRaw.trim().isEmpty && newS != null;
  }

  /// 挿入行だけを連結（文脈行は捨てる）。Add 救済用。
  static String? insertOnlyContent(CodingProposedPatch patch) {
    if (patch.rawDiff.trim().isNotEmpty) {
      final hunks = _parseHunks(patch.rawDiff);
      final inserts = <String>[];
      var sawInsert = false;
      var sawDelete = false;
      for (final h in hunks) {
        if (h.deletedLines.isNotEmpty) sawDelete = true;
        if (h.insertedLines.isNotEmpty) {
          sawInsert = true;
          inserts.addAll(h.insertedLines);
        }
      }
      if (sawInsert && !sawDelete) {
        return inserts.join('\n');
      }
    }
    final newS = patch.newSnippet?.replaceAll('\r\n', '\n');
    if (newS != null) return newS;
    return null;
  }

  /// 選択範囲置換用。先頭 hunk の新側（文脈＋追加）のみ。複数 @@ があっても連結しない。
  static String? firstHunkNewContent(String patchBody) {
    final hunks = _parseHunks(patchBody);
    if (hunks.isEmpty) return null;
    final lines = hunks.first.newLines;
    if (lines.isEmpty) return null;
    return _trimTrailingNl(lines.join('\n'));
  }

  /// 先頭 hunk の + 行のみ（修正後の項目。文脈行は含めない）。
  static String? firstHunkInsertedContent(String patchBody) {
    final hunks = _parseHunks(patchBody);
    if (hunks.isEmpty) return null;
    final lines = hunks.first.insertedLines;
    if (lines.isEmpty) return null;
    return _trimTrailingNl(lines.join('\n'));
  }

  /// 先頭 hunk の -/+ プレビュー（関数単位の修正表示用）。
  static String? firstHunkChangedLinesPreview(String patchBody) {
    final preview = firstHunkDiffPreview(patchBody);
    if (preview == null || preview.isEmpty) return null;
    final buf = StringBuffer();
    for (final line in preview.deletedLines) {
      buf.writeln('-$line');
    }
    for (final line in preview.insertedLines) {
      buf.writeln('+$line');
    }
    return _trimTrailingNl(buf.toString());
  }

  /// 先頭 hunk の削除／追加行（カード差分プレビュー用。プレフィックスなし）。
  static CodingPatchDiffPreview? firstHunkDiffPreview(String patchBody) {
    final hunks = _parseHunks(patchBody);
    if (hunks.isEmpty) return null;
    final h = hunks.first;
    if (h.deletedLines.isEmpty && h.insertedLines.isEmpty) return null;
    return CodingPatchDiffPreview(
      deletedLines: List<String>.of(h.deletedLines),
      insertedLines: List<String>.of(h.insertedLines),
    );
  }

  static String? _applyRawDiff(
    String base,
    String rawDiff, {
    bool preferInsertOnly = false,
  }) {
    final hunks = _parseHunks(rawDiff);
    if (hunks.isEmpty) return null;

    final onlyInserts = hunks.every(
      (h) => h.deletedLines.isEmpty && h.insertedLines.isNotEmpty,
    );
    // 追加のみ（文脈行があっても可）・ベース空 → 新規ファイルとして + 行だけ採用
    if (onlyInserts && base.trim().isEmpty) {
      return hunks.expand((h) => h.insertedLines).join('\n');
    }
    if (preferInsertOnly && onlyInserts && base.trim().isEmpty) {
      return hunks.expand((h) => h.insertedLines).join('\n');
    }

    var current = base;
    for (final hunk in hunks) {
      final next = _applyHunk(current, hunk);
      if (next == null) return null;
      current = next;
    }
    return current;
  }

  static String? _applyHunk(String base, _PatchHunk hunk) {
    if (hunk.oldLines.isEmpty) {
      if (hunk.newLines.isEmpty) return base;
      if (base.trim().isEmpty) return hunk.newLines.join('\n');
      return null;
    }

    // +/- が完全一致の hunk は no-op（適用成功扱い）
    if (hunk.deletedLines.isNotEmpty &&
        hunk.deletedLines.length == hunk.insertedLines.length &&
        _sameLines(hunk.deletedLines, hunk.insertedLines)) {
      return base;
    }

    final oldText = hunk.oldLines.join('\n');
    final newText = hunk.newLines.join('\n');

    final exact = _applyByLines(
      base,
      oldText,
      newText,
      ignoreTrailingWs: false,
    );
    if (exact != null) return exact;

    final soft = _applyByLines(base, oldText, newText, ignoreTrailingWs: true);
    if (soft != null) return soft;

    // コンテキスト無し: 削除行だけをキーに置換
    if (hunk.deletedLines.isNotEmpty) {
      final del = hunk.deletedLines.join('\n');
      final ins = hunk.insertedLines.join('\n');
      final d1 = _applyByLines(base, del, ins, ignoreTrailingWs: false);
      if (d1 != null) return d1;
      final d2 = _applyByLines(base, del, ins, ignoreTrailingWs: true);
      if (d2 != null) return d2;

      // インデント差を無視（先頭空白）
      final d3 = _applyByLines(
        base,
        del,
        ins,
        ignoreTrailingWs: true,
        ignoreLeadingWs: true,
      );
      if (d3 != null) return d3;

      // コメント等で行が連続していないとき: 差分のある行だけ個別置換
      final pairwise = _applyChangedLinesPairwise(base, hunk);
      if (pairwise != null) return pairwise;
    }

    // 全体をコンテキスト込みでインデント無視
    return _applyByLines(
      base,
      oldText,
      newText,
      ignoreTrailingWs: true,
      ignoreLeadingWs: true,
    );
  }

  static bool _sameLines(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// 削除／追加の行数が同じとき、異なる行だけを個別に置換する。
  /// （間にコメントがある ThemeData ブロック等で連続一致しないケース向け）
  static String? _applyChangedLinesPairwise(String base, _PatchHunk hunk) {
    final del = hunk.deletedLines;
    final ins = hunk.insertedLines;
    if (del.isEmpty || del.length != ins.length) return null;

    var current = base;
    var changed = false;
    for (var i = 0; i < del.length; i++) {
      if (del[i] == ins[i]) continue;
      changed = true;
      final next =
          _applyByLines(current, del[i], ins[i], ignoreTrailingWs: false) ??
          _applyByLines(current, del[i], ins[i], ignoreTrailingWs: true) ??
          _applyByLines(
            current,
            del[i],
            ins[i],
            ignoreTrailingWs: true,
            ignoreLeadingWs: true,
          );
      if (next == null) return null;
      current = next;
    }
    return changed ? current : base;
  }

  static List<_PatchHunk> _parseHunks(String patchBody) {
    final normalized = patchBody.replaceAll('\r\n', '\n');
    final lines = normalized.split('\n');
    final hunkLineGroups = <List<String>>[];
    var current = <String>[];

    void pushCurrent() {
      if (current.isNotEmpty) {
        hunkLineGroups.add(current);
        current = <String>[];
      }
    }

    for (final line in lines) {
      if (line.startsWith('***')) continue;
      if (line.startsWith('--- ') || line.startsWith('+++ ')) continue;
      if (line.startsWith('diff ')) continue;
      if (line.startsWith('index ')) continue;
      if (line.trimRight() == '```' || line.startsWith('```')) {
        continue;
      }
      if (line.startsWith('@@')) {
        pushCurrent();
        continue;
      }
      current.add(line);
    }
    pushCurrent();

    final hunks = <_PatchHunk>[];
    for (final group in hunkLineGroups) {
      final trimmed = _trimTrailingEmptyLines(group);
      if (trimmed.isEmpty) continue;
      final hunk = _hunkFromLines(trimmed);
      if (hunk != null) hunks.add(hunk);
    }
    return hunks;
  }

  static List<String> _trimTrailingEmptyLines(List<String> lines) {
    var end = lines.length;
    while (end > 0 && lines[end - 1].isEmpty) {
      end--;
    }
    return end == lines.length ? lines : lines.sublist(0, end);
  }

  static _PatchHunk? _hunkFromLines(List<String> lines) {
    final oldLines = <String>[];
    final newLines = <String>[];
    final deletedLines = <String>[];
    final insertedLines = <String>[];
    var sawChange = false;

    for (final line in lines) {
      if (line.startsWith('-')) {
        final body = line.substring(1);
        oldLines.add(body);
        deletedLines.add(body);
        sawChange = true;
      } else if (line.startsWith('+')) {
        final body = line.substring(1);
        newLines.add(body);
        insertedLines.add(body);
        sawChange = true;
      } else if (line.startsWith(' ')) {
        final body = line.substring(1);
        oldLines.add(body);
        newLines.add(body);
      } else if (line.isEmpty) {
        // 空行は文脈
        oldLines.add('');
        newLines.add('');
      } else {
        // LLM が文脈行の先頭スペースを省略したケース
        oldLines.add(line);
        newLines.add(line);
      }
    }

    if (!sawChange && oldLines.isEmpty && newLines.isEmpty) return null;
    if (!sawChange) return null;
    return _PatchHunk(
      oldLines: oldLines,
      newLines: newLines,
      deletedLines: deletedLines,
      insertedLines: insertedLines,
    );
  }

  /// 連続行一致で old を探し、該当行ブロックを new で置換する。
  static String? _applyByLines(
    String base,
    String oldS,
    String newS, {
    required bool ignoreTrailingWs,
    bool ignoreLeadingWs = false,
  }) {
    final oldLines = _splitKeepStructure(oldS);
    if (oldLines.isEmpty) return null;
    final baseLines = base.split('\n');
    if (baseLines.length < oldLines.length) return null;

    String norm(String line) {
      var s = line;
      if (ignoreTrailingWs) s = s.trimRight();
      if (ignoreLeadingWs) s = s.trimLeft();
      return s;
    }

    int? matchAt;
    for (var i = 0; i <= baseLines.length - oldLines.length; i++) {
      var match = true;
      for (var j = 0; j < oldLines.length; j++) {
        if (norm(baseLines[i + j]) != norm(oldLines[j])) {
          match = false;
          break;
        }
      }
      if (!match) continue;
      if (matchAt != null) {
        // 複数箇所ヒットは危険なので失敗扱い
        return null;
      }
      matchAt = i;
    }
    if (matchAt == null) return null;

    final i = matchAt;
    final before = baseLines.sublist(0, i);
    final after = baseLines.sublist(i + oldLines.length);
    final newLines = _splitKeepStructure(newS);
    return [...before, ...newLines, ...after].join('\n');
  }

  /// `split('\n')` と同じ。空文字は空リストではなく `['']`。
  static List<String> _splitKeepStructure(String s) {
    if (s.isEmpty) return const [''];
    return s.split('\n');
  }

  static String _trimTrailingNl(String s) {
    if (s.endsWith('\n')) return s.substring(0, s.length - 1);
    return s;
  }
}
