import 'ami_voice_engine.dart';
import 'coding_llm_backend.dart';
import 'generative_ai_provider.dart';
import 'local_llm_connection_settings.dart';
import 'strata_connection_settings.dart';

/// AmiVoice 接続設定。
/// 新規追加：ドメインエンティティ
class AmiVoiceConnectionSettings {
  const AmiVoiceConnectionSettings({
    this.apiKey = '',
    this.engine = AmiVoiceEngine.general,
    this.noLog = true,
    this.resultUpdatedIntervalMs = 1000,
    this.keepFillerToken = false,
    this.companyName = '',
    this.departmentName = '',
    this.personName = '',
    this.useDiarizer = false,
  });

  final String apiKey;
  final AmiVoiceEngine engine;
  // 新規追加：true のとき nolog エンドポイントを使用
  final bool noLog;
  final int resultUpdatedIntervalMs;
  final bool keepFillerToken;

  /// 使用量タグ用：企業名。
  final String companyName;

  /// 使用量タグ用：部署名。
  final String departmentName;

  /// 使用量タグ用：氏名。
  final String personName;

  /// 話者ダイアライゼーション（`useDiarizer=1`）を有効にする。
  /// 会議画面のトグルから接続時に渡す（設定画面では永続化しない）。
  final bool useDiarizer;

  bool get isConfigured => apiKey.trim().isNotEmpty;

  /// 企業名・部署名・氏名を結合した billing_key。
  /// 空の項目は省略し、`_` で連結する。
  String get resolvedBillingKey {
    return [companyName, departmentName, personName]
        .map((part) => _sanitizeBillingPart(part.trim()))
        .where((part) => part.isNotEmpty)
        .join('_');
  }

  static String _sanitizeBillingPart(String value) {
    return value
        .replaceAll(RegExp(r'[\s"\\]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  AmiVoiceConnectionSettings copyWith({
    String? apiKey,
    AmiVoiceEngine? engine,
    bool? noLog,
    int? resultUpdatedIntervalMs,
    bool? keepFillerToken,
    String? companyName,
    String? departmentName,
    String? personName,
    bool? useDiarizer,
  }) {
    return AmiVoiceConnectionSettings(
      apiKey: apiKey ?? this.apiKey,
      engine: engine ?? this.engine,
      noLog: noLog ?? this.noLog,
      resultUpdatedIntervalMs:
          resultUpdatedIntervalMs ?? this.resultUpdatedIntervalMs,
      keepFillerToken: keepFillerToken ?? this.keepFillerToken,
      companyName: companyName ?? this.companyName,
      departmentName: departmentName ?? this.departmentName,
      personName: personName ?? this.personName,
      useDiarizer: useDiarizer ?? this.useDiarizer,
    );
  }
}

/// 生成AI（Gemini）接続設定。
/// 新規追加：ドメインエンティティ
class GeminiConnectionSettings {
  const GeminiConnectionSettings({
    this.apiKey = '',
    this.modelName = GeminiModelPresets.defaultModel,
    this.enabled = false,
  });

  final String apiKey;
  final String modelName;

  /// Gemini をアプリ機能で使うか（キー有無とは独立）。
  final bool enabled;

  /// APIキーとモデル名が入力済みか。
  bool get hasCredentials =>
      apiKey.trim().isNotEmpty && modelName.trim().isNotEmpty;

  /// キー入力済み（設定画面の「設定済」表示用）。
  bool get isConfigured => hasCredentials;

  /// 実際に Gemini API を呼び出してよいか。
  bool get isUsable => enabled && hasCredentials;

  GeminiConnectionSettings copyWith({
    String? apiKey,
    String? modelName,
    bool? enabled,
  }) {
    return GeminiConnectionSettings(
      apiKey: apiKey ?? this.apiKey,
      modelName: modelName ?? this.modelName,
      enabled: enabled ?? this.enabled,
    );
  }
}

/// STT + 生成AI（Gemini / ローカル LLM）の接続設定一式。
class ConnectionSettings {
  const ConnectionSettings({
    this.localLlm = const LocalLlmConnectionSettings(),
    this.strata = const StrataConnectionSettings(),
    this.codingBackend = CodingLlmBackend.llamaCpp,
    this.provider = GenerativeAiProvider.localLlm,
    this.dartSdkPath = '',
  });

  final LocalLlmConnectionSettings localLlm;

  /// Strata（既定ポート 8090）。llama（8080）と共存可。
  final StrataConnectionSettings strata;

  /// S16 Agent が使う推論バックエンド。
  final CodingLlmBackend codingBackend;

  final GenerativeAiProvider provider;

  /// S16 Dart 入力中補完用。空＝PATH から `dart` 探索（S11 §4.6）。
  final String dartSdkPath;

  /// Agent 送信用の OpenAI 互換設定（選択中バックエンド）。
  LocalLlmConnectionSettings agentChatSettings({String? strataModelId}) {
    return switch (codingBackend) {
      CodingLlmBackend.llamaCpp => localLlm.forServer(),
      CodingLlmBackend.strata => strata.toChatClientSettings(
          resolvedModelId: strataModelId,
        ),
    };
  }

  /// 選択中バックエンドが Agent 利用可能か。
  /// Strata は Agent 選択時に起動するため、enabled ではなく接続先の有無で判定する。
  bool get isAgentBackendUsable => switch (codingBackend) {
        CodingLlmBackend.llamaCpp => localLlm.isCodingUsable,
        CodingLlmBackend.strata => strata.hasEndpoint,
      };

  ConnectionSettings copyWith({
    LocalLlmConnectionSettings? localLlm,
    StrataConnectionSettings? strata,
    CodingLlmBackend? codingBackend,
    GenerativeAiProvider? provider,
    String? dartSdkPath,
  }) {
    return ConnectionSettings(
      localLlm: localLlm ?? this.localLlm,
      strata: strata ?? this.strata,
      codingBackend: codingBackend ?? this.codingBackend,
      provider: provider ?? this.provider,
      dartSdkPath: dartSdkPath ?? this.dartSdkPath,
    );
  }
}
