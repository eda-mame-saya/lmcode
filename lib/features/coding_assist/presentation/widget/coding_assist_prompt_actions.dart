part of '../pages/coding_assist_page.dart';

/// メニュー選択結果（実行 or お気に入りトグル）。
sealed class _AgentPromptMenuPick {
  const _AgentPromptMenuPick();
}

final class _AgentPromptMenuRun extends _AgentPromptMenuPick {
  const _AgentPromptMenuRun(this.action);
  final CodingPromptAction action;
}

final class _AgentPromptMenuToggleFavorite extends _AgentPromptMenuPick {
  const _AgentPromptMenuToggleFavorite(this.action);
  final CodingPromptAction action;
}

/// 入力欄下の「＋」とお気に入りショートカット（最大2・1行）。
class _AgentPromptActionsRow extends StatelessWidget {
  const _AgentPromptActionsRow({
    required this.enabled,
    required this.selectionEnabled,
    required this.taskEvaluateEnabled,
    required this.favorites,
    required this.applied,
    required this.onSelected,
    required this.onToggleFavorite,
  });

  final bool enabled;
  final bool selectionEnabled;
  final bool taskEvaluateEnabled;
  final List<CodingPromptAction> favorites;
  final List<CodingPromptAction> applied;
  final ValueChanged<CodingPromptAction> onSelected;
  final ValueChanged<CodingPromptAction> onToggleFavorite;

  static const _size = 28.0;
  static const _width = 80.0;
  static const _radius = 4.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = enabled
        ? scheme.secondaryContainer
        : scheme.onSurface.withValues(alpha: 0.08);
    final fg = enabled
        ? scheme.onSecondaryContainer
        : scheme.onSurface.withValues(alpha: 0.38);
    final favoriteSet = favorites.toSet();
    final appliedSet = applied.toSet();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PopupMenuButton<_AgentPromptMenuPick>(
          tooltip: 'プロンプト補助',
          enabled: enabled,
          padding: EdgeInsets.zero,
          offset: const Offset(0, 4),
          position: PopupMenuPosition.under,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          onSelected: (pick) {
            switch (pick) {
              case _AgentPromptMenuRun(:final action):
                onSelected(action);
              case _AgentPromptMenuToggleFavorite(:final action):
                onToggleFavorite(action);
            }
          },
          itemBuilder: (context) => [
            _menuItem(
              context,
              action: CodingPromptAction.attachSelection,
              hint: codingAssistAttachSelectionHint,
              enabled: selectionEnabled,
              isFavorite: favoriteSet.contains(
                CodingPromptAction.attachSelection,
              ),
            ),
            _menuItem(
              context,
              action: CodingPromptAction.errorAnalyze,
              hint: codingAssistErrorAnalyzeHint,
              isFavorite: favoriteSet.contains(CodingPromptAction.errorAnalyze),
              isApplied: appliedSet.contains(CodingPromptAction.errorAnalyze),
            ),
            _menuItem(
              context,
              action: CodingPromptAction.concise,
              hint: codingAssistConciseHint,
              isFavorite: favoriteSet.contains(CodingPromptAction.concise),
              isApplied: appliedSet.contains(CodingPromptAction.concise),
            ),
            const PopupMenuDivider(),
            _menuItem(
              context,
              action: CodingPromptAction.expectFileOutput,
              hint: codingAssistExpectFileOutputHint,
              isFavorite: favoriteSet.contains(
                CodingPromptAction.expectFileOutput,
              ),
              isApplied: appliedSet.contains(
                CodingPromptAction.expectFileOutput,
              ),
            ),
            _menuItem(
              context,
              action: CodingPromptAction.expectFixProposal,
              hint: codingAssistExpectFixProposalHint,
              isFavorite: favoriteSet.contains(
                CodingPromptAction.expectFixProposal,
              ),
              isApplied: appliedSet.contains(
                CodingPromptAction.expectFixProposal,
              ),
            ),
            _menuItem(
              context,
              action: CodingPromptAction.expectDocumentCreate,
              hint: codingAssistExpectDocumentCreateHint,
              isFavorite: favoriteSet.contains(
                CodingPromptAction.expectDocumentCreate,
              ),
              isApplied: appliedSet.contains(
                CodingPromptAction.expectDocumentCreate,
              ),
            ),
            _menuItem(
              context,
              action: CodingPromptAction.expectDocumentEdit,
              hint: codingAssistExpectDocumentEditHint,
              isFavorite: favoriteSet.contains(
                CodingPromptAction.expectDocumentEdit,
              ),
              isApplied: appliedSet.contains(
                CodingPromptAction.expectDocumentEdit,
              ),
            ),
            _menuItem(
              context,
              action: CodingPromptAction.programAnalyze,
              hint: codingAssistProgramAnalyzeHint,
              isFavorite: favoriteSet.contains(
                CodingPromptAction.programAnalyze,
              ),
              isApplied: appliedSet.contains(CodingPromptAction.programAnalyze),
            ),
            _menuItem(
              context,
              action: CodingPromptAction.taskDecompose,
              hint: codingAssistTaskDecomposeHint,
              isFavorite: favoriteSet.contains(
                CodingPromptAction.taskDecompose,
              ),
              isApplied: appliedSet.contains(CodingPromptAction.taskDecompose),
            ),
            _menuItem(
              context,
              action: CodingPromptAction.taskEvaluate,
              hint: codingAssistTaskEvaluateHint,
              enabled: taskEvaluateEnabled,
              isFavorite: favoriteSet.contains(CodingPromptAction.taskEvaluate),
            ),
            _menuItem(
              context,
              action: CodingPromptAction.runFlutterVerify,
              hint: codingAssistRunFlutterVerifyHint,
              isFavorite: favoriteSet.contains(
                CodingPromptAction.runFlutterVerify,
              ),
              isApplied: appliedSet.contains(
                CodingPromptAction.runFlutterVerify,
              ),
            ),
          ],
          child: Material(
            color: bg,
            borderRadius: BorderRadius.circular(_radius),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: _width,
              height: _size,
              child: Icon(Icons.add, size: 18, color: fg),
            ),
          ),
        ),
        for (final action in favorites) ...[
          const SizedBox(width: 6),
          _AgentPromptFavoriteChip(
            label: action.shortLabel,
            tooltip: action.menuLabel,
            enabled:
                enabled &&
                (action != CodingPromptAction.attachSelection ||
                    selectionEnabled) &&
                (action != CodingPromptAction.taskEvaluate ||
                    taskEvaluateEnabled),
            applied: appliedSet.contains(action),
            onPressed: () => onSelected(action),
          ),
        ],
      ],
    );
  }

  PopupMenuItem<_AgentPromptMenuPick> _menuItem(
    BuildContext context, {
    required CodingPromptAction action,
    required String hint,
    required bool isFavorite,
    bool isApplied = false,
    bool enabled = true,
  }) {
    final theme = Theme.of(context);
    final labelColor = enabled
        ? null
        : theme.colorScheme.onSurface.withValues(alpha: 0.38);
    final starColor = isFavorite
        ? theme.colorScheme.tertiary
        : theme.colorScheme.onSurface.withValues(alpha: 0.45);
    // アクション無効時も ★ でお気に入り登録できるよう item 自体は有効のまま。
    return PopupMenuItem<_AgentPromptMenuPick>(
      value: enabled ? _AgentPromptMenuRun(action) : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      if (isApplied) ...[
                        Icon(
                          Icons.check,
                          size: 14,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          action.menuLabel,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: labelColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: isFavorite ? 'お気に入り解除' : 'お気に入り登録（最大2）',
              onPressed: () {
                Navigator.of(
                  context,
                ).pop(_AgentPromptMenuToggleFavorite(action));
              },
              icon: Icon(
                isFavorite ? Icons.star : Icons.star_border,
                size: 18,
                color: starColor,
              ),
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }
}

/// ＋隣の短いお気に入りボタン（高さは＋と同程度）。
class _AgentPromptFavoriteChip extends StatelessWidget {
  const _AgentPromptFavoriteChip({
    required this.label,
    required this.tooltip,
    required this.enabled,
    required this.applied,
    required this.onPressed,
  });

  final String label;
  final String tooltip;
  final bool enabled;
  final bool applied;
  final VoidCallback onPressed;

  static const _height = 28.0;
  static const _radius = 4.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = !enabled
        ? scheme.onSurface.withValues(alpha: 0.08)
        : applied
        ? scheme.primaryContainer
        : scheme.secondaryContainer;
    final fg = !enabled
        ? scheme.onSurface.withValues(alpha: 0.38)
        : applied
        ? scheme.onPrimaryContainer
        : scheme.onSecondaryContainer;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(_radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 28, minHeight: _height),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: fg,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
