import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/connection_settings.dart';
import '../../domain/entities/generative_ai_provider.dart';
import '../../domain/entities/local_llm_connection_settings.dart';

/// 接続設定のローカル永続化。
class ApiSettingsLocalDataSource {
  ApiSettingsLocalDataSource({
    required SharedPreferences preferences
  })  : _preferences = preferences;

  final SharedPreferences _preferences;

  static const _prefAiProvider = 'generative_ai_provider';
  static const _prefLocalLlmHost = 'local_llm_host';
  static const _prefLocalLlmPort = 'local_llm_port';
  static const _prefLocalLlmModel = 'local_llm_model_id';
  static const _prefLocalLlmCustomId = 'local_llm_custom_model_id';
  static const _prefLocalLlmCustomLabel = 'local_llm_custom_model_label';
  static const _prefLocalLlmCustomGguf = 'local_llm_custom_gguf_file';
  static const _prefLocalLlmChatModel = 'local_llm_chat_model_id';
  static const _prefLocalLlmChatCustomId = 'local_llm_chat_custom_model_id';
  static const _prefLocalLlmChatCustomLabel = 'local_llm_chat_custom_model_label';
  static const _prefLocalLlmChatCustomGguf = 'local_llm_chat_custom_gguf_file';
  static const _prefLocalLlmContext = 'local_llm_context_size';
  static const _prefLocalLlmThinking = 'local_llm_thinking_enabled';
  static const _prefLocalLlmChatContext = 'local_llm_chat_context_size';
  static const _prefLocalLlmChatThinking = 'local_llm_chat_thinking_enabled';
  static const _prefLocalLlmCodingModel = 'local_llm_coding_model_id';
  static const _prefLocalLlmCodingCustomId = 'local_llm_coding_custom_model_id';
  static const _prefLocalLlmCodingCustomLabel =
      'local_llm_coding_custom_model_label';
  static const _prefLocalLlmCodingCustomGguf = 'local_llm_coding_custom_gguf_file';
  static const _prefLocalLlmCodingContext = 'local_llm_coding_context_size';
  static const _prefLocalLlmCodingThinking = 'local_llm_coding_thinking_enabled';
  static const _prefLocalLlmCodingAutoApply =
      'local_llm_coding_auto_apply_patches';
  static const _prefLocalLlmEnabled = 'local_llm_enabled';
  static const _prefDartSdkPath = 'dart_sdk_path';

  Future<ConnectionSettings> load() async {
    const provider = GenerativeAiProvider.localLlm;

    final localHost = _preferences.getString(_prefLocalLlmHost);
    final localPort = _preferences.getInt(_prefLocalLlmPort);
    final localModel = _preferences.getString(_prefLocalLlmModel);
    final localContext = _preferences.getInt(_prefLocalLlmContext);
    final localThinking = _preferences.getBool(_prefLocalLlmThinking);
    final localEnabled = _preferences.getBool(_prefLocalLlmEnabled) ??
        true;

    final localLlm = LocalLlmConnectionSettings.fromStored(
      endpointOrHost: localHost,
      port: localPort,
      codingModelNameOrId: _preferences.getString(_prefLocalLlmCodingModel),
      codingCustomModelId: _preferences.getString(_prefLocalLlmCodingCustomId),
      codingCustomModelLabel:
          _preferences.getString(_prefLocalLlmCodingCustomLabel),
      codingCustomGgufFileName:
          _preferences.getString(_prefLocalLlmCodingCustomGguf),
      codingContextSize: _preferences.getInt(_prefLocalLlmCodingContext),
      codingThinkingEnabled: _preferences.getBool(_prefLocalLlmCodingThinking),
      codingAutoApplyPatches:
          _preferences.getBool(_prefLocalLlmCodingAutoApply),
      enabled: localEnabled,
      legacyModelNameOrId: localModel,
      legacyCustomModelId: _preferences.getString(_prefLocalLlmCustomId),
      legacyCustomModelLabel: _preferences.getString(_prefLocalLlmCustomLabel),
      legacyCustomGgufFileName: _preferences.getString(_prefLocalLlmCustomGguf),
      legacyChatModelNameOrId: _preferences.getString(_prefLocalLlmChatModel),
      legacyChatCustomModelId:
          _preferences.getString(_prefLocalLlmChatCustomId),
      legacyChatCustomModelLabel:
          _preferences.getString(_prefLocalLlmChatCustomLabel),
      legacyChatCustomGgufFileName:
          _preferences.getString(_prefLocalLlmChatCustomGguf),
      legacyContextSize: localContext,
      legacyThinkingEnabled: localThinking,
    );

    return ConnectionSettings(
      localLlm: localLlm,
      provider: provider,
      dartSdkPath: _preferences.getString(_prefDartSdkPath) ?? '',
    );
  }

  Future<void> save(ConnectionSettings settings) async {
    await _preferences.setString(
      _prefAiProvider,
      settings.provider.storageValue,
    );
    await _preferences.setString(
      _prefLocalLlmHost,
      settings.localLlm.host.trim(),
    );
    await _preferences.setInt(_prefLocalLlmPort, settings.localLlm.port);
    final llm = settings.localLlm;
    if (llm.usesCustomCodingModel) {
      await _preferences.setString(
        _prefLocalLlmCodingModel,
        'custom:${llm.codingCustomGgufFileName!.trim()}',
      );
      await _preferences.setString(
        _prefLocalLlmCodingCustomId,
        (llm.codingCustomModelId ?? '').trim(),
      );
      await _preferences.setString(
        _prefLocalLlmCodingCustomLabel,
        (llm.codingCustomModelLabel ?? '').trim(),
      );
      await _preferences.setString(
        _prefLocalLlmCodingCustomGguf,
        llm.codingCustomGgufFileName!.trim(),
      );
    } else {
      await _preferences.remove(_prefLocalLlmCodingModel);
      await _preferences.remove(_prefLocalLlmCodingCustomId);
      await _preferences.remove(_prefLocalLlmCodingCustomLabel);
      await _preferences.remove(_prefLocalLlmCodingCustomGguf);
    }
    await _preferences.setInt(
      _prefLocalLlmCodingContext,
      settings.localLlm.codingContextSize,
    );
    await _preferences.setBool(
      _prefLocalLlmCodingThinking,
      settings.localLlm.codingThinkingEnabled,
    );
    await _preferences.setBool(
      _prefLocalLlmCodingAutoApply,
      settings.localLlm.codingAutoApplyPatches,
    );
    await _preferences.setBool(
      _prefLocalLlmEnabled,
      settings.localLlm.enabled,
    );
    await _preferences.setString(
      _prefDartSdkPath,
      settings.dartSdkPath.trim(),
    );
    await _preferences.remove(_prefLocalLlmModel);
    await _preferences.remove(_prefLocalLlmCustomId);
    await _preferences.remove(_prefLocalLlmCustomLabel);
    await _preferences.remove(_prefLocalLlmCustomGguf);
    await _preferences.remove(_prefLocalLlmContext);
    await _preferences.remove(_prefLocalLlmThinking);
    await _preferences.remove(_prefLocalLlmChatModel);
    await _preferences.remove(_prefLocalLlmChatCustomId);
    await _preferences.remove(_prefLocalLlmChatCustomLabel);
    await _preferences.remove(_prefLocalLlmChatCustomGguf);
    await _preferences.remove(_prefLocalLlmChatContext);
    await _preferences.remove(_prefLocalLlmChatThinking);
  }
}
