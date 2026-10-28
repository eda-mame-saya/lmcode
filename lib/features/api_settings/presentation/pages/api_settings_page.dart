import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../injection.dart';
import '../../../../routes.dart';
import '../../../../theme.dart';
import '../../../coding_assist/domain/coding_assist_availability.dart';
import '../../../generative_ai/domain/gemma_mtp_draft.dart';
import '../../../oss_licenses/presentation/open_oss_licenses_page.dart';
import '../../data/datasources/custom_llm_models_local_datasource.dart';
import '../../domain/entities/custom_llm_model.dart';
import '../../domain/entities/local_llm_connection_settings.dart';
import '../bloc/api_settings_bloc.dart';
import '../bloc/api_settings_event.dart';
import '../bloc/api_settings_state.dart';

/// エンジン設定画面（画面ID: S11）。
/// llama.cpp と Dart SDK パスのみ
class ApiSettingsPage extends StatelessWidget {
  const ApiSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<ApiSettingsBloc>()..add(const ApiSettingsStarted()),
      child: const _ApiSettingsView(),
    );
  }
}

class _ApiSettingsView extends StatefulWidget {
  const _ApiSettingsView();

  @override
  State<_ApiSettingsView> createState() => _ApiSettingsViewState();
}

class _ApiSettingsViewState extends State<_ApiSettingsView> {
  final _localLlmHostController = TextEditingController();
  final _localLlmPortController = TextEditingController();
  final _dartSdkPathController = TextEditingController();
  List<CustomLlmModel> _customModels = const [];

  List<CustomLlmModel> get _targetModels => [
        for (final model in _customModels)
          if (!GemmaMtpDraft.isDraftFileName(model.ggufFileName)) model,
      ];

  bool _controllersHydrated = false;

  @override
  void initState() {
    super.initState();
    _loadCustomModels();
  }

  Future<void> _loadCustomModels() async {
    final list = await getIt<CustomLlmModelsLocalDataSource>().list();
    if (!mounted) return;
    setState(() => _customModels = list);
  }

  @override
  void dispose() {
    _localLlmHostController.dispose();
    _localLlmPortController.dispose();
    _dartSdkPathController.dispose();
    super.dispose();
  }

  void _hydrateControllers(ApiSettingsState state) {
    if (_controllersHydrated || state.isLoading) return;
    final localLlm = state.settings.localLlm;
    _localLlmHostController.text = localLlm.host;
    _localLlmPortController.text = state.localLlmPortText;
    _dartSdkPathController.text = state.settings.dartSdkPath;
    _controllersHydrated = true;
  }

  String? _codingModelDropdownValue(LocalLlmConnectionSettings local) {
    return _dropdownValue(
      enabled: local.usesCustomCodingModel,
      id: local.codingCustomModelId,
      fileName: local.codingCustomGgufFileName,
    );
  }

  /// 下書き係（mtp-*.gguf）は会話モデルにしない。
  String? _dropdownValue({
    required bool enabled,
    required String? id,
    required String? fileName,
  }) {
    if (!enabled) return null;
    final file = fileName?.trim() ?? '';
    if (GemmaMtpDraft.isDraftFileName(file)) return null;
    final modelId = id?.trim() ?? '';
    if (modelId.isNotEmpty && _targetModels.any((m) => m.id == modelId)) {
      return 'custom:$modelId';
    }
    final byFile = _targetModels.where((m) => m.ggufFileName == file);
    if (byFile.isNotEmpty) return 'custom:${byFile.first.id}';
    return 'custom_orphan';
  }

  List<DropdownMenuItem<String>> _modelDropdownItems({
    required bool orphan,
    required String orphanLabel,
  }) {
    return [
      for (final m in _targetModels)
        DropdownMenuItem(
          value: 'custom:${m.id}',
          child: Text(m.label),
        ),
      if (orphan)
        DropdownMenuItem(
          value: 'custom_orphan',
          child: Text('$orphanLabel（未登録）'),
        ),
    ];
  }

  void _onCodingModelKeySelected(
    BuildContext context,
    String? key,
  ) {
    if (key == null || key == 'custom_orphan') return;
    if (!key.startsWith('custom:')) return;
    final id = key.substring('custom:'.length);
    final model = _targetModels.where((m) => m.id == id).firstOrNull;
    if (model == null) return;
    context.read<ApiSettingsBloc>().add(
          ApiSettingsLocalLlmCodingCustomModelChanged(model),
        );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ApiSettingsBloc, ApiSettingsState>(
      listenWhen: (previous, current) =>
          (previous.saveSucceeded != current.saveSucceeded &&
              current.saveSucceeded) ||
          (previous.infoMessage != current.infoMessage &&
              current.infoMessage != null) ||
          (previous.isLoading && !current.isLoading) ||
          previous.settings.localLlm.host != current.settings.localLlm.host ||
          previous.settings.localLlm.port != current.settings.localLlm.port,
      listener: (context, state) {
        _hydrateControllers(state);

        if (_controllersHydrated &&
            _localLlmHostController.text != state.settings.localLlm.host) {
          _localLlmHostController.text = state.settings.localLlm.host;
        }
        if (_controllersHydrated &&
            _localLlmPortController.text != state.localLlmPortText) {
          _localLlmPortController.text = state.localLlmPortText;
        }

        if (state.saveSucceeded) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.infoMessage ?? '接続設定を保存しました'),
            ),
          );
          context.pop(true);
          context.read<ApiSettingsBloc>().add(
                const ApiSettingsSaveMessageConsumed(),
              );
          return;
        }

        if (state.infoMessage != null && !state.isSaving) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.infoMessage!)),
          );
          context.read<ApiSettingsBloc>().add(
                const ApiSettingsSaveMessageConsumed(),
              );
        }
      },
      builder: (context, state) {
        _hydrateControllers(state);

        return PopScope(
          canPop: !state.isSaving,
          child: Stack(
            children: [
              Scaffold(
                body: state.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Material(
                            color: AppColors.of(context).dialogSurface,
                            child: ListTile(
                              leading: IconButton(
                                tooltip: '戻る',
                                icon: const Icon(Icons.arrow_back),
                                onPressed: state.isSaving
                                    ? null
                                    : () => context.pop(),
                              ),
                              title: const Text(
                                'エンジン設定',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              subtitle:
                                  const Text('接続・API設定（llama.cpp）'),
                            ),
                          ),
                          const Divider(height: 1),
                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildLocalLlmSection(context, state),
                                  const SizedBox(height: 24),
                                  const Divider(),
                                  const SizedBox(height: 24),
                                  _buildDartSdkSection(context, state),
                                  const SizedBox(height: 24),
                                  const Divider(),
                                  const SizedBox(height: 24),
                                  _buildAboutSection(context),
                                  const SizedBox(height: 24),
                                  Row(
                                    children: [
                                      FilledButton(
                                        onPressed: state.isSaving
                                            ? null
                                            : () => context
                                                .read<ApiSettingsBloc>()
                                                .add(
                                                  const ApiSettingsSaveRequested(),
                                                ),
                                        child: state.isSaving
                                            ? const SizedBox(
                                                width: 20,
                                                height: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                ),
                                              )
                                            : const Text('保存'),
                                      ),
                                      const SizedBox(width: 12),
                                      OutlinedButton(
                                        onPressed: state.isSaving
                                            ? null
                                            : () => context
                                                .read<ApiSettingsBloc>()
                                                .add(
                                                  const ApiSettingsConnectionTestRequested(),
                                                ),
                                        child: const Text('接続テスト'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
              if (state.isSaving)
                const Positioned.fill(
                  child: _ServerRestartBlockingOverlay(),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLocalLlmSection(BuildContext context, ApiSettingsState state) {
    final local = state.settings.localLlm;
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('生成AI（llama.cpp・ローカル）', style: textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'コーディングアシスト用のモデル・コンテキスト長を設定します。'
          'ポート衝突時は下のポートを変更してください（自動探索しません）。',
          style: textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Text(
          local.enabled
              ? (local.isConfigured
                  ? '状態: 使用する（設定済）→ ${local.baseUrl}'
                  : '状態: 使用する（コーディング用モデル未設定）')
              : '状態: 使用しない',
          style: textTheme.bodySmall?.copyWith(
            color: local.enabled ? null : colorScheme.error,
          ),
        ),
        if (state.localLlmConnectionError != null) ...[
          const SizedBox(height: 8),
          Text(
            state.localLlmConnectionError!,
            style: textTheme.bodySmall?.copyWith(color: colorScheme.error),
          ),
        ],
        if (local.enabled && !local.usesCustomCodingModel) ...[
          const SizedBox(height: 8),
          Text(
            'コーディング用モデルが未設定です。「モデルを追加…」から GGUF を取り込んでください。'
            ' モデルのライセンス・利用条件は利用者自身の責任で確認してください。',
            style: textTheme.bodySmall?.copyWith(color: colorScheme.error),
          ),
        ] else if (state.modelFileMissing) ...[
          const SizedBox(height: 8),
          Text(
            'コーディング用 GGUF が見つかりません（${local.resolvedCodingModelLabel}）。'
            ' LMCode/local_llm/models/ に配置してください。',
            style: textTheme.bodySmall?.copyWith(color: colorScheme.error),
          ),
        ] else if (state.modelResolvedPath != null) ...[
          const SizedBox(height: 8),
          Text(
            'コーディング用: ${state.modelResolvedPath}',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('ローカルLLMを使用する'),
          subtitle: Text(
            local.enabled
                ? 'llama-server でコーディングアシストを生成します'
                : 'ローカル LLM を使いません（コーディング Agent は無効）',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          value: local.enabled,
          onChanged: (value) => context.read<ApiSettingsBloc>().add(
                ApiSettingsLocalLlmEnabledChanged(value),
              ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _localLlmHostController,
          onChanged: (value) => context.read<ApiSettingsBloc>().add(
                ApiSettingsLocalLlmHostChanged(value),
              ),
          decoration: InputDecoration(
            labelText: local.enabled ? 'ベースURL *' : 'ベースURL（任意）',
            hintText: LocalLlmPresets.defaultHost,
            helperText:
                'ホストのみ（ポートは下欄）。例: ${LocalLlmPresets.defaultHost}',
            errorText: state.localLlmHostError,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _localLlmPortController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (value) => context.read<ApiSettingsBloc>().add(
                ApiSettingsLocalLlmPortChanged(value),
              ),
          decoration: InputDecoration(
            labelText: local.enabled ? 'ポート *' : 'ポート（任意）',
            hintText: '${LocalLlmPresets.defaultPort}',
            helperText: '既定 ${LocalLlmPresets.defaultPort}。衝突時のみ変更',
            errorText: state.localLlmPortError,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        if (!CodingAssistAvailability.isUiEnabled) ...[
          Text(
            'Windows ではコーディング画面がありません。'
            '以下は macOS 向け設定の保管用です。',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
        ],
        InputDecorator(
          decoration: const InputDecoration(
            labelText: 'コーディング用モデル',
            helperText:
                'コーディングアシスト専用。9B~14B 級推奨。切替時に再起動。'
                '同じフォルダの mtp-*.gguf は対応する本体と自動で併用',
            border: OutlineInputBorder(),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _codingModelDropdownValue(local),
              isExpanded: true,
              hint: Text(
                _targetModels.isEmpty
                    ? 'モデルを追加してください'
                    : LocalLlmPresets.unsetModelLabel,
              ),
              items: _modelDropdownItems(
                orphan: local.usesCustomCodingModel &&
                    _codingModelDropdownValue(local) == 'custom_orphan',
                orphanLabel: local.resolvedCodingModelLabel,
              ),
              onChanged: local.enabled
                  ? (value) => _onCodingModelKeySelected(context, value)
                  : null,
            ),
          ),
        ),
        
        const SizedBox(height: 12),
        InputDecorator(
          decoration: const InputDecoration(
            labelText: 'コーディング用コンテキスト長',
            helperText: '既定 131072（128k） 最低でも32768 (32k)推奨',
            border: OutlineInputBorder(),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: LocalLlmPresets.contextSizeOptions
                      .contains(local.codingContextSize)
                  ? local.codingContextSize
                  : LocalLlmPresets.defaultCodingContextSize,
              isExpanded: true,
              items: [
                for (final size in LocalLlmPresets.contextSizeOptions)
                  DropdownMenuItem(
                    value: size,
                    child: Text('$size'),
                  ),
              ],
              onChanged: local.enabled
                  ? (value) {
                      if (value == null) return;
                      context.read<ApiSettingsBloc>().add(
                            ApiSettingsLocalLlmCodingContextChanged(value),
                          );
                    }
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 24),

        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () async {
              final bloc = context.read<ApiSettingsBloc>();
              await context.push(AppRoutes.addLlmModel);
              if (!mounted) return;
              await _loadCustomModels();
              if (!mounted) return;
              bloc.add(const ApiSettingsStarted());
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('ローカルLLM モデルを追加…'),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildDartSdkSection(BuildContext context, ApiSettingsState state) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'コーディング自動補完 : Flutter',
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (!CodingAssistAvailability.isUiEnabled) ...[
          const SizedBox(height: 8),
          Text(
            'Windows ではコーディング画面がありません（補完も S16 上では使えません）。',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          'Dart／Flutter SDK パス（空＝PATH から dart を探索）',
          style: textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _dartSdkPathController,
                decoration: const InputDecoration(
                  hintText: '例: /Users/you/flutter/bin',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (value) => context.read<ApiSettingsBloc>().add(
                      ApiSettingsDartSdkPathChanged(value),
                    ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () async {
                final dir = await FilePicker.getDirectoryPath(
                  dialogTitle: 'Dart／Flutter SDK を選択',
                );
                if (dir == null || !context.mounted) return;
                _dartSdkPathController.text = dir;
                context.read<ApiSettingsBloc>().add(
                      ApiSettingsDartSdkPathChanged(dir),
                    );
              },
              child: const Text('参照…'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAboutSection(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'このアプリについて',
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => openOssLicensesPage(context),
            icon: const Icon(Icons.balance_outlined, size: 18),
            label: const Text('OSSライセンスを表示'),
          ),
        ),
      ],
    );
  }
}

/// 保存〜llama-server 起動確認完了まで、シェル全体（サイドバー含む）を操作不可にする。
class _ServerRestartBlockingOverlay extends StatelessWidget {
  const _ServerRestartBlockingOverlay();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return AbsorbPointer(
      child: ColoredBox(
        color: colors.dialogBarrier,
        child: Center(
          child: Card(
            color: colors.dialogSurface,
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'llama-server を反映しています…',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '起動確認またはエラーになるまでお待ちください',
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.contentMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
