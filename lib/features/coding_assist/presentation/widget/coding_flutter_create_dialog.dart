import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../../injection.dart';
import '../../../../theme.dart';
import '../../../api_settings/domain/usecases/get_connection_settings.dart';
import '../../data/coding_flutter_project_creator.dart';
import '../../data/flutter_sdk_resolver.dart';

/// Flutter プロジェクト作成ダイアログを開き、成功時は作成先パスを返す。
///
/// 作成中は非キャンセル可能な待機ダイアログを出し、他操作を塞ぐ。
/// 失敗時は null（エラーは SnackBar／ダイアログ内で表示）。
Future<String?> showCodingFlutterCreateDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    barrierColor: AppColors.of(context).dialogBarrier,
    builder: (ctx) => const _CodingFlutterCreateDialog(),
  );
}

class _CodingFlutterCreateDialog extends StatefulWidget {
  const _CodingFlutterCreateDialog();

  @override
  State<_CodingFlutterCreateDialog> createState() =>
      _CodingFlutterCreateDialogState();
}

class _CodingFlutterCreateDialogState extends State<_CodingFlutterCreateDialog> {
  final _nameController = TextEditingController();
  final _creator = CodingFlutterProjectCreator();

  final Set<CodingFlutterCreatePlatform> _platforms = {
    CodingFlutterCreatePlatform.ios,
    CodingFlutterCreatePlatform.android,
  };

  String? _flutterBin;
  String? _resolveError;
  String? _parentDirectory;
  String? _formError;
  bool _resolving = true;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _resolveFlutter();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _resolveFlutter() async {
    setState(() {
      _resolving = true;
      _resolveError = null;
      _flutterBin = null;
    });
    try {
      final settings = await getIt<GetConnectionSettings>()();
      final bin = await FlutterSdkResolver.resolveFlutterExecutable(
        settings.dartSdkPath,
      );
      if (!mounted) return;
      setState(() {
        _resolving = false;
        _flutterBin = bin;
        if (bin == null) {
          _resolveError =
              'Flutter が見つかりません。PATH に flutter を通すか、エンジン設定（S11）の Dart SDK パスを確認してください。';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _resolving = false;
        _resolveError = 'Flutter の解決に失敗しました: $e';
      });
    }
  }

  Future<void> _pickParent() async {
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: 'プロジェクトの作成先フォルダを選択',
    );
    if (path == null || !mounted) return;
    setState(() {
      _parentDirectory = path;
      _formError = null;
    });
  }

  Future<void> _submit() async {
    final flutterBin = _flutterBin;
    if (flutterBin == null || _creating) return;

    final name = _nameController.text.trim();
    final parent = _parentDirectory?.trim() ?? '';
    if (!CodingFlutterProjectCreator.isValidProjectName(name)) {
      setState(() {
        _formError =
            'フォルダ名は小文字の英字で始め、英小文字・数字・アンダースコアのみにしてください（例: my_app）。';
      });
      return;
    }
    if (parent.isEmpty) {
      setState(() => _formError = '作成先フォルダを選択してください。');
      return;
    }
    if (_platforms.isEmpty) {
      setState(() => _formError = '対象プラットフォームを1つ以上選んでください。');
      return;
    }

    final outputPath = CodingFlutterProjectCreator.projectPath(
      parentDirectory: parent,
      projectName: name,
    );

    setState(() {
      _creating = true;
      _formError = null;
    });

    final result = await _creator.create(
      flutterExecutable: flutterBin,
      parentDirectory: parent,
      projectName: name,
      platforms: _platforms.map((e) => e.id).toList(),
    );

    if (!mounted) return;

    if (!result.ok) {
      setState(() {
        _creating = false;
        _formError = result.errorMessage ?? '作成に失敗しました。';
      });
      return;
    }

    Navigator.of(context).pop(result.projectPath ?? outputPath);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final preview = (_parentDirectory != null &&
            _nameController.text.trim().isNotEmpty)
        ? p.join(_parentDirectory!, _nameController.text.trim())
        : null;

    return PopScope(
      canPop: !_creating,
      child: AlertDialog(
        title: const Text('Flutterプロジェクト作成'),
        content: SizedBox(
          width: 420,
          child: _resolving
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              : _creating
                  ? _CreatingBody(path: preview)
                  : SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_resolveError != null) ...[
                            Text(
                              _resolveError!,
                              style: TextStyle(color: scheme.error, height: 1.4),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                onPressed: _resolveFlutter,
                                child: const Text('再検出'),
                              ),
                            ),
                          ] else ...[
                            Text(
                              '検出: $_flutterBin',
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurfaceVariant,
                                fontFamily: 'monospace',
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              '対象プラットフォーム',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 4,
                              runSpacing: 0,
                              children: [
                                for (final platform
                                    in CodingFlutterCreatePlatform.values)
                                  FilterChip(
                                    label: Text(platform.label),
                                    selected: _platforms.contains(platform),
                                    onSelected: (selected) {
                                      setState(() {
                                        if (selected) {
                                          _platforms.add(platform);
                                        } else {
                                          _platforms.remove(platform);
                                        }
                                        _formError = null;
                                      });
                                    },
                                  ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _nameController,
                              autofocus: true,
                              decoration: const InputDecoration(
                                labelText: 'フォルダ名（プロジェクト名）',
                                hintText: 'my_app',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              onChanged: (_) => setState(() => _formError = null),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              '作成先',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _parentDirectory ?? '未選択',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _parentDirectory == null
                                          ? scheme.onSurfaceVariant
                                          : null,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton(
                                  onPressed: _pickParent,
                                  child: const Text('フォルダを選択'),
                                ),
                              ],
                            ),
                            if (preview != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                '作成パス: $preview',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.onSurfaceVariant,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                            if (_formError != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                _formError!,
                                style: TextStyle(
                                  color: scheme.error,
                                  height: 1.35,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
        ),
        actions: [
          if (!_creating)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('キャンセル'),
            ),
          if (!_resolving && _resolveError == null && !_creating)
            FilledButton(
              onPressed: _submit,
              child: const Text('作成して開く'),
            ),
        ],
      ),
    );
  }
}

class _CreatingBody extends StatelessWidget {
  const _CreatingBody({this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          const Text(
            'Flutterプロジェクトを作成しています…',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            '完了するまで他の操作はできません。',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (path != null) ...[
            const SizedBox(height: 12),
            Text(
              path!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
