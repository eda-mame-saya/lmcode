import 'coding_fence_parser.dart';
import 'coding_patch.dart';

/// 自動実行中に同じ実行が繰り返されたときの扱い。
enum CodingAutoLoopAction {
  /// 直前と違う。今回を記憶する。
  remember,

  /// 1回目。新規会話へ移して自動実行を続ける。
  relocate,

  /// 2回目。新規会話には移さず、この実行だけ止める。設定の自動実行は変えない。
  stopAuto,
}

/// 比較に使う実行。 [signature] が一致したら同じ実行。
class CodingAutoExecution {
  const CodingAutoExecution({required this.signature, required this.body});

  final String signature;

  /// 新規会話へ載せる本文（長いときは末尾を残して切る）。
  final String body;
}

class CodingAutoLoopObservation {
  const CodingAutoLoopObservation({
    required this.action,
    required this.memory,
    this.previous,
    this.current,
  });

  final CodingAutoLoopAction action;

  /// 次の比較に渡す記憶。繰り返しのときは今回を残し、次の同一実行を2回目にする。
  final CodingAutoExecution? memory;
  final CodingAutoExecution? previous;
  final CodingAutoExecution? current;
}

/// 自動実行の同一応答・同一検証ログの判定。副作用は持たない。
abstract final class CodingAutoLoop {
  /// 1回移したあとの再検知は止める。
  static const maxRelocations = 1;

  static const bodyMaxChars = 4000;

  static const _minProseChars = 80;

  static const _minCommandChars = 40;

  static CodingAutoLoopObservation observe({
    required int relocationsUsed,
    required CodingAutoExecution? previous,
    required CodingAutoExecution current,
    int maxRelocations = CodingAutoLoop.maxRelocations,
  }) {
    if (current.signature.isEmpty) {
      return CodingAutoLoopObservation(
        action: CodingAutoLoopAction.remember,
        memory: previous,
      );
    }
    if (previous != null && previous.signature == current.signature) {
      final repeated = relocationsUsed >= maxRelocations;
      return CodingAutoLoopObservation(
        action: repeated
            ? CodingAutoLoopAction.stopAuto
            : CodingAutoLoopAction.relocate,
        memory: current,
        previous: previous,
        current: current,
      );
    }
    return CodingAutoLoopObservation(
      action: CodingAutoLoopAction.remember,
      memory: current,
    );
  }

  /// パッチ、または十分な長さの説明がある回答。ツールだけの応答は null。
  static CodingAutoExecution? answerExecution({
    required String rawReply,
    required List<CodingToolCall> toolCalls,
    required List<CodingProposedPatch> patches,
    required String displayText,
    int minProseChars = _minProseChars,
    int bodyMaxChars = CodingAutoLoop.bodyMaxChars,
  }) {
    final prose = _prose(displayText);
    final boilerplate = _isBoilerplate(prose);
    if (patches.isEmpty && (boilerplate || prose.length < minProseChars)) {
      return null;
    }
    final tools = [
      for (final call in toolCalls) _toolSignature(call),
    ]..sort();
    final patchSigs = [
      for (final patch in patches) _patchSignature(patch),
    ]..sort();
    final proseSig = !boilerplate && prose.length >= minProseChars
        ? _loose(prose)
        : '';
    final signature = [
      if (tools.isNotEmpty) 'T:${tools.join('|')}',
      if (patchSigs.isNotEmpty) 'P:${patchSigs.join('|')}',
      if (proseSig.isNotEmpty) 'D:$proseSig',
    ].join('\n');
    if (signature.isEmpty) return null;
    return CodingAutoExecution(
      signature: signature,
      body: _clipTail(rawReply, bodyMaxChars),
    );
  }

  /// 失敗ログ。所要時間の差では別結果にしない。短いログは null。
  static CodingAutoExecution? failedCommandExecution({
    required String commandLabel,
    required String log,
    int minCommandChars = _minCommandChars,
    int bodyMaxChars = CodingAutoLoop.bodyMaxChars,
  }) {
    final normalized = _commandBody(log);
    if (normalized.length < minCommandChars) return null;
    final signature = '$commandLabel\n${_commandSignatureText(normalized)}';
    return CodingAutoExecution(
      signature: signature,
      body: _clipTail('$commandLabel\n$normalized', bodyMaxChars),
    );
  }

  static String _toolSignature(CodingToolCall call) {
    final keys = call.args.keys.toList()..sort();
    final parts = [
      for (final key in keys) '$key=${_loose('${call.args[key] ?? ''}')}',
    ];
    return '${call.name}(${parts.join(',')})';
  }

  static String _patchSignature(CodingProposedPatch patch) {
    final kind = patch.isAddFile ? 'add' : 'update';
    final path = patch.relativePath.replaceAll('\\', '/').trim();
    return '$kind:$path:${_loose(CodingFenceParser.proposalBody(patch))}';
  }

  static String _prose(String displayText) {
    final lines = _loose(displayText).split('\n');
    if (lines.isNotEmpty && lines.last.startsWith('（実行:')) {
      lines.removeLast();
    }
    return lines.join('\n').trim();
  }

  static bool _isBoilerplate(String prose) {
    const prefixes = [
      'ツールを実行します',
      'ファイル作成案を提案しました',
      '変更案を提案しました',
      '変更案とファイル作成案を提案しました',
      'ツール実行と変更案を準備しました',
      '（応答本文なし）',
    ];
    for (final prefix in prefixes) {
      if (prose == prefix || prose.startsWith('$prefix\n')) return true;
    }
    return false;
  }

  static String _commandBody(String log) {
    return _loose(log);
  }

  static String _commandSignatureText(String normalizedLog) {
    var text = normalizedLog;
    text = text.replaceAll(
      RegExp(r'\(ran in [^)]*\)', caseSensitive: false),
      '',
    );
    text = text.replaceAll(RegExp(r'\b\d+(\.\d+)?\s*(ms|s)\b'), '');
    text = text.replaceAll(RegExp(r'^\d+:\d+\s+', multiLine: true), '');
    return _loose(text);
  }

  static String _loose(String raw) {
    return raw
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map((line) => line.trimRight())
        .join('\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  static String _clipTail(String raw, int maxChars) {
    final text = _loose(raw);
    if (text.length <= maxChars) return text;
    return '…（先頭を省略）\n${text.substring(text.length - maxChars)}';
  }
}
