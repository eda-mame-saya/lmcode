import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../generative_ai/data/coding_llm_sidecar_coordinator.dart';
import '../../../generative_ai/data/local_llm_client.dart';
import '../../../generative_ai/data/local_llm_server_launcher.dart';
import '../../../generative_ai/data/strata_server_launcher.dart';
import '../../domain/entities/coding_llm_backend.dart';
import '../../domain/entities/generative_ai_provider.dart';
import '../../domain/entities/local_endpoint.dart';
import '../../domain/entities/local_llm_connection_settings.dart';
import '../../domain/entities/strata_connection_settings.dart';
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
    required StrataServerLauncher strataServerLauncher,
    required CodingLlmSidecarCoordinator sidecarCoordinator,
  })  : _getConnectionSettings = getConnectionSettings,
        _saveConnectionSettings = saveConnectionSettings,
        _localLlmClient = localLlmClient,
        _localLlmServerLauncher = localLlmServerLauncher,
        _strataServerLauncher = strataServerLauncher,
        _sidecarCoordinator = sidecarCoordinator,
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
    on<ApiSettingsCodingBackendChanged>(_onCodingBackendChanged);
    on<ApiSettingsStrataEnabledChanged>(_onStrataEnabledChanged);
    on<ApiSettingsStrataHostChanged>(_onStrataHostChanged);
    on<ApiSettingsStrataPortChanged>(_onStrataPortChanged);
    on<ApiSettingsStrataCliPathChanged>(_onStrataCliPathChanged);
    on<ApiSettingsStrataRunConfigPathChanged>(_onStrataRunConfigPathChanged);
    on<ApiSettingsStrataModelIdChanged>(_onStrataModelIdChanged);
    on<ApiSettingsSaveRequested>(_onSaveRequested);
    on<ApiSettingsConnectionTestRequested>(_onConnectionTestRequested);
    on<ApiSettingsSaveMessageConsumed>(_onSaveMessageConsumed);
  }

  final GetConnectionSettings _getConnectionSettings;
  final SaveConnectionSettings _saveConnectionSettings;
  final LocalLlmClient _localLlmClient;
  final LocalLlmServerLauncher _localLlmServerLauncher;
  final StrataServerLauncher _strataServerLauncher;
  final CodingLlmSidecarCoordinator _sidecarCoordinator;

  /// 画面オープン時／前回保存時のローカル LLM 設定（再起動差分検出用）。
  LocalLlmConnectionSettings? _persistedLocalLlm;
  StrataConnectionSettings? _persistedStrata;

  Future<void> _onStarted(
    ApiSettingsStarted event,
    Emitter<ApiSettingsState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, clearLocalLlmConnectionError: true));
    final settings = await _getConnectionSettings();
    _persistedLocalLlm = settings.localLlm;
    _persistedStrata = settings.strata;
    final modelPath =
        await _localLlmServerLauncher.resolveModelPathForSettings(
          settings.localLlm.forServer(),
        );
    final strataCli = await _strataServerLauncher.resolveCliPathForSettings(
      settings.strata,
    );
    final strataConfig =
        await _strataServerLauncher.resolveRunConfigForSettings(
      settings.strata,
    );
    emit(
      state.copyWith(
        isLoading: false,
        settings: settings,
        localLlmPortText: '${settings.localLlm.port}',
        strataPortText: '${settings.strata.port}',
        modelResolvedPath: modelPath,
        clearModelResolvedPath: modelPath == null,
        modelFileMissing: settings.localLlm.enabled &&
            settings.localLlm.usesCustomCodingModel &&
            modelPath == null,
        strataCliPathResolved: strataCli,
        clearStrataCliPathResolved: strataCli == null,
        strataRunConfigResolved: strataConfig,
        clearStrataRunConfigResolved: strataConfig == null,
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

  void _onCodingBackendChanged(
    ApiSettingsCodingBackendChanged event,
    Emitter<ApiSettingsState> emit,
  ) {
    var next = state.settings.copyWith(codingBackend: event.backend);
    // Agent を Strata にしたら Strata を ON に揃える（OFF のまま「未設定」になるのを防ぐ）
    if (event.backend == CodingLlmBackend.strata) {
      next = next.copyWith(
        strata: next.strata.copyWith(enabled: true),
      );
    }
    emit(state.copyWith(settings: next));
  }

  Future<void> _onStrataEnabledChanged(
    ApiSettingsStrataEnabledChanged event,
    Emitter<ApiSettingsState> emit,
  ) async {
    final next = state.settings.strata.copyWith(enabled: event.value);
    final strataCli =
        await _strataServerLauncher.resolveCliPathForSettings(next);
    final strataConfig =
        await _strataServerLauncher.resolveRunConfigForSettings(next);
    emit(
      state.copyWith(
        settings: state.settings.copyWith(strata: next),
        clearStrataHostError: true,
        clearStrataPortError: true,
        strataCliPathResolved: strataCli,
        clearStrataCliPathResolved: strataCli == null,
        strataRunConfigResolved: strataConfig,
        clearStrataRunConfigResolved: strataConfig == null,
      ),
    );
  }

  void _onStrataHostChanged(
    ApiSettingsStrataHostChanged event,
    Emitter<ApiSettingsState> emit,
  ) {
    emit(
      state.copyWith(
        settings: state.settings.copyWith(
          strata: state.settings.strata.copyWith(host: event.value),
        ),
        clearStrataHostError: true,
      ),
    );
  }

  void _onStrataPortChanged(
    ApiSettingsStrataPortChanged event,
    Emitter<ApiSettingsState> emit,
  ) {
    final port = LocalEndpoint.parsePort(event.value);
    emit(
      state.copyWith(
        strataPortText: event.value,
        settings: port == null
            ? state.settings
            : state.settings.copyWith(
                strata: state.settings.strata.copyWith(port: port),
              ),
        clearStrataPortError: true,
      ),
    );
  }

  Future<void> _onStrataCliPathChanged(
    ApiSettingsStrataCliPathChanged event,
    Emitter<ApiSettingsState> emit,
  ) async {
    final next = state.settings.strata.copyWith(cliPath: event.value);
    final strataCli =
        await _strataServerLauncher.resolveCliPathForSettings(next);
    final strataConfig =
        await _strataServerLauncher.resolveRunConfigForSettings(next);
    emit(
      state.copyWith(
        settings: state.settings.copyWith(strata: next),
        strataCliPathResolved: strataCli,
        clearStrataCliPathResolved: strataCli == null,
        strataRunConfigResolved: strataConfig,
        clearStrataRunConfigResolved: strataConfig == null,
      ),
    );
  }

  Future<void> _onStrataRunConfigPathChanged(
    ApiSettingsStrataRunConfigPathChanged event,
    Emitter<ApiSettingsState> emit,
  ) async {
    final next = state.settings.strata.copyWith(runConfigPath: event.value);
    final strataConfig =
        await _strataServerLauncher.resolveRunConfigForSettings(next);
    emit(
      state.copyWith(
        settings: state.settings.copyWith(strata: next),
        strataRunConfigResolved: strataConfig,
        clearStrataRunConfigResolved: strataConfig == null,
      ),
    );
  }

  void _onStrataModelIdChanged(
    ApiSettingsStrataModelIdChanged event,
    Emitter<ApiSettingsState> emit,
  ) {
    emit(
      state.copyWith(
        settings: state.settings.copyWith(
          strata: state.settings.strata.copyWith(modelId: event.value),
        ),
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
    final useStrata =
        state.settings.codingBackend == CodingLlmBackend.strata;
    final strataEnabled = useStrata ? true : state.settings.strata.enabled;
    final strataHost = state.settings.strata.host.trim();
    final strataPort = LocalEndpoint.parsePort(state.strataPortText) ??
        state.settings.strata.port;

    var hasError = false;
    String? localHostError;
    String? localPortError;
    String? strataHostError;
    String? strataPortError;

    if (!useStrata && localEnabled) {
      if (localHost.isEmpty) {
        localHostError = '使用する場合はベースURLが必要です';
        hasError = true;
      }
      if (LocalEndpoint.parsePort(state.localLlmPortText) == null) {
        localPortError = '1〜65535 のポートを入力してください';
        hasError = true;
      }
    }

    if (useStrata) {
      if (strataHost.isEmpty) {
        strataHostError = '使用する場合はベースURLが必要です';
        hasError = true;
      }
      if (LocalEndpoint.parsePort(state.strataPortText) == null) {
        strataPortError = '1〜65535 のポートを入力してください';
        hasError = true;
      }
    }

    if (!useStrata &&
        localEnabled &&
        strataEnabled &&
        localPort == strataPort &&
        _sameListenHost(localHost, strataHost)) {
      strataPortError =
          'llama（$localPort）と同じポートです。Strata は別ポートにしてください（既定 ${StrataPresets.defaultPort}）';
      hasError = true;
    }

    if (hasError) {
      emit(
        state.copyWith(
          localLlmHostError: localHostError,
          localLlmPortError: localPortError,
          strataHostError: strataHostError,
          strataPortError: strataPortError,
          clearLocalLlmHostError: localHostError == null,
          clearLocalLlmPortError: localPortError == null,
          clearStrataHostError: strataHostError == null,
          clearStrataPortError: strataPortError == null,
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
      strata: state.settings.strata.copyWith(
        host: strataHost.isEmpty ? StrataPresets.defaultHost : strataHost,
        port: strataPort,
        enabled: strataEnabled,
        cliPath: state.settings.strata.cliPath.trim(),
        runConfigPath: state.settings.strata.runConfigPath.trim(),
        modelId: state.settings.strata.modelId.trim(),
      ),
      codingBackend: state.settings.codingBackend,
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

    final messages = <String>['保存しました。'];
    final sidecar = await _sidecarCoordinator.apply(
      settings: toSave,
      previousLocalLlm: _persistedLocalLlm,
      previousStrata: _persistedStrata,
      onStatus: (message) {
        debugPrint('[CodingLlm] $message');
      },
      waitForHealth: true,
    );
    if (toSave.codingBackend == CodingLlmBackend.strata) {
      messages.add(
        sidecar.strataReady
            ? 'Strata: ${toSave.strata.baseUrl}（llama 停止）'
            : 'Strata: 起動失敗',
      );
    } else if (!toSave.localLlm.enabled) {
      messages.add('llama-server: OFF（Strata 停止）');
    } else if (sidecar.llamaDraft == null) {
      messages.add(
        sidecar.llamaReady
            ? 'llama-server: ${toSave.localLlm.baseUrl}（Strata 停止）'
            : 'llama-server: 起動失敗',
      );
    } else {
      messages.add(
        'llama-server: ${toSave.localLlm.baseUrl}（MTP ${sidecar.llamaDraft}・Strata 停止）',
      );
    }
    if (sidecar.error != null) {
      messages.add(sidecar.error!);
    }

    _persistedLocalLlm = toSave.localLlm;
    _persistedStrata = toSave.strata;

    emit(
      state.copyWith(
        isSaving: false,
        settings: toSave,
        localLlmPortText: '${toSave.localLlm.port}',
        strataPortText: '${toSave.strata.port}',
        saveSucceeded: true,
        clearGeminiKeyError: true,
        clearGeminiModelError: true,
        clearLocalLlmHostError: true,
        clearLocalLlmPortError: true,
        clearStrataHostError: true,
        clearStrataPortError: true,
        clearIntervalError: true,
        infoMessage: messages.join(' '),
      ),
    );
  }

  Future<void> _onConnectionTestRequested(
    ApiSettingsConnectionTestRequested event,
    Emitter<ApiSettingsState> emit,
  ) async {
    final parts = <String>[];
    final agent = state.settings.codingBackend;
    if (agent == CodingLlmBackend.llamaCpp) {
      if (state.settings.localLlm.enabled) {
        final ok = await _localLlmClient.isReachable(state.settings.localLlm);
        parts.add(
          ok
              ? 'llama-server: OK（${state.settings.localLlm.baseUrl}）'
              : 'llama-server: 未接続（ポート ${state.settings.localLlm.port}）',
        );
      } else {
        parts.add('llama-server: 使用しない');
      }
      parts.add('Strata: 停止（Agent が llama.cpp）');
    } else {
      final ok = await _localLlmClient.isReachable(
        state.settings.strata.toChatClientSettings(),
      );
      parts.add(
        ok
            ? 'Strata: OK（${state.settings.strata.baseUrl}）'
            : 'Strata: 未接続（ポート ${state.settings.strata.port}）',
      );
      parts.add('llama-server: 停止（Agent が Strata）');
    }

    parts.add('Agent: ${agent.label}');

    emit(
      state.copyWith(
        infoMessage: parts.join(' / '),
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

  static bool _sameListenHost(String a, String b) {
    String norm(String raw) {
      final uri = Uri.tryParse(raw.trim());
      if (uri != null && uri.host.isNotEmpty) return uri.host.toLowerCase();
      return raw
          .trim()
          .replaceFirst(RegExp(r'^https?://'), '')
          .split('/')
          .first
          .split(':')
          .first
          .toLowerCase();
    }

    return norm(a) == norm(b);
  }
}
