import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../injection.dart';
import '../../../generative_ai/domain/gemma_mtp_draft.dart';
import '../../data/datasources/custom_llm_models_local_datasource.dart';
import '../../domain/entities/custom_llm_model.dart';
import '../../domain/usecases/get_connection_settings.dart';
import '../../domain/usecases/save_connection_settings.dart';

/// S11 配下: ユーザー GGUF の取り込み。
class AddLlmModelPage extends StatefulWidget {
  const AddLlmModelPage({super.key});

  @override
  State<AddLlmModelPage> createState() => _AddLlmModelPageState();
}

class _AddLlmModelPageState extends State<AddLlmModelPage> {
  final _nameController = TextEditingController();
  String? _pickedPath;
  String? _pickedFileName;
  var _busy = false;
  String? _error;
  String? _info;
  List<CustomLlmModel> _models = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final list = await getIt<CustomLlmModelsLocalDataSource>().list();
    if (!mounted) return;
    setState(() => _models = list);
  }

  Future<void> _pickFile() async {
    setState(() {
      _error = null;
      _info = null;
    });
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['gguf'],
      withData: false,
      dialogTitle: 'GGUF モデルを選択',
    );
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    final path = file.path;
    if (path == null || path.isEmpty) {
      setState(() => _error = 'ファイルパスを取得できませんでした');
      return;
    }
    if (!path.toLowerCase().endsWith('.gguf')) {
      setState(() => _error = 'GGUF ファイルのみ取り込めます');
      return;
    }
    setState(() {
      _pickedPath = path;
      _pickedFileName = file.name;
      if (_nameController.text.trim().isEmpty) {
        final stem = file.name
            .replaceAll(RegExp(r'\.gguf$', caseSensitive: false), '');
        _nameController.text = stem;
      }
    });
  }

  Future<void> _import({required bool selectAfter}) async {
    final path = _pickedPath;
    if (path == null) {
      setState(() => _error = '先に GGUF ファイルを選択してください');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      final ds = getIt<CustomLlmModelsLocalDataSource>();
      final model = await ds.importGguf(
        sourcePath: path,
        label: _nameController.text,
      );
      final isDraft = GemmaMtpDraft.isDraftFileName(model.ggufFileName);
      if (selectAfter && !isDraft) {
        final current = await getIt<GetConnectionSettings>()();
        await getIt<SaveConnectionSettings>()(
          current.copyWith(
            localLlm: current.localLlm.withCustomCodingModel(
              id: model.id,
              label: model.label,
              ggufFileName: model.ggufFileName,
            ),
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _pickedPath = null;
        _pickedFileName = null;
        _info = isDraft
            ? '「${model.label}」を下書き係として配置しました。'
                '対応する Gemma 4 本体を選ぶと、起動時に自動で併用します'
            : selectAfter
                ? '「${model.label}」を取り込み、コーディング用モデルにしました'
                    '（エンジン設定で保存すると再起動されます）'
                : '「${model.label}」を取り込みました';
      });
      await _reload();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: IconButton(
              tooltip: '戻る',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.pop(true),
            ),
            title: Text('モデルを追加', style: theme.textTheme.titleLarge),
          ),
          const SizedBox(height: 8),
          Text(
            '独自の GGUF をアプリの models フォルダへ取り込み、エンジン設定のモデル一覧から選べます。'
            'mtp- で始まるファイルは Gemma 4 の下書き係で、一覧には出ません。',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.5,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'ライセンスについて: 取り込み・利用するモデルのライセンス・利用条件は、'
                '各ユーザーご自身の責任で確認・遵守してください。'
                '本アプリはモデルの権利関係を保証しません。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickFile,
            icon: const Icon(Icons.folder_open),
            label: Text(
              _pickedFileName == null
                  ? 'GGUF ファイルを選択'
                  : '選択中: $_pickedFileName',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: '表示名',
              hintText: '例: 社内向け 7B',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: _busy ? null : () => _import(selectAfter: false),
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('取り込む'),
              ),
              FilledButton.tonal(
                onPressed: _busy ? null : () => _import(selectAfter: true),
                child: const Text('取り込んで選択する'),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          if (_info != null) ...[
            const SizedBox(height: 12),
            Text(_info!, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 28),
          Text('登録済みカスタムモデル', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          if (_models.isEmpty)
            Text(
              'まだありません',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            for (final m in _models)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(m.label),
                subtitle: Text(
                  GemmaMtpDraft.isDraftFileName(m.ggufFileName)
                      ? '${m.ggufFileName}（MTP 下書き係）'
                      : m.ggufFileName,
                ),
                trailing: IconButton(
                  tooltip: '一覧から削除（ファイルは残ります）',
                  onPressed: _busy
                      ? null
                      : () async {
                          await getIt<CustomLlmModelsLocalDataSource>()
                              .remove(m.id);
                          await _reload();
                        },
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
        ],
      ),
    );
  }
}
