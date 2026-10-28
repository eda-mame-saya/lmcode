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
    final llm = state.localLlm;
    final scheme = Theme.of(context).colorScheme;
    final modelLabel = llm.resolvedCodingModelLabel;
    final mtp = state.mtpDraftFileName;
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
              child: Text(
                agentProgress,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
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
