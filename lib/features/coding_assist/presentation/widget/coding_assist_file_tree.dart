part of '../pages/coding_assist_page.dart';

class _TreeDragPayload {
  const _TreeDragPayload({
    required this.relativePath,
    required this.isDirectory,
  });

  final String relativePath;
  final bool isDirectory;
}

Future<String?> _promptCodingEntryName(
  BuildContext context, {
  required String title,
  String hint = '',
  String initialValue = '',
  String confirmLabel = '作成',
}) async {
  final result = await showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'dismiss',
    barrierColor: AppColors.of(context).dialogBarrier,
    // 退場アニメ中に親を組み替えると RenderObject deactivate assertion になる
    transitionDuration: Duration.zero,
    pageBuilder: (ctx, animation, secondaryAnimation) {
      return _CodingEntryNameDialog(
        title: title,
        hint: hint,
        initialValue: initialValue,
        confirmLabel: confirmLabel,
      );
    },
  );
  if (result == null || result.isEmpty) return null;
  // pop 直後の同一フレームでの親 rebuild を避ける
  await WidgetsBinding.instance.endOfFrame;
  await Future<void>.delayed(Duration.zero);
  return result;
}

class _CodingEntryNameDialog extends StatefulWidget {
  const _CodingEntryNameDialog({
    required this.title,
    required this.hint,
    this.initialValue = '',
    this.confirmLabel = '作成',
  });

  final String title;
  final String hint;
  final String initialValue;
  final String confirmLabel;

  @override
  State<_CodingEntryNameDialog> createState() => _CodingEntryNameDialogState();
}

class _CodingEntryNameDialogState extends State<_CodingEntryNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    if (widget.initialValue.isNotEmpty) {
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.initialValue.length,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context, rootNavigator: true).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AlertDialog(
        title: Text(widget.title),
        content: TextField(
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: widget.hint,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onSubmitted: (_) => _submit(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
            child: const Text('キャンセル'),
          ),
          FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
        ],
      ),
    );
  }
}

/// 選択ファイルと同階層。フォルダ選択時はその中。未選択はルート。
String _codingCreateParentDir({
  required String? selectedPath,
  required bool selectedIsDirectory,
  required String? activeTabPath,
}) {
  final path = selectedPath ?? activeTabPath;
  if (path == null || path.isEmpty) return '';
  final isDir = selectedPath != null ? selectedIsDirectory : false;
  if (isDir) return path.replaceAll('\\', '/');
  final parent = p.dirname(path.replaceAll('\\', '/'));
  if (parent == '.' || parent == '/') return '';
  return parent;
}

/// 新規ファイル／フォルダの作成先を決める。
///
/// [entryName] に `/` を含む場合はワークスペース相対のフルパスとみなし、
/// 左メニュー選択位置は使わない。ファイル名だけなら従来どおり選択位置配下。
({String parentRelativeDir, String name})? codingAssistResolveCreateTarget({
  required String entryName,
  required String? selectedPath,
  required bool selectedIsDirectory,
  required String? activeTabPath,
}) {
  var raw = entryName.trim().replaceAll('\\', '/');
  if (raw.isEmpty) return null;
  while (raw.startsWith('./')) {
    raw = raw.substring(2);
  }
  if (raw.startsWith('/')) return null;
  final segments = raw.split('/');
  if (segments.any((s) => s.isEmpty || s == '.' || s == '..')) return null;

  if (raw.contains('/')) {
    final name = segments.last;
    final parent = segments.sublist(0, segments.length - 1).join('/');
    return (parentRelativeDir: parent, name: name);
  }

  return (
    parentRelativeDir: _codingCreateParentDir(
      selectedPath: selectedPath,
      selectedIsDirectory: selectedIsDirectory,
      activeTabPath: activeTabPath,
    ),
    name: raw,
  );
}

class _LeftMenuPane extends StatefulWidget {
  const _LeftMenuPane({
    super.key,
    required this.state,
    required this.onOpenRecent,
    required this.onOpenFolder,
    required this.onCollapse,
  });

  final CodingAssistState state;
  final ValueChanged<String> onOpenRecent;
  final VoidCallback onOpenFolder;
  final VoidCallback onCollapse;

  @override
  State<_LeftMenuPane> createState() => _LeftMenuPaneState();
}

class _LeftMenuPaneState extends State<_LeftMenuPane> {
  String? _selectedPath;
  bool _selectedIsDirectory = false;
  bool _folderExpanded = true;
  bool _searchExpanded = false;
  bool _gitExpanded = false;

  final _searchController = TextEditingController();
  final _replaceController = TextEditingController();
  final _commitController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final Map<String, ExpansibleController> _dirControllers = {};
  CodingAssistBloc? _bloc;
  bool _expansionSaveScheduled = false;
  String? _pendingExpansionRoot;
  List<CodingSearchHit> _searchHits = const [];
  bool _searchBusy = false;
  bool _searchCaseSensitive = false;
  String? _searchStatus;
  bool _gitBusy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bloc = context.read<CodingAssistBloc>();
  }

  @override
  void dispose() {
    _emitExpansion(widget.state.workspaceRoot);
    _searchController.dispose();
    _replaceController.dispose();
    _commitController.dispose();
    _searchFocusNode.dispose();
    _disposeDirControllers();
    super.dispose();
  }

  void _disposeDirControllers() {
    for (final c in _dirControllers.values) {
      c.dispose();
    }
    _dirControllers.clear();
  }

  ExpansibleController _dirController(
    String relativePath, {
    required bool expanded,
  }) {
    final existing = _dirControllers[relativePath];
    if (existing != null) return existing;
    final controller = ExpansibleController();
    if (expanded) {
      controller.expand();
    }
    _dirControllers[relativePath] = controller;
    return controller;
  }

  bool _wantsExpanded(
    String relativePath, {
    required bool preferInitiallyExpanded,
  }) {
    return CodingFolderExpansion.isExpanded(
      relativePath: relativePath,
      preferInitiallyExpanded: preferInitiallyExpanded,
      remembered: widget.state.folderExpansion,
    );
  }

  void _scheduleFolderExpansionSave() {
    final root = widget.state.workspaceRoot?.trim();
    if (root == null || root.isEmpty) return;
    _pendingExpansionRoot = root;
    if (_expansionSaveScheduled) return;
    _expansionSaveScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _expansionSaveScheduled = false;
      if (!mounted) return;
      final target = _pendingExpansionRoot;
      _pendingExpansionRoot = null;
      if (target == null || widget.state.workspaceRoot != target) return;
      _emitExpansion(target);
    });
  }

  void _emitExpansion(String? workspaceRoot) {
    final root = workspaceRoot?.trim() ?? '';
    final bloc = _bloc;
    if (root.isEmpty || bloc == null || bloc.isClosed) return;
    final visible = <String, bool>{
      for (final entry in _dirControllers.entries)
        entry.key: entry.value.isExpanded,
    };
    bloc.add(
      CodingAssistFolderExpansionCaptured(
        workspaceRoot: root,
        visible: visible,
      ),
    );
  }

  void _revealInTree(String relativePath) {
    final rel = relativePath.replaceAll('\\', '/').trim();
    if (rel.isEmpty) return;
    final ancestors = CodingFileTreeNode.ancestorDirectories(rel);
    setState(() {
      _folderExpanded = true;
      _selectedPath = rel;
      _selectedIsDirectory = false;
    });
    for (final dir in ancestors) {
      final c = _dirController(dir, expanded: true);
      if (!c.isExpanded) {
        c.expand();
      }
    }
    // 未マウントの祖先は次フレームで再度 expand
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final dir in ancestors) {
        final c = _dirControllers[dir];
        if (c != null && !c.isExpanded) {
          c.expand();
        }
      }
      _scheduleFolderExpansionSave();
      context.read<CodingAssistBloc>().add(
        const CodingAssistRevealInTreeConsumed(),
      );
    });
  }

  @override
  void didUpdateWidget(covariant _LeftMenuPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    final active = widget.state.activeTabPath;
    if (active != null &&
        active != oldWidget.state.activeTabPath &&
        active != _selectedPath) {
      _selectedPath = active;
      _selectedIsDirectory = false;
    }
    if (oldWidget.state.workspaceRoot != widget.state.workspaceRoot) {
      _emitExpansion(oldWidget.state.workspaceRoot);
      _searchHits = const [];
      _searchStatus = null;
      _searchController.clear();
      _replaceController.clear();
      _commitController.clear();
      _disposeDirControllers();
      _selectedPath = null;
      _selectedIsDirectory = false;
    }
    if (widget.state.workspaceRoot != null &&
        widget.state.index != null &&
        (oldWidget.state.workspaceRoot != widget.state.workspaceRoot ||
            oldWidget.state.index != widget.state.index)) {
      _scheduleFolderExpansionSave();
    }
    final reveal = widget.state.treeRevealPath;
    if (reveal != null && reveal != oldWidget.state.treeRevealPath) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _revealInTree(reveal);
      });
    }
  }

  void _select(String path, {required bool isDirectory}) {
    setState(() {
      _selectedPath = path;
      _selectedIsDirectory = isDirectory;
    });
  }

  Future<void> _removeRecentWorkspace(String path) async {
    final bloc = context.read<CodingAssistBloc>();
    bloc.add(CodingAssistRemoveRecentWorkspaceRequested(path));
  }

  /// ショートカット ⌘N からも呼ぶ。名前ダイアログ付き。
  Future<void> promptCreateFile() => _createFile();

  /// ⌘N の作成先。選択フォルダの中、選択ファイルと同階層、未選択はルート。
  String createParentDirForNewEntry() {
    return _codingCreateParentDir(
      selectedPath: _selectedPath,
      selectedIsDirectory: _selectedIsDirectory,
      activeTabPath: widget.state.activeTabPath,
    );
  }

  void expandFolderSection() {
    if (_folderExpanded) return;
    setState(() => _folderExpanded = true);
  }

  /// ⌘⇧F / ⌘クリックからフォルダ内文言検索を開く（識別子と記号列を検索語にできる）。
  void openWorkspaceSearch({String? query, bool runSearch = false}) {
    setState(() {
      _searchExpanded = true;
      if (query != null) {
        _searchController.text = query;
        _searchController.selection = TextSelection.collapsed(
          offset: query.length,
        );
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _searchFocusNode.requestFocus();
      if (runSearch && (_searchController.text.trim().isNotEmpty)) {
        // ignore: discarded_futures
        _runSearch();
      }
    });
  }

  Future<void> _createFile() async {
    // DragTarget builder の context は await 後に unmounted になり得るため State 側を使う。
    if (widget.state.workspaceRoot == null) return;
    setState(() => _folderExpanded = true);
    final bloc = context.read<CodingAssistBloc>();
    final activeTabPath = widget.state.activeTabPath;
    final selectedPath = _selectedPath;
    final selectedIsDirectory = _selectedIsDirectory;
    final name = await _promptCodingEntryName(
      context,
      title: '新規ファイル',
      hint: 'example.dart または lib/features/foo/example.dart',
    );
    if (name == null || !mounted) return;
    final target = codingAssistResolveCreateTarget(
      entryName: name,
      selectedPath: selectedPath,
      selectedIsDirectory: selectedIsDirectory,
      activeTabPath: activeTabPath,
    );
    if (target == null) {
      if (!mounted) return;
      await showBrandConfirmDialog(
        context: context,
        title: '新規ファイル',
        message: 'パスが不正です。ファイル名、またはワークスペース相対パスを入力してください',
        cancelLabel: '閉じる',
        confirmLabel: 'OK',
      );
      return;
    }
    bloc.add(
      CodingAssistCreateFileRequested(
        parentRelativeDir: target.parentRelativeDir,
        name: target.name,
      ),
    );
  }

  Future<void> _createFolder() async {
    final bloc = context.read<CodingAssistBloc>();
    final activeTabPath = widget.state.activeTabPath;
    final selectedPath = _selectedPath;
    final selectedIsDirectory = _selectedIsDirectory;
    final name = await _promptCodingEntryName(
      context,
      title: '新規フォルダ',
      hint: 'features または lib/features/todo',
    );
    if (name == null || !mounted) return;
    final target = codingAssistResolveCreateTarget(
      entryName: name,
      selectedPath: selectedPath,
      selectedIsDirectory: selectedIsDirectory,
      activeTabPath: activeTabPath,
    );
    if (target == null) {
      if (!mounted) return;
      await showBrandConfirmDialog(
        context: context,
        title: '新規フォルダ',
        message: 'パスが不正です。フォルダ名、またはワークスペース相対パスを入力してください',
        cancelLabel: '閉じる',
        confirmLabel: 'OK',
      );
      return;
    }
    bloc.add(
      CodingAssistCreateFolderRequested(
        parentRelativeDir: target.parentRelativeDir,
        name: target.name,
      ),
    );
  }

  void _toggleSearchCase() {
    setState(() => _searchCaseSensitive = !_searchCaseSensitive);
    if (_searchController.text.trim().isEmpty) return;
    _runSearch();
  }

  Future<void> _runSearch() async {
    final root = widget.state.workspaceRoot;
    final query = _searchController.text.trim();
    if (root == null) return;
    if (query.isEmpty) {
      setState(() {
        _searchHits = const [];
        _searchStatus = '検索語を入力してください';
      });
      return;
    }
    setState(() {
      _searchBusy = true;
      _searchStatus = null;
    });
    try {
      final hits = await CodingWorkspaceSearch.search(
        rootPath: root,
        query: query,
        caseSensitive: _searchCaseSensitive,
      );
      if (!mounted) return;
      setState(() {
        _searchHits = hits;
        _searchBusy = false;
        _searchStatus = hits.isEmpty
            ? '見つかりませんでした'
            : (hits.length >= CodingWorkspaceSearch.maxHits
                  ? '上位 ${hits.length} 件（上限）'
                  : '${hits.length} 件');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searchBusy = false;
        _searchHits = const [];
        _searchStatus = '検索失敗: $e';
      });
    }
  }

  Future<void> _runReplaceAll() async {
    final root = widget.state.workspaceRoot;
    final query = _searchController.text.trim();
    if (root == null || _searchBusy) return;
    if (query.isEmpty) {
      setState(() => _searchStatus = '検索語を入力してください');
      return;
    }
    final replacement = _replaceController.text;
    final matchNote = _searchCaseSensitive ? '大文字小文字を区別' : '大文字小文字無視';
    final ok = await showBrandConfirmDialog(
      context: context,
      title: 'すべて置換',
      message:
          'ワークスペース内の「$query」を'
          '「${replacement.isEmpty ? '（空）' : replacement}」に'
          '一括置換します（$matchNote）。よろしいですか？',
      confirmLabel: '置換',
      isDestructive: true,
    );
    if (!ok || !mounted) return;

    setState(() {
      _searchBusy = true;
      _searchStatus = null;
    });
    try {
      final overrides = <String, String>{
        for (final tab in widget.state.openTabs) tab.relativePath: tab.content,
      };
      final result = await CodingWorkspaceSearch.replaceAll(
        rootPath: root,
        query: query,
        replacement: replacement,
        contentOverrides: overrides,
        caseSensitive: _searchCaseSensitive,
      );
      if (!mounted) return;
      if (result.updatedContents.isNotEmpty) {
        context.read<CodingAssistBloc>().add(
          CodingAssistSyncTabContentsRequested(result.updatedContents),
        );
      }
      final hits = await CodingWorkspaceSearch.search(
        rootPath: root,
        query: query,
        caseSensitive: _searchCaseSensitive,
      );
      if (!mounted) return;
      setState(() {
        _searchBusy = false;
        _searchHits = hits;
        _searchStatus = result.filesChanged == 0
            ? '置換対象がありませんでした'
            : '${result.filesChanged} ファイル・'
                  '${result.occurrenceCount} 箇所を置換'
                  '${hits.isEmpty ? '' : '（残 ${hits.length} 件）'}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searchBusy = false;
        _searchStatus = '置換失敗: $e';
      });
    }
  }

  Future<void> _runCommit() async {
    final root = widget.state.workspaceRoot;
    if (root == null || _gitBusy) return;
    setState(() => _gitBusy = true);
    try {
      await CodingGit.commit(
        workspaceRoot: root,
        message: _commitController.text,
      );
      if (!mounted) return;
      setState(() => _gitBusy = false);
      _commitController.clear();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('コミットしました')));
    } on CodingGitException catch (e) {
      if (!mounted) return;
      setState(() => _gitBusy = false);
      await _showGitErrorDialog(context, e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _gitBusy = false);
      await _showGitErrorDialog(context, '$e');
    }
  }

  Future<void> _showGitErrorDialog(BuildContext context, String message) {
    return showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('コミットできませんでした'),
          content: SingleChildScrollView(child: Text(message)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Widget _sectionHeader({
    required String title,
    required bool expanded,
    required VoidCallback onToggle,
  }) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: InkWell(
        onTap: onToggle,
        child: SizedBox(
          height: 32,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Icon(
                  expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 18,
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: widget.state.uiFontSizes.menu,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFolderBody(CodingAssistState state) {
    final index = state.index;
    if (index == null) {
      return ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text('ワークスペース', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: widget.onOpenFolder,
            child: const Text('フォルダを開く'),
          ),
          if (state.recentWorkspaces.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('最近'),
            for (final path in state.recentWorkspaces)
              ListTile(
                dense: true,
                title: Text(p.basename(path)),
                subtitle: Text(
                  path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => widget.onOpenRecent(path),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: '最近開いたフォルダから削除',
                  onPressed: () => _removeRecentWorkspace(path),
                ),
              ),
          ],
        ],
      );
    }
    final nodes = CodingFileTreeNode.fromRelativeFiles(
      index.relativeFiles,
      relativeDirectories: index.relativeDirectories,
    );
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 2, 2),
          child: DragTarget<_TreeDragPayload>(
            onWillAcceptWithDetails: (details) {
              final src = details.data.relativePath;
              return src.isNotEmpty && p.dirname(src) != '.';
            },
            onAcceptWithDetails: (details) {
              context.read<CodingAssistBloc>().add(
                CodingAssistMovePathRequested(
                  sourceRelativePath: details.data.relativePath,
                  sourceIsDirectory: details.data.isDirectory,
                  targetDirectoryRelativePath: '',
                ),
              );
            },
            builder: (context, candidate, rejected) {
              final highlight = candidate.isNotEmpty;
              return DecoratedBox(
                decoration: BoxDecoration(
                  color: highlight
                      ? scheme.primary.withValues(alpha: 0.12)
                      : null,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text(
                          index.rootLabel,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '新規ファイル',
                      onPressed: _createFile,
                      icon: const Icon(Icons.note_add_outlined, size: 18),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                    ),
                    IconButton(
                      tooltip: '新規フォルダ',
                      onPressed: _createFolder,
                      icon: const Icon(
                        Icons.create_new_folder_outlined,
                        size: 18,
                      ),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                    ),
                    IconButton(
                      tooltip: 'ファイル情報を更新',
                      onPressed: () => context.read<CodingAssistBloc>().add(
                        const CodingAssistRefreshWorkspaceRequested(),
                      ),
                      icon: const Icon(Icons.refresh, size: 18),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 8),
            children: [
              for (final node in nodes)
                _FileTreeNodeTile(
                  node: node,
                  depth: 0,
                  fontSize: state.uiFontSizes.menu,
                  activeTabPath: state.activeTabPath,
                  selectedPath: _selectedPath,
                  hasGit: state.gitBranch != null,
                  onSelect: _select,
                  dirController: _dirController,
                  wantsExpanded: _wantsExpanded,
                  onFolderExpansionChanged: _scheduleFolderExpansionSave,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBody(CodingAssistState state) {
    final enabled = state.workspaceRoot != null && !_searchBusy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      enabled: enabled,
                      style: TextStyle(fontSize: state.uiFontSizes.menu),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: '検索語',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                      ),
                      onSubmitted: enabled ? (_) => _runSearch() : null,
                    ),
                  ),
                  CodingMatchCaseButton(
                    selected: _searchCaseSensitive,
                    onPressed: enabled ? _toggleSearchCase : null,
                  ),
                  const SizedBox(width: 6),
                  FilledButton(
                    onPressed: enabled ? _runSearch : null,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 36),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: _searchBusy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('検索', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _replaceController,
                      enabled: enabled,
                      style: const TextStyle(fontSize: 12),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: '置換後',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                      ),
                      onSubmitted: enabled ? (_) => _runReplaceAll() : null,
                    ),
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton(
                    onPressed: enabled ? _runReplaceAll : null,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 36),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('すべて置換', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_searchStatus != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              _searchStatus!,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 8),
            itemCount: _searchHits.length,
            itemBuilder: (context, i) {
              final hit = _searchHits[i];
              return InkWell(
                onTap: () {
                  context.read<CodingAssistBloc>().add(
                    CodingAssistOpenFileRequested(
                      hit.relativePath,
                      revealLine: hit.lineNumber,
                      revealOffset: hit.matchStart,
                      revealLength: hit.matchLength,
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${hit.relativePath}:${hit.lineNumber}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hit.snippet,
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildGitBody(CodingAssistState state) {
    final enabled = state.workspaceRoot != null && !_gitBusy;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _commitController,
            enabled: enabled,
            minLines: 2,
            maxLines: 4,
            style: const TextStyle(fontSize: 12),
            decoration: const InputDecoration(
              isDense: true,
              hintText: 'コミットメッセージ',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: enabled ? _runCommit : null,
            child: _gitBusy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Commit'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 0, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'メニュー',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: state.uiFontSizes.menu,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'メニューを折りたたむ',
                onPressed: widget.onCollapse,
                icon: const Icon(Icons.chevron_left, size: 20),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        _sectionHeader(
          title: 'フォルダ操作',
          expanded: _folderExpanded,
          onToggle: () => setState(() => _folderExpanded = !_folderExpanded),
        ),
        if (_folderExpanded) Expanded(flex: 2, child: _buildFolderBody(state)),
        const Divider(height: 1),
        _sectionHeader(
          title: 'フォルダ内文言検索',
          expanded: _searchExpanded,
          onToggle: () => setState(() => _searchExpanded = !_searchExpanded),
        ),
        if (_searchExpanded) Expanded(flex: 3, child: _buildSearchBody(state)),
        const Divider(height: 1),
        _sectionHeader(
          title: 'Git commit',
          expanded: _gitExpanded,
          onToggle: () => setState(() => _gitExpanded = !_gitExpanded),
        ),
        if (_gitExpanded) _buildGitBody(state),
      ],
    );
  }
}

class _LeftMenuCollapsedStrip extends StatelessWidget {
  const _LeftMenuCollapsedStrip({required this.onExpand});

  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Column(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque, // これがないとExpandedの余白がクリック不可
              onTap: onExpand,
              child: Center(
                child: RotatedBox(
                  quarterTurns: 3,
                  child: Text(
                    'メニュー',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).hintColor,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FileTreeNodeTile extends StatelessWidget {
  const _FileTreeNodeTile({
    required this.node,
    required this.depth,
    required this.fontSize,
    required this.activeTabPath,
    required this.selectedPath,
    required this.hasGit,
    required this.onSelect,
    required this.dirController,
    required this.wantsExpanded,
    required this.onFolderExpansionChanged,
  });

  final CodingFileTreeNode node;
  final int depth;
  final double fontSize;
  final String? activeTabPath;
  final String? selectedPath;
  final bool hasGit;
  final void Function(String path, {required bool isDirectory}) onSelect;
  final ExpansibleController Function(
    String relativePath, {
    required bool expanded,
  })
  dirController;
  final bool Function(
    String relativePath, {
    required bool preferInitiallyExpanded,
  })
  wantsExpanded;
  final VoidCallback onFolderExpansionChanged;

  static const _density = VisualDensity(horizontal: 0, vertical: -4);

  /// ファイル行とディレクトリ行を同じ高さにする。展開アイコンの既定余白より詰める。
  double get _rowHeight => (fontSize + 4).clamp(18.0, 28.0);

  String get _dropTargetDir {
    if (node.isDirectory) return node.relativePath;
    final parent = p.dirname(node.relativePath);
    if (parent == '.' || parent == '/') return '';
    return parent;
  }

  bool _isInvalidDrop(_TreeDragPayload data) {
    final src = data.relativePath;
    final targetDir = _dropTargetDir;
    if (src == node.relativePath) return true;
    final srcParent = p.dirname(src);
    final normalizedParent = (srcParent == '.' || srcParent == '/')
        ? ''
        : srcParent;
    if (normalizedParent == targetDir) return true;
    if (data.isDirectory &&
        (targetDir == src || targetDir.startsWith('$src/'))) {
      return true;
    }
    return false;
  }

  Future<void> _showContextMenu(
    BuildContext context,
    Offset globalPosition,
  ) async {
    onSelect(node.relativePath, isDirectory: node.isDirectory);
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      items: [
        const PopupMenuItem(value: 'rename', child: Text('RENAME')),
        const PopupMenuItem(value: 'delete', child: Text('DELETE')),
        if (hasGit)
          PopupMenuItem(
            value: 'git_add',
            child: Text(node.isDirectory ? 'Git Add（フォルダ）' : 'Git Add（ファイル）'),
          ),
        const PopupMenuItem(value: 'copy_name', child: Text('名前のコピー')),
        const PopupMenuItem(value: 'copy_path', child: Text('パスをコピー')),
        if (node.isDirectory)
          const PopupMenuItem(
            value: 'copy_structure',
            child: Text('フォルダ構造をAgent貼り付け'),
          ),
        if (node.isDirectory)
          const PopupMenuItem(
            value: 'attach_folder_files',
            child: Text('フォルダが持っているファイルを全てAgentに追加'),
          ),
      ],
    );
    if (selected == null || !context.mounted) return;
    final bloc = context.read<CodingAssistBloc>();
    if (selected == 'rename') {
      final name = await _promptCodingEntryName(
        context,
        title: 'RENAME',
        hint: node.name,
        initialValue: node.name,
        confirmLabel: 'RENAME',
      );
      if (name == null || !context.mounted) return;
      bloc.add(
        CodingAssistRenamePathRequested(
          relativePath: node.relativePath,
          isDirectory: node.isDirectory,
          newName: name,
        ),
      );
      return;
    }
    if (selected == 'delete') {
      final ok = await showBrandConfirmDialog(
        context: context,
        title: 'DELETE',
        message: node.isDirectory
            ? 'フォルダを削除しますか？\n${node.relativePath}'
            : 'ファイルを削除しますか？\n${node.relativePath}',
        confirmLabel: 'DELETE',
        isDestructive: true,
      );
      if (!ok || !context.mounted) return;
      bloc.add(
        CodingAssistDeletePathRequested(
          relativePath: node.relativePath,
          isDirectory: node.isDirectory,
        ),
      );
      return;
    }
    if (selected == 'git_add') {
      bloc.add(CodingAssistGitAddRequested(relativePath: node.relativePath));
      return;
    }
    if (selected == 'copy_name') {
      final name = node.name;
      if (name.isEmpty) return;
      await Clipboard.setData(ClipboardData(text: name));
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('名前をコピーしました')));
      }
      return;
    }
    if (selected == 'copy_path') {
      final path = node.relativePath.replaceAll('\\', '/');
      if (path.isEmpty) return;
      await Clipboard.setData(ClipboardData(text: path));
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('パスをコピーしました')));
      }
      return;
    }
    if (selected == 'copy_structure') {
      final path = node.relativePath.replaceAll('\\', '/');
      bloc.add(
        CodingAssistFolderStructureAttached(
          CodingAttachedFolderStructure(
            relativePath: path == '.' ? '' : path,
            block: node.toAgentStructureBlock(),
          ),
        ),
      );
      return;
    }
    if (selected == 'attach_folder_files') {
      final path = node.relativePath.replaceAll('\\', '/');
      bloc.add(CodingAssistFolderFilesAttachRequested(path == '.' ? '' : path));
    }
  }

  Widget _dragHandle({required BuildContext context, required Widget child}) {
    final scheme = Theme.of(context).colorScheme;
    final payload = _TreeDragPayload(
      relativePath: node.relativePath,
      isDirectory: node.isDirectory,
    );
    // ExpansionTile 全体を Draggable で包まない（deactivate assertion 回避）
    return Draggable<_TreeDragPayload>(
      data: payload,
      feedback: Material(
        elevation: 3,
        color: scheme.surface,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(node.name, style: TextStyle(fontSize: fontSize)),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: child),
      child: GestureDetector(
        onSecondaryTapDown: (details) =>
            _showContextMenu(context, details.globalPosition),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final indent = 6.0 + depth * 10.0;
    final selected =
        selectedPath == node.relativePath ||
        (!node.isDirectory && activeTabPath == node.relativePath);
    final scheme = Theme.of(context).colorScheme;
    final rowHeight = _rowHeight;

    return DragTarget<_TreeDragPayload>(
      onWillAcceptWithDetails: (details) => !_isInvalidDrop(details.data),
      onAcceptWithDetails: (details) {
        context.read<CodingAssistBloc>().add(
          CodingAssistMovePathRequested(
            sourceRelativePath: details.data.relativePath,
            sourceIsDirectory: details.data.isDirectory,
            targetDirectoryRelativePath: _dropTargetDir,
          ),
        );
      },
      builder: (context, candidate, rejected) {
        final highlight = candidate.isNotEmpty;
        final deco = BoxDecoration(
          color: highlight ? scheme.primary.withValues(alpha: 0.14) : null,
        );

        if (node.isDirectory) {
          final expanded = wantsExpanded(
            node.relativePath,
            preferInitiallyExpanded: node.preferInitiallyExpanded,
          );
          return DecoratedBox(
            decoration: deco,
            child: Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: IconTheme(
                data: const IconThemeData(size: 16),
                child: ListTileTheme.merge(
                  dense: true,
                  minVerticalPadding: 0,
                  child: ExpansionTile(
                    key: ValueKey('coding-dir:${node.relativePath}'),
                    controller: dirController(
                      node.relativePath,
                      expanded: expanded,
                    ),
                    initiallyExpanded: expanded,
                    tilePadding: EdgeInsets.only(left: indent, right: 2),
                    childrenPadding: EdgeInsets.zero,
                    dense: true,
                    visualDensity: _density,
                    minTileHeight: rowHeight,
                    title: _dragHandle(
                      context: context,
                      child: Row(
                        children: [
                          Icon(
                            Icons.folder,
                            size: 14,
                            color: selected
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              node.name,
                              style: TextStyle(
                                fontSize: fontSize,
                                height: 1,
                                fontWeight: FontWeight.w500,
                                color: selected ? scheme.primary : null,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    onExpansionChanged: (_) {
                      onSelect(node.relativePath, isDirectory: true);
                      onFolderExpansionChanged();
                    },
                    children: [
                      for (final child in node.children)
                        _FileTreeNodeTile(
                          node: child,
                          depth: depth + 1,
                          fontSize: fontSize,
                          activeTabPath: activeTabPath,
                          selectedPath: selectedPath,
                          hasGit: hasGit,
                          onSelect: onSelect,
                          dirController: dirController,
                          wantsExpanded: wantsExpanded,
                          onFolderExpansionChanged: onFolderExpansionChanged,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        return DecoratedBox(
          decoration: deco,
          child: _dragHandle(
            context: context,
            child: Material(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.12)
                  : Colors.transparent,
              child: InkWell(
                onTap: () {
                  onSelect(node.relativePath, isDirectory: false);
                  context.read<CodingAssistBloc>().add(
                    CodingAssistOpenFileRequested(node.relativePath),
                  );
                },
                child: SizedBox(
                  height: rowHeight,
                  child: Padding(
                    padding: EdgeInsets.only(left: indent, right: 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        node.name,
                        style: TextStyle(
                          fontSize: fontSize,
                          height: 1,
                          color: selected ? scheme.primary : null,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
