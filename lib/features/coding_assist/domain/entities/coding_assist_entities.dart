import '../coding_patch.dart';
import '../coding_prompt_action.dart';

enum CodingMessageRole { user, assistant, tool, system }

/// 送信済みユーザー発言に残す添付の表示用ラベル。本文は持たない。
enum CodingHistoryChipKind { file, selection, folder }

final class CodingHistoryChip {
  const CodingHistoryChip({required this.kind, required this.label, this.path});

  final CodingHistoryChipKind kind;

  /// 吹き出しに出す短い表示。ファイルはワークスペース相対パス。
  final String label;

  /// 編集で付与を戻すときの相対パス。
  final String? path;

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'label': label,
    if (path != null && path!.isNotEmpty) 'path': path,
  };

  factory CodingHistoryChip.fromJson(Map<String, dynamic> json) {
    final kindName = '${json['kind'] ?? ''}';
    final kind = CodingHistoryChipKind.values
        .where((e) => e.name == kindName)
        .firstOrNull;
    final label = '${json['label'] ?? ''}'.trim();
    if (kind == null || label.isEmpty) {
      return const CodingHistoryChip(
        kind: CodingHistoryChipKind.file,
        label: '',
      );
    }
    final path = json['path'] as String?;
    return CodingHistoryChip(
      kind: kind,
      label: label,
      path: (path != null && path.trim().isNotEmpty) ? path.trim() : null,
    );
  }
}

/// コンテキスト警告（S16 §4.5／§5.7）。
enum CodingContextWarningLevel {
  none,
  warn,
  compacted,
  block;

  String get storageValue => name;

  static CodingContextWarningLevel fromStorage(String? value) {
    return switch (value) {
      'warn' => CodingContextWarningLevel.warn,
      'compacted' => CodingContextWarningLevel.compacted,
      'block' => CodingContextWarningLevel.block,
      _ => CodingContextWarningLevel.none,
    };
  }
}

final class CodingChatMessage {
  const CodingChatMessage({
    required this.role,
    required this.content,
    required this.at,
    this.toolName,
    this.llmContent,
    this.fixedPrompts = const [],
    this.requestText,
    this.historyChips = const [],
  });

  final CodingMessageRole role;

  /// UI 表示用（Patch／tool フェンス除去後など）。
  final String content;
  final DateTime at;
  final String? toolName;

  /// LLM 再送信用の生本文（assistant の tool フェンス付きなど）。null なら [content]。
  final String? llmContent;

  /// この送信に付けた＋の固定プロンプト。上限後の検査が完了の形を決める。
  final List<CodingPromptAction> fixedPrompts;

  /// 入力欄の依頼文。開いているファイルや固定プロンプトのテンプレは含まない。
  final String? requestText;

  /// この送信の添付表示。ファイル本文は [content] にだけ置く。
  final List<CodingHistoryChip> historyChips;

  /// API に載せる本文。
  String get contentForLlm =>
      (llmContent != null && llmContent!.trim().isNotEmpty)
      ? llmContent!
      : content;

  Map<String, dynamic> toJson() => {
    'role': role.name,
    'content': content,
    'at': at.toIso8601String(),
    if (toolName != null) 'toolName': toolName,
    if (llmContent != null) 'llmContent': llmContent,
    if (fixedPrompts.isNotEmpty)
      'fixedPrompts': [for (final action in fixedPrompts) action.id],
    if (requestText != null && requestText!.trim().isNotEmpty)
      'requestText': requestText,
    if (historyChips.isNotEmpty)
      'historyChips': [for (final chip in historyChips) chip.toJson()],
  };

  factory CodingChatMessage.fromJson(Map<String, dynamic> json) {
    final roleName = '${json['role'] ?? 'user'}';
    final role = CodingMessageRole.values.firstWhere(
      (e) => e.name == roleName,
      orElse: () => CodingMessageRole.user,
    );
    final llm = json['llmContent'] as String?;
    final request = json['requestText'] as String?;
    return CodingChatMessage(
      role: role,
      content: '${json['content'] ?? ''}',
      at: DateTime.tryParse('${json['at'] ?? ''}') ?? DateTime.now(),
      toolName: json['toolName'] as String?,
      llmContent: (llm != null && llm.trim().isNotEmpty) ? llm : null,
      fixedPrompts: _fixedPromptsFromJson(json['fixedPrompts']),
      requestText: (request != null && request.trim().isNotEmpty)
          ? request
          : null,
      historyChips: _historyChipsFromJson(json['historyChips']),
    );
  }

  static List<CodingHistoryChip> _historyChipsFromJson(Object? raw) {
    if (raw is! List) return const [];
    final out = <CodingHistoryChip>[];
    for (final item in raw) {
      if (item is Map<String, dynamic>) {
        final chip = CodingHistoryChip.fromJson(item);
        if (chip.label.isEmpty) continue;
        out.add(chip);
      } else if (item is Map) {
        final chip = CodingHistoryChip.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (chip.label.isEmpty) continue;
        out.add(chip);
      }
    }
    return List<CodingHistoryChip>.unmodifiable(out);
  }

  static List<CodingPromptAction> _fixedPromptsFromJson(Object? raw) {
    if (raw is! List) return const [];
    final out = <CodingPromptAction>[];
    for (final item in raw) {
      final action = CodingPromptAction.tryParse('$item');
      if (action == null || out.contains(action)) continue;
      out.add(action);
    }
    return List<CodingPromptAction>.unmodifiable(out);
  }
}

final class CodingThread {
  const CodingThread({
    required this.id,
    required this.title,
    required this.workspaceRootPath,
    required this.messages,
    required this.updatedAt,
    this.pendingPatches = const [],
    this.contextWarningLevel = CodingContextWarningLevel.none,
    this.compactedSummary,
    this.compactedAt,
    this.compactedUpToExclusive = 0,
  });

  /// まだ送信していない会話の表示名。
  static const placeholderTitle = '新規';

  static bool isPlaceholderTitle(String title) {
    final trimmed = title.trim();
    return trimmed.isEmpty || trimmed == placeholderTitle;
  }

  final String id;
  final String title;
  final String workspaceRootPath;
  final List<CodingChatMessage> messages;
  final DateTime updatedAt;
  final List<CodingProposedPatch> pendingPatches;
  final CodingContextWarningLevel contextWarningLevel;

  /// API 先頭付近に挿入する【これまでの要約】（UI messages は不変）。
  final String? compactedSummary;
  final DateTime? compactedAt;

  /// [messages] のこの index 未満を API では要約に畳む（UI は全文維持）。
  final int compactedUpToExclusive;

  CodingThread copyWith({
    String? title,
    List<CodingChatMessage>? messages,
    DateTime? updatedAt,
    List<CodingProposedPatch>? pendingPatches,
    CodingContextWarningLevel? contextWarningLevel,
    String? compactedSummary,
    DateTime? compactedAt,
    int? compactedUpToExclusive,
    bool clearCompacted = false,
  }) {
    return CodingThread(
      id: id,
      title: title ?? this.title,
      workspaceRootPath: workspaceRootPath,
      messages: messages ?? this.messages,
      updatedAt: updatedAt ?? this.updatedAt,
      pendingPatches: pendingPatches ?? this.pendingPatches,
      contextWarningLevel: contextWarningLevel ?? this.contextWarningLevel,
      compactedSummary: clearCompacted
          ? null
          : (compactedSummary ?? this.compactedSummary),
      compactedAt: clearCompacted ? null : (compactedAt ?? this.compactedAt),
      compactedUpToExclusive: clearCompacted
          ? 0
          : (compactedUpToExclusive ?? this.compactedUpToExclusive),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'workspaceRootPath': workspaceRootPath,
    'updatedAt': updatedAt.toIso8601String(),
    'messages': messages.map((m) => m.toJson()).toList(),
    'pendingPatches': pendingPatches.map((p) => p.toJson()).toList(),
    'contextWarningLevel': contextWarningLevel.storageValue,
    if (compactedSummary != null) 'compactedSummary': compactedSummary,
    if (compactedAt != null) 'compactedAt': compactedAt!.toIso8601String(),
    'compactedUpToExclusive': compactedUpToExclusive,
  };

  factory CodingThread.fromJson(Map<String, dynamic> json) {
    final msgs = <CodingChatMessage>[];
    final rawMsgs = json['messages'];
    if (rawMsgs is List) {
      for (final item in rawMsgs) {
        if (item is Map<String, dynamic>) {
          msgs.add(CodingChatMessage.fromJson(item));
        } else if (item is Map) {
          msgs.add(CodingChatMessage.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    final patches = <CodingProposedPatch>[];
    final rawPatches = json['pendingPatches'];
    if (rawPatches is List) {
      for (final item in rawPatches) {
        if (item is Map<String, dynamic>) {
          patches.add(CodingProposedPatch.fromJson(item));
        } else if (item is Map) {
          patches.add(
            CodingProposedPatch.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    final upTo = json['compactedUpToExclusive'];
    return CodingThread(
      id: '${json['id'] ?? ''}',
      title: '${json['title'] ?? '無題'}',
      workspaceRootPath: '${json['workspaceRootPath'] ?? ''}',
      messages: msgs,
      updatedAt:
          DateTime.tryParse('${json['updatedAt'] ?? ''}') ?? DateTime.now(),
      pendingPatches: patches,
      contextWarningLevel: CodingContextWarningLevel.fromStorage(
        json['contextWarningLevel'] as String?,
      ),
      compactedSummary: json['compactedSummary'] as String?,
      compactedAt: DateTime.tryParse('${json['compactedAt'] ?? ''}'),
      compactedUpToExclusive: upTo is int ? upTo : int.tryParse('$upTo') ?? 0,
    );
  }
}

final class CodingOpenTab {
  const CodingOpenTab({
    required this.relativePath,
    required this.content,
    this.dirty = false,
  });

  final String relativePath;
  final String content;
  final bool dirty;

  CodingOpenTab copyWith({String? relativePath, String? content, bool? dirty}) {
    return CodingOpenTab(
      relativePath: relativePath ?? this.relativePath,
      content: content ?? this.content,
      dirty: dirty ?? this.dirty,
    );
  }
}

/// エディタ選択範囲をプロンプトへ付与する（下書き本文には書き込まない）。
final class CodingAttachedSelection {
  const CodingAttachedSelection({
    required this.relativePath,
    required this.startLine,
    required this.endLine,
    required this.selectedText,
  });

  final String relativePath;

  /// 1-based inclusive
  final int startLine;

  /// 1-based inclusive
  final int endLine;
  final String selectedText;

  String toPromptBlock() {
    final range = startLine == endLine
        ? 'L$startLine'
        : 'L$startLine–L$endLine';
    return '【選択範囲】\n'
        'ファイル: $relativePath\n'
        '行: $range\n'
        '```\n'
        '$selectedText\n'
        '```';
  }
}

/// フォルダ構造をプロンプトへ付与する（下書き本文には書き込まない）。
final class CodingAttachedFolderStructure {
  const CodingAttachedFolderStructure({
    required this.relativePath,
    required this.block,
  });

  /// ワークスペース相対パス。ルートは空。
  final String relativePath;

  /// 付与時点の構造テキスト。
  final String block;

  String get chipLabel {
    final path = relativePath.replaceAll('\\', '/');
    return path.isEmpty ? 'ワークスペース' : path;
  }

  String toPromptBlock() => block.trimRight();
}

/// 開いているタブ内容の送信前取り込み（下書き本文には書き込まない。S13 添付と同様）。
final class CodingAttachedOpenFile {
  const CodingAttachedOpenFile({
    required this.relativePath,
    required this.content,
  });

  final String relativePath;

  /// 取り込み時点のスナップショット（長大時は截断済み可）。
  final String content;

  String get chipLabel {
    final i = relativePath.replaceAll('\\', '/').lastIndexOf('/');
    return i < 0 ? relativePath : relativePath.substring(i + 1);
  }

  String toPromptBlock({int maxChars = 80000}) {
    if (content.isEmpty) {
      return '【開いているファイル: $relativePath】\n（空ファイル）';
    }
    var body = content;
    var truncatedNote = '';
    if (body.length > maxChars) {
      body = body.substring(0, maxChars);
      truncatedNote = '\n…（先頭 $maxChars 文字まで）';
    }
    return '【開いているファイル: $relativePath】\n```\n$body$truncatedNote\n```';
  }
}
