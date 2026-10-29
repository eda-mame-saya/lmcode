import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';

import '../../../../injection.dart';
import '../../../../routes.dart';
import '../../../../theme.dart';
import '../widget/coding_markdown.dart';
import '../../../api_settings/data/datasources/custom_llm_models_local_datasource.dart';
import '../../../api_settings/domain/entities/custom_llm_model.dart';
import '../../../api_settings/domain/entities/local_llm_connection_settings.dart';
import '../../../generative_ai/domain/gemma_mtp_draft.dart';
import '../../../api_settings/domain/usecases/get_connection_settings.dart';
import '../../../oss_licenses/presentation/open_oss_licenses_page.dart';
import '../../../../core/theme/app_color_tokens.dart';
import '../../../../core/theme/app_theme_controller.dart';
import '../../../../core/widgets/app_color_picker_dialog.dart';
import '../../../../core/widgets/brand_confirm_dialog.dart';
import '../../domain/coding_auto_sleep.dart';
import '../../domain/coding_debug_exchange.dart';
import '../../domain/coding_harness_settings.dart';
import '../../domain/coding_dart_definition.dart';
import '../../domain/coding_editor_file_link.dart';
import '../../domain/coding_editor_split.dart';
import '../../domain/coding_file_tree.dart';
import '../../domain/coding_folder_expansion.dart';
import '../../domain/coding_user_history_view.dart';
import '../../domain/coding_git.dart';
import '../../domain/coding_indent_aligner.dart';
import '../../domain/coding_patch.dart';
import '../../domain/coding_prompt_action.dart';
import '../../domain/coding_task_evaluation.dart';
import '../../domain/coding_ui_font_sizes.dart';
import '../../domain/coding_unsaved_editor.dart';
import '../../domain/coding_workspace_search.dart';
import '../../domain/entities/coding_assist_entities.dart';
import '../bloc/coding_assist_bloc.dart';
import '../coding_symbol_gateway.dart';
import '../coding_tab_editors.dart';
import '../prompt/coding_assist_prompts.dart';
import '../widget/coding_dart_completion.dart';
import '../widget/coding_swift_lsp.dart';
import '../widget/coding_dart_definition_balloon.dart';
import '../widget/coding_find_panel.dart';
import '../widget/coding_markup_preview.dart';
import '../widget/coding_minimap.dart';
import '../widget/coding_ram_usage_indicator.dart';
import '../widget/coding_shortcuts.dart';
import '../widget/coding_syntax.dart';
import '../widget/coding_terminal_panel.dart';
import '../widget/coding_user_prompt_preview.dart';

part '../widget/coding_assist_chat_pane.dart';
part '../widget/coding_assist_dialogs.dart';
part '../widget/coding_assist_settings_dialog.dart';
part '../widget/coding_assist_editor_pane.dart';
part '../widget/coding_assist_file_tree.dart';
part '../widget/coding_assist_patch_card.dart';
part '../widget/coding_assist_prompt_actions.dart';
part '../widget/coding_assist_status_bar.dart';
part '../widget/coding_assist_toolbar.dart';

class _AlignIndentIntent extends Intent {
  const _AlignIndentIntent();
}

class _WorkspaceSearchIntent extends Intent {
  const _WorkspaceSearchIntent();
}

class _CloseEditorTabIntent extends Intent {
  const _CloseEditorTabIntent();
}

class _ToggleAgentIntent extends Intent {
  const _ToggleAgentIntent();
}

/// エディタ選択、なければキャレット位置の識別子または記号列を検索語にする。
String? codingAssistEditorSearchQuery(CodeLineEditingController controller) {
  if (!controller.selection.isCollapsed) {
    final selected = controller.selectedText.trim();
    if (selected.isEmpty) return null;
    // 複数行選択は先頭行だけ（フォルダ検索は1語想定）
    final firstLine = selected.split('\n').first.trim();
    return firstLine.isEmpty ? null : firstLine;
  }
  final index = controller.selection.baseIndex;
  if (index < 0 || index >= controller.codeLines.length) return null;
  final line = controller.codeLines[index].text;
  final offset = controller.selection.baseOffset.clamp(0, line.length);
  return _searchTokenAt(line, offset);
}

/// 検索語が空白以外の記号を含むか（識別子だけなら false）。
bool codingAssistSearchQueryHasSymbol(String query) {
  for (final c in query.codeUnits) {
    if (!_isSearchIdent(c) && !_isSearchSpace(c)) return true;
  }
  return false;
}

/// キャレット位置の識別子、または連続する記号（`=>` `.` `?.` など）。
///
/// 空白で区切る。識別子の途中では記号まで伸ばさない。
/// 記号の上では直前の識別子へ戻さず、その記号列を返す。
String? _searchTokenAt(String line, int offset) {
  if (line.isEmpty) return null;
  var i = offset;
  var kind = _searchCharKind(line, i);
  if (kind == _SearchCharKind.other) {
    kind = _searchCharKind(line, i - 1);
    if (kind == _SearchCharKind.other) return null;
    i--;
  }
  var start = i;
  while (start > 0 && _searchCharKind(line, start - 1) == kind) {
    start--;
  }
  var end = i + 1;
  while (end < line.length && _searchCharKind(line, end) == kind) {
    end++;
  }
  final word = line.substring(start, end);
  return word.isEmpty ? null : word;
}

enum _SearchCharKind { ident, symbol, other }

_SearchCharKind _searchCharKind(String line, int index) {
  if (index < 0 || index >= line.length) return _SearchCharKind.other;
  final c = line.codeUnitAt(index);
  if (_isSearchIdent(c)) return _SearchCharKind.ident;
  if (_isSearchSpace(c)) return _SearchCharKind.other;
  return _SearchCharKind.symbol;
}

bool _isSearchIdent(int c) =>
    (c >= 0x41 && c <= 0x5a) ||
    (c >= 0x61 && c <= 0x7a) ||
    (c >= 0x30 && c <= 0x39) ||
    c == 0x5f ||
    c == 0x24; // $

bool _isSearchSpace(int c) => String.fromCharCode(c).trim().isEmpty;

class CodingAssistPage extends StatelessWidget {
  const CodingAssistPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          getIt<CodingAssistBloc>()..add(const CodingAssistStarted()),
      child: const _CodingAssistView(),
    );
  }
}

class _CodingAssistView extends StatefulWidget {
  const _CodingAssistView();

  @override
  State<_CodingAssistView> createState() => _CodingAssistViewState();
}

class _CodingAssistViewState extends State<_CodingAssistView> {
  static const _agentWidthMin = 290.0;
  static const _agentWidthMax = 720.0;
  static const _agentWidthDefault = 360.0;
  static const _agentCollapsedWidth = 20.0;

  final _draftController = TextEditingController();
  late final CodingTabEditors _tabs = CodingTabEditors(
    onSelectionChanged: _onEditorSelectionChanged,
  );
  CodeLineEditingController get _editorController => _tabs.active;
  CodeFindController get _findController => _tabs.findController;
  final _leftMenuKey = GlobalKey<_LeftMenuPaneState>();
  final _editorPaneKey = GlobalKey<_EditorPaneState>();
  final _dartLsp = CodingDartLspController();
  final _swiftLsp = CodingSwiftLspController();
  late final CodingSymbolGateway _symbolGateway = CodingSymbolGateway(
    dart: _dartLsp,
    swift: _swiftLsp,
  );
  String? _lspBoundWorkspace;
  List<CustomLlmModel> _customModels = const [];
  bool _applyingEditorText = false;
  bool _agentCollapsed = false;
  bool _leftMenuCollapsed = false;
  bool _minimapCollapsed = false;
  double _agentWidth = _agentWidthDefault;
  bool _hasEditorSelection = false;
  int _boundDraftEpoch = 0;
  bool _allowPop = false;
  bool _leaveCheckOpen = false;
  static const _leftMenuWidth = 280.0;
  static const _leftMenuCollapsedWidth = 20.0;

  @override
  void initState() {
    super.initState();
    _loadCustomModels();
    _dartLsp.addListener(_onDartLspChanged);
    _swiftLsp.addListener(_onDartLspChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    context.read<CodingAssistBloc>().symbolIndex = _symbolGateway;
  }

  void _rebindEditorIndent(int indentSize) {
    _tabs.rebindIndent(indentSize);
  }

  void _replaceEditorText(CodeLineEditingController controller, String text) {
    _applyingEditorText = true;
    controller.text = text;
    _applyingEditorText = false;
  }

  void _retireEditorsAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tabs.disposeRetired();
    });
  }

  void _alignIndent() {
    final path = context.read<CodingAssistBloc>().state.activeTabPath;
    if (path == null) return;
    _alignIndentOf(path, _editorController);
  }

  void _alignIndentOf(String path, CodeLineEditingController controller) {
    final state = context.read<CodingAssistBloc>().state;
    final sel = controller.selection;
    final text = controller.text;
    final next = sel.isCollapsed
        ? CodingIndentAligner.align(
            text,
            indentSize: state.indentSize,
            relativePath: path,
          )
        : CodingIndentAligner.align(
            text,
            indentSize: state.indentSize,
            relativePath: path,
            startLineIndex: sel.startIndex,
            endLineIndex: sel.endIndex,
          );
    if (next == text) return;
    _applyingEditorText = true;
    controller.text = next;
    _applyingEditorText = false;
    context.read<CodingAssistBloc>().add(
      CodingAssistTabContentChanged(relativePath: path, content: next),
    );
  }

  void _onDartLspChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _syncDartLsp(CodingAssistState state) async {
    final root = state.workspaceRoot?.trim();
    if (root == null || root.isEmpty) {
      if (_lspBoundWorkspace != null) {
        _lspBoundWorkspace = null;
        await _dartLsp.detach();
        await _swiftLsp.detach();
      }
      return;
    }
    if (_lspBoundWorkspace == root) return;
    _lspBoundWorkspace = root;
    final settings = await getIt<GetConnectionSettings>()();
    if (!mounted) return;
    await _dartLsp.attachWorkspace(
      workspaceRoot: root,
      dartSdkPathSetting: settings.dartSdkPath,
    );
    if (!mounted) return;
    await _swiftLsp.attachWorkspace(workspaceRoot: root);
  }

  void _onEditorSelectionChanged() {
    final has =
        !_editorController.selection.isCollapsed &&
        _editorController.selectedText.isNotEmpty;
    if (has != _hasEditorSelection) {
      setState(() => _hasEditorSelection = has);
    }
  }

  Future<void> _openEngineSettings(BuildContext context) async {
    await context.push<bool>(AppRoutes.apiKeys);
    if (!mounted) return;
    // S11 でモデル／SDK が変わっている可能性があるので戻ったら再同期する。
    _lspBoundWorkspace = null;
    await _loadCustomModels();
    if (!context.mounted) return;
    context.read<CodingAssistBloc>().add(const CodingAssistStarted());
  }

  Future<void> _loadCustomModels() async {
    try {
      final list = await getIt<CustomLlmModelsLocalDataSource>().list();
      if (mounted) setState(() => _customModels = list);
    } catch (_) {}
  }

  @override
  void dispose() {
    _dartLsp.removeListener(_onDartLspChanged);
    _dartLsp.dispose();
    _swiftLsp.removeListener(_onDartLspChanged);
    _swiftLsp.dispose();
    _draftController.dispose();
    _tabs.dispose();
    super.dispose();
  }

  void _closeActiveTab() {
    final path =
        _editorPaneKey.currentState?.shortcutClosePath ??
        context.read<CodingAssistBloc>().state.activeTabPath;
    if (path == null) return;
    context.read<CodingAssistBloc>().add(CodingAssistCloseTabRequested(path));
  }

  void _toggleLeftMenu() {
    setState(() => _leftMenuCollapsed = !_leftMenuCollapsed);
  }

  void _toggleAgentPane() {
    setState(() => _agentCollapsed = !_agentCollapsed);
  }

  void _shortcutNewFile() {
    final bloc = context.read<CodingAssistBloc>();
    if (bloc.state.workspaceRoot == null) return;
    final menu = _leftMenuKey.currentState;
    final parent =
        menu?.createParentDirForNewEntry() ??
        _codingCreateParentDir(
          selectedPath: null,
          selectedIsDirectory: false,
          activeTabPath: bloc.state.activeTabPath,
        );
    menu?.expandFolderSection();
    bloc.add(
      CodingAssistCreateUntitledFileRequested(parentRelativeDir: parent),
    );
  }

  void _shortcutFind() {
    final state = context.read<CodingAssistBloc>().state;
    if (state.activeTabPath == null) return;
    final collapsed = _editorController.selection.isCollapsed;
    final query = collapsed
        ? codingAssistEditorSearchQuery(_editorController)
        : null;
    final symbolQuery = query != null && codingAssistSearchQueryHasSymbol(query)
        ? query
        : null;
    _findController.findMode();
    // 選択がないとき re_editor は前回の検索語を残す。記号上ならその列を検索語にする。
    if (symbolQuery != null) {
      _findController.findInputController.value = TextEditingValue(
        text: symbolQuery,
        selection: TextSelection(
          baseOffset: 0,
          extentOffset: symbolQuery.length,
        ),
      );
    }
  }

  void _shortcutSave() {
    final path = context.read<CodingAssistBloc>().state.activeTabPath;
    if (path == null) return;
    context.read<CodingAssistBloc>().add(CodingAssistSaveTabRequested(path));
  }

  void _shortcutWorkspaceSearch() {
    _shortcutWorkspaceSearchFrom(_editorController);
  }

  void _shortcutWorkspaceSearchFrom(CodeLineEditingController controller) {
    final selected = !controller.selection.isCollapsed
        ? controller.selectedText.trim().split('\n').first.trim()
        : '';
    final query = selected.isEmpty ? null : selected;
    _openWorkspaceSearch(query: query, runSearch: query != null);
  }

  /// ⌘クリック: 選択、なければキャレット下の識別子または記号列で検索。
  void _shortcutWorkspaceSearchFromClickOf(
    CodeLineEditingController controller,
  ) {
    final query = codingAssistEditorSearchQuery(controller);
    _openWorkspaceSearch(query: query, runSearch: query != null);
  }

  void _openWorkspaceSearch({String? query, bool runSearch = false}) {
    void invoke() {
      _leftMenuKey.currentState?.openWorkspaceSearch(
        query: query,
        runSearch: runSearch,
      );
    }

    if (_leftMenuCollapsed) {
      setState(() => _leftMenuCollapsed = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        invoke();
      });
      return;
    }
    invoke();
  }

  Map<ShortcutActivator, VoidCallback> _pageShortcutBindings() {
    return {
      const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _shortcutSave,
      const SingleActivator(LogicalKeyboardKey.keyS, control: true):
          _shortcutSave,
      const SingleActivator(LogicalKeyboardKey.keyW, meta: true):
          _closeActiveTab,
      const SingleActivator(LogicalKeyboardKey.keyW, control: true):
          _closeActiveTab,
      const SingleActivator(LogicalKeyboardKey.keyN, meta: true):
          _shortcutNewFile,
      const SingleActivator(LogicalKeyboardKey.keyN, control: true):
          _shortcutNewFile,
      const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _shortcutFind,
      const SingleActivator(LogicalKeyboardKey.keyF, control: true):
          _shortcutFind,
      const SingleActivator(LogicalKeyboardKey.keyF, meta: true, shift: true):
          _shortcutWorkspaceSearch,
      const SingleActivator(
        LogicalKeyboardKey.keyF,
        control: true,
        shift: true,
      ): _shortcutWorkspaceSearch,
      const SingleActivator(LogicalKeyboardKey.keyB, meta: true):
          _toggleLeftMenu,
      const SingleActivator(LogicalKeyboardKey.keyB, control: true):
          _toggleLeftMenu,
      const SingleActivator(LogicalKeyboardKey.keyB, meta: true, shift: true):
          _toggleAgentPane,
      const SingleActivator(
        LogicalKeyboardKey.keyB,
        control: true,
        shift: true,
      ): _toggleAgentPane,
      const SingleActivator(LogicalKeyboardKey.keyL, meta: true, alt: true):
          _alignIndent,
      const SingleActivator(LogicalKeyboardKey.keyL, control: true, alt: true):
          _alignIndent,
    };
  }

  void _attachSelection(BuildContext context) {
    final path = context.read<CodingAssistBloc>().state.activeTabPath;
    if (path == null) return;
    final selection = _editorController.selection;
    if (selection.isCollapsed) return;
    final text = _editorController.selectedText;
    if (text.isEmpty) return;
    context.read<CodingAssistBloc>().add(
      CodingAssistSelectionAttached(
        CodingAttachedSelection(
          relativePath: path,
          startLine: selection.startIndex + 1,
          endLine: selection.endIndex + 1,
          selectedText: text,
        ),
      ),
    );
  }

  /// プログラム分析用。取り込みが空のときのフォールバック（表示中タブ）。
  CodingAttachedOpenFile? _activeEditorAttachment() {
    final path = context.read<CodingAssistBloc>().state.activeTabPath;
    if (path == null) return null;
    return CodingAttachedOpenFile(
      relativePath: path,
      content: _editorController.text,
    );
  }

  /// いま開いているエディタの選択範囲を、提案の新側ソースで機械置換する。
  /// 提案パスとアクティブタブの一致は問わない（Agent のパス誤りでも人手で差し替え可能）。
  Future<void> _replaceSelectionWithProposal(
    BuildContext context,
    CodingProposedPatch patch,
  ) async {
    final bloc = context.read<CodingAssistBloc>();
    final state = bloc.state;
    final active = state.activeTabPath?.replaceAll('\\', '/');
    final proposed = patch.relativePath.replaceAll('\\', '/');
    if (active == null) {
      await showBrandConfirmDialog(
        context: context,
        title: '選択範囲を置換',
        message: '置換先のファイルをタブで開いて、範囲を選択してから押してください',
        cancelLabel: '閉じる',
        confirmLabel: 'OK',
      );
      return;
    }
    final selection = _editorController.selection;
    if (selection.isCollapsed || _editorController.selectedText.isEmpty) {
      await showBrandConfirmDialog(
        context: context,
        title: '選択範囲を置換',
        message: 'いま開いているエディタで、置換したい範囲を選択してから押してください',
        cancelLabel: '閉じる',
        confirmLabel: 'OK',
      );
      return;
    }
    final replacement = codingAssistPatchReplacementBody(patch);
    if (replacement == null || replacement.isEmpty) {
      await showBrandConfirmDialog(
        context: context,
        title: '選択範囲を置換',
        message:
            '提案から置換用の新ソースを取り出せませんでした。'
            'カードの「ソースをコピー」で貼り付けるか、現状で再提案してください',
        cancelLabel: '閉じる',
        confirmLabel: 'OK',
      );
      return;
    }

    _editorController.replaceSelection(replacement);
    _finishEditorPatchApply(
      context,
      bloc: bloc,
      active: active,
      proposed: proposed,
      patchId: patch.id,
      doneLabel: '選択範囲を置換しました',
    );
  }

  /// 新規関数案を、提案行（なければカーソル位置）へ挿入する。
  Future<void> _insertAtCursorWithProposal(
    BuildContext context,
    CodingProposedPatch patch,
  ) async {
    final bloc = context.read<CodingAssistBloc>();
    final state = bloc.state;
    final active = state.activeTabPath?.replaceAll('\\', '/');
    final proposed = patch.relativePath.replaceAll('\\', '/');
    final suggestedLine = patch.suggestedInsertLine;
    if (active == null) {
      await showBrandConfirmDialog(
        context: context,
        title: suggestedLine != null ? '提案行に挿入' : 'カーソル位置に挿入',
        message: suggestedLine != null
            ? '挿入先のファイルをタブで開いてから押してください'
                  '（提案: ${patch.relativePath} の $suggestedLine 行目）'
            : '挿入先のファイルをタブで開き、挿入したい位置にカーソルを置いてから押してください',
        cancelLabel: '閉じる',
        confirmLabel: 'OK',
      );
      return;
    }
    final body = codingAssistPatchReplacementBody(patch);
    if (body == null || body.isEmpty) {
      await showBrandConfirmDialog(
        context: context,
        title: suggestedLine != null ? '提案行に挿入' : 'カーソル位置に挿入',
        message:
            '提案から挿入用のソースを取り出せませんでした。'
            'カードの「ソースをコピー」で貼り付けるか、現状で再提案してください',
        cancelLabel: '閉じる',
        confirmLabel: 'OK',
      );
      return;
    }

    final CodeLineSelection insertAt;
    var insertText = body;
    if (suggestedLine != null && suggestedLine > 0) {
      final lines = _editorController.codeLines;
      final lineCount = lines.length;
      if (lineCount <= 0) {
        insertAt = const CodeLineSelection.collapsed(index: 0, offset: 0);
      } else if (suggestedLine > lineCount) {
        // 提案行が末尾超え → 最終行の末尾へ追記
        final last = lineCount - 1;
        insertAt = CodeLineSelection.collapsed(
          index: last,
          offset: lines[last].length,
        );
        if (!insertText.startsWith('\n')) {
          insertText = '\n$insertText';
        }
      } else {
        insertAt = CodeLineSelection.collapsed(
          index: suggestedLine - 1,
          offset: 0,
        );
      }
      if (!insertText.endsWith('\n')) {
        insertText = '$insertText\n';
      }
    } else {
      // 選択があってもキャレット位置（base）へ挿入し、選択範囲は消さない
      final sel = _editorController.selection;
      insertAt = CodeLineSelection.collapsed(
        index: sel.baseIndex,
        offset: sel.baseOffset,
      );
      if (sel.baseOffset > 0 && !insertText.startsWith('\n')) {
        insertText = '\n$insertText';
      }
      if (!insertText.endsWith('\n')) {
        insertText = '$insertText\n';
      }
    }
    _editorController.replaceSelection(insertText, insertAt);
    _finishEditorPatchApply(
      context,
      bloc: bloc,
      active: active,
      proposed: proposed,
      patchId: patch.id,
      doneLabel: suggestedLine != null
          ? '$suggestedLine 行目へ挿入しました'
          : 'カーソル位置に挿入しました',
    );
  }

  void _finishEditorPatchApply(
    BuildContext context, {
    required CodingAssistBloc bloc,
    required String active,
    required String proposed,
    required String patchId,
    required String doneLabel,
  }) {
    final content = _editorController.text;
    bloc.add(
      CodingAssistTabContentChanged(relativePath: active, content: content),
    );
    // カード適用はエディタ更新に続けてディスクへ保存する。
    bloc.add(CodingAssistSaveTabRequested(active));
    // カードは消さず適用済みとして残す
    bloc.add(CodingAssistMarkPatchAppliedRequested(patchId));
    if (!context.mounted) return;
    final pathNote = active == proposed ? active : '$active（提案パス: $proposed）';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$doneLabel: $pathNote（保存しました）')));
  }

  Future<void> _pickFolder(BuildContext context) async {
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: 'プロジェクトフォルダを選択',
    );
    if (path == null || !context.mounted) return;
    context.read<CodingAssistBloc>().add(
      CodingAssistOpenWorkspaceRequested(path),
    );
  }

  void _syncEditor(CodingAssistState state) {
    _tabs.sync(
      activePath: state.activeTabPath,
      tabs: [
        for (final tab in state.openTabs)
          (path: tab.relativePath, content: tab.content),
      ],
      replaceText: _replaceEditorText,
    );
    _retireEditorsAfterFrame();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CodingAssistBloc, CodingAssistState>(
      // ストリーミング文字だけは Agent 側 BlocBuilder に任せ、画面全体の再構築を避ける
      buildWhen: (p, c) {
        if (p.streamingText != c.streamingText &&
            p.isGenerating == c.isGenerating &&
            p.thread?.id == c.thread?.id &&
            p.thread?.messages.length == c.thread?.messages.length &&
            p.pendingPatches.length == c.pendingPatches.length &&
            p.usedTokens == c.usedTokens &&
            p.warningLevel == c.warningLevel &&
            p.agentStatusMessage == c.agentStatusMessage &&
            p.mtpDraftFileName == c.mtpDraftFileName &&
            p.workspaceStatusMessage == c.workspaceStatusMessage &&
            p.draft == c.draft &&
            p.isLlmBusy == c.isLlmBusy &&
            p.localLlm.codingCustomModelId == c.localLlm.codingCustomModelId &&
            p.localLlm.codingCustomGgufFileName ==
                c.localLlm.codingCustomGgufFileName &&
            p.uiFontSizes == c.uiFontSizes &&
            p.autoSleepSettings == c.autoSleepSettings &&
            p.autoSleepArmed == c.autoSleepArmed &&
            p.autoSleepDeadline == c.autoSleepDeadline &&
            p.indentSize == c.indentSize &&
            p.localLlm.codingThinkingEnabled ==
                c.localLlm.codingThinkingEnabled) {
          return false;
        }
        return true;
      },
      listenWhen: (p, c) =>
          (p.errorMessage != c.errorMessage && c.errorMessage != null) ||
          p.activeTabPath != c.activeTabPath ||
          p.openTabs != c.openTabs ||
          p.draftEpoch != c.draftEpoch ||
          p.indentSize != c.indentSize ||
          p.revealLine != c.revealLine ||
          p.revealOffset != c.revealOffset ||
          p.revealLength != c.revealLength ||
          p.treeRevealPath != c.treeRevealPath ||
          p.workspaceRoot != c.workspaceRoot,
      listener: (context, state) {
        if (state.treeRevealPath != null && _leftMenuCollapsed) {
          setState(() => _leftMenuCollapsed = false);
        }
        // ignore: discarded_futures
        _syncDartLsp(state);
        _rebindEditorIndent(state.indentSize);
        _syncEditor(state);
        if (state.draftEpoch != _boundDraftEpoch) {
          _boundDraftEpoch = state.draftEpoch;
          _draftController.value = TextEditingValue(
            text: state.draft,
            selection: TextSelection.collapsed(offset: state.draft.length),
          );
        }
        final err = state.errorMessage;
        if (err != null) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(err)));
          context.read<CodingAssistBloc>().add(
            const CodingAssistErrorConsumed(),
          );
        }
      },
      builder: (context, state) {
        final splitPath = _editorPaneKey.currentState?.splitPath;
        final splitBuffer = _editorPaneKey.currentState?.splitController?.text;
        final unsaved = codingEditorHasUnsavedChanges(
          tabs: state.openTabs,
          editorPath: _tabs.activePath,
          editorBuffer: _editorController.text,
          secondPath: splitPath,
          secondBuffer: splitBuffer,
        );
        return PopScope(
          canPop: _allowPop || !unsaved,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            _confirmDiscardAndLeave(context);
          },
          child: CallbackShortcuts(
            bindings: _pageShortcutBindings(),
            child: Focus(
              autofocus: true,
              child: Scaffold(
                body: Column(
                  children: [
                    _Toolbar(
                      state: state,
                      customModels: _customModels,
                      onOpenFolder: () => _pickFolder(context),
                      onOpenEngineSettings: () => _openEngineSettings(context),
                    ),
                    Expanded(
                      child: state.isLoading
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const CircularProgressIndicator(),
                                const SizedBox(height: 16),
                                const Text('Agent起動中'),
                              ],
                            )
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                final maxAgent = (_agentWidthMax).clamp(
                                  _agentWidthMin,
                                  constraints.maxWidth * 0.55,
                                );
                                final agentW = _agentCollapsed
                                    ? _agentCollapsedWidth
                                    : _agentWidth.clamp(
                                        _agentWidthMin,
                                        maxAgent,
                                      );
                                return Row(
                                  children: [
                                    SizedBox(
                                      width: _leftMenuCollapsed
                                          ? _leftMenuCollapsedWidth
                                          : _leftMenuWidth,
                                      child: _leftMenuCollapsed
                                          ? _LeftMenuCollapsedStrip(
                                              onExpand: () => setState(
                                                () =>
                                                    _leftMenuCollapsed = false,
                                              ),
                                            )
                                          : _LeftMenuPane(
                                              key: _leftMenuKey,
                                              state: state,
                                              onOpenRecent: (path) => context
                                                  .read<CodingAssistBloc>()
                                                  .add(
                                                    CodingAssistOpenWorkspaceRequested(
                                                      path,
                                                    ),
                                                  ),
                                              onOpenFolder: () =>
                                                  _pickFolder(context),
                                              onCollapse: () => setState(
                                                () => _leftMenuCollapsed = true,
                                              ),
                                            ),
                                    ),
                                    const VerticalDivider(width: 1),
                                    Expanded(
                                      child: _EditorPane(
                                        key: _editorPaneKey,
                                        state: state,
                                        controller: _editorController,
                                        findController: _findController,
                                        dartLsp: _dartLsp,
                                        swiftLsp: _swiftLsp,
                                        minimapCollapsed: _minimapCollapsed,
                                        onToggleMinimap: () => setState(
                                          () => _minimapCollapsed =
                                              !_minimapCollapsed,
                                        ),
                                        onSave: _shortcutSave,
                                        onAlignIndent: _alignIndentOf,
                                        onWorkspaceSearch:
                                            _shortcutWorkspaceSearchFrom,
                                        onWorkspaceSearchFromClick:
                                            _shortcutWorkspaceSearchFromClickOf,
                                        onToggleAgent: _toggleAgentPane,
                                        onChanged: (path, value) {
                                          if (_applyingEditorText) return;
                                          context.read<CodingAssistBloc>().add(
                                            CodingAssistTabContentChanged(
                                              relativePath: path,
                                              content: value,
                                            ),
                                          );
                                        },
                                        controllerFor: (path) {
                                          final tab = state.openTabs
                                              .where(
                                                (item) =>
                                                    item.relativePath == path,
                                              )
                                              .firstOrNull;
                                          if (tab == null) return null;
                                          return _tabs.controllerFor(
                                            path,
                                            tab.content,
                                          );
                                        },
                                      ),
                                    ),
                                    if (!_agentCollapsed)
                                      _AgentResizeHandle(
                                        onDrag: (dx) {
                                          setState(() {
                                            _agentWidth = (_agentWidth - dx)
                                                .clamp(
                                                  _agentWidthMin,
                                                  maxAgent,
                                                );
                                          });
                                        },
                                      )
                                    else
                                      const VerticalDivider(width: 1),
                                    SizedBox(
                                      width: agentW,
                                      child: _agentCollapsed
                                          ? _AgentCollapsedStrip(
                                              onExpand: () => setState(
                                                () => _agentCollapsed = false,
                                              ),
                                            )
                                          : _ChatPane(
                                              draftController: _draftController,
                                              hasEditorSelection:
                                                  _hasEditorSelection,
                                              onAttachSelection: () =>
                                                  _attachSelection(context),
                                              onReplaceSelectionWithProposal:
                                                  (patch) =>
                                                      _replaceSelectionWithProposal(
                                                        context,
                                                        patch,
                                                      ),
                                              onInsertAtCursorWithProposal:
                                                  (patch) =>
                                                      _insertAtCursorWithProposal(
                                                        context,
                                                        patch,
                                                      ),
                                              activeEditorAttachment:
                                                  _activeEditorAttachment,
                                              onCollapse: () => setState(
                                                () => _agentCollapsed = true,
                                              ),
                                            ),
                                    ),
                                  ],
                                );
                              },
                            ),
                    ),
                    _StatusBar(
                      state: state,
                      dartLspStatus: _dartLsp.statusMessage,
                      swiftLspStatus: _swiftLsp.statusMessage,
                      dartServerRunning: _dartLsp.isReady,
                      swiftServerRunning: _swiftLsp.isReady,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDiscardAndLeave(BuildContext context) async {
    if (_leaveCheckOpen || _allowPop) return;
    final state = context.read<CodingAssistBloc>().state;
    final unsaved = codingEditorHasUnsavedChanges(
      tabs: state.openTabs,
      editorPath: _tabs.activePath,
      editorBuffer: _editorController.text,
    );
    if (unsaved) {
      _leaveCheckOpen = true;
      final discard = await showBrandConfirmDialog(
        context: context,
        title: '未保存の変更',
        message: 'エディタに未保存の変更があります。破棄して戻りますか？',
        confirmLabel: '破棄して戻る',
        cancelLabel: 'キャンセル',
        isDestructive: true,
      );
      _leaveCheckOpen = false;
      if (!discard || !context.mounted) return;
    }
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) context.pop();
    });
  }
}
