/// 生成AIプロバイダ（設定で切替）。
/// アルファ運用は [localLlm] のみ UI 表示。Gemini は事前圧縮等の残置。
enum GenerativeAiProvider {
  gemini,
  localLlm;

  String get label => switch (this) {
        GenerativeAiProvider.gemini => 'Gemini',
        GenerativeAiProvider.localLlm => 'llama.cpp（ローカル）',
      };

  static GenerativeAiProvider fromStorage(String? value) {
    if (value == 'gemini') return GenerativeAiProvider.gemini;
    // 旧 `ollama` キーもローカル LLM へ寄せる
    return GenerativeAiProvider.localLlm;
  }

  String get storageValue => name;
}
