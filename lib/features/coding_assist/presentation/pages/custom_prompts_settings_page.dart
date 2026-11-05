import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../injection.dart';
import '../../../../theme.dart';
import '../../../api_settings/domain/usecases/get_connection_settings.dart';
import '../../../generative_ai/data/local_llm_client.dart';
import '../../data/datasources/coding_custom_prompts_local_datasource.dart';
import '../../domain/coding_custom_prompt_id.dart';
import '../../domain/coding_custom_prompts.dart';
import '../../domain/coding_workspace_kind.dart';
import '../prompt/coding_custom_prompt_defaults.dart';

/// カスタムプロンプト設定（画面ID: S17）。
class CustomPromptsSettingsPage extends StatefulWidget {
  const CustomPromptsSettingsPage({super.key, this.initialId});

  final CodingCustomPromptId? initialId;

  @override
  State<CustomPromptsSettingsPage> createState() =>
      _CustomPromptsSettingsPageState();
}

class _CustomPromptsSettingsPageState extends State<CustomPromptsSettingsPage> {
  CodingCustomPromptId? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialId;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: colors.dialogSurface,
            child: ListTile(
              leading: IconButton(
                tooltip: '戻る',
                icon: Icon(
                  _selected == null ? Icons.arrow_back : Icons.arrow_back,
                ),
                onPressed: () {
                  if (_selected != null) {
                    setState(() => _selected = null);
                  } else {
                    context.pop();
                  }
                },
              ),
              title: Text(
                _selected?.title ?? 'カスタムプロンプト',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                _selected == null
                    ? 'Agent が使うプロンプトを個別に変更'
                    : _selected!.description,
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _selected == null
                ? _PromptList(
                    onSelect: (id) => setState(() => _selected = id),
                  )
                : _PromptEditor(
                    id: _selected!,
                    onChanged: () => setState(() {}),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PromptList extends StatelessWidget {
  const _PromptList({required this.onSelect});

  final ValueChanged<CodingCustomPromptId> onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Card(
          color: Theme.of(context).colorScheme.errorContainer.withValues(
                alpha: 0.35,
              ),
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              '注意: プロンプトの変更は Agent とアプリの連携を壊す可能性があります。'
              'Begin/End Patch・tool フェンス・「不足:」・各【…の指示】などの印を変えると、'
              'カード表示・自動実行・検証スキップ判定が動かなくなることがあります。'
              '各プロンプトは個別にデフォルトへ戻せます。',
              style: TextStyle(height: 1.35),
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (final category in CodingCustomPromptCategory.values) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(
              CodingCustomPromptId.categoryLabel(category),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          for (final id in CodingCustomPromptId.values.where(
            (e) => e.category == category,
          ))
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: Text(id.title),
              subtitle: Text(
                id.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (CodingCustomPrompts.isCustomized(id))
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Chip(
                        label: const Text('変更済'),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        labelStyle: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              onTap: () => onSelect(id),
            ),
          const Divider(),
        ],
      ],
    );
  }
}

class _PromptEditor extends StatefulWidget {
  const _PromptEditor({required this.id, required this.onChanged});

  final CodingCustomPromptId id;
  final VoidCallback onChanged;

  @override
  State<_PromptEditor> createState() => _PromptEditorState();
}

class _PromptEditorState extends State<_PromptEditor> {
  late final TextEditingController _promptController;
  late final TextEditingController _sampleController;
  late final TextEditingController _systemForTestController;
  String _preview = '';
  String? _llmResult;
  String? _llmError;
  bool _testing = false;
  bool _dirty = false;
  CodingWorkspaceKind _kind = CodingWorkspaceKind.flutter;

  @override
  void initState() {
    super.initState();
    final override = CodingCustomPrompts.overrideOf(widget.id);
    final initial =
        override ?? CodingCustomPromptDefaults.text(widget.id, kind: _kind);
    _promptController = TextEditingController(text: initial);
    _sampleController = TextEditingController(
      text: widget.id == CodingCustomPromptId.errorAnalyze ||
              widget.id == CodingCustomPromptId.errorAnalyzeAuto ||
              widget.id == CodingCustomPromptId.errorAnalyzeBodies
          ? 'Error: Null check operator used on a null value\n#0  main (lib/main.dart:10)'
          : 'ログイン画面にパスワード表示切替を追加して',
    );
    _systemForTestController = TextEditingController(
      text: 'あなたはコーディングアシスタントです。指定形式だけを守って短く答えてください。',
    );
    _promptController.addListener(_onEdited);
    _sampleController.addListener(_refreshPreview);
    _refreshPreview();
  }

  @override
  void didUpdateWidget(covariant _PromptEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      final override = CodingCustomPrompts.overrideOf(widget.id);
      _promptController.text =
          override ?? CodingCustomPromptDefaults.text(widget.id, kind: _kind);
      _dirty = false;
      _llmResult = null;
      _llmError = null;
      _refreshPreview();
    }
  }

  void _onEdited() {
    if (!_dirty) setState(() => _dirty = true);
    _refreshPreview();
  }

  void _refreshPreview() {
    setState(() {
      _preview = CodingCustomPromptDefaults.previewApplied(
        id: widget.id,
        promptText: _promptController.text,
        sampleDraft: _sampleController.text,
        kind: _kind,
      );
    });
  }

  @override
  void dispose() {
    _promptController.dispose();
    _sampleController.dispose();
    _systemForTestController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final ds = getIt<CodingCustomPromptsLocalDataSource>();
    final defaultText = CodingCustomPromptDefaults.text(
      widget.id,
      kind: _kind,
    );
    final next = _promptController.text;
    if (next.trim() == defaultText.trim()) {
      await ds.clearOne(widget.id);
    } else {
      await ds.saveOne(widget.id, next);
    }
    if (!mounted) return;
    setState(() => _dirty = false);
    widget.onChanged();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('このプロンプトを保存しました')),
    );
  }

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('デフォルトに戻す'),
        content: Text('「${widget.id.title}」を組み込み既定に戻しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('戻す'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await getIt<CodingCustomPromptsLocalDataSource>().clearOne(widget.id);
    if (!mounted) return;
    setState(() {
      _promptController.text = CodingCustomPromptDefaults.text(
        widget.id,
        kind: _kind,
      );
      _dirty = false;
      _llmResult = null;
      _llmError = null;
    });
    widget.onChanged();
    _refreshPreview();
  }

  Future<void> _runLlmTest() async {
    setState(() {
      _testing = true;
      _llmResult = null;
      _llmError = null;
    });
    try {
      final settings = await getIt<GetConnectionSettings>()();
      final llm = settings.localLlm.forServer();
      if (!llm.hasEndpoint || !settings.localLlm.enabled) {
        throw StateError('ローカル LLM が未設定または OFF です。エンジン設定を確認してください。');
      }
      final isSystem = widget.id.category == CodingCustomPromptCategory.system;
      final userPrompt = isSystem
          ? (_sampleController.text.trim().isEmpty
                ? 'こんにちは。短い自己紹介をしてください。'
                : _sampleController.text.trim())
          : _preview;
      final systemPrompt = isSystem
          ? _preview
          : _systemForTestController.text.trim().isEmpty
              ? '簡潔に答えてください。'
              : _systemForTestController.text.trim();
      final text = await getIt<LocalLlmClient>().chat(
        settings: llm,
        prompt: userPrompt,
        systemPrompt: systemPrompt,
        maxTokens: 512,
      );
      if (!mounted) return;
      setState(() => _llmResult = text);
    } catch (e) {
      if (!mounted) return;
      setState(() => _llmError = '$e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final customized = CodingCustomPrompts.isCustomized(widget.id);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Card(
          color: Theme.of(context).colorScheme.errorContainer.withValues(
                alpha: 0.35,
              ),
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'このプロンプトを変えると、Agent の応答形式がアプリの期待とずれ、'
              'パッチカード・自動実行・ツール呼び出しが壊れることがあります。'
              '検証用の印や Begin/End Patch 形式はできるだけ残してください。',
              style: TextStyle(height: 1.35),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            if (customized)
              const Chip(
                label: Text('変更済'),
                visualDensity: VisualDensity.compact,
              ),
            const Spacer(),
            TextButton(
              onPressed: customized || _dirty ? _reset : null,
              child: const Text('デフォルトに戻す'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _dirty ? _save : null,
              child: const Text('このプロンプトを保存'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        InputDecorator(
          decoration: const InputDecoration(
            labelText: 'パス例のワークスペース種別（プレビュー用）',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<CodingWorkspaceKind>(
              value: _kind,
              isExpanded: true,
              items: [
                for (final k in CodingWorkspaceKind.values)
                  DropdownMenuItem(
                    value: k,
                    child: Text(CodingWorkspaceKindDetect.displayLabel(k)),
                  ),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _kind = v);
                if (!_dirty && !CodingCustomPrompts.isCustomized(widget.id)) {
                  _promptController.text = CodingCustomPromptDefaults.text(
                    widget.id,
                    kind: v,
                  );
                }
                _refreshPreview();
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text('プロンプト本文', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        TextField(
          controller: _promptController,
          maxLines: 18,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 20),
        Text('適用テスト', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'サンプル入力を付けたときの合成結果を確認できます。'
          '任意でローカル LLM に一度送り、意図どおりか試せます（会話には残りません）。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _sampleController,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'サンプルのユーザー入力／エラー文言',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        if (widget.id.category != CodingCustomPromptCategory.system) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _systemForTestController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'LLM テスト時の system（簡易）',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text('合成プレビュー', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(8),
            color: AppColors.of(context).codeBlockBackground,
          ),
          child: SelectableText(
            _preview,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _testing ? null : _runLlmTest,
            icon: _testing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow),
            label: Text(_testing ? 'LLM テスト中…' : 'LLM で試す'),
          ),
        ),
        if (_llmError != null) ...[
          const SizedBox(height: 8),
          Text(
            _llmError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (_llmResult != null) ...[
          const SizedBox(height: 8),
          Text('LLM 応答', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(_llmResult!),
          ),
        ],
      ],
    );
  }
}
