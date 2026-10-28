part of '../pages/coding_assist_page.dart';

class _AgentResizeHandle extends StatelessWidget {
  const _AgentResizeHandle({required this.onDrag});

  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
        child: SizedBox(
          width: 6,
          child: Center(
            child: Container(width: 1, color: scheme.outlineVariant),
          ),
        ),
      ),
    );
  }
}

class _AgentCollapsedStrip extends StatelessWidget {
  const _AgentCollapsedStrip({required this.onExpand});

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
              child: RotatedBox(
                quarterTurns: 3,
                child: Center(
                  child: Text(
                    'Agent',
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

class _ChatPane extends StatelessWidget {
  const _ChatPane({
    required this.draftController,
    required this.hasEditorSelection,
    required this.onAttachSelection,
    required this.onReplaceSelectionWithProposal,
    required this.onInsertAtCursorWithProposal,
    required this.activeEditorAttachment,
    required this.onCollapse,
  });

  final TextEditingController draftController;
  final bool hasEditorSelection;
  final VoidCallback onAttachSelection;
  final Future<void> Function(CodingProposedPatch patch)
  onReplaceSelectionWithProposal;
  final Future<void> Function(CodingProposedPatch patch)
  onInsertAtCursorWithProposal;
  final CodingAttachedOpenFile? Function() activeEditorAttachment;
  final VoidCallback onCollapse;

  void _sendIfPossible(
    BuildContext context,
    bool canAct,
    CodingAssistState state,
  ) {
    if (!canAct || !state.canSend) return;
    context.read<CodingAssistBloc>().add(const CodingAssistSendRequested());
  }

  Future<void> _copyDebugExchange(
    BuildContext context,
    CodingAssistState state,
  ) async {
    final text = codingDebugExchangeText(
      state.messages,
      generationTrace: state.generationTrace,
    );
    if (text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('コピーする入力と出力がありません')));
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('入力と出力をコピーしました')));
    }
  }

  Future<void> _togglePromptAction(
    BuildContext context,
    CodingPromptAction action,
  ) async {
    final bloc = context.read<CodingAssistBloc>();
    final state = bloc.state;
    final turningOn = !state.appliedPromptActions.contains(action);
    if (turningOn &&
        action == CodingPromptAction.programAnalyze &&
        state.attachedOpenFiles.isEmpty) {
      final fallback = activeEditorAttachment();
      if (fallback == null) {
        await showBrandConfirmDialog(
          context: context,
          title: 'プログラム分析',
          message: 'ファイルを取り込むか、エディタでファイルを開いてください',
          cancelLabel: '閉じる',
          confirmLabel: 'OK',
        );
        return;
      }
      bloc.add(CodingAssistOpenFilesAttached([fallback]));
    }
    bloc.add(CodingAssistPromptActionToggled(action));
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CodingAssistBloc, CodingAssistState>(
      builder: (context, state) {
        final canAct =
            state.workspaceRoot != null &&
            !state.isGenerating &&
            !state.isLlmBusy;
        final historyOpen = state.isHistoryOpen;
        final warn = state.warningLevel;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Agent を折りたたむ',
                    onPressed: onCollapse,
                    icon: const Icon(Icons.chevron_right, size: 20),
                    visualDensity: VisualDensity.compact,
                  ),
                  Text(
                    historyOpen ? 'ヒストリー' : 'Agent',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (!historyOpen) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        state.contextUsageLabel,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: warn == CodingContextWarningLevel.block
                              ? Theme.of(context).colorScheme.error
                              : warn == CodingContextWarningLevel.warn ||
                                    warn == CodingContextWarningLevel.compacted
                              ? Theme.of(context).colorScheme.tertiary
                              : null,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                  if (!historyOpen && warn != CodingContextWarningLevel.none)
                    Expanded(child: _ContextWarnBanner(level: warn)),
                  const SizedBox(width: 8),
                  if (historyOpen)
                    IconButton(
                      tooltip: 'ヒストリーを閉じる',
                      onPressed: () => context.read<CodingAssistBloc>().add(
                        const CodingAssistHistoryCloseRequested(),
                      ),
                      icon: const Icon(Icons.close, size: 20),
                      visualDensity: VisualDensity.compact,
                    )
                  else ...[
                    if (kDebugMode)
                      IconButton(
                        tooltip: '入力と出力をコピー',
                        onPressed: () => _copyDebugExchange(context, state),
                        icon: const Icon(Icons.copy_all, size: 20),
                        visualDensity: VisualDensity.compact,
                      ),
                    IconButton(
                      tooltip: 'ヒストリー',
                      onPressed: state.workspaceRoot == null
                          ? null
                          : () => context.read<CodingAssistBloc>().add(
                              const CodingAssistHistoryOpenRequested(),
                            ),
                      icon: const Icon(Icons.history, size: 20),
                      visualDensity: VisualDensity.compact,
                    ),
                    TextButton(
                      onPressed: canAct
                          ? () => context.read<CodingAssistBloc>().add(
                              const CodingAssistNewThreadRequested(),
                            )
                          : null,
                      child: const Text('新規'),
                    ),
                    TextButton(
                      onPressed: canAct && state.messages.isNotEmpty
                          ? () => context.read<CodingAssistBloc>().add(
                              const CodingAssistCompactContextRequested(),
                            )
                          : null,
                      child: const Text('圧縮'),
                    ),
                    if (state.isGenerating)
                      TextButton(
                        onPressed: () => context.read<CodingAssistBloc>().add(
                          const CodingAssistStopRequested(),
                        ),
                        child: const Text('停止'),
                      ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: historyOpen
                  ? _HistoryList(state: state)
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount:
                          state.messages.length +
                          ((state.isGenerating ||
                                  state.generationTrace.trim().isNotEmpty)
                              ? 1
                              : 0) +
                          state.pendingPatches.length,
                      itemBuilder: (context, i) {
                        final msgCount = state.messages.length;
                        if (i < msgCount) {
                          return _Bubble(
                            message: state.messages[i],
                            fontSize: state.uiFontSizes.agent,
                            showEditActions:
                                state.messages[i].role ==
                                    CodingMessageRole.user &&
                                i == state.lastUserMessageIndex &&
                                state.canEditOrRevokeLastUser,
                            onEdit: () => context.read<CodingAssistBloc>().add(
                              const CodingAssistEditLastUserRequested(),
                            ),
                            onRerun: () => context.read<CodingAssistBloc>().add(
                              const CodingAssistRerunLastUserRequested(),
                            ),
                            onRevoke: () =>
                                context.read<CodingAssistBloc>().add(
                                  const CodingAssistRevokeLastTurnRequested(),
                                ),
                          );
                        }
                        var idx = i - msgCount;
                        final showGenLog =
                            state.isGenerating ||
                            state.generationTrace.trim().isNotEmpty;
                        if (showGenLog) {
                          if (idx == 0) {
                            return _GenerationProgressFold(
                              isGenerating: state.isGenerating,
                              statusMessage: state.isGenerating
                                  ? (state.agentStatusMessage ?? '生成中…')
                                  : '直前の生成ログ',
                              generationTrace: state.generationTrace,
                              streamingText: state.streamingText,
                            );
                          }
                          idx -= 1;
                        }
                        return _PatchCard(
                          patch: state.pendingPatches[idx],
                          onReplaceSelection: onReplaceSelectionWithProposal,
                          onInsertAtCursor: onInsertAtCursorWithProposal,
                        );
                      },
                    ),
            ),
            if (!historyOpen)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (state.isEditingLastUser)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '直近のメッセージを編集中（送信で再生成）',
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    if (state.attachedOpenFiles.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: _PendingOpenFilesBar(
                          files: state.attachedOpenFiles,
                          enabled: canAct,
                          onRemove: (path) => context
                              .read<CodingAssistBloc>()
                              .add(CodingAssistOpenFileAttachmentRemoved(path)),
                          onClearAll: () =>
                              context.read<CodingAssistBloc>().add(
                                const CodingAssistOpenFileAttachmentsCleared(),
                              ),
                        ),
                      ),
                    if (state.attachedSelection != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Text(
                              '情報が付与されました',
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context).hintColor,
                              ),
                            ),
                            IconButton(
                              tooltip: '付与情報を削除',
                              onPressed: () => context
                                  .read<CodingAssistBloc>()
                                  .add(const CodingAssistSelectionCleared()),
                              icon: const Icon(Icons.close, size: 14),
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints(
                                minWidth: 28,
                                minHeight: 28,
                              ),
                              padding: EdgeInsets.zero,
                            ),
                          ],
                        ),
                      ),
                    if (state.attachedFolderStructures.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final folder in state.attachedFolderStructures)
                              Row(
                                children: [
                                  const Icon(
                                    Icons.account_tree_outlined,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      'フォルダ構造: ${folder.chipLabel}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Theme.of(context).hintColor,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'フォルダ構造を外す',
                                    onPressed: canAct
                                        ? () => context
                                              .read<CodingAssistBloc>()
                                              .add(
                                                CodingAssistFolderStructureRemoved(
                                                  folder.relativePath,
                                                ),
                                              )
                                        : null,
                                    icon: const Icon(Icons.close, size: 14),
                                    visualDensity: VisualDensity.compact,
                                    constraints: const BoxConstraints(
                                      minWidth: 28,
                                      minHeight: 28,
                                    ),
                                    padding: EdgeInsets.zero,
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    CodingDraftPromptField(
                      controller: draftController,
                      enabled: canAct,
                      fontSize: state.uiFontSizes.agent,
                      onChanged: (v) => context.read<CodingAssistBloc>().add(
                        CodingAssistDraftChanged(v),
                      ),
                      onSubmitShortcut: () =>
                          _sendIfPossible(context, canAct, state),
                      sendButton: _AgentSendButton(
                        onPressed: !state.canSend
                            ? null
                            : () => context.read<CodingAssistBloc>().add(
                                const CodingAssistSendRequested(),
                              ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _AgentPromptActionsRow(
                        enabled: canAct,
                        selectionEnabled: hasEditorSelection,
                        taskEvaluateEnabled:
                            codingTaskEvaluationSource(state.messages) != null,
                        favorites: state.promptFavorites,
                        applied: state.appliedPromptActions,
                        onSelected: (action) {
                          switch (action) {
                            case CodingPromptAction.attachSelection:
                              onAttachSelection();
                            case CodingPromptAction.taskEvaluate:
                              context.read<CodingAssistBloc>().add(
                                const CodingAssistTaskEvaluateRequested(),
                              );
                            case CodingPromptAction.errorAnalyze:
                            case CodingPromptAction.concise:
                            case CodingPromptAction.expectFileOutput:
                            case CodingPromptAction.expectFixProposal:
                            case CodingPromptAction.expectDocumentCreate:
                            case CodingPromptAction.expectDocumentEdit:
                            case CodingPromptAction.programAnalyze:
                            case CodingPromptAction.taskDecompose:
                            case CodingPromptAction.runFlutterVerify:
                              _togglePromptAction(context, action);
                          }
                        },
                        onToggleFavorite: (action) {
                          context.read<CodingAssistBloc>().add(
                            CodingAssistPromptFavoriteToggled(action),
                          );
                        },
                      ),
                    ),
                    if (state.appliedPromptActions.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              '適用',
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context).hintColor,
                              ),
                            ),
                            for (final action in state.appliedPromptActions)
                              InputChip(
                                label: Text(
                                  action.shortLabel,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                onDeleted: canAct
                                    ? () =>
                                          context.read<CodingAssistBloc>().add(
                                            CodingAssistPromptActionToggled(
                                              action,
                                            ),
                                          )
                                    : null,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// S13 の取り込みファイルバーに近い、送信前の開いているファイル表示。
class _PendingOpenFilesBar extends StatefulWidget {
  const _PendingOpenFilesBar({
    required this.files,
    required this.enabled,
    required this.onRemove,
    required this.onClearAll,
  });

  final List<CodingAttachedOpenFile> files;
  final bool enabled;
  final ValueChanged<String> onRemove;
  final VoidCallback onClearAll;

  @override
  State<_PendingOpenFilesBar> createState() => _PendingOpenFilesBarState();
}

class _PendingOpenFilesBarState extends State<_PendingOpenFilesBar> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final files = widget.files;
    final enabled = widget.enabled;
    final colors = AppColors.of(context);
    return Material(
      color: colors.panelAccentSoft,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              child: Row(
                children: [
                  Icon(
                    _expanded ? Icons.expand_more : Icons.chevron_right,
                    color: colors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '取り込み中のファイル（${files.length}）',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: enabled ? widget.onClearAll : null,
                    child: const Text('すべて削除'),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Column(
                children: [
                  for (final f in files)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Material(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                          child: Row(
                            children: [
                              const Icon(Icons.description_outlined, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  f.relativePath,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              IconButton(
                                tooltip: 'この取り込みを削除',
                                onPressed: enabled
                                    ? () => widget.onRemove(f.relativePath)
                                    : null,
                                icon: const Icon(Icons.close, size: 16),
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ContextWarnBanner extends StatelessWidget {
  const _ContextWarnBanner({required this.level});

  final CodingContextWarningLevel level;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final blocked = level == CodingContextWarningLevel.block;
    final text = switch (level) {
      CodingContextWarningLevel.block => 'コンテキスト上限です',
      CodingContextWarningLevel.compacted => 'コンテキストを圧縮済み',
      CodingContextWarningLevel.warn => 'コンテキスト使用量が多くなっています',
      CodingContextWarningLevel.none => '',
    };
    return Material(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            color: blocked
                ? scheme.onErrorContainer
                : scheme.onTertiaryContainer,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

/// 入力欄と同じ高さに伸びる角丸送信ボタン。
class _AgentSendButton extends StatelessWidget {
  const _AgentSendButton({required this.onPressed});

  final VoidCallback? onPressed;

  static const _radius = 4.0;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final enabled = onPressed != null;
    final bg = enabled
        ? colors.primary
        : colors.primary.withValues(alpha: 0.35);
    final fg = enabled
        ? colors.onPrimary
        : colors.onPrimary.withValues(alpha: 0.7);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(_radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(_radius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.send, size: 18, color: fg),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.state});

  final CodingAssistState state;

  @override
  Widget build(BuildContext context) {
    final items = state.workspaceThreadSummaries;
    if (items.isEmpty) {
      return const Center(
        child: Text('このワークスペースの履歴はまだありません', style: TextStyle(fontSize: 13)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final selected = state.thread?.id == item.id;
        return ListTile(
          dense: true,
          selected: selected,
          title: Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
          subtitle: Text(
            _formatHistoryTime(item.updatedAt),
            style: const TextStyle(fontSize: 11),
          ),
          trailing: IconButton(
            tooltip: '削除',
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: state.isGenerating
                ? null
                : () => context.read<CodingAssistBloc>().add(
                    CodingAssistDeleteThreadRequested(item.id),
                  ),
          ),
          onTap: state.isGenerating
              ? null
              : () => context.read<CodingAssistBloc>().add(
                  CodingAssistOpenThreadRequested(item.id),
                ),
        );
      },
    );
  }

  String _formatHistoryTime(DateTime at) {
    final local = at.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}/${two(local.month)}/${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

class _Bubble extends StatefulWidget {
  const _Bubble({
    required this.message,
    required this.fontSize,
    this.showEditActions = false,
    this.onEdit,
    this.onRerun,
    this.onRevoke,
  });

  final CodingChatMessage message;
  final double fontSize;
  final bool showEditActions;
  final VoidCallback? onEdit;
  final VoidCallback? onRerun;
  final VoidCallback? onRevoke;

  @override
  State<_Bubble> createState() => _BubbleState();
}

class _BubbleState extends State<_Bubble> {
  /// 長いユーザー文は既定で簡易（先頭10行）。
  bool _showFullPrompt = false;

  @override
  void didUpdateWidget(covariant _Bubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.content != widget.message.content ||
        oldWidget.message.requestText != widget.message.requestText ||
        oldWidget.message.historyChips.length !=
            widget.message.historyChips.length) {
      _showFullPrompt = false;
    }
  }

  Future<void> _copyAll(BuildContext context) async {
    final view = codingUserHistoryView(widget.message);
    final text = !view.split
        ? widget.message.content
        : (view.text.trim().isNotEmpty
              ? view.text
              : view.chips.map((chip) => chip.label).join('\n'));
    if (text.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('コピーしました')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final fontSize = widget.fontSize;
    final showEditActions = widget.showEditActions;
    final isUser = message.role == CodingMessageRole.user;
    final isTool = message.role == CodingMessageRole.tool;
    final isAssistant = message.role == CodingMessageRole.assistant;
    final canCopy = message.content.trim().isNotEmpty;
    final history = isUser ? codingUserHistoryView(message) : null;
    final shownText = history?.text ?? message.content;
    final promptLong = isUser && codingUserPromptExceedsPreview(shownText);
    final userText = promptLong && !_showFullPrompt
        ? codingUserPromptPreview(shownText)
        : shownText;
    final label = isTool
        ? 'tool:${message.toolName ?? ''}'
        : (isUser ? 'You' : 'AI');

    final colors = AppColors.of(context);
    final decoration = isUser
        ? BoxDecoration(
            color: colors.chatUserBubble,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.subtleBorder),
          )
        : null;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.fromLTRB(
        isUser ? 10 : 4,
        isUser ? 10 : 4,
        isUser ? 6 : 0,
        4,
      ),
      decoration: decoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!isTool)
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: colors.contentMuted,
              ),
            ),
          if (!isTool) const SizedBox(height: 4),
          if (isTool)
            _ToolResultFold(
              toolName: message.toolName ?? 'tool',
              content: message.content,
              onCopy: canCopy ? () => _copyAll(context) : null,
            )
          else if (isAssistant)
            _AgentMarkdownBody(data: message.content, fontSize: fontSize)
          else ...[
            if (history != null && history.chips.isNotEmpty)
              _HistoryAttachmentList(chips: history.chips),
            if (userText.trim().isNotEmpty)
              SelectableText(
                userText,
                style: TextStyle(
                  fontSize: fontSize,
                  color: colors.contentForeground,
                  height: 1.4,
                ),
              ),
          ],
          if (!isTool)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (promptLong)
                  TextButton(
                    onPressed: () =>
                        setState(() => _showFullPrompt = !_showFullPrompt),
                    style: TextButton.styleFrom(
                      foregroundColor: colors.contentFaint,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: Text(
                      _showFullPrompt ? '簡易' : '全文',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                if (showEditActions) ...[
                  IconButton(
                    tooltip: '再実行',
                    onPressed: widget.onRerun,
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    color: colors.contentFaint,
                    icon: const Icon(Icons.replay),
                  ),
                  IconButton(
                    tooltip: '編集',
                    onPressed: widget.onEdit,
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    color: colors.contentFaint,
                    icon: const Icon(Icons.edit),
                  ),
                  IconButton(
                    tooltip: '削除',
                    onPressed: widget.onRevoke,
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    color: colors.contentFaint,
                    icon: const Icon(Icons.delete),
                  ),
                ],
                IconButton(
                  tooltip: history?.split == true
                      ? '入力をコピー'
                      : '全文コピー（Markdown）',
                  onPressed: canCopy ? () => _copyAll(context) : null,
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  color: colors.contentFaint,
                  icon: const Icon(Icons.copy),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// 送信済みの添付。本文は出さず、パスだけを折りたたむ。
class _HistoryAttachmentList extends StatefulWidget {
  const _HistoryAttachmentList({required this.chips});

  final List<CodingHistoryChip> chips;

  @override
  State<_HistoryAttachmentList> createState() => _HistoryAttachmentListState();
}

class _HistoryAttachmentListState extends State<_HistoryAttachmentList> {
  late bool _expanded = widget.chips.length <= 6;

  @override
  Widget build(BuildContext context) {
    final chips = widget.chips;
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: colors.panelAccentSoft,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                child: Row(
                  children: [
                    Icon(
                      _expanded ? Icons.expand_more : Icons.chevron_right,
                      size: 18,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '添付（${chips.length}）',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                child: Column(
                  children: [
                    for (final chip in chips)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Row(
                          children: [
                            Icon(_historyChipIcon(chip.kind), size: 14),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                chip.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

IconData _historyChipIcon(CodingHistoryChipKind kind) {
  return switch (kind) {
    CodingHistoryChipKind.file => Icons.description_outlined,
    CodingHistoryChipKind.selection => Icons.short_text,
    CodingHistoryChipKind.folder => Icons.account_tree_outlined,
  };
}

/// 生成中／直前の生ログ。生成中は既定展開（ハルシネーション確認用）。
class _GenerationProgressFold extends StatefulWidget {
  const _GenerationProgressFold({
    required this.isGenerating,
    required this.statusMessage,
    required this.generationTrace,
    required this.streamingText,
  });

  final bool isGenerating;
  final String statusMessage;
  final String generationTrace;
  final String streamingText;

  @override
  State<_GenerationProgressFold> createState() =>
      _GenerationProgressFoldState();
}

class _GenerationProgressFoldState extends State<_GenerationProgressFold> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.isGenerating;
  }

  @override
  void didUpdateWidget(covariant _GenerationProgressFold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isGenerating && !oldWidget.isGenerating) {
      _expanded = true;
    } else if (!widget.isGenerating && oldWidget.isGenerating) {
      _expanded = false;
    }
  }

  String get _body {
    final parts = <String>[
      if (widget.generationTrace.trim().isNotEmpty) widget.generationTrace,
      if (widget.streamingText.trim().isNotEmpty) widget.streamingText,
    ];
    if (parts.isEmpty) {
      return '（応答待ち…）';
    }
    return parts.join('\n\n');
  }

  String get _summary {
    final body = _body;
    final chars = body == '（応答待ち…）' ? 0 : body.length;
    final lines = body == '（応答待ち…）' ? 0 : '\n'.allMatches(body).length + 1;
    if (chars == 0) return widget.statusMessage;
    return '${widget.statusMessage} · $chars文字 または $lines行';
  }

  Future<void> _copy() async {
    final text = _body;
    if (text.trim().isEmpty || text == '（応答待ち…）') return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('生成ログをコピーしました')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = AppColors.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.subtleBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
              child: Row(
                children: [
                  Icon(
                    _expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 18,
                    color: colors.contentMuted,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    widget.isGenerating ? '生成ログ' : '直前の生成ログ',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: colors.contentMuted,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.contentForeground,
                      ),
                    ),
                  ),
                  if (widget.isGenerating) ...[
                    SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  IconButton(
                    tooltip: '生成ログをコピー',
                    onPressed: _copy,
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    color: colors.contentFaint,
                    icon: const Icon(Icons.copy),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                reverse: true,
                child: SelectableText(
                  _body,
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.contentForeground,
                    height: 1.35,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// tool 結果（read_file 等）は既定で折りたたみ。
class _ToolResultFold extends StatefulWidget {
  const _ToolResultFold({
    required this.toolName,
    required this.content,
    this.onCopy,
  });

  final String toolName;
  final String content;
  final VoidCallback? onCopy;

  @override
  State<_ToolResultFold> createState() => _ToolResultFoldState();
}

class _ToolResultFoldState extends State<_ToolResultFold> {
  bool _expanded = false;

  String get _summary {
    final lines = widget.content.split('\n');
    final nonEmpty = lines.where((l) => l.trim().isNotEmpty).length;
    // read_file 先頭に path があることが多い
    final first = lines.isEmpty ? '' : lines.first.trim();
    final pathHint = first.length > 64 ? '${first.substring(0, 64)}…' : first;
    if (pathHint.isNotEmpty &&
        (pathHint.contains('/') || pathHint.endsWith('.dart'))) {
      return '$pathHint · ${lines.length}行';
    }
    return '${widget.toolName} · ${lines.length}行'
        '${nonEmpty != lines.length ? '（空行含）' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = AppColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.subtleBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
              child: Row(
                children: [
                  Icon(
                    _expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 18,
                    color: colors.contentMuted,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    'tool:${widget.toolName}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: colors.contentMuted,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.contentForeground,
                      ),
                    ),
                  ),
                  if (widget.onCopy != null)
                    IconButton(
                      tooltip: '全文コピー',
                      onPressed: widget.onCopy,
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      color: colors.contentFaint,
                      icon: const Icon(Icons.copy),
                    ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: SelectableText(
                widget.content,
                style: TextStyle(
                  fontSize: 11,
                  color: colors.contentForeground,
                  height: 1.35,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// S13 AIチャットと同系統の Markdown 表示（Agent 返答用）。
class _AgentMarkdownBody extends StatelessWidget {
  const _AgentMarkdownBody({required this.data, required this.fontSize});

  final String data;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final foreground = colors.contentForeground;
    final codeBg = colors.codeBlockBackground;
    final base = TextStyle(color: foreground, fontSize: fontSize, height: 1.4);

    return MarkdownBody(
      data: data,
      selectable: true,
      shrinkWrap: true,
      softLineBreak: true,
      onTapLink: (text, href, title) {
        final path = codingAssistEditorLinkPath(href);
        if (path == null) return;
        context.read<CodingAssistBloc>().add(
          CodingAssistOpenFileRequested(path),
        );
      },
      inlineSyntaxes: codingMarkdownInlineSyntaxes(),
      styleSheet: MarkdownStyleSheet(
        p: base,
        pPadding: EdgeInsets.zero,
        h1: base.copyWith(fontSize: fontSize + 6, fontWeight: FontWeight.w700),
        h2: base.copyWith(fontSize: fontSize + 4, fontWeight: FontWeight.w700),
        h3: base.copyWith(fontSize: fontSize + 2, fontWeight: FontWeight.w700),
        h4: base.copyWith(fontWeight: FontWeight.w700),
        h5: base.copyWith(fontWeight: FontWeight.w700),
        h6: base.copyWith(fontWeight: FontWeight.w600),
        strong: base.copyWith(fontWeight: FontWeight.w700),
        em: base.copyWith(fontStyle: FontStyle.italic),
        del: base.copyWith(decoration: TextDecoration.lineThrough),
        listBullet: base,
        blockquote: base.copyWith(color: colors.contentMuted),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: colors.blockquoteBorder, width: 3),
          ),
        ),
        code: base.copyWith(
          fontSize: fontSize * 0.92,
          fontFamily: 'monospace',
          backgroundColor: codeBg,
        ),
        codeblockPadding: const EdgeInsets.all(10),
        codeblockDecoration: BoxDecoration(
          color: codeBg,
          borderRadius: BorderRadius.circular(6),
        ),
        a: base.copyWith(
          color: colors.primary,
          decoration: TextDecoration.underline,
        ),
        tableHead: base.copyWith(fontWeight: FontWeight.w700),
        tableBody: base,
        horizontalRuleDecoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.ruleBorder)),
        ),
      ),
      imageBuilder: (uri, title, alt) {
        final label = (alt != null && alt.trim().isNotEmpty)
            ? alt.trim()
            : uri.toString();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            '[画像: $label]',
            style: base.copyWith(
              fontStyle: FontStyle.italic,
              color: colors.contentMuted,
            ),
          ),
        );
      },
    );
  }
}
