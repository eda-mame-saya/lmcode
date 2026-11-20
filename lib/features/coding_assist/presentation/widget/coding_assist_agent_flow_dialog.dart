part of '../pages/coding_assist_page.dart';

/// 「いまの入力だと Agent はどう動くか」を示すポップアップ（10 §4）。
///
/// 送信はしない。＋の選択・入力・自動実行・ワークスペース種別・パターンから
/// [CodingAgentFlow] が組み立てた見取り図を、状態が変わるたびに更新して見せる。
Future<void> showCodingAgentFlowDialog(BuildContext context) {
  final bloc = context.read<CodingAssistBloc>();
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      return BlocProvider.value(
        value: bloc,
        child: const _CodingAgentFlowDialog(),
      );
    },
  );
}

CodingAgentFlowInput _agentFlowInputFrom(CodingAssistState state) {
  final kind = state.index?.kind ?? CodingWorkspaceKind.generic;
  final system = CodingPatternProfiles.systemFor(kind);
  final level = state.patternSelection.levelOf(system);
  final harness = state.harness;
  final auto = state.localLlm.codingAutoApplyPatches;
  return CodingAgentFlowInput(
    actions: state.appliedPromptActions,
    draft: state.draft,
    hasAttachments: state.hasPromptAttachments,
    kind: kind,
    autoApply: auto,
    autoAllowReadFile: state.localLlm.codingAutoAllowReadFile,
    webLibraryDocs: state.webLibraryDocsEnabled,
    // 自動実行 ON の往復上限は OFF／ON の大きい方（bloc の `maxSteps` と同じ）。
    maxRounds: auto && harness.maxAgentStepsAuto > harness.maxAgentSteps
        ? harness.maxAgentStepsAuto
        : harness.maxAgentSteps,
    maxVerifySets: harness.maxVerifySets,
    maxReproposals: harness.maxAutoReproposals,
    readFilesPerBatch: harness.readFilesPerBatch,
    patternLabel: '${system.label}・${level.label}',
  );
}

class _CodingAgentFlowDialog extends StatelessWidget {
  const _CodingAgentFlowDialog();

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.8;
    return AlertDialog(
      title: const Text('Agent の動き（いまの入力の場合）'),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      content: SizedBox(
        width: 580,
        height: height.clamp(380, 760),
        child: BlocBuilder<CodingAssistBloc, CodingAssistState>(
          buildWhen: (p, c) =>
              p.appliedPromptActions != c.appliedPromptActions ||
              p.draft != c.draft ||
              p.hasPromptAttachments != c.hasPromptAttachments ||
              p.index?.kind != c.index?.kind ||
              p.localLlm.codingAutoApplyPatches !=
                  c.localLlm.codingAutoApplyPatches ||
              p.localLlm.codingAutoAllowReadFile !=
                  c.localLlm.codingAutoAllowReadFile ||
              p.webLibraryDocsEnabled != c.webLibraryDocsEnabled ||
              p.harness != c.harness ||
              p.patternSelection != c.patternSelection,
          builder: (context, state) {
            final preview = CodingAgentFlow.build(_agentFlowInputFrom(state));
            return _AgentFlowBody(preview: preview);
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('閉じる'),
        ),
      ],
    );
  }
}

class _AgentFlowBody extends StatelessWidget {
  const _AgentFlowBody({required this.preview});

  final CodingAgentFlowPreview preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hint = theme.hintColor;
    final v = preview.verdict;

    final (writeLabel, writeIcon) = switch (v.writes) {
      CodingFlowWrites.auto => (
        v.writesMaybe ? 'Patch が出たら自動で書き込む' : '自動で書き込む',
        Icons.edit_note,
      ),
      CodingFlowWrites.approval => (
        v.writesMaybe ? 'Patch が出たら承認後に書き込む' : '承認後に書き込む',
        Icons.touch_app_outlined,
      ),
      CodingFlowWrites.none => ('書き込まない', Icons.visibility_outlined),
    };
    final verifyLabel = switch (v.verifies) {
      CodingFlowVerifies.yes => '走る',
      CodingFlowVerifies.ifWritten => '書き込みがあれば走る',
      CodingFlowVerifies.none => '走らない',
    };
    final fixLabel = v.autoFixSets > 0 ? '最大 ${v.autoFixSets} セット' : 'なし';

    return ListView(
      children: [
        Text(
          preview.headline,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _VerdictTile(
                title: 'ファイル変更',
                value: writeLabel,
                icon: writeIcon,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _VerdictTile(
                title: 'analyze／test',
                value: verifyLabel,
                icon: Icons.science_outlined,
                emphasized: v.verifies != CodingFlowVerifies.none,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _VerdictTile(
                title: '失敗時の自動修正',
                value: fixLabel,
                icon: Icons.build_circle_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final label in preview.assumptions)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.dividerColor),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  label,
                  style: TextStyle(fontSize: 11, color: hint),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text('手順', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        for (var n = 0; n < preview.steps.length; n++)
          _FlowStepRow(
            step: preview.steps[n],
            isLast: n == preview.steps.length - 1 && preview.loop == null,
          ),
        if (preview.loop case final loop?) _FlowLoopBlock(loop: loop),
        const SizedBox(height: 12),
        Text('終わり方', style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        for (final ending in preview.endings) _FlowEndingRow(ending: ending),
        if (preview.notes.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final note in preview.notes)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 14, color: hint),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      note,
                      style: TextStyle(fontSize: 12, color: hint),
                    ),
                  ),
                ],
              ),
            ),
        ],
        const SizedBox(height: 8),
        Text(
          '実際の動きは、モデルの応答（Patch を出すか等）で変わります。ここでは設定どおりに進んだ場合を示します。',
          style: TextStyle(fontSize: 11, color: hint),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _VerdictTile extends StatelessWidget {
  const _VerdictTile({
    required this.title,
    required this.value,
    required this.icon,
    this.emphasized = false,
  });

  final String title;
  final String value;
  final IconData icon;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: emphasized
            ? scheme.primaryContainer.withValues(alpha: 0.5)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

({IconData icon, Color color}) _flowStepStyle(
  BuildContext context,
  CodingFlowStepKind kind,
) {
  final scheme = Theme.of(context).colorScheme;
  return switch (kind) {
    CodingFlowStepKind.send => (icon: Icons.send, color: scheme.primary),
    CodingFlowStepKind.docs => (icon: Icons.public, color: scheme.primary),
    CodingFlowStepKind.read => (
      icon: Icons.description_outlined,
      color: scheme.primary,
    ),
    CodingFlowStepKind.generate => (
      icon: Icons.auto_awesome,
      color: scheme.primary,
    ),
    CodingFlowStepKind.apply => (
      icon: Icons.check_circle_outline,
      color: scheme.primary,
    ),
    CodingFlowStepKind.manual => (
      icon: Icons.touch_app,
      color: scheme.tertiary,
    ),
    CodingFlowStepKind.analyze => (icon: Icons.rule, color: scheme.secondary),
    CodingFlowStepKind.test => (
      icon: Icons.science_outlined,
      color: scheme.secondary,
    ),
    CodingFlowStepKind.fix => (
      icon: Icons.build_circle_outlined,
      color: scheme.error,
    ),
    CodingFlowStepKind.skip => (
      icon: Icons.remove_circle_outline,
      color: Theme.of(context).hintColor,
    ),
  };
}

class _FlowStepRow extends StatelessWidget {
  const _FlowStepRow({required this.step, required this.isLast});

  final CodingFlowStep step;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = _flowStepStyle(context, step.kind);
    final muted = step.kind == CodingFlowStepKind.skip;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: style.color.withValues(alpha: 0.14),
                  ),
                  child: Icon(style.icon, size: 14, color: style.color),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: theme.dividerColor,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        step.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: muted ? theme.hintColor : null,
                        ),
                      ),
                      if (step.conditional)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '出たときだけ',
                            style: TextStyle(
                              fontSize: 10,
                              color: theme.hintColor,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (step.detail != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        step.detail!,
                        style: TextStyle(fontSize: 12, color: theme.hintColor),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FlowLoopBlock extends StatelessWidget {
  const _FlowLoopBlock({required this.loop});

  final CodingFlowLoop loop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.error;
    return Container(
      margin: const EdgeInsets.only(top: 4, left: 36),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.replay, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '失敗したら（最大 ${loop.maxSets} セット繰り返し）',
                  style: TextStyle(fontWeight: FontWeight.w600, color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var n = 0; n < loop.steps.length; n++)
            _FlowStepRow(step: loop.steps[n], isLast: n == loop.steps.length - 1),
        ],
      ),
    );
  }
}

class _FlowEndingRow extends StatelessWidget {
  const _FlowEndingRow({required this.ending});

  final CodingFlowEnding ending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (icon, color) = switch (ending.kind) {
      CodingFlowEndingKind.success => (Icons.check_circle, scheme.primary),
      CodingFlowEndingKind.stop => (Icons.stop_circle_outlined, scheme.error),
      CodingFlowEndingKind.manual => (
        Icons.pan_tool_alt_outlined,
        scheme.tertiary,
      ),
      CodingFlowEndingKind.info => (Icons.info_outline, theme.hintColor),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ending.label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (ending.detail != null)
                  Text(
                    ending.detail!,
                    style: TextStyle(fontSize: 12, color: theme.hintColor),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
