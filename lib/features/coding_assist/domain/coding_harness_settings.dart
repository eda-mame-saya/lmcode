import 'package:equatable/equatable.dart';

enum CodingHarnessValueKind { intValue, doubleValue }

/// 設定画面の1行。既定・範囲・読み書きをここへ集約する。
class CodingHarnessField {
  const CodingHarnessField({
    required this.id,
    required this.group,
    required this.label,
    required this.kind,
    required this.min,
    required this.max,
    required this.read,
    required this.write,
    required this.hint,
  });

  final String id;
  final String group;
  final String label;
  final CodingHarnessValueKind kind;
  final num min;
  final num max;
  final num Function(CodingHarnessSettings settings) read;
  final CodingHarnessSettings Function(CodingHarnessSettings settings, num value)
      write;
  /// 値を変えたときに送信・ツール・圧縮・検証のどれがどう変わるか。
  final String hint;
}

/// S16 Agent のハーネス定数。未保存の項目は [defaults]。
class CodingHarnessSettings extends Equatable {
  const CodingHarnessSettings({
    this.temperature = 0.2,
    this.maxTokens = 0,
    this.requestTimeoutMinutes = 5,
    this.charsPerToken = 2,
    this.replyReserveRatio = 0.12,
    this.thinkingGuideChars = 400,
    this.reasoningAbortChars = 8000,
    this.maxAgentSteps = 12,
    this.maxAgentStepsAuto = 12,
    this.maxAutoReproposals = 1,
    this.maxReadFailuresPerPath = 3,
    this.maxReadChars = 80000,
    this.toolResultClipChars = 12000,
    this.maxGrepHits = 40,
    this.maxListEntries = 200,
    this.maxPathCandidates = 8,
    this.symbolMaxHits = 40,
    this.symbolMaxHitsBoth = 20,
    this.maxOutlineEntries = 80,
    this.maxDefinitionLocations = 8,
    this.maxSignatureMapChars = 2000,
    this.maxSymbolLineChars = 160,
    this.maxSymbolMapFiles = 6,
    this.openFileMaxChars = 80000,
    this.reproposeMaxChars = 24000,
    this.maxReplaceRangeLines = 400,
    this.maxListedFiles = 5000,
    this.maxTreeLines = 400,
    this.systemTreeChars = 6000,
    this.warnRatio = 0.70,
    this.autoCompactRatio = 0.85,
    this.blockRatio = 0.90,
    this.keepRecentUserTurns = 3,
    this.compactKeepRecentUserTurns = 1,
    this.autoExecuteKeptReads = 2,
    this.summaryPurposeCount = 5,
    this.summaryLineChars = 120,
    this.summaryFileCount = 20,
    this.priorSummaryChars = 240,
    this.autoExecuteMaxErrorLines = 40,
    this.verifyLogTailLines = 15,
    this.slimAssistantChars = 4000,
    this.slimAssistantFallbackChars = 800,
    this.investigatedPathCount = 20,
    this.maxVerifySets = 3,
    this.analyzeTimeoutMinutes = 3,
    this.testTimeoutMinutes = 10,
    this.verifyLogMaxChars = 8000,
    this.maxLoopRelocations = 1,
    this.minProseChars = 80,
    this.minCommandChars = 40,
    this.loopBodyMaxChars = 4000,
  });

  static const defaults = CodingHarnessSettings();

  final double temperature;
  final int maxTokens;
  final int requestTimeoutMinutes;
  final double charsPerToken;
  final double replyReserveRatio;
  final int thinkingGuideChars;
  final int reasoningAbortChars;
  final int maxAgentSteps;
  final int maxAgentStepsAuto;
  final int maxAutoReproposals;
  final int maxReadFailuresPerPath;
  final int maxReadChars;
  final int toolResultClipChars;
  final int maxGrepHits;
  final int maxListEntries;
  final int maxPathCandidates;
  final int symbolMaxHits;
  final int symbolMaxHitsBoth;
  final int maxOutlineEntries;
  final int maxDefinitionLocations;
  final int maxSignatureMapChars;
  final int maxSymbolLineChars;
  final int maxSymbolMapFiles;
  final int openFileMaxChars;
  final int reproposeMaxChars;
  final int maxReplaceRangeLines;
  final int maxListedFiles;
  final int maxTreeLines;
  final int systemTreeChars;
  final double warnRatio;
  final double autoCompactRatio;
  final double blockRatio;
  final int keepRecentUserTurns;
  final int compactKeepRecentUserTurns;
  final int autoExecuteKeptReads;
  final int summaryPurposeCount;
  final int summaryLineChars;
  final int summaryFileCount;
  final int priorSummaryChars;
  final int autoExecuteMaxErrorLines;
  final int verifyLogTailLines;
  final int slimAssistantChars;
  final int slimAssistantFallbackChars;
  final int investigatedPathCount;
  final int maxVerifySets;
  final int analyzeTimeoutMinutes;
  final int testTimeoutMinutes;
  final int verifyLogMaxChars;
  final int maxLoopRelocations;
  final int minProseChars;
  final int minCommandChars;
  final int loopBodyMaxChars;

  static final List<CodingHarnessField> fields = [
    CodingHarnessField(
      id: 'temperature',
      group: '生成',
      label: 'temperature',
      hint:
          'モデルの揺れ。上げると言い回しとパッチが変わりやすく、'
          '消す行（-）がファイルの現状とずれやすい。'
          '下げると、同じ依頼への返答が安定する。',
      kind: CodingHarnessValueKind.doubleValue,
      min: 0,
      max: 2,
      read: (s) => s.temperature,
      write: (s, v) => s.copyWith(temperature: v.toDouble()),
    ),
    CodingHarnessField(
      id: 'maxTokens',
      group: '生成',
      label: 'max_tokens',
      hint:
          '1回の返答の上限。0 はサーバ既定で、リクエストには載せない。'
          '正の値にすると、そのトークン数で生成が止まる。'
          '小さくすると Patch やツール呼び出しの途中で切れやすい。'
          '大きくすると1回の返答が長くなり、次のターンの使用見込みが増える。',
      kind: CodingHarnessValueKind.intValue,
      min: 0,
      max: 65536,
      read: (s) => s.maxTokens,
      write: (s, v) => s.copyWith(maxTokens: v.round()),
    ),
    CodingHarnessField(
      id: 'requestTimeoutMinutes',
      group: '生成',
      label: '接続待ち（分）',
      hint:
          'llama-server の応答を待つ時間。'
          '上げると、遅いモデルや長い思考でも待ち続ける。'
          '下げると、その分数で生成を打ち切る。',
      kind: CodingHarnessValueKind.intValue,
      min: 1,
      max: 30,
      read: (s) => s.requestTimeoutMinutes,
      write: (s, v) => s.copyWith(requestTimeoutMinutes: v.round()),
    ),
    CodingHarnessField(
      id: 'charsPerToken',
      group: '生成',
      label: '見積（文字／トークン）',
      hint:
          '文字数をトークンに換える係数（文字数÷この値）。'
          'ヘッダの使用見込みと、注意・自動圧縮・送信停止の判定に使う。'
          '上げると使用見込みが小さく見え、注意・圧縮・送信停止が遅れる。'
          '実際のトークンはコンテキスト長を超えることがある。'
          '下げると見積が大きくなり、まだ余裕があるうちに圧縮や送信停止が始まる。',
      kind: CodingHarnessValueKind.doubleValue,
      min: 0.5,
      max: 8,
      read: (s) => s.charsPerToken,
      write: (s, v) => s.copyWith(charsPerToken: v.toDouble()),
    ),
    CodingHarnessField(
      id: 'replyReserveRatio',
      group: '生成',
      label: '返答余白（ctx 比）',
      hint:
          'コーディング用コンテキスト長のこの割合を、返答枠として使用見込みに足す。'
          '上げると履歴に使える枠が減り、圧縮と送信停止が早くなる。'
          '返答はコンテキストの末尾で切れにくい。'
          '下げると履歴を多く載せる。返答に残る枠は減る。',
      kind: CodingHarnessValueKind.doubleValue,
      min: 0,
      max: 0.5,
      read: (s) => s.replyReserveRatio,
      write: (s, v) => s.copyWith(replyReserveRatio: v.toDouble()),
    ),
    CodingHarnessField(
      id: 'thinkingGuideChars',
      group: '生成',
      label: '思考の目安（字）',
      hint:
          '思考が ON のときだけ、システム指示に「目安はこの字数」と書く。'
          '上げると長い思考を許す指示になる。下げると短く考える指示になる。'
          'この値では生成は止まらない。停止は「思考の打ち切り」。',
      kind: CodingHarnessValueKind.intValue,
      min: 50,
      max: 4000,
      read: (s) => s.thinkingGuideChars,
      write: (s, v) => s.copyWith(thinkingGuideChars: v.round()),
    ),
    CodingHarnessField(
      id: 'reasoningAbortChars',
      group: '生成',
      label: '思考の打ち切り（字）',
      hint:
          '思考の本文がこの字数を超え、まだ返答本文が無いときに生成を止める。'
          '上げると長考を許す。待ち時間とメモリが増える。'
          '下げると、本文が出ない空回りを早く切る。'
          '考えたあとに本文を出すモデルは、本文の前に止まることがある。',
      kind: CodingHarnessValueKind.intValue,
      min: 200,
      max: 100000,
      read: (s) => s.reasoningAbortChars,
      write: (s, v) => s.copyWith(reasoningAbortChars: v.round()),
    ),
    CodingHarnessField(
      id: 'maxAgentSteps',
      group: 'ループ',
      label: 'ステップ上限（自動実行 OFF）',
      hint:
          '自動実行が OFF のとき、その送信でモデルを呼ぶ回数。'
          '上げるとツールとの往復が増え、パッチまで届きやすい。時間と使用見込みも増える。'
          '下げると早く止まり、最後がツールのままだと再生成に届かず終了する。',
      kind: CodingHarnessValueKind.intValue,
      min: 1,
      max: 40,
      read: (s) => s.maxAgentSteps,
      write: (s, v) => s.copyWith(maxAgentSteps: v.round()),
    ),
    CodingHarnessField(
      id: 'maxAgentStepsAuto',
      group: 'ループ',
      label: 'ステップ上限（自動実行 ON）',
      hint:
          '自動実行 ON の回数は、OFF のステップ上限とこの値の大きい方。'
          'この値を OFF より上げると、自動実行の往復がその数まで伸びる。'
          'OFF より下げても、ループは OFF の回数のまま続く。'
          'read_file を1応答で新たに開く件数（5件）とは別。',
      kind: CodingHarnessValueKind.intValue,
      min: 1,
      max: 40,
      read: (s) => s.maxAgentStepsAuto,
      write: (s, v) => s.copyWith(maxAgentStepsAuto: v.round()),
    ),
    CodingHarnessField(
      id: 'maxAutoReproposals',
      group: 'ループ',
      label: '同一パスの自動再提案',
      hint:
          '適用が現状と一致しないときや、作成先が既にあるときに、'
          '同じ相対パスを自動でもう一度出させる回数。'
          '0 にすると自動では出さず、差分カードを人に残す。'
          '上げると、その回数まで現状のファイルを渡して出し直す。'
          '人が押す「現状で再提案」は、この回数に関係なく実行できる。',
      kind: CodingHarnessValueKind.intValue,
      min: 0,
      max: 10,
      read: (s) => s.maxAutoReproposals,
      write: (s, v) => s.copyWith(maxAutoReproposals: v.round()),
    ),
    CodingHarnessField(
      id: 'maxReadFailuresPerPath',
      group: 'ループ',
      label: '同一パスの read 連続失敗',
      hint:
          '同じ相対パスの read_file が本文なしで続いた回数。'
          'この回数に達すると、そのターンでは再試行せず、システム指示の文言もこの回数になる。'
          '上げると、誤ったパスでも読み直しを続ける。'
          '下げると早く人手の取り込みに移る。'
          '一度成功すると回数は戻り、次の送信では数え直す。',
      kind: CodingHarnessValueKind.intValue,
      min: 1,
      max: 20,
      read: (s) => s.maxReadFailuresPerPath,
      write: (s, v) => s.copyWith(maxReadFailuresPerPath: v.round()),
    ),
    CodingHarnessField(
      id: 'maxReadChars',
      group: 'ツール',
      label: 'read_file（字）',
      hint:
          'read_file が1ファイルから返す先頭の文字数。超えた分は切って「先頭 N 文字まで」と返す。'
          '上げると大きいファイルを1回で読める。使用見込みも増える。'
          '下げると後半が結果に入らず、続きを読む指示が必要になる。',
      kind: CodingHarnessValueKind.intValue,
      min: 1000,
      max: 500000,
      read: (s) => s.maxReadChars,
      write: (s, v) => s.copyWith(maxReadChars: v.round()),
    ),
    CodingHarnessField(
      id: 'toolResultClipChars',
      group: 'ツール',
      label: '履歴に残すツール結果（字）',
      hint:
          'これから保存するツール結果と、その吹き出しの上限。'
          '上げると grep や長い read が履歴に残る。'
          '下げると保存した時点で末尾が落ち、圧縮する前からモデルは短い結果しか見ない。'
          '既に出ている吹き出しは短くならない。',
      kind: CodingHarnessValueKind.intValue,
      min: 500,
      max: 500000,
      read: (s) => s.toolResultClipChars,
      write: (s, v) => s.copyWith(toolResultClipChars: v.round()),
    ),
    CodingHarnessField(
      id: 'maxGrepHits',
      group: 'ツール',
      label: 'grep ヒット',
      hint:
          '1回の grep が返す一致の件数。'
          '上げると一致を多く見せる。使用見込みも増える。'
          '下げると後ろの一致が結果に出ない。',
      kind: CodingHarnessValueKind.intValue,
      min: 1,
      max: 500,
      read: (s) => s.maxGrepHits,
      write: (s, v) => s.copyWith(maxGrepHits: v.round()),
    ),
    CodingHarnessField(
      id: 'maxListEntries',
      group: 'ツール',
      label: 'list_dir 件数',
      hint:
          '1ディレクトリの一覧件数。'
          '上げると大きいディレクトリの奥まで見える。'
          '下げると一覧が先の方で終わる。',
      kind: CodingHarnessValueKind.intValue,
      min: 1,
      max: 5000,
      read: (s) => s.maxListEntries,
      write: (s, v) => s.copyWith(maxListEntries: v.round()),
    ),
    CodingHarnessField(
      id: 'maxPathCandidates',
      group: 'ツール',
      label: 'パス候補',
      hint:
          '指定パスが無いとき、索引から添える近いパスの数。'
          '上げるとモデルが選び直す材料が増える。'
          '下げると候補が少なく、パス補正の手がかりが減る。',
      kind: CodingHarnessValueKind.intValue,
      min: 1,
      max: 50,
      read: (s) => s.maxPathCandidates,
      write: (s, v) => s.copyWith(maxPathCandidates: v.round()),
    ),
    CodingHarnessField(
      id: 'symbolMaxHits',
      group: 'ツール',
      label: 'シンボル検索',
      hint:
          'Dart か Swift の一方だけ言語サーバがあるときの、ワークスペース記号検索の件数。'
          '上げると候補が増える。下げると先頭の候補だけになる。',
      kind: CodingHarnessValueKind.intValue,
      min: 1,
      max: 200,
      read: (s) => s.symbolMaxHits,
      write: (s, v) => s.copyWith(symbolMaxHits: v.round()),
    ),
    CodingHarnessField(
      id: 'symbolMaxHitsBoth',
      group: 'ツール',
      label: 'シンボル検索（Dart と Swift）',
      hint:
          'Dart と Swift の言語サーバが両方あるとき、それぞれの検索件数。'
          '上げると両方の結果が長くなり、使用見込みが増える。'
          '下げると片方あたりの候補が減る。',
      kind: CodingHarnessValueKind.intValue,
      min: 1,
      max: 200,
      read: (s) => s.symbolMaxHitsBoth,
      write: (s, v) => s.copyWith(symbolMaxHitsBoth: v.round()),
    ),
    CodingHarnessField(
      id: 'maxOutlineEntries',
      group: 'ツール',
      label: 'アウトライン行',
      hint:
          '1ファイルのアウトラインと、シグネチャ地図に出す記号の行数。'
          '上げるとファイル内の記号を多く載せる。'
          '下げるとファイル後方の宣言が地図から落ちる。',
      kind: CodingHarnessValueKind.intValue,
      min: 1,
      max: 500,
      read: (s) => s.maxOutlineEntries,
      write: (s, v) => s.copyWith(maxOutlineEntries: v.round()),
    ),
    CodingHarnessField(
      id: 'maxDefinitionLocations',
      group: 'ツール',
      label: '定義位置',
      hint:
          '定義へ飛ぶツールが返す位置の数。'
          '上げると同名の候補を多く返す。下げると最初の数件だけになる。',
      kind: CodingHarnessValueKind.intValue,
      min: 1,
      max: 50,
      read: (s) => s.maxDefinitionLocations,
      write: (s, v) => s.copyWith(maxDefinitionLocations: v.round()),
    ),
    CodingHarnessField(
      id: 'maxSignatureMapChars',
      group: 'ツール',
      label: 'シグネチャ地図（字）',
      hint:
          '毎回システム指示に付けるシンボル地図の総文字数。'
          '上げると、開いているファイルのシグネチャが長く残る。毎ターンの使用見込みが増える。'
          '下げると地図が早く切れる。',
      kind: CodingHarnessValueKind.intValue,
      min: 200,
      max: 50000,
      read: (s) => s.maxSignatureMapChars,
      write: (s, v) => s.copyWith(maxSignatureMapChars: v.round()),
    ),
    CodingHarnessField(
      id: 'maxSymbolLineChars',
      group: 'ツール',
      label: 'シンボル1行（字）',
      hint:
          '記号を1行に書くときの長さ。'
          '上げると引数リストが途中で切れにくく、呼び出し方まで地図に残る。'
          '下げると名前の途中で切れ、どの関数か判別しにくくなる。',
      kind: CodingHarnessValueKind.intValue,
      min: 40,
      max: 1000,
      read: (s) => s.maxSymbolLineChars,
      write: (s, v) => s.copyWith(maxSymbolLineChars: v.round()),
    ),
    CodingHarnessField(
      id: 'maxSymbolMapFiles',
      group: 'ツール',
      label: '地図に載せるファイル',
      hint:
          'シグネチャ地図に入れる、開いているファイルと取り込み中ファイルの数。'
          '上げると多くのファイルの宣言がシステム指示に入り、毎ターンの使用見込みが増える。'
          '下げると先頭のファイルだけになる。',
      kind: CodingHarnessValueKind.intValue,
      min: 1,
      max: 30,
      read: (s) => s.maxSymbolMapFiles,
      write: (s, v) => s.copyWith(maxSymbolMapFiles: v.round()),
    ),
    CodingHarnessField(
      id: 'openFileMaxChars',
      group: 'ツール',
      label: '取り込みファイル（字）',
      hint:
          '取り込みバーのファイルを送信文へ載せるときの、1ファイルの文字数上限。'
          '上げると大きいファイルの末尾まで依頼に含まれる。使用見込みも増える。'
          '下げると末尾が依頼から落ち、その部分の修正が現状とずれやすい。',
      kind: CodingHarnessValueKind.intValue,
      min: 1000,
      max: 500000,
      read: (s) => s.openFileMaxChars,
      write: (s, v) => s.copyWith(openFileMaxChars: v.round()),
    ),
    CodingHarnessField(
      id: 'reproposeMaxChars',
      group: 'ツール',
      label: '再提案の現状全文（字）',
      hint:
          '適用に失敗したあと、現状ファイルとしてモデルへ渡す本文の上限。'
          '上げると大きいファイルでも、消す行を現状に合わせやすい。'
          '下げると先頭だけが現状になり、後半の再提案が不一致になりやすい。',
      kind: CodingHarnessValueKind.intValue,
      min: 1000,
      max: 500000,
      read: (s) => s.reproposeMaxChars,
      write: (s, v) => s.copyWith(reproposeMaxChars: v.round()),
    ),
    CodingHarnessField(
      id: 'maxReplaceRangeLines',
      group: 'ツール',
      label: '自動置換の行数',
      hint:
          '自動実行が置換範囲で置き換えてよい行数。'
          '範囲がこれより広いと範囲置換はせず、不一致として再提案へ進む。'
          '上げると広い範囲を自動で書ける。'
          '下げると広い範囲は人の差分カードか再提案に回る。',
      kind: CodingHarnessValueKind.intValue,
      min: 10,
      max: 5000,
      read: (s) => s.maxReplaceRangeLines,
      write: (s, v) => s.copyWith(maxReplaceRangeLines: v.round()),
    ),
    CodingHarnessField(
      id: 'maxListedFiles',
      group: 'ツール',
      label: '索引ファイル数',
      hint:
          'フォルダ走査で覚える相対パスの数。次にフォルダを走査したときから効く。'
          '上げると大きいリポジトリでもパス補正と一覧に残る。走査は重くなる。'
          '下げると上限を超えたファイルが索引から外れ、候補にもディレクトリ樹にも出ない。',
      kind: CodingHarnessValueKind.intValue,
      min: 100,
      max: 50000,
      read: (s) => s.maxListedFiles,
      write: (s, v) => s.copyWith(maxListedFiles: v.round()),
    ),
    CodingHarnessField(
      id: 'maxTreeLines',
      group: 'ツール',
      label: '索引ツリー行',
      hint:
          '走査で作るディレクトリ樹の行数。次にフォルダを走査したときから効く。'
          'ファイルを先に並べるので、行数を下げてもルートの README や pubspec は残りやすい。'
          '上げると深いディレクトリまで樹に入る。',
      kind: CodingHarnessValueKind.intValue,
      min: 20,
      max: 5000,
      read: (s) => s.maxTreeLines,
      write: (s, v) => s.copyWith(maxTreeLines: v.round()),
    ),
    CodingHarnessField(
      id: 'systemTreeChars',
      group: 'ツール',
      label: 'system に載せる樹（字）',
      hint:
          '索引の樹のうち、システム指示へコピーする文字数。索引そのものの行数は「索引ツリー行」のまま。'
          '上げると毎ターン見える樹が長くなり、使用見込みが増える。'
          '下げるとシステム指示上の樹だけが途中で切れる。',
      kind: CodingHarnessValueKind.intValue,
      min: 200,
      max: 100000,
      read: (s) => s.systemTreeChars,
      write: (s, v) => s.copyWith(systemTreeChars: v.round()),
    ),
    CodingHarnessField(
      id: 'warnRatio',
      group: 'コンテキスト',
      label: 'warn（ctx 比）',
      hint:
          '使用見込みがコンテキスト長のこの割合以上になると、ヘッダに注意を出す。送信は止まらない。'
          '上げると注意が遅れる。下げると早い段階から注意が出る。'
          '保存時は、自動圧縮より小さい値に揃える。',
      kind: CodingHarnessValueKind.doubleValue,
      min: 0.05,
      max: 0.95,
      read: (s) => s.warnRatio,
      write: (s, v) => s.copyWith(warnRatio: v.toDouble()),
    ),
    CodingHarnessField(
      id: 'autoCompactRatio',
      group: 'コンテキスト',
      label: '自動圧縮（ctx 比）',
      hint:
          '自動実行が OFF のとき、次の送信前に使用見込みがこの割合へ達していたら、'
          '古いツール結果を短い控えにし、古い対話を要約に畳む。'
          '上げると全文に近い履歴を長く送る。'
          '下げると早い段階で古いツールが控えになり、古い対話が要約になる。'
          '自動実行が ON のときはこの割合を待たず、毎回作業記憶に圧縮する。'
          '保存時は、注意より大きく、送信停止より小さい値に揃える。',
      kind: CodingHarnessValueKind.doubleValue,
      min: 0.1,
      max: 0.98,
      read: (s) => s.autoCompactRatio,
      write: (s, v) => s.copyWith(autoCompactRatio: v.toDouble()),
    ),
    CodingHarnessField(
      id: 'blockRatio',
      group: 'コンテキスト',
      label: 'block（ctx 比）',
      hint:
          '圧縮したあとも使用見込みがこの割合以上なら、送信せず新規会話を案内する。'
          '上げるとコンテキスト長のぎりぎりまで送る。サーバ側で溢れる余地が増える。'
          '下げると早めに送信を止める。'
          '保存時は、自動圧縮より大きい値に揃える。',
      kind: CodingHarnessValueKind.doubleValue,
      min: 0.15,
      max: 0.99,
      read: (s) => s.blockRatio,
      write: (s, v) => s.copyWith(blockRatio: v.toDouble()),
    ),
    CodingHarnessField(
      id: 'keepRecentUserTurns',
      group: 'コンテキスト',
      label: '全文で残すターン',
      hint:
          '自動実行が OFF のとき、API へ送る履歴で、直近いくつのユーザー依頼以降のツール結果を全文のまま残すか。'
          'それより古いツール結果は短い控えになる。'
          '同じパスの read_file は、この範囲の中でも最新1件だけ全文。'
          '上げると最近の読取が残り、同じファイルの読み直しが減る。使用見込みは増える。'
          '下げると控えが増え、モデルが読み直す。0 だとツール結果はすべて控えになる。',
      kind: CodingHarnessValueKind.intValue,
      min: 0,
      max: 20,
      read: (s) => s.keepRecentUserTurns,
      write: (s, v) => s.copyWith(keepRecentUserTurns: v.round()),
    ),
    CodingHarnessField(
      id: 'compactKeepRecentUserTurns',
      group: 'コンテキスト',
      label: '圧縮時に残すターン',
      hint:
          '使用見込みによる圧縮で、メッセージのまま残す直近ユーザー依頼の数。'
          'それより前は「これまでの要約」1本に畳む。'
          '上げると圧縮しても直近の往復が長く残る。減る量は小さい。'
          '下げると多くの対話が要約だけになる。0 だと残すターンが無く、要約に寄せる。',
      kind: CodingHarnessValueKind.intValue,
      min: 0,
      max: 20,
      read: (s) => s.compactKeepRecentUserTurns,
      write: (s, v) => s.copyWith(compactKeepRecentUserTurns: v.round()),
    ),
    CodingHarnessField(
      id: 'autoExecuteKeptReads',
      group: 'コンテキスト',
      label: '自動実行で残す read',
      hint:
          '自動実行の作業記憶で、直前に読んだまとまり以外に全文で残す read_file の件数。'
          '残す優先は、まだ適用していないパスと、最新のエラーに出たパス。'
          '上げるとファイル本文が送信のたびに残り、使用見込みが増える。'
          '下げるとパスの一覧だけになり、モデルが同じファイルを読み直す。'
          '0 だと直前に読んだまとまり以外の本文は残さない。',
      kind: CodingHarnessValueKind.intValue,
      min: 0,
      max: 20,
      read: (s) => s.autoExecuteKeptReads,
      write: (s, v) => s.copyWith(autoExecuteKeptReads: v.round()),
    ),
    CodingHarnessField(
      id: 'summaryPurposeCount',
      group: 'コンテキスト',
      label: '要約に残す依頼',
      hint:
          '要約と作業記憶の「これまでの依頼」に載せるユーザー依頼の件数。'
          '上げると古い目的が残る。'
          '下げると古い依頼が要約から落ち、モデルが最初の目的を忘れやすい。',
      kind: CodingHarnessValueKind.intValue,
      min: 1,
      max: 30,
      read: (s) => s.summaryPurposeCount,
      write: (s, v) => s.copyWith(summaryPurposeCount: v.round()),
    ),
    CodingHarnessField(
      id: 'summaryLineChars',
      group: 'コンテキスト',
      label: '要約1行（字）',
      hint:
          '要約へ畳むユーザー依頼1件の長さ。'
          '上げると依頼の文面が長く残る。'
          '下げると1行が短くなり、条件やパスが切れる。',
      kind: CodingHarnessValueKind.intValue,
      min: 20,
      max: 1000,
      read: (s) => s.summaryLineChars,
      write: (s, v) => s.copyWith(summaryLineChars: v.round()),
    ),
    CodingHarnessField(
      id: 'summaryFileCount',
      group: 'コンテキスト',
      label: '要約に残すファイル',
      hint:
          '要約の「触ったファイル」に書くパスの数。'
          '上げると多くのパスが要約に残る。下げると古いパスが要約から落ちる。',
      kind: CodingHarnessValueKind.intValue,
      min: 1,
      max: 200,
      read: (s) => s.summaryFileCount,
      write: (s, v) => s.copyWith(summaryFileCount: v.round()),
    ),
    CodingHarnessField(
      id: 'priorSummaryChars',
      group: 'コンテキスト',
      label: '前回要約の再掲（字）',
      hint:
          'もう一度圧縮するとき、前回の要約を1行にして残す長さ。'
          '上げると前の要約が次の要約に長く残る。下げると古い要約が早く短くなる。',
      kind: CodingHarnessValueKind.intValue,
      min: 40,
      max: 4000,
      read: (s) => s.priorSummaryChars,
      write: (s, v) => s.copyWith(priorSummaryChars: v.round()),
    ),
    CodingHarnessField(
      id: 'autoExecuteMaxErrorLines',
      group: 'コンテキスト',
      label: '検証ログの error 行',
      hint:
          '自動実行の作業記憶で、最新の失敗ログから残す error、warning、FAILED、Expected の行数。'
          '上げると修正のターンが多くの診断を見る。使用見込みも増える。'
          '下げると後ろの診断が作業記憶から落ちる。',
      kind: CodingHarnessValueKind.intValue,
      min: 1,
      max: 400,
      read: (s) => s.autoExecuteMaxErrorLines,
      write: (s, v) => s.copyWith(autoExecuteMaxErrorLines: v.round()),
    ),
    CodingHarnessField(
      id: 'verifyLogTailLines',
      group: 'コンテキスト',
      label: '検証ログの末尾行',
      hint:
          '失敗ログに error などの行が1行も無いとき、末尾から残す行数。'
          '上げると形式の違うログが長く残る。下げると末尾の数行だけになる。',
      kind: CodingHarnessValueKind.intValue,
      min: 1,
      max: 200,
      read: (s) => s.verifyLogTailLines,
      write: (s, v) => s.copyWith(verifyLogTailLines: v.round()),
    ),
    CodingHarnessField(
      id: 'slimAssistantChars',
      group: 'コンテキスト',
      label: '直近応答を残す（字）',
      hint:
          '自動実行で、直前の応答がこの字数を超えたとき、'
          'ツール呼び出しと Patch の見出し行だけを残して短くする。'
          '上げると説明文も残りやすい。下げると説明が落ち、Patch の行だけが残りやすい。',
      kind: CodingHarnessValueKind.intValue,
      min: 200,
      max: 50000,
      read: (s) => s.slimAssistantChars,
      write: (s, v) => s.copyWith(slimAssistantChars: v.round()),
    ),
    CodingHarnessField(
      id: 'slimAssistantFallbackChars',
      group: 'コンテキスト',
      label: '直近応答の下限（字）',
      hint:
          '直前の応答に Patch の行もツール呼び出しも無いとき、先頭から残す字数。'
          '上げると長い説明が作業記憶に残る。下げると説明だけの応答は短く切れる。',
      kind: CodingHarnessValueKind.intValue,
      min: 50,
      max: 10000,
      read: (s) => s.slimAssistantFallbackChars,
      write: (s, v) => s.copyWith(slimAssistantFallbackChars: v.round()),
    ),
    CodingHarnessField(
      id: 'investigatedPathCount',
      group: 'コンテキスト',
      label: '調査済みパス',
      hint:
          '作業記憶の「調査したパス」（本文を載せていないツールのパス）の件数。'
          '上げると調べた場所の一覧が長く残る。'
          '下げると古いパスが一覧から落ち、同じ探索を繰り返しやすい。',
      kind: CodingHarnessValueKind.intValue,
      min: 1,
      max: 200,
      read: (s) => s.investigatedPathCount,
      write: (s, v) => s.copyWith(investigatedPathCount: v.round()),
    ),
    CodingHarnessField(
      id: 'maxVerifySets',
      group: '検証',
      label: '修正セット',
      hint:
          '検証が失敗したあと、エラー解析と自動書き込みを続ける回数。画面の n/この数 もこの値になる。'
          '上げると失敗が続くあいだ自動修正が長くなる。'
          '下げると早く検証レポートに移り、その実行は止まる。自動実行のスイッチは ON のまま。',
      kind: CodingHarnessValueKind.intValue,
      min: 1,
      max: 20,
      read: (s) => s.maxVerifySets,
      write: (s, v) => s.copyWith(maxVerifySets: v.round()),
    ),
    CodingHarnessField(
      id: 'analyzeTimeoutMinutes',
      group: '検証',
      label: 'flutter analyze（分）',
      hint:
          'flutter analyze を打ち切るまでの時間。'
          '上げると遅い解析を待てる。'
          '下げると時間切れになり、そのログで修正ループか検証レポートに進む。',
      kind: CodingHarnessValueKind.intValue,
      min: 1,
      max: 60,
      read: (s) => s.analyzeTimeoutMinutes,
      write: (s, v) => s.copyWith(analyzeTimeoutMinutes: v.round()),
    ),
    CodingHarnessField(
      id: 'testTimeoutMinutes',
      group: '検証',
      label: 'flutter test（分）',
      hint:
          'flutter test を打ち切るまでの時間。'
          '上げると遅いテスト全体を待てる。'
          '下げると時間切れになり、そのログで修正ループか検証レポートに進む。',
      kind: CodingHarnessValueKind.intValue,
      min: 1,
      max: 120,
      read: (s) => s.testTimeoutMinutes,
      write: (s, v) => s.copyWith(testTimeoutMinutes: v.round()),
    ),
    CodingHarnessField(
      id: 'verifyLogMaxChars',
      group: '検証',
      label: '検証ログ（字）',
      hint:
          'コマンド出力を残す文字数。残すときは末尾を優先する。'
          '上げると失敗ログの前の方まで、修正依頼とチャットに残る。'
          '下げると古い行が落ち、エラー抜粋の材料が末尾に寄る。'
          '既に出ている吹き出しは短くならない。',
      kind: CodingHarnessValueKind.intValue,
      min: 500,
      max: 100000,
      read: (s) => s.verifyLogMaxChars,
      write: (s, v) => s.copyWith(verifyLogMaxChars: v.round()),
    ),
    CodingHarnessField(
      id: 'maxLoopRelocations',
      group: '検証',
      label: '同一実行の会話移動',
      hint:
          '自動実行中に、同じ回答または同じ失敗ログが続いたとき、新しい会話へ移す回数。'
          '0 だと移さず、その実行だけ止める。1 だと1回移して続け、2回目で止める。'
          '上げると、同じ実行のたびに新しい会話で試す回数が増える。'
          '自動実行のスイッチは変えない。自動実行 OFF ではこの検知は動かない。',
      kind: CodingHarnessValueKind.intValue,
      min: 0,
      max: 10,
      read: (s) => s.maxLoopRelocations,
      write: (s, v) => s.copyWith(maxLoopRelocations: v.round()),
    ),
    CodingHarnessField(
      id: 'minProseChars',
      group: '検証',
      label: '同じ回答とみなす説明（字）',
      hint:
          'パッチが無い応答を「同じ回答」と比べるための、説明の長さ。'
          'この字数未満の説明は検知しない。ツールだけの応答も対象外。'
          '上げると短い繰り返しは同じ回答にならない。'
          '下げると短い説明の繰り返しでも、新しい会話への移動か停止が起きる。'
          '0 だと、決まった短い定型を除き、説明は長さに関係なく比べる。',
      kind: CodingHarnessValueKind.intValue,
      min: 0,
      max: 2000,
      read: (s) => s.minProseChars,
      write: (s, v) => s.copyWith(minProseChars: v.round()),
    ),
    CodingHarnessField(
      id: 'minCommandChars',
      group: '検証',
      label: '同じ失敗ログとみなす長さ（字）',
      hint:
          '失敗ログを同じ実行と比べるための長さ。所要時間の差は無視する。'
          '上げると短い失敗は同じ実行にならない。'
          '下げると短い同一ログでも、新しい会話への移動か停止が起きる。',
      kind: CodingHarnessValueKind.intValue,
      min: 0,
      max: 2000,
      read: (s) => s.minCommandChars,
      write: (s, v) => s.copyWith(minCommandChars: v.round()),
    ),
    CodingHarnessField(
      id: 'loopBodyMaxChars',
      group: '検証',
      label: '新規会話へ載せる本文（字）',
      hint:
          '会話を移すとき、直前の実行と今回の実行として新しい会話に載せる本文の長さ。末尾を残して切る。'
          '上げると新しい会話が直前の Patch やログを長く持つ。使用見込みも増える。'
          '下げると新しい会話が見る材料が短くなる。',
      kind: CodingHarnessValueKind.intValue,
      min: 200,
      max: 50000,
      read: (s) => s.loopBodyMaxChars,
      write: (s, v) => s.copyWith(loopBodyMaxChars: v.round()),
    ),
  ];

  CodingHarnessSettings normalized() {
    var next = this;
    for (final field in fields) {
      final raw = field.read(next).toDouble();
      final clamped = raw.clamp(field.min.toDouble(), field.max.toDouble());
      final stored = field.kind == CodingHarnessValueKind.intValue
          ? clamped.roundToDouble()
          : clamped;
      if ((stored - raw).abs() > 0.000001) {
        next = field.write(next, stored);
      }
    }
    var warn = next.warnRatio;
    var compact = next.autoCompactRatio;
    var block = next.blockRatio;
    if (compact <= warn) {
      compact = (warn + 0.01).clamp(0.1, 0.98);
    }
    if (block <= compact) {
      block = (compact + 0.01).clamp(0.15, 0.99);
    }
    if (warn != next.warnRatio ||
        compact != next.autoCompactRatio ||
        block != next.blockRatio) {
      next = next.copyWith(
        warnRatio: warn,
        autoCompactRatio: compact,
        blockRatio: block,
      );
    }
    return next;
  }

  Map<String, num> toJson() => {
    for (final field in fields) field.id: field.read(this),
  };

  factory CodingHarnessSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return defaults;
    var next = defaults;
    for (final field in fields) {
      final raw = json[field.id];
      if (raw is num) next = field.write(next, raw);
    }
    return next.normalized();
  }

  CodingHarnessSettings copyWith({
    double? temperature,
    int? maxTokens,
    int? requestTimeoutMinutes,
    double? charsPerToken,
    double? replyReserveRatio,
    int? thinkingGuideChars,
    int? reasoningAbortChars,
    int? maxAgentSteps,
    int? maxAgentStepsAuto,
    int? maxAutoReproposals,
    int? maxReadFailuresPerPath,
    int? maxReadChars,
    int? toolResultClipChars,
    int? maxGrepHits,
    int? maxListEntries,
    int? maxPathCandidates,
    int? symbolMaxHits,
    int? symbolMaxHitsBoth,
    int? maxOutlineEntries,
    int? maxDefinitionLocations,
    int? maxSignatureMapChars,
    int? maxSymbolLineChars,
    int? maxSymbolMapFiles,
    int? openFileMaxChars,
    int? reproposeMaxChars,
    int? maxReplaceRangeLines,
    int? maxListedFiles,
    int? maxTreeLines,
    int? systemTreeChars,
    double? warnRatio,
    double? autoCompactRatio,
    double? blockRatio,
    int? keepRecentUserTurns,
    int? compactKeepRecentUserTurns,
    int? autoExecuteKeptReads,
    int? summaryPurposeCount,
    int? summaryLineChars,
    int? summaryFileCount,
    int? priorSummaryChars,
    int? autoExecuteMaxErrorLines,
    int? verifyLogTailLines,
    int? slimAssistantChars,
    int? slimAssistantFallbackChars,
    int? investigatedPathCount,
    int? maxVerifySets,
    int? analyzeTimeoutMinutes,
    int? testTimeoutMinutes,
    int? verifyLogMaxChars,
    int? maxLoopRelocations,
    int? minProseChars,
    int? minCommandChars,
    int? loopBodyMaxChars,
  }) {
    return CodingHarnessSettings(
      temperature: temperature ?? this.temperature,
      maxTokens: maxTokens ?? this.maxTokens,
      requestTimeoutMinutes:
          requestTimeoutMinutes ?? this.requestTimeoutMinutes,
      charsPerToken: charsPerToken ?? this.charsPerToken,
      replyReserveRatio: replyReserveRatio ?? this.replyReserveRatio,
      thinkingGuideChars: thinkingGuideChars ?? this.thinkingGuideChars,
      reasoningAbortChars: reasoningAbortChars ?? this.reasoningAbortChars,
      maxAgentSteps: maxAgentSteps ?? this.maxAgentSteps,
      maxAgentStepsAuto: maxAgentStepsAuto ?? this.maxAgentStepsAuto,
      maxAutoReproposals: maxAutoReproposals ?? this.maxAutoReproposals,
      maxReadFailuresPerPath:
          maxReadFailuresPerPath ?? this.maxReadFailuresPerPath,
      maxReadChars: maxReadChars ?? this.maxReadChars,
      toolResultClipChars: toolResultClipChars ?? this.toolResultClipChars,
      maxGrepHits: maxGrepHits ?? this.maxGrepHits,
      maxListEntries: maxListEntries ?? this.maxListEntries,
      maxPathCandidates: maxPathCandidates ?? this.maxPathCandidates,
      symbolMaxHits: symbolMaxHits ?? this.symbolMaxHits,
      symbolMaxHitsBoth: symbolMaxHitsBoth ?? this.symbolMaxHitsBoth,
      maxOutlineEntries: maxOutlineEntries ?? this.maxOutlineEntries,
      maxDefinitionLocations:
          maxDefinitionLocations ?? this.maxDefinitionLocations,
      maxSignatureMapChars: maxSignatureMapChars ?? this.maxSignatureMapChars,
      maxSymbolLineChars: maxSymbolLineChars ?? this.maxSymbolLineChars,
      maxSymbolMapFiles: maxSymbolMapFiles ?? this.maxSymbolMapFiles,
      openFileMaxChars: openFileMaxChars ?? this.openFileMaxChars,
      reproposeMaxChars: reproposeMaxChars ?? this.reproposeMaxChars,
      maxReplaceRangeLines: maxReplaceRangeLines ?? this.maxReplaceRangeLines,
      maxListedFiles: maxListedFiles ?? this.maxListedFiles,
      maxTreeLines: maxTreeLines ?? this.maxTreeLines,
      systemTreeChars: systemTreeChars ?? this.systemTreeChars,
      warnRatio: warnRatio ?? this.warnRatio,
      autoCompactRatio: autoCompactRatio ?? this.autoCompactRatio,
      blockRatio: blockRatio ?? this.blockRatio,
      keepRecentUserTurns: keepRecentUserTurns ?? this.keepRecentUserTurns,
      compactKeepRecentUserTurns:
          compactKeepRecentUserTurns ?? this.compactKeepRecentUserTurns,
      autoExecuteKeptReads: autoExecuteKeptReads ?? this.autoExecuteKeptReads,
      summaryPurposeCount: summaryPurposeCount ?? this.summaryPurposeCount,
      summaryLineChars: summaryLineChars ?? this.summaryLineChars,
      summaryFileCount: summaryFileCount ?? this.summaryFileCount,
      priorSummaryChars: priorSummaryChars ?? this.priorSummaryChars,
      autoExecuteMaxErrorLines:
          autoExecuteMaxErrorLines ?? this.autoExecuteMaxErrorLines,
      verifyLogTailLines: verifyLogTailLines ?? this.verifyLogTailLines,
      slimAssistantChars: slimAssistantChars ?? this.slimAssistantChars,
      slimAssistantFallbackChars:
          slimAssistantFallbackChars ?? this.slimAssistantFallbackChars,
      investigatedPathCount:
          investigatedPathCount ?? this.investigatedPathCount,
      maxVerifySets: maxVerifySets ?? this.maxVerifySets,
      analyzeTimeoutMinutes:
          analyzeTimeoutMinutes ?? this.analyzeTimeoutMinutes,
      testTimeoutMinutes: testTimeoutMinutes ?? this.testTimeoutMinutes,
      verifyLogMaxChars: verifyLogMaxChars ?? this.verifyLogMaxChars,
      maxLoopRelocations: maxLoopRelocations ?? this.maxLoopRelocations,
      minProseChars: minProseChars ?? this.minProseChars,
      minCommandChars: minCommandChars ?? this.minCommandChars,
      loopBodyMaxChars: loopBodyMaxChars ?? this.loopBodyMaxChars,
    );
  }

  @override
  List<Object?> get props => [for (final field in fields) field.read(this)];
}
