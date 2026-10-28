part of '../pages/coding_assist_page.dart';

/// ショートカット一覧（追加時はここへ追記）。
const List<({String keys, String description})> codingAssistShortcutHelp = [
  (keys: '⌘S または Ctrl+S', description: 'アクティブなエディタタブを保存'),
  (keys: '⌘W または Ctrl+W', description: 'フォーカスしているエディタのタブを閉じる。右を選択中なら右のファイル'),
  (keys: '⌘N または Ctrl+N', description: '拡張子なしの Untitled-1 を作り、すぐエディタを開く（同階層にあれば連番）'),
  (
    keys: '⌘F または Ctrl+F',
    description: '開いているエディタ内を検索（選択、またはキャレット下の記号列を検索語にする）',
  ),
  (keys: '⌘/ または Ctrl+/', description: '行コメントの切替（拡張子に応じた記号）'),
  (
    keys: '⌘⌥L または Ctrl+Alt+L',
    description: 'インデントを付け直す（Dart等は括弧深さ、空白幅2/4。選択範囲または全体）',
  ),
  (keys: '⌘⇧F または Ctrl+⇧F', description: 'フォルダ内文言検索（選択中ならその語で検索まで実行）'),
  (
    keys: '⌘クリック または Ctrl+クリック',
    description: 'フォルダ内文言検索（選択、またはキャレット下の識別子／記号列で検索まで実行）',
  ),
  (keys: '⌘B または Ctrl+B', description: '左メニューを折りたたみ／展開'),
];

const List<({String keys, String description})> codingAssistAgentShortcutHelp = [
  (keys: '⌘Enter または Ctrl+Enter', description: 'テキスト入力中に限り、Agent へ送信'),
  (keys: '⌘⇧B または Ctrl+⇧B', description: 'Agent を展開／収納'),
];

Future<void> showCodingAssistShortcutHelp(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => const _CodingAssistShortcutHelpDialog(),
  );
}

class _CodingAssistShortcutHelpDialog extends StatefulWidget {
  const _CodingAssistShortcutHelpDialog();

  @override
  State<_CodingAssistShortcutHelpDialog> createState() =>
      _CodingAssistShortcutHelpDialogState();
}

class _CodingAssistShortcutHelpDialogState
    extends State<_CodingAssistShortcutHelpDialog> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.7;
    return AlertDialog(
      title: const Text('ショートカット'),
      content: SizedBox(
        width: 360,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight.clamp(240, 560)),
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _scrollController,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('エディタ部'),
                  const Divider(),
                  for (final item in codingAssistShortcutHelp)
                    _ShortcutHelpRow(item: item),
                  const SizedBox(height: 12),
                  const Text('Agent部'),
                  const Divider(),
                  for (final item in codingAssistAgentShortcutHelp)
                    _ShortcutHelpRow(item: item),
                ],
              ),
            ),
          ),
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

class _ShortcutHelpRow extends StatelessWidget {
  const _ShortcutHelpRow({required this.item});

  final ({String keys, String description}) item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              item.keys,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              item.description,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _FontSizeStepperRow extends StatelessWidget {
  const _FontSizeStepperRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 88, child: Text(label)),
          IconButton(
            tooltip: '小さく',
            onPressed: value <= CodingUiFontSizes.min
                ? null
                : () => onChanged(value - 1),
            icon: const Icon(Icons.remove, size: 18),
            visualDensity: VisualDensity.compact,
          ),
          SizedBox(
            width: 40,
            child: Text(
              '${value.toInt()}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            tooltip: '大きく',
            onPressed: value >= CodingUiFontSizes.max
                ? null
                : () => onChanged(value + 1),
            icon: const Icon(Icons.add, size: 18),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

Future<void> showCodingAssistAutoSleepDialog(BuildContext context) {
  final bloc = context.read<CodingAssistBloc>();
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      return BlocProvider.value(value: bloc, child: const _AutoSleepDialog());
    },
  );
}

class _AutoSleepDialog extends StatefulWidget {
  const _AutoSleepDialog();

  @override
  State<_AutoSleepDialog> createState() => _AutoSleepDialogState();
}

class _AutoSleepDialogState extends State<_AutoSleepDialog> {
  late bool _whenFinished;
  late bool _useTimer;
  late final TextEditingController _minutes;
  String? _error;

  @override
  void initState() {
    super.initState();
    final settings = context.read<CodingAssistBloc>().state.autoSleepSettings;
    _whenFinished = settings.sleepWhenFinished;
    _useTimer = settings.sleepAfterMinutes > 0;
    _minutes = TextEditingController(
      text: settings.sleepAfterMinutes > 0
          ? '${settings.sleepAfterMinutes}'
          : '30',
    );
  }

  @override
  void dispose() {
    _minutes.dispose();
    super.dispose();
  }

  void _save() {
    final minutes = int.tryParse(_minutes.text.trim()) ?? 0;
    if (_useTimer &&
        (minutes < 1 || minutes > CodingAutoSleepSettings.maxMinutes)) {
      setState(() => _error = '時間は 1〜240 分で指定してください');
      return;
    }
    context.read<CodingAssistBloc>().add(
      CodingAssistAutoSleepSettingsChanged(
        CodingAutoSleepSettings(
          sleepWhenFinished: _whenFinished,
          sleepAfterMinutes: _useTimer ? minutes : 0,
        ),
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('自動実行後のスリープ'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '自動実行 ON で処理が始まった時点から数えます。'
              '処理が全部終わるか、指定した時間になると、停止して Mac をスリープします。',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            ValueListenableBuilder<bool>(
              valueListenable: context
                  .read<CodingAssistBloc>()
                  .autoSleepArmedNow,
              builder: (context, armedNow, _) {
                if (!armedNow) return const SizedBox.shrink();
                final state = context.read<CodingAssistBloc>().state;
                final deadline = state.autoSleepDeadline;
                final triggers = <String>[
                  if (state.autoSleepSettings.sleepWhenFinished) '処理が終わったら',
                  if (deadline != null) '${_clockLabel(deadline)} になったら',
                ];
                final when = triggers.isEmpty
                    ? 'スリープ予定があります。'
                    : '${triggers.join('、または')}、停止してスリープします。';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(when, style: const TextStyle(fontSize: 13)),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () => context
                              .read<CodingAssistBloc>()
                              .cancelAutoSleepNow(),
                          child: const Text('スリープ予定を停止'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('処理が終わったらスリープ'),
              value: _whenFinished,
              onChanged: (v) => setState(() => _whenFinished = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('指定時間でスリープ'),
              value: _useTimer,
              onChanged: (v) => setState(() => _useTimer = v),
            ),
            if (_useTimer)
              TextField(
                controller: _minutes,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: '分',
                  helperText: '1〜240。自動実行の開始から数えます',
                  isDense: true,
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('閉じる'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }
}

String _clockLabel(DateTime time) {
  final local = time.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
