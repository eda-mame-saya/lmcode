import 'package:equatable/equatable.dart';

import '../../domain/entities/connection_settings.dart';
import '../../domain/entities/local_llm_connection_settings.dart';

/// 接続・API設定画面の状態。
final class ApiSettingsState extends Equatable {
  const ApiSettingsState({
    this.settings = const ConnectionSettings(),
    this.isLoading = true,
    this.isSaving = false,
    this.intervalText = '1000',
    this.localLlmPortText = '${LocalLlmPresets.defaultPort}',
    this.geminiKeyError,
    this.geminiModelError,
    this.localLlmHostError,
    this.localLlmPortError,
    this.localLlmConnectionError,
    this.intervalError,
    this.saveSucceeded = false,
    this.infoMessage,
    this.modelResolvedPath,
    this.modelFileMissing = false,
  });

  final ConnectionSettings settings;
  final bool isLoading;
  final bool isSaving;
  final String intervalText;
  final String localLlmPortText;
  final String? geminiKeyError;
  final String? geminiModelError;
  final String? localLlmHostError;
  final String? localLlmPortError;
  final String? localLlmConnectionError;
  final String? intervalError;
  final bool saveSucceeded;
  final String? infoMessage;
  /// コーディング用モデルの GGUF 解決パス（未発見時 null）。
  final String? modelResolvedPath;
  final bool modelFileMissing;

  ApiSettingsState copyWith({
    ConnectionSettings? settings,
    bool? isLoading,
    bool? isSaving,
    String? intervalText,
    String? localLlmPortText,
    String? geminiKeyError,
    String? geminiModelError,
    String? localLlmHostError,
    String? localLlmPortError,
    String? localLlmConnectionError,
    String? intervalError,
    bool? saveSucceeded,
    String? infoMessage,
    String? modelResolvedPath,
    bool? modelFileMissing,
    bool clearGeminiKeyError = false,
    bool clearGeminiModelError = false,
    bool clearLocalLlmHostError = false,
    bool clearLocalLlmPortError = false,
    bool clearLocalLlmConnectionError = false,
    bool clearIntervalError = false,
    bool clearInfoMessage = false,
    bool clearModelResolvedPath = false,
  }) {
    return ApiSettingsState(
      settings: settings ?? this.settings,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      intervalText: intervalText ?? this.intervalText,
      localLlmPortText: localLlmPortText ?? this.localLlmPortText,
      localLlmHostError: clearLocalLlmHostError
          ? null
          : (localLlmHostError ?? this.localLlmHostError),
      localLlmPortError: clearLocalLlmPortError
          ? null
          : (localLlmPortError ?? this.localLlmPortError),
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
        settings.dartSdkPath,
        settings.provider,
        isLoading,
        isSaving,
        intervalText,
        localLlmPortText,
        localLlmHostError,
        localLlmPortError,
        localLlmConnectionError,
        intervalError,
        saveSucceeded,
        infoMessage,
        modelResolvedPath,
        modelFileMissing,
      ];
}
