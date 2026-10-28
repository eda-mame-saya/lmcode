part of '../pages/coding_assist_page.dart';

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.state,
    required this.customModels,
    required this.onOpenFolder,
    required this.onOpenEngineSettings,
  });

  final CodingAssistState state;
  final List<CustomLlmModel> customModels;
  final VoidCallback onOpenFolder;
  final VoidCallback onOpenEngineSettings;

  @override
  Widget build(BuildContext context) {
    final llm = state.localLlm;
    String? value;
    if (llm.usesCustomCodingModel) {
      final id = llm.codingCustomModelId?.trim() ?? '';
      final file = llm.codingCustomGgufFileName?.trim() ?? '';
      if (GemmaMtpDraft.isDraftFileName(file)) {
        value = null;
      } else if (id.isNotEmpty && customModels.any((m) => m.id == id)) {
        value = 'custom:$id';
      } else {
        final byFile = customModels.where((m) => m.ggufFileName == file);
        if (byFile.isNotEmpty) value = 'custom:${byFile.first.id}';
      }
    }
    return Material(
      elevation: 1,
      child: Row(
        children: [
          if (state.gitBranch != null) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: 'Git ブランチ',
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.call_split,
                      size: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 160),
                      child: Text(
                        state.gitBranch!,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          Expanded(
            child: SizedBox(),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: onOpenFolder,
            icon: const Icon(Icons.folder_open, size: 18),
            label: const Text('フォルダを開く'),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 300,
            child: DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: value,
              isDense: true,
              hint: Text(
                customModels.isEmpty
                    ? 'モデルを追加（設定）'
                    : LocalLlmPresets.unsetModelLabel,
              ),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
              ),
              items: [
                for (final m in customModels)
                  if (!GemmaMtpDraft.isDraftFileName(m.ggufFileName))
                    DropdownMenuItem(
                      value: 'custom:${m.id}',
                      child: Text(m.label),
                    ),
              ],
              onChanged:
                  state.isGenerating ||
                      state.isLlmBusy ||
                      customModels.isEmpty
                  ? null
                  : (key) {
                      if (key == null || key == value) return;
                      if (!key.startsWith('custom:')) return;
                      final id = key.substring('custom:'.length);
                      final m = customModels
                          .where((e) => e.id == id)
                          .firstOrNull;
                      if (m != null) {
                        context.read<CodingAssistBloc>().add(
                          CodingAssistCodingModelChanged(m),
                        );
                      }
                    },
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'エンジン設定',
            onPressed: state.isGenerating || state.isLlmBusy
                ? null
                : onOpenEngineSettings,
            icon: const Icon(Icons.tune),
            visualDensity: VisualDensity.compact,
          ),
          ValueListenableBuilder<bool>(
            valueListenable: context
                .read<CodingAssistBloc>()
                .autoSleepArmedNow,
            builder: (context, armed, _) {
              return IconButton(
                tooltip: armed ? '設定（スリープ予定あり）' : '表示・Agent・ハーネスの設定',
                onPressed: () => showCodingAssistSettingsDialog(context),
                icon: Icon(
                  Icons.settings,
                  color: armed ? Theme.of(context).colorScheme.primary : null,
                ),
                visualDensity: VisualDensity.compact,
              );
            },
          ),
          const SizedBox(width: 4),
          const CodingRamUsageIndicator(),
        ],
      ),
    );
  }
}
