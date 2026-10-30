part of '../pages/coding_assist_page.dart';

class _EditorPane extends StatefulWidget {
  const _EditorPane({
    super.key,
    required this.state,
    required this.controller,
    required this.findController,
    required this.dartLsp,
    required this.swiftLsp,
    required this.minimapCollapsed,
    required this.onToggleMinimap,
    required this.onSave,
    required this.onAlignIndent,
    required this.onWorkspaceSearch,
    required this.onWorkspaceSearchFromClick,
    required this.onToggleAgent,
    required this.onChanged,
    required this.controllerFor,
  });

  final CodingAssistState state;
  final CodeLineEditingController controller;
  final CodeFindController findController;
  final CodingDartLspController dartLsp;
  final CodingSwiftLspController swiftLsp;
  final bool minimapCollapsed;
  final VoidCallback onToggleMinimap;
  final VoidCallback onSave;
  final void Function(String path, CodeLineEditingController controller)
  onAlignIndent;
  final void Function(CodeLineEditingController controller) onWorkspaceSearch;
  final void Function(CodeLineEditingController controller)
  onWorkspaceSearchFromClick;
  final VoidCallback onToggleAgent;
  final void Function(String path, String value) onChanged;
  final CodeLineEditingController? Function(String path) controllerFor;

  @override
  State<_EditorPane> createState() => _EditorPaneState();
}

class _EditorPaneState extends State<_EditorPane> {
  /// Markdown／マークアップ時のみ有効。タブ切替でリセット。
  bool _previewMode = false;
  bool _terminalCollapsed = true;
  double _terminalHeight = CodingTerminalPanel.heightDefault;
  String? _splitPath;
  final List<String> _rightPaths = [];
  double _splitFraction = 0.5;
  bool _rightMinimapCollapsed = false;
  CodeLineEditingController? _rightController;
  CodeFindController? _rightFind;
  final List<CodeFindController> _retiredRightFinds = [];

  /// 今フレームで CodeEditor に渡しているコントローラ。
  /// 分割で左右を入れ替えるフレームは両方 null にし、破棄後の次フレームで付ける。
  CodeLineEditingController? _shownLeftController;
  CodeLineEditingController? _shownRightController;
  bool _deferEditorMount = false;

  /// このフレームで表示をやめたコントローラ。破棄はフレーム末なので、次のフレームまで付けない。
  final Set<CodeLineEditingController> _releasedControllers = {};
  var _releaseClearScheduled = false;

  /// 右のファイルが選択されたフレームだけ、左に残すパス。
  String? _holdLeft;
  CodeFindController? _holdFind;
  CodeLineEditingController? _holdFindTarget;
  bool _restoreLeftScheduled = false;

  /// 分割ボタンの対象が右のファイルか。右のタブを選んでいるあいだ true。
  bool _selectionOnRight = false;

  /// 右へ移した直後の左切替では、右の選択を維持する。
  bool _retainRightSelection = false;

  CodingAssistState get state => widget.state;
  CodeLineEditingController get controller => widget.controller;
  CodeFindController get findController => widget.findController;
  bool get minimapCollapsed => widget.minimapCollapsed;
  VoidCallback get onToggleMinimap => widget.onToggleMinimap;
  VoidCallback get onSave => widget.onSave;
  void Function(String path, CodeLineEditingController controller)
  get onAlignIndent => widget.onAlignIndent;
  void Function(CodeLineEditingController controller) get onWorkspaceSearch =>
      widget.onWorkspaceSearch;
  void Function(CodeLineEditingController controller)
  get onWorkspaceSearchFromClick => widget.onWorkspaceSearchFromClick;
  VoidCallback get onToggleAgent => widget.onToggleAgent;
  void Function(String path, String value) get onChanged => widget.onChanged;

  @override
  void initState() {
    super.initState();
    _shownLeftController = widget.controller;
  }

  @override
  void didUpdateWidget(covariant _EditorPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    final path = widget.state.activeTabPath;
    final oldPath = oldWidget.state.activeTabPath;
    if (path != oldPath) {
      _previewMode = false;
    } else if (_previewMode && !CodingMarkupPreview.isPreviewablePath(path)) {
      _previewMode = false;
    }
    // 検索ヒット表示時はプレビューを閉じ、エディタで該当箇所を見せる
    if (widget.state.revealLine != null && _previewMode) {
      _previewMode = false;
    }
    _applySplitPolicy(oldWidget);
    _syncHoldFind();
    _syncRightEditor();
    _syncShownEditors();
  }

  /// 左右が同じコントローラを引き継ぐフレームでは CodeEditor を外す。
  void _syncShownEditors() {
    if (_deferEditorMount) return;
    final left = _optionalLeftController;
    final right = splitController;
    _releaseShown(_shownLeftController, left);
    _releaseShown(_shownRightController, right);
    final blocked =
        _releasedControllers.contains(left) ||
        (right != null && _releasedControllers.contains(right));
    if (blocked ||
        CodingEditorSplit.mountConflicts(
          nextLeft: left,
          nextRight: right,
          shownLeft: _shownLeftController,
          shownRight: _shownRightController,
        )) {
      _deferEditorMount = true;
      _markReleased(_shownLeftController);
      _markReleased(_shownRightController);
      _shownLeftController = null;
      _shownRightController = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _deferEditorMount = false;
          _releasedControllers.clear();
          final nextLeft = _optionalLeftController;
          final nextRight = splitController;
          _shownLeftController = nextLeft;
          _shownRightController =
              nextRight != null && identical(nextRight, nextLeft)
              ? null
              : nextRight;
        });
      });
      return;
    }
    _shownLeftController = left;
    _shownRightController = right;
  }

  void _releaseShown(
    CodeLineEditingController? previous,
    CodeLineEditingController? next,
  ) {
    if (previous == null || identical(previous, next)) return;
    _markReleased(previous);
  }

  void _markReleased(CodeLineEditingController? controller) {
    if (controller == null) return;
    _releasedControllers.add(controller);
    if (_releaseClearScheduled) return;
    _releaseClearScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _releasedControllers.clear();
      _releaseClearScheduled = false;
    });
  }

  @override
  void dispose() {
    _disposeRightFind(_rightFind);
    _disposeRightFind(_holdFind);
    for (final find in _retiredRightFinds) {
      find.dispose();
    }
    _retiredRightFinds.clear();
    super.dispose();
  }

  List<String> get _openPaths => [
    for (final tab in state.openTabs) tab.relativePath,
  ];

  /// 左右が別ファイルのときだけ右ペインを出す。
  ///
  /// 右のファイルを選び直したフレームは、左を戻すまで右を出したままにする。
  String? get splitPath {
    final split = _splitPath;
    if (split == null || !_openPaths.contains(split)) return null;
    if (!_rightPaths.contains(split) || _openPaths.length < 2) return null;
    final left = _displayLeftPath;
    if (left != null && left == split) return null;
    return split;
  }

  String? get _displayLeftPath {
    final active = state.activeTabPath;
    if (active == null) return null;
    if (!_rightPaths.contains(active)) return active;
    final hold = _holdLeft;
    if (hold != null &&
        hold != active &&
        _openPaths.contains(hold) &&
        !_rightPaths.contains(hold)) {
      return hold;
    }
    return null;
  }

  bool get _showingHeldLeft {
    final left = _displayLeftPath;
    final active = state.activeTabPath;
    return left != null && active != null && left != active;
  }

  CodeLineEditingController? get _optionalLeftController {
    final path = _displayLeftPath;
    if (path == null) return null;
    if (path == state.activeTabPath) return widget.controller;
    return widget.controllerFor(path);
  }

  CodeFindController get _displayLeftFind {
    if (_showingHeldLeft && _holdFind != null) return _holdFind!;
    return findController;
  }

  CodeLineEditingController? get splitController =>
      splitPath == null ? null : _rightController;

  /// ⌘W。右を選択中ならそのファイル。そうでなければ左。
  String? get shortcutClosePath {
    if (_selectionOnRight) {
      final split = splitPath;
      if (split != null) return split;
    }
    return state.activeTabPath;
  }

  void _applySplitPolicy(_EditorPane oldWidget) {
    final active = widget.state.activeTabPath;
    final paths = _openPaths;
    _rightPaths.removeWhere((path) => !paths.contains(path));
    if (active == null || paths.length < 2 || _rightPaths.isEmpty) {
      _rightPaths.clear();
      _splitPath = null;
      _holdLeft = null;
      _selectionOnRight = false;
      _retainRightSelection = false;
      return;
    }
    final previousShown = _splitPath;
    if (_splitPath == null || !_rightPaths.contains(_splitPath)) {
      _splitPath = _rightPaths.last;
      if (_selectionOnRight && previousShown != _splitPath) {
        _selectionOnRight = false;
      }
    }
    if (_rightPaths.contains(active)) {
      _splitPath = active;
      _selectionOnRight = true;
      final keep = CodingEditorSplit.leftCandidate(
        openPaths: paths,
        rightPaths: _rightPaths,
        prefer: _holdLeft ?? oldWidget.state.activeTabPath,
      );
      _holdLeft = keep;
      if (keep != null) _restoreLeft(keep);
      return;
    }
    if (_retainRightSelection) {
      _retainRightSelection = false;
    } else if (oldWidget.state.activeTabPath != active) {
      _selectionOnRight = false;
    }
    _holdLeft = null;
  }

  void _restoreLeft(String path) {
    if (_restoreLeftScheduled) return;
    _restoreLeftScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreLeftScheduled = false;
      if (!mounted) return;
      if (widget.state.activeTabPath == path) return;
      if (!_rightPaths.contains(widget.state.activeTabPath)) return;
      context.read<CodingAssistBloc>().add(
        CodingAssistSelectTabRequested(path),
      );
    });
  }

  void _syncHoldFind() {
    if (!_showingHeldLeft) {
      _retireHoldFind();
      return;
    }
    final editor = widget.controllerFor(_holdLeft!);
    if (editor == null) {
      _retireHoldFind();
      return;
    }
    if (identical(_holdFindTarget, editor) && _holdFind != null) return;
    _retireHoldFind();
    _holdFindTarget = editor;
    _holdFind = CodeFindController(editor);
  }

  void _retireHoldFind() {
    final find = _holdFind;
    _holdFind = null;
    _holdFindTarget = null;
    if (find == null) return;
    _retiredRightFinds.add(find);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_retiredRightFinds.contains(find)) return;
      _retiredRightFinds.remove(find);
      if (identical(find, _holdFind) || identical(find, _rightFind)) return;
      find.dispose();
    });
  }

  void _syncRightEditor() {
    final split = splitPath;
    if (split == null) {
      _releaseRightEditor();
      return;
    }
    final next = widget.controllerFor(split);
    if (next == null) {
      _releaseRightEditor();
      return;
    }
    if (identical(_rightController, next) && _rightFind != null) return;
    _releaseRightEditor();
    _rightController = next;
    _rightFind = CodeFindController(next);
  }

  void _releaseRightEditor() {
    final find = _rightFind;
    _rightFind = null;
    _rightController = null;
    if (find == null) return;
    _retiredRightFinds.add(find);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_retiredRightFinds.contains(find)) return;
      _retiredRightFinds.remove(find);
      if (identical(find, _rightFind)) return;
      find.dispose();
    });
  }

  void _disposeRightFind(CodeFindController? find) {
    if (find == null) return;
    find.dispose();
  }

  void _toggleSplit() {
    if (_selectionOnRight) {
      final current = splitPath;
      if (current != null) {
        _moveSelectionBackToLeft(current);
        return;
      }
      _selectionOnRight = false;
    }
    final active = _displayLeftPath ?? state.activeTabPath;
    if (active == null || state.openTabs.length < 2) return;
    final next = CodingEditorSplit.moveToRight(
      current: active,
      rightPaths: _rightPaths,
      openPaths: _openPaths,
    );
    if (next == null) return;
    final left = next.left;
    setState(() {
      _rightPaths
        ..clear()
        ..addAll(next.rightPaths);
      _splitPath = next.shown;
      _holdLeft = next.left;
      _selectionOnRight = true;
      _retainRightSelection = left != null && left != active;
      _syncHoldFind();
      _syncRightEditor();
      _syncShownEditors();
    });
    if (left != null && left != active) {
      context.read<CodingAssistBloc>().add(
        CodingAssistSelectTabRequested(left),
      );
    }
  }

  void _moveSelectionBackToLeft(String current) {
    final back = CodingEditorSplit.moveBackToLeft(
      current: current,
      shown: _splitPath,
      rightPaths: _rightPaths,
      openPaths: _openPaths,
    );
    if (back == null) return;
    setState(() {
      _rightPaths
        ..clear()
        ..addAll(back.rightPaths);
      _splitPath = back.shown;
      _selectionOnRight = false;
      _retainRightSelection = false;
      _holdLeft = null;
      _syncHoldFind();
      _syncRightEditor();
      _syncShownEditors();
    });
    context.read<CodingAssistBloc>().add(
      CodingAssistSelectTabRequested(current),
    );
  }

  Future<void> _showTabContextMenu(
    BuildContext context,
    Offset globalPosition,
    CodingOpenTab tab,
  ) async {
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      items: const [
        PopupMenuItem(value: 'reveal', child: Text('メニューで表示')),
        PopupMenuItem(value: 'rename', child: Text('RENAME')),
      ],
    );
    if (selected == null || !context.mounted) return;
    final bloc = context.read<CodingAssistBloc>();
    if (selected == 'reveal') {
      bloc.add(CodingAssistRevealInTreeRequested(tab.relativePath));
      return;
    }
    if (selected == 'rename') {
      final name = await _promptCodingEntryName(
        context,
        title: 'RENAME',
        hint: p.basename(tab.relativePath),
        initialValue: p.basename(tab.relativePath),
        confirmLabel: 'RENAME',
      );
      if (name == null || !context.mounted) return;
      bloc.add(
        CodingAssistRenamePathRequested(
          relativePath: tab.relativePath,
          isDirectory: false,
          newName: name,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (state.workspaceRoot == null) {
      return const Center(child: Text('左の「フォルダを開く」からプロジェクトフォルダを選択'));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxTerminal = (constraints.maxHeight * 0.55).clamp(
          CodingTerminalPanel.heightMin,
          constraints.maxHeight,
        );
        final terminalH = _terminalHeight.clamp(
          CodingTerminalPanel.heightMin,
          maxTerminal,
        );

        return Column(
          children: [
            Expanded(child: _buildEditorBody(context)),
            CodingTerminalPanel(
              workingDirectory: state.workspaceRoot!,
              collapsed: _terminalCollapsed,
              height: terminalH,
              onToggleCollapsed: () =>
                  setState(() => _terminalCollapsed = !_terminalCollapsed),
              onHeightDrag: (delta) {
                setState(() {
                  _terminalHeight = (_terminalHeight + delta).clamp(
                    CodingTerminalPanel.heightMin,
                    maxTerminal,
                  );
                });
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildEditorBody(BuildContext context) {
    if (state.openTabs.isEmpty) {
      return const Center(child: Text('左のファイル一覧からファイルを開く'));
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    final colors = AppColors.of(context);
    final highlight = CodingSyntax.themeForPath(
      state.activeTabPath,
      dark: dark,
    );
    // ソース本体色。行番号ガターは別色（indicatorBuilder）。
    final bg = colors.editorBackground;
    final previewKind = CodingMarkupPreview.kindForPath(state.activeTabPath);
    final showPreviewToggle = previewKind != null;
    final inPreview = _previewMode && previewKind != null;

    return Column(
      children: [
        SizedBox(
          height: 40,
          child: Row(
            children: [
              Expanded(
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(left: 4, right: 4),
                  children: [
                    for (final tab in state.openTabs)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: GestureDetector(
                          onSecondaryTapDown: (details) => _showTabContextMenu(
                            context,
                            details.globalPosition,
                            tab,
                          ),
                          child: InputChip(
                            label: Text(
                              p.basename(tab.relativePath),
                              style: const TextStyle(fontSize: 12),
                            ),
                            selected: _selectionOnRight
                                ? tab.relativePath == splitPath
                                : tab.relativePath == _displayLeftPath,
                            avatar: _rightPaths.contains(tab.relativePath)
                                ? const Icon(Icons.vertical_split, size: 14)
                                : null,
                            onSelected: (_) {
                              if (_rightPaths.contains(tab.relativePath)) {
                                setState(() {
                                  _splitPath = tab.relativePath;
                                  _selectionOnRight = true;
                                  _syncRightEditor();
                                  _syncShownEditors();
                                });
                                return;
                              }
                              setState(() => _selectionOnRight = false);
                              context.read<CodingAssistBloc>().add(
                                CodingAssistSelectTabRequested(
                                  tab.relativePath,
                                ),
                              );
                            },
                            onDeleted: () =>
                                context.read<CodingAssistBloc>().add(
                                  CodingAssistCloseTabRequested(
                                    tab.relativePath,
                                  ),
                                ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              if (showPreviewToggle)
                IconButton(
                  tooltip: inPreview
                      ? 'エディタ表示に戻す'
                      : '${CodingMarkupPreview.buttonLabel(previewKind)}のビュー表示',
                  onPressed: () => setState(() => _previewMode = !_previewMode),
                  icon: Icon(
                    inPreview
                        ? Icons.edit_note_outlined
                        : Icons.visibility_outlined,
                    size: 20,
                  ),
                  visualDensity: VisualDensity.compact,
                  isSelected: inPreview,
                ),
              IconButton(
                tooltip: '今開いているファイルをAgentに取り込み',
                onPressed: state.activeTabPath == null
                    ? null
                    : () => _attachOpenFilesToPrompt(context, activeOnly: true),
                icon: const Icon(Icons.description_outlined, size: 20),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                tooltip: '開いているすべてのファイルをAgentに取り込み',
                onPressed: state.openTabs.isEmpty
                    ? null
                    : () =>
                          _attachOpenFilesToPrompt(context, activeOnly: false),
                icon: const Icon(Icons.library_books_outlined, size: 20),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                tooltip: 'ディスクから再読込（このタブのみ・未保存は破棄）',
                onPressed: state.activeTabPath == null
                    ? null
                    : () => context.read<CodingAssistBloc>().add(
                        const CodingAssistReloadActiveTabFromDiskRequested(),
                      ),
                icon: const Icon(Icons.refresh, size: 20),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                tooltip: '保存',
                onPressed: state.activeTabPath == null
                    ? null
                    : () => context.read<CodingAssistBloc>().add(
                        CodingAssistSaveTabRequested(state.activeTabPath!),
                      ),
                icon: const Icon(Icons.save_outlined, size: 20),
                visualDensity: VisualDensity.compact,
              ),
              if (state.openTabs.length >= 2)
                IconButton(
                  tooltip: _selectionOnRight
                      ? '選択中のファイルを左側に戻す'
                      : splitPath == null
                      ? '選択中のファイルを右側に表示'
                      : '選択中のファイルを右側へ移す',
                  onPressed: _toggleSplit,
                  icon: const Icon(Icons.vertical_split, size: 20),
                  visualDensity: VisualDensity.compact,
                  isSelected: splitPath != null,
                ),
              IconButton(
                tooltip: 'ショートカット一覧',
                onPressed: () => showCodingAssistShortcutHelp(context),
                icon: const Icon(Icons.keyboard_alt_outlined, size: 20),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        Expanded(
          child: ColoredBox(
            color: bg,
            child: _buildEditorSurface(
              inPreview: inPreview,
              previewKind: previewKind,
              dark: dark,
              highlight: highlight,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEditorSurface({
    required bool inPreview,
    required CodingPreviewKind? previewKind,
    required bool dark,
    required CodeHighlightTheme? highlight,
  }) {
    final leftPath = _displayLeftPath;
    final leftController = _optionalLeftController;
    final left = leftPath == null || leftController == null
        ? const Center(child: Text('左に表示するファイルがありません'))
        : inPreview && previewKind != null
        ? CodingMarkupPreviewPane(
            kind: previewKind,
            content: leftController.text,
          )
        : _editorHost(
            key: const ValueKey('coding-editor-host'),
            path: leftPath,
            editor: leftController,
            find: _displayLeftFind,
            highlight: highlight,
            dark: dark,
            reveal: true,
            autofocus: true,
            showEditor: identical(_shownLeftController, leftController),
            minimapCollapsed: minimapCollapsed,
            onToggleMinimap: onToggleMinimap,
          );
    final split = splitPath;
    final rightEditor = _rightController;
    final rightFind = _rightFind;
    final showRight = split != null && rightEditor != null && rightFind != null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        const handle = 6.0;
        const minPane = 200.0;
        final span = !width.isFinite
            ? 0.0
            : (width - handle) > 0
            ? width - handle
            : 0.0;
        final leftWidth = !showRight
            ? (width.isFinite ? width : null)
            : span < minPane * 2
            ? span / 2
            : (span * _splitFraction).clamp(minPane, span - minPane);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (leftWidth == null)
              Expanded(child: left)
            else
              SizedBox(width: leftWidth, child: left),
            if (showRight) ...[
              _AgentResizeHandle(
                onDrag: (dx) {
                  if (span <= 0) return;
                  setState(() {
                    _splitFraction = (_splitFraction + dx / span).clamp(
                      0.2,
                      0.8,
                    );
                  });
                },
              ),
              Expanded(
                child: _splitEditor(split, rightEditor, rightFind, dark),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _splitEditor(
    String split,
    CodeLineEditingController rightEditor,
    CodeFindController rightFind,
    bool dark,
  ) {
    return _editorHost(
      key: const ValueKey('coding-editor-split'),
      path: split,
      editor: rightEditor,
      find: rightFind,
      highlight: CodingSyntax.themeForPath(split, dark: dark),
      dark: dark,
      reveal: false,
      autofocus: false,
      showEditor: identical(_shownRightController, rightEditor),
      minimapCollapsed: _rightMinimapCollapsed,
      onToggleMinimap: () =>
          setState(() => _rightMinimapCollapsed = !_rightMinimapCollapsed),
    );
  }

  Widget _editorHost({
    required Key key,
    required String? path,
    required CodeLineEditingController editor,
    required CodeFindController find,
    required CodeHighlightTheme? highlight,
    required bool dark,
    required bool reveal,
    required bool autofocus,
    required bool showEditor,
    required bool minimapCollapsed,
    required VoidCallback onToggleMinimap,
  }) {
    return _CodeEditorHost(
      key: key,
      controller: editor,
      findController: find,
      highlight: highlight,
      editorFontSize: state.uiFontSizes.editor,
      activeTabPath: path,
      workspaceRoot: state.workspaceRoot,
      dartLsp: widget.dartLsp,
      swiftLsp: widget.swiftLsp,
      minimapCollapsed: minimapCollapsed,
      onToggleMinimap: onToggleMinimap,
      onSave: path == null
          ? onSave
          : () => context.read<CodingAssistBloc>().add(
              CodingAssistSaveTabRequested(path),
            ),
      onAlignIndent: () {
        if (path == null) return;
        onAlignIndent(path, editor);
      },
      onWorkspaceSearch: () => onWorkspaceSearch(editor),
      onWorkspaceSearchFromClick: () => onWorkspaceSearchFromClick(editor),
      onToggleAgent: onToggleAgent,
      revealLine: reveal ? state.revealLine : null,
      revealOffset: reveal ? state.revealOffset : null,
      revealLength: reveal ? state.revealLength : null,
      onRevealConsumed: () => context.read<CodingAssistBloc>().add(
        const CodingAssistRevealLineConsumed(),
      ),
      dark: dark,
      autofocus: autofocus,
      showEditor: showEditor,
      onChanged: (value) {
        if (path == null) return;
        onChanged(path, value);
      },
    );
  }

  void _attachOpenFilesToPrompt(
    BuildContext context, {
    required bool activeOnly,
  }) {
    final activePath = state.activeTabPath;
    final files = <CodingAttachedOpenFile>[];
    if (activeOnly) {
      if (activePath == null) return;
      files.add(
        CodingAttachedOpenFile(
          relativePath: activePath,
          content: controller.text,
        ),
      );
    } else {
      for (final tab in state.openTabs) {
        final content = tab.relativePath == activePath
            ? controller.text
            : tab.relativePath == splitPath
            ? (splitController?.text ?? tab.content)
            : tab.content;
        files.add(
          CodingAttachedOpenFile(
            relativePath: tab.relativePath,
            content: content,
          ),
        );
      }
    }
    if (files.isEmpty) return;
    context.read<CodingAssistBloc>().add(CodingAssistOpenFilesAttached(files));
  }
}

class _CodeEditorHost extends StatefulWidget {
  const _CodeEditorHost({
    super.key,
    required this.controller,
    required this.findController,
    required this.highlight,
    required this.activeTabPath,
    required this.workspaceRoot,
    required this.dartLsp,
    required this.swiftLsp,
    required this.minimapCollapsed,
    required this.onToggleMinimap,
    required this.onSave,
    required this.onAlignIndent,
    required this.onWorkspaceSearch,
    required this.onWorkspaceSearchFromClick,
    required this.onToggleAgent,
    required this.revealLine,
    required this.revealOffset,
    required this.revealLength,
    required this.onRevealConsumed,
    required this.dark,
    required this.editorFontSize,
    required this.autofocus,
    required this.showEditor,
    required this.onChanged,
  });

  final CodeLineEditingController controller;
  final CodeFindController findController;
  final CodeHighlightTheme? highlight;
  final String? activeTabPath;
  final String? workspaceRoot;
  final CodingDartLspController dartLsp;
  final CodingSwiftLspController swiftLsp;
  final bool minimapCollapsed;
  final VoidCallback onToggleMinimap;
  final VoidCallback onSave;
  final VoidCallback onAlignIndent;
  final VoidCallback onWorkspaceSearch;
  final VoidCallback onWorkspaceSearchFromClick;
  final VoidCallback onToggleAgent;
  final int? revealLine;
  final int? revealOffset;
  final int? revealLength;
  final VoidCallback onRevealConsumed;
  final bool dark;
  final double editorFontSize;
  final bool autofocus;
  final bool showEditor;
  final ValueChanged<String> onChanged;

  @override
  State<_CodeEditorHost> createState() => _CodeEditorHostState();
}

class _CodeEditorHostState extends State<_CodeEditorHost> {
  /// エディタ寿命に合わせて所有（ミニマップ連動用）。親から毎ビルド new しない。
  late final CodeScrollController _scrollController;
  CodingDartLspPromptsBuilder? _lspPrompts;
  bool _seenDartReady = false;
  bool _seenSwiftReady = false;
  OverlayEntry? _definitionEntry;
  String _definitionTitle = '';
  String _definitionBody = '';
  bool _secondaryPointer = false;

  @override
  void initState() {
    super.initState();
    _scrollController = CodeScrollController();
    _seenDartReady = widget.dartLsp.isReady;
    _seenSwiftReady = widget.swiftLsp.isReady;
    _refreshLspPrompts();
    if (widget.revealLine != null) {
      _scheduleReveal();
    }
  }

  @override
  void didUpdateWidget(covariant _CodeEditorHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final dartReady = widget.dartLsp.isReady;
    final swiftReady = widget.swiftLsp.isReady;
    if (oldWidget.controller != widget.controller) {
      _scrollSelectionIntoView(widget.controller);
    }
    if (oldWidget.activeTabPath != widget.activeTabPath ||
        oldWidget.workspaceRoot != widget.workspaceRoot ||
        oldWidget.dartLsp != widget.dartLsp ||
        oldWidget.swiftLsp != widget.swiftLsp ||
        dartReady != _seenDartReady ||
        swiftReady != _seenSwiftReady) {
      _seenDartReady = dartReady;
      _seenSwiftReady = swiftReady;
      _refreshLspPrompts();
    } else if (_lspPrompts != null) {
      _lspPrompts!.fullText = widget.controller.text;
    }
    if (widget.revealLine != null &&
        (oldWidget.revealLine != widget.revealLine ||
            oldWidget.revealOffset != widget.revealOffset ||
            oldWidget.revealLength != widget.revealLength ||
            oldWidget.activeTabPath != widget.activeTabPath)) {
      _scheduleReveal();
    }
  }

  void _scrollSelectionIntoView(CodeLineEditingController next) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(widget.controller, next)) return;
      if (!widget.showEditor) {
        _scrollSelectionIntoView(next);
        return;
      }
      final selection = next.selection;
      _scrollController.makeVisible(
        CodeLinePosition(
          index: selection.extentIndex,
          offset: selection.extentOffset,
        ),
      );
    });
  }

  void _scheduleReveal() {
    final reveal = widget.revealLine;
    if (reveal == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.revealLine != reveal) return;
      if (!widget.showEditor) {
        _scheduleReveal();
        return;
      }
      final lineCount = widget.controller.codeLines.length;
      if (lineCount <= 0) {
        widget.onRevealConsumed();
        return;
      }
      final index = (reveal - 1).clamp(0, lineCount - 1);
      final lineText = widget.controller.codeLines[index].text;
      final offset = (widget.revealOffset ?? 0).clamp(0, lineText.length);
      final length = widget.revealLength ?? 0;
      final end = length > 0
          ? (offset + length).clamp(offset, lineText.length)
          : offset;
      try {
        if (end > offset) {
          widget.controller.selection = CodeLineSelection(
            baseIndex: index,
            baseOffset: offset,
            extentIndex: index,
            extentOffset: end,
          );
        } else {
          widget.controller.selection = CodeLineSelection.collapsed(
            index: index,
            offset: offset,
          );
        }
        final pos = CodeLinePosition(index: index, offset: offset);
        _scrollController.makeCenterIfInvisible(pos);
      } catch (_) {}
      widget.onRevealConsumed();
    });
  }

  void _refreshLspPrompts() {
    final path = widget.activeTabPath;
    final root = widget.workspaceRoot;
    if (path == null || root == null) {
      _lspPrompts = null;
      return;
    }
    final lower = path.toLowerCase();
    final CodingLspCompletionSource? source;
    final String suffix;
    if (lower.endsWith('.dart') && widget.dartLsp.isReady) {
      source = widget.dartLsp;
      suffix = '.dart';
    } else if (lower.endsWith('.swift') && widget.swiftLsp.isReady) {
      source = widget.swiftLsp;
      suffix = '.swift';
    } else {
      _lspPrompts = null;
      return;
    }
    _lspPrompts = CodingDartLspPromptsBuilder(
      lsp: source,
      absolutePath: p.join(root, path),
      pathSuffix: suffix,
      fullText: widget.controller.text,
      onNotifierReady: (_) {},
    );
  }

  CodingDartDefinitionQuery? _selectedIdentifier() {
    final selection = widget.controller.selection;
    final lines = widget.controller.codeLines;
    if (selection.baseIndex < 0 || selection.baseIndex >= lines.length) {
      return null;
    }
    return codingDartSelectedIdentifier(
      collapsed: selection.isCollapsed,
      baseLine: selection.baseIndex,
      baseOffset: selection.baseOffset,
      extentLine: selection.extentIndex,
      extentOffset: selection.extentOffset,
      lineText: lines[selection.baseIndex].text,
    );
  }

  Future<void> _showEditorContextMenu(Offset globalPosition) async {
    if (!mounted) return;
    final path = widget.activeTabPath;
    final selection = widget.controller.selection;
    final selectedText = widget.controller.selectedText;
    final canAttach =
        path != null &&
        !context.read<CodingAssistBloc>().state.isGenerating &&
        !selection.isCollapsed &&
        selectedText.isNotEmpty;
    final query = _selectedIdentifier();
    if (!canAttach && query == null) return;
    final startLine = selection.startIndex + 1;
    final endLine = selection.endIndex + 1;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      items: [
        if (canAttach)
          PopupMenuItem(
            value: 'attach',
            child: Text(CodingPromptAction.attachSelection.menuLabel),
          ),
        if (query != null)
          const PopupMenuItem(value: 'definition', child: Text('定義を表示')),
      ],
    );
    if (!mounted || selected == null) return;
    if (selected == 'attach' && path != null && canAttach) {
      context.read<CodingAssistBloc>().add(
        CodingAssistSelectionAttached(
          CodingAttachedSelection(
            relativePath: path,
            startLine: startLine,
            endLine: endLine,
            selectedText: selectedText,
          ),
        ),
      );
      return;
    }
    if (selected == 'definition' && query != null) {
      await _showDefinitionBalloon(globalPosition, query);
    }
  }

  Future<void> _showDefinitionBalloon(
    Offset anchor,
    CodingDartDefinitionQuery query,
  ) async {
    final path = widget.activeTabPath;
    final root = widget.workspaceRoot;
    final lower = path?.toLowerCase() ?? '';
    final isDart = lower.endsWith('.dart');
    final isSwift = lower.endsWith('.swift');
    final ready =
        path != null &&
        root != null &&
        ((isDart && widget.dartLsp.isReady) ||
            (isSwift && widget.swiftLsp.isReady));
    _presentDefinitionBalloon(anchor, query.word, '取得中…');
    if (!ready) {
      _presentDefinitionBalloon(anchor, query.word, '定義が見つかりません');
      return;
    }
    final absolutePath = p.join(root, path);
    final snippet = isSwift
        ? await widget.swiftLsp.definitionAt(
            absolutePath: absolutePath,
            content: widget.controller.text,
            line: query.line,
            character: query.character,
          )
        : await widget.dartLsp.definitionAt(
            absolutePath: absolutePath,
            content: widget.controller.text,
            line: query.line,
            character: query.character,
          );
    if (!mounted || _definitionEntry == null) return;
    if (snippet == null) {
      _presentDefinitionBalloon(anchor, query.word, '定義が見つかりません');
      return;
    }
    _presentDefinitionBalloon(anchor, snippet.title, snippet.body);
  }

  void _presentDefinitionBalloon(Offset anchor, String title, String body) {
    _definitionTitle = title;
    _definitionBody = body;
    final existing = _definitionEntry;
    if (existing != null) {
      existing.markNeedsBuild();
      return;
    }
    final entry = OverlayEntry(
      builder: (context) {
        return CodingDartDefinitionBalloon(
          anchor: anchor,
          title: _definitionTitle,
          body: _definitionBody,
          onDismiss: _dismissDefinitionBalloon,
        );
      },
    );
    _definitionEntry = entry;
    Overlay.of(context).insert(entry);
  }

  void _dismissDefinitionBalloon() {
    _definitionEntry?.remove();
    _definitionEntry = null;
  }

  @override
  void dispose() {
    _dismissDefinitionBalloon();
    _scrollController.verticalScroller.dispose();
    _scrollController.horizontalScroller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 入力のたびに全文を LSP 橋渡しへ渡す
    _lspPrompts?.fullText = widget.controller.text;

    final editor = Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if (event.kind != PointerDeviceKind.mouse) return;
        if (event.buttons == kSecondaryButton) {
          _secondaryPointer = true;
          _dismissDefinitionBalloon();
          return;
        }
        _secondaryPointer = false;
        if (event.buttons != kPrimaryButton) return;
        final keys = HardwareKeyboard.instance.logicalKeysPressed;
        final mod =
            keys.contains(LogicalKeyboardKey.metaLeft) ||
            keys.contains(LogicalKeyboardKey.metaRight) ||
            keys.contains(LogicalKeyboardKey.controlLeft) ||
            keys.contains(LogicalKeyboardKey.controlRight);
        if (!mod) return;
        // キャレット移動後に選択／識別子／記号列を拾う
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          widget.onWorkspaceSearchFromClick();
        });
      },
      onPointerUp: (event) {
        if (!_secondaryPointer) return;
        _secondaryPointer = false;
        if (event.kind != PointerDeviceKind.mouse) return;
        _showEditorContextMenu(event.position);
      },
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.keyL, meta: true, alt: true):
              _AlignIndentIntent(),
          SingleActivator(LogicalKeyboardKey.keyL, control: true, alt: true):
              _AlignIndentIntent(),
          SingleActivator(LogicalKeyboardKey.keyF, meta: true, shift: true):
              _WorkspaceSearchIntent(),
          SingleActivator(LogicalKeyboardKey.keyF, control: true, shift: true):
              _WorkspaceSearchIntent(),
          SingleActivator(LogicalKeyboardKey.keyW, meta: true):
              _CloseEditorTabIntent(),
          SingleActivator(LogicalKeyboardKey.keyW, control: true):
              _CloseEditorTabIntent(),
          SingleActivator(LogicalKeyboardKey.keyB, meta: true, shift: true):
              _ToggleAgentIntent(),
          SingleActivator(LogicalKeyboardKey.keyB, control: true, shift: true):
              _ToggleAgentIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            _AlignIndentIntent: CallbackAction<_AlignIndentIntent>(
              onInvoke: (_) {
                widget.onAlignIndent();
                return null;
              },
            ),
            _WorkspaceSearchIntent: CallbackAction<_WorkspaceSearchIntent>(
              onInvoke: (_) {
                widget.onWorkspaceSearch();
                return null;
              },
            ),
            _CloseEditorTabIntent: CallbackAction<_CloseEditorTabIntent>(
              onInvoke: (_) {
                final path = widget.activeTabPath;
                if (path == null) return null;
                context.read<CodingAssistBloc>().add(
                  CodingAssistCloseTabRequested(path),
                );
                return null;
              },
            ),
            _ToggleAgentIntent: CallbackAction<_ToggleAgentIntent>(
              onInvoke: (_) {
                widget.onToggleAgent();
                return null;
              },
            ),
          },
          child: widget.showEditor
              ? CodeEditor(
                  // コントローラを差し替えると re_editor が前の Undo 用リスナーを外さない。
                  // タブ（コントローラ）が変わるたびにエディタ状態を作り直す。
                  key: ValueKey<CodeLineEditingController>(widget.controller),
                  controller: widget.controller,
                  findController: widget.findController,
                  scrollController: _scrollController,
                  findBuilder: (context, findController, readOnly) =>
                      CodingFindPanel(
                        controller: findController,
                        readOnly: readOnly,
                      ),
                  // ⌘/ または Ctrl+/ は re_editor 既定。ブロックコメントは無効化（§2.2.3）。
                  shortcutsActivatorsBuilder:
                      const CodingAssistShortcutsActivatorsBuilder(),
                  // 括弧自動閉じは日本語 IME 変換中に選択／挿入がずれやすいのでオフ。
                  autocompleteSymbols: false,
                  commentFormatter: CodingSyntax.commentFormatterForPath(
                    widget.activeTabPath,
                  ),
                  wordWrap: false,
                  autofocus: widget.autofocus,
                  padding: const EdgeInsets.all(8),
                  // re_editor は Cmd/Ctrl+S を CodeShortcutSaveIntent で消費するが
                  // 既定ハンドラが無いため、ここで保存を接続する。
                  shortcutOverrideActions: {
                    CodeShortcutSaveIntent:
                        CallbackAction<CodeShortcutSaveIntent>(
                          onInvoke: (_) {
                            widget.onSave();
                            return null;
                          },
                        ),
                  },
                  style: CodeEditorStyle(
                    fontSize: widget.editorFontSize,
                    fontFamily: 'monospace',
                    backgroundColor: AppColors.of(context).editorBackground,
                    codeTheme: widget.highlight,
                  ),
                  indicatorBuilder:
                      (context, editingController, chunkController, notifier) {
                        final gutterBg =
                            AppColors.of(context).editorGutterBackground;
                        return ColoredBox(
                          color: gutterBg,
                          child: Row(
                            children: [
                              DefaultCodeLineNumber(
                                controller: editingController,
                                notifier: notifier,
                              ),
                              DefaultCodeChunkIndicator(
                                width: 16,
                                controller: chunkController,
                                notifier: notifier,
                              ),
                            ],
                          ),
                        );
                      },
                  onChanged: (_) => widget.onChanged(widget.controller.text),
                )
              : const SizedBox.expand(),
        ),
      ),
    );

    // Dart 補完の有無で CodeAutocomplete を付け外しすると、同じフレームで
    // CodeEditor が破棄され作り直される。共有コントローラの通知が、まだ
    // dispose 前の入力接続から inactive な Element へ findRenderObject して
    // ⌘W（タブを閉じた直後）に落ちることがある。親は常に同じにする。
    final promptsBuilder = _lspPrompts;
    final editorChild = CodeAutocomplete(
      viewBuilder: (context, notifier, onSelected) {
        final active = _lspPrompts;
        if (active == null) return const _InactiveAutocompleteView();
        return CodingDartCompletionListView(
          notifier: notifier,
          onSelected: onSelected,
          promptsBuilder: active,
        );
      },
      promptsBuilder: promptsBuilder ?? const _InactiveAutocompletePrompts(),
      child: editor,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: editorChild),
        CodingMinimap(
          editingController: widget.controller,
          scrollController: _scrollController,
          collapsed: widget.minimapCollapsed,
          onToggleCollapsed: widget.onToggleMinimap,
          backgroundColor: AppColors.of(context).minimapBackground,
        ),
      ],
    );
  }
}

class _InactiveAutocompleteView extends StatelessWidget
    implements PreferredSizeWidget {
  const _InactiveAutocompleteView();

  @override
  Size get preferredSize => Size.zero;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _InactiveAutocompletePrompts implements CodeAutocompletePromptsBuilder {
  const _InactiveAutocompletePrompts();

  @override
  CodeAutocompleteEditingValue? build(
    BuildContext context,
    CodeLine codeLine,
    CodeLineSelection selection,
  ) {
    return null;
  }
}
