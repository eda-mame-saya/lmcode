import 'package:equatable/equatable.dart';

import '../../../api_settings/domain/entities/custom_llm_model.dart';
import '../../domain/coding_auto_sleep.dart';
import '../../domain/coding_harness_settings.dart';
import '../../domain/coding_patch.dart';
import '../../domain/coding_prompt_action.dart';
import '../../domain/coding_ui_font_sizes.dart';
import '../../domain/entities/coding_assist_entities.dart';

sealed class CodingAssistEvent extends Equatable {
  const CodingAssistEvent();

  @override
  List<Object?> get props => [];
}

final class CodingAssistStarted extends CodingAssistEvent {
  const CodingAssistStarted();
}

final class CodingAssistOpenWorkspaceRequested extends CodingAssistEvent {
  const CodingAssistOpenWorkspaceRequested(this.rootPath);
  final String rootPath;

  @override
  List<Object?> get props => [rootPath];
}

final class CodingAssistOpenFileRequested extends CodingAssistEvent {
  const CodingAssistOpenFileRequested(
    this.relativePath, {
    this.revealLine,
    this.revealOffset,
    this.revealLength,
  });
  final String relativePath;

  /// 1-based。指定時は開いたあと該当行へスクロールする。
  final int? revealLine;

  /// 行内オフセット（0-based）。[revealLength] と併用で一致箇所を選択。
  final int? revealOffset;
  final int? revealLength;

  @override
  List<Object?> get props => [
    relativePath,
    revealLine,
    revealOffset,
    revealLength,
  ];
}

final class CodingAssistRevealLineConsumed extends CodingAssistEvent {
  const CodingAssistRevealLineConsumed();
}

/// 左メニューでファイル位置を選択・祖先フォルダを展開する。
final class CodingAssistRevealInTreeRequested extends CodingAssistEvent {
  const CodingAssistRevealInTreeRequested(this.relativePath);
  final String relativePath;

  @override
  List<Object?> get props => [relativePath];
}

final class CodingAssistRevealInTreeConsumed extends CodingAssistEvent {
  const CodingAssistRevealInTreeConsumed();
}

final class CodingAssistCloseTabRequested extends CodingAssistEvent {
  const CodingAssistCloseTabRequested(this.relativePath);
  final String relativePath;

  @override
  List<Object?> get props => [relativePath];
}

final class CodingAssistSelectTabRequested extends CodingAssistEvent {
  const CodingAssistSelectTabRequested(this.relativePath);
  final String relativePath;

  @override
  List<Object?> get props => [relativePath];
}

final class CodingAssistTabContentChanged extends CodingAssistEvent {
  const CodingAssistTabContentChanged({
    required this.relativePath,
    required this.content,
  });
  final String relativePath;
  final String content;

  @override
  List<Object?> get props => [relativePath, content];
}

final class CodingAssistSaveTabRequested extends CodingAssistEvent {
  const CodingAssistSaveTabRequested(this.relativePath);
  final String relativePath;

  @override
  List<Object?> get props => [relativePath];
}

final class CodingAssistDraftChanged extends CodingAssistEvent {
  const CodingAssistDraftChanged(this.value);
  final String value;

  @override
  List<Object?> get props => [value];
}

final class CodingAssistSendRequested extends CodingAssistEvent {
  const CodingAssistSendRequested();
}

final class CodingAssistStopRequested extends CodingAssistEvent {
  const CodingAssistStopRequested();
}

final class CodingAssistApplyPatchRequested extends CodingAssistEvent {
  const CodingAssistApplyPatchRequested(this.patchId);
  final String patchId;

  @override
  List<Object?> get props => [patchId];
}

/// Add File 提案の人手承認（機械的にファイル作成）。
final class CodingAssistApproveCreateFileRequested extends CodingAssistEvent {
  const CodingAssistApproveCreateFileRequested(this.patchId);
  final String patchId;

  @override
  List<Object?> get props => [patchId];
}

final class CodingAssistRejectPatchRequested extends CodingAssistEvent {
  const CodingAssistRejectPatchRequested(this.patchId);
  final String patchId;

  @override
  List<Object?> get props => [patchId];
}

/// 人手置換／挿入／自動適用／作成のあと、カードを消さず applied にする。
final class CodingAssistMarkPatchAppliedRequested extends CodingAssistEvent {
  const CodingAssistMarkPatchAppliedRequested(this.patchId);
  final String patchId;

  @override
  List<Object?> get props => [patchId];
}

/// 適用失敗したパッチを、現状ファイルを正として Agent に再提案させる。
final class CodingAssistReproposePatchRequested extends CodingAssistEvent {
  const CodingAssistReproposePatchRequested(this.patchId);
  final String patchId;

  @override
  List<Object?> get props => [patchId];
}

/// 既存ファイルへの作成案で、修正か別パス作成かを選ぶ。
final class CodingAssistAddFileConflictChoiceRequested
    extends CodingAssistEvent {
  const CodingAssistAddFileConflictChoiceRequested(this.patchId, this.choice);
  final String patchId;
  final CodingAddFileConflictChoice choice;

  @override
  List<Object?> get props => [patchId, choice];
}

final class CodingAssistNewThreadRequested extends CodingAssistEvent {
  const CodingAssistNewThreadRequested();
}

final class CodingAssistSelectionAttached extends CodingAssistEvent {
  const CodingAssistSelectionAttached(this.selection);
  final CodingAttachedSelection selection;

  @override
  List<Object?> get props => [
    selection.relativePath,
    selection.startLine,
    selection.endLine,
    selection.selectedText,
  ];
}

final class CodingAssistSelectionCleared extends CodingAssistEvent {
  const CodingAssistSelectionCleared();
}

/// フォルダ配下のファイル本文を、送信前の取り込みにする。
final class CodingAssistFolderFilesAttachRequested extends CodingAssistEvent {
  const CodingAssistFolderFilesAttachRequested(this.relativePath);
  final String relativePath;

  @override
  List<Object?> get props => [relativePath];
}

/// フォルダ構造を送信前の付与項目にする（下書きには書かない）。
final class CodingAssistFolderStructureAttached extends CodingAssistEvent {
  const CodingAssistFolderStructureAttached(this.structure);
  final CodingAttachedFolderStructure structure;

  @override
  List<Object?> get props => [structure.relativePath, structure.block];
}

final class CodingAssistFolderStructureRemoved extends CodingAssistEvent {
  const CodingAssistFolderStructureRemoved(this.relativePath);
  final String relativePath;

  @override
  List<Object?> get props => [relativePath];
}

/// 開いているファイルを送信前取り込み（下書きには書かない）。
final class CodingAssistOpenFilesAttached extends CodingAssistEvent {
  const CodingAssistOpenFilesAttached(this.files);
  final List<CodingAttachedOpenFile> files;

  @override
  List<Object?> get props => [
    for (final f in files) '${f.relativePath}:${f.content.length}',
  ];
}

final class CodingAssistOpenFileAttachmentRemoved extends CodingAssistEvent {
  const CodingAssistOpenFileAttachmentRemoved(this.relativePath);
  final String relativePath;

  @override
  List<Object?> get props => [relativePath];
}

final class CodingAssistOpenFileAttachmentsCleared extends CodingAssistEvent {
  const CodingAssistOpenFileAttachmentsCleared();
}

/// 取り込みファイル（無ければ [fallbackActiveFile]）を分析して説明させる。
final class CodingAssistProgramAnalyzeRequested extends CodingAssistEvent {
  const CodingAssistProgramAnalyzeRequested({
    required this.prompt,
    this.fallbackActiveFile,
  });

  /// 分析指示（ユーザー下書き＋定型指示）。
  final String prompt;

  /// 取り込みが空のとき、エディタ表示中のファイルをここに渡す。
  final CodingAttachedOpenFile? fallbackActiveFile;

  @override
  List<Object?> get props => [
    prompt,
    fallbackActiveFile?.relativePath,
    fallbackActiveFile?.content.length,
  ];
}

final class CodingAssistEditLastUserRequested extends CodingAssistEvent {
  const CodingAssistEditLastUserRequested();
}

/// 直近の user メッセージを同じ内容で再生成（以降の応答は切り捨て）。
final class CodingAssistRerunLastUserRequested extends CodingAssistEvent {
  const CodingAssistRerunLastUserRequested();
}

final class CodingAssistRevokeLastTurnRequested extends CodingAssistEvent {
  const CodingAssistRevokeLastTurnRequested();
}

final class CodingAssistCodingModelChanged extends CodingAssistEvent {
  const CodingAssistCodingModelChanged(this.customModel);

  final CustomLlmModel customModel;

  @override
  List<Object?> get props => [customModel.id, customModel.ggufFileName];
}

/// S16 からコーディング用 thinking を切替（S11 と同じ設定キーへ永続・サーバー再起動）。
final class CodingAssistCodingThinkingChanged extends CodingAssistEvent {
  const CodingAssistCodingThinkingChanged(this.enabled);
  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}

/// S16 ツールバーの Agent自動実行（変更案の自動適用）。llama-server は再起動しない。
final class CodingAssistAgentAutoRunChanged extends CodingAssistEvent {
  const CodingAssistAgentAutoRunChanged(this.enabled);
  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}

/// 自動実行後のスリープ設定。開始は自動実行が始まったとき。
final class CodingAssistAutoSleepSettingsChanged extends CodingAssistEvent {
  const CodingAssistAutoSleepSettingsChanged(this.settings);
  final CodingAutoSleepSettings settings;

  @override
  List<Object?> get props => [
    settings.sleepWhenFinished,
    settings.sleepAfterMinutes,
  ];
}

/// 自動実行中でも、スリープ予定だけを止める。Agent の生成は止めない。
final class CodingAssistAutoSleepCancelled extends CodingAssistEvent {
  const CodingAssistAutoSleepCancelled();
}

/// 指定時間に達した。生成中でなければここからスリープする。
final class CodingAssistAutoSleepDeadlineReached extends CodingAssistEvent {
  const CodingAssistAutoSleepDeadlineReached();
}

/// S16 メニュー／エディタ／Agent の表示フォントサイズ。
/// S16 歯車のハーネス定数。次の送信から使う。
final class CodingAssistHarnessChanged extends CodingAssistEvent {
  const CodingAssistHarnessChanged(this.settings);

  final CodingHarnessSettings settings;

  @override
  List<Object?> get props => [settings];
}

final class CodingAssistUiFontSizesChanged extends CodingAssistEvent {
  const CodingAssistUiFontSizesChanged(this.sizes);
  final CodingUiFontSizes sizes;

  @override
  List<Object?> get props => [sizes.menu, sizes.editor, sizes.agent];
}

/// エディタのインデント幅（空白 2 または 4）。
final class CodingAssistIndentSizeChanged extends CodingAssistEvent {
  const CodingAssistIndentSizeChanged(this.indentSize);
  final int indentSize;

  @override
  List<Object?> get props => [indentSize];
}

/// プロンプト補助のお気に入り登録／解除（最大2）。
final class CodingAssistPromptFavoriteToggled extends CodingAssistEvent {
  const CodingAssistPromptFavoriteToggled(this.action);
  final CodingPromptAction action;

  @override
  List<Object?> get props => [action];
}

/// 直近のタスク分解を新しい会話へ移して評価する。
final class CodingAssistTaskEvaluateRequested extends CodingAssistEvent {
  const CodingAssistTaskEvaluateRequested();
}

/// プロンプト補助の適用／解除。送信はしない。
final class CodingAssistPromptActionToggled extends CodingAssistEvent {
  const CodingAssistPromptActionToggled(this.action);
  final CodingPromptAction action;

  @override
  List<Object?> get props => [action];
}

/// Agent コンテキストの手動圧縮（§5.7 P1）。
final class CodingAssistCompactContextRequested extends CodingAssistEvent {
  const CodingAssistCompactContextRequested();
}

final class CodingAssistErrorConsumed extends CodingAssistEvent {
  const CodingAssistErrorConsumed();
}

final class CodingAssistRefreshWorkspaceRequested extends CodingAssistEvent {
  const CodingAssistRefreshWorkspaceRequested();
}

/// アクティブタブのみディスクから再読込（未保存は破棄）。索引の再走査はしない。
final class CodingAssistReloadActiveTabFromDiskRequested
    extends CodingAssistEvent {
  const CodingAssistReloadActiveTabFromDiskRequested();
}

/// ⌘N。名前は聞かず、同階層の `Untitled-N`（拡張子なし）を作って開く。
final class CodingAssistCreateUntitledFileRequested extends CodingAssistEvent {
  const CodingAssistCreateUntitledFileRequested({
    required this.parentRelativeDir,
  });

  /// 空文字ならワークスペース直下。
  final String parentRelativeDir;

  @override
  List<Object?> get props => [parentRelativeDir];
}

final class CodingAssistCreateFileRequested extends CodingAssistEvent {
  const CodingAssistCreateFileRequested({
    required this.parentRelativeDir,
    required this.name,
  });

  /// 空文字ならワークスペース直下。
  final String parentRelativeDir;
  final String name;

  @override
  List<Object?> get props => [parentRelativeDir, name];
}

final class CodingAssistCreateFolderRequested extends CodingAssistEvent {
  const CodingAssistCreateFolderRequested({
    required this.parentRelativeDir,
    required this.name,
  });

  final String parentRelativeDir;
  final String name;

  @override
  List<Object?> get props => [parentRelativeDir, name];
}

final class CodingAssistMovePathRequested extends CodingAssistEvent {
  const CodingAssistMovePathRequested({
    required this.sourceRelativePath,
    required this.sourceIsDirectory,
    required this.targetDirectoryRelativePath,
  });

  final String sourceRelativePath;
  final bool sourceIsDirectory;

  /// ドロップ先フォルダ。空文字ならルート。
  final String targetDirectoryRelativePath;

  @override
  List<Object?> get props => [
    sourceRelativePath,
    sourceIsDirectory,
    targetDirectoryRelativePath,
  ];
}

final class CodingAssistRenamePathRequested extends CodingAssistEvent {
  const CodingAssistRenamePathRequested({
    required this.relativePath,
    required this.isDirectory,
    required this.newName,
  });

  final String relativePath;
  final bool isDirectory;
  final String newName;

  @override
  List<Object?> get props => [relativePath, isDirectory, newName];
}

final class CodingAssistDeletePathRequested extends CodingAssistEvent {
  const CodingAssistDeletePathRequested({
    required this.relativePath,
    required this.isDirectory,
  });

  final String relativePath;
  final bool isDirectory;

  @override
  List<Object?> get props => [relativePath, isDirectory];
}

final class CodingAssistGitAddRequested extends CodingAssistEvent {
  const CodingAssistGitAddRequested({required this.relativePath});

  final String relativePath;

  @override
  List<Object?> get props => [relativePath];
}

/// Agent 下書きへテキストを追記（フォルダ構造コピー等）。
final class CodingAssistAppendDraftRequested extends CodingAssistEvent {
  const CodingAssistAppendDraftRequested(this.text);
  final String text;

  @override
  List<Object?> get props => [text];
}

/// ディスク置換後の本文を開いているタブへ同期（dirty=false）。
final class CodingAssistSyncTabContentsRequested extends CodingAssistEvent {
  const CodingAssistSyncTabContentsRequested(this.contentsByRelativePath);

  final Map<String, String> contentsByRelativePath;

  @override
  List<Object?> get props => [contentsByRelativePath];
}

/// いま見えているフォルダの展開／折りたたみを記録する。
final class CodingAssistFolderExpansionCaptured extends CodingAssistEvent {
  const CodingAssistFolderExpansionCaptured({
    required this.workspaceRoot,
    required this.visible,
  });

  final String workspaceRoot;

  /// 相対パス → 展開しているか。見えていないパスは含めない。
  final Map<String, bool> visible;

  @override
  List<Object?> get props => [
    workspaceRoot,
    visible.entries.map((e) => '${e.key}=${e.value ? 1 : 0}').join('\n'),
  ];
}

/// 最近開いたフォルダ一覧から特定パスを削除する。
final class CodingAssistRemoveRecentWorkspaceRequested
    extends CodingAssistEvent {
  const CodingAssistRemoveRecentWorkspaceRequested(this.rootPath);
  final String rootPath;

  @override
  List<Object?> get props => [rootPath];
}
