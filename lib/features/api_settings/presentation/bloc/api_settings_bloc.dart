import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../generative_ai/data/local_llm_client.dart';
import '../../../generative_ai/data/local_llm_server_launcher.dart';
import '../../domain/entities/generative_ai_provider.dart';
import '../../domain/entities/local_endpoint.dart';
import '../../domain/entities/local_llm_connection_settings.dart';
import '../../domain/usecases/get_connection_settings.dart';
import '../../domain/usecases/save_connection_settings.dart';
import 'api_settings_event.dart';
import 'api_settings_state.dart';

/// 接続・API設定画面の状態管理（S11）。
class ApiSettingsBloc extends Bloc<ApiSettingsEvent, ApiSettingsState> {
  ApiSettingsBloc({
    required GetConnectionSettings getConnectionSettings,
    required SaveConnectionSettings saveConnectionSettings,
    required LocalLlmClient localLlmClient,
    required LocalLlmServerLauncher localLlmServerLauncher,
  })  : _getConnectionSettings = getConnectionSettings,
        _saveConnectionSettings = saveConnectionSettings,
        _localLlmClient = localLlmClient,
        _localLlmServerLauncher = localLlmServerLauncher,
        super(const ApiSettingsState()) {
    on<ApiSettingsStarted>(_onStarted);
    on<ApiSettingsIntervalChanged>(_onIntervalChanged);
    on<ApiSettingsProviderChanged>(_onProviderChanged);
    on<ApiSettingsLocalLlmEnabledChanged>(_onLocalLlmEnabledChanged);
    on<ApiSettingsLocalLlmHostChanged>(_onLocalLlmHostChanged);
    on<ApiSettingsLocalLlmPortChanged>(_onLocalLlmPortChanged);
    on<ApiSettingsLocalLlmCodingCustomModelChanged>(
      _onLocalLlmCodingCustomModelChanged,
    );
    on<ApiSettingsLocalLlmCodingContextChanged>(_onLocalLlmCodingContextChanged);
    on<ApiSettingsDartSdkPathChanged>(_onDartSdkPathChanged);
    on<ApiSettingsSaveRequested>(_onSaveRequested);
    on<ApiSettingsConnectionTestRequested>(_onConnectionTestRequested);
    on<ApiSettingsSaveMessageConsumed>(_onSaveMessageConsumed);
  }

  final GetConnectionSettings _getConnectionSettings;
  final SaveConnectionSettings _saveConnectionSettings;
  final LocalLlmClient _localLlmClient;
  final LocalLlmServerLauncher _localLlmServerLauncher;

  /// 画面オープン時／前回保存時のローカル LLM 設定（再起動差分検出用）。
  LocalLlmConnectionSettings? _persistedLocalLlm;

  Future<void> _onStarted(
    ApiSettingsStarted event,
    Emitter<ApiSettingsState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, clearLocalLlmConnectionError: true));
    final settings = await _getConnectionSettings();
    _persistedLocalLlm = settings.localLlm;
    final modelPath =
        await _localLlmServerLauncher.resolveModelPathForSettings(
          settings.localLlm.forServer(),
        );
    emit(
      state.copyWith(
        isLoading: false,
        settings: settings,
        localLlmPortText: '${settings.localLlm.port}',
        modelResolvedPath: modelPath,
        clearModelResolvedPath: modelPath == null,
        modelFileMissing: settings.localLlm.enabled &&
            settings.localLlm.usesCustomCodingModel &&
            modelPath == null,
      ),
    );
  }

  void _onIntervalChanged(
    ApiSettingsIntervalChanged event,
    Emitter<ApiSettingsState> emit,
  ) {
    emit(
      state.copyWith(
        intervalText: event.value,
        clearIntervalError: true,
      ),
    );
  }

  void _onProviderChanged(
    ApiSettingsProviderChanged event,
    Emitter<ApiSettingsState> emit,
  ) {
    emit(
      state.copyWith(
        settings: state.settings.copyWith(provider: event.provider),
        clearGeminiKeyError: true,
        clearGeminiModelError: true,
        clearLocalLlmHostError: true,
        clearLocalLlmPortError: true,
      ),
    );
  }

  Future<void> _onLocalLlmEnabledChanged(
    ApiSettingsLocalLlmEnabledChanged event,
    Emitter<ApiSettingsState> emit,
  ) async {
    final next = state.settings.localLlm.copyWith(enabled: event.value);
    final modelPath =
        await _localLlmServerLauncher.resolveModelPathForSettings(
      next.forServer(),
    );
    emit(
      state.copyWith(
        settings: state.settings.copyWith(localLlm: next),
        clearLocalLlmHostError: true,
        clearLocalLlmPortError: true,
        modelResolvedPath: modelPath,
        clearModelResolvedPath: modelPath == null,
        modelFileMissing:
            event.value && next.usesCustomCodingModel && modelPath == null,
      ),
    );
  }

  void _onLocalLlmHostChanged(
    ApiSettingsLocalLlmHostChanged event,
    Emitter<ApiSettingsState> emit,
  ) {
    emit(
      state.copyWith(
        settings: state.settings.copyWith(
          localLlm: state.settings.localLlm.copyWith(host: event.value),
        ),
        clearLocalLlmHostError: true,
      ),
    );
  }

  void _onLocalLlmPortChanged(
    ApiSettingsLocalLlmPortChanged event,
    Emitter<ApiSettingsState> emit,
  ) {
    final port = LocalEndpoint.parsePort(event.value);
    emit(
      state.copyWith(
        localLlmPortText: event.value,
        settings: port == null
            ? state.settings
            : state.settings.copyWith(
                localLlm: state.settings.localLlm.copyWith(port: port),
              ),
        clearLocalLlmPortError: true,
      ),
    );
  }

  Future<void> _onLocalLlmCodingCustomModelChanged(
    ApiSettingsLocalLlmCodingCustomModelChanged event,
    Emitter<ApiSettingsState> emit,
  ) async {
    final next = state.settings.localLlm.withCustomCodingModel(
      id: event.model.id,
      label: event.model.label,
      ggufFileName: event.model.ggufFileName,
    );
    final modelPath =
        await _localLlmServerLauncher.resolveModelPathForSettings(
      next.forServer(),
    );
    emit(
      state.copyWith(
        settings: state.settings.copyWith(localLlm: next),
        modelResolvedPath: modelPath,
        clearModelResolvedPath: modelPath == null,
        modelFileMissing:
            next.enabled && next.usesCustomCodingModel && modelPath == null,
        clearInfoMessage: true,
      ),
    );
  }

  void _onLocalLlmCodingContextChanged(
    ApiSettingsLocalLlmCodingContextChanged event,
    Emitter<ApiSettingsState> emit,
  ) {
    emit(
      state.copyWith(
        settings: state.settings.copyWith(
          localLlm: state.settings.localLlm
              .copyWith(codingContextSize: event.value),
        ),
      ),
    );
  }

  void _onDartSdkPathChanged(
    ApiSettingsDartSdkPathChanged event,
    Emitter<ApiSettingsState> emit,
  ) {
    emit(
      state.copyWith(
        settings: state.settings.copyWith(dartSdkPath: event.value),
      ),
    );
  }

  Future<void> _onSaveRequested(
    ApiSettingsSaveRequested event,
    Emitter<ApiSettingsState> emit,
  ) async {
    const provider = GenerativeAiProvider.localLlm;
    final localEnabled = state.settings.localLlm.enabled;
    final localHost = state.settings.localLlm.host.trim();
    final localPort = LocalEndpoint.parsePort(state.localLlmPortText) ??
        state.settings.localLlm.port;

    var hasError = false;
    String? localHostError;
    String? localPortError;
    String? intervalError;

    if (provider == GenerativeAiProvider.localLlm && localEnabled) {
      if (localHost.isEmpty) {
        localHostError = '使用する場合はベースURLが必要です';
        hasError = true;
      }
      if (LocalEndpoint.parsePort(state.localLlmPortText) == null) {
        localPortError = '1〜65535 のポートを入力してください';
        hasError = true;
      }
    }

    if (hasError) {
      emit(
        state.copyWith(
          localLlmHostError: localHostError,
          localLlmPortError: localPortError,
          intervalError: intervalError,
          clearLocalLlmHostError: localHostError == null,
          clearLocalLlmPortError: localPortError == null,
        ),
      );
      return;
    }

    emit(state.copyWith(isSaving: true));

    final toSave = state.settings.copyWith(
      localLlm: state.settings.localLlm.copyWith(
        host: localHost.isEmpty ? LocalLlmPresets.defaultHost : localHost,
        port: localPort,
        enabled: localEnabled,
      ),
      provider: provider,
      dartSdkPath: state.settings.dartSdkPath.trim(),
    );

    try {
      await _saveConnectionSettings(toSave).timeout(
        const Duration(seconds: 10),
      );
    } catch (_) {
      emit(
        state.copyWith(
          isSaving: false,
          infoMessage: '保存に失敗しました。しばらくしてから再度お試しください。',
        ),
      );
      return;
    }

    String serverMessage = '保存しました。';
    try {
      // 進捗 Snackbar は出さず、画面オーバーレイだけで待機させる
      // 保存時は会議 AI 用モデルで起動（S13 入場時にチャット用へ切替）。
      final draftName = await _localLlmServerLauncher.applySettings(
        settings: toSave.localLlm.forServer(),
        previous: _persistedLocalLlm?.forServer(),
        isHealthy: _localLlmClient.isReachable,
        onStatus: (message) {
          debugPrint('[LocalLlm] $message');
        },
        waitForHealth: true,
      );
      serverMessage = !toSave.localLlm.enabled
          ? '保存しました。ローカル LLM は OFF です。'
          : draftName == null
              ? '保存しました。llama-server を反映済みです（${toSave.localLlm.baseUrl}）。'
              : '保存しました。MTP 下書き係を併用します（$draftName）。';
    } catch (e) {
      serverMessage =
          '設定は保存しましたが、llama-server の起動／再起動に失敗しました: $e';
    }
    _persistedLocalLlm = toSave.localLlm;

    emit(
      state.copyWith(
        isSaving: false,
        settings: toSave,
        localLlmPortText: '${toSave.localLlm.port}',
        saveSucceeded: true,
        clearGeminiKeyError: true,
        clearGeminiModelError: true,
        clearLocalLlmHostError: true,
        clearLocalLlmPortError: true,
        clearIntervalError: true,
        infoMessage: serverMessage,
      ),
    );
  }

  Future<void> _onConnectionTestRequested(
    ApiSettingsConnectionTestRequested event,
    Emitter<ApiSettingsState> emit,
  ) async {
    final String llmMsg;
    if (state.settings.localLlm.enabled) {
      final ok = await _localLlmClient.isReachable(state.settings.localLlm);
      llmMsg = ok
          ? 'llama-server: OK（${state.settings.localLlm.baseUrl}）'
          : 'llama-server: 未接続（起動とポート ${state.settings.localLlm.port} を確認）';
    } else {
      llmMsg = 'llama-server: 使用しない設定';
    }

    emit(
      state.copyWith(
        infoMessage: llmMsg,
        clearLocalLlmConnectionError: true,
      ),
    );
  }

  void _onSaveMessageConsumed(
    ApiSettingsSaveMessageConsumed event,
    Emitter<ApiSettingsState> emit,
  ) {
    emit(
      state.copyWith(
        saveSucceeded: false,
        clearInfoMessage: true,
      ),
    );
  }
}
