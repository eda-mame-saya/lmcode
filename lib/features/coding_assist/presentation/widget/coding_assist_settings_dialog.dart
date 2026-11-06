part of '../pages/coding_assist_page.dart';

Future<void> showCodingAssistSettingsDialog(BuildContext context) {
  final bloc = context.read<CodingAssistBloc>();
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      return BlocProvider.value(
        value: bloc,
        child: const _CodingAssistSettingsDialog(),
      );
    },
  );
}

class _CodingAssistSettingsDialog extends StatelessWidget {
  const _CodingAssistSettingsDialog();

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.78;
    return AlertDialog(
      title: const Text('設定'),
      content: SizedBox(
        width: 640,
        height: height.clamp(420, 720),
        child: BlocBuilder<CodingAssistBloc, CodingAssistState>(
          buildWhen: (p, c) =>
              p.uiFontSizes != c.uiFontSizes ||
              p.indentSize != c.indentSize ||
              p.novelSettings != c.novelSettings ||
              p.harness != c.harness ||
              p.localLlm.codingThinkingEnabled !=
                  c.localLlm.codingThinkingEnabled ||
              p.localLlm.codingAutoApplyPatches !=
                  c.localLlm.codingAutoApplyPatches ||
              p.autoSleepSettings != c.autoSleepSettings ||
              p.isGenerating != c.isGenerating ||
              p.isLlmBusy != c.isLlmBusy,
          builder: (context, state) {
            final busy = state.isGenerating || state.isLlmBusy;
            final groups = <String, List<CodingHarnessField>>{};
            for (final field in CodingHarnessSettings.fields) {
              groups.putIfAbsent(field.group, () => []).add(field);
            }
            return ListView(
              children: [
                const _SettingsSectionTitle('表示'),
                const _ThemeModeRow(),
                const _AppColorsSection(),
                _FontSizeStepperRow(
                  label: 'メニュー',
                  value: state.uiFontSizes.menu,
                  onChanged: (v) => _setFonts(
                    context,
                    state.uiFontSizes.copyWith(menu: v),
                  ),
                ),
                _FontSizeStepperRow(
                  label: 'エディタ',
                  value: state.uiFontSizes.editor,
                  onChanged: (v) => _setFonts(
                    context,
                    state.uiFontSizes.copyWith(editor: v),
                  ),
                ),
                _FontSizeStepperRow(
                  label: 'Agent',
                  value: state.uiFontSizes.agent,
                  onChanged: (v) => _setFonts(
                    context,
                    state.uiFontSizes.copyWith(agent: v),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => _setFonts(context, CodingUiFontSizes.defaults),
                    child: const Text('フォントを既定に戻す'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const SizedBox(width: 220, child: Text('インデント（空白）')),
                      SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(value: 2, label: Text('2')),
                          ButtonSegment(value: 4, label: Text('4')),
                        ],
                        selected: {state.indentSize},
                        onSelectionChanged: (next) {
                          context.read<CodingAssistBloc>().add(
                            CodingAssistIndentSizeChanged(next.first),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(),
                const _SettingsSectionTitle('小説執筆'),
                Text(
                  '小説ワークスペースの .txt で有効。⌘⌥L で地の文とセリフの空行・字下げを揃えます。',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).hintColor,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const SizedBox(width: 220, child: Text('改行インデント文字数')),
                      IconButton(
                        tooltip: '減らす',
                        onPressed: state.novelSettings.indentCount <=
                                CodingNovelSettings.minIndentCount
                            ? null
                            : () => context.read<CodingAssistBloc>().add(
                                  CodingAssistNovelSettingsChanged(
                                    state.novelSettings.copyWith(
                                      indentCount:
                                          state.novelSettings.indentCount - 1,
                                    ),
                                  ),
                                ),
                        icon: const Icon(Icons.remove, size: 18),
                        visualDensity: VisualDensity.compact,
                      ),
                      Text('${state.novelSettings.indentCount}'),
                      IconButton(
                        tooltip: '増やす',
                        onPressed: state.novelSettings.indentCount >=
                                CodingNovelSettings.maxIndentCount
                            ? null
                            : () => context.read<CodingAssistBloc>().add(
                                  CodingAssistNovelSettingsChanged(
                                    state.novelSettings.copyWith(
                                      indentCount:
                                          state.novelSettings.indentCount + 1,
                                    ),
                                  ),
                                ),
                        icon: const Icon(Icons.add, size: 18),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const SizedBox(width: 220, child: Text('インデントの種類')),
                      Expanded(
                        child: SegmentedButton<CodingNovelIndentSpace>(
                          segments: const [
                            ButtonSegment(
                              value: CodingNovelIndentSpace.fullWidth,
                              label: Text('全角'),
                            ),
                            ButtonSegment(
                              value: CodingNovelIndentSpace.halfWidth,
                              label: Text('半角'),
                            ),
                          ],
                          selected: {state.novelSettings.indentSpace},
                          onSelectionChanged: (next) {
                            context.read<CodingAssistBloc>().add(
                              CodingAssistNovelSettingsChanged(
                                state.novelSettings.copyWith(
                                  indentSpace: next.first,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('セリフ行もインデントする'),
                  subtitle: const Text('登録した記号でセリフと判定した行。オフなら字下げしない（整形時）'),
                  value: state.novelSettings.indentDialogue,
                  onChanged: (v) => context.read<CodingAssistBloc>().add(
                        CodingAssistNovelSettingsChanged(
                          state.novelSettings.copyWith(indentDialogue: v),
                        ),
                      ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'セリフ記号',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Text(
                    '判定は、字下げを除いた1行の先頭と末尾が、登録した開き／閉じ記号の組と一致するときだけです。'
                    '地の文の途中に「」などが入る行はセリフ扱いしません。'
                    '作者ごとに「」『』（）など使う記号が違うため、複数登録できます。',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: Theme.of(context).hintColor,
                    ),
                  ),
                ),
                for (final delim in state.novelSettings.dialogueDelimiters)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${delim.open} … ${delim.close}',
                            style: const TextStyle(fontSize: 15),
                          ),
                        ),
                        IconButton(
                          tooltip: '削除',
                          onPressed: state.novelSettings.dialogueDelimiters
                                      .length <=
                                  1
                              ? null
                              : () {
                                  final next = [
                                    for (final d
                                        in state.novelSettings.dialogueDelimiters)
                                      if (d != delim) d,
                                  ];
                                  context.read<CodingAssistBloc>().add(
                                        CodingAssistNovelSettingsChanged(
                                          state.novelSettings.copyWith(
                                            dialogueDelimiters: next,
                                          ),
                                        ),
                                      );
                                },
                          icon: const Icon(Icons.close, size: 18),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                _NovelDialogueDelimiterAddRow(
                  settings: state.novelSettings,
                ),
                const Divider(),
                const _SettingsSectionTitle('Agent'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('思考'),
                  subtitle: const Text('切替時は llama-server を再起動します'),
                  value: state.localLlm.codingThinkingEnabled,
                  onChanged: busy
                      ? null
                      : (v) => context.read<CodingAssistBloc>().add(
                          CodingAssistCodingThinkingChanged(v),
                        ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('自動実行'),
                  subtitle: const Text(
                    '応答のあと Update と Add を書きます。サーバ再起動は不要',
                  ),
                  value: state.localLlm.codingAutoApplyPatches,
                  onChanged: busy
                      ? null
                      : (v) => context.read<CodingAssistBloc>().add(
                          CodingAssistAgentAutoRunChanged(v),
                        ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('自動実行後のスリープ'),
                  subtitle: Text(_sleepLabel(state.autoSleepSettings)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showCodingAssistAutoSleepDialog(context),
                ),
                const Divider(),
                const _SettingsSectionTitle('ハーネス'),
                Text(
                  '既定はこれまでの固定値です。変えた値は次の送信から使います。'
                  '索引の件数は、次にフォルダを走査したときから使います。',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).hintColor,
                  ),
                ),
                for (final entry in groups.entries) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 4),
                    child: Text(
                      entry.key,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  for (final field in entry.value)
                    _HarnessNumberRow(
                      key: ValueKey(field.id),
                      field: field,
                      settings: state.harness,
                    ),
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => context.read<CodingAssistBloc>().add(
                      const CodingAssistHarnessChanged(
                        CodingHarnessSettings.defaults,
                      ),
                    ),
                    child: const Text('ハーネスを既定に戻す'),
                  ),
                ),
                const Divider(),
                const _SettingsSectionTitle('このアプリについて'),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.balance_outlined),
                  title: const Text('OSSライセンス'),
                  subtitle: const Text(
                    '依存パッケージとローカル LLM ランタイム（llama.cpp）のライセンス',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openOssLicensesPage(context),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('閉じる'),
        ),
      ],
    );
  }

  void _setFonts(BuildContext context, CodingUiFontSizes sizes) {
    context.read<CodingAssistBloc>().add(CodingAssistUiFontSizesChanged(sizes));
  }

  String _sleepLabel(CodingAutoSleepSettings settings) {
    final parts = <String>[
      if (settings.sleepWhenFinished) '処理が終わったら',
      if (settings.sleepAfterMinutes > 0) '${settings.sleepAfterMinutes}分後',
    ];
    if (parts.isEmpty) return 'オフ';
    return parts.join(' / ');
  }
}

class _SettingsSectionTitle extends StatelessWidget {
  const _SettingsSectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

/// セリフ記号の追加行（開き／閉じを入力して追加）。
class _NovelDialogueDelimiterAddRow extends StatefulWidget {
  const _NovelDialogueDelimiterAddRow({required this.settings});

  final CodingNovelSettings settings;

  @override
  State<_NovelDialogueDelimiterAddRow> createState() =>
      _NovelDialogueDelimiterAddRowState();
}

class _NovelDialogueDelimiterAddRowState
    extends State<_NovelDialogueDelimiterAddRow> {
  final _open = TextEditingController();
  final _close = TextEditingController();

  @override
  void dispose() {
    _open.dispose();
    _close.dispose();
    super.dispose();
  }

  void _add() {
    final open = _open.text.trim();
    final close = _close.text.trim();
    final delim = CodingNovelDialogueDelimiter(open: open, close: close);
    if (!delim.isValid) return;
    if (widget.settings.dialogueDelimiters.length >=
        CodingNovelSettings.maxDialogueDelimiters) {
      return;
    }
    if (widget.settings.dialogueDelimiters.contains(delim)) return;
    context.read<CodingAssistBloc>().add(
          CodingAssistNovelSettingsChanged(
            widget.settings.copyWith(
              dialogueDelimiters: [
                ...widget.settings.dialogueDelimiters,
                delim,
              ],
            ),
          ),
        );
    _open.clear();
    _close.clear();
  }

  @override
  Widget build(BuildContext context) {
    final full = widget.settings.dialogueDelimiters.length >=
        CodingNovelSettings.maxDialogueDelimiters;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: TextField(
              controller: _open,
              enabled: !full,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                hintText: '「',
              ),
              onSubmitted: (_) => _add(),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text('…'),
          ),
          SizedBox(
            width: 56,
            child: TextField(
              controller: _close,
              enabled: !full,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                hintText: '」',
              ),
              onSubmitted: (_) => _add(),
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: full ? null : _add,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('追加'),
          ),
        ],
      ),
    );
  }
}

/// ライト／ダーク／システム切替（アプリ全体・永続）。
class _ThemeModeRow extends StatelessWidget {
  const _ThemeModeRow();

  @override
  Widget build(BuildContext context) {
    final controller = getIt<AppThemeController>();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          return Row(
            children: [
              const SizedBox(width: 220, child: Text('外観')),
              Expanded(
                child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('システム'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text('ライト'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text('ダーク'),
                    ),
                  ],
                  selected: {controller.themeMode},
                  onSelectionChanged: (next) {
                    controller.setThemeMode(next.first);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 個別色カスタム（ライト／ダーク配色を別々に編集・永続）。折りたたみ可。
class _AppColorsSection extends StatefulWidget {
  const _AppColorsSection();

  @override
  State<_AppColorsSection> createState() => _AppColorsSectionState();
}

class _AppColorsSectionState extends State<_AppColorsSection> {
  late Brightness _palette;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _palette = WidgetsBinding.instance.platformDispatcher.platformBrightness;
  }

  @override
  Widget build(BuildContext context) {
    final controller = getIt<AppThemeController>();
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final colors = controller.colorsFor(_palette);
        final customized = controller.hasAnyOverride(_palette);
        return Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: const PageStorageKey<String>('settings_colors'),
            initiallyExpanded: false,
            onExpansionChanged: (v) => setState(() => _expanded = v),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 4),
            title: Text(
              customized ? '色設定（カスタムあり）' : '色設定',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              _expanded
                  ? 'ピッカーで色を変えられます。変更はすぐ反映・保存されます。'
                  : 'タップしてライト／ダークの個別色を編集',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).hintColor,
              ),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const SizedBox(width: 220, child: Text('色の編集対象')),
                    Expanded(
                      child: SegmentedButton<Brightness>(
                        segments: const [
                          ButtonSegment(
                            value: Brightness.light,
                            label: Text('ライト配色'),
                          ),
                          ButtonSegment(
                            value: Brightness.dark,
                            label: Text('ダーク配色'),
                          ),
                        ],
                        selected: {_palette},
                        onSelectionChanged: (next) {
                          setState(() => _palette = next.first);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              for (final group in AppColorToken.groupOrder) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 2),
                  child: Text(
                    group,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                for (final token in AppColorToken.values.where(
                  (t) => t.group == group,
                ))
                  _AppColorTokenRow(
                    token: token,
                    color: token.read(colors),
                    isCustomized: controller.hasOverride(_palette, token),
                    onPick: () => _pick(context, controller, token, colors),
                    onReset: controller.hasOverride(_palette, token)
                        ? () => controller.clearColorOverride(
                              brightness: _palette,
                              token: token,
                            )
                        : null,
                  ),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: customized
                      ? () => controller.clearAllColorOverrides(_palette)
                      : null,
                  child: Text(
                    _palette == Brightness.dark
                        ? 'ダーク配色を既定に戻す'
                        : 'ライト配色を既定に戻す',
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pick(
    BuildContext context,
    AppThemeController controller,
    AppColorToken token,
    AppColors colors,
  ) async {
    final next = await showAppColorPickerDialog(
      context: context,
      title: token.label,
      initialColor: token.read(colors),
      enableAlpha: token.enableAlpha,
    );
    if (next == null || !mounted) return;
    await controller.setColorOverride(
      brightness: _palette,
      token: token,
      color: next,
    );
  }
}

class _AppColorTokenRow extends StatelessWidget {
  const _AppColorTokenRow({
    required this.token,
    required this.color,
    required this.isCustomized,
    required this.onPick,
    required this.onReset,
  });

  final AppColorToken token;
  final Color color;
  final bool isCustomized;
  final VoidCallback onPick;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final hex = '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              token.label,
              style: TextStyle(
                fontWeight: isCustomized ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          Text(
            hex,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: Theme.of(context).hintColor,
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: '色を選ぶ',
            child: InkWell(
              onTap: onPick,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'この色を既定に戻す',
            onPressed: onReset,
            icon: const Icon(Icons.restart_alt, size: 18),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _HarnessNumberRow extends StatefulWidget {
  const _HarnessNumberRow({
    super.key,
    required this.field,
    required this.settings,
  });

  final CodingHarnessField field;
  final CodingHarnessSettings settings;

  @override
  State<_HarnessNumberRow> createState() => _HarnessNumberRowState();
}

class _HarnessNumberRowState extends State<_HarnessNumberRow> {
  late final TextEditingController _controller;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _format(widget.field.read(widget.settings)));
    _focus = FocusNode()..addListener(_onFocus);
  }

  @override
  void didUpdateWidget(covariant _HarnessNumberRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_focus.hasFocus) return;
    final text = _format(widget.field.read(widget.settings));
    if (_controller.text != text) _controller.text = text;
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (!_focus.hasFocus) _commit();
  }

  String _format(num value) {
    if (widget.field.kind == CodingHarnessValueKind.intValue) {
      return '${value.round()}';
    }
    final text = value.toStringAsFixed(2);
    return text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  void _commit() {
    final raw = double.tryParse(_controller.text.trim());
    if (raw == null) {
      _controller.text = _format(widget.field.read(widget.settings));
      return;
    }
    final next = widget.field.write(widget.settings, raw).normalized();
    final stored = widget.field.read(next);
    _controller.text = _format(stored);
    if (stored == widget.field.read(widget.settings)) return;
    context.read<CodingAssistBloc>().add(CodingAssistHarnessChanged(next));
  }

  @override
  Widget build(BuildContext context) {
    final field = widget.field;
    final hintStyle = TextStyle(
      fontSize: 12,
      height: 1.35,
      color: Theme.of(context).hintColor,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(field.label),
                Text(
                  '${_format(field.min)}〜${_format(field.max)}',
                  style: hintStyle,
                ),
                const SizedBox(height: 2),
                Text(field.hint, style: hintStyle),
              ],
            ),
          ),
          SizedBox(
            width: 96,
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              textAlign: TextAlign.end,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _commit(),
            ),
          ),
        ],
      ),
    );
  }
}
