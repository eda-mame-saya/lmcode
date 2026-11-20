import 'coding_flutter_verify_policy.dart';

final RegExp _analyzeErrorLine = RegExp(r'^\s*error\s+[•·-]\s+(.+)$');

/// 検証ログの最初のエラー 1 行。見つからなければ null。
///
/// `flutter analyze` の `error • メッセージ • path:行` と、
/// `flutter test` の `[E]`／`Error:`／`Some tests failed` を拾う。
String? codingVerifyFirstError(String log, {int maxChars = 160}) {
  for (final raw in log.split('\n')) {
    final line = raw.trimRight();
    if (line.isEmpty) continue;
    final analyze = _analyzeErrorLine.firstMatch(line);
    String? hit;
    if (analyze != null) {
      hit = analyze.group(1);
    } else if (line.contains('[E]') ||
        line.contains('Error:') ||
        line.contains('Some tests failed')) {
      hit = line.trim();
    }
    if (hit == null || hit.trim().isEmpty) continue;
    final text = hit.trim();
    return text.length <= maxChars ? text : '${text.substring(0, maxChars)}…';
  }
  return null;
}

/// 検証が止まったときの「次にやること」。
///
/// 止まった理由ごとの手当てを短い手順で返す。次の手段が無い理由
/// （Flutter 以外・成功）は空文字。副作用なし。
String codingVerifyNextStepsText({
  required CodingFlutterVerifyStopReason reason,
  required bool autoOn,
  required int maxSets,
  String? log,
  String? command,
}) {
  final steps = <String>[];
  final cmd = command == null || command.isEmpty ? '検証' : command;
  switch (reason) {
    case CodingFlutterVerifyStopReason.setsExhausted:
      steps
        ..add('上の最初のエラーだけに絞って、「このエラーだけを直して」と指示する')
        ..add('原因が分からないときは、＋の「エラーの再現」で再現テストから始める')
        ..add('手元で `flutter analyze`／`flutter test` を実行し、失敗の全体を確認する');
      if (maxSets < 4) {
        steps.add('もう一段試すなら、設定の運用パターンを「深掘り」にする（検証セットと読取が増える）');
      }
    case CodingFlutterVerifyStopReason.noUpdateApplied:
      steps
        ..add('Patch カードの理由（現状と合わない／既に存在する等）を確認する')
        ..add('対象ファイルを開いて取り込み直し、もう一度指示する')
        ..add('同じ内容で止まるときは、「新規」で会話を作り直す');
    case CodingFlutterVerifyStopReason.pendingAdd:
      steps
        ..add('Patch カードの「作成」を押す（作成先パスを確認する）')
        ..add('作成できないときは、別のディレクトリ付きパスで出し直すよう指示する');
    case CodingFlutterVerifyStopReason.timedOut:
      steps
        ..add('重いテストを避け、対象を絞って（例: 該当ファイルだけ）手元で実行する')
        ..add('毎回遅い場合は、設定のハーネス「詳細」で analyze／test のタイムアウトを延ばす');
    case CodingFlutterVerifyStopReason.launchFailed:
      steps
        ..add('ターミナルで `flutter --version` が動くか確認する')
        ..add('動かないときは、設定の Dart SDK パスを確認する')
        ..add('直ったら、＋の「テストを実行」でもう一度確認する');
    case CodingFlutterVerifyStopReason.verifyOnlyFailed:
      steps.add('失敗ログを貼り、＋の「エラー解析」で修正案を出させる');
      if (!autoOn) {
        steps.add('設定で自動実行を ON にすると、失敗時に自動修正まで進む');
      }
    case CodingFlutterVerifyStopReason.packageInstall:
      steps
        ..add('`pubspec.yaml` に必要なパッケージを追記し、`flutter pub get` を実行する')
        ..add('その後、＋の「テストを実行」で確認する');
    case CodingFlutterVerifyStopReason.notFlutter:
    case CodingFlutterVerifyStopReason.none:
      return '';
  }
  final first = log == null ? null : codingVerifyFirstError(log);
  final buf = StringBuffer('【次にやること】');
  if (first != null) {
    buf.write('\n最初のエラー（$cmd）: $first');
  }
  for (var i = 0; i < steps.length; i++) {
    buf.write('\n${i + 1}. ${steps[i]}');
  }
  return buf.toString();
}

/// 同じ実行の繰り返しで自動実行を止めたときの「次にやること」。
String codingRepeatedStopNextStepsText() {
  const steps = [
    '指示を具体的にする（対象ファイル・期待する結果・直したくない範囲）',
    '関係するファイルを取り込んでから送り直す',
    '同じ結果が続くときは、「新規」で会話を作り直すか、モデルを切り替える',
  ];
  final buf = StringBuffer('【次にやること】');
  for (var i = 0; i < steps.length; i++) {
    buf.write('\n${i + 1}. ${steps[i]}');
  }
  return buf.toString();
}
