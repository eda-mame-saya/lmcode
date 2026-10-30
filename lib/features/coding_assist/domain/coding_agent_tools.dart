import 'dart:io';

import 'package:path/path.dart' as p;

import 'coding_generation_repeat.dart';
import 'coding_path_resolver.dart';
import 'coding_prompt_action.dart';
import 'coding_symbol_format.dart';
import 'coding_symbol_index.dart';
import 'coding_text_file.dart';
import 'coding_workspace_scan.dart';

/// 検査文に添える依頼文の最大文字数。
const codingFixedPromptRequestChars = 400;

/// 上限後の検査・再指示で、完了の形を一つに決める。
///
/// 優先はタスク評価、次いでタスク分解、次いで Patch（ソース／文書の出力・エラー解析）、次いでプログラム分析。
/// 簡潔はどれにも重ねる。テンプレ全文は再送しない。
String codingFixedPromptCompletion(List<CodingPromptAction> actions) {
  final set = actions.toSet();
  final buf = StringBuffer();
  if (set.contains(CodingPromptAction.taskEvaluate)) {
    buf.write(
      '「判定: 要修正」または「判定: このまま」を書いてください。'
      '指摘を1行以上書いてください。'
      'Begin/End Patch は禁止です。',
    );
  } else if (set.contains(CodingPromptAction.taskDecompose)) {
    buf.write(
      '最初に「目的:」で、何を達成するタスクかを1〜2文書いてください。'
      'そのあと番号付きの実行タスクを出してください。'
      '各行は「（新規|既存）相対パス — 何をするか」です。'
      'Begin/End Patch は禁止です。',
    );
  } else if (_wantsPatch(set)) {
    final update =
        set.contains(CodingPromptAction.expectFixProposal) ||
        set.contains(CodingPromptAction.errorAnalyze) ||
        set.contains(CodingPromptAction.expectDocumentEdit);
    final add =
        set.contains(CodingPromptAction.expectFileOutput) ||
        set.contains(CodingPromptAction.expectDocumentCreate);
    if (update && add) {
      buf.write(
        '既に読んだ本文で Begin/End Patch を出してください。'
        '既存の修正は Update File、新規ファイルは Add File です。'
        'Add File のパスはディレクトリ付きです。ファイル名だけは不可です。',
      );
    } else if (add) {
      buf.write(
        '既に読んだ本文で Begin/End Patch を出してください。'
        '新規は Add File です。パスはディレクトリ付きの相対パスです。ファイル名だけは不可です。',
      );
    } else {
      buf.write('既に読んだ本文で Begin/End Patch を出してください。既存の修正は Update File です。');
    }
    if (CodingPromptAction.skipsFlutterVerify(actions)) {
      buf.write('文書だけです。ソース、テスト、Dart は出さないでください。');
    }
  } else if (set.contains(CodingPromptAction.programAnalyze)) {
    buf.write('説明だけを書いてください。Begin/End Patch は禁止です。');
  } else {
    buf.write('持っている内容で、この依頼を完了してください。');
  }
  if (set.contains(CodingPromptAction.concise)) {
    buf.write('回答は短く簡潔に。');
  }
  return buf.toString();
}

/// タスク評価・タスク分解・Patch・プログラム分析のいずれかが付き、完了の形が一つに決まっている。
bool codingFixedPromptHasCompletionShape(List<CodingPromptAction> actions) {
  final set = actions.toSet();
  return set.contains(CodingPromptAction.taskEvaluate) ||
      set.contains(CodingPromptAction.taskDecompose) ||
      _wantsPatch(set) ||
      set.contains(CodingPromptAction.programAnalyze);
}

bool _wantsPatch(Set<CodingPromptAction> actions) {
  return actions.contains(CodingPromptAction.expectFixProposal) ||
      actions.contains(CodingPromptAction.expectFileOutput) ||
      actions.contains(CodingPromptAction.expectDocumentCreate) ||
      actions.contains(CodingPromptAction.expectDocumentEdit) ||
      actions.contains(CodingPromptAction.errorAnalyze);
}

/// 固定プロンプトが求める成果物が応答に無いか。
/// 形を決めない送信では false（読み取り続行の判定は別）。
/// パッチを求める＋は、Begin と End と Update／Add が揃って初めて成果物とみなす。
bool codingReplyMissesFixedPrompt(
  String reply,
  List<CodingPromptAction> actions,
) {
  final set = actions.toSet();
  final text = reply.trim();
  if (set.contains(CodingPromptAction.taskEvaluate)) {
    return !RegExp(r'判定\s*[:：]\s*(?:要修正|このまま)').hasMatch(text);
  }
  if (set.contains(CodingPromptAction.taskDecompose)) {
    final hasPurpose = RegExp(r'目的\s*[:：]').hasMatch(text);
    final hasTask = RegExp(
      r'^\s*\d+\.\s*（(?:新規|既存)）',
      multiLine: true,
    ).hasMatch(text);
    return !hasPurpose || !hasTask;
  }
  if (_wantsPatch(set)) {
    final closed =
        text.contains('*** Begin Patch') && text.contains('*** End Patch');
    final hasFile =
        text.contains('*** Update File') || text.contains('*** Add File');
    return !closed || !hasFile;
  }
  return false;
}

/// Begin の数が End より多い。パーサは End の無い Patch をカードにしない。
bool codingReplyHasUnclosedPatch(String reply) {
  final begin = '*** Begin Patch'.allMatches(reply).length;
  final end = '*** End Patch'.allMatches(reply).length;
  return begin > end;
}

/// 説明だけの＋は、閉じ忘れの Patch を完成させない。
bool codingMayRetryUnclosedPatch(List<CodingPromptAction> actions) {
  final set = actions.toSet();
  if (set.contains(CodingPromptAction.taskDecompose)) return false;
  if (set.contains(CodingPromptAction.taskEvaluate)) return false;
  if (set.contains(CodingPromptAction.programAnalyze) && !_wantsPatch(set)) {
    return false;
  }
  return true;
}

/// End が無くカードが 0 件のとき、読み取りなしで 1 回だけ書き直させる。
String codingUnclosedPatchCloseMessage({
  String requestText = '',
  List<CodingPromptAction> fixedPrompts = const [],
}) {
  final buf = StringBuffer()
    ..writeln('【アプリ】')
    ..writeln('*** Begin Patch はありましたが *** End Patch が無いため、カードは0件です。')
    ..writeln('read_file・list_dir・grep・不足: は書かない。')
    ..writeln('同じ修正を *** Begin Patch から *** End Patch まで書き直してください。')
    ..writeln('完了の形に従う。')
    ..writeln(codingFixedPromptCompletion(fixedPrompts));
  _writeRequestAndPromptLabels(
    buf,
    requestText: requestText,
    fixedPrompts: fixedPrompts,
  );
  return buf.toString().trimRight();
}

String _clipFixedPromptRequest(String raw) {
  final one = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (one.isEmpty) return '';
  if (one.length <= codingFixedPromptRequestChars) return one;
  return '${one.substring(0, codingFixedPromptRequestChars)}…';
}

void _writeRequestAndPromptLabels(
  StringBuffer buf, {
  required String requestText,
  required List<CodingPromptAction> fixedPrompts,
}) {
  final request = _clipFixedPromptRequest(requestText);
  if (request.isNotEmpty) {
    buf
      ..writeln('【依頼】')
      ..writeln(request);
  }
  const shown = [
    CodingPromptAction.taskDecompose,
    CodingPromptAction.taskEvaluate,
    CodingPromptAction.expectFixProposal,
    CodingPromptAction.expectFileOutput,
    CodingPromptAction.expectDocumentEdit,
    CodingPromptAction.expectDocumentCreate,
    CodingPromptAction.errorAnalyze,
    CodingPromptAction.programAnalyze,
    CodingPromptAction.concise,
  ];
  final labels = [
    for (final action in shown)
      if (fixedPrompts.contains(action)) action.menuLabel,
  ];
  if (labels.isNotEmpty) {
    buf
      ..writeln('【固定プロンプト】')
      ..writeln(labels.join('、'));
  }
}

/// 自動実行が読み取り上限に達したとき、既読パスと完了の形を Agent に返す文。
String codingReadStepLimitCheckMessage(
  Iterable<String> readPaths, {
  String requestText = '',
  List<CodingPromptAction> fixedPrompts = const [],
  bool forbidReadFile = false,
}) {
  final paths =
      readPaths
          .map((path) => path.trim().replaceAll('\\', '/'))
          .where((path) => path.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
  final buf = StringBuffer()
    ..writeln('【アプリの検査】')
    ..writeln('読み取りが上限に達したため、アプリがこのターンの read_file を検査しました。');
  if (paths.isEmpty) {
    buf.writeln('成功した read_file はありません。');
  } else {
    buf
      ..writeln('次のパスは既に読んであります。本文はこれまでのツール結果にあります。')
      ..writeln(paths.map((path) => '- $path').join('\n'));
  }
  buf.writeln(
    forbidReadFile
        ? 'read_file・list_dir・grep・不足: は書かない。'
              '行番号は【既読の本文】の1行目から数える。'
              '完了の形に従う。'
        : 'これらのパスは read_file しない。'
              'まだ開いていないパスが必要なら、そのパスだけ read_file する。'
              '足りているなら完了の形に従う。',
  );
  _writeRequestAndPromptLabels(
    buf,
    requestText: requestText,
    fixedPrompts: fixedPrompts,
  );
  buf
    ..writeln('【完了の形】')
    ..writeln(codingFixedPromptCompletion(fixedPrompts));
  return buf.toString().trimRight();
}

/// 検査のあと、成果物が無いときの再指示。
///
/// [allowUnreadReads] が false のときは、未着手の `read_file` も許さない。
String codingReadStepLimitRetryMessage({
  String requestText = '',
  Iterable<String> alreadyRead = const [],
  List<CodingPromptAction> fixedPrompts = const [],
  bool allowUnreadReads = true,
}) {
  final buf = StringBuffer()
    ..writeln('【アプリの検査・再指示】')
    ..writeln('直前のツール呼び出しは破棄した。');
  if (!allowUnreadReads) {
    final read = _sortedPaths(alreadyRead);
    if (read.isEmpty) {
      buf.writeln('read_file・list_dir・grep・不足: は書かない。');
    } else {
      buf
        ..writeln('次のファイルはもう読んである。read_file・list_dir・grep・不足: は書かない。')
        ..writeln(read.map((path) => '- $path').join('\n'));
    }
    buf
      ..writeln('行番号は上の【既読の本文】の1行目から数える。')
      ..writeln('完了の形に従う。')
      ..writeln(codingFixedPromptCompletion(fixedPrompts));
  } else {
    buf.writeln(
      codingReadBatchReport(
        alreadyRead,
        completion: codingFixedPromptCompletion(fixedPrompts),
      ),
    );
  }
  _writeRequestAndPromptLabels(
    buf,
    requestText: requestText,
    fixedPrompts: fixedPrompts,
  );
  return buf.toString().trimRight();
}

/// パッチもタスクリストもなく、読み取りの続行だけを書いている応答か。
bool codingReplyStillRequestsReads(String reply) {
  final text = reply.trim();
  if (text.isEmpty) return false;
  if (text.contains('*** Begin Patch') ||
      text.contains('*** Update File') ||
      text.contains('*** Add File')) {
    return false;
  }
  if (RegExp(r'^\s*\d+\.\s*（(?:新規|既存)）', multiLine: true).hasMatch(text)) {
    return false;
  }
  return text.contains('read_file') || text.contains('ファイルを読');
}

/// 自動実行 ON の system 末尾。人が渡した本文で Patch を書き、`read_file` は出さない。
const codingAutoExecuteNoReadFileSuffix = '''
【自動実行】read_file は出さない。本文は人が添付したファイルか、アプリが開いて渡した本文だけを使う。行番号はその本文の1行目から数える。
足りないファイルはツールにせず、次の形だけを書く:
不足:
相対/パス.dart
アプリは有効なパスをこのターンで1回だけ開く。開いたあとは完了の形を書く。list_dir と grep で本文の代わりにしない。
''';

/// 自動実行で実行しなかった `read_file`。本文ではないので検査の既読には戻さない。
String codingAutoExecuteReadFileRefused(String path) {
  final rel = path.trim().replaceAll('\\', '/');
  final label = rel.isEmpty ? '(path 空)' : rel;
  return '$label\n---\nこのファイルは開いていません。自動実行中は read_file を実行しません。';
}

final RegExp _codingMissingPathHeader = RegExp(r'^不足:\s*$', multiLine: true);

/// 自動実行でアプリが開く候補。`read_file` の path と、`不足:` の直後の相対パス。
List<String> codingAutoExecuteNamedPaths({
  required Iterable<({String name, String path})> toolCalls,
  required String replyText,
}) {
  final out = <String>[];
  void add(String raw) {
    var path = raw.trim().replaceAll('\\', '/');
    if (path.startsWith('./')) path = path.substring(2);
    if (path.isEmpty || path.startsWith('/') || path.contains('..')) return;
    if (path.contains(' ') || path.contains('`')) return;
    if (!path.contains('/') && !path.contains('.')) return;
    if (out.contains(path)) return;
    out.add(path);
  }

  for (final call in toolCalls) {
    if (call.name == 'read_file') add(call.path);
  }
  final marker = _codingMissingPathHeader.firstMatch(replyText);
  if (marker != null) {
    final rest = replyText.substring(marker.end);
    for (final line in rest.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith('```') ||
          trimmed.startsWith('***') ||
          trimmed.startsWith('【')) {
        break;
      }
      final path = trimmed.startsWith('- ')
          ? trimmed.substring(2).trim()
          : trimmed;
      if (path.contains(' ') || (!path.contains('/') && !path.contains('.'))) {
        break;
      }
      add(path);
    }
  }
  return List<String>.unmodifiable(out);
}

/// `不足:` のうち、この周期で開いた、または開けなかったパスを除いたもの。
List<String> codingFreshShortagePaths({
  required Iterable<String> named,
  required Set<String> opened,
  required Set<String> unopened,
}) {
  final out = <String>[];
  for (final raw in named) {
    final path = raw.trim().replaceAll('\\', '/');
    if (path.isEmpty || opened.contains(path) || unopened.contains(path)) {
      continue;
    }
    if (out.contains(path)) continue;
    out.add(path);
  }
  return out;
}

/// 検査 API の末尾に足す、チャットへは出さないファイル本文。
String codingSuppliedFileBodies(List<({String path, String body})> reads) {
  final buf = StringBuffer()
    ..writeln('【既読の本文】')
    ..writeln('次が渡された本文です。read_file は出さない。行番号はこの本文の1行目から数える。')
    ..writeln('不足: は書かない。渡したファイルだけを直す。一覧に無いパスは書かない。')
    ..writeln();
  for (final read in reads) {
    buf
      ..writeln('【ファイル: ${read.path}】')
      ..writeln(read.body.trimRight())
      ..writeln();
  }
  return buf.toString().trimRight();
}

/// 検査のあと、未着手の `read_file` を開いて検査 API を続けてよい回数。
const codingPostInspectUnreadRounds = 2;

/// 検査・再指示の system に足す。既読の読み直しだけを禁じ、未着手のパスは読む。
const codingDeliverableSystemSuffix =
    '【この送信】一覧の既読パスは read_file しない。'
    'まだ開いていないパスが必要なら、そのパスだけ read_file する。'
    '足りているなら完了の形だけを書く。';

/// 本文を渡したあとの検査・再指示。開く前の `不足:` の型を取り消す。
const codingDeliverableCloseSystemSuffix =
    '【この送信】行番号は read_file ではなく、上の【既読の本文】の1行目から数える。'
    '不足:・read_file・list_dir・grep は書かない。完了の形だけを書く。';

/// 渡した本文のあとに、まだ `不足:` や読み取りを求めている応答か。
///
/// 完了の形がある応答は false。固定プロンプトが無い平文で、開き直しも無い応答も false。
bool codingSuppliedReplyNeedsClose({
  required String reply,
  required Iterable<({String name, String path})> toolCalls,
  required List<CodingPromptAction> fixedPrompts,
}) {
  if (codingReplyWasRepeatDiscard(reply)) return false;
  final calls = toolCalls.toList();
  if (codingFixedPromptHasCompletionShape(fixedPrompts) &&
      !codingReplyMissesFixedPrompt(reply, fixedPrompts)) {
    return false;
  }
  final asksOpen = codingAutoExecuteNamedPaths(
    toolCalls: calls,
    replyText: reply,
  ).isNotEmpty;
  final stillReads =
      codingReplyStillRequestsReads(reply) ||
      codingToolCallsRequestWorkspaceReads(calls);
  if (!codingFixedPromptHasCompletionShape(fixedPrompts) &&
      calls.isEmpty &&
      !stillReads &&
      !asksOpen) {
    return false;
  }
  return true;
}

/// 既読パスへの `不足:` を破棄したあとの再指示。開かない。
String codingAlreadySuppliedCloseMessage({
  String requestText = '',
  Iterable<String> alreadyRead = const [],
  List<CodingPromptAction> fixedPrompts = const [],
}) {
  final buf = StringBuffer()
    ..writeln('【アプリの検査・再指示】')
    ..writeln('直前の不足: と read_file は破棄した。開かない。')
    ..writeln('パスは上の【既読の本文】にある。行番号はその本文の1行目から数える。');
  final read = _sortedPaths(alreadyRead);
  if (read.isNotEmpty) {
    buf.writeln(read.map((path) => '- $path').join('\n'));
  }
  buf
    ..writeln('read_file・list_dir・grep・不足: は書かない。')
    ..writeln('完了の形に従う。')
    ..writeln(codingFixedPromptCompletion(fixedPrompts));
  _writeRequestAndPromptLabels(
    buf,
    requestText: requestText,
    fixedPrompts: fixedPrompts,
  );
  return buf.toString().trimRight();
}

/// 検査のあと、未着手の `read_file` をまだ開いてよいか。
bool codingPostInspectMayOpenUnread({
  required int roundsOpened,
  required bool hasUnopenedRead,
}) {
  return hasUnopenedRead && roundsOpened < codingPostInspectUnreadRounds;
}

/// ツール呼び出しが、既読パスへの `read_file` だけか。
bool codingToolCallsAreRepeatReads(
  Iterable<({String name, String path})> calls, {
  required bool Function(String path) alreadyRead,
}) {
  final list = calls.toList();
  if (list.isEmpty) return false;
  for (final call in list) {
    if (call.name != 'read_file') return false;
    final path = call.path.trim();
    if (path.isEmpty || !alreadyRead(path)) return false;
  }
  return true;
}

/// `read_file`・`list_dir`・`grep` が1件でもあるか。
bool codingToolCallsRequestWorkspaceReads(
  Iterable<({String name, String path})> calls,
) {
  for (final call in calls) {
    if (call.name == 'read_file' ||
        call.name == 'list_dir' ||
        call.name == 'grep') {
      return true;
    }
  }
  return false;
}

/// 1回のモデル応答で新たに開く `read_file` の件数。既読の再指定は数えない。
const codingReadFilesPerBatch = 5;

/// 既読パスだけの `read_file` がこの回数続いたら、残りステップを使わず検査へ入る。
const codingRepeatReadStreakLimit = 2;

/// 既読だけの `read_file` が続いた回数。別のツールが混ざったら 0 に戻す。
int codingAdvanceRepeatReadStreak(int current, {required bool repeatOnly}) {
  if (!repeatOnly) return 0;
  final next = current < 0 ? 0 : current;
  return next + 1;
}

/// [codingAdvanceRepeatReadStreak] が検査へ入る回数に達したか。
bool codingRepeatReadStreakReached(int streak) =>
    streak >= codingRepeatReadStreakLimit;

/// 同一ターンで成功済みの `read_file` を、もう一度開かずに返す文。
String codingAlreadyReadFileMessage(String relativePath) =>
    '$relativePath はこのターンで既に読みました。'
    '本文はこれまでの結果にあります。このファイルは開いていません。';

/// 送信文の `【開いているファイル】` にあるパス。ディスクは開かない。
String codingAttachedFileReadRefused(String relativePath) =>
    '$relativePath は送信時に添付済みです。'
    '本文は【開いているファイル】にあります。このファイルは開いていません。';

/// このバッチの5件に入らなかった新規 `read_file`。
String codingReadBatchDeferredMessage(String relativePath) =>
    '$relativePath はこのバッチの read_file $codingReadFilesPerBatch件に入らなかったため、開いていません。'
    '次の応答で読み直せます。';

/// バッチのあと、既読と未読を伝える文。
///
/// このバッチで開かなかったパスがあるときだけ、そのパスの `read_file` を指示する。
/// 開き終えたあとは既読を読ませず、まだ開いていない別パスは [completion] の前に許す。
String codingReadBatchReport(
  Iterable<String> alreadyRead, {
  Iterable<String> deferred = const [],
  String completion = '',
}) {
  final read = _sortedPaths(alreadyRead);
  final later = _sortedPaths(deferred);
  final buf = StringBuffer()..writeln('【読み取りの報告】');
  if (read.isEmpty) {
    buf.writeln('このターンで開けた read_file はまだありません。');
  } else {
    buf
      ..writeln('次のファイルはもう読んである。既読のパスは read_file しない。')
      ..writeln(read.map((path) => '- $path').join('\n'));
  }
  if (later.isNotEmpty) {
    buf
      ..writeln('このバッチでは開かなかった。次の未読だけ read_file する。')
      ..writeln(later.map((path) => '- $path').join('\n'))
      ..writeln('上の未読を読んで、指示を続行してください。');
    return buf.toString().trimRight();
  }
  buf.writeln(
    'このバッチで指定された新規の read_file は開き終えた。'
    'まだ開いていない別のパスが必要なら、そのパスだけ read_file する。',
  );
  final done = completion.trim();
  if (done.isNotEmpty) {
    buf
      ..writeln('足りているなら、次に従う。')
      ..writeln(done);
  } else {
    buf.writeln('足りているなら、持っている本文で指示を完了してください。');
  }
  return buf.toString().trimRight();
}

List<String> _sortedPaths(Iterable<String> paths) {
  final unique =
      paths
          .map((path) => path.trim().replaceAll('\\', '/'))
          .where((path) => path.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
  return unique;
}

/// ワークスペース内ツール実行（パッチ適用は別）。
/// インスタンスは Agent 1ターンにつき1つ。成功した `read_file` のパスはその間だけ覚える。
final class CodingAgentTools {
  CodingAgentTools(
    this.rootPath, {
    this.indexedFiles = const [],
    this.indexedDirectories = const [],
    this.rootLabel,
    this.openBuffers = const {},
    this.symbols,
    int? readCharLimit,
    int? grepHitLimit,
    int? listEntryLimit,
    int? pathCandidateLimit,
    int? readFailureLimit,
  }) : readCharLimit = readCharLimit ?? maxReadChars,
       grepHitLimit = grepHitLimit ?? maxGrepHits,
       listEntryLimit = listEntryLimit ?? maxListEntries,
       pathCandidateLimit =
           pathCandidateLimit ?? CodingPathResolver.maxCandidates,
       readFailureLimit = readFailureLimit ?? 3;

  final String rootPath;
  final List<String> indexedFiles;
  final List<String> indexedDirectories;
  final String? rootLabel;
  final Map<String, String> openBuffers;
  final CodingSymbolIndex? symbols;
  final int readCharLimit;
  final int grepHitLimit;
  final int listEntryLimit;
  final int pathCandidateLimit;
  final int readFailureLimit;
  final Map<String, int> _readFailures = {};

  /// このターンで本文を返せた相対パス。失敗したパスは入れない。
  final Set<String> _readThisTurn = {};

  /// 送信文に本文があるパス。`read_file` では開かない。
  final Set<String> _suppliedThisTurn = {};

  Set<String> get readPathsThisTurn => Set.unmodifiable(_readThisTurn);

  /// このターンで本文を渡せたパス。ディスクは開かない。
  void noteSuccessfulRead(String path) {
    final norm = normalizePathInput(path.trim()).replaceAll('\\', '/');
    if (norm.isEmpty) return;
    _readThisTurn.add(norm);
  }

  /// フォルダ一括取り込みなど、送信文へ載せた相対パスをこのターンの既添付にする。
  void noteSuppliedPaths(Iterable<String> paths) {
    for (final raw in paths) {
      final norm = normalizePathInput(raw.trim()).replaceAll('\\', '/');
      if (norm.isEmpty) continue;
      _suppliedThisTurn.add(norm);
    }
  }

  /// [raw] が送信文の添付なら、その正規化パス。無ければ null。
  String? suppliedKey(String raw) {
    final norm = normalizePathInput(raw.trim()).replaceAll('\\', '/');
    if (norm.isEmpty) return null;
    if (_suppliedThisTurn.contains(norm)) return norm;
    final soft = CodingPathResolver.softMatchFile(
      norm,
      _suppliedThisTurn.toList(),
    );
    if (soft == null) return null;
    final key = soft.replaceAll('\\', '/');
    return _suppliedThisTurn.contains(key) ? key : null;
  }

  /// [raw] が、このターンで本文を返せたパスか、送信文に添付済みか。
  bool hasReadPath(String raw) {
    if (suppliedKey(raw) != null) return true;
    final norm = normalizePathInput(raw.trim()).replaceAll('\\', '/');
    if (norm.isEmpty) return false;
    if (_readThisTurn.contains(norm)) return true;
    final soft = CodingPathResolver.softMatchFile(norm, indexedFiles);
    if (soft == null) return false;
    return _readThisTurn.contains(soft.replaceAll('\\', '/'));
  }

  static const maxReadChars = 80000;
  static const maxGrepHits = 40;
  static const maxListEntries = 200;

  String get _label => (rootLabel != null && rootLabel!.isNotEmpty)
      ? rootLabel!
      : p.basename(rootPath);

  /// 正規化後の相対パスを絶対パスへ（WS 外は例外）。
  String resolve(String relativePath) {
    final normalized = relativePath.replaceAll('\\', '/');
    if (normalized.startsWith('..') ||
        normalized == '..' ||
        p.isAbsolute(normalized)) {
      throw StateError('ワークスペース外のパスは読めません: $relativePath');
    }
    final abs = p.normalize(p.join(rootPath, normalized));
    final root = p.normalize(rootPath);
    if (abs != root && !p.isWithin(root, abs)) {
      throw StateError('ワークスペース外のパスは読めません: $relativePath');
    }
    return abs;
  }

  String normalizePathInput(String raw) {
    return CodingPathResolver.normalizeInput(
      raw,
      rootPath: rootPath,
      rootLabel: _label,
      indexedFiles: indexedFiles,
      indexedDirectories: indexedDirectories,
    );
  }

  Future<String> listDir(String relativePath) async {
    try {
      final raw = relativePath.trim();
      if (raw.isEmpty) {
        return _listAbs(rootPath);
      }
      final norm = normalizePathInput(raw);
      var resolvedRel = norm;
      final absTry = resolve(norm);
      if (!await Directory(absTry).exists()) {
        final soft = CodingPathResolver.softMatchDir(
          norm,
          indexedDirectories,
          indexedFiles,
        );
        if (soft != null) {
          resolvedRel = soft;
        }
      }
      final abs = resolvedRel.isEmpty ? rootPath : resolve(resolvedRel);
      final dir = Directory(abs);
      if (!await dir.exists()) {
        final candidates = CodingPathResolver.suggestCandidates(
          query: norm,
          indexedFiles: indexedFiles,
          indexedDirs: indexedDirectories,
          limit: pathCandidateLimit,
        );
        return CodingPathResolver.formatNotFound(
          kind: 'ディレクトリ',
          requested: raw,
          candidates: candidates,
        );
      }
      return _listAbs(abs);
    } on StateError catch (e) {
      return e.message;
    }
  }

  Future<String> _listAbs(String abs) async {
    final dir = Directory(abs);
    final entries = <String>[];
    await for (final entity in dir.list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (entity is Directory) {
        if (CodingWorkspaceScan.isExcludedDirName(name)) continue;
        entries.add('$name/');
      } else if (entity is File) {
        if (!CodingWorkspaceScan.isTextFile(entity.path)) continue;
        entries.add(name);
      }
      if (entries.length >= listEntryLimit) {
        entries.add('…');
        break;
      }
    }
    entries.sort();
    return entries.isEmpty ? '(空)' : entries.join('\n');
  }

  Future<String> readFile(String relativePath) async {
    try {
      final raw = relativePath.trim();
      if (raw.isEmpty) return 'path が空です';
      final norm = normalizePathInput(raw);
      if (norm.isEmpty) return 'path が空です';
      final supplied = suppliedKey(raw);
      if (supplied != null) return codingAttachedFileReadRefused(supplied);

      var rel = norm;
      final absExact = resolve(rel);
      if (!await File(absExact).exists()) {
        final soft = CodingPathResolver.softMatchFile(norm, indexedFiles);
        if (soft != null) {
          rel = soft;
        }
      }

      final abs = resolve(rel);
      final file = File(abs);
      final key = rel.replaceAll('\\', '/');
      if (_readThisTurn.contains(key)) {
        return codingAlreadyReadFileMessage(key);
      }
      if ((_readFailures[key] ?? 0) >= readFailureLimit) {
        return '$key は連続 $readFailureLimit 回失敗したため、このターンでは再試行しません。';
      }
      if (!await file.exists()) {
        _readFailures[key] = (_readFailures[key] ?? 0) + 1;
        final candidates = CodingPathResolver.suggestCandidates(
          query: norm,
          indexedFiles: indexedFiles,
          indexedDirs: indexedDirectories,
          limit: pathCandidateLimit,
        );
        return CodingPathResolver.formatNotFound(
          kind: 'ファイル',
          requested: raw,
          candidates: candidates,
        );
      }

      var text = await CodingTextFile.read(file);
      var truncated = false;
      if (text.length > readCharLimit) {
        text = text.substring(0, readCharLimit);
        truncated = true;
      }
      final note = rel != norm ? '（パス補正: $raw → $rel）\n' : '';
      final body = truncated ? '$text\n…（先頭 $readCharLimit 文字まで）' : text;
      _readFailures.remove(key);
      _readThisTurn.add(key);
      return '$note$body';
    } on StateError catch (e) {
      return e.message;
    }
  }

  Future<String> grep({
    required String pattern,
    String path = '',
    bool regex = false,
  }) async {
    try {
      final RegExp re;
      try {
        re = regex ? RegExp(pattern) : RegExp(RegExp.escape(pattern));
      } catch (e) {
        return '正規表現が不正です: $e';
      }

      final hits = <String>[];
      final rawPath = path.trim();

      Future<void> scanFile(File entity) async {
        if (hits.length >= grepHitLimit) return;
        if (!CodingWorkspaceScan.isTextFile(entity.path)) return;
        String content;
        try {
          content = await CodingTextFile.read(entity);
        } catch (_) {
          return;
        }
        final rel = p
            .relative(entity.path, from: rootPath)
            .replaceAll('\\', '/');
        final lines = content.split('\n');
        for (var i = 0; i < lines.length; i++) {
          if (re.hasMatch(lines[i])) {
            hits.add('$rel:${i + 1}:${lines[i]}');
            if (hits.length >= grepHitLimit) break;
          }
        }
      }

      Future<void> walk(Directory dir) async {
        if (hits.length >= grepHitLimit) return;
        await for (final entity in dir.list(followLinks: false)) {
          if (hits.length >= grepHitLimit) return;
          final name = p.basename(entity.path);
          if (entity is Directory) {
            if (CodingWorkspaceScan.isExcludedDirName(name)) continue;
            await walk(entity);
          } else if (entity is File) {
            await scanFile(entity);
          }
        }
      }

      if (rawPath.isEmpty) {
        await walk(Directory(rootPath));
      } else {
        final norm = normalizePathInput(rawPath);
        var rel = norm;
        var abs = resolve(rel);
        final asFile = File(abs);
        final asDir = Directory(abs);

        if (!await asFile.exists() && !await asDir.exists()) {
          final softFile = CodingPathResolver.softMatchFile(norm, indexedFiles);
          final softDir = CodingPathResolver.softMatchDir(
            norm,
            indexedDirectories,
            indexedFiles,
          );
          if (softFile != null) {
            rel = softFile;
            abs = resolve(rel);
          } else if (softDir != null) {
            rel = softDir;
            abs = rel.isEmpty ? rootPath : resolve(rel);
          }
        }

        final file = File(abs);
        final dir = Directory(abs);
        if (await file.exists()) {
          await scanFile(file);
        } else if (await dir.exists()) {
          await walk(dir);
        } else {
          final candidates = CodingPathResolver.suggestCandidates(
            query: norm,
            indexedFiles: indexedFiles,
            indexedDirs: indexedDirectories,
            limit: pathCandidateLimit,
          );
          return CodingPathResolver.formatNotFound(
            kind: 'パス',
            requested: rawPath,
            candidates: candidates,
          );
        }
      }

      if (hits.isEmpty) {
        final mode = regex ? 'regex' : 'literal';
        return 'ヒットなし（$mode: $pattern）';
      }
      final more = hits.length >= grepHitLimit ? '\n…（上限 $grepHitLimit）' : '';
      return '${hits.join('\n')}$more';
    } on StateError catch (e) {
      return e.message;
    }
  }

  Future<String> execute(String name, Map<String, dynamic> args) async {
    switch (name) {
      case 'list_dir':
        return listDir('${args['path'] ?? ''}');
      case 'read_file':
        final path = '${args['path'] ?? ''}'.trim();
        if (path.isEmpty) return 'path が空です';
        return readFile(path);
      case 'grep':
        final pattern = '${args['pattern'] ?? ''}'.trim();
        if (pattern.isEmpty) return 'pattern が空です';
        return grep(
          pattern: pattern,
          path: '${args['path'] ?? ''}',
          regex: _truthy(args['regex']) || _truthy(args['is_regex']),
        );
      case 'file_outline':
        return _symbolFile('${args['path'] ?? ''}', (rel, buffer) {
          return symbols!.fileOutline(relativePath: rel, bufferText: buffer);
        });
      case 'workspace_symbol':
        return _workspaceSymbol(args);
      case 'go_to_definition':
        return _symbolAt('go_to_definition', args);
      case 'find_references':
        return _symbolAt('find_references', args);
      case 'propose_patch':
        return 'propose_patch は応答内の Begin/End Patch で提案してください（ツール実行不要）';
      default:
        return '未知のツール: $name';
    }
  }

  static bool _truthy(dynamic v) {
    if (v == true) return true;
    if (v is num) return v != 0;
    final s = '$v'.trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes';
  }

  static int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v'.trim());
  }

  Future<String> _workspaceSymbol(Map<String, dynamic> args) async {
    final index = symbols;
    if (index == null || !index.isReady) return CodingSymbolFormat.unavailable;
    final query = '${args['query'] ?? args['pattern'] ?? ''}'.trim();
    if (query.isEmpty) return 'query が空です';
    try {
      return await index.workspaceSymbol(query: query);
    } catch (e) {
      return CodingSymbolFormat.failed(e);
    }
  }

  Future<String> _symbolAt(String name, Map<String, dynamic> args) {
    return _symbolFile('${args['path'] ?? ''}', (rel, buffer) async {
      final line = _asInt(args['line']);
      if (line == null || line < 1) return 'line が必要です（1始まり）';
      final column = _asInt(args['column'] ?? args['character']);
      final symbol = '${args['symbol'] ?? args['name'] ?? ''}'.trim();
      if ((column == null || column < 1) && symbol.isEmpty) {
        return 'symbol か column が必要です';
      }
      if (name == 'go_to_definition') {
        return symbols!.goToDefinition(
          relativePath: rel,
          line: line,
          column: column,
          symbol: symbol,
          bufferText: buffer,
          openBuffers: openBuffers,
        );
      }
      return symbols!.findReferences(
        relativePath: rel,
        line: line,
        column: column,
        symbol: symbol,
        bufferText: buffer,
        openBuffers: openBuffers,
      );
    });
  }

  Future<String> _symbolFile(
    String raw,
    Future<String> Function(String rel, String? buffer) action,
  ) async {
    final index = symbols;
    if (index == null || !index.isReady) return CodingSymbolFormat.unavailable;
    try {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return 'path が空です';
      final norm = normalizePathInput(trimmed);
      if (norm.isEmpty) return 'path が空です';
      var rel = norm;
      if (!await File(resolve(rel)).exists() && !_hasBuffer(rel)) {
        final soft = CodingPathResolver.softMatchFile(norm, indexedFiles);
        if (soft != null) rel = soft;
      }
      if (!await File(resolve(rel)).exists() && !_hasBuffer(rel)) {
        final candidates = CodingPathResolver.suggestCandidates(
          query: norm,
          indexedFiles: indexedFiles,
          indexedDirs: indexedDirectories,
          limit: pathCandidateLimit,
        );
        return CodingPathResolver.formatNotFound(
          kind: 'ファイル',
          requested: raw,
          candidates: candidates,
        );
      }
      final note = rel != norm ? '（パス補正: $raw → $rel）\n' : '';
      final body = await action(rel, _buffer(rel));
      return '$note$body';
    } on StateError catch (e) {
      return e.message;
    } catch (e) {
      return CodingSymbolFormat.failed(e);
    }
  }

  bool _hasBuffer(String rel) => _buffer(rel) != null;

  String? _buffer(String rel) {
    if (openBuffers.containsKey(rel)) return openBuffers[rel];
    final slash = rel.replaceAll('\\', '/');
    if (openBuffers.containsKey(slash)) return openBuffers[slash];
    return null;
  }
}
