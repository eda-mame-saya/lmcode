import 'package:equatable/equatable.dart';

import '../../domain/entities/connection_settings.dart';
import '../../domain/entities/local_llm_connection_settings.dart';
import '../../domain/entities/strata_connection_settings.dart';

/// 接続・API設定画面の状態。
final class ApiSettingsState extends Equatable {
  const ApiSettingsState({
    this.settings = const ConnectionSettings(),
    this.isLoading = true,
    this.isSaving = false,
    this.intervalText = '1000',
    this.localLlmPortText = '${LocalLlmPresets.defaultPort}',
    this.strataPortText = '${StrataPresets.defaultPort}',
    this.geminiKeyError,
    this.geminiModelError,
    this.localLlmHostError,
    this.localLlmPortError,
    this.strataHostError,
    this.strataPortError,
    this.localLlmConnectionError,
    this.intervalError,
    this.saveSucceeded = false,
    this.infoMessage,
    this.modelResolvedPath,
    this.modelFileMissing = false,
    this.strataCliPathResolved,
    this.strataRunConfigResolved,
  });

  final ConnectionSettings settings;
  final bool isLoading;
  final bool isSaving;
  final String intervalText;
  final String localLlmPortText;
  final String strataPortText;
  final String? geminiKeyError;
  final String? geminiModelError;
  final String? localLlmHostError;
  final String? localLlmPortError;
  final String? strataHostError;
  final String? strataPortError;
  final String? localLlmConnectionError;
  final String? intervalError;
  final bool saveSucceeded;
  final String? infoMessage;
  /// コーディング用モデルの GGUF 解決パス（未発見時 null）。
  final String? modelResolvedPath;
  final bool modelFileMissing;
  final String? strataCliPathResolved;
  final String? strataRunConfigResolved;

  ApiSettingsState copyWith({
    ConnectionSettings? settings,
    bool? isLoading,
    bool? isSaving,
    String? intervalText,
    String? localLlmPortText,
    String? strataPortText,
    String? geminiKeyError,
    String? geminiModelError,
    String? localLlmHostError,
    String? localLlmPortError,
    String? strataHostError,
    String? strataPortError,
    String? localLlmConnectionError,
    String? intervalError,
    bool? saveSucceeded,
    String? infoMessage,
    String? modelResolvedPath,
    bool? modelFileMissing,
    String? strataCliPathResolved,
    String? strataRunConfigResolved,
    bool clearGeminiKeyError = false,
    bool clearGeminiModelError = false,
    bool clearLocalLlmHostError = false,
    bool clearLocalLlmPortError = false,
    bool clearStrataHostError = false,
    bool clearStrataPortError = false,
    bool clearLocalLlmConnectionError = false,
    bool clearIntervalError = false,
    bool clearInfoMessage = false,
    bool clearModelResolvedPath = false,
    bool clearStrataCliPathResolved = false,
    bool clearStrataRunConfigResolved = false,
  }) {
    return ApiSettingsState(
      settings: settings ?? this.settings,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      intervalText: intervalText ?? this.intervalText,
      localLlmPortText: localLlmPortText ?? this.localLlmPortText,
      strataPortText: strataPortText ?? this.strataPortText,
      localLlmHostError: clearLocalLlmHostError
          ? null
          : (localLlmHostError ?? this.localLlmHostError),
      localLlmPortError: clearLocalLlmPortError
          ? null
          : (localLlmPortError ?? this.localLlmPortError),
      strataHostError: clearStrataHostError
          ? null
          : (strataHostError ?? this.strataHostError),
      strataPortError: clearStrataPortError
          ? null
          : (strataPortError ?? this.strataPortError),
      localLlmConnectionError: clearLocalLlmConnectionError
          ? null
          : (localLlmConnectionError ?? this.localLlmConnectionError),
      intervalError:
          clearIntervalError ? null : (intervalError ?? this.intervalError),
      saveSucceeded: saveSucceeded ?? this.saveSucceeded,
      infoMessage:
          clearInfoMessage ? null : (infoMessage ?? this.infoMessage),
      modelResolvedPath: clearModelResolvedPath
          ? null
          : (modelResolvedPath ?? this.modelResolvedPath),
      modelFileMissing: modelFileMissing ?? this.modelFileMissing,
      strataCliPathResolved: clearStrataCliPathResolved
          ? null
          : (strataCliPathResolved ?? this.strataCliPathResolved),
      strataRunConfigResolved: clearStrataRunConfigResolved
          ? null
          : (strataRunConfigResolved ?? this.strataRunConfigResolved),
    );
  }

  @override
  List<Object?> get props => [
        settings.localLlm.host,
        settings.localLlm.port,
        settings.localLlm.codingCustomModelId,
        settings.localLlm.codingCustomGgufFileName,
        settings.localLlm.codingContextSize,
        settings.localLlm.codingAutoApplyPatches,
        settings.localLlm.enabled,
        settings.strata.host,
        settings.strata.port,
        settings.strata.enabled,
        settings.strata.cliPath,
        settings.strata.runConfigPath,
        settings.strata.modelId,
        settings.codingBackend,
        settings.dartSdkPath,
        settings.provider,
        isLoading,
        isSaving,
        intervalText,
        localLlmPortText,
        strataPortText,
        localLlmHostError,
        localLlmPortError,
        strataHostError,
        strataPortError,
        localLlmConnectionError,
        intervalError,
        saveSucceeded,
        infoMessage,
        modelResolvedPath,
        modelFileMissing,
        strataCliPathResolved,
        strataRunConfigResolved,
      ];
}
