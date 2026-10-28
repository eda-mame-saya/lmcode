import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../api_settings/domain/entities/local_llm_connection_settings.dart';
import '../../../api_settings/domain/usecases/get_connection_settings.dart';
import '../../../api_settings/domain/usecases/save_connection_settings.dart';
import '../../../generative_ai/data/local_llm_client.dart';
import '../../../generative_ai/data/local_llm_server_launcher.dart';
import '../../../generative_ai/domain/ai_generation_progress.dart';
import '../../data/coding_flutter_verify_runner.dart';
import '../../data/coding_system_sleeper.dart';
import '../../data/flutter_sdk_resolver.dart';
import '../../domain/coding_add_file_conflict.dart';
import '../../domain/coding_agent_tools.dart';
import '../../domain/coding_auto_loop.dart';
import '../../domain/coding_generation_repeat.dart';
import '../../domain/coding_auto_sleep.dart';
import '../../domain/coding_api_context_builder.dart';
import '../../domain/coding_context_estimator.dart';
import '../../domain/coding_fence_parser.dart';
import '../../domain/coding_flutter_verify_policy.dart';
import '../../domain/coding_git.dart';
import '../../domain/coding_harness_settings.dart';
import '../../data/datasources/coding_ui_settings_local_datasource.dart';
import '../../domain/coding_patch.dart';
import '../../domain/coding_path_resolver.dart';
import '../../domain/coding_prompt_action.dart';
import '../../domain/coding_pubspec_package_change.dart';
import '../../domain/coding_symbol_index.dart';
import '../../domain/coding_task_evaluation.dart';
import '../../domain/coding_file_tree.dart';
import '../../domain/coding_untitled_file.dart';
import '../../domain/coding_folder_expansion.dart';
import '../../domain/coding_user_history_view.dart';
import '../../domain/coding_workspace_kind.dart';
import '../../domain/coding_workspace_scan.dart';
import '../../domain/entities/coding_assist_entities.dart';
import '../../domain/repositories/coding_assist_repository.dart';
import '../prompt/coding_assist_prompts.dart';
import 'coding_assist_event.dart';
import 'coding_assist_state.dart';

export 'coding_assist_event.dart';
export 'coding_assist_state.dart';

class CodingAssistBloc extends Bloc<CodingAssistEvent, CodingAssistState> {
  CodingAssistBloc({
    required CodingAssistRepository repository,
    required GetConnectionSettings getConnectionSettings,
    required SaveConnectionSettings saveConnectionSettings,
    required LocalLlmClient localLlmClient,
    required LocalLlmServerLauncher localLlmServerLauncher,
    required CodingUiSettingsLocalDataSource uiSettingsLocalDataSource,
  }) : _repository = repository,
       _getConnectionSettings = getConnectionSettings,
       _saveConnectionSettings = saveConnectionSettings,
       _localLlmClient = localLlmClient,
       _localLlmServerLauncher = localLlmServerLauncher,
       _uiSettingsLocalDataSource = uiSettingsLocalDataSource,
       super(const CodingAssistState()) {
    on<CodingAssistStarted>(_onStarted);
    on<CodingAssistOpenWorkspaceRequested>(_onOpenWorkspace);
    on<CodingAssistOpenFileRequested>(_onOpenFile);
    on<CodingAssistRevealLineConsumed>(_onRevealLineConsumed);
    on<CodingAssistRevealInTreeRequested>(_onRevealInTree);
    on<CodingAssistRevealInTreeConsumed>(_onRevealInTreeConsumed);
    on<CodingAssistCloseTabRequested>(_onCloseTab);
    on<CodingAssistSelectTabRequested>(_onSelectTab);
    on<CodingAssistTabContentChanged>(_onTabContentChanged);
    on<CodingAssistSaveTabRequested>(_onSaveTab);
    on<CodingAssistDraftChanged>(_onDraftChanged);
    on<CodingAssistSendRequested>(_onSend);
    on<CodingAssistTaskEvaluateRequested>(_onTaskEvaluate);
    on<CodingAssistStopRequested>(_onStop);
    on<CodingAssistApplyPatchRequested>(_onApplyPatch);
    on<CodingAssistApproveCreateFileRequested>(_onApproveCreateFile);
    on<CodingAssistRejectPatchRequested>(_onRejectPatch);
    on<CodingAssistMarkPatchAppliedRequested>(_onMarkPatchApplied);
    on<CodingAssistReproposePatchRequested>(_onReproposePatch);
    on<CodingAssistAddFileConflictChoiceRequested>(_onAddFileConflictChoice);
    on<CodingAssistNewThreadRequested>(_onNewThread);
    on<CodingAssistHistoryOpenRequested>(_onHistoryOpen);
    on<CodingAssistHistoryCloseRequested>(_onHistoryClose);
    on<CodingAssistOpenThreadRequested>(_onOpenThread);
    on<CodingAssistDeleteThreadRequested>(_onDeleteThread);
    on<CodingAssistSelectionAttached>(_onSelectionAttached);
    on<CodingAssistSelectionCleared>(_onSelectionCleared);
    on<CodingAssistFolderFilesAttachRequested>(_onFolderFilesAttachRequested);
    on<CodingAssistFolderStructureAttached>(_onFolderStructureAttached);
    on<CodingAssistFolderStructureRemoved>(_onFolderStructureRemoved);
    on<CodingAssistOpenFilesAttached>(_onOpenFilesAttached);
    on<CodingAssistOpenFileAttachmentRemoved>(_onOpenFileAttachmentRemoved);
    on<CodingAssistOpenFileAttachmentsCleared>(_onOpenFileAttachmentsCleared);
    on<CodingAssistProgramAnalyzeRequested>(_onProgramAnalyze);
    on<CodingAssistEditLastUserRequested>(_onEditLastUser);
    on<CodingAssistRerunLastUserRequested>(_onRerunLastUser);
    on<CodingAssistRevokeLastTurnRequested>(_onRevokeLastTurn);
    on<CodingAssistCodingModelChanged>(_onCodingModelChanged);
    on<CodingAssistCodingThinkingChanged>(_onCodingThinkingChanged);
    on<CodingAssistAgentAutoRunChanged>(_onAgentAutoRunChanged);
    on<CodingAssistUiFontSizesChanged>(_onUiFontSizesChanged);
    on<CodingAssistHarnessChanged>(_onHarnessChanged);
    on<CodingAssistAutoSleepSettingsChanged>(_onAutoSleepSettingsChanged);
    on<CodingAssistAutoSleepCancelled>(_onAutoSleepCancelled);
    on<CodingAssistAutoSleepDeadlineReached>(_onAutoSleepDeadlineReached);
    on<CodingAssistIndentSizeChanged>(_onIndentSizeChanged);
    on<CodingAssistPromptFavoriteToggled>(_onPromptFavoriteToggled);
    on<CodingAssistPromptActionToggled>(_onPromptActionToggled);
    on<CodingAssistCompactContextRequested>(_onCompactContext);
    on<CodingAssistErrorConsumed>(_onErrorConsumed);
    on<CodingAssistRefreshWorkspaceRequested>(_onRefreshWorkspace);
    on<CodingAssistReloadActiveTabFromDiskRequested>(
      _onReloadActiveTabFromDisk,
    );
    on<CodingAssistCreateFileRequested>(_onCreateFile);
    on<CodingAssistCreateUntitledFileRequested>(_onCreateUntitledFile);
    on<CodingAssistCreateFolderRequested>(_onCreateFolder);
    on<CodingAssistMovePathRequested>(_onMovePath);
    on<CodingAssistRenamePathRequested>(_onRenamePath);
    on<CodingAssistDeletePathRequested>(_onDeletePath);
    on<CodingAssistGitAddRequested>(_onGitAdd);
    on<CodingAssistAppendDraftRequested>(_onAppendDraft);
    on<CodingAssistSyncTabContentsRequested>(_onSyncTabContents);
    on<CodingAssistRemoveRecentWorkspaceRequested>(_onRemoveRecentWorkspace);
    on<CodingAssistFolderExpansionCaptured>(_onFolderExpansionCaptured);
  }

  final CodingAssistRepository _repository;
  final GetConnectionSettings _getConnectionSettings;
  final SaveConnectionSettings _saveConnectionSettings;
  final LocalLlmClient _localLlmClient;
  final LocalLlmServerLauncher _localLlmServerLauncher;
  final CodingUiSettingsLocalDataSource _uiSettingsLocalDataSource;

  bool _cancelRequested = false;

  /// このターンで、自動実行の不足パスをアプリがすでに開いたか。
  bool _autoSuppliedNamedPaths = false;

  /// 自動実行の入れ子（検証の修正ターンなど）を含む深さ。0 が周期の外。
  int _autoCycleDepth = 0;
  bool _autoSleepArmed = false;
  bool _autoSleepDeadlineReached = false;
  bool _autoSleepInProgress = false;
  DateTime? _autoSleepStartedAt;
  Timer? _autoSleepTimer;

  /// 生成ハンドラの完了を待たずにアイコンと停止ボタンへ反映する。
  final ValueNotifier<bool> autoSleepArmedNow = ValueNotifier(false);

  @override
  Future<void> close() {
    _autoSleepTimer?.cancel();
    autoSleepArmedNow.dispose();
    return super.close();
  }

  /// 自動実行中でも、スリープ予定だけをすぐ止める。Agent の生成は止めない。
  void cancelAutoSleepNow() {
    _autoSleepTimer?.cancel();
    _autoSleepTimer = null;
    _autoSleepDeadlineReached = false;
    _autoSleepStartedAt = null;
    _markAutoSleepArmed(false);
    if (!isClosed) add(const CodingAssistAutoSleepCancelled());
  }

  void _markAutoSleepArmed(bool armed) {
    _autoSleepArmed = armed;
    if (autoSleepArmedNow.value != armed) {
      autoSleepArmedNow.value = armed;
    }
  }

  /// 適用失敗→再提案の回数（パス単位。上限はハーネス）。
  final Map<String, int> _reproposedCounts = <String, int>{};

  /// 生成中に溜めた再提案対象（ターン終了後にまとめて実行）。
  final List<CodingProposedPatch> _queuedRepropose = <CodingProposedPatch>[];

  /// 画面の言語サーバ。未起動なら null のまま（grep 等だけ）。
  CodingSymbolIndex? _symbolIndex;
  CodingSymbolIndex? get symbolIndex => _symbolIndex;
  set symbolIndex(CodingSymbolIndex? value) {
    _symbolIndex = value;
    value?.applyHarness(state.harness);
  }

  /// 送信直前に組み立てるシグネチャ地図。
  String _symbolMap = '';

  /// 再提案の理由（patchId → 種別）。
  final Map<String, _CodingReproposeKind> _reproposeKinds =
      <String, _CodingReproposeKind>{};

  final CodingFlutterVerifyRunner _flutterVerify = CodingFlutterVerifyRunner();

  /// 人の送信以降に始めた修正セット数。自動検証の修正ターンではリセットしない。
  int _verifyFixSetsUsed = 0;

  /// 人の送信以降に自動で書けた Update／Add 件数。
  int _updatesAppliedThisCycle = 0;

  /// この周期でディスクへ書いた相対パス。次の自動実行では当初の添付を捨て、現状を読む。
  final Set<String> _writtenPathsThisCycle = <String>{};

  /// 直近の修正セットで自動で書けた Update／Add 件数。
  int _updatesAppliedThisSet = 0;

  /// ＋の「テストを実行」が付いた送信。書き込みが無くても検証する。
  bool _flutterVerifyRequested = false;

  /// 文書だけの＋。書き込み後の analyze／test を始めない。
  bool _documentOnlyTurn = false;

  /// 検証結果の報告ターン。ここから再検証へ戻さない。
  bool _flutterVerifyReportTurn = false;

  /// この周期で pubspec.yaml のパッケージ追加を人が行う必要がある。
  bool _packageInstallNeeded = false;

  /// 同一実行で新規会話へ移した回数。1回まで。人の送信で戻す。
  int _autoLoopRelocations = 0;

  /// 直前の Agent 回答。ツールだけの応答は入れない。
  CodingAutoExecution? _lastAutoAnswer;

  /// 直前の失敗した検証コマンド。
  CodingAutoExecution? _lastAutoCommand;

  /// この検証周期で本文を渡せたパス。セットをまたいで開き直さない。
  final Set<String> _verifyOpenedPaths = <String>{};

  /// この検証周期で開けなかったパス。セットをまたいで再要求しない。
  final Set<String> _verifyUnopenedPaths = <String>{};

  /// 今の Agent ターンで API にだけ載せる本文。ネストした再提案が終わったら戻す。
  List<({String path, String body})> _turnPreloadReads = const [];

  /// 生成中に同じ段落が続いた。ユーザーの停止とは別。
  bool _repeatAbort = false;

  void _resetFlutterVerifyCycle() {
    _verifyFixSetsUsed = 0;
    _updatesAppliedThisCycle = 0;
    _updatesAppliedThisSet = 0;
    _writtenPathsThisCycle.clear();
    _verifyOpenedPaths.clear();
    _verifyUnopenedPaths.clear();
    _flutterVerifyRequested = false;
    _documentOnlyTurn = false;
    _packageInstallNeeded = false;
    _autoLoopRelocations = 0;
    _lastAutoAnswer = null;
    _lastAutoCommand = null;
  }

  bool _generationCancelled() => _cancelRequested || _repeatAbort;

  void _noteGenerationRepeat(AiGenerationProgress progress) {
    if (_repeatAbort || _cancelRequested) return;
    if (progress.phase != AiGenerationPhase.generating) return;
    final text = progress.partialText;
    if (text.isEmpty || text.startsWith('（思考中')) return;
    if (codingGenerationRepeats(text)) _repeatAbort = true;
  }

  List<Map<String, String>> _withPreloadReads(
    List<Map<String, String>> messages,
  ) {
    if (_turnPreloadReads.isEmpty) return messages;
    return [
      ...messages,
      {'role': 'user', 'content': codingSuppliedFileBodies(_turnPreloadReads)},
    ];
  }

  void _armFlutterVerifyIfMarked(String text) {
    if (text.contains(codingAssistFlutterVerifyMarker)) {
      _flutterVerifyRequested = true;
    }
  }

  void _armDocumentOnlyTurn({
    required List<CodingPromptAction> actions,
    required String text,
  }) {
    _documentOnlyTurn =
        CodingPromptAction.skipsFlutterVerify(actions) ||
        (actions.isEmpty && codingTextSkipsFlutterVerify(text));
  }

  String _systemPromptFor(
    String? root, {
    CodingWorkspaceIndex? index,
    CodingHarnessSettings? harness,
  }) {
    final limits = harness ?? state.harness;
    final resolved = index ?? state.index;
    final kind = resolved?.kind ?? CodingWorkspaceKind.generic;
    final failures = limits.maxReadFailuresPerPath;
    final buf = StringBuffer(
      CodingWorkspaceKindDetect.systemPrompt(
        kind,
      ).replaceAll('3回', '$failures回'),
    );
    if (symbolIndex?.isReady == true) {
      buf
        ..writeln()
        ..writeln(CodingWorkspaceKindDetect.symbolToolsFor(kind).trim());
    }
    if (root != null && root.isNotEmpty) {
      buf
        ..writeln()
        ..writeln('プロファイル: ${CodingWorkspaceKindDetect.displayLabel(kind)}')
        ..writeln('ワークスペース: $root');
      final treeHint = resolved?.treeText ?? '';
      if (treeHint.isNotEmpty) {
        buf
          ..writeln('ファイル樹（要約）:')
          ..writeln(
            treeHint.length > limits.systemTreeChars
                ? '${treeHint.substring(0, limits.systemTreeChars)}\n…'
                : treeHint,
          );
      }
      if (_symbolMap.isNotEmpty) {
        buf
          ..writeln('シンボル地図（開いているファイルと取り込み中のシグネチャ。本文なし）:')
          ..writeln(_symbolMap);
      }
    }
    return buf.toString();
  }

  int _estimateUsedTokens({
    List<CodingChatMessage>? messages,
    String? draft,
    int? contextSize,
    String? workspaceRoot,
    CodingWorkspaceIndex? index,
    CodingAttachedSelection? attachedSelection,
    List<CodingAttachedOpenFile>? attachedOpenFiles,
    List<CodingAttachedFolderStructure>? attachedFolderStructures,
    bool clearAttached = false,
    bool clearAttachedOpenFiles = false,
    bool clearAttachedFolderStructures = false,
    CodingThread? thread,
    CodingHarnessSettings? harness,
    Set<String> restoreReadPaths = const {},
  }) {
    final limits = harness ?? state.harness;
    final th = thread ?? state.thread;
    final msgs = messages ?? th?.messages ?? state.messages;
    final input = draft ?? state.draft;
    final c = contextSize ?? state.contextSize;
    final autoExecute = state.localLlm.codingAutoApplyPatches;
    // 見積は API 送信ビュー基準（S16 §5.7。自動実行中は §5.7.6 の作業記憶）
    var history = 0;
    for (final body in CodingApiContextBuilder.apiContentBodies(
      msgs,
      compactedSummary: th?.compactedSummary,
      compactedUpToExclusive: th?.compactedUpToExclusive ?? 0,
      symbolTools: symbolIndex?.isReady == true,
      autoExecute: autoExecute,
      pendingPatchPaths: _pendingPatchPaths(th),
      harness: limits,
      restoreReadPaths: restoreReadPaths,
    )) {
      history +=
          CodingContextEstimator.estimateTokens(
            body,
            charsPerToken: limits.charsPerToken,
          ) +
          4;
    }
    final systemText = _systemPromptFor(
      workspaceRoot ?? state.workspaceRoot,
      index: index,
      harness: limits,
    );
    final system =
        CodingContextEstimator.estimateTokens(
          systemText,
          charsPerToken: limits.charsPerToken,
        ) +
        (systemText.isEmpty ? 0 : 4);
    final pending = CodingContextEstimator.estimateTokens(
      input,
      charsPerToken: limits.charsPerToken,
    );
    final attached = clearAttached
        ? null
        : (attachedSelection ?? state.attachedSelection);
    final attachedTokens = attached == null
        ? 0
        : CodingContextEstimator.estimateTokens(
            attached.toPromptBlock(),
            charsPerToken: limits.charsPerToken,
          );
    final openFiles = clearAttachedOpenFiles
        ? const <CodingAttachedOpenFile>[]
        : (attachedOpenFiles ?? state.attachedOpenFiles);
    var openFileTokens = 0;
    for (final f in openFiles) {
      openFileTokens += CodingContextEstimator.estimateTokens(
        f.toPromptBlock(maxChars: limits.openFileMaxChars),
        charsPerToken: limits.charsPerToken,
      );
    }
    final folders = clearAttachedFolderStructures
        ? const <CodingAttachedFolderStructure>[]
        : (attachedFolderStructures ?? state.attachedFolderStructures);
    var folderTokens = 0;
    for (final folder in folders) {
      folderTokens += CodingContextEstimator.estimateTokens(
        folder.toPromptBlock(),
        charsPerToken: limits.charsPerToken,
      );
    }
    final reserve = (c * limits.replyReserveRatio).ceil();
    return history +
        system +
        pending +
        attachedTokens +
        openFileTokens +
        folderTokens +
        reserve;
  }

  /// 検査・再指示の見積。作業記憶と添付の再加算はしない。
  int _estimateDeliverableTokens(
    List<Map<String, String>> apiMessages,
    String systemText,
  ) {
    final limits = state.harness;
    var used = 0;
    for (final message in apiMessages) {
      used +=
          CodingContextEstimator.estimateTokens(
            message['content'] ?? '',
            charsPerToken: limits.charsPerToken,
          ) +
          4;
    }
    used +=
        CodingContextEstimator.estimateTokens(
          systemText,
          charsPerToken: limits.charsPerToken,
        ) +
        (systemText.isEmpty ? 0 : 4);
    final context = state.contextSize;
    return used + (context * limits.replyReserveRatio).ceil();
  }

  String _composeUserTextWithAttachments(String draftText) {
    final parts = <String>[];
    for (final f in state.attachedOpenFiles) {
      parts.add(f.toPromptBlock(maxChars: state.harness.openFileMaxChars));
    }
    final sel = state.attachedSelection;
    if (sel != null) parts.add(sel.toPromptBlock());
    for (final folder in state.attachedFolderStructures) {
      final block = folder.toPromptBlock();
      if (block.isNotEmpty) parts.add(block);
    }
    final draft = draftText.trim();
    if (draft.isNotEmpty) parts.add(draft);
    return parts.join('\n\n');
  }

  List<String> _pendingPatchPaths(CodingThread? thread) {
    return [
      for (final patch
          in thread?.pendingPatches ?? const <CodingProposedPatch>[])
        if (patch.status == CodingPatchStatus.pending) patch.relativePath,
    ];
  }

  String _clipToolResult(String result) {
    final cap = state.harness.toolResultClipChars;
    if (result.length <= cap) return result;
    return '${result.substring(0, cap)}\n…';
  }

  Future<CodingWorkspaceIndex> _scanWorkspace(String root) {
    return CodingWorkspaceScan.scan(
      root,
      listedFileLimit: state.harness.maxListedFiles,
      treeLineLimit: state.harness.maxTreeLines,
    );
  }

  CodingContextWarningLevel _warningFor(
    int used, {
    int? contextSize,
    CodingHarnessSettings? harness,
  }) {
    final limits = harness ?? state.harness;
    return CodingContextEstimator.levelFor(
      usedTokens: used,
      contextSize: contextSize ?? state.contextSize,
      warnRatio: limits.warnRatio,
      blockRatio: limits.blockRatio,
    );
  }

  /// P1: 古い対話をテンプレ要約に畳む。成功したら更新後スレッド、失敗なら null。
  CodingThread? _compactThread(CodingThread thread) {
    final built = CodingApiContextBuilder.buildTemplateCompact(
      messages: thread.messages,
      existingSummary: thread.compactedSummary,
      harness: state.harness,
    );
    if (built == null) return null;
    final upTo = built.upToExclusive;
    if (upTo <= thread.compactedUpToExclusive) return null;
    return thread.copyWith(
      compactedSummary: built.summary,
      compactedAt: DateTime.now(),
      compactedUpToExclusive: upTo,
      contextWarningLevel: CodingContextWarningLevel.compacted,
      updatedAt: DateTime.now(),
    );
  }

  Future<void> _onStarted(
    CodingAssistStarted event,
    Emitter<CodingAssistState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, clearError: true));
    String? error;
    String? mtpDraft;
    var llm = const LocalLlmConnectionSettings();
    var recent = <String>[];
    final uiFonts = _uiSettingsLocalDataSource.loadFontSizes();
    final harness = _uiSettingsLocalDataSource.loadHarness();
    final autoSleep = _uiSettingsLocalDataSource.loadAutoSleepSettings();
    final indentSize = _uiSettingsLocalDataSource.loadIndentSize();
    final promptFavorites = _uiSettingsLocalDataSource.loadPromptFavorites();
    try {
      final settings = await _getConnectionSettings();
      llm = settings.localLlm;
    } catch (e) {
      error = '設定の読込に失敗: $e';
    }
    try {
      recent = await _repository.listRecentWorkspaces();
      // 保存済みの空「新規」を履歴から外す。
      await _repository.listSummaries();
    } catch (e) {
      error = error == null ? '$e' : '$error / $e';
    }

    if (llm.enabled) {
      emit(
        state.copyWith(isLlmBusy: true, agentStatusMessage: 'コーディング用モデルを起動中…'),
      );
      try {
        mtpDraft = await _localLlmServerLauncher.applySettings(
          settings: llm.forServer(),
          isHealthy: _localLlmClient.isReachable,
        );
      } catch (e) {
        error = error == null ? 'コーディング用モデルの起動に失敗: $e' : '$error（起動失敗: $e）';
      }
    }

    emit(
      state.copyWith(
        isLoading: false,
        isLlmBusy: false,
        localLlm: llm,
        uiFontSizes: uiFonts,
        harness: harness,
        autoSleepSettings: autoSleep,
        indentSize: indentSize,
        promptFavorites: promptFavorites,
        recentWorkspaces: recent,
        usedTokens: _estimateUsedTokens(
          messages: const [],
          draft: '',
          contextSize: llm.codingContextSize,
          harness: harness,
        ),
        agentStatusMessage: !llm.enabled
            ? 'ローカルLLMがOFFです'
            : mtpDraft == null
                ? 'コーディング用モデル準備完了'
                : 'MTP 下書き係を併用します（$mtpDraft）',
        mtpDraftFileName: mtpDraft,
        clearMtpDraft: mtpDraft == null,
        errorMessage: error,
        clearError: error == null,
      ),
    );
    symbolIndex?.applyHarness(state.harness);
  }

  Future<void> _onAutoSleepSettingsChanged(
    CodingAssistAutoSleepSettingsChanged event,
    Emitter<CodingAssistState> emit,
  ) async {
    final next = event.settings.normalized();
    try {
      await _uiSettingsLocalDataSource.saveAutoSleepSettings(next);
    } catch (e) {
      emit(state.copyWith(errorMessage: 'スリープ設定の保存に失敗: $e'));
      return;
    }
    emit(state.copyWith(autoSleepSettings: next));
    if (!next.enabled) {
      if (_autoSleepArmed) {
        _disarmAutoSleep(emit, status: 'スリープ予定を停止しました');
      }
      return;
    }
    final cycleRunning =
        _autoCycleDepth > 0 && state.localLlm.codingAutoApplyPatches;
    if (!cycleRunning && !_autoSleepArmed) return;
    if (!_autoSleepArmed) {
      _autoSleepStartedAt = DateTime.now();
      _autoSleepDeadlineReached = false;
      _markAutoSleepArmed(true);
    }
    _scheduleAutoSleepTimer();
    emit(
      state.copyWith(
        autoSleepArmed: true,
        autoSleepDeadline: _autoSleepDeadlineFrom(next),
        clearAutoSleepDeadline: next.sleepAfterMinutes <= 0,
      ),
    );
  }

  // フォルダ未選択時、最近開いたフォルダ一覧から特定のフォルダを削除する機能
  // フォルダ未選択時、最近開いたフォルダ一覧から特定のフォルダを削除する機能
  Future<void> _onRemoveRecentWorkspace(
    CodingAssistRemoveRecentWorkspaceRequested event,
    Emitter<CodingAssistState> emit,
  ) async {
    final root = event.rootPath.trim();
    if (root.isEmpty) return;
    try {
      await _repository.removeRecentWorkspace(root);
      final recent = await _repository.listRecentWorkspaces();
      emit(state.copyWith(recentWorkspaces: recent));
    } catch (e) {
      emit(state.copyWith(errorMessage: '最近開いたフォルダの削除に失敗: $e'));
    }
  }

  Future<void> _onFolderExpansionCaptured(
    CodingAssistFolderExpansionCaptured event,
    Emitter<CodingAssistState> emit,
  ) async {
    final root = event.workspaceRoot.trim();
    if (root.isEmpty) return;
    if (state.workspaceRoot != root) {
      try {
        final existing = await _repository.loadFolderExpansion(root);
        final merged = CodingFolderExpansion.merge(
          remembered: existing,
          visible: event.visible,
        );
        if (CodingFolderExpansion.same(existing, merged)) return;
        await _repository.saveFolderExpansion(root, merged);
      } catch (e) {
        if (!emit.isDone) {
          emit(state.copyWith(errorMessage: 'フォルダの展開状態の保存に失敗: $e'));
        }
      }
      return;
    }
    final merged = CodingFolderExpansion.merge(
      remembered: state.folderExpansion,
      visible: event.visible,
    );
    if (CodingFolderExpansion.same(state.folderExpansion, merged)) return;
    emit(state.copyWith(folderExpansion: merged));
    try {
      await _repository.saveFolderExpansion(root, merged);
    } catch (e) {
      if (!emit.isDone) {
        emit(state.copyWith(errorMessage: 'フォルダの展開状態の保存に失敗: $e'));
      }
    }
  }

  Future<void> _persistMovedFolderExpansion({
    required String workspaceRoot,
    required Map<String, bool>? previous,
    required Map<String, bool>? next,
    required Emitter<CodingAssistState> emit,
  }) async {
    if (next == null || identical(next, previous)) return;
    try {
      await _repository.saveFolderExpansion(workspaceRoot, next);
    } catch (e) {
      if (!emit.isDone) {
        emit(state.copyWith(errorMessage: 'フォルダの展開状態の保存に失敗: $e'));
      }
    }
  }

  void _onAutoSleepCancelled(
    CodingAssistAutoSleepCancelled event,
    Emitter<CodingAssistState> emit,
  ) {
    _disarmAutoSleep(emit, status: 'スリープ予定を停止しました');
  }

  Future<void> _onAutoSleepDeadlineReached(
    CodingAssistAutoSleepDeadlineReached event,
    Emitter<CodingAssistState> emit,
  ) async {
    if (!_autoSleepArmed || _autoSleepInProgress) return;
    if (_autoCycleDepth > 0 || state.isGenerating) return;
    _autoSleepDeadlineReached = true;
    _cancelRequested = true;
    await _sleepAndDisarm(emit);
  }

  bool _beginAutoSleepCycle(Emitter<CodingAssistState> emit) {
    final settings = state.autoSleepSettings;
    if (!settings.enabled || !state.localLlm.codingAutoApplyPatches) {
      return false;
    }
    _markAutoSleepArmed(true);
    _autoSleepDeadlineReached = false;
    _autoSleepStartedAt = DateTime.now();
    _scheduleAutoSleepTimer();
    emit(
      state.copyWith(
        autoSleepArmed: true,
        autoSleepDeadline: _autoSleepDeadlineFrom(settings),
        clearAutoSleepDeadline: settings.sleepAfterMinutes <= 0,
      ),
    );
    return true;
  }

  Future<void> _finishAutoSleepCycle(Emitter<CodingAssistState> emit) async {
    if (emit.isDone || !_autoSleepArmed || _autoSleepInProgress) return;
    final sleep = CodingAutoSleepPolicy.sleepOnCycleEnd(
      settings: state.autoSleepSettings,
      armed: true,
      deadlineReached: _autoSleepDeadlineReached,
      stoppedByUser: _cancelRequested && !_autoSleepDeadlineReached,
    );
    if (sleep) {
      await _sleepAndDisarm(emit);
      return;
    }
    final waitingForTimer =
        state.autoSleepSettings.sleepAfterMinutes > 0 &&
        _autoSleepTimer != null;
    if (!waitingForTimer) {
      _disarmAutoSleep(emit);
    }
  }

  void _scheduleAutoSleepTimer() {
    _autoSleepTimer?.cancel();
    _autoSleepTimer = null;
    final settings = state.autoSleepSettings;
    final started = _autoSleepStartedAt;
    if (!_autoSleepArmed ||
        started == null ||
        settings.sleepAfterMinutes <= 0) {
      return;
    }
    final deadline = started.add(Duration(minutes: settings.sleepAfterMinutes));
    final delay = deadline.difference(DateTime.now());
    _autoSleepTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
      if (!_autoSleepArmed || _autoSleepInProgress) return;
      _autoSleepDeadlineReached = true;
      _cancelRequested = true;
      if (_autoCycleDepth == 0) {
        add(const CodingAssistAutoSleepDeadlineReached());
      }
    });
  }

  DateTime? _autoSleepDeadlineFrom(CodingAutoSleepSettings settings) {
    final started = _autoSleepStartedAt;
    if (started == null || settings.sleepAfterMinutes <= 0) return null;
    return started.add(Duration(minutes: settings.sleepAfterMinutes));
  }

  void _disarmAutoSleep(Emitter<CodingAssistState> emit, {String? status}) {
    _autoSleepTimer?.cancel();
    _autoSleepTimer = null;
    _autoSleepDeadlineReached = false;
    _autoSleepStartedAt = null;
    _markAutoSleepArmed(false);
    if (emit.isDone) return;
    emit(
      state.copyWith(
        autoSleepArmed: false,
        clearAutoSleepDeadline: true,
        agentStatusMessage: status,
      ),
    );
  }

  Future<void> _sleepAndDisarm(Emitter<CodingAssistState> emit) async {
    if (_autoSleepInProgress) return;
    _autoSleepInProgress = true;
    _autoSleepTimer?.cancel();
    _autoSleepTimer = null;
    _cancelRequested = true;
    _autoSleepStartedAt = null;
    _markAutoSleepArmed(false);
    if (!emit.isDone) {
      emit(
        state.copyWith(
          autoSleepArmed: false,
          clearAutoSleepDeadline: true,
          agentStatusMessage: '停止してスリープします…',
        ),
      );
    }
    final error = await CodingSystemSleeper.sleepNow();
    _autoSleepDeadlineReached = false;
    _autoSleepInProgress = false;
    _cancelRequested = false;
    if (error != null && !emit.isDone) {
      emit(state.copyWith(errorMessage: error, agentStatusMessage: error));
    }
  }

  Future<void> _onUiFontSizesChanged(
    CodingAssistUiFontSizesChanged event,
    Emitter<CodingAssistState> emit,
  ) async {
    final next = event.sizes.copyWith();
    emit(state.copyWith(uiFontSizes: next));
    try {
      await _uiSettingsLocalDataSource.saveFontSizes(next);
    } catch (e) {
      emit(state.copyWith(errorMessage: 'フォントサイズの保存に失敗: $e'));
    }
  }

  Future<void> _onHarnessChanged(
    CodingAssistHarnessChanged event,
    Emitter<CodingAssistState> emit,
  ) async {
    final next = event.settings.normalized();
    if (state.harness == next) return;
    final used = _estimateUsedTokens(harness: next);
    emit(
      state.copyWith(
        harness: next,
        usedTokens: used,
        warningLevel: _warningFor(used, harness: next),
      ),
    );
    symbolIndex?.applyHarness(next);
    try {
      await _uiSettingsLocalDataSource.saveHarness(next);
    } catch (e) {
      emit(state.copyWith(errorMessage: 'ハーネス設定の保存に失敗: $e'));
    }
  }

  Future<void> _onIndentSizeChanged(
    CodingAssistIndentSizeChanged event,
    Emitter<CodingAssistState> emit,
  ) async {
    final next = event.indentSize == 2 ? 2 : 4;
    if (state.indentSize == next) return;
    emit(state.copyWith(indentSize: next));
    try {
      await _uiSettingsLocalDataSource.saveIndentSize(next);
    } catch (e) {
      emit(state.copyWith(errorMessage: 'インデント設定の保存に失敗: $e'));
    }
  }

  Future<void> _onPromptFavoriteToggled(
    CodingAssistPromptFavoriteToggled event,
    Emitter<CodingAssistState> emit,
  ) async {
    final next = CodingPromptAction.toggleFavorite(
      current: state.promptFavorites,
      action: event.action,
    );
    if (next == null) {
      emit(
        state.copyWith(
          errorMessage: 'お気に入りは${CodingPromptAction.maxFavorites}つまでです',
        ),
      );
      return;
    }
    emit(state.copyWith(promptFavorites: next, clearError: true));
    try {
      await _uiSettingsLocalDataSource.savePromptFavorites(next);
    } catch (e) {
      emit(state.copyWith(errorMessage: 'お気に入りの保存に失敗: $e'));
    }
  }

  void _onPromptActionToggled(
    CodingAssistPromptActionToggled event,
    Emitter<CodingAssistState> emit,
  ) {
    final action = event.action;
    if (action == CodingPromptAction.attachSelection) return;
    final toggled = CodingPromptAction.toggleApplied(
      current: state.appliedPromptActions,
      action: action,
    );
    final removing = !toggled.applied.contains(action);
    final status = removing
        ? '適用解除: ${action.shortLabel}'
        : toggled.removed.isEmpty
        ? '適用: ${action.shortLabel}'
        : '適用: ${action.shortLabel}'
              '（${toggled.removed.map((item) => item.shortLabel).join('、')}は外しました）';
    emit(
      state.copyWith(
        appliedPromptActions: toggled.applied,
        clearError: true,
        agentStatusMessage: status,
      ),
    );
  }

  Future<void> _onOpenWorkspace(
    CodingAssistOpenWorkspaceRequested event,
    Emitter<CodingAssistState> emit,
  ) async {
    final root = event.rootPath.trim();
    if (root.isEmpty) return;
    _resetFlutterVerifyCycle();
    emit(state.copyWith(workspaceStatusMessage: '索引を作成中…', clearError: true));
    try {
      final index = await _scanWorkspace(root);
      final branch = await CodingGit.currentBranch(root);
      await _repository.rememberWorkspace(root);
      final recent = await _repository.listRecentWorkspaces();
      final folderExpansion = await _repository.loadFolderExpansion(root);
      final thread = CodingThread(
        id: const Uuid().v4(),
        title: CodingThread.placeholderTitle,
        workspaceRootPath: root,
        messages: const [],
        updatedAt: DateTime.now(),
      );
      emit(
        state.copyWith(
          workspaceRoot: root,
          gitBranch: branch,
          clearGitBranch: branch == null,
          index: index,
          openTabs: const [],
          clearActiveTab: true,
          thread: thread,
          pendingPatches: const [],
          recentWorkspaces: recent,
          folderExpansion: folderExpansion,
          clearFolderExpansion: folderExpansion == null,
          isHistoryOpen: false,
          isEditingLastUser: false,
          clearAttachedSelection: true,
          clearAttachedOpenFiles: true,
          clearAttachedFolderStructures: true,
          clearAppliedPromptActions: true,
          usedTokens: _estimateUsedTokens(
            messages: const [],
            draft: state.draft,
            workspaceRoot: root,
            index: index,
            clearAttached: true,
            clearAttachedOpenFiles: true,
            clearAttachedFolderStructures: true,
          ),
          workspaceStatusMessage:
              '${index.rootLabel}（${index.relativeFiles.length} files）',
        ),
      );
      await _repository.saveThread(thread);
    } catch (e) {
      emit(state.copyWith(errorMessage: '$e', clearWorkspaceStatus: true));
    }
  }

  Future<void> _onOpenFile(
    CodingAssistOpenFileRequested event,
    Emitter<CodingAssistState> emit,
  ) async {
    final root = state.workspaceRoot;
    if (root == null) return;
    final rel = event.relativePath.replaceAll('\\', '/');
    final reveal = event.revealLine;
    final revealOffset = event.revealOffset;
    final revealLength = event.revealLength;
    final existing = state.openTabs.where((t) => t.relativePath == rel);
    if (existing.isNotEmpty) {
      emit(
        state.copyWith(
          activeTabPath: rel,
          revealLine: reveal,
          revealOffset: revealOffset,
          revealLength: revealLength,
          clearRevealLine: reveal == null,
        ),
      );
      return;
    }
    try {
      final abs = p.join(root, rel);
      final content = await File(abs).readAsString();
      emit(
        state.copyWith(
          openTabs: [
            ...state.openTabs,
            CodingOpenTab(relativePath: rel, content: content),
          ],
          activeTabPath: rel,
          revealLine: reveal,
          revealOffset: revealOffset,
          revealLength: revealLength,
          clearRevealLine: reveal == null,
        ),
      );
    } catch (e) {
      emit(state.copyWith(errorMessage: 'ファイルを開けません: $e'));
    }
  }

  void _onRevealLineConsumed(
    CodingAssistRevealLineConsumed event,
    Emitter<CodingAssistState> emit,
  ) {
    if (state.revealLine == null) return;
    emit(state.copyWith(clearRevealLine: true));
  }

  void _onRevealInTree(
    CodingAssistRevealInTreeRequested event,
    Emitter<CodingAssistState> emit,
  ) {
    final rel = event.relativePath.replaceAll('\\', '/').trim();
    if (rel.isEmpty) return;
    emit(state.copyWith(treeRevealPath: rel, activeTabPath: rel));
  }

  void _onRevealInTreeConsumed(
    CodingAssistRevealInTreeConsumed event,
    Emitter<CodingAssistState> emit,
  ) {
    if (state.treeRevealPath == null) return;
    emit(state.copyWith(clearTreeRevealPath: true));
  }

  void _onCloseTab(
    CodingAssistCloseTabRequested event,
    Emitter<CodingAssistState> emit,
  ) {
    final next = state.openTabs
        .where((t) => t.relativePath != event.relativePath)
        .toList();
    String? active = state.activeTabPath;
    if (active == event.relativePath) {
      active = next.isEmpty ? null : next.last.relativePath;
    }
    emit(
      state.copyWith(
        openTabs: next,
        activeTabPath: active,
        clearActiveTab: active == null,
      ),
    );
  }

  void _onSelectTab(
    CodingAssistSelectTabRequested event,
    Emitter<CodingAssistState> emit,
  ) {
    emit(state.copyWith(activeTabPath: event.relativePath));
  }

  void _onTabContentChanged(
    CodingAssistTabContentChanged event,
    Emitter<CodingAssistState> emit,
  ) {
    final next = [
      for (final t in state.openTabs)
        if (t.relativePath == event.relativePath)
          t.copyWith(content: event.content, dirty: true)
        else
          t,
    ];
    emit(state.copyWith(openTabs: next));
  }

  Future<void> _onSaveTab(
    CodingAssistSaveTabRequested event,
    Emitter<CodingAssistState> emit,
  ) async {
    final root = state.workspaceRoot;
    if (root == null) return;
    final tab = state.openTabs
        .where((t) => t.relativePath == event.relativePath)
        .firstOrNull;
    if (tab == null) return;
    try {
      final file = File(p.join(root, tab.relativePath));
      await file.writeAsString(tab.content);
      final next = [
        for (final t in state.openTabs)
          if (t.relativePath == tab.relativePath)
            t.copyWith(dirty: false)
          else
            t,
      ];
      emit(state.copyWith(openTabs: next, workspaceStatusMessage: '保存しました'));
    } catch (e) {
      emit(state.copyWith(errorMessage: '保存失敗: $e'));
    }
  }

  void _onAppendDraft(
    CodingAssistAppendDraftRequested event,
    Emitter<CodingAssistState> emit,
  ) {
    final chunk = event.text.trimRight();
    if (chunk.isEmpty) return;
    final current = state.draft;
    final next = current.trimRight().isEmpty
        ? chunk
        : '${current.trimRight()}\n\n$chunk';
    emit(
      state.copyWith(
        draft: next,
        bumpDraftEpoch: true,
        agentStatusMessage: 'Agent 入力へ貼り付けました',
      ),
    );
  }

  void _onSyncTabContents(
    CodingAssistSyncTabContentsRequested event,
    Emitter<CodingAssistState> emit,
  ) {
    if (event.contentsByRelativePath.isEmpty) return;
    final next = [
      for (final t in state.openTabs)
        if (event.contentsByRelativePath.containsKey(t.relativePath))
          t.copyWith(
            content: event.contentsByRelativePath[t.relativePath]!,
            dirty: false,
          )
        else
          t,
    ];
    emit(
      state.copyWith(openTabs: next, workspaceStatusMessage: '置換結果をタブに反映しました'),
    );
  }

  void _onDraftChanged(
    CodingAssistDraftChanged event,
    Emitter<CodingAssistState> emit,
  ) {
    final used = _estimateUsedTokens(draft: event.value);
    var warn = _warningFor(used);
    if (state.thread?.compactedSummary != null &&
        warn != CodingContextWarningLevel.block) {
      warn = CodingContextWarningLevel.compacted;
    }
    emit(
      state.copyWith(draft: event.value, usedTokens: used, warningLevel: warn),
    );
  }

  void _onStop(
    CodingAssistStopRequested event,
    Emitter<CodingAssistState> emit,
  ) {
    _cancelRequested = true;
    emit(state.copyWith(agentStatusMessage: '停止を要求しました…'));
  }

  Future<void> _onSend(
    CodingAssistSendRequested event,
    Emitter<CodingAssistState> emit,
  ) async {
    final rawDraft = state.draft.trim();
    final wantsVerify = state.appliedPromptActions.contains(
      CodingPromptAction.runFlutterVerify,
    );
    if (rawDraft.isEmpty && !state.hasPromptAttachments && !wantsVerify) {
      return;
    }
    if (state.appliedPromptActions.contains(CodingPromptAction.errorAnalyze) &&
        rawDraft.isEmpty) {
      emit(state.copyWith(errorMessage: 'エラーを貼り付けてください'));
      return;
    }
    final requestText = state.draft.trim();
    final fixedPrompts = List<CodingPromptAction>.from(
      state.appliedPromptActions,
    );
    final text = _composeUserTextWithAttachments(
      codingAssistApplyPromptActions(
        state.draft,
        fixedPrompts,
        omitReadFile: state.localLlm.codingAutoApplyPatches,
        kind: state.index?.kind ?? CodingWorkspaceKind.generic,
      ),
    );
    if (text.trim().isEmpty) return;
    _resetFlutterVerifyCycle();
    _armFlutterVerifyIfMarked(text);
    _armDocumentOnlyTurn(actions: fixedPrompts, text: text);
    _reproposedCounts.clear();
    _queuedRepropose.clear();
    await _runAgentTurn(
      emit,
      userText: text,
      clearDraft: true,
      honorEditLastUser: true,
      fixedPrompts: fixedPrompts,
      requestText: requestText,
      recordComposerAttachments: true,
    );
  }

  Future<void> _onTaskEvaluate(
    CodingAssistTaskEvaluateRequested event,
    Emitter<CodingAssistState> emit,
  ) async {
    final root = state.workspaceRoot;
    if (root == null || state.isGenerating || state.isLlmBusy) return;
    if (!state.localLlm.isCodingUsable) {
      emit(state.copyWith(errorMessage: 'コーディング用 LLM が利用できません'));
      return;
    }
    final source = codingTaskEvaluationSource(state.messages);
    if (source == null) {
      emit(state.copyWith(errorMessage: '評価するタスク分解がありません'));
      return;
    }
    final cap = state.harness.openFileMaxChars;
    final instruction = codingAssistTaskEvaluatePrompt(source.tasks);
    final text = [
      for (final file in source.files) file.toPromptBlock(maxChars: cap),
      instruction,
    ].join('\n\n');
    final chips = [
      for (final file in source.files)
        CodingHistoryChip(
          kind: CodingHistoryChipKind.file,
          label: file.relativePath,
          path: file.relativePath,
        ),
    ];
    _resetFlutterVerifyCycle();
    final thread = CodingThread(
      id: const Uuid().v4(),
      title: CodingThread.placeholderTitle,
      workspaceRootPath: root,
      messages: const [],
      updatedAt: DateTime.now(),
    );
    emit(
      state.copyWith(
        thread: thread,
        pendingPatches: const [],
        draft: '',
        bumpDraftEpoch: true,
        streamingText: '',
        isHistoryOpen: false,
        isEditingLastUser: false,
        clearAttachedSelection: true,
        clearAttachedOpenFiles: true,
        clearAttachedFolderStructures: true,
        clearAppliedPromptActions: true,
        usedTokens: _estimateUsedTokens(
          messages: const [],
          draft: '',
          clearAttached: true,
          clearAttachedOpenFiles: true,
          clearAttachedFolderStructures: true,
        ),
        warningLevel: CodingContextWarningLevel.none,
        agentStatusMessage: 'タスク評価の会話を作成しました',
        clearError: true,
      ),
    );
    _reproposedCounts.clear();
    _queuedRepropose.clear();
    await _runAgentTurn(
      emit,
      userText: text,
      clearDraft: true,
      honorEditLastUser: false,
      fixedPrompts: const [CodingPromptAction.taskEvaluate],
      requestText: source.tasks,
      historyChips: chips,
    );
  }

  Future<void> _onProgramAnalyze(
    CodingAssistProgramAnalyzeRequested event,
    Emitter<CodingAssistState> emit,
  ) async {
    final prompt = event.prompt.trim();
    if (prompt.isEmpty) return;

    var files = List<CodingAttachedOpenFile>.from(state.attachedOpenFiles);
    if (files.isEmpty) {
      final fallback = event.fallbackActiveFile;
      if (fallback == null || fallback.relativePath.trim().isEmpty) {
        emit(
          state.copyWith(
            errorMessage: '分析するファイルがありません。ファイルを取り込むか、エディタでファイルを開いてください',
          ),
        );
        return;
      }
      final rel = fallback.relativePath.replaceAll('\\', '/');
      final cap = state.harness.openFileMaxChars;
      final content = fallback.content.length > cap
          ? fallback.content.substring(0, cap)
          : fallback.content;
      files = [CodingAttachedOpenFile(relativePath: rel, content: content)];
      emit(
        state.copyWith(
          attachedOpenFiles: files,
          usedTokens: _estimateUsedTokens(attachedOpenFiles: files),
          agentStatusMessage: '取り込み中: 1 件（分析用）',
          clearError: true,
        ),
      );
    }

    final parts = <String>[
      for (final f in files)
        f.toPromptBlock(maxChars: state.harness.openFileMaxChars),
      if (state.attachedSelection != null)
        state.attachedSelection!.toPromptBlock(),
      for (final folder in state.attachedFolderStructures)
        folder.toPromptBlock(),
      prompt,
    ];
    final text = parts.join('\n\n');
    _resetFlutterVerifyCycle();
    _reproposedCounts.clear();
    _queuedRepropose.clear();
    await _runAgentTurn(
      emit,
      userText: text,
      clearDraft: true,
      honorEditLastUser: true,
      requestText: prompt,
      recordComposerAttachments: true,
    );
  }

  Future<void> _onReproposePatch(
    CodingAssistReproposePatchRequested event,
    Emitter<CodingAssistState> emit,
  ) async {
    final patch = state.pendingPatches
        .where((p) => p.id == event.patchId)
        .firstOrNull;
    if (patch == null) return;
    // 手動再提案はガードを解除して再実行可
    _reproposedCounts.remove(patch.relativePath.replaceAll('\\', '/'));
    await _startReproposeFromCurrent(emit, [patch]);
  }

  Future<void> _onAddFileConflictChoice(
    CodingAssistAddFileConflictChoiceRequested event,
    Emitter<CodingAssistState> emit,
  ) async {
    final patch = state.pendingPatches
        .where((p) => p.id == event.patchId)
        .firstOrNull;
    if (patch == null || !patch.isAddFile) return;
    final rel = patch.relativePath.replaceAll('\\', '/');
    _reproposedCounts.remove(rel);
    final kind = switch (event.choice) {
      CodingAddFileConflictChoice.reviseExisting =>
        _CodingReproposeKind.addReviseExisting,
      CodingAddFileConflictChoice.chooseNewPath =>
        _CodingReproposeKind.addChooseNewPath,
    };
    await _startReproposeFromCurrent(
      emit,
      [patch],
      kindsById: {patch.id: kind},
    );
  }

  String _normalizeWorkspacePath(String raw) {
    final root = state.workspaceRoot;
    if (root == null || root.isEmpty) {
      return raw.replaceAll('\\', '/').trim();
    }
    final index = state.index;
    return CodingPathResolver.normalizeInput(
      raw,
      rootPath: root,
      rootLabel: index?.rootLabel ?? p.basename(root),
      indexedFiles: index?.relativeFiles ?? const [],
      indexedDirectories: index?.relativeDirectories ?? const [],
    );
  }

  String _reproposeAddPathGuidance(String relativePath) {
    if (relativePath.contains('/')) {
      return '未作成／空なので *** Add File: $relativePath と + 行のみで出し直すこと（文脈行不要）。';
    }
    final sample = CodingWorkspaceKindDetect.samplesFor(
      state.index?.kind ?? CodingWorkspaceKind.generic,
    ).addFile;
    return 'ファイル名だけなので作成できない。'
        '既存構成に合わせたディレクトリ付き相対パスの *** Add File で出し直すこと'
        '（例: $sample。この例をそのまま使わない。ファイル名だけは禁止）。';
  }

  /// 中身のある既存パスへの Add File は、作成の前に手段変更できるよう印を付ける。
  Future<List<CodingProposedPatch>> _markExistingAddFiles(
    List<CodingProposedPatch> patches,
  ) async {
    final root = state.workspaceRoot;
    if (root == null) return patches;
    final marked = <CodingProposedPatch>[];
    for (final patch in patches) {
      if (!patch.isAddFile ||
          patch.status != CodingPatchStatus.pending ||
          patch.errorMessage == codingAddFileExistsMessage) {
        marked.add(patch);
        continue;
      }
      final rel = _normalizeWorkspacePath(patch.relativePath);
      if (rel.isEmpty || !rel.contains('/')) {
        marked.add(patch);
        continue;
      }
      final open = state.openTabs
          .where((t) => t.relativePath.replaceAll('\\', '/') == rel)
          .firstOrNull;
      final file = File(p.join(root, rel));
      final existing =
          open?.content ??
          (await file.exists() ? await file.readAsString() : '');
      if (existing.trim().isEmpty) {
        marked.add(
          patch.relativePath == rel ? patch : patch.copyWith(relativePath: rel),
        );
        continue;
      }
      marked.add(
        patch.copyWith(
          relativePath: rel,
          errorMessage: codingAddFileExistsMessage,
        ),
      );
    }
    return marked;
  }

  /// 現状ファイルを正として Agent にパッチ再提案を依頼する。
  Future<void> _startReproposeFromCurrent(
    Emitter<CodingAssistState> emit,
    List<CodingProposedPatch> patches, {
    Map<String, _CodingReproposeKind>? kindsById,
  }) async {
    if (patches.isEmpty) return;
    if (kindsById != null) {
      _reproposeKinds.addAll(kindsById);
    }
    if (state.isGenerating) {
      for (final p in patches) {
        if (!_queuedRepropose.any((q) => q.id == p.id)) {
          _queuedRepropose.add(p);
        }
      }
      return;
    }
    final root = state.workspaceRoot;
    if (root == null) return;

    final blocks = <String>[];
    final dropIds = <String>{};
    final droppedConflicts = <String>[];
    var anyAddExists = false;
    var anyReviseExisting = false;
    var anyChooseNewPath = false;
    var anyEmptyTarget = false;
    var anyPrescribedAdd = false;
    var anyPrescribedUpdate = false;
    for (final patch in patches) {
      final rel = patch.relativePath.replaceAll('\\', '/');
      final used = _reproposedCounts[rel] ?? 0;
      if (used >= state.harness.maxAutoReproposals) continue;
      _reproposedCounts[rel] = used + 1;
      dropIds.add(patch.id);
      final current = await _loadCurrentFileText(rel);
      final kind =
          _reproposeKinds[patch.id] ??
          (current.trim().isEmpty
              ? _CodingReproposeKind.addOrEmpty
              : _CodingReproposeKind.generic);
      CodingAddConflictPlan? plan;
      if (kind == _CodingReproposeKind.addExists) {
        anyAddExists = true;
        plan = codingPlanAddFileConflict(
          existingPath: rel,
          existingContent: current,
          proposedDiff: patch.rawDiff,
          destinationOccupied: _workspaceFileOccupied,
          destinationUnavailable: (path) {
            final key = path.replaceAll('\\', '/');
            return _verifyUnopenedPaths.contains(key) &&
                !_workspaceFileOccupied(key);
          },
        );
        if (plan.action == CodingAddConflictAction.drop) {
          droppedConflicts.add(rel);
          _reproposeKinds.remove(patch.id);
          continue;
        }
        if (plan.action == CodingAddConflictAction.addElsewhere) {
          anyPrescribedAdd = true;
        } else {
          anyPrescribedUpdate = true;
        }
      }
      if (kind == _CodingReproposeKind.addReviseExisting) {
        anyReviseExisting = true;
      }
      if (kind == _CodingReproposeKind.addChooseNewPath) {
        anyChooseNewPath = true;
      }
      if (kind == _CodingReproposeKind.addOrEmpty || current.trim().isEmpty) {
        anyEmptyTarget = true;
      }
      var blockPath = rel;
      var blockContent = current;
      if (plan != null && plan.path.isNotEmpty && plan.path != rel) {
        blockPath = plan.path;
        blockContent = plan.action == CodingAddConflictAction.addElsewhere
            ? ''
            : await _loadCurrentFileText(plan.path);
      }
      blocks.add(
        _buildReproposeBlock(
          relativePath: blockPath,
          currentContent: blockContent,
          failedDiff: patch.rawDiff,
          kind: kind,
          plan: plan,
        ),
      );
      _reproposeKinds.remove(patch.id);
    }

    // 失敗した旧パッチは除去（新提案で置き換える）。出せない衝突も残さない。
    final pending = [
      for (final p in state.pendingPatches)
        if (!dropIds.contains(p.id)) p,
    ];
    final thread = state.thread?.copyWith(
      pendingPatches: pending,
      updatedAt: DateTime.now(),
    );
    if (blocks.isEmpty) {
      final note = droppedConflicts.isEmpty
          ? ''
          : '（対象が違うため再提案しません）\n${droppedConflicts.map((path) => '- $path').join('\n')}';
      if (!emit.isDone) {
        emit(
          state.copyWith(
            pendingPatches: pending,
            thread: thread,
            agentStatusMessage: droppedConflicts.isEmpty
                ? state.agentStatusMessage
                : '対象が違うため再提案しません',
            generationTrace: note.isEmpty
                ? state.generationTrace
                : _appendGenerationTrace(state.generationTrace, note),
            clearError: true,
          ),
        );
      }
      await _maybeContinueFlutterVerify(emit);
      return;
    }
    emit(
      state.copyWith(
        pendingPatches: pending,
        thread: thread,
        agentStatusMessage: '現状を正として再提案中…',
        clearError: true,
      ),
    );

    final prompt = StringBuffer();
    final addExistsOnly =
        anyAddExists &&
        !anyReviseExisting &&
        !anyChooseNewPath &&
        !anyEmptyTarget;
    final currentLine = state.localLlm.codingAutoApplyPatches
        ? '古い内容の推測禁止。下記現状の行をそのまま - に使う。read_file は出さない。'
        : '古い内容の推測禁止。read_file または下記現状の行をそのまま - に使う。';
    if (anyReviseExisting && !anyChooseNewPath && !anyAddExists) {
      prompt
        ..writeln('作成先にファイルが既にあります。上書きせず、現状を正として既存ファイルの修正案にしてください。')
        ..writeln(currentLine);
    } else if (anyChooseNewPath && !anyReviseExisting && !anyAddExists) {
      prompt
        ..writeln('作成先にファイルが既にあります。上書きせず、別の新規パスでファイル作成案を出し直してください。')
        ..writeln('既存パスの上書きと Update File は禁止。');
    } else if (addExistsOnly) {
      prompt.writeln(codingAddFileExistsAutoReproposeLead);
    } else {
      prompt
        ..writeln('適用に失敗した変更があります。ディスク／エディタの現状を正として修正案を出し直してください。')
        ..writeln(currentLine);
    }
    if (anyAddExists && !addExistsOnly) {
      prompt.writeln('既に存在するパスへの Add File は不可。各対象の指示が指定した1種類だけを出す。');
    }
    if (anyEmptyTarget) {
      prompt.writeln('未作成／空ファイルは *** Add File: 相対パス と + 行のみでよい（文脈行や - 行は不要）。');
    }
    final onlyNewPath = anyChooseNewPath && !anyReviseExisting && !anyAddExists;
    final prescribedAddOnly =
        anyPrescribedAdd &&
        !anyPrescribedUpdate &&
        !anyReviseExisting &&
        !anyChooseNewPath;
    if (!onlyNewPath &&
        !prescribedAddOnly &&
        (!anyEmptyTarget || anyAddExists || anyReviseExisting)) {
      if (anyPrescribedAdd && anyPrescribedUpdate) {
        prompt.writeln('Update の対象は -/+。Add の対象は + のみ。対象を混ぜない。');
      } else {
        prompt.writeln('既存ファイルの修正は現状に一致する - 行で消し、+ 行で入れること（+ のみ追記は禁止）。');
      }
    }
    prompt
      ..writeln()
      ..writeAll(blocks, '\n\n');

    await _runAgentTurn(
      emit,
      userText: prompt.toString(),
      clearDraft: false,
      honorEditLastUser: false,
      pendingOverride: pending,
    );
  }

  Future<String> _loadCurrentFileText(String relativePath) async {
    final root = state.workspaceRoot;
    if (root == null) return '';
    final rel = relativePath.replaceAll('\\', '/');
    final open = state.openTabs
        .where((t) => t.relativePath.replaceAll('\\', '/') == rel)
        .firstOrNull;
    if (open != null) return open.content;
    final file = File(p.join(root, rel));
    if (await file.exists()) {
      try {
        return await file.readAsString();
      } catch (_) {}
    }
    return '';
  }

  /// 空でないファイルがディスクまたは開いているタブにあるか。
  bool _workspaceFileOccupied(String relativePath) {
    final rel = relativePath.replaceAll('\\', '/');
    final open = state.openTabs
        .where((t) => t.relativePath.replaceAll('\\', '/') == rel)
        .firstOrNull;
    if (open != null) return open.content.trim().isNotEmpty;
    final root = state.workspaceRoot;
    if (root == null) return false;
    final file = File(p.join(root, rel));
    if (!file.existsSync()) return false;
    try {
      return file.lengthSync() > 0;
    } catch (_) {
      return false;
    }
  }

  /// ファイルが無いときは null。空ファイルは空文字。
  Future<String?> _loadExistingFileText(String relativePath) async {
    final rel = relativePath.replaceAll('\\', '/');
    final open = state.openTabs
        .where((t) => t.relativePath.replaceAll('\\', '/') == rel)
        .firstOrNull;
    if (open != null) return open.content;
    final root = state.workspaceRoot;
    if (root == null) return null;
    final file = File(p.join(root, rel));
    if (!await file.exists()) return null;
    try {
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  /// 検証ログのパスを最大5件、未開封を優先して読む。
  Future<List<({String path, String body})>> _preloadVerifyFixBodies(
    String log,
  ) async {
    final ordered = codingVerifyPreloadPaths(
      logPaths: codingVerifyLogPaths(log),
      opened: _verifyOpenedPaths,
      unopened: _verifyUnopenedPaths,
    );
    final out = <({String path, String body})>[];
    for (final path in ordered) {
      if (out.length >= codingReadFilesPerBatch) break;
      final body = await _loadExistingFileText(path);
      if (body == null) {
        _verifyUnopenedPaths.add(path);
        continue;
      }
      _verifyOpenedPaths.add(path);
      out.add((path: path, body: body));
    }
    return out;
  }

  String _buildReproposeBlock({
    required String relativePath,
    required String currentContent,
    required String failedDiff,
    required _CodingReproposeKind kind,
    CodingAddConflictPlan? plan,
  }) {
    final maxChars = state.harness.reproposeMaxChars;
    final body = currentContent.length > maxChars
        ? '${currentContent.substring(0, maxChars)}\n…（省略）'
        : currentContent;
    final emptyHint = body.trim().isEmpty
        ? (relativePath.contains('/')
              ? '（ファイルが空、または未作成。*** Add File: $relativePath で新規作成可）'
              : '（未作成。ファイル名だけなので、ディレクトリ付きの別パスで *** Add File すること）')
        : body;
    final guidance = plan != null
        ? plan.instruction
        : switch (kind) {
            _CodingReproposeKind.addExists =>
              'このパスだけを *** Update File: $relativePath で直す。'
                  'Add File は出さない。別パスは出さない。説明だけで終わらない。',
            _CodingReproposeKind.addReviseExisting =>
              'このパスは既に存在します。新規作成も別パスへの退避もしない。'
                  '【現状】を正として、提案の意図を *** Update File: $relativePath の -/+ で既存ファイルへ反映する。'
                  'Add File は出さない。関数単位。既存関数は 置換範囲、新しい関数は 挿入行。',
            _CodingReproposeKind.addChooseNewPath =>
              'このパスは既に存在するため上書きしない。Update File にもしない。'
                  '同じ内容を、衝突しない別のディレクトリ付き相対パスの *** Add File で出し直す。'
                  'Patch 直前に 配置先: を書き、Add File 行と一致させる。',
            _CodingReproposeKind.addOrEmpty => _reproposeAddPathGuidance(
              relativePath,
            ),
            _CodingReproposeKind.generic =>
              body.trim().isEmpty
                  ? _reproposeAddPathGuidance(relativePath)
                  : '既存ファイルなので -（削除）と +（追加）のペア必須。+ だけのパッチは不可。'
                        '既存関数の修正は Patch 直前に 置換範囲: 開始-終了（この現状の行番号。両端含む）を付ける。',
          };
    final avoid = plan != null && plan.avoidPath.isNotEmpty
        ? '触らないパス: ${plan.avoidPath}\n'
        : '';
    return '''
対象ファイル: $relativePath

【現状（これを正とする）】
```
$emptyHint
```

【適用できなかった提案】
```
$failedDiff
```

上記現状に合わせて同じ変更意図の Begin/End Patch だけを出し直すこと。
$avoid$guidance
''';
  }

  Future<void> _refreshSymbolMap() async {
    final index = symbolIndex;
    final root = state.workspaceRoot;
    if (index == null || !index.isReady || root == null || root.isEmpty) {
      _symbolMap = '';
      return;
    }
    final files = <({String relativePath, String content})>[];
    final seen = <String>{};
    void add(String rel, String content) {
      final key = rel.replaceAll('\\', '/');
      if (!seen.add(key)) return;
      final lower = key.toLowerCase();
      if (!lower.endsWith('.dart') && !lower.endsWith('.swift')) return;
      files.add((relativePath: key, content: content));
    }

    for (final file in state.attachedOpenFiles) {
      add(file.relativePath, file.content);
    }
    final active = state.activeTabPath;
    if (active != null) {
      for (final tab in state.openTabs) {
        if (tab.relativePath == active) {
          add(tab.relativePath, tab.content);
          break;
        }
      }
    }
    for (final tab in state.openTabs) {
      add(tab.relativePath, tab.content);
    }
    try {
      _symbolMap = await index
          .signatureMap(files)
          .timeout(const Duration(seconds: 8), onTimeout: () => '');
    } catch (_) {
      _symbolMap = '';
    }
  }

  Future<void> _runAgentTurn(
    Emitter<CodingAssistState> emit, {
    required String userText,
    required bool clearDraft,
    required bool honorEditLastUser,
    List<CodingProposedPatch>? pendingOverride,
    List<CodingPromptAction> fixedPrompts = const [],
    String requestText = '',
    bool recordComposerAttachments = false,
    List<CodingHistoryChip>? historyChips,
    List<({String path, String body})> preloadReads = const [],
  }) async {
    final root = state.workspaceRoot;
    final thread = state.thread;
    if (userText.trim().isEmpty || root == null || thread == null) return;
    if (!state.localLlm.isCodingUsable) {
      emit(state.copyWith(errorMessage: 'コーディング用 LLM が利用できません'));
      return;
    }
    if (state.isGenerating) return;

    await _refreshSymbolMap();

    if (_autoSleepDeadlineReached) return;
    _cancelRequested = false;
    _autoSuppliedNamedPaths = false;

    final trackAutoSleep = _autoCycleDepth == 0;
    _autoCycleDepth++;
    final previousPreload = _turnPreloadReads;
    _turnPreloadReads = preloadReads;
    var autoSleepLatched = false;
    try {
      var baseMessages = thread.messages;
      var pending = List<CodingProposedPatch>.from(
        pendingOverride ?? state.pendingPatches,
      );
      var workingThread = thread;
      if (honorEditLastUser && state.isEditingLastUser) {
        final cut = state.lastUserMessageIndex;
        if (cut != null) {
          baseMessages = baseMessages.sublist(0, cut);
          pending = const [];
          if (cut < thread.compactedUpToExclusive) {
            workingThread = thread.copyWith(clearCompacted: true);
          }
        }
      }

      final cycleRequest = requestText.trim();
      final chips =
          historyChips ??
          (recordComposerAttachments
              ? _historyChipsFromState()
              : const <CodingHistoryChip>[]);
      final userMsg = CodingChatMessage(
        role: CodingMessageRole.user,
        content: userText,
        at: DateTime.now(),
        fixedPrompts: fixedPrompts,
        requestText: cycleRequest.isEmpty ? null : cycleRequest,
        historyChips: chips,
      );
      var messages = [...baseMessages, userMsg];
      var title = thread.title;
      if (CodingThread.isPlaceholderTitle(title)) {
        final fileCount = chips
            .where((chip) => chip.kind == CodingHistoryChipKind.file)
            .length;
        final source = cycleRequest.isNotEmpty
            ? cycleRequest
            : (fileCount > 0 ? 'ファイル $fileCount 件' : userText);
        title = source.length > 40 ? '${source.substring(0, 40)}…' : source;
      }
      var current = workingThread.copyWith(
        title: title,
        messages: messages,
        pendingPatches: pending,
        updatedAt: DateTime.now(),
      );
      final summaryBefore = workingThread.compactedSummary;

      // §5.7: 送信前に見積。自動実行 OFF は 85% でテンプレ圧縮。
      // 自動実行 ON は各 API 送信で作業記憶へ組み直す（§5.7.6）。85% は待たない。
      final autoExecute = state.localLlm.codingAutoApplyPatches;
      var used = _estimateUsedTokens(
        messages: messages,
        draft: '',
        thread: current,
        clearAttached: clearDraft,
        clearAttachedOpenFiles: clearDraft,
        clearAttachedFolderStructures: clearDraft,
      );
      if (!autoExecute &&
          CodingContextEstimator.shouldAutoCompact(
            usedTokens: used,
            contextSize: state.contextSize,
            autoCompactRatio: state.harness.autoCompactRatio,
          )) {
        final compacted = _compactThread(current);
        if (compacted != null) {
          current = compacted;
          used = _estimateUsedTokens(
            messages: messages,
            draft: '',
            thread: current,
            clearAttached: clearDraft,
            clearAttachedOpenFiles: clearDraft,
            clearAttachedFolderStructures: clearDraft,
          );
        }
      }
      var warn = _warningFor(used);
      if (current.compactedSummary != null &&
          warn != CodingContextWarningLevel.block) {
        warn = CodingContextWarningLevel.compacted;
      }
      current = current.copyWith(contextWarningLevel: warn);

      if (warn == CodingContextWarningLevel.block) {
        emit(
          state.copyWith(
            thread: current,
            usedTokens: used,
            warningLevel: warn,
            errorMessage: 'コンテキスト上限のため送信できません。「圧縮」を試すか、新規会話を始めてください。',
          ),
        );
        return;
      }

      if (trackAutoSleep) {
        autoSleepLatched = _beginAutoSleepCycle(emit);
      }

      emit(
        state.copyWith(
          thread: current,
          draft: clearDraft ? '' : state.draft,
          bumpDraftEpoch: clearDraft,
          clearAppliedPromptActions: clearDraft,
          isGenerating: true,
          isEditingLastUser: false,
          streamingText: '',
          clearGenerationTrace: true,
          pendingPatches: pending,
          clearError: true,
          clearAttachedSelection: clearDraft,
          clearAttachedOpenFiles: clearDraft,
          clearAttachedFolderStructures: clearDraft,
          isHistoryOpen: false,
          usedTokens: used,
          warningLevel: warn,
          agentStatusMessage:
              current.compactedSummary != null &&
                  summaryBefore != current.compactedSummary
              ? 'コンテキストを圧縮して生成中…'
              : (autoExecute && messages.length > 1)
              ? 'コンテキストを圧縮して生成中…'
              : '生成中…',
        ),
      );

      final index = state.index;
      final openBuffers = <String, String>{
        for (final tab in state.openTabs) tab.relativePath: tab.content,
      };
      final tools = CodingAgentTools(
        root,
        indexedFiles: index?.relativeFiles ?? const [],
        indexedDirectories: index?.relativeDirectories ?? const [],
        rootLabel: index?.rootLabel,
        openBuffers: openBuffers,
        symbols: symbolIndex,
        readCharLimit: state.harness.maxReadChars,
        grepHitLimit: state.harness.maxGrepHits,
        listEntryLimit: state.harness.maxListEntries,
        pathCandidateLimit: state.harness.maxPathCandidates,
        readFailureLimit: state.harness.maxReadFailuresPerPath,
      );
      tools.noteSuppliedPaths(
        _composerFileBodies(userMsg.content).map((file) => file.path),
      );
      for (final read in _turnPreloadReads) {
        tools.noteSuccessfulRead(read.path);
      }
      final system = _systemPromptFor(root);
      final codingSettings = state.localLlm.forServer();
      var lastStreamEmit = DateTime.fromMillisecondsSinceEpoch(0);
      // tool 実行後は必ず後続の LLM 応答が必要（無いのに完了にしない）
      var needsFollowUpAfterTools = false;
      var repeatReadStreak = 0;
      var unclosedPatchRetried = false;
      // 思考 ON 時は長考しやすいので、短い思考指示を system に足す
      final guide = state.harness.thinkingGuideChars;
      final baseSystem = codingSettings.thinkingEnabled
          ? '$system\n\n'
                '【思考モード時・厳守】思考は短く（目安$guide字以内）。'
                'プロンプト規則の逐条照合・方針の長文検討は禁止。'
                'すぐ ```tool か *** Begin Patch を出す。終わらない長考は失敗とみなす。'
          : system;
      final streamSystem = autoExecute
          ? '$baseSystem\n\n$codingAutoExecuteNoReadFileSuffix'
          : baseSystem;

      try {
        final maxSteps = autoExecute
            ? max(state.harness.maxAgentSteps, state.harness.maxAgentStepsAuto)
            : state.harness.maxAgentSteps;
        for (var step = 0; step < maxSteps; step++) {
          if (_cancelRequested) break;

          if (needsFollowUpAfterTools && !emit.isDone) {
            emit(state.copyWith(agentStatusMessage: 'ツール結果を踏まえて再生成中…'));
          }

          used = _estimateUsedTokens(
            messages: messages,
            draft: '',
            thread: current,
          );
          if (!autoExecute &&
              CodingContextEstimator.shouldAutoCompact(
                usedTokens: used,
                contextSize: state.contextSize,
                autoCompactRatio: state.harness.autoCompactRatio,
              )) {
            final compacted = _compactThread(
              current.copyWith(messages: messages),
            );
            if (compacted != null) {
              current = compacted;
              messages = current.messages;
              used = _estimateUsedTokens(
                messages: messages,
                draft: '',
                thread: current,
              );
              if (!emit.isDone) {
                emit(
                  state.copyWith(
                    thread: current,
                    usedTokens: used,
                    warningLevel: CodingContextWarningLevel.compacted,
                    agentStatusMessage: 'コンテキストを圧縮しました',
                  ),
                );
              }
            }
          }
          warn = _warningFor(used);
          if (warn == CodingContextWarningLevel.block) {
            if (!emit.isDone) {
              emit(
                state.copyWith(
                  thread: current.copyWith(
                    messages: messages,
                    contextWarningLevel: warn,
                  ),
                  usedTokens: used,
                  warningLevel: warn,
                  isGenerating: false,
                  streamingText: '',
                  agentStatusMessage: 'コンテキスト上限のため停止しました',
                  errorMessage: 'コンテキスト上限のため続行できません。新規会話を始めてください。',
                ),
              );
            }
            return;
          }

          final apiMessages = _withPreloadReads(
            CodingApiContextBuilder.buildApiMessages(
              _messagesWithFreshWrites(messages),
              compactedSummary: current.compactedSummary,
              compactedUpToExclusive: current.compactedUpToExclusive,
              symbolTools: symbolIndex?.isReady == true,
              autoExecute: autoExecute,
              pendingPatchPaths: _pendingPatchPaths(current),
              harness: state.harness,
            ),
          );

          _repeatAbort = false;
          var reply = await _localLlmClient.chatMessagesStream(
            settings: codingSettings,
            messages: apiMessages,
            temperature: state.harness.temperature,
            maxTokens: state.harness.maxTokens > 0
                ? state.harness.maxTokens
                : null,
            requestTimeout: Duration(
              minutes: state.harness.requestTimeoutMinutes,
            ),
            maxReasoningChars: state.harness.reasoningAbortChars,
            systemPrompt: streamSystem,
            isCancelled: _generationCancelled,
            onProgress: (progress) {
              _noteGenerationRepeat(progress);
              if (_repeatAbort) return;
              if (progress.partialText.isNotEmpty &&
                  progress.phase == AiGenerationPhase.generating) {
                final now = DateTime.now();
                if (now.difference(lastStreamEmit) <
                    const Duration(milliseconds: 50)) {
                  return;
                }
                lastStreamEmit = now;
                if (!emit.isDone) {
                  emit(state.copyWith(streamingText: progress.partialText));
                }
              }
            },
          );

          if (_cancelRequested) {
            _repeatAbort = false;
            final partial = reply.trim();
            if (partial.isNotEmpty || needsFollowUpAfterTools) {
              final note = partial.isEmpty ? '（再生成が停止されました・応答なし）' : partial;
              if (!emit.isDone) {
                emit(
                  state.copyWith(
                    generationTrace: _appendGenerationTrace(
                      state.generationTrace,
                      note,
                    ),
                    streamingText: '',
                  ),
                );
              }
            }
            break;
          }
          if (_repeatAbort) {
            _repeatAbort = false;
            reply = codingGenerationRepeatDiscarded;
            if (!emit.isDone) {
              emit(
                state.copyWith(
                  streamingText: '',
                  agentStatusMessage: '同じ段落が続いたため切りました',
                ),
              );
            }
          }

          if (reply.trim().isEmpty) {
            throw StateError(
              needsFollowUpAfterTools
                  ? 'ツール実行後の再生成が空応答でした'
                  : 'llama-server から空の応答が返りました',
            );
          }

          // 後続応答を受け取った
          needsFollowUpAfterTools = false;

          final parsed = CodingFenceParser.parse(reply);
          final assistantMsg = CodingChatMessage(
            role: CodingMessageRole.assistant,
            content: parsed.displayText.trim().isEmpty
                ? (parsed.toolCalls.isNotEmpty ? 'ツールを実行します…' : '（応答本文なし）')
                : parsed.displayText,
            at: DateTime.now(),
            // 次ステップの API には tool フェンス付きの生応答を渡す
            llmContent: reply,
          );
          messages = [...messages, assistantMsg];
          if (parsed.patches.isNotEmpty) {
            // 調査ツールの前後で同じ Add File を繰り返してもカードは1枚。
            pending = CodingFenceParser.mergePatches(pending, parsed.patches);
            pending = await _markExistingAddFiles(pending);
          }

          // 適用済みカードは残す（却下済みのみ除外）
          final visiblePatches = pending
              .where((p) => p.status != CodingPatchStatus.rejected)
              .toList();
          current = current.copyWith(
            messages: messages,
            pendingPatches: visiblePatches,
            updatedAt: DateTime.now(),
          );
          final stepTrace = _appendGenerationTrace(
            state.generationTrace,
            reply,
          );
          emit(
            state.copyWith(
              thread: current,
              pendingPatches: visiblePatches,
              streamingText: '',
              generationTrace: stepTrace,
              agentStatusMessage: parsed.toolCalls.isEmpty
                  ? '応答完了'
                  : 'ツール実行中（${parsed.toolCalls.length}）…',
            ),
          );

          if (await _observeAutoLoopAnswer(
            emit,
            rawReply: reply,
            parsed: parsed,
          )) {
            return;
          }

          if (parsed.toolCalls.isEmpty) {
            if (autoExecute &&
                !unclosedPatchRetried &&
                parsed.patches.isEmpty &&
                codingReplyHasUnclosedPatch(reply) &&
                codingMayRetryUnclosedPatch(userMsg.fixedPrompts) &&
                codingAutoExecuteNamedPaths(
                  toolCalls: const [],
                  replyText: reply,
                ).isEmpty) {
              unclosedPatchRetried = true;
              final retryText = codingUnclosedPatchCloseMessage(
                requestText: userMsg.requestText ?? '',
                fixedPrompts: userMsg.fixedPrompts,
              );
              messages = [
                ...messages,
                CodingChatMessage(
                  role: CodingMessageRole.user,
                  content: retryText,
                  at: DateTime.now(),
                ),
              ];
              current = current.copyWith(
                messages: messages,
                updatedAt: DateTime.now(),
              );
              if (!emit.isDone) {
                emit(
                  state.copyWith(
                    thread: current,
                    generationTrace: _appendGenerationTrace(
                      state.generationTrace,
                      '（End Patch が無いため、カードにせず書き直させます）\n$retryText',
                    ),
                    streamingText: '',
                    agentStatusMessage: 'End Patch が無いため書き直しています',
                  ),
                );
              }
              needsFollowUpAfterTools = true;
              continue;
            }
            if (autoExecute &&
                parsed.patches.isEmpty &&
                codingAutoExecuteNamedPaths(
                  toolCalls: const [],
                  replyText: reply,
                ).isNotEmpty) {
              final supplied = await _supplyNamedPathsInsteadOfReadFile(
                emit,
                tools: tools,
                messages: messages,
                thread: current,
                pending: pending,
                systemPrompt: streamSystem,
                settings: codingSettings,
                symbolToolsReady: symbolIndex?.isReady == true,
                requestText: userMsg.requestText ?? '',
                fixedPrompts: userMsg.fixedPrompts,
                composerContent: userMsg.content,
                replyText: reply,
                readCalls: const <CodingToolCall>[],
              );
              if (supplied == null) return;
              messages = supplied.messages;
              current = supplied.thread;
              pending = supplied.pending;
            }
            break;
          }

          if (autoExecute &&
              parsed.toolCalls.any((call) => call.name == 'read_file')) {
            if (parsed.patches.isNotEmpty) {
              if (!emit.isDone) {
                emit(
                  state.copyWith(
                    generationTrace: _appendGenerationTrace(
                      state.generationTrace,
                      '（自動実行では read_file を開かず、変更案を採用します）',
                    ),
                  ),
                );
              }
              needsFollowUpAfterTools = false;
              break;
            }
            final supplied = await _supplyNamedPathsInsteadOfReadFile(
              emit,
              tools: tools,
              messages: messages,
              thread: current,
              pending: pending,
              systemPrompt: streamSystem,
              settings: codingSettings,
              symbolToolsReady: symbolIndex?.isReady == true,
              requestText: userMsg.requestText ?? '',
              fixedPrompts: userMsg.fixedPrompts,
              composerContent: userMsg.content,
              replyText: reply,
              readCalls: parsed.toolCalls,
            );
            if (supplied == null) return;
            messages = supplied.messages;
            current = supplied.thread;
            pending = supplied.pending;
            needsFollowUpAfterTools = false;
            break;
          }

          final repeatOnly = codingToolCallsAreRepeatReads(
            parsed.toolCalls.map(
              (call) => (name: call.name, path: '${call.args['path'] ?? ''}'),
            ),
            alreadyRead: tools.hasReadPath,
          );
          repeatReadStreak = codingAdvanceRepeatReadStreak(
            repeatReadStreak,
            repeatOnly: repeatOnly,
          );
          if (autoExecute && codingRepeatReadStreakReached(repeatReadStreak)) {
            needsFollowUpAfterTools = true;
            if (!emit.isDone) {
              emit(
                state.copyWith(
                  generationTrace: _appendGenerationTrace(
                    state.generationTrace,
                    '（既読だけの read_file が$codingRepeatReadStreakLimit回続いたため、残りステップを使わず検査に入ります）',
                  ),
                  agentStatusMessage: '既読の読み直しが続いたため検査します',
                ),
              );
            }
            final continued = await _completeReadLimitCheck(
              emit,
              tools: tools,
              messages: messages,
              thread: current,
              pending: pending,
              systemPrompt: streamSystem,
              settings: codingSettings,
              symbolToolsReady: symbolIndex?.isReady == true,
              requestText: userMsg.requestText ?? '',
              fixedPrompts: userMsg.fixedPrompts,
              attachedReads: _composerFileBodies(userMsg.content),
            );
            if (continued == null) return;
            messages = continued.messages;
            current = continued.thread;
            pending = continued.pending;
            if (continued.resumeLoop) {
              repeatReadStreak = 0;
              needsFollowUpAfterTools = true;
              continue;
            }
            needsFollowUpAfterTools = false;
            break;
          }

          messages = await _executeToolBatch(
            emit,
            tools,
            parsed.toolCalls,
            messages,
            fixedPrompts: userMsg.fixedPrompts,
          );
          current = current.copyWith(
            messages: messages,
            updatedAt: DateTime.now(),
          );
          needsFollowUpAfterTools = !_cancelRequested;
          emit(
            state.copyWith(
              thread: current,
              agentStatusMessage: needsFollowUpAfterTools
                  ? 'ツール結果を踏まえて再生成中…'
                  : state.agentStatusMessage,
            ),
          );
        }

        if (needsFollowUpAfterTools && !_cancelRequested && autoExecute) {
          final continued = await _completeReadLimitCheck(
            emit,
            tools: tools,
            messages: messages,
            thread: current,
            pending: pending,
            systemPrompt: streamSystem,
            settings: codingSettings,
            symbolToolsReady: symbolIndex?.isReady == true,
            requestText: userMsg.requestText ?? '',
            fixedPrompts: userMsg.fixedPrompts,
            attachedReads: _composerFileBodies(userMsg.content),
          );
          if (continued == null) return;
          messages = continued.messages;
          current = continued.thread;
          pending = continued.pending;
          if (continued.resumeLoop) {
            final followUp = await _requestAgentReply(
              emit,
              messages: messages,
              thread: current,
              systemPrompt: streamSystem,
              settings: codingSettings,
              symbolToolsReady: symbolIndex?.isReady == true,
              emptyMessage: '未着手の読み取りのあとの応答が空でした',
            );
            if (followUp == null) return;
            final absorbed = await _absorbAgentReply(
              emit,
              reply: followUp,
              messages: messages,
              thread: current,
              pending: pending,
            );
            if (absorbed == null) return;
            messages = absorbed.messages;
            current = absorbed.thread;
            pending = absorbed.pending;
            if (absorbed.toolCalls.isNotEmpty && !emit.isDone) {
              emit(
                state.copyWith(
                  generationTrace: _appendGenerationTrace(
                    state.generationTrace,
                    '（上限のあと読み取りが続いたため、ここで止めました）',
                  ),
                  agentStatusMessage: '読み取りが続いたため止めました',
                ),
              );
            }
          }
          needsFollowUpAfterTools = false;
        } else if (needsFollowUpAfterTools && !_cancelRequested) {
          final trace = _appendGenerationTrace(
            state.generationTrace,
            '（ツール実行後の再生成に到達せず終了しました）',
          );
          emit(
            state.copyWith(
              isGenerating: false,
              streamingText: '',
              generationTrace: trace,
              thread: current,
              agentStatusMessage: '生成中断',
              errorMessage: 'ツール実行後の再生成が行われませんでした。もう一度送信してください。',
            ),
          );
          return;
        }

        if (!_cancelRequested) {
          await _maybeAutoApplyPendingPatches(emit);
          current = state.thread ?? current;
        }

        final finalUsed = _estimateUsedTokens(
          messages: current.messages,
          draft: '',
          thread: current,
        );
        var finalWarn = _warningFor(finalUsed);
        if (current.compactedSummary != null &&
            finalWarn != CodingContextWarningLevel.block) {
          finalWarn = CodingContextWarningLevel.compacted;
        }
        current = current.copyWith(contextWarningLevel: finalWarn);
        await _repository.saveThread(current);
        final summaries = await _repository.listSummaries();
        emit(
          state.copyWith(
            isGenerating: false,
            streamingText: '',
            // generationTrace は次ターン開始まで残し、直前ログとして確認可能にする
            thread: current,
            threadSummaries: summaries,
            usedTokens: finalUsed,
            warningLevel: finalWarn,
            agentStatusMessage: _cancelRequested ? '停止しました' : '完了',
          ),
        );

        // 自動適用失敗分を、現状正で再提案。再提案ターンの末尾で検証する。
        if (!_cancelRequested && _queuedRepropose.isNotEmpty) {
          final queued = List<CodingProposedPatch>.from(_queuedRepropose);
          _queuedRepropose.clear();
          await _startReproposeFromCurrent(emit, queued);
        } else if (!_cancelRequested) {
          await _maybeContinueFlutterVerify(emit);
        }
      } catch (e) {
        // ログは残して原因確認できるようにする（status も完了のままにしない）
        emit(
          state.copyWith(
            isGenerating: false,
            streamingText: '',
            generationTrace: _appendGenerationTrace(
              state.generationTrace,
              '（エラー: $e）',
            ),
            agentStatusMessage: '生成失敗',
            errorMessage: '生成失敗: $e',
          ),
        );
      }
    } finally {
      _turnPreloadReads = previousPreload;
      _repeatAbort = false;
      _autoCycleDepth--;
      if (trackAutoSleep && autoSleepLatched) {
        await _finishAutoSleepCycle(emit);
      }
    }
  }

  void _rememberWrittenPath(String relativePath) {
    final rel = relativePath.trim().replaceAll('\\', '/');
    if (rel.isEmpty) return;
    _writtenPathsThisCycle.add(rel);
  }

  /// この周期で書いたパスの当初添付を、タブかディスクの現状に置き換える。
  /// 永続メッセージは変えない。
  List<CodingChatMessage> _messagesWithFreshWrites(
    List<CodingChatMessage> messages,
  ) {
    if (_writtenPathsThisCycle.isEmpty) return messages;
    final fresh = <String, String>{};
    for (final path in _writtenPathsThisCycle) {
      final body = _bodyOfWrittenFile(path);
      if (body != null) fresh[path] = body;
    }
    if (fresh.isEmpty) return messages;
    return [
      for (final message in messages)
        if (message.role == CodingMessageRole.user &&
            message.content.contains('【開いているファイル:'))
          CodingChatMessage(
            role: message.role,
            content: CodingApiContextBuilder.replaceAttachedFileBodies(
              message.content,
              fresh,
            ),
            at: message.at,
            toolName: message.toolName,
            llmContent: message.llmContent,
            fixedPrompts: message.fixedPrompts,
            requestText: message.requestText,
            historyChips: message.historyChips,
          )
        else
          message,
    ];
  }

  String? _bodyOfWrittenFile(String relativePath) {
    final rel = relativePath.replaceAll('\\', '/');
    for (final tab in state.openTabs) {
      if (tab.relativePath.replaceAll('\\', '/') == rel) return tab.content;
    }
    final root = state.workspaceRoot;
    if (root == null) return null;
    final file = File(p.join(root, rel));
    if (!file.existsSync()) return null;
    try {
      return file.readAsStringSync();
    } catch (_) {
      return null;
    }
  }

  List<({String path, String body})> _composerFileBodies(String content) {
    return [
      for (final file in codingRestoreComposerAttachments(content).files)
        (path: file.relativePath.replaceAll('\\', '/'), body: file.content),
    ];
  }

  /// 自動実行で `read_file` は実行しない。名前のあったパスをアプリが1回だけ開き、
  /// 本文はチャットに出さず次の検査 API に載せる。
  Future<
    ({
      List<CodingChatMessage> messages,
      CodingThread thread,
      List<CodingProposedPatch> pending,
    })?
  >
  _supplyNamedPathsInsteadOfReadFile(
    Emitter<CodingAssistState> emit, {
    required CodingAgentTools tools,
    required List<CodingChatMessage> messages,
    required CodingThread thread,
    required List<CodingProposedPatch> pending,
    required String systemPrompt,
    required LocalLlmConnectionSettings settings,
    required bool symbolToolsReady,
    required String requestText,
    required List<CodingPromptAction> fixedPrompts,
    required String composerContent,
    required String replyText,
    required List<CodingToolCall> readCalls,
  }) async {
    final refused = [
      for (final call in readCalls)
        if (call.name == 'read_file')
          CodingChatMessage(
            role: CodingMessageRole.tool,
            content: codingAutoExecuteReadFileRefused(
              '${call.args['path'] ?? ''}',
            ),
            at: DateTime.now(),
            toolName: call.name,
          ),
    ];
    messages = [...messages, ...refused];
    if (_autoSuppliedNamedPaths) {
      thread = thread.copyWith(messages: messages, updatedAt: DateTime.now());
      if (!emit.isDone) {
        emit(
          state.copyWith(
            thread: thread,
            generationTrace: _appendGenerationTrace(
              state.generationTrace,
              '（自動実行では read_file を開かないため、ここで止めました）',
            ),
            agentStatusMessage: 'read_file は開かずに止めました',
          ),
        );
      }
      return (messages: messages, thread: thread, pending: pending);
    }
    _autoSuppliedNamedPaths = true;

    final named = codingAutoExecuteNamedPaths(
      toolCalls: [
        for (final call in readCalls)
          (name: call.name, path: '${call.args['path'] ?? ''}'),
      ],
      replyText: replyText,
    );
    final attached = {
      for (final file in _composerFileBodies(composerContent)) file.path,
    };
    final fresh = codingFreshShortagePaths(
      named: named,
      opened: _verifyOpenedPaths,
      unopened: _verifyUnopenedPaths,
    );
    final opened = <({String path, String body})>[];
    final skipped = <String>[];
    for (final raw in fresh) {
      if (opened.length >= codingReadFilesPerBatch) {
        skipped.add(raw);
        continue;
      }
      final soft =
          CodingPathResolver.softMatchFile(
            raw,
            state.index?.relativeFiles ?? const [],
          ) ??
          raw;
      final path = soft.replaceAll('\\', '/');
      if (attached.contains(path) || tools.hasReadPath(path)) {
        skipped.add('$path（添付または既読）');
        _verifyOpenedPaths.add(path);
        continue;
      }
      final body = await tools.readFile(path);
      if (!tools.hasReadPath(path) ||
          body.contains('開いていません') ||
          body.contains('がありません')) {
        skipped.add(path);
        _verifyUnopenedPaths
          ..add(path)
          ..add(raw.replaceAll('\\', '/'));
        continue;
      }
      final note = RegExp(r'^（パス補正: .+ → .+）\n').firstMatch(body);
      _verifyOpenedPaths
        ..add(path)
        ..add(raw.replaceAll('\\', '/'));
      opened.add((
        path: path,
        body: note == null ? body : body.substring(note.end),
      ));
    }

    final note = StringBuffer()..writeln('【アプリ】自動実行では read_file を実行しません。');
    if (opened.isEmpty) {
      note.writeln('新しく開けたファイルはありません。');
    } else {
      note.writeln('次のパスをアプリが開きました。本文はチャットには出さず、次の送信に載せます。');
      for (final file in opened) {
        note.writeln('- ${file.path}');
      }
    }
    if (skipped.isNotEmpty) {
      note.writeln('開かなかったパス:');
      for (final path in skipped) {
        note.writeln('- $path');
      }
    }
    final noteText = note.toString().trimRight();
    messages = [
      ...messages,
      CodingChatMessage(
        role: CodingMessageRole.user,
        content: noteText,
        at: DateTime.now(),
      ),
    ];
    thread = thread.copyWith(messages: messages, updatedAt: DateTime.now());
    if (!emit.isDone) {
      emit(
        state.copyWith(
          thread: thread,
          pendingPatches: pending,
          generationTrace: _appendGenerationTrace(
            state.generationTrace,
            noteText,
          ),
          streamingText: '',
          agentStatusMessage: opened.isEmpty
              ? 'read_file は開かず、添付の本文で続けます'
              : '不足パスを ${opened.length} 件開きました',
        ),
      );
    }
    final instruction = codingReadStepLimitRetryMessage(
      requestText: requestText,
      alreadyRead: [
        ...attached,
        for (final file in opened) file.path,
        ...tools.readPathsThisTurn,
      ],
      fixedPrompts: fixedPrompts,
      allowUnreadReads: false,
    );
    final reply = await _requestAgentReply(
      emit,
      messages: messages,
      thread: thread,
      systemPrompt: systemPrompt,
      settings: settings,
      symbolToolsReady: symbolToolsReady,
      emptyMessage: '不足パスを開いたあとの応答が空でした',
      requestText: requestText,
      fixedPrompts: fixedPrompts,
      restoreReadPaths: CodingApiContextBuilder.readPathsToRestore(
        messages,
        requestText: requestText,
        pendingPatchPaths: _pendingPatchPaths(thread),
        readPaths: tools.readPathsThisTurn,
      ),
      deliverableInstruction: instruction,
      deliverableSystemSuffix: codingDeliverableCloseSystemSuffix,
      extraReads: [..._composerFileBodies(composerContent), ...opened],
      forbidReadFile: true,
    );
    if (reply == null) return null;
    var absorbed = await _absorbAgentReply(
      emit,
      reply: reply,
      messages: messages,
      thread: thread,
      pending: pending,
    );
    if (absorbed == null) return null;
    var latestReply = reply;
    var step = absorbed;
    final suppliedPaths = <String>[
      ...attached,
      for (final file in opened) file.path,
      ...tools.readPathsThisTurn,
    ];
    if (codingSuppliedReplyNeedsClose(
      reply: latestReply,
      toolCalls: [
        for (final call in step.toolCalls)
          (name: call.name, path: '${call.args['path'] ?? ''}'),
      ],
      fixedPrompts: fixedPrompts,
    )) {
      final retryText = codingAlreadySuppliedCloseMessage(
        requestText: requestText,
        alreadyRead: suppliedPaths,
        fixedPrompts: fixedPrompts,
      );
      messages = [
        ...step.messages,
        CodingChatMessage(
          role: CodingMessageRole.user,
          content: retryText,
          at: DateTime.now(),
        ),
      ];
      thread = step.thread.copyWith(
        messages: messages,
        updatedAt: DateTime.now(),
      );
      if (!emit.isDone) {
        emit(
          state.copyWith(
            thread: thread,
            generationTrace: _appendGenerationTrace(
              state.generationTrace,
              '（不足: は開かず、完了の形だけを再指示します）\n$retryText',
            ),
            streamingText: '',
            agentStatusMessage: '不足の再要求を捨てて再指示しています',
          ),
        );
      }
      final next = await _requestAgentReply(
        emit,
        messages: messages,
        thread: thread,
        systemPrompt: systemPrompt,
        settings: settings,
        symbolToolsReady: symbolToolsReady,
        emptyMessage: '不足を破棄したあとの応答が空でした',
        requestText: requestText,
        fixedPrompts: fixedPrompts,
        restoreReadPaths: CodingApiContextBuilder.readPathsToRestore(
          messages,
          requestText: requestText,
          pendingPatchPaths: _pendingPatchPaths(thread),
          readPaths: tools.readPathsThisTurn,
        ),
        deliverableInstruction: retryText,
        deliverableSystemSuffix: codingDeliverableCloseSystemSuffix,
        extraReads: [..._composerFileBodies(composerContent), ...opened],
        forbidReadFile: true,
      );
      if (next == null) return null;
      latestReply = next;
      final closedReply = await _absorbAgentReply(
        emit,
        reply: next,
        messages: messages,
        thread: thread,
        pending: step.pending,
      );
      if (closedReply == null) return null;
      step = closedReply;
      final stillCalls = [
        for (final call in step.toolCalls)
          (name: call.name, path: '${call.args['path'] ?? ''}'),
      ];
      if (codingSuppliedReplyNeedsClose(
            reply: latestReply,
            toolCalls: stillCalls,
            fixedPrompts: fixedPrompts,
          ) &&
          !emit.isDone) {
        final stillReads =
            codingToolCallsRequestWorkspaceReads(stillCalls) ||
            codingReplyStillRequestsReads(latestReply) ||
            codingAutoExecuteNamedPaths(
              toolCalls: stillCalls,
              replyText: latestReply,
            ).isNotEmpty;
        final note = stillReads
            ? '（再指示のあとも読み取りが続いたため、ここで止めました）'
            : step.toolCalls.isNotEmpty
            ? '（再指示のあともツールが続いたため、ここで止めました）'
            : '（再指示のあとも依頼の成果物が無いため、ここで止めました）';
        emit(
          state.copyWith(
            generationTrace: _appendGenerationTrace(
              state.generationTrace,
              note,
            ),
            agentStatusMessage: stillReads || step.toolCalls.isNotEmpty
                ? '読み取りが続いたため止めました'
                : '依頼の成果物が無いため止めました',
          ),
        );
      }
    }
    return (
      messages: step.messages,
      thread: step.thread,
      pending: step.pending,
    );
  }

  /// 既読の読み直しが続いたあと、検査を返す。
  /// 自動実行では `read_file` を開かない。人が添付した本文と、このターンで
  /// アプリが開いた本文だけを検査 API に載せる。中断したときは null。
  /// [resumeLoop] は false。
  Future<
    ({
      List<CodingChatMessage> messages,
      CodingThread thread,
      List<CodingProposedPatch> pending,
      bool resumeLoop,
    })?
  >
  _completeReadLimitCheck(
    Emitter<CodingAssistState> emit, {
    required CodingAgentTools tools,
    required List<CodingChatMessage> messages,
    required CodingThread thread,
    required List<CodingProposedPatch> pending,
    required String systemPrompt,
    required LocalLlmConnectionSettings settings,
    required bool symbolToolsReady,
    required String requestText,
    required List<CodingPromptAction> fixedPrompts,
    List<({String path, String body})> attachedReads = const [],
  }) async {
    final checkText = codingReadStepLimitCheckMessage(
      tools.readPathsThisTurn,
      requestText: requestText,
      fixedPrompts: fixedPrompts,
      forbidReadFile: true,
    );
    messages = [
      ...messages,
      CodingChatMessage(
        role: CodingMessageRole.user,
        content: checkText,
        at: DateTime.now(),
      ),
    ];
    thread = thread.copyWith(messages: messages, updatedAt: DateTime.now());
    if (!emit.isDone) {
      emit(
        state.copyWith(
          thread: thread,
          generationTrace: _appendGenerationTrace(
            state.generationTrace,
            checkText,
          ),
          streamingText: '',
          agentStatusMessage: '読み取りの重複を検査しています',
        ),
      );
    }
    final reply = await _requestAgentReply(
      emit,
      messages: messages,
      thread: thread,
      systemPrompt: systemPrompt,
      settings: settings,
      symbolToolsReady: symbolToolsReady,
      emptyMessage: '読み取り検査のあとの応答が空でした',
      requestText: requestText,
      fixedPrompts: fixedPrompts,
      restoreReadPaths: CodingApiContextBuilder.readPathsToRestore(
        messages,
        requestText: requestText,
        pendingPatchPaths: _pendingPatchPaths(thread),
        readPaths: tools.readPathsThisTurn,
      ),
      deliverableInstruction: checkText,
      deliverableSystemSuffix: codingDeliverableCloseSystemSuffix,
      extraReads: attachedReads,
      forbidReadFile: true,
    );
    if (reply == null) return null;

    var absorbed = await _absorbAgentReply(
      emit,
      reply: reply,
      messages: messages,
      thread: thread,
      pending: pending,
    );
    if (absorbed == null) return null;
    var step = absorbed;
    messages = step.messages;
    thread = step.thread;
    pending = step.pending;

    var latestReply = reply;
    var closed = false;
    while (true) {
      if (codingReplyWasRepeatDiscard(latestReply)) {
        return (
          messages: messages,
          thread: thread,
          pending: pending,
          resumeLoop: false,
        );
      }
      final missesDeliverable = codingReplyMissesFixedPrompt(
        latestReply,
        fixedPrompts,
      );
      if (codingFixedPromptHasCompletionShape(fixedPrompts) &&
          !missesDeliverable) {
        return (
          messages: messages,
          thread: thread,
          pending: pending,
          resumeLoop: false,
        );
      }
      if (!codingFixedPromptHasCompletionShape(fixedPrompts) &&
          step.toolCalls.isEmpty &&
          !codingReplyStillRequestsReads(latestReply)) {
        return (
          messages: messages,
          thread: thread,
          pending: pending,
          resumeLoop: false,
        );
      }
      if (!closed) {
        closed = true;
        final retryText = codingReadStepLimitRetryMessage(
          requestText: requestText,
          alreadyRead: tools.readPathsThisTurn,
          fixedPrompts: fixedPrompts,
          allowUnreadReads: false,
        );
        messages = [
          ...messages,
          CodingChatMessage(
            role: CodingMessageRole.user,
            content: retryText,
            at: DateTime.now(),
          ),
        ];
        thread = thread.copyWith(messages: messages, updatedAt: DateTime.now());
        if (!emit.isDone) {
          emit(
            state.copyWith(
              thread: thread,
              generationTrace: _appendGenerationTrace(
                state.generationTrace,
                '（読み取りを続けず、完了の形だけを再指示します）\n$retryText',
              ),
              streamingText: '',
              agentStatusMessage: '読み取りなしで再指示しています',
            ),
          );
        }
        final next = await _requestDeliverableReadCheck(
          emit,
          messages: messages,
          thread: thread,
          systemPrompt: systemPrompt,
          settings: settings,
          symbolToolsReady: symbolToolsReady,
          requestText: requestText,
          fixedPrompts: fixedPrompts,
          tools: tools,
          instruction: retryText,
          allowUnreadReads: false,
          emptyMessage: '読み取り検査の再指示のあと、応答が空でした',
          extraReads: attachedReads,
        );
        if (next == null) return null;
        latestReply = next;
        final closedReply = await _absorbAgentReply(
          emit,
          reply: next,
          messages: messages,
          thread: thread,
          pending: pending,
        );
        if (closedReply == null) return null;
        step = closedReply;
        messages = step.messages;
        thread = step.thread;
        pending = step.pending;
        continue;
      }

      final callNames = step.toolCalls
          .map((call) => (name: call.name, path: '${call.args['path'] ?? ''}'))
          .toList();
      final stillReads =
          codingToolCallsAreRepeatReads(
            callNames,
            alreadyRead: tools.hasReadPath,
          ) ||
          codingToolCallsRequestWorkspaceReads(callNames) ||
          codingReplyStillRequestsReads(latestReply);
      if ((step.toolCalls.isNotEmpty || stillReads || missesDeliverable) &&
          !emit.isDone) {
        final note = stillReads
            ? '（再指示のあとも読み取りが続いたため、ここで止めました）'
            : step.toolCalls.isNotEmpty
            ? '（再指示のあともツールが続いたため、ここで止めました）'
            : '（再指示のあとも依頼の成果物が無いため、ここで止めました）';
        emit(
          state.copyWith(
            generationTrace: _appendGenerationTrace(
              state.generationTrace,
              note,
            ),
            agentStatusMessage: stillReads || step.toolCalls.isNotEmpty
                ? '読み取りが続いたため止めました'
                : '依頼の成果物が無いため止めました',
          ),
        );
      }
      return (
        messages: messages,
        thread: thread,
        pending: pending,
        resumeLoop: false,
      );
    }
  }

  Future<String?> _requestDeliverableReadCheck(
    Emitter<CodingAssistState> emit, {
    required List<CodingChatMessage> messages,
    required CodingThread thread,
    required String systemPrompt,
    required LocalLlmConnectionSettings settings,
    required bool symbolToolsReady,
    required String requestText,
    required List<CodingPromptAction> fixedPrompts,
    required CodingAgentTools tools,
    required String instruction,
    required bool allowUnreadReads,
    required String emptyMessage,
    List<({String path, String body})> extraReads = const [],
  }) {
    return _requestAgentReply(
      emit,
      messages: messages,
      thread: thread,
      systemPrompt: systemPrompt,
      settings: settings,
      symbolToolsReady: symbolToolsReady,
      emptyMessage: emptyMessage,
      requestText: requestText,
      fixedPrompts: fixedPrompts,
      restoreReadPaths: CodingApiContextBuilder.readPathsToRestore(
        messages,
        requestText: requestText,
        pendingPatchPaths: _pendingPatchPaths(thread),
        readPaths: tools.readPathsThisTurn,
      ),
      deliverableInstruction: instruction,
      deliverableSystemSuffix: allowUnreadReads
          ? codingDeliverableSystemSuffix
          : codingDeliverableCloseSystemSuffix,
      extraReads: extraReads,
      forbidReadFile: !allowUnreadReads,
    );
  }

  Future<String?> _requestAgentReply(
    Emitter<CodingAssistState> emit, {
    required List<CodingChatMessage> messages,
    required CodingThread thread,
    required String systemPrompt,
    required LocalLlmConnectionSettings settings,
    required bool symbolToolsReady,
    required String emptyMessage,
    String requestText = '',
    String? deliverableInstruction,
    String deliverableSystemSuffix = codingDeliverableSystemSuffix,
    List<CodingPromptAction> fixedPrompts = const [],
    Set<String> restoreReadPaths = const {},
    List<({String path, String body})> extraReads = const [],
    bool forbidReadFile = false,
  }) async {
    final restored = deliverableInstruction == null
        ? const <({String path, String body})>[]
        : CodingApiContextBuilder.restoredReadBodies(
            messages,
            restoreReadPaths,
          );
    final seenReads = <String>{};
    final deliverableReads = <({String path, String body})>[];
    void addRead(({String path, String body}) read) {
      final path = read.path.replaceAll('\\', '/');
      if (path.isEmpty || !seenReads.add(path)) return;
      deliverableReads.add((path: path, body: read.body));
    }

    for (final read in extraReads) {
      addRead(read);
    }
    for (final read in _turnPreloadReads) {
      addRead(read);
    }
    for (final read in restored) {
      addRead(read);
    }
    final promptRules = deliverableInstruction == null
        ? ''
        : codingAssistFixedPromptRules(
            fixedPrompts,
            omitReadFile: forbidReadFile,
            bodiesSupplied: forbidReadFile && deliverableReads.isNotEmpty,
            kind: state.index?.kind ?? CodingWorkspaceKind.generic,
          );
    final deliverableMessages = deliverableInstruction == null
        ? null
        : CodingApiContextBuilder.buildDeliverableMessages(
            requestText: requestText,
            reads: deliverableReads,
            instruction: deliverableInstruction,
            promptRules: promptRules,
            forbidReadFile: forbidReadFile,
          );
    final systemForCall = deliverableInstruction == null
        ? systemPrompt
        : '$systemPrompt\n\n$deliverableSystemSuffix';
    final used = deliverableMessages == null
        ? _estimateUsedTokens(
            messages: messages,
            draft: '',
            thread: thread,
            restoreReadPaths: restoreReadPaths,
          )
        : _estimateDeliverableTokens(deliverableMessages, systemForCall);
    if (deliverableMessages != null && !emit.isDone) {
      final listed = deliverableReads.map((read) => read.path).join('、');
      final notes = StringBuffer(
        listed.isEmpty
            ? '（この API はツール往復を省きます。送る既読の本文はありません）'
            : '（この API はツール往復を省きます。送る既読: $listed）',
      );
      if (promptRules.isNotEmpty) {
        final labels = [
          for (final action in fixedPrompts)
            if (action != CodingPromptAction.attachSelection) action.menuLabel,
        ];
        notes
          ..writeln()
          ..write(
            labels.isEmpty
                ? '（この API に＋の指示を足します）'
                : '（この API に＋の指示を足します: ${labels.join('、')}）',
          );
      }
      emit(
        state.copyWith(
          generationTrace: _appendGenerationTrace(
            state.generationTrace,
            notes.toString(),
          ),
        ),
      );
    }
    if (_warningFor(used) == CodingContextWarningLevel.block) {
      if (!emit.isDone) {
        emit(
          state.copyWith(
            thread: thread.copyWith(
              messages: messages,
              contextWarningLevel: CodingContextWarningLevel.block,
            ),
            usedTokens: used,
            warningLevel: CodingContextWarningLevel.block,
            isGenerating: false,
            streamingText: '',
            agentStatusMessage: 'コンテキスト上限のため停止しました',
            errorMessage: 'コンテキスト上限のため続行できません。新規会話を始めてください。',
          ),
        );
      }
      return null;
    }
    final built =
        deliverableMessages ??
        CodingApiContextBuilder.buildApiMessages(
          _messagesWithFreshWrites(messages),
          compactedSummary: thread.compactedSummary,
          compactedUpToExclusive: thread.compactedUpToExclusive,
          symbolTools: symbolToolsReady,
          autoExecute: true,
          pendingPatchPaths: _pendingPatchPaths(thread),
          harness: state.harness,
          restoreReadPaths: restoreReadPaths,
        );
    final apiMessages = deliverableMessages == null
        ? _withPreloadReads(built)
        : built;
    var lastStreamEmit = DateTime.fromMillisecondsSinceEpoch(0);
    _repeatAbort = false;
    var reply = await _localLlmClient.chatMessagesStream(
      temperature: state.harness.temperature,
      maxTokens: state.harness.maxTokens > 0 ? state.harness.maxTokens : null,
      requestTimeout: Duration(minutes: state.harness.requestTimeoutMinutes),
      maxReasoningChars: state.harness.reasoningAbortChars,
      settings: settings,
      messages: apiMessages,
      systemPrompt: systemForCall,
      isCancelled: _generationCancelled,
      onProgress: (progress) {
        _noteGenerationRepeat(progress);
        if (_repeatAbort) return;
        if (progress.partialText.isEmpty ||
            progress.phase != AiGenerationPhase.generating) {
          return;
        }
        final now = DateTime.now();
        if (now.difference(lastStreamEmit) < const Duration(milliseconds: 50)) {
          return;
        }
        lastStreamEmit = now;
        if (!emit.isDone) {
          emit(state.copyWith(streamingText: progress.partialText));
        }
      },
    );
    if (_cancelRequested) {
      _repeatAbort = false;
      final partial = reply.trim();
      if (!emit.isDone) {
        emit(
          state.copyWith(
            isGenerating: false,
            streamingText: '',
            generationTrace: _appendGenerationTrace(
              state.generationTrace,
              partial.isEmpty ? '（再生成が停止されました・応答なし）' : partial,
            ),
            agentStatusMessage: '停止しました',
          ),
        );
      }
      return null;
    }
    if (_repeatAbort) {
      _repeatAbort = false;
      reply = codingGenerationRepeatDiscarded;
      if (!emit.isDone) {
        emit(
          state.copyWith(
            streamingText: '',
            generationTrace: _appendGenerationTrace(
              state.generationTrace,
              reply,
            ),
            agentStatusMessage: '同じ段落が続いたため切りました',
          ),
        );
      }
    }
    if (reply.trim().isEmpty) {
      throw StateError(emptyMessage);
    }
    return reply;
  }

  Future<
    ({
      List<CodingChatMessage> messages,
      CodingThread thread,
      List<CodingProposedPatch> pending,
      List<CodingToolCall> toolCalls,
    })?
  >
  _absorbAgentReply(
    Emitter<CodingAssistState> emit, {
    required String reply,
    required List<CodingChatMessage> messages,
    required CodingThread thread,
    required List<CodingProposedPatch> pending,
  }) async {
    final parsed = CodingFenceParser.parse(reply);
    final assistantMsg = CodingChatMessage(
      role: CodingMessageRole.assistant,
      content: parsed.displayText.trim().isEmpty
          ? (parsed.toolCalls.isNotEmpty ? 'ツールを実行します…' : '（応答本文なし）')
          : parsed.displayText,
      at: DateTime.now(),
      llmContent: reply,
    );
    messages = [...messages, assistantMsg];
    if (parsed.patches.isNotEmpty) {
      pending = CodingFenceParser.mergePatches(pending, parsed.patches);
      pending = await _markExistingAddFiles(pending);
    }
    final visiblePatches = pending
        .where((p) => p.status != CodingPatchStatus.rejected)
        .toList();
    thread = thread.copyWith(
      messages: messages,
      pendingPatches: visiblePatches,
      updatedAt: DateTime.now(),
    );
    if (!emit.isDone) {
      emit(
        state.copyWith(
          thread: thread,
          pendingPatches: visiblePatches,
          streamingText: '',
          generationTrace: _appendGenerationTrace(state.generationTrace, reply),
          agentStatusMessage: parsed.toolCalls.isEmpty
              ? '応答完了'
              : 'ツール実行中（${parsed.toolCalls.length}）…',
        ),
      );
    }
    if (await _observeAutoLoopAnswer(emit, rawReply: reply, parsed: parsed)) {
      return null;
    }
    return (
      messages: messages,
      thread: thread,
      pending: visiblePatches,
      toolCalls: parsed.toolCalls,
    );
  }

  Future<List<CodingChatMessage>> _executeToolBatch(
    Emitter<CodingAssistState> emit,
    CodingAgentTools tools,
    List<CodingToolCall> calls,
    List<CodingChatMessage> messages, {
    List<CodingPromptAction> fixedPrompts = const [],
  }) async {
    var openedReads = 0;
    var batchHadRead = false;
    final deferredReads = <String>[];
    final suppliedReads = <String>[];
    for (final call in calls) {
      if (_cancelRequested) break;
      if (call.name == 'read_file') {
        batchHadRead = true;
        final pathArg = '${call.args['path'] ?? ''}'.trim();
        final supplied = tools.suppliedKey(pathArg);
        if (supplied != null) suppliedReads.add(supplied);
        final seen = pathArg.isNotEmpty && tools.hasReadPath(pathArg);
        if (!seen && openedReads >= codingReadFilesPerBatch) {
          deferredReads.add(pathArg.isEmpty ? '(path 空)' : pathArg);
          messages = [
            ...messages,
            CodingChatMessage(
              role: CodingMessageRole.tool,
              content: codingReadBatchDeferredMessage(
                pathArg.isEmpty ? '(path 空)' : pathArg,
              ),
              at: DateTime.now(),
              toolName: call.name,
            ),
          ];
          continue;
        }
        if (!seen) openedReads++;
      }
      messages = await _appendExecutedTools(emit, tools, [call], messages);
    }
    if (batchHadRead && !_cancelRequested) {
      messages = [
        ...messages,
        CodingChatMessage(
          role: CodingMessageRole.tool,
          content: codingReadBatchReport(
            [...tools.readPathsThisTurn, ...suppliedReads],
            deferred: deferredReads,
            completion: codingFixedPromptCompletion(fixedPrompts),
          ),
          at: DateTime.now(),
          toolName: 'read_batch',
        ),
      ];
    }
    return messages;
  }

  Future<List<CodingChatMessage>> _appendExecutedTools(
    Emitter<CodingAssistState> emit,
    CodingAgentTools tools,
    List<CodingToolCall> calls,
    List<CodingChatMessage> messages,
  ) async {
    for (final call in calls) {
      if (_cancelRequested) break;
      final toolPath = '${call.args['path'] ?? ''}'.trim();
      final toolQuery =
          '${call.args['symbol'] ?? call.args['query'] ?? call.args['pattern'] ?? ''}'
              .trim();
      final toolLine = toolPath.isEmpty
          ? (toolQuery.isEmpty ? call.name : '${call.name}($toolQuery)')
          : (toolQuery.isEmpty
                ? '${call.name}($toolPath)'
                : '${call.name}($toolPath $toolQuery)');
      if (!emit.isDone) {
        emit(
          state.copyWith(
            generationTrace: _appendGenerationTrace(
              state.generationTrace,
              '【$toolLine】',
            ),
            agentStatusMessage: 'ツール実行中: $toolLine',
          ),
        );
      }
      final result = await tools.execute(call.name, call.args);
      final clipped = _clipToolResult(result);
      final contentForUi = (call.name == 'read_file' && toolPath.isNotEmpty)
          ? '$toolPath\n---\n$clipped'
          : clipped;
      messages = [
        ...messages,
        CodingChatMessage(
          role: CodingMessageRole.tool,
          content: contentForUi,
          at: DateTime.now(),
          toolName: call.name,
        ),
      ];
    }
    return messages;
  }

  static String _appendGenerationTrace(String current, String chunk) {
    final prev = current.trimRight();
    final next = chunk.trimRight();
    if (next.isEmpty) return current;
    if (prev.isEmpty) return next;
    return '$prev\n\n$next';
  }

  /// 設定 ON のとき、応答完了後に pending パッチを順に自動適用する。
  Future<void> _maybeAutoApplyPendingPatches(
    Emitter<CodingAssistState> emit,
  ) async {
    try {
      final settings = await _getConnectionSettings();
      final llm = settings.localLlm;
      emit(state.copyWith(localLlm: llm));
      if (!llm.codingAutoApplyPatches) return;
    } catch (_) {
      if (!state.localLlm.codingAutoApplyPatches) return;
    }

    final packagePatches = [
      for (final p in state.pendingPatches)
        if (p.status == CodingPatchStatus.pending &&
            codingPatchNeedsPackageInstall(
              relativePath: p.relativePath,
              rawDiff: p.rawDiff,
            ))
          p,
    ];
    final freshPackageIds = [
      for (final p in packagePatches)
        if (p.errorMessage != codingPackageInstallHandoffMessage) p.id,
    ];
    if (freshPackageIds.isNotEmpty) {
      _packageInstallNeeded = true;
      await _markPackageInstallCards(emit, freshPackageIds.toSet());
    }
    final packageIds = {for (final p in packagePatches) p.id};
    final updateIds = [
      for (final p in state.pendingPatches)
        if (p.status == CodingPatchStatus.pending &&
            !p.isAddFile &&
            !packageIds.contains(p.id))
          p.id,
    ];
    final addIds = [
      for (final p in state.pendingPatches)
        if (p.status == CodingPatchStatus.pending &&
            p.isAddFile &&
            !packageIds.contains(p.id))
          p.id,
    ];
    if (updateIds.isEmpty && addIds.isEmpty) return;

    emit(state.copyWith(agentStatusMessage: '変更案を自動適用中…'));
    for (final id in updateIds) {
      if (_cancelRequested) break;
      await _applyPatchById(id, emit, auto: true);
    }
    for (final id in addIds) {
      if (_cancelRequested) break;
      await _approveCreateFileById(id, emit, auto: true);
    }
  }

  /// pubspec.yaml のパッケージ行は自動で書かない。カードに理由を残す。
  Future<void> _markPackageInstallCards(
    Emitter<CodingAssistState> emit,
    Set<String> patchIds,
  ) async {
    const msg = codingPackageInstallHandoffMessage;
    final pending = [
      for (final p in state.pendingPatches)
        if (patchIds.contains(p.id)) p.copyWith(errorMessage: msg) else p,
    ];
    final thread = state.thread?.copyWith(
      pendingPatches: pending,
      updatedAt: DateTime.now(),
    );
    if (thread != null) {
      await _repository.saveThread(thread);
    }
    if (!emit.isDone) {
      emit(
        state.copyWith(
          pendingPatches: pending,
          thread: thread,
          agentStatusMessage: 'パッケージ追加は人手で行ってください',
        ),
      );
    }
  }

  /// 再提案が終わったあとの Flutter 自動検証。人の送信でセット数は 0 に戻してある。
  Future<void> _maybeContinueFlutterVerify(
    Emitter<CodingAssistState> emit,
  ) async {
    if (_flutterVerifyReportTurn || _cancelRequested || emit.isDone) return;
    final root = state.workspaceRoot;
    if (root == null) return;

    final gate = CodingFlutterVerifyPolicy.decide(
      _verifyInput(phase: CodingFlutterVerifyPhase.afterTurn),
    );
    switch (gate.action) {
      case CodingFlutterVerifyAction.skip:
      case CodingFlutterVerifyAction.runTest:
      case CodingFlutterVerifyAction.startFix:
      case CodingFlutterVerifyAction.success:
        return;
      case CodingFlutterVerifyAction.stopKeepAuto:
        await _finishFlutterVerify(emit, decision: gate);
        return;
      case CodingFlutterVerifyAction.runAnalyze:
        break;
    }
    await _runFlutterVerifyCommands(emit, root);
  }

  CodingFlutterVerifyInput _verifyInput({
    required CodingFlutterVerifyPhase phase,
    int? exitCode,
    bool timedOut = false,
    bool launchFailed = false,
    String? commandLog,
  }) {
    final pendingAdd = state.pendingPatches.any(
      (p) => p.isAddFile && p.status == CodingPatchStatus.pending,
    );
    return CodingFlutterVerifyInput(
      phase: phase,
      kind: state.index?.kind ?? CodingWorkspaceKind.generic,
      autoApplyEnabled: state.localLlm.codingAutoApplyPatches,
      updatesAppliedThisCycle: _updatesAppliedThisCycle,
      updatesAppliedThisSet: _updatesAppliedThisSet,
      pendingAdd: pendingAdd,
      setsUsed: _verifyFixSetsUsed,
      maxSets: state.harness.maxVerifySets,
      exitCode: exitCode,
      timedOut: timedOut,
      launchFailed: launchFailed,
      verifyRequested: _flutterVerifyRequested,
      packageInstallNeeded:
          _packageInstallNeeded ||
          codingLogNeedsPackageInstall(commandLog ?? ''),
      documentOnly: _documentOnlyTurn,
    );
  }

  Future<void> _runFlutterVerifyCommands(
    Emitter<CodingAssistState> emit,
    String root,
  ) async {
    final String? flutterBin;
    try {
      final settings = await _getConnectionSettings();
      flutterBin = await FlutterSdkResolver.resolveFlutterExecutable(
        settings.dartSdkPath,
      );
    } catch (e) {
      await _finishFlutterVerify(
        emit,
        decision: const CodingFlutterVerifyDecision(
          CodingFlutterVerifyAction.stopKeepAuto,
          CodingFlutterVerifyStopReason.launchFailed,
        ),
        result: CodingFlutterVerifyResult(
          commandLabel: 'flutter',
          launchFailed: true,
          launchError: '$e',
        ),
      );
      return;
    }
    if (flutterBin == null) {
      await _finishFlutterVerify(
        emit,
        decision: const CodingFlutterVerifyDecision(
          CodingFlutterVerifyAction.stopKeepAuto,
          CodingFlutterVerifyStopReason.launchFailed,
        ),
        result: const CodingFlutterVerifyResult(
          commandLabel: 'flutter',
          launchFailed: true,
          launchError: 'flutter が見つかりません',
        ),
      );
      return;
    }

    if (!emit.isDone) {
      emit(
        state.copyWith(
          isGenerating: true,
          agentStatusMessage: '検証中: flutter analyze',
        ),
      );
    }
    final analyze = await _flutterVerify.analyze(
      flutterExecutable: flutterBin,
      workingDirectory: root,
      isCancelled: () => _cancelRequested,
      timeout: Duration(minutes: state.harness.analyzeTimeoutMinutes),
      logMaxChars: state.harness.verifyLogMaxChars,
    );
    if (await _abortVerifyIfCancelled(emit, analyze)) return;
    final afterAnalyze = CodingFlutterVerifyPolicy.decide(
      _verifyInput(
        phase: CodingFlutterVerifyPhase.afterAnalyze,
        exitCode: analyze.exitCode,
        timedOut: analyze.timedOut,
        launchFailed: analyze.launchFailed,
        commandLog: analyze.log,
      ),
    );
    await _handleFlutterCommandDecision(
      emit,
      decision: afterAnalyze,
      result: analyze,
      flutterBin: flutterBin,
      root: root,
    );
  }

  Future<void> _handleFlutterCommandDecision(
    Emitter<CodingAssistState> emit, {
    required CodingFlutterVerifyDecision decision,
    required CodingFlutterVerifyResult result,
    required String flutterBin,
    required String root,
    CodingFlutterVerifyResult? analyzeResult,
  }) async {
    switch (decision.action) {
      case CodingFlutterVerifyAction.runTest:
        if (!emit.isDone) {
          emit(
            state.copyWith(
              isGenerating: true,
              agentStatusMessage: '検証中: flutter test',
            ),
          );
        }
        final testResult = await _flutterVerify.test(
          flutterExecutable: flutterBin,
          workingDirectory: root,
          isCancelled: () => _cancelRequested,
          timeout: Duration(minutes: state.harness.testTimeoutMinutes),
          logMaxChars: state.harness.verifyLogMaxChars,
        );
        if (await _abortVerifyIfCancelled(emit, testResult)) return;
        final afterTest = CodingFlutterVerifyPolicy.decide(
          _verifyInput(
            phase: CodingFlutterVerifyPhase.afterTest,
            exitCode: testResult.exitCode,
            timedOut: testResult.timedOut,
            launchFailed: testResult.launchFailed,
            commandLog: testResult.log,
          ),
        );
        await _handleFlutterCommandDecision(
          emit,
          decision: afterTest,
          result: testResult,
          flutterBin: flutterBin,
          root: root,
          analyzeResult: result,
        );
        return;
      case CodingFlutterVerifyAction.startFix:
        if (await _observeAutoLoopCommand(emit, result)) return;
        await _beginVerifyFixTurn(emit, result);
        return;
      case CodingFlutterVerifyAction.success:
      case CodingFlutterVerifyAction.stopKeepAuto:
        await _finishFlutterVerify(
          emit,
          decision: decision,
          result: result,
          analyzeResult: analyzeResult,
        );
        return;
      case CodingFlutterVerifyAction.skip:
      case CodingFlutterVerifyAction.runAnalyze:
        return;
    }
  }

  Future<bool> _abortVerifyIfCancelled(
    Emitter<CodingAssistState> emit,
    CodingFlutterVerifyResult result,
  ) async {
    if (!_cancelRequested && !result.cancelled) return false;
    if (!emit.isDone) {
      emit(state.copyWith(isGenerating: false, agentStatusMessage: '停止しました'));
    }
    return true;
  }

  /// 同じ回答なら true。呼び出し元はツール実行も検証も続けない。
  Future<bool> _observeAutoLoopAnswer(
    Emitter<CodingAssistState> emit, {
    required String rawReply,
    required CodingFenceParseResult parsed,
  }) async {
    if (!state.localLlm.codingAutoApplyPatches || _flutterVerifyReportTurn) {
      return false;
    }
    final current = CodingAutoLoop.answerExecution(
      rawReply: rawReply,
      toolCalls: parsed.toolCalls,
      patches: parsed.patches,
      displayText: parsed.displayText,
      minProseChars: state.harness.minProseChars,
      bodyMaxChars: state.harness.loopBodyMaxChars,
    );
    if (current == null) return false;
    final observation = CodingAutoLoop.observe(
      relocationsUsed: _autoLoopRelocations,
      previous: _lastAutoAnswer,
      current: current,
      maxRelocations: state.harness.maxLoopRelocations,
    );
    _lastAutoAnswer = observation.memory;
    if (observation.action == CodingAutoLoopAction.remember) return false;
    await _handleRepeatedExecution(emit, observation);
    return true;
  }

  /// 同じ失敗ログなら true。修正ターンは始めない。
  Future<bool> _observeAutoLoopCommand(
    Emitter<CodingAssistState> emit,
    CodingFlutterVerifyResult result,
  ) async {
    if (!state.localLlm.codingAutoApplyPatches || _cancelRequested) {
      return false;
    }
    final current = CodingAutoLoop.failedCommandExecution(
      commandLabel: result.commandLabel,
      log: result.log,
      minCommandChars: state.harness.minCommandChars,
      bodyMaxChars: state.harness.loopBodyMaxChars,
    );
    if (current == null) return false;
    final observation = CodingAutoLoop.observe(
      relocationsUsed: _autoLoopRelocations,
      previous: _lastAutoCommand,
      current: current,
      maxRelocations: state.harness.maxLoopRelocations,
    );
    _lastAutoCommand = observation.memory;
    if (observation.action == CodingAutoLoopAction.remember) return false;
    await _handleRepeatedExecution(emit, observation);
    return true;
  }

  Future<void> _handleRepeatedExecution(
    Emitter<CodingAssistState> emit,
    CodingAutoLoopObservation observation,
  ) async {
    if (_cancelRequested || emit.isDone) return;
    if (observation.action == CodingAutoLoopAction.stopAuto) {
      await _stopAutoRunForRepeatedExecution(emit);
      return;
    }
    await _relocateAutoLoopConversation(
      emit,
      lastBody: observation.previous?.body ?? '',
      currentBody: observation.current?.body ?? '',
    );
  }

  /// 今の会話は残し、最後の実行と今の実行だけを載せた新規会話で続ける。
  Future<void> _relocateAutoLoopConversation(
    Emitter<CodingAssistState> emit, {
    required String lastBody,
    required String currentBody,
  }) async {
    final root = state.workspaceRoot;
    final existing = state.thread;
    if (root == null || existing == null) {
      if (!emit.isDone) {
        emit(
          state.copyWith(isGenerating: false, errorMessage: '新しい会話へ移せませんでした'),
        );
      }
      return;
    }
    try {
      await _repository.saveThread(existing);
    } catch (e) {
      if (!emit.isDone) {
        emit(
          state.copyWith(
            isGenerating: false,
            errorMessage: '会話を保存できませんでした: $e',
          ),
        );
      }
      return;
    }
    final thread = CodingThread(
      id: const Uuid().v4(),
      title: CodingThread.placeholderTitle,
      workspaceRootPath: root,
      messages: const [],
      updatedAt: DateTime.now(),
    );
    try {
      await _repository.saveThread(thread);
    } catch (e) {
      if (!emit.isDone) {
        emit(
          state.copyWith(
            isGenerating: false,
            errorMessage: '新しい会話を作れませんでした: $e',
          ),
        );
      }
      return;
    }
    final summaries = await _repository.listSummaries();
    if (emit.isDone) return;
    emit(
      state.copyWith(
        thread: thread,
        pendingPatches: const [],
        isGenerating: false,
        streamingText: '',
        threadSummaries: summaries,
        isHistoryOpen: false,
        isEditingLastUser: false,
        clearError: true,
        agentStatusMessage: '同じ実行が繰り返されたため、新しい会話で続けます',
      ),
    );
    _autoLoopRelocations += 1;
    await _runAgentTurn(
      emit,
      userText: codingAssistAutoLoopContinuePrompt(
        lastBody: lastBody,
        currentBody: currentBody,
      ),
      clearDraft: false,
      honorEditLastUser: false,
    );
  }

  /// 2回目の同一実行。新規会話には移さず、この実行だけ止める。自動実行は OFF にしない。
  Future<void> _stopAutoRunForRepeatedExecution(
    Emitter<CodingAssistState> emit,
  ) async {
    _lastAutoAnswer = null;
    _lastAutoCommand = null;
    await _appendAssistantNotice(
      emit,
      '同じ実行が2回繰り返されたため、ここで止めました。自動実行は ON のままです。',
      status: '同じ実行の繰り返しで止めました',
      localLlm: state.localLlm,
    );
  }

  Future<void> _beginVerifyFixTurn(
    Emitter<CodingAssistState> emit,
    CodingFlutterVerifyResult result,
  ) async {
    if (_cancelRequested || emit.isDone) {
      await _abortVerifyIfCancelled(
        emit,
        const CodingFlutterVerifyResult(
          commandLabel: 'flutter',
          cancelled: true,
        ),
      );
      return;
    }
    _verifyFixSetsUsed += 1;
    _updatesAppliedThisSet = 0;
    final setNumber = _verifyFixSetsUsed;
    final preload = await _preloadVerifyFixBodies(result.log);
    final prompt = codingAssistAutoVerifyFixPrompt(
      setNumber: setNumber,
      maxSets: state.harness.maxVerifySets,
      commandLabel: result.commandLabel,
      log: result.log,
      bodiesSupplied: preload.isNotEmpty,
    );
    if (!emit.isDone) {
      final notes = <String>[];
      if (_writtenPathsThisCycle.isNotEmpty) {
        notes.add(
          '（書いたファイルの添付は捨て、現状を読み直して続けます）\n'
          '${_writtenPathsThisCycle.map((path) => '- $path').join('\n')}',
        );
      }
      if (preload.isNotEmpty) {
        notes.add(
          '（検証の修正で先に渡す本文）\n'
          '${preload.map((file) => '- ${file.path}').join('\n')}',
        );
      }
      final reread = notes.join('\n');
      emit(
        state.copyWith(
          isGenerating: false,
          agentStatusMessage: '自動修正 $setNumber/${state.harness.maxVerifySets}',
          generationTrace: reread.isEmpty
              ? state.generationTrace
              : _appendGenerationTrace(state.generationTrace, reread),
        ),
      );
    }
    await _runAgentTurn(
      emit,
      userText: prompt,
      clearDraft: false,
      honorEditLastUser: false,
      fixedPrompts: const [CodingPromptAction.errorAnalyze],
      preloadReads: preload,
    );
  }

  Future<void> _finishFlutterVerify(
    Emitter<CodingAssistState> emit, {
    required CodingFlutterVerifyDecision decision,
    CodingFlutterVerifyResult? result,
    CodingFlutterVerifyResult? analyzeResult,
  }) async {
    final llm = state.localLlm;
    if (decision.action == CodingFlutterVerifyAction.success) {
      _resetFlutterVerifyCycle();
    }
    final status = _verifyStatusMessage(decision);
    if (await _reportFlutterVerify(
      emit,
      decision: decision,
      result: result,
      analyzeResult: analyzeResult,
      localLlm: llm,
      status: status,
    )) {
      return;
    }
    await _appendAssistantNotice(
      emit,
      _verifyNoticeText(decision, result),
      status: status,
      localLlm: llm,
    );
  }

  /// コマンド結果があるとき、Agent に検証レポートを書かせる。
  /// 報告できたとき true。短い通知に戻すときは false。
  Future<bool> _reportFlutterVerify(
    Emitter<CodingAssistState> emit, {
    required CodingFlutterVerifyDecision decision,
    required CodingFlutterVerifyResult? result,
    required CodingFlutterVerifyResult? analyzeResult,
    required LocalLlmConnectionSettings localLlm,
    required String status,
  }) async {
    if (!_shouldAskVerifyReport(decision, result)) return false;
    if (!state.localLlm.isCodingUsable || state.thread == null) return false;
    if (emit.isDone) return true;
    emit(
      state.copyWith(
        isGenerating: false,
        localLlm: localLlm,
        agentStatusMessage: '検証結果を報告中',
      ),
    );
    final commands =
        <({String label, int? exitCode, bool timedOut, String log})>[
          if (analyzeResult != null) _verifyReportCommand(analyzeResult),
          if (analyzeResult?.commandLabel != result!.commandLabel)
            _verifyReportCommand(result),
        ];
    _flutterVerifyReportTurn = true;
    try {
      await _runAgentTurn(
        emit,
        userText: codingAssistFlutterVerifyReportPrompt(
          passed: decision.action == CodingFlutterVerifyAction.success,
          commands: commands,
        ),
        clearDraft: false,
        honorEditLastUser: false,
      );
    } finally {
      _flutterVerifyReportTurn = false;
    }
    if (_cancelRequested || emit.isDone) return true;
    if (state.agentStatusMessage == '生成失敗') return false;
    emit(state.copyWith(isGenerating: false, agentStatusMessage: status));
    return true;
  }

  bool _shouldAskVerifyReport(
    CodingFlutterVerifyDecision decision,
    CodingFlutterVerifyResult? result,
  ) {
    if (result == null) return false;
    if (decision.action == CodingFlutterVerifyAction.success) return true;
    return switch (decision.reason) {
      CodingFlutterVerifyStopReason.verifyOnlyFailed ||
      CodingFlutterVerifyStopReason.setsExhausted ||
      CodingFlutterVerifyStopReason.timedOut ||
      CodingFlutterVerifyStopReason.noUpdateApplied => true,
      _ => false,
    };
  }

  ({String label, int? exitCode, bool timedOut, String log})
  _verifyReportCommand(CodingFlutterVerifyResult result) {
    return (
      label: result.commandLabel,
      exitCode: result.exitCode,
      timedOut: result.timedOut,
      log: result.log,
    );
  }

  Future<void> _appendAssistantNotice(
    Emitter<CodingAssistState> emit,
    String text, {
    required String status,
    required LocalLlmConnectionSettings localLlm,
  }) async {
    final thread = state.thread;
    if (thread == null) {
      if (!emit.isDone) {
        emit(
          state.copyWith(
            isGenerating: false,
            localLlm: localLlm,
            agentStatusMessage: status,
          ),
        );
      }
      return;
    }
    final next = thread.copyWith(
      messages: [
        ...thread.messages,
        CodingChatMessage(
          role: CodingMessageRole.assistant,
          content: text,
          at: DateTime.now(),
        ),
      ],
      updatedAt: DateTime.now(),
    );
    try {
      await _repository.saveThread(next);
    } catch (e) {
      if (!emit.isDone) {
        emit(
          state.copyWith(
            isGenerating: false,
            localLlm: localLlm,
            errorMessage: '検証結果を保存できませんでした: $e',
            agentStatusMessage: status,
          ),
        );
      }
      return;
    }
    final summaries = await _repository.listSummaries();
    final used = _estimateUsedTokens(
      messages: next.messages,
      draft: state.draft,
      thread: next,
    );
    var warn = _warningFor(used);
    if (next.compactedSummary != null &&
        warn != CodingContextWarningLevel.block) {
      warn = CodingContextWarningLevel.compacted;
    }
    if (!emit.isDone) {
      emit(
        state.copyWith(
          isGenerating: false,
          streamingText: '',
          thread: next,
          threadSummaries: summaries,
          localLlm: localLlm,
          usedTokens: used,
          warningLevel: warn,
          agentStatusMessage: status,
        ),
      );
    }
  }

  String _verifyStatusMessage(CodingFlutterVerifyDecision decision) {
    return switch (decision.action) {
      CodingFlutterVerifyAction.success => '検証成功',
      CodingFlutterVerifyAction.stopKeepAuto => switch (decision.reason) {
        CodingFlutterVerifyStopReason.pendingAdd => '作成承認が必要です',
        CodingFlutterVerifyStopReason.notFlutter => 'Flutter 以外では検証しません',
        CodingFlutterVerifyStopReason.verifyOnlyFailed => '検証失敗',
        CodingFlutterVerifyStopReason.launchFailed => 'flutter を起動できませんでした',
        CodingFlutterVerifyStopReason.timedOut => '検証がタイムアウトしました',
        CodingFlutterVerifyStopReason.packageInstall => 'パッケージ追加は人手で行ってください',
        CodingFlutterVerifyStopReason.setsExhausted => '検証3セットで打ち切り',
        CodingFlutterVerifyStopReason.noUpdateApplied => '修正を適用できませんでした',
        _ => '検証を止めました',
      },
      _ => '完了',
    };
  }

  String _verifyNoticeText(
    CodingFlutterVerifyDecision decision,
    CodingFlutterVerifyResult? result,
  ) {
    if (decision.action == CodingFlutterVerifyAction.success) {
      return 'flutter analyze と flutter test は成功しました。';
    }
    final autoOn = state.localLlm.codingAutoApplyPatches;
    final command = result?.commandLabel ?? '検証';
    final detail = switch (decision.reason) {
      CodingFlutterVerifyStopReason.setsExhausted =>
        '自動検証の修正を3セット行いましたが、$command はまだ失敗しています。ここで止めました。自動実行は ON のままです。',
      CodingFlutterVerifyStopReason.noUpdateApplied =>
        '自動修正でファイルを更新も作成もできなかったため、ここで止めました。自動実行は ON のままです。',
      CodingFlutterVerifyStopReason.pendingAdd =>
        '新規ファイルを自動作成できませんでした。カードの理由を確認し、必要なら「作成」を押してください。自動実行は ON のままです。',
      CodingFlutterVerifyStopReason.timedOut =>
        autoOn
            ? '$command が時間内に終わらなかったため、ここで止めました。自動実行は ON のままです。'
            : '$command が時間内に終わらなかったため、ここで止めました。自動実行が OFF のため自動修正はしません。',
      CodingFlutterVerifyStopReason.launchFailed =>
        autoOn
            ? 'flutter を起動できませんでした（${result?.launchError ?? '実行ファイルが見つからないか起動に失敗'}）。ここで止めました。自動実行は ON のままです。'
            : 'flutter を起動できませんでした（${result?.launchError ?? '実行ファイルが見つからないか起動に失敗'}）。自動実行が OFF のため自動修正はしません。',
      CodingFlutterVerifyStopReason.verifyOnlyFailed =>
        '$command は失敗しました。自動実行が OFF のため、修正の自動適用はしません。',
      CodingFlutterVerifyStopReason.notFlutter =>
        'このワークスペースは Flutter ではないため、flutter analyze と flutter test は実行しません。',
      CodingFlutterVerifyStopReason.packageInstall =>
        autoOn
            ? '新しいパッケージの追加が必要です。pubspec.yaml への記述とインストールは人が行ってください。ここで止めました。自動実行は ON のままです。'
            : '新しいパッケージの追加が必要です。pubspec.yaml への記述とインストールは人が行ってください。',
      CodingFlutterVerifyStopReason.none => '自動検証を止めました。',
    };
    final log = result?.log.trim() ?? '';
    if (log.isEmpty ||
        decision.reason == CodingFlutterVerifyStopReason.pendingAdd ||
        decision.reason == CodingFlutterVerifyStopReason.notFlutter ||
        decision.reason == CodingFlutterVerifyStopReason.packageInstall) {
      return detail;
    }
    final code = result?.exitCode;
    final codeLine = code == null ? '' : '\n終了コード: $code';
    return '$detail$codeLine\n\n【ログ】\n$log';
  }

  Future<void> _onApplyPatch(
    CodingAssistApplyPatchRequested event,
    Emitter<CodingAssistState> emit,
  ) async {
    final patch = state.pendingPatches
        .where((p) => p.id == event.patchId)
        .firstOrNull;
    if (patch != null && patch.isAddFile) {
      await _approveCreateFileById(event.patchId, emit);
      return;
    }
    await _applyPatchById(event.patchId, emit, auto: false);
  }

  Future<void> _onApproveCreateFile(
    CodingAssistApproveCreateFileRequested event,
    Emitter<CodingAssistState> emit,
  ) async {
    await _approveCreateFileById(event.patchId, emit);
  }

  /// Add File をディスクへ作る。自動実行中は [auto] で件数に数える。
  Future<void> _approveCreateFileById(
    String patchId,
    Emitter<CodingAssistState> emit, {
    bool auto = false,
  }) async {
    final root = state.workspaceRoot;
    if (root == null) return;
    final patch = state.pendingPatches
        .where((p) => p.id == patchId)
        .firstOrNull;
    if (patch == null) return;
    if (patch.status == CodingPatchStatus.applied) return;
    if (!patch.isAddFile) {
      await _applyPatchById(patchId, emit, auto: false);
      return;
    }

    try {
      // 作成先はパッチの Add File パスのみ（左メニュー選択位置は使わない）。
      final rel = _normalizeWorkspacePath(patch.relativePath);
      if (rel.isEmpty) {
        emit(state.copyWith(errorMessage: '作成できません: パスが空です'));
        return;
      }
      if (!rel.contains('/')) {
        final sample = CodingWorkspaceKindDetect.samplesFor(
          state.index?.kind ?? CodingWorkspaceKind.generic,
        ).addFile;
        final msg =
            '作成先はディレクトリを含む相対パスが必要です（例: $sample）。'
            'ファイル名だけの提案は作成できません。配置先を明示して再提案してください。';
        emit(
          state.copyWith(
            pendingPatches: [
              for (final p in state.pendingPatches)
                if (p.id == patch.id)
                  p.copyWith(relativePath: rel, errorMessage: msg)
                else
                  p,
            ],
            errorMessage: '作成できません: $rel\nディレクトリ付きパスで再提案が必要です',
            agentStatusMessage: '作成先不明: $rel',
          ),
        );
        return;
      }

      final content =
          CodingPatchApplier.insertOnlyContent(patch) ??
          patch.newSnippet?.replaceAll('\r\n', '\n') ??
          '';

      final abs = p.join(root, rel);
      final file = File(abs);
      final open = state.openTabs
          .where((t) => t.relativePath.replaceAll('\\', '/') == rel)
          .firstOrNull;

      final existing =
          open?.content ??
          (await file.exists() ? await file.readAsString() : '');
      if (existing.trim().isNotEmpty) {
        final conflict = patch.copyWith(
          relativePath: rel,
          errorMessage: codingAddFileExistsMessage,
        );
        emit(
          state.copyWith(
            pendingPatches: [
              for (final p in state.pendingPatches)
                if (p.id == patch.id) conflict else p,
            ],
            errorMessage: auto ? null : '作成できません: $rel\n既に存在するファイルです',
            clearError: auto,
            agentStatusMessage: auto ? '既存を確認して再提案: $rel' : '作成衝突: $rel',
          ),
        );
        if (auto) {
          await _startReproposeFromCurrent(
            emit,
            [conflict],
            kindsById: {conflict.id: _CodingReproposeKind.addExists},
          );
        }
        return;
      }

      await file.parent.create(recursive: true);
      await file.writeAsString(content);
      _rememberWrittenPath(rel);

      final scanned = await _scanWorkspace(root);
      final index = scanned.relativeFiles.contains(rel)
          ? scanned
          : CodingWorkspaceIndex(
              rootPath: scanned.rootPath,
              rootLabel: scanned.rootLabel,
              relativeFiles: [...scanned.relativeFiles, rel],
              relativeDirectories: scanned.relativeDirectories,
              treeText: scanned.treeText,
              truncated: scanned.truncated,
            );

      var tabs = state.openTabs;
      if (open != null) {
        tabs = [
          for (final t in tabs)
            if (t.relativePath.replaceAll('\\', '/') == rel)
              t.copyWith(content: content, dirty: false)
            else
              t,
        ];
      } else {
        tabs = [...tabs, CodingOpenTab(relativePath: rel, content: content)];
      }

      final pending = _withPatchStatus(
        state.pendingPatches,
        patch.id,
        CodingPatchStatus.applied,
        relativePath: rel,
      );
      final thread = state.thread?.copyWith(
        pendingPatches: pending,
        updatedAt: DateTime.now(),
      );
      if (thread != null) await _repository.saveThread(thread);
      if (auto) {
        _updatesAppliedThisCycle++;
        _updatesAppliedThisSet++;
      }

      emit(
        state.copyWith(
          index: index,
          openTabs: tabs,
          activeTabPath: rel,
          pendingPatches: pending,
          thread: thread,
          agentStatusMessage: auto ? '自動作成: $rel' : '作成: $rel',
          clearError: true,
        ),
      );
    } catch (e) {
      emit(state.copyWith(errorMessage: 'ファイル作成失敗: $e'));
    }
  }

  Future<void> _applyPatchById(
    String patchId,
    Emitter<CodingAssistState> emit, {
    required bool auto,
  }) async {
    final root = state.workspaceRoot;
    if (root == null) return;
    final patch = state.pendingPatches
        .where((p) => p.id == patchId)
        .firstOrNull;
    if (patch == null) return;
    if (patch.status == CodingPatchStatus.applied) return;

    try {
      final rel = _normalizeWorkspacePath(patch.relativePath);
      if (rel.isEmpty) {
        emit(state.copyWith(errorMessage: '適用できません: パスが空です'));
        return;
      }
      final workingPatch = rel == patch.relativePath
          ? patch
          : patch.copyWith(relativePath: rel);

      final abs = p.join(root, rel);
      final file = File(abs);
      final open = state.openTabs
          .where((t) => t.relativePath.replaceAll('\\', '/') == rel)
          .firstOrNull;

      CodingPatchApplyResult tryApply(String base) {
        final detailed = CodingPatchApplier.applyDetailed(
          baseContent: base,
          patch: workingPatch,
        );
        if (detailed.status == CodingPatchApplyStatus.applied || !auto) {
          return detailed;
        }
        final ranged = CodingPatchApplier.applyReplaceRange(
          baseContent: base,
          patch: workingPatch,
          maxLines: state.harness.maxReplaceRangeLines,
        );
        if (ranged != null) {
          return CodingPatchApplyResult.applied(ranged);
        }
        final inserted = CodingPatchApplier.applyInsertAtLine(
          baseContent: base,
          patch: workingPatch,
        );
        if (inserted != null) {
          return CodingPatchApplyResult.applied(inserted);
        }
        return detailed;
      }

      CodingPatchApplyResult? best;
      void consider(CodingPatchApplyResult r) {
        if (best == null) {
          best = r;
          return;
        }
        // applied を最優先、次に conflict、failed は最後
        if (r.status == CodingPatchApplyStatus.applied) {
          best = r;
        } else if (r.status == CodingPatchApplyStatus.addExistsConflict &&
            best!.status == CodingPatchApplyStatus.failed) {
          best = r;
        }
      }

      if (open != null) {
        consider(tryApply(open.content));
      }
      if (best?.status != CodingPatchApplyStatus.applied &&
          await file.exists()) {
        final disk = await file.readAsString();
        if (open == null || disk != open.content) {
          consider(tryApply(disk));
        }
      }
      if (best?.status != CodingPatchApplyStatus.applied &&
          open == null &&
          !await file.exists()) {
        consider(tryApply(''));
      }
      // タブもディスクも無い／空扱いで未試行なら空ベースを試す
      if (best == null) {
        consider(tryApply(open?.content ?? ''));
      }

      final outcome = best ?? const CodingPatchApplyResult.failed();

      if (outcome.status == CodingPatchApplyStatus.addExistsConflict) {
        const msg = 'このパスは既に存在するため Add File を適用できません。Update で出し直します…';
        final prefix = auto ? '自動適用できません' : '適用できません';
        emit(
          state.copyWith(
            pendingPatches: [
              for (final p in state.pendingPatches)
                if (p.id == patch.id)
                  p.copyWith(relativePath: rel, errorMessage: msg)
                else
                  p,
            ],
            agentStatusMessage: 'Add 衝突→再提案: $rel',
            errorMessage: '$prefix: $rel\n既に存在するファイルです。Update File で再提案させます',
          ),
        );
        await _startReproposeFromCurrent(
          emit,
          [workingPatch],
          kindsById: {workingPatch.id: _CodingReproposeKind.addExists},
        );
        return;
      }

      final nextContent = outcome.content;
      if (outcome.status != CodingPatchApplyStatus.applied ||
          nextContent == null) {
        final insertOnly =
            workingPatch.isAddFile ||
            CodingPatchApplier.isInsertOnlyPatch(workingPatch);
        final kind = insertOnly
            ? _CodingReproposeKind.addOrEmpty
            : _CodingReproposeKind.generic;
        const msg = 'ベースと一致しないため適用できません。現状を正として再提案します…';
        final prefix = auto ? '自動適用できません' : '適用できません';
        emit(
          state.copyWith(
            pendingPatches: [
              for (final p in state.pendingPatches)
                if (p.id == patch.id)
                  p.copyWith(relativePath: rel, errorMessage: msg)
                else
                  p,
            ],
            agentStatusMessage: '適用失敗→再提案: $rel',
            errorMessage: '$prefix: $rel\n現状ファイルを正として Agent に再提案させます',
          ),
        );
        await _startReproposeFromCurrent(
          emit,
          [workingPatch],
          kindsById: {workingPatch.id: kind},
        );
        return;
      }

      await file.parent.create(recursive: true);
      await file.writeAsString(nextContent);
      _rememberWrittenPath(rel);
      var tabs = state.openTabs;
      if (open != null) {
        tabs = [
          for (final t in tabs)
            if (t.relativePath.replaceAll('\\', '/') == rel)
              t.copyWith(content: nextContent, dirty: false)
            else
              t,
        ];
      } else {
        tabs = [
          ...tabs,
          CodingOpenTab(relativePath: rel, content: nextContent),
        ];
      }

      final pending = _withPatchStatus(
        state.pendingPatches,
        patch.id,
        CodingPatchStatus.applied,
        relativePath: rel,
      );
      final thread = state.thread?.copyWith(
        pendingPatches: pending,
        updatedAt: DateTime.now(),
      );
      if (thread != null) await _repository.saveThread(thread);
      if (auto && !workingPatch.isAddFile) {
        _updatesAppliedThisCycle++;
        _updatesAppliedThisSet++;
      }
      emit(
        state.copyWith(
          openTabs: tabs,
          activeTabPath: rel,
          pendingPatches: pending,
          thread: thread,
          agentStatusMessage: auto ? '自動適用: $rel' : '適用: $rel',
        ),
      );
    } catch (e) {
      emit(state.copyWith(errorMessage: '${auto ? '自動適用' : '適用'}失敗: $e'));
    }
  }

  Future<void> _onRejectPatch(
    CodingAssistRejectPatchRequested event,
    Emitter<CodingAssistState> emit,
  ) async {
    final pending = [
      for (final p in state.pendingPatches)
        if (p.id != event.patchId) p,
    ];
    final thread = state.thread?.copyWith(
      pendingPatches: pending,
      updatedAt: DateTime.now(),
    );
    if (thread != null) await _repository.saveThread(thread);
    emit(state.copyWith(pendingPatches: pending, thread: thread));
  }

  Future<void> _onMarkPatchApplied(
    CodingAssistMarkPatchAppliedRequested event,
    Emitter<CodingAssistState> emit,
  ) async {
    final pending = _withPatchStatus(
      state.pendingPatches,
      event.patchId,
      CodingPatchStatus.applied,
    );
    final thread = state.thread?.copyWith(
      pendingPatches: pending,
      updatedAt: DateTime.now(),
    );
    if (thread != null) await _repository.saveThread(thread);
    emit(state.copyWith(pendingPatches: pending, thread: thread));
  }

  /// 指定パッチの status を更新（カードはリストに残す）。
  static List<CodingProposedPatch> _withPatchStatus(
    List<CodingProposedPatch> patches,
    String patchId,
    CodingPatchStatus status, {
    String? relativePath,
  }) {
    return [
      for (final p in patches)
        if (p.id == patchId)
          p.copyWith(
            status: status,
            relativePath: relativePath,
            clearError: true,
          )
        else
          p,
    ];
  }

  Future<void> _onNewThread(
    CodingAssistNewThreadRequested event,
    Emitter<CodingAssistState> emit,
  ) async {
    final root = state.workspaceRoot;
    if (root == null) return;
    _resetFlutterVerifyCycle();
    final thread = CodingThread(
      id: const Uuid().v4(),
      title: CodingThread.placeholderTitle,
      workspaceRootPath: root,
      messages: const [],
      updatedAt: DateTime.now(),
    );
    await _repository.saveThread(thread);
    final summaries = await _repository.listSummaries();
    final used = _estimateUsedTokens(
      messages: const [],
      draft: '',
      clearAttached: true,
      clearAttachedOpenFiles: true,
      clearAttachedFolderStructures: true,
    );
    emit(
      state.copyWith(
        thread: thread,
        pendingPatches: const [],
        draft: '',
        bumpDraftEpoch: true,
        streamingText: '',
        threadSummaries: summaries,
        isHistoryOpen: false,
        isEditingLastUser: false,
        clearAttachedSelection: true,
        clearAttachedOpenFiles: true,
        clearAttachedFolderStructures: true,
        clearAppliedPromptActions: true,
        usedTokens: used,
        warningLevel: CodingContextWarningLevel.none,
        agentStatusMessage: '新しい会話',
      ),
    );
  }

  Future<void> _onHistoryOpen(
    CodingAssistHistoryOpenRequested event,
    Emitter<CodingAssistState> emit,
  ) async {
    try {
      final summaries = await _repository.listSummaries();
      emit(
        state.copyWith(
          isHistoryOpen: true,
          threadSummaries: summaries,
          clearError: true,
        ),
      );
    } catch (e) {
      emit(state.copyWith(errorMessage: '履歴の読込に失敗: $e'));
    }
  }

  void _onHistoryClose(
    CodingAssistHistoryCloseRequested event,
    Emitter<CodingAssistState> emit,
  ) {
    emit(state.copyWith(isHistoryOpen: false));
  }

  Future<void> _onOpenThread(
    CodingAssistOpenThreadRequested event,
    Emitter<CodingAssistState> emit,
  ) async {
    try {
      final thread = await _repository.loadThread(event.threadId);
      if (thread == null) {
        emit(state.copyWith(errorMessage: '会話が見つかりません'));
        return;
      }
      final pending = thread.pendingPatches
          .where((p) => p.status != CodingPatchStatus.rejected)
          .toList();
      final used = _estimateUsedTokens(
        messages: thread.messages,
        draft: state.draft,
        thread: thread,
        clearAttached: true,
        clearAttachedOpenFiles: true,
        clearAttachedFolderStructures: true,
      );
      var warn = _warningFor(used);
      if (thread.compactedSummary != null &&
          warn != CodingContextWarningLevel.block) {
        warn = CodingContextWarningLevel.compacted;
      }
      emit(
        state.copyWith(
          thread: thread,
          pendingPatches: pending,
          isHistoryOpen: false,
          isEditingLastUser: false,
          streamingText: '',
          clearAttachedSelection: true,
          clearAttachedOpenFiles: true,
          clearAttachedFolderStructures: true,
          clearAppliedPromptActions: true,
          usedTokens: used,
          warningLevel: warn,
          agentStatusMessage: '履歴を開きました',
        ),
      );
    } catch (e) {
      emit(state.copyWith(errorMessage: '会話の読込に失敗: $e'));
    }
  }

  Future<void> _onDeleteThread(
    CodingAssistDeleteThreadRequested event,
    Emitter<CodingAssistState> emit,
  ) async {
    try {
      await _repository.deleteThread(event.threadId);
      final summaries = await _repository.listSummaries();
      final deletingCurrent = state.thread?.id == event.threadId;
      if (deletingCurrent) {
        final root = state.workspaceRoot;
        if (root == null) {
          emit(
            state.copyWith(
              threadSummaries: summaries,
              clearThread: true,
              pendingPatches: const [],
            ),
          );
          return;
        }
        final thread = CodingThread(
          id: const Uuid().v4(),
          title: CodingThread.placeholderTitle,
          workspaceRootPath: root,
          messages: const [],
          updatedAt: DateTime.now(),
        );
        await _repository.saveThread(thread);
        final nextSummaries = await _repository.listSummaries();
        emit(
          state.copyWith(
            thread: thread,
            pendingPatches: const [],
            draft: '',
            streamingText: '',
            threadSummaries: nextSummaries,
            clearAttachedSelection: true,
            clearAttachedOpenFiles: true,
            clearAttachedFolderStructures: true,
            clearAppliedPromptActions: true,
            agentStatusMessage: '会話を削除しました',
          ),
        );
        return;
      }
      emit(state.copyWith(threadSummaries: summaries));
    } catch (e) {
      emit(state.copyWith(errorMessage: '削除に失敗: $e'));
    }
  }

  void _onSelectionAttached(
    CodingAssistSelectionAttached event,
    Emitter<CodingAssistState> emit,
  ) {
    emit(
      state.copyWith(
        attachedSelection: event.selection,
        usedTokens: _estimateUsedTokens(attachedSelection: event.selection),
      ),
    );
  }

  void _onSelectionCleared(
    CodingAssistSelectionCleared event,
    Emitter<CodingAssistState> emit,
  ) {
    emit(
      state.copyWith(
        clearAttachedSelection: true,
        usedTokens: _estimateUsedTokens(clearAttached: true),
      ),
    );
  }

  List<CodingHistoryChip> _historyChipsFromState() {
    final selection = state.attachedSelection;
    return [
      for (final file in state.attachedOpenFiles)
        CodingHistoryChip(
          kind: CodingHistoryChipKind.file,
          label: file.relativePath,
          path: file.relativePath,
        ),
      if (selection != null)
        CodingHistoryChip(
          kind: CodingHistoryChipKind.selection,
          label: '選択範囲: ${selection.relativePath}',
          path: selection.relativePath,
        ),
      for (final folder in state.attachedFolderStructures)
        CodingHistoryChip(
          kind: CodingHistoryChipKind.folder,
          label: 'フォルダ構造: ${folder.chipLabel}',
          path: folder.relativePath,
        ),
    ];
  }

  Future<void> _onFolderFilesAttachRequested(
    CodingAssistFolderFilesAttachRequested event,
    Emitter<CodingAssistState> emit,
  ) async {
    final root = state.workspaceRoot;
    final index = state.index;
    if (root == null || index == null) return;
    final paths = CodingFileTreeNode.filesUnderDirectory(
      index.relativeFiles,
      event.relativePath,
    );
    if (paths.isEmpty) {
      emit(state.copyWith(agentStatusMessage: 'このフォルダに付与できるファイルはありません'));
      return;
    }
    final openByPath = <String, String>{
      for (final tab in state.openTabs)
        tab.relativePath.replaceAll('\\', '/'): tab.content,
    };
    final files = <CodingAttachedOpenFile>[];
    var failed = 0;
    for (final rel in paths) {
      final fromTab = openByPath[rel];
      if (fromTab != null) {
        files.add(CodingAttachedOpenFile(relativePath: rel, content: fromTab));
        continue;
      }
      try {
        final file = File(p.join(root, rel));
        if (!await file.exists()) {
          failed++;
          continue;
        }
        files.add(
          CodingAttachedOpenFile(
            relativePath: rel,
            content: await file.readAsString(),
          ),
        );
      } catch (_) {
        failed++;
      }
    }
    if (files.isEmpty) {
      emit(state.copyWith(agentStatusMessage: 'ファイルを読めませんでした'));
      return;
    }
    _onOpenFilesAttached(CodingAssistOpenFilesAttached(files), emit);
    if (emit.isDone) return;
    final status = failed > 0
        ? 'フォルダのファイルを ${files.length} 件付与しました（$failed 件は読めませんでした）'
        : 'フォルダのファイルを ${files.length} 件付与しました';
    emit(state.copyWith(agentStatusMessage: status, clearError: true));
  }

  void _onFolderStructureAttached(
    CodingAssistFolderStructureAttached event,
    Emitter<CodingAssistState> emit,
  ) {
    final item = event.structure;
    if (item.block.trim().isEmpty) return;
    final path = item.relativePath.replaceAll('\\', '/');
    final next = [
      for (final current in state.attachedFolderStructures)
        if (current.relativePath != path) current,
      CodingAttachedFolderStructure(relativePath: path, block: item.block),
    ];
    emit(
      state.copyWith(
        attachedFolderStructures: next,
        usedTokens: _estimateUsedTokens(attachedFolderStructures: next),
        agentStatusMessage: 'フォルダ構造を付与しました',
      ),
    );
  }

  void _onFolderStructureRemoved(
    CodingAssistFolderStructureRemoved event,
    Emitter<CodingAssistState> emit,
  ) {
    final path = event.relativePath.replaceAll('\\', '/');
    final next = [
      for (final current in state.attachedFolderStructures)
        if (current.relativePath != path) current,
    ];
    emit(
      state.copyWith(
        attachedFolderStructures: next,
        usedTokens: _estimateUsedTokens(attachedFolderStructures: next),
      ),
    );
  }

  void _onOpenFilesAttached(
    CodingAssistOpenFilesAttached event,
    Emitter<CodingAssistState> emit,
  ) {
    if (event.files.isEmpty) return;
    final byPath = <String, CodingAttachedOpenFile>{
      for (final f in state.attachedOpenFiles)
        f.relativePath.replaceAll('\\', '/'): f,
    };
    for (final f in event.files) {
      final rel = f.relativePath.replaceAll('\\', '/');
      // 截断は toPromptBlock 側。保持は全文（上限内）またはあらかじめ截断済み。
      byPath[rel] = CodingAttachedOpenFile(
        relativePath: rel,
        content: f.content.length > state.harness.openFileMaxChars
            ? f.content.substring(0, state.harness.openFileMaxChars)
            : f.content,
      );
    }
    final next = byPath.values.toList(growable: false);
    emit(
      state.copyWith(
        attachedOpenFiles: next,
        usedTokens: _estimateUsedTokens(attachedOpenFiles: next),
        agentStatusMessage: '取り込み中: ${next.length} 件',
        clearError: true,
      ),
    );
  }

  void _onOpenFileAttachmentRemoved(
    CodingAssistOpenFileAttachmentRemoved event,
    Emitter<CodingAssistState> emit,
  ) {
    final rel = event.relativePath.replaceAll('\\', '/');
    final next = [
      for (final f in state.attachedOpenFiles)
        if (f.relativePath.replaceAll('\\', '/') != rel) f,
    ];
    emit(
      state.copyWith(
        attachedOpenFiles: next,
        usedTokens: _estimateUsedTokens(attachedOpenFiles: next),
      ),
    );
  }

  void _onOpenFileAttachmentsCleared(
    CodingAssistOpenFileAttachmentsCleared event,
    Emitter<CodingAssistState> emit,
  ) {
    emit(
      state.copyWith(
        clearAttachedOpenFiles: true,
        usedTokens: _estimateUsedTokens(clearAttachedOpenFiles: true),
      ),
    );
  }

  void _onEditLastUser(
    CodingAssistEditLastUserRequested event,
    Emitter<CodingAssistState> emit,
  ) {
    if (!state.canEditOrRevokeLastUser) return;
    final index = state.lastUserMessageIndex;
    final thread = state.thread;
    if (index == null || thread == null) return;
    final message = thread.messages[index];
    final view = codingUserHistoryView(message);
    final restored = view.split
        ? codingRestoreComposerAttachments(message.content, chips: view.chips)
        : null;
    final draft = view.split ? view.text : message.content;
    final files = restored?.files ?? const <CodingAttachedOpenFile>[];
    final folders =
        restored?.folders ?? const <CodingAttachedFolderStructure>[];
    emit(
      state.copyWith(
        draft: draft,
        bumpDraftEpoch: true,
        isEditingLastUser: true,
        attachedOpenFiles: view.split ? files : null,
        clearAttachedOpenFiles: !view.split,
        attachedFolderStructures: view.split ? folders : null,
        clearAttachedFolderStructures: !view.split,
        attachedSelection: restored?.selection,
        clearAttachedSelection: restored?.selection == null,
        appliedPromptActions: view.split ? message.fixedPrompts : null,
        clearAppliedPromptActions: !view.split,
        usedTokens: _estimateUsedTokens(
          draft: draft,
          attachedOpenFiles: view.split ? files : null,
          attachedFolderStructures: view.split ? folders : null,
          attachedSelection: restored?.selection,
          clearAttached: restored?.selection == null,
          clearAttachedOpenFiles: !view.split,
          clearAttachedFolderStructures: !view.split,
        ),
        agentStatusMessage: '直近のメッセージを編集中（送信で再生成）',
        clearError: true,
      ),
    );
  }

  Future<void> _onRerunLastUser(
    CodingAssistRerunLastUserRequested event,
    Emitter<CodingAssistState> emit,
  ) async {
    if (!state.canEditOrRevokeLastUser) return;
    final index = state.lastUserMessageIndex;
    final thread = state.thread;
    if (index == null || thread == null) return;
    final message = thread.messages[index];
    final content = message.content.trim();
    if (content.isEmpty) return;
    final fixedPrompts = message.fixedPrompts;
    _resetFlutterVerifyCycle();
    _armFlutterVerifyIfMarked(content);
    _armDocumentOnlyTurn(actions: fixedPrompts, text: content);

    emit(
      state.copyWith(
        draft: '',
        bumpDraftEpoch: true,
        isEditingLastUser: true,
        clearAttachedSelection: true,
        clearAttachedOpenFiles: true,
        clearAttachedFolderStructures: true,
        usedTokens: _estimateUsedTokens(
          draft: '',
          clearAttached: true,
          clearAttachedOpenFiles: true,
          clearAttachedFolderStructures: true,
        ),
        agentStatusMessage: '直近のメッセージを再実行中…',
        clearError: true,
      ),
    );
    _reproposedCounts.clear();
    _queuedRepropose.clear();
    await _runAgentTurn(
      emit,
      userText: content,
      clearDraft: true,
      honorEditLastUser: true,
      fixedPrompts: fixedPrompts,
      requestText: message.requestText ?? '',
      historyChips: codingUserHistoryView(message).chips,
    );
  }

  Future<void> _onRevokeLastTurn(
    CodingAssistRevokeLastTurnRequested event,
    Emitter<CodingAssistState> emit,
  ) async {
    if (!state.canEditOrRevokeLastUser) return;
    final thread = state.thread;
    final index = state.lastUserMessageIndex;
    if (thread == null || index == null) return;

    final trimmed = thread.copyWith(
      messages: thread.messages.sublist(0, index),
      pendingPatches: const [],
      updatedAt: DateTime.now(),
    );
    final draft = state.isEditingLastUser ? '' : state.draft;
    try {
      await _repository.saveThread(trimmed);
      final summaries = await _repository.listSummaries();
      emit(
        state.copyWith(
          thread: trimmed,
          pendingPatches: const [],
          draft: draft,
          bumpDraftEpoch: state.isEditingLastUser,
          isEditingLastUser: false,
          streamingText: '',
          threadSummaries: summaries,
          usedTokens: _estimateUsedTokens(
            messages: trimmed.messages,
            draft: draft,
          ),
          agentStatusMessage: 'とりけししました',
          clearError: true,
        ),
      );
    } catch (e) {
      emit(state.copyWith(errorMessage: 'とりけしに失敗: $e'));
    }
  }

  Future<void> _onCodingModelChanged(
    CodingAssistCodingModelChanged event,
    Emitter<CodingAssistState> emit,
  ) async {
    var busy = false;
    try {
      final settings = await _getConnectionSettings();
      final previous = settings.localLlm;
      final m = event.customModel;
      // ドロップダウンの再通知で同じモデルを切り直すと、送信不可のまま残る。
      if (previous.usesCustomCodingModel &&
          previous.codingCustomModelId == m.id &&
          previous.codingCustomGgufFileName == m.ggufFileName) {
        return;
      }
      final llm = previous.withCustomCodingModel(
        id: m.id,
        label: m.label,
        ggufFileName: m.ggufFileName,
      );
      await _saveConnectionSettings(settings.copyWith(localLlm: llm));
      if (emit.isDone) return;
      emit(state.copyWith(isLlmBusy: true, agentStatusMessage: 'モデル切替中…'));
      busy = true;
      final mtpDraft = await _localLlmServerLauncher.applySettings(
        settings: llm.forServer(),
        previous: previous.forServer(),
        isHealthy: _localLlmClient.isReachable,
      );
      if (emit.isDone) return;
      final used = _estimateUsedTokens(contextSize: llm.codingContextSize);
      var warn = _warningFor(used, contextSize: llm.codingContextSize);
      if (state.thread?.compactedSummary != null &&
          warn != CodingContextWarningLevel.block) {
        warn = CodingContextWarningLevel.compacted;
      }
      emit(
        state.copyWith(
          localLlm: llm,
          isLlmBusy: false,
          usedTokens: used,
          warningLevel: warn,
          agentStatusMessage: mtpDraft == null
              ? 'モデル: ${llm.resolvedCodingModelLabel}'
              : 'MTP 下書き係を併用します（$mtpDraft）',
          mtpDraftFileName: mtpDraft,
          clearMtpDraft: mtpDraft == null,
        ),
      );
      busy = false;
    } catch (e) {
      if (!emit.isDone) {
        emit(state.copyWith(isLlmBusy: false, errorMessage: 'モデル変更失敗: $e'));
      }
      busy = false;
    } finally {
      if (busy && !emit.isDone) {
        emit(state.copyWith(isLlmBusy: false));
      }
    }
  }

  Future<void> _onCodingThinkingChanged(
    CodingAssistCodingThinkingChanged event,
    Emitter<CodingAssistState> emit,
  ) async {
    if (state.isGenerating || state.isLlmBusy) return;
    try {
      final settings = await _getConnectionSettings();
      final previous = settings.localLlm;
      if (previous.codingThinkingEnabled == event.enabled) return;
      final llm = previous.copyWith(codingThinkingEnabled: event.enabled);
      await _saveConnectionSettings(settings.copyWith(localLlm: llm));
      emit(
        state.copyWith(
          isLlmBusy: true,
          agentStatusMessage: event.enabled ? '思考モードを ON…' : '思考モードを OFF…',
        ),
      );
      // previous を渡さないと forceRestart にならず、起動済みサーバへ接続するだけで終わる。
      final mtpDraft = await _localLlmServerLauncher.applySettings(
        settings: llm.forServer(),
        previous: previous.forServer(),
        isHealthy: _localLlmClient.isReachable,
        onStatus: (message) {
          if (!emit.isDone) {
            emit(state.copyWith(isLlmBusy: true, agentStatusMessage: message));
          }
        },
      );
      emit(
        state.copyWith(
          localLlm: llm,
          isLlmBusy: false,
          agentStatusMessage: event.enabled ? '思考モード: ON' : '思考モード: OFF',
          mtpDraftFileName: mtpDraft,
          clearMtpDraft: mtpDraft == null,
        ),
      );
    } catch (e) {
      emit(state.copyWith(isLlmBusy: false, errorMessage: '思考モード変更失敗: $e'));
    }
  }

  /// Agent自動実行。設定キーだけ更新し、llama-server は再起動しない。
  Future<void> _onAgentAutoRunChanged(
    CodingAssistAgentAutoRunChanged event,
    Emitter<CodingAssistState> emit,
  ) async {
    if (state.isGenerating || state.isLlmBusy) return;
    try {
      final settings = await _getConnectionSettings();
      final previous = settings.localLlm;
      if (previous.codingAutoApplyPatches == event.enabled) return;
      final llm = previous.copyWith(codingAutoApplyPatches: event.enabled);
      await _saveConnectionSettings(settings.copyWith(localLlm: llm));
      emit(
        state.copyWith(
          localLlm: llm,
          agentStatusMessage: event.enabled
              ? 'Agent自動実行: ON'
              : 'Agent自動実行: OFF',
        ),
      );
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Agent自動実行の変更失敗: $e'));
    }
  }

  Future<void> _onCompactContext(
    CodingAssistCompactContextRequested event,
    Emitter<CodingAssistState> emit,
  ) async {
    if (state.isGenerating) return;
    final thread = state.thread;
    if (thread == null || thread.messages.isEmpty) {
      emit(state.copyWith(agentStatusMessage: '圧縮する会話がありません'));
      return;
    }
    final compacted = _compactThread(thread);
    if (compacted == null) {
      emit(state.copyWith(agentStatusMessage: 'これ以上圧縮できません（直近ターンは維持）'));
      return;
    }
    final used = _estimateUsedTokens(thread: compacted, draft: state.draft);
    var warn = _warningFor(used);
    if (warn != CodingContextWarningLevel.block) {
      warn = CodingContextWarningLevel.compacted;
    }
    final saved = compacted.copyWith(contextWarningLevel: warn);
    try {
      await _repository.saveThread(saved);
      emit(
        state.copyWith(
          thread: saved,
          usedTokens: used,
          warningLevel: warn,
          agentStatusMessage: 'コンテキストを圧縮しました',
          clearError: true,
        ),
      );
    } catch (e) {
      emit(state.copyWith(errorMessage: '圧縮の保存に失敗: $e'));
    }
  }

  void _onErrorConsumed(
    CodingAssistErrorConsumed event,
    Emitter<CodingAssistState> emit,
  ) {
    emit(state.copyWith(clearError: true));
  }

  Future<void> _onRefreshWorkspace(
    CodingAssistRefreshWorkspaceRequested event,
    Emitter<CodingAssistState> emit,
  ) async {
    final root = state.workspaceRoot;
    if (root == null) return;
    emit(state.copyWith(workspaceStatusMessage: '索引を更新中…', clearError: true));
    try {
      final index = await _scanWorkspace(root);
      final branch = await CodingGit.currentBranch(root);
      final nextTabs = <CodingOpenTab>[];
      for (final tab in state.openTabs) {
        final abs = p.join(root, tab.relativePath);
        final file = File(abs);
        if (!await file.exists()) continue;
        if (tab.dirty) {
          nextTabs.add(tab);
        } else {
          nextTabs.add(
            tab.copyWith(content: await file.readAsString(), dirty: false),
          );
        }
      }
      String? active = state.activeTabPath;
      if (active != null && !nextTabs.any((t) => t.relativePath == active)) {
        active = nextTabs.isEmpty ? null : nextTabs.last.relativePath;
      }
      emit(
        state.copyWith(
          index: index,
          gitBranch: branch,
          clearGitBranch: branch == null,
          openTabs: nextTabs,
          activeTabPath: active,
          clearActiveTab: active == null,
          workspaceStatusMessage:
              '${index.rootLabel}（${index.relativeFiles.length} files）',
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(errorMessage: '更新失敗: $e', clearWorkspaceStatus: true),
      );
    }
  }

  /// VS Code 等で保存したあと、表示中タブだけディスクから取り直す（未保存は破棄）。
  Future<void> _onReloadActiveTabFromDisk(
    CodingAssistReloadActiveTabFromDiskRequested event,
    Emitter<CodingAssistState> emit,
  ) async {
    final root = state.workspaceRoot;
    final rel = state.activeTabPath?.replaceAll('\\', '/');
    if (root == null || rel == null) return;
    try {
      final file = File(p.join(root, rel));
      if (!await file.exists()) {
        emit(state.copyWith(errorMessage: '再読込できません（ディスクにありません）: $rel'));
        return;
      }
      final content = await file.readAsString();
      emit(
        state.copyWith(
          openTabs: [
            for (final t in state.openTabs)
              if (t.relativePath.replaceAll('\\', '/') == rel)
                t.copyWith(content: content, dirty: false)
              else
                t,
          ],
          workspaceStatusMessage: '再読込: $rel',
          clearError: true,
        ),
      );
    } catch (e) {
      emit(state.copyWith(errorMessage: '再読込失敗: $e'));
    }
  }

  Future<void> _onCreateUntitledFile(
    CodingAssistCreateUntitledFileRequested event,
    Emitter<CodingAssistState> emit,
  ) async {
    final root = state.workspaceRoot;
    if (root == null) return;
    final parent = _normalizeRelDir(event.parentRelativeDir);
    final used = <String>[
      ...?state.index?.relativeFiles,
      ...?state.index?.relativeDirectories,
      for (final tab in state.openTabs) tab.relativePath,
    ];
    for (var attempt = 0; attempt < 1000; attempt++) {
      final name = codingAssistNextUntitledName(
        relativePaths: used,
        parentRelativeDir: parent,
      );
      final rel = parent.isEmpty ? name : '$parent/$name';
      final abs = p.join(root, rel);
      final taken = await File(abs).exists() || await Directory(abs).exists();
      if (taken) {
        used.add(rel);
        continue;
      }
      await _createEmptyFile(emit, parentRelativeDir: parent, name: name);
      return;
    }
    emit(state.copyWith(errorMessage: 'Untitled の連番を決められません'));
  }

  Future<void> _onCreateFile(
    CodingAssistCreateFileRequested event,
    Emitter<CodingAssistState> emit,
  ) async {
    final name = _sanitizeEntryName(event.name);
    if (name == null) {
      emit(state.copyWith(errorMessage: 'ファイル名が不正です'));
      return;
    }
    await _createEmptyFile(
      emit,
      parentRelativeDir: event.parentRelativeDir,
      name: name,
    );
  }

  Future<void> _createEmptyFile(
    Emitter<CodingAssistState> emit, {
    required String parentRelativeDir,
    required String name,
  }) async {
    final root = state.workspaceRoot;
    if (root == null) return;
    final safeName = _sanitizeEntryName(name);
    if (safeName == null) {
      emit(state.copyWith(errorMessage: 'ファイル名が不正です'));
      return;
    }
    final parent = _normalizeRelDir(parentRelativeDir);
    final rel = parent.isEmpty ? safeName : '$parent/$safeName';
    final abs = p.join(root, rel);
    try {
      final file = File(abs);
      if (await file.exists() || await Directory(abs).exists()) {
        emit(state.copyWith(errorMessage: '既に存在します: $rel'));
        return;
      }
      await file.parent.create(recursive: true);
      await file.writeAsString('');
      // 走査対象外拡張子でもツリーに出す（明示作成したファイルは必ず載せる）。
      final scanned = await _scanWorkspace(root);
      final index = scanned.relativeFiles.contains(rel)
          ? scanned
          : CodingWorkspaceIndex(
              rootPath: scanned.rootPath,
              rootLabel: scanned.rootLabel,
              relativeFiles: [...scanned.relativeFiles, rel],
              relativeDirectories: scanned.relativeDirectories,
              treeText: scanned.treeText,
              truncated: scanned.truncated,
            );
      final alreadyOpen = state.openTabs.any((t) => t.relativePath == rel);
      emit(
        state.copyWith(
          index: index,
          openTabs: alreadyOpen
              ? state.openTabs
              : [
                  ...state.openTabs,
                  CodingOpenTab(relativePath: rel, content: ''),
                ],
          activeTabPath: rel,
          workspaceStatusMessage: '作成: $rel',
          clearError: true,
        ),
      );
    } catch (e) {
      emit(state.copyWith(errorMessage: 'ファイル作成失敗: $e'));
    }
  }

  Future<void> _onCreateFolder(
    CodingAssistCreateFolderRequested event,
    Emitter<CodingAssistState> emit,
  ) async {
    final root = state.workspaceRoot;
    if (root == null) return;
    final name = _sanitizeEntryName(event.name);
    if (name == null) {
      emit(state.copyWith(errorMessage: 'フォルダ名が不正です'));
      return;
    }
    final parent = _normalizeRelDir(event.parentRelativeDir);
    final rel = parent.isEmpty ? name : '$parent/$name';
    final abs = p.join(root, rel);
    try {
      final dir = Directory(abs);
      if (await dir.exists() || await File(abs).exists()) {
        emit(state.copyWith(errorMessage: '既に存在します: $rel'));
        return;
      }
      await dir.create(recursive: true);
      final index = await _scanWorkspace(root);
      emit(
        state.copyWith(
          index: index,
          workspaceStatusMessage: 'フォルダ作成: $rel',
          clearError: true,
        ),
      );
    } catch (e) {
      emit(state.copyWith(errorMessage: 'フォルダ作成失敗: $e'));
    }
  }

  Future<void> _onMovePath(
    CodingAssistMovePathRequested event,
    Emitter<CodingAssistState> emit,
  ) async {
    final root = state.workspaceRoot;
    if (root == null) return;
    final source = event.sourceRelativePath.replaceAll('\\', '/').trim();
    final targetDir = _normalizeRelDir(event.targetDirectoryRelativePath);
    if (source.isEmpty) return;

    final baseName = p.basename(source);
    final destRel = targetDir.isEmpty ? baseName : '$targetDir/$baseName';
    if (source == destRel) return;

    if (event.sourceIsDirectory) {
      if (targetDir == source || targetDir.startsWith('$source/')) {
        emit(state.copyWith(errorMessage: '自分自身の中には移動できません'));
        return;
      }
    }

    final srcParent = _normalizeRelDir(p.dirname(source));
    if (srcParent == targetDir) return;

    final srcAbs = p.join(root, source);
    final destAbs = p.join(root, destRel);
    try {
      if (await File(destAbs).exists() || await Directory(destAbs).exists()) {
        emit(state.copyWith(errorMessage: '移動先に同名が既にあります: $destRel'));
        return;
      }
      await Directory(p.dirname(destAbs)).create(recursive: true);
      if (event.sourceIsDirectory) {
        await Directory(srcAbs).rename(destAbs);
      } else {
        await File(srcAbs).rename(destAbs);
      }

      final nextTabs = <CodingOpenTab>[
        for (final tab in state.openTabs)
          if (event.sourceIsDirectory &&
              (tab.relativePath == source ||
                  tab.relativePath.startsWith('$source/')))
            tab.copyWith(
              relativePath: destRel + tab.relativePath.substring(source.length),
            )
          else if (!event.sourceIsDirectory && tab.relativePath == source)
            tab.copyWith(relativePath: destRel)
          else
            tab,
      ];
      String? active = state.activeTabPath;
      if (active != null) {
        if (event.sourceIsDirectory &&
            (active == source || active.startsWith('$source/'))) {
          active = destRel + active.substring(source.length);
        } else if (!event.sourceIsDirectory && active == source) {
          active = destRel;
        }
      }

      final index = await _scanWorkspace(root);
      final previousExpansion = state.folderExpansion;
      final nextExpansion = event.sourceIsDirectory
          ? CodingFolderExpansion.movePrefix(
              remembered: previousExpansion,
              from: source,
              to: destRel,
            )
          : null;
      emit(
        state.copyWith(
          index: index,
          openTabs: nextTabs,
          activeTabPath: active,
          clearActiveTab: active == null,
          folderExpansion: nextExpansion,
          workspaceStatusMessage: '移動: $source → $destRel',
          clearError: true,
        ),
      );
      await _persistMovedFolderExpansion(
        workspaceRoot: root,
        previous: previousExpansion,
        next: nextExpansion,
        emit: emit,
      );
    } catch (e) {
      emit(state.copyWith(errorMessage: '移動失敗: $e'));
    }
  }

  Future<void> _onRenamePath(
    CodingAssistRenamePathRequested event,
    Emitter<CodingAssistState> emit,
  ) async {
    final root = state.workspaceRoot;
    if (root == null) return;
    final source = event.relativePath.replaceAll('\\', '/').trim();
    if (source.isEmpty) return;
    final newName = _sanitizeEntryName(event.newName);
    if (newName == null) {
      emit(state.copyWith(errorMessage: '名前が不正です'));
      return;
    }
    final parent = _normalizeRelDir(p.dirname(source));
    final destRel = parent.isEmpty ? newName : '$parent/$newName';
    if (source == destRel) return;

    final srcAbs = p.join(root, source);
    final destAbs = p.join(root, destRel);
    try {
      if (await File(destAbs).exists() || await Directory(destAbs).exists()) {
        emit(state.copyWith(errorMessage: '同名が既にあります: $destRel'));
        return;
      }
      if (event.isDirectory) {
        await Directory(srcAbs).rename(destAbs);
      } else {
        await File(srcAbs).rename(destAbs);
      }

      final nextTabs = <CodingOpenTab>[
        for (final tab in state.openTabs)
          if (event.isDirectory &&
              (tab.relativePath == source ||
                  tab.relativePath.startsWith('$source/')))
            tab.copyWith(
              relativePath: destRel + tab.relativePath.substring(source.length),
            )
          else if (!event.isDirectory && tab.relativePath == source)
            tab.copyWith(relativePath: destRel)
          else
            tab,
      ];
      String? active = state.activeTabPath;
      if (active != null) {
        if (event.isDirectory &&
            (active == source || active.startsWith('$source/'))) {
          active = destRel + active.substring(source.length);
        } else if (!event.isDirectory && active == source) {
          active = destRel;
        }
      }

      final index = await _scanWorkspace(root);
      final previousExpansion = state.folderExpansion;
      final nextExpansion = event.isDirectory
          ? CodingFolderExpansion.movePrefix(
              remembered: previousExpansion,
              from: source,
              to: destRel,
            )
          : null;
      emit(
        state.copyWith(
          index: index,
          openTabs: nextTabs,
          activeTabPath: active,
          clearActiveTab: active == null,
          folderExpansion: nextExpansion,
          workspaceStatusMessage: 'Rename: $source → $destRel',
          clearError: true,
        ),
      );
      await _persistMovedFolderExpansion(
        workspaceRoot: root,
        previous: previousExpansion,
        next: nextExpansion,
        emit: emit,
      );
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Rename 失敗: $e'));
    }
  }

  Future<void> _onDeletePath(
    CodingAssistDeletePathRequested event,
    Emitter<CodingAssistState> emit,
  ) async {
    final root = state.workspaceRoot;
    if (root == null) return;
    final rel = event.relativePath.replaceAll('\\', '/').trim();
    if (rel.isEmpty) return;
    final abs = p.join(root, rel);
    try {
      if (event.isDirectory) {
        final dir = Directory(abs);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      } else {
        final file = File(abs);
        if (await file.exists()) {
          await file.delete();
        }
      }

      final nextTabs = state.openTabs.where((tab) {
        if (event.isDirectory) {
          return tab.relativePath != rel &&
              !tab.relativePath.startsWith('$rel/');
        }
        return tab.relativePath != rel;
      }).toList();
      String? active = state.activeTabPath;
      if (active != null) {
        final removed = event.isDirectory
            ? (active == rel || active.startsWith('$rel/'))
            : active == rel;
        if (removed) {
          active = nextTabs.isEmpty ? null : nextTabs.last.relativePath;
        }
      }

      final index = await _scanWorkspace(root);
      final previousExpansion = state.folderExpansion;
      final nextExpansion = event.isDirectory
          ? CodingFolderExpansion.removePrefix(
              remembered: previousExpansion,
              directory: rel,
            )
          : null;
      emit(
        state.copyWith(
          index: index,
          openTabs: nextTabs,
          activeTabPath: active,
          clearActiveTab: active == null,
          folderExpansion: nextExpansion,
          workspaceStatusMessage: 'Delete: $rel',
          clearError: true,
        ),
      );
      await _persistMovedFolderExpansion(
        workspaceRoot: root,
        previous: previousExpansion,
        next: nextExpansion,
        emit: emit,
      );
    } catch (e) {
      emit(state.copyWith(errorMessage: 'Delete 失敗: $e'));
    }
  }

  Future<void> _onGitAdd(
    CodingAssistGitAddRequested event,
    Emitter<CodingAssistState> emit,
  ) async {
    final root = state.workspaceRoot;
    if (root == null) return;
    try {
      await CodingGit.add(
        workspaceRoot: root,
        relativePath: event.relativePath,
      );
      emit(
        state.copyWith(
          workspaceStatusMessage: 'git add: ${event.relativePath}',
          clearError: true,
        ),
      );
    } on CodingGitException catch (e) {
      emit(state.copyWith(errorMessage: e.message));
    } catch (e) {
      emit(state.copyWith(errorMessage: 'git add 失敗: $e'));
    }
  }

  static String _normalizeRelDir(String raw) {
    var s = raw.replaceAll('\\', '/').trim();
    if (s == '.' || s == '/') return '';
    while (s.startsWith('./')) {
      s = s.substring(2);
    }
    if (s.endsWith('/')) s = s.substring(0, s.length - 1);
    if (s == '.') return '';
    return s;
  }

  /// パス区切りや `..` を含まない単一セグメント名のみ許可。
  static String? _sanitizeEntryName(String raw) {
    final name = raw.trim();
    if (name.isEmpty) return null;
    if (name.contains('/') || name.contains('\\')) return null;
    if (name == '.' || name == '..') return null;
    if (name.contains('..')) return null;
    return name;
  }
}

enum _CodingReproposeKind {
  generic,
  addExists,
  addOrEmpty,
  addReviseExisting,
  addChooseNewPath,
}

// uuid package may not exist - use simple id if needed
class Uuid {
  const Uuid();
  String v4() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String h(int b) => b.toRadixString(16).padLeft(2, '0');
    final b = bytes.map(h).join();
    return '${b.substring(0, 8)}-${b.substring(8, 12)}-${b.substring(12, 16)}-'
        '${b.substring(16, 20)}-${b.substring(20, 32)}';
  }
}
