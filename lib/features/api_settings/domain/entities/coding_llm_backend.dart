/// S16 Agent が使うローカル推論バックエンド。
enum CodingLlmBackend {
  /// llama.cpp（`llama-server`）。既定ポート 8080。
  llamaCpp,

  /// Strata（OpenAI 互換 API）。既定ポート 8090（llama と衝突しない）。
  strata;

  String get label => switch (this) {
        CodingLlmBackend.llamaCpp => 'llama.cpp',
        CodingLlmBackend.strata => 'Strata',
      };

  static CodingLlmBackend fromStorage(String? value) {
    if (value == 'strata') return CodingLlmBackend.strata;
    return CodingLlmBackend.llamaCpp;
  }

  String get storageValue => switch (this) {
        CodingLlmBackend.llamaCpp => 'llama_cpp',
        CodingLlmBackend.strata => 'strata',
      };
}
