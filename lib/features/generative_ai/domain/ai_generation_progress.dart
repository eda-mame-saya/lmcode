/// 生成中の進捗（パーセントは Ollama 標準 API では取れない）。
/// 経過時間・出力文字数・部分テキスト・完了メトリクスで UI を埋める。
class AiGenerationProgress {
  const AiGenerationProgress({
    required this.phase,
    required this.elapsed,
    this.outputChars = 0,
    this.partialText = '',
    this.evalCount,
    this.promptEvalCount,
    this.tokensPerSecond,
    this.statusLabel,
  });

  final AiGenerationPhase phase;
  final Duration elapsed;
  final int outputChars;
  final String partialText;
  final int? evalCount;
  final int? promptEvalCount;
  final double? tokensPerSecond;
  final String? statusLabel;

  String get displayLabel {
    if (statusLabel != null && statusLabel!.trim().isNotEmpty) {
      return statusLabel!;
    }
    final sec = elapsed.inSeconds;
    return switch (phase) {
      AiGenerationPhase.connecting => '接続中…',
      AiGenerationPhase.waitingFirstToken => 'モデル準備・プロンプト処理中…（$sec秒）',
      AiGenerationPhase.generating =>
        '生成中…（$sec秒・約$outputChars文字）',
      AiGenerationPhase.done => () {
          final tps = tokensPerSecond;
          final eval = evalCount;
          if (tps != null && eval != null) {
            return '完了（$sec秒・$evalトークン・${tps.toStringAsFixed(1)} tok/s）';
          }
          return '完了（$sec秒）';
        }(),
      AiGenerationPhase.failed => '失敗（$sec秒）',
    };
  }
}

enum AiGenerationPhase {
  connecting,
  waitingFirstToken,
  generating,
  done,
  failed,
}
