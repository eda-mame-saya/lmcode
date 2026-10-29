import 'package:equatable/equatable.dart';
import 'package:intl/intl.dart';

import '../../../api_settings/domain/entities/local_llm_connection_settings.dart';
import '../../domain/coding_auto_sleep.dart';
import '../../domain/coding_harness_settings.dart';
import '../../domain/coding_patch.dart';
import '../../domain/coding_prompt_action.dart';
import '../../domain/coding_ui_font_sizes.dart';
import '../../domain/coding_workspace_scan.dart';
import '../../domain/entities/coding_assist_entities.dart';

final class CodingAssistState extends Equatable {
  const CodingAssistState({
    this.isLoading = true,
    this.isLlmBusy = false,
    this.isGenerating = false,
    this.isEditingLastUser = false,
    this.localLlm = const LocalLlmConnectionSettings(),
    this.uiFontSizes = CodingUiFontSizes.defaults,
    this.harness = CodingHarnessSettings.defaults,
    this.autoSleepSettings = const CodingAutoSleepSettings(),
    this.autoSleepArmed = false,
    this.autoSleepDeadline,
    this.indentSize = 4,
    this.promptFavorites = const [],
    this.appliedPromptActions = const [],
    this.recentWorkspaces = const [],
    this.folderExpansion,
    this.workspaceRoot,
    this.gitBranch,
    this.index,
    this.openTabs = const [],
    this.activeTabPath,
    this.revealLine,
    this.revealOffset,
    this.revealLength,
    this.treeRevealPath,
    this.thread,
    this.draft = '',
    this.draftEpoch = 0,
    this.streamingText = '',
    this.generationTrace = '',
    this.agentStatusMessage,
    this.mtpDraftFileName,
    this.workspaceStatusMessage,
    this.errorMessage,
    this.pendingPatches = const [],
    this.attachedSelection,
    this.attachedOpenFiles = const [],
    this.attachedFolderStructures = const [],
    this.usedTokens = 0,
    this.warningLevel = CodingContextWarningLevel.none,
  });

  final bool isLoading;
  final bool isLlmBusy;
  final bool isGenerating;
  final bool isEditingLastUser;
  final LocalLlmConnectionSettings localLlm;

  /// メニュー／エディタ／Agent の表示フォントサイズ。
  final CodingUiFontSizes uiFontSizes;

  /// Agent のハーネス定数。表示設定とは別に保存する。
  final CodingHarnessSettings harness;

  /// 自動実行後のスリープ設定。時刻の開始は自動実行が始まったとき。
  final CodingAutoSleepSettings autoSleepSettings;

  /// いまの自動実行に対してスリープ予定が有効。
  final bool autoSleepArmed;

  /// 時間指定があるときのスリープ時刻。終わったらスリープだけのときは null。
  final DateTime? autoSleepDeadline;

  /// インデント空白幅（2 または 4。既定 4）。
  final int indentSize;

  /// プロンプト補助のお気に入り（最大2・登録順。＋隣に短縮ボタン表示）。
  final List<CodingPromptAction> promptFavorites;

  /// 送信前に適用中のプロンプト補助（押した順）。送信ボタンで本文へ重ねる。
  final List<CodingPromptAction> appliedPromptActions;
  final List<String> recentWorkspaces;

  /// 開いているワークスペースのフォルダ展開記録。null は未記録（既定展開）。
  final Map<String, bool>? folderExpansion;
  final String? workspaceRoot;

  /// git があるときのみブランチ名（なければ null）。
  final String? gitBranch;
  final CodingWorkspaceIndex? index;
  final List<CodingOpenTab> openTabs;
  final String? activeTabPath;

  /// エディタで開いたあとスクロールする行（1-based）。消費後にクリア。
  final int? revealLine;

  /// 行内選択（0-based）。[revealLength] とセット。
  final int? revealOffset;
  final int? revealLength;

  /// 左メニューで位置表示する相対パス。消費後にクリア。
  final String? treeRevealPath;
  final CodingThread? thread;
  final String draft;

  /// 入力欄へ下書きを強制同期するときに増やす（編集など）。
  final int draftEpoch;
  final String streamingText;

  /// 現在ターンの生成生ログ（ツールステップ跨ぎ。UI の折りたたみ表示用）。
  final String generationTrace;

  /// フッター左。起動・生成・ツール・検証・会話など Agent の進行。
  final String? agentStatusMessage;

  /// 起動中の本体に付いている MTP 下書き係のファイル名。無いときは null。
  final String? mtpDraftFileName;

  /// フッター中央。索引・保存・ファイル操作・git など Agent 以外の進行。
  final String? workspaceStatusMessage;
  final String? errorMessage;
  final List<CodingProposedPatch> pendingPatches;
  final CodingAttachedSelection? attachedSelection;

  /// 送信前の開いているファイル取り込み（S13 添付と同様。下書きには書かない）。
  final List<CodingAttachedOpenFile> attachedOpenFiles;

  /// 送信前に付けるフォルダ構造。入力欄には書かない。
  final List<CodingAttachedFolderStructure> attachedFolderStructures;
  final int usedTokens;
  final CodingContextWarningLevel warningLevel;

  List<CodingChatMessage> get messages => thread?.messages ?? const [];

  int get contextSize => localLlm.codingContextSize;

  // String get contextUsageLabel => '$usedTokens / $contextSize';
  String get contextUsageLabel {
    final nf = NumberFormat('#,###');
    final pf = NumberFormat('#0.0#');
    final per = (usedTokens / contextSize) * 100;
    return '${nf.format(usedTokens)} / ${nf.format(contextSize)} (${pf.format(per)}%)';
  }

  bool get canSend {
    if (isGenerating || isLlmBusy) return false;
    if (workspaceRoot == null) return false;
    if (warningLevel == CodingContextWarningLevel.block) return false;
    if (draft.trim().isNotEmpty) return true;
    if (appliedPromptActions.contains(CodingPromptAction.runFlutterVerify)) {
      return true;
    }
    // 入力空でも取り込み／選択範囲／フォルダ構造があれば送信可
    return attachedOpenFiles.isNotEmpty ||
        attachedSelection != null ||
        attachedFolderStructures.isNotEmpty;
  }

  bool get hasPromptAttachments =>
      attachedOpenFiles.isNotEmpty ||
      attachedSelection != null ||
      attachedFolderStructures.isNotEmpty;

  bool get canEditOrRevokeLastUser {
    if (isGenerating || isLlmBusy) return false;
    return messages.any((m) => m.role == CodingMessageRole.user);
  }

  /// 直近の user メッセージ index。なければ null。
  int? get lastUserMessageIndex {
    final list = messages;
    if (list.isEmpty) return null;
    for (var i = list.length - 1; i >= 0; i--) {
      if (list[i].role == CodingMessageRole.user) return i;
    }
    return null;
  }

  CodingAssistState copyWith({
    bool? isLoading,
    bool? isLlmBusy,
    bool? isGenerating,
    bool? isEditingLastUser,
    LocalLlmConnectionSettings? localLlm,
    CodingUiFontSizes? uiFontSizes,
    CodingHarnessSettings? harness,
    CodingAutoSleepSettings? autoSleepSettings,
    bool? autoSleepArmed,
    DateTime? autoSleepDeadline,
    bool clearAutoSleepDeadline = false,
    int? indentSize,
    List<CodingPromptAction>? promptFavorites,
    List<CodingPromptAction>? appliedPromptActions,
    bool clearAppliedPromptActions = false,
    List<String>? recentWorkspaces,
    Map<String, bool>? folderExpansion,
    bool clearFolderExpansion = false,
    String? workspaceRoot,
    String? gitBranch,
    CodingWorkspaceIndex? index,
    List<CodingOpenTab>? openTabs,
    String? activeTabPath,
    int? revealLine,
    int? revealOffset,
    int? revealLength,
    String? treeRevealPath,
    CodingThread? thread,
    String? draft,
    int? draftEpoch,
    bool bumpDraftEpoch = false,
    String? streamingText,
    String? generationTrace,
    String? agentStatusMessage,
    String? mtpDraftFileName,
    bool clearMtpDraft = false,
    String? workspaceStatusMessage,
    String? errorMessage,
    List<CodingProposedPatch>? pendingPatches,
    CodingAttachedSelection? attachedSelection,
    List<CodingAttachedOpenFile>? attachedOpenFiles,
    List<CodingAttachedFolderStructure>? attachedFolderStructures,
    int? usedTokens,
    CodingContextWarningLevel? warningLevel,
    bool clearWorkspace = false,
    bool clearGitBranch = false,
    bool clearIndex = false,
    bool clearThread = false,
    bool clearActiveTab = false,
    bool clearRevealLine = false,
    bool clearTreeRevealPath = false,
    bool clearError = false,
    bool clearAttachedSelection = false,
    bool clearAttachedOpenFiles = false,
    bool clearAttachedFolderStructures = false,
    bool clearGenerationTrace = false,
    bool clearAgentStatus = false,
    bool clearWorkspaceStatus = false,
  }) {
    return CodingAssistState(
      isLoading: isLoading ?? this.isLoading,
      isLlmBusy: isLlmBusy ?? this.isLlmBusy,
      isGenerating: isGenerating ?? this.isGenerating,
      isEditingLastUser: isEditingLastUser ?? this.isEditingLastUser,
      localLlm: localLlm ?? this.localLlm,
      uiFontSizes: uiFontSizes ?? this.uiFontSizes,
      harness: harness ?? this.harness,
      autoSleepSettings: autoSleepSettings ?? this.autoSleepSettings,
      autoSleepArmed: autoSleepArmed ?? this.autoSleepArmed,
      autoSleepDeadline: clearAutoSleepDeadline
          ? null
          : (autoSleepDeadline ?? this.autoSleepDeadline),
      indentSize: indentSize ?? this.indentSize,
      promptFavorites: promptFavorites ?? this.promptFavorites,
      appliedPromptActions: clearAppliedPromptActions
          ? const []
          : (appliedPromptActions ?? this.appliedPromptActions),
      recentWorkspaces: recentWorkspaces ?? this.recentWorkspaces,
      folderExpansion: clearFolderExpansion
          ? null
          : (folderExpansion ?? this.folderExpansion),
      workspaceRoot: clearWorkspace
          ? null
          : (workspaceRoot ?? this.workspaceRoot),
      gitBranch: clearGitBranch || clearWorkspace
          ? null
          : (gitBranch ?? this.gitBranch),
      index: clearIndex ? null : (index ?? this.index),
      openTabs: openTabs ?? this.openTabs,
      activeTabPath: clearActiveTab
          ? null
          : (activeTabPath ?? this.activeTabPath),
      revealLine: clearRevealLine ? null : (revealLine ?? this.revealLine),
      revealOffset: clearRevealLine
          ? null
          : (revealOffset ?? this.revealOffset),
      revealLength: clearRevealLine
          ? null
          : (revealLength ?? this.revealLength),
      treeRevealPath: clearTreeRevealPath || clearWorkspace
          ? null
          : (treeRevealPath ?? this.treeRevealPath),
      thread: clearThread ? null : (thread ?? this.thread),
      draft: draft ?? this.draft,
      draftEpoch: bumpDraftEpoch
          ? this.draftEpoch + 1
          : (draftEpoch ?? this.draftEpoch),
      streamingText: streamingText ?? this.streamingText,
      generationTrace: clearGenerationTrace
          ? ''
          : (generationTrace ?? this.generationTrace),
      agentStatusMessage: clearAgentStatus
          ? null
          : (agentStatusMessage ?? this.agentStatusMessage),
      mtpDraftFileName: clearMtpDraft
          ? null
          : (mtpDraftFileName ?? this.mtpDraftFileName),
      workspaceStatusMessage: clearWorkspaceStatus
          ? null
          : (workspaceStatusMessage ?? this.workspaceStatusMessage),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      pendingPatches: pendingPatches ?? this.pendingPatches,
      attachedSelection: clearAttachedSelection
          ? null
          : (attachedSelection ?? this.attachedSelection),
      attachedOpenFiles: clearAttachedOpenFiles
          ? const []
          : (attachedOpenFiles ?? this.attachedOpenFiles),
      attachedFolderStructures: clearAttachedFolderStructures
          ? const []
          : (attachedFolderStructures ?? this.attachedFolderStructures),
      usedTokens: usedTokens ?? this.usedTokens,
      warningLevel: warningLevel ?? this.warningLevel,
    );
  }

  @override
  List<Object?> get props => [
    isLoading,
    isLlmBusy,
    isGenerating,
    isEditingLastUser,
    localLlm.codingCustomModelId,
    localLlm.codingCustomGgufFileName,
    localLlm.codingContextSize,
    harness,
    localLlm.codingThinkingEnabled,
    localLlm.codingAutoApplyPatches,
    localLlm.enabled,
    uiFontSizes,
    autoSleepSettings,
    autoSleepArmed,
    autoSleepDeadline,
    indentSize,
    promptFavorites,
    appliedPromptActions,
    recentWorkspaces,
    _folderExpansionProp(folderExpansion),
    workspaceRoot,
    gitBranch,
    index?.rootPath,
    index?.relativeFiles.length,
    index?.relativeDirectories.length,
    openTabs.map(
      (t) =>
          '${t.relativePath}:${t.dirty}:${t.content.length}:${t.content.hashCode}',
    ),
    activeTabPath,
    revealLine,
    revealOffset,
    revealLength,
    treeRevealPath,
    thread?.id,
    thread?.messages.length,
    thread?.compactedUpToExclusive,
    thread?.compactedSummary,
    thread?.contextWarningLevel,
    draft,
    draftEpoch,
    streamingText,
    generationTrace,
    agentStatusMessage,
    mtpDraftFileName,
    workspaceStatusMessage,
    errorMessage,
    pendingPatches.map(
      (p) => '${p.id}:${p.status.name}:${p.errorMessage ?? ''}',
    ),
    attachedSelection?.relativePath,
    attachedSelection?.startLine,
    attachedSelection?.endLine,
    attachedSelection?.selectedText,
    attachedOpenFiles.map((f) => '${f.relativePath}:${f.content.length}'),
    attachedFolderStructures.map((f) => '${f.relativePath}:${f.block.length}'),
    usedTokens,
    warningLevel,
  ];
}

String? _folderExpansionProp(Map<String, bool>? map) {
  if (map == null) return null;
  final keys = map.keys.toList()..sort();
  return keys.map((key) => '$key=${map[key]! ? 1 : 0}').join('\n');
}
