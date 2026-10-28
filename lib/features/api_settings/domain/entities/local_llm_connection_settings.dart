import 'local_endpoint.dart';

/// ローカル LLM（llama.cpp / llama-server）の接続設定。
/// 本アプリでは **コーディング用**のモデル／ctx／thinking のみを使う。
///
/// GGUF はアプリ同梱しない。ユーザーが S11a で取り込んだモデルのみ選択できる。
class LocalLlmConnectionSettings {
  const LocalLlmConnectionSettings({
    this.host = LocalLlmPresets.defaultHost,
    this.port = LocalLlmPresets.defaultPort,
    this.codingCustomModelId,
    this.codingCustomModelLabel,
    this.codingCustomGgufFileName,
    this.codingContextSize = LocalLlmPresets.defaultCodingContextSize,
    this.codingThinkingEnabled = false,
    this.codingAutoApplyPatches = false,
    this.enabled = true,
  });

  /// ホスト（スキーム＋ホスト。例: `http://127.0.0.1`）。
  final String host;

  /// ポート（既定 8080）。接続および `llama-server --port`。
  final int port;

  /// コーディング用カスタムモデルの ID。
  final String? codingCustomModelId;

  /// コーディング用カスタムの表示名。
  final String? codingCustomModelLabel;

  /// コーディング用カスタム GGUF ファイル名。
  final String? codingCustomGgufFileName;

  /// コーディング用 `--ctx-size`。
  final int codingContextSize;

  /// コーディング用 `--reasoning on|off`。既定 OFF。
  final bool codingThinkingEnabled;

  /// S16 ツールバー「Agent自動実行」。変更案（Update）を確認なしで適用。既定 OFF。
  final bool codingAutoApplyPatches;

  /// ローカル LLM をアプリ機能で使うか。
  final bool enabled;

  bool get usesCustomCodingModel {
    final file = codingCustomGgufFileName?.trim() ?? '';
    return file.isNotEmpty;
  }

  /// コーディング用の表示ラベル。
  String get resolvedCodingModelLabel {
    if (!usesCustomCodingModel) return LocalLlmPresets.unsetModelLabel;
    final label = codingCustomModelLabel?.trim() ?? '';
    if (label.isNotEmpty) return label;
    return codingCustomGgufFileName!.trim();
  }

  /// コーディング用の API `model` 識別子。
  String get codingModelName {
    if (!usesCustomCodingModel) return '';
    final id = codingCustomModelId?.trim() ?? '';
    if (id.isNotEmpty) return id;
    final file = codingCustomGgufFileName!.trim();
    final dot = file.toLowerCase().lastIndexOf('.gguf');
    return dot > 0 ? file.substring(0, dot) : file;
  }

  // --- llama-server / OpenAI 互換クライアント向けエイリアス ---

  bool get usesCustomModel => usesCustomCodingModel;

  String? get customModelId => codingCustomModelId;

  String? get customModelLabel => codingCustomModelLabel;

  String? get customGgufFileName => codingCustomGgufFileName;

  String get resolvedModelLabel => resolvedCodingModelLabel;

  String get modelName => codingModelName;

  int get contextSize => codingContextSize;

  bool get thinkingEnabled => codingThinkingEnabled;

  bool get hasEndpoint => host.trim().isNotEmpty && port > 0;

  /// コーディング用モデルが揃っているか（本アプリの設定完了条件）。
  bool get isConfigured => hasEndpoint && usesCustomCodingModel;

  bool get isCodingConfigured => isConfigured;

  bool get isUsable => enabled && isConfigured;

  bool get isCodingUsable => isUsable;

  /// 接続先フル URL（例: `http://127.0.0.1:8080`）。
  String get baseUrl => LocalEndpoint.compose(host, port);

  Uri get resolvedBaseUri {
    final raw = baseUrl.trim();
    final normalized = raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
    return Uri.parse(normalized);
  }

  /// 起動・API 用。coding のみのため自身を返す。
  LocalLlmConnectionSettings forServer() => this;

  LocalLlmConnectionSettings copyWith({
    String? host,
    int? port,
    String? codingCustomModelId,
    String? codingCustomModelLabel,
    String? codingCustomGgufFileName,
    int? codingContextSize,
    bool? codingThinkingEnabled,
    bool? codingAutoApplyPatches,
    bool? enabled,
    bool clearCodingCustomModel = false,
  }) {
    return LocalLlmConnectionSettings(
      host: host ?? this.host,
      port: port ?? this.port,
      codingCustomModelId: clearCodingCustomModel
          ? null
          : (codingCustomModelId ?? this.codingCustomModelId),
      codingCustomModelLabel: clearCodingCustomModel
          ? null
          : (codingCustomModelLabel ?? this.codingCustomModelLabel),
      codingCustomGgufFileName: clearCodingCustomModel
          ? null
          : (codingCustomGgufFileName ?? this.codingCustomGgufFileName),
      codingContextSize: codingContextSize ?? this.codingContextSize,
      codingThinkingEnabled:
          codingThinkingEnabled ?? this.codingThinkingEnabled,
      codingAutoApplyPatches:
          codingAutoApplyPatches ?? this.codingAutoApplyPatches,
      enabled: enabled ?? this.enabled,
    );
  }

  /// コーディング用にカスタム GGUF を選択。
  LocalLlmConnectionSettings withCustomCodingModel({
    required String id,
    required String label,
    required String ggufFileName,
  }) {
    return copyWith(
      codingCustomModelId: id,
      codingCustomModelLabel: label,
      codingCustomGgufFileName: ggufFileName,
    );
  }

  /// 永続値からの復元。コーディング用のみ。
  /// コーディング未保存時は旧会議／チャット用キーを一度だけフォールバックする。
  factory LocalLlmConnectionSettings.fromStored({
    String? endpointOrHost,
    int? port,
    String? codingModelNameOrId,
    String? codingCustomModelId,
    String? codingCustomModelLabel,
    String? codingCustomGgufFileName,
    int? codingContextSize,
    bool? codingThinkingEnabled,
    bool? codingAutoApplyPatches,
    bool? enabled,
    // 旧キー（移行用。結果には会議／チャットスロットを持たない）
    String? legacyModelNameOrId,
    String? legacyCustomModelId,
    String? legacyCustomModelLabel,
    String? legacyCustomGgufFileName,
    String? legacyChatModelNameOrId,
    String? legacyChatCustomModelId,
    String? legacyChatCustomModelLabel,
    String? legacyChatCustomGgufFileName,
    int? legacyContextSize,
    bool? legacyThinkingEnabled,
  }) {
    final split = LocalEndpoint.split(
      endpointOrHost ?? LocalLlmPresets.defaultHost,
      defaultPort: _migrateDefaultPort(endpointOrHost),
      defaultHost: LocalLlmPresets.defaultHost,
    );
    final hasCodingStored =
        (codingModelNameOrId?.trim().isNotEmpty ?? false) ||
            (codingCustomGgufFileName?.trim().isNotEmpty ?? false) ||
            (codingCustomModelId?.trim().isNotEmpty ?? false);
    final coding = hasCodingStored
        ? _resolveModelSelection(
            modelNameOrId: codingModelNameOrId,
            customModelId: codingCustomModelId,
            customModelLabel: codingCustomModelLabel,
            customGgufFileName: codingCustomGgufFileName,
          )
        : _resolveModelSelection(
            modelNameOrId: legacyChatModelNameOrId ?? legacyModelNameOrId,
            customModelId: legacyChatCustomModelId ?? legacyCustomModelId,
            customModelLabel:
                legacyChatCustomModelLabel ?? legacyCustomModelLabel,
            customGgufFileName:
                legacyChatCustomGgufFileName ?? legacyCustomGgufFileName,
          );
    return LocalLlmConnectionSettings(
      host: split.host,
      port: port ?? split.port,
      codingCustomModelId: coding.customModelId,
      codingCustomModelLabel: coding.customModelLabel,
      codingCustomGgufFileName: coding.customGgufFileName,
      codingContextSize: codingContextSize ??
          legacyContextSize ??
          LocalLlmPresets.defaultCodingContextSize,
      codingThinkingEnabled:
          codingThinkingEnabled ?? legacyThinkingEnabled ?? false,
      codingAutoApplyPatches: codingAutoApplyPatches ?? false,
      enabled: enabled ?? true,
    );
  }

  static ({
    String? customModelId,
    String? customModelLabel,
    String? customGgufFileName,
  }) _resolveModelSelection({
    String? modelNameOrId,
    String? customModelId,
    String? customModelLabel,
    String? customGgufFileName,
  }) {
    final customFile = customGgufFileName?.trim() ?? '';
    final storedModel = modelNameOrId?.trim() ?? '';
    String? resolvedCustomId = customModelId?.trim();
    String? resolvedCustomLabel = customModelLabel?.trim();
    String? resolvedCustomFile = customFile.isEmpty ? null : customFile;
    if (resolvedCustomFile == null && storedModel.startsWith('custom:')) {
      resolvedCustomFile = storedModel.substring('custom:'.length);
      resolvedCustomId ??= resolvedCustomFile;
      resolvedCustomLabel ??= resolvedCustomFile;
    }
    // 旧組み込み ID（qwen35_4b 等）のみの場合は未設定のまま。
    return (
      customModelId: resolvedCustomFile == null ? null : resolvedCustomId,
      customModelLabel: resolvedCustomFile == null ? null : resolvedCustomLabel,
      customGgufFileName: resolvedCustomFile,
    );
  }

  /// 旧 Ollama 既定 11434 が prefs に残っている場合はそのまま、未設定なら 8080。
  static int _migrateDefaultPort(String? endpointOrHost) {
    if (endpointOrHost == null || endpointOrHost.trim().isEmpty) {
      return LocalLlmPresets.defaultPort;
    }
    final split = LocalEndpoint.split(
      endpointOrHost,
      defaultPort: LocalLlmPresets.defaultPort,
    );
    return split.port;
  }
}

/// ローカル LLM の既定値。
abstract final class LocalLlmPresets {
  static const defaultHost = 'http://127.0.0.1';
  static const defaultPort = 8080;
  static const defaultContextSize = 4096;

  /// S16 コーディング用の既定コンテキスト長（128k）。
  static const defaultCodingContextSize = 131072;

  /// モデル未選択時の表示。
  static const unsetModelLabel = '未設定（モデルを追加）';

  /// 選択肢。大きいほど KV キャッシュで RAM 増。Mac 余裕機向けに 32k〜256k を含む。
  static const contextSizeOptions = <int>[
    2048,
    4096,
    8192,
    16384,
    32768,
    65536,
    131072,
    262144,
  ];

  /// 互換エイリアス。
  static const defaultBaseUrl = 'http://127.0.0.1:8080';
}

/// @Deprecated 移行互換。新規は [LocalLlmConnectionSettings]。
typedef OllamaConnectionSettings = LocalLlmConnectionSettings;

/// @Deprecated 移行互換。
typedef OllamaModelPresets = LocalLlmPresets;
