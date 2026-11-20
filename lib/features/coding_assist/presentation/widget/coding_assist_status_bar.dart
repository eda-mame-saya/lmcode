part of '../pages/coding_assist_page.dart';

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.state,
    this.dartLspStatus,
    this.swiftLspStatus,
    this.dartServerRunning = false,
    this.swiftServerRunning = false,
  });

  final CodingAssistState state;
  final String? dartLspStatus;
  final String? swiftLspStatus;
  final bool dartServerRunning;
  final bool swiftServerRunning;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final modelLabel = state.agentModelLabel();
    final mtp = state.codingBackend == CodingLlmBackend.llamaCpp
        ? state.mtpDraftFileName
        : null;
    final agentProgress = [
      mtp == null || mtp.isEmpty ? 'model:$modelLabel' : 'model:$modelLabel · MTP',
      'ctx: ${state.usedTokens} / ${state.contextSize}',
      _agentProgressLabel(state),
    ].where((e) => e.isNotEmpty).join('  ·  ');
    final other = state.workspaceStatusMessage?.trim() ?? '';
    return Material(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            const SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  if (state.isGenerating && state.agentProgress != null) ...[
                    _AgentPhaseStepper(
                      progress: state.agentProgress!,
                      verifyExpected:
                          state.localLlm.codingAutoApplyPatches &&
                          state.index?.kind == CodingWorkspaceKind.flutter,
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      agentProgress,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(width: 1, height: 14, color: scheme.outlineVariant),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: Text(
                other,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(width: 12),
            Container(width: 1, height: 14, color: scheme.outlineVariant),
            const SizedBox(width: 12),
            _ServerRunLabel(
              name: 'Dart Analysis Server',
              running: dartServerRunning,
              detail: dartLspStatus,
            ),
            const SizedBox(width: 16),
            _ServerRunLabel(
              name: 'sourcekit-lsp',
              running: swiftServerRunning,
              detail: swiftLspStatus,
            ),
          ],
        ),
      ),
    );
  }
}

/// 自動実行の段階。「修正 2/3」の次に「生成 › 適用 › analyze › test」を並べ、
/// いまの段階を強調する。検証に進まない見込みのときは、いまの段階だけ見せる。
class _AgentPhaseStepper extends StatelessWidget {
  const _AgentPhaseStepper({
    required this.progress,
    required this.verifyExpected,
  });

  final CodingAgentProgress progress;
  final bool verifyExpected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stages = progress.stages(verifyExpected: verifyExpected);
    final currentIndex = stages.indexOf(progress.phase);
    final children = <Widget>[];
    if (progress.inFix) {
      children
        ..add(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: scheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              progress.fixLabel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: scheme.onErrorContainer,
              ),
            ),
          ),
        )
        ..add(const SizedBox(width: 6));
    }
    for (var n = 0; n < stages.length; n++) {
      if (n > 0) {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Icon(
              Icons.chevron_right,
              size: 12,
              color: scheme.outline,
            ),
          ),
        );
      }
      final isCurrent = n == currentIndex;
      final isDone = n < currentIndex;
      children.add(
        Text(
          stages[n].label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
            color: isCurrent
                ? scheme.primary
                : isDone
                ? scheme.onSurfaceVariant
                : scheme.outline,
            decoration: isDone ? TextDecoration.lineThrough : null,
          ),
        ),
      );
    }
    return Tooltip(
      message: progress.inFix
          ? '自動修正 ${progress.fixSet}/${progress.fixMax} セット目の進行'
          : '自動実行の進行',
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// Agent 進行。文言があるときはそれを優先し、無ければ起動中／生成中。
String _agentProgressLabel(CodingAssistState state) {
  final message = state.agentStatusMessage?.trim() ?? '';
  if (message.isNotEmpty) return message;
  if (state.isLlmBusy) return '起動中';
  if (state.isGenerating) return '生成中';
  return '';
}

/// 進行メッセージとは別の、言語サーバが動いているかの表示。
class _ServerRunLabel extends StatelessWidget {
  const _ServerRunLabel({
    required this.name,
    required this.running,
    this.detail,
  });

  final String name;
  final bool running;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final starting = !running && (detail?.contains('中') ?? false);
    final attempted = !running && detail != null && !starting;
    final colors = AppColors.of(context);
    final (label, color) = running
        ? ('起動', colors.statusRunning)
        : starting
            ? ('起動中', scheme.primary)
            : attempted
                ? ('停止', scheme.error)
                : ('未使用', scheme.outline);
    final tip =
        (detail == null || detail!.isEmpty) ? '$name は起動していません' : detail!;
    return Tooltip(
      message: tip,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            '$name $label',
            style: TextStyle(fontSize: 12, color: scheme.onSurface),
          ),
        ],
      ),
    );
  }
}
