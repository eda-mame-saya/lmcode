import 'local_endpoint.dart';
import 'local_llm_connection_settings.dart';
import 'strata_thinking_effort.dart';

export 'strata_thinking_effort.dart';

/// Strata（ローカル OpenAI／Anthropic 互換サーバ）の接続設定。
///
/// llama-server（既定 8080）と同時起動できるよう、**既定ポートは 8090**。
class StrataConnectionSettings {
  const StrataConnectionSettings({
    this.host = StrataPresets.defaultHost,
    this.port = StrataPresets.defaultPort,
    this.enabled = false,
    this.cliPath = '',
    this.runConfigPath = '',
    this.modelId = '',
    this.thinkingEffort = StrataThinkingEffort.none,
  });

  /// ホスト（スキーム＋ホスト。例: `http://127.0.0.1`）。
  final String host;

  /// ポート（既定 [StrataPresets.defaultPort] = 8090）。
  final int port;

  /// LMCode から Strata を起動し Agent 等で使うか。
  final bool enabled;

  /// `strata` CLI の絶対パス。空＝自動探索。
  final String cliPath;

  /// run config（`strata-*.json`）の絶対パス。空＝インストール済みモデルから自動選択。
  final String runConfigPath;

  /// API `model` 識別子。空＝起動後に `/v1/models` から取得、または `strata`。
  final String modelId;

  /// S16 歯車の思考段階。リクエストの `reasoning_effort` に載せる（再起動不要）。
  final StrataThinkingEffort thinkingEffort;

  bool get hasEndpoint => host.trim().isNotEmpty && port > 0;

  bool get isUsable => enabled && hasEndpoint;

  String get baseUrl => LocalEndpoint.compose(host, port);

  Uri get resolvedBaseUri {
    final raw = baseUrl.trim();
    final normalized =
        raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
    return Uri.parse(normalized);
  }

  /// [LocalLlmClient] へ渡す OpenAI 互換設定。
  ///
  /// [contextSize] は run config の `--max-context`。未指定時は既定 65536。
  LocalLlmConnectionSettings toChatClientSettings({
    String? resolvedModelId,
    int? contextSize,
  }) {
    final id = (resolvedModelId ?? modelId).trim();
    final effectiveId = id.isEmpty ? StrataPresets.fallbackModelId : id;
    final ctx = (contextSize != null && contextSize > 0)
        ? contextSize
        : StrataPresets.defaultContextSize;
    return LocalLlmConnectionSettings(
      host: host,
      port: port,
      enabled: enabled,
      codingCustomModelId: effectiveId,
      codingCustomModelLabel: effectiveId,
      // llama-server 起動対象から外す仮想マーカー
      codingCustomGgufFileName: '${StrataPresets.virtualGgufPrefix}$effectiveId',
      codingContextSize: ctx,
      codingThinkingEnabled: thinkingEffort.isEnabled,
      codingAutoApplyPatches: false,
      reasoningEffort: thinkingEffort.apiValue,
    );
  }

  StrataConnectionSettings copyWith({
    String? host,
    int? port,
    bool? enabled,
    String? cliPath,
    String? runConfigPath,
    String? modelId,
    StrataThinkingEffort? thinkingEffort,
  }) {
    return StrataConnectionSettings(
      host: host ?? this.host,
      port: port ?? this.port,
      enabled: enabled ?? this.enabled,
      cliPath: cliPath ?? this.cliPath,
      runConfigPath: runConfigPath ?? this.runConfigPath,
      modelId: modelId ?? this.modelId,
      thinkingEffort: thinkingEffort ?? this.thinkingEffort,
    );
  }

  factory StrataConnectionSettings.fromStored({
    String? host,
    int? port,
    bool? enabled,
    String? cliPath,
    String? runConfigPath,
    String? modelId,
    String? thinkingEffort,
  }) {
    final split = LocalEndpoint.split(
      host ?? StrataPresets.defaultHost,
      defaultPort: StrataPresets.defaultPort,
      defaultHost: StrataPresets.defaultHost,
    );
    return StrataConnectionSettings(
      host: split.host,
      port: port ?? split.port,
      enabled: enabled ?? false,
      cliPath: cliPath?.trim() ?? '',
      runConfigPath: runConfigPath?.trim() ?? '',
      modelId: modelId?.trim() ?? '',
      thinkingEffort: StrataThinkingEffort.fromStorage(thinkingEffort),
    );
  }
}

/// Strata 連携の既定値。
abstract final class StrataPresets {
  static const defaultHost = 'http://127.0.0.1';

  /// llama-server（8080）と衝突しない既定。
  static const defaultPort = 8090;

  static const defaultContextSize = 65536;
  static const fallbackModelId = 'strata';
  static const virtualGgufPrefix = 'strata://';
  static const defaultProfileHint = 'lmcode';
}
