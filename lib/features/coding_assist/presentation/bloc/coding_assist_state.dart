import 'package:equatable/equatable.dart';
import 'package:intl/intl.dart';

import '../../../api_settings/domain/entities/coding_llm_backend.dart';
import '../../../api_settings/domain/entities/local_llm_connection_settings.dart';
import '../../../api_settings/domain/entities/strata_connection_settings.dart';
import '../../domain/coding_auto_sleep.dart';
import '../../domain/coding_harness_settings.dart';
import '../../domain/coding_novel_settings.dart';
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
    this.isHistoryOpen = false,
    this.isEditingLastUser = false,
    this.localLlm = const LocalLlmConnectionSettings(),
    this.strata = const StrataConnectionSettings(),
    this.codingBackend = CodingLlmBackend.llamaCpp,
    this.strataContextSize,
    this.uiFontSizes = CodingUiFontSizes.defaults,
    this.harness = CodingHarnessSettings.defaults,
    this.autoSleepSettings = const CodingAutoSleepSettings(),
    this.autoSleepArmed = false,
    this.autoSleepDeadline,
    this.indentSize = 4,
    this.novelSettings = CodingNovelSettings.defaults,
    this.novelKeywordsContent,
    this.promptFavorites = const [],
    this.appliedPromptActions = const [],
    this.recentWorkspaces = const [],
    this.folderExpansion,
    this.threadSummaries = const [],
    this.workspaceRoot,
    this.gitBranch,
    this.index,
    this.openTabs = const [],
    this.activeTabPath,
    this.editorBufferEpoch = 0,
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
  final bool isHistoryOpen;
  final bool isEditingLastUser;
  final LocalLlmConnectionSettings localLlm;

  /// Strata 接続（既定ポート 8090）。
  final StrataConnectionSettings strata;

  /// Agent が使う推論バックエンド。
  final CodingLlmBackend codingBackend;

  /// Strata run config の `--max-context`（未解決なら null → 既定値）。
  final int? strataContextSize;

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

  /// 小説執筆モードの改行インデント等。
  final CodingNovelSettings novelSettings;

  /// 小説キーワード `keywords.md` のディスク／確保済み本文。開いているタブがあればそちらを優先表示。
  final String? novelKeywordsContent;

  /// プロンプト補助のお気に入り（最大2・登録順。＋隣に短縮ボタン表示）。
  final List<CodingPromptAction> promptFavorites;

  /// 送信前に適用中のプロンプト補助（押した順）。送信ボタンで本文へ重ねる。
  final List<CodingPromptAction> appliedPromptActions;
  final List<String> recentWorkspaces;

  /// 開いているワークスペースのフォルダ展開記録。null は未記録（既定展開）。
  final Map<String, bool>? folderExpansion;
  final List<CodingThreadSummary> threadSummaries;
  final String? workspaceRoot;

  /// git があるときのみブランチ名（なければ null）。
  final String? gitBranch;
  final CodingWorkspaceIndex? index;
  final List<CodingOpenTab> openTabs;
  final String? activeTabPath;

  /// ディスク等からエディタ本文を押し込むときに増やす（手入力の TabContent では増やさない）。
  /// IME 変換中に BLoC→コントローラへ古い本文が戻るのを防ぐ。
  final int editorBufferEpoch;

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

  int get contextSize => switch (codingBackend) {
        CodingLlmBackend.llamaCpp => localLlm.codingContextSize,
        CodingLlmBackend.strata =>
          (strataContextSize != null && strataContextSize! > 0)
              ? strataContextSize!
              : StrataPresets.defaultContextSize,
      };

  /// 選択中バックエンドで Agent 送信可能か。
  /// Strata は Agent 選択時にサイドカーを起動するため、enabled ではなく接続先の有無で判定する。
  bool get isAgentLlmUsable => switch (codingBackend) {
        CodingLlmBackend.llamaCpp => localLlm.isCodingUsable,
        CodingLlmBackend.strata => strata.hasEndpoint,
      };

  /// Agent 送信用の OpenAI 互換設定。
  LocalLlmConnectionSettings agentChatSettings({String? strataModelId}) {
    return switch (codingBackend) {
      CodingLlmBackend.llamaCpp => localLlm.forServer(),
      CodingLlmBackend.strata => strata.toChatClientSettings(
          resolvedModelId: strataModelId,
          contextSize: strataContextSize,
        ),
    };
  }

  /// ツールバー／ステータスバー用のモデル表示名。
  String agentModelLabel({String? strataModelId}) {
    return switch (codingBackend) {
      CodingLlmBackend.llamaCpp => localLlm.resolvedCodingModelLabel,
      CodingLlmBackend.strata => () {
          final id = (strataModelId ?? strata.modelId).trim();
          if (id.isNotEmpty) return 'Strata: $id';
          return 'Strata（${strata.baseUrl}）';
        }(),
    };
  }

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

  /// 現在ワークスペースに紐づく履歴のみ。
  List<CodingThreadSummary> get workspaceThreadSummaries {
    final root = workspaceRoot;
    if (root == null) return const [];
    return threadSummaries
        .where((s) => s.workspaceRootPath == root)
        .toList(growable: false);
  }

  CodingAssistState copyWith({
    bool? isLoading,
    bool? isLlmBusy,
    bool? isGenerating,
    bool? isHistoryOpen,
    bool? isEditingLastUser,
    LocalLlmConnectionSettings? localLlm,
    StrataConnectionSettings? strata,
    CodingLlmBackend? codingBackend,
    int? strataContextSize,
    bool clearStrataContextSize = false,
    CodingUiFontSizes? uiFontSizes,
    CodingHarnessSettings? harness,
    CodingAutoSleepSettings? autoSleepSettings,
    bool? autoSleepArmed,
    DateTime? autoSleepDeadline,
    bool clearAutoSleepDeadline = false,
    int? indentSize,
    CodingNovelSettings? novelSettings,
    String? novelKeywordsContent,
    bool clearNovelKeywordsContent = false,
    List<CodingPromptAction>? promptFavorites,
    List<CodingPromptAction>? appliedPromptActions,
    bool clearAppliedPromptActions = false,
    List<String>? recentWorkspaces,
    Map<String, bool>? folderExpansion,
    bool clearFolderExpansion = false,
    List<CodingThreadSummary>? threadSummaries,
    String? workspaceRoot,
    String? gitBranch,
    CodingWorkspaceIndex? index,
    List<CodingOpenTab>? openTabs,
    String? activeTabPath,
    int? editorBufferEpoch,
    bool bumpEditorBufferEpoch = false,
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
      isHistoryOpen: isHistoryOpen ?? this.isHistoryOpen,
      isEditingLastUser: isEditingLastUser ?? this.isEditingLastUser,
      localLlm: localLlm ?? this.localLlm,
      strata: strata ?? this.strata,
      codingBackend: codingBackend ?? this.codingBackend,
      strataContextSize: clearStrataContextSize
          ? null
          : (strataContextSize ?? this.strataContextSize),
      uiFontSizes: uiFontSizes ?? this.uiFontSizes,
      harness: harness ?? this.harness,
      autoSleepSettings: autoSleepSettings ?? this.autoSleepSettings,
      autoSleepArmed: autoSleepArmed ?? this.autoSleepArmed,
      autoSleepDeadline: clearAutoSleepDeadline
          ? null
          : (autoSleepDeadline ?? this.autoSleepDeadline),
      indentSize: indentSize ?? this.indentSize,
      novelSettings: novelSettings ?? this.novelSettings,
      novelKeywordsContent: clearNovelKeywordsContent || clearWorkspace
          ? null
          : (novelKeywordsContent ?? this.novelKeywordsContent),
      promptFavorites: promptFavorites ?? this.promptFavorites,
      appliedPromptActions: clearAppliedPromptActions
          ? const []
          : (appliedPromptActions ?? this.appliedPromptActions),
      recentWorkspaces: recentWorkspaces ?? this.recentWorkspaces,
      folderExpansion: clearFolderExpansion
          ? null
          : (folderExpansion ?? this.folderExpansion),
      threadSummaries: threadSummaries ?? this.threadSummaries,
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
      editorBufferEpoch: bumpEditorBufferEpoch
          ? this.editorBufferEpoch + 1
          : (editorBufferEpoch ?? this.editorBufferEpoch),
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
    isHistoryOpen,
    isEditingLastUser,
    localLlm.codingCustomModelId,
    localLlm.codingCustomGgufFileName,
    localLlm.codingContextSize,
    harness,
    localLlm.codingThinkingEnabled,
    localLlm.codingAutoApplyPatches,
    localLlm.enabled,
    strata.host,
    strata.port,
    strata.enabled,
    strata.modelId,
    strata.thinkingEffort,
    codingBackend,
    strataContextSize,
    uiFontSizes,
    autoSleepSettings,
    autoSleepArmed,
    autoSleepDeadline,
    indentSize,
    novelSettings,
    novelKeywordsContent,
    promptFavorites,
    appliedPromptActions,
    recentWorkspaces,
    _folderExpansionProp(folderExpansion),
    threadSummaries.map((s) => '${s.id}:${s.updatedAt.toIso8601String()}'),
    workspaceRoot,
    gitBranch,
    index?.rootPath,
    index?.kind,
    index?.relativeFiles.length,
    index?.relativeDirectories.length,
    openTabs.map(
      (t) =>
          '${t.relativePath}:${t.dirty}:${t.content.length}:${t.content.hashCode}',
    ),
    activeTabPath,
    editorBufferEpoch,
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
