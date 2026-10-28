import '../../domain/coding_prompt_action.dart';
import '../../domain/coding_workspace_kind.dart';
import '../../domain/entities/coding_assist_entities.dart';

/// 自動検証の失敗ログを、既存のエラー解析指示つきで Agent に渡す。
/// チャット上の先頭は `【自動検証 n/3】flutter analyze` のようになる。
String codingAssistAutoVerifyFixPrompt({
  required int setNumber,
  required int maxSets,
  required String commandLabel,
  required String log,
  bool bodiesSupplied = false,
}) {
  final header = '【自動検証 $setNumber/$maxSets】$commandLabel';
  return '$header\n${codingAssistErrorAnalyzePrompt(log, omitReadFile: true, bodiesSupplied: bodiesSupplied)}';
}

/// ＋メニュー「テストを実行」の印。再実行でも検証を始める判定に使う。
const codingAssistFlutterVerifyMarker = '【テスト実行】';

/// 「テストを実行」ボタン用。送信後にアプリが analyze と test を回す。
String codingAssistRunFlutterVerifyPrompt(String draft) {
  const rules =
      '''
【テスト実行】
今の実装を flutter analyze と flutter test で確認する。
コマンドはアプリが送信後にこの順で実行する。あなたは実行したことにしない。

- 依頼がテストだけのときはパッチを出さず、確認する対象を短く書く。合格・不合格はこの時点では書かない
- 実装・修正・新規ファイルの依頼があるときは、これまでどおり Begin/End Patch で出す。文章やコードフェンスだけのソースは禁止
- 「新規ソース提案を期待」と同時なら Add File の形式を守る
- 失敗ログが後から渡されたときは、そのログに対する修正 Patch を出す

${CodingWorkspaceKindDetect.flutterRegressionTestRule}
''';
  final body = draft.trim();
  if (body.isEmpty) return rules.trim();
  return '$body\n\n$rules'.trim();
}

/// 検証コマンドのあと、何をテストしどの結果で合格か不合格かを報告させる。
/// 印 `【テスト実行】` は付けない（再検証の判定に使わない）。
String codingAssistFlutterVerifyReportPrompt({
  required bool passed,
  required List<({String label, int? exitCode, bool timedOut, String log})>
  commands,
}) {
  final verdict = passed ? '合格' : '不合格';
  final blocks = commands
      .map((command) {
        final code = command.exitCode?.toString() ?? 'なし';
        final timeout = command.timedOut ? '\nタイムアウト: あり' : '';
        final log = command.log.trim().isEmpty ? '（ログなし）' : command.log.trim();
        return '### ${command.label}\n終了コード: $code$timeout\n$log';
      })
      .join('\n\n');
  return '''
【検証結果の報告】
アプリがコマンドを実行し終えた。判定の材料は下の結果だけです。あなたはコマンドを実行したことにしない。

パッチ（*** Begin Patch / *** End Patch）も修正案も出さない。回答の最後は次の報告だけにする。

## 検証レポート
- 判定: $verdict（この判定は変えない）
- 何をテストしたか: 実行したコマンドと、ログにある対象（テスト名、ファイル、issue）。ログに無い対象は書かない
- 合格または不合格を分けた結果: 終了コードと、判断に使ったログの行

$blocks
'''
      .trim();
}

/// 同一実行の1回目。最後に実行した内容と、今の内容だけを新しい会話へ載せる。
String codingAssistAutoLoopContinuePrompt({
  required String lastBody,
  required String currentBody,
}) {
  return '''
【ループ検知】
同じ応答、または同じコマンド結果が繰り返されたため、新しい会話で自動実行を続けます。
直前と同じ Patch、同じツール、同じ修正を出さない。別の原因と別の直し方を検討する。

【最後に実行した内容】
$lastBody

【現在実行している内容】
$currentBody
'''
      .trim();
}

/// 「エラー解析」ボタン用。貼り付け済みエラー本文に解析・修正指示を付与する。
///
/// [omitReadFile] は自動実行 ON。`read_file` を書かせず、足りないパスは `不足:` だけにする。
/// [bodiesSupplied] は本文を渡したあと。`不足:` を許さず、渡したファイルだけを直させる。
String codingAssistErrorAnalyzePrompt(
  String errorText, {
  bool omitReadFile = false,
  bool bodiesSupplied = false,
  CodingWorkspaceKind kind = CodingWorkspaceKind.flutter,
}) {
  final samples = CodingWorkspaceKindDetect.samplesFor(kind);
  final shortageExample = kind == CodingWorkspaceKind.flutter
      ? '相対/パス.dart'
      : samples.addFile;
  final regression = samples.usesFlutterTests
      ? CodingWorkspaceKindDetect.flutterRegressionTestRule
      : '';
  final investigate = bodiesSupplied
      ? '2. 行番号は渡された本文の1行目から数える。渡したファイルだけを直す。一覧に無いパスは書かない。read_file・list_dir・grep・不足: は書かない。'
      : omitReadFile
      ? '''
2. 行番号は渡された本文の1行目から数える。read_file・list_dir・grep は書かない。足りないファイルはツールにせず、次の形だけを書く:
不足:
$shortageExample'''
      : '2. 必要なら list_dir または grep または read_file で該当箇所を確認する（推測で直さない）';
  final unknown = bodiesSupplied
      ? '渡した本文で直せないときは、そのファイルの Patch を出さない。渡していないパスは書かない。推測 Patch は出さない。'
      : omitReadFile
      ? 'エラーが特定できないときだけ、不足: と相対パスだけを書く。read_file・list_dir・grep は書かない。推測 Patch は出さない。'
      : 'エラーが特定できないときだけ、追加調査の tool 呼び出しに留め、推測 Patch は出さない。';
  final autoReads = bodiesSupplied
      ? '\n渡した本文だけで Patch を書く。list_dir・grep・read_file・不足: は書かない。文法エラーだけの修正ではテスト Patch を出さない。'
      : omitReadFile
      ? (samples.usesFlutterTests
            ? '\n自動実行中は、上の list_dir・grep も read_file も書かない。test/ のパスは渡された本文から決める。本文に無ければ 不足: と相対パスだけを書く。'
            : '\n自動実行中は、上の list_dir・grep も read_file も書かない。本文に無ければ 不足: と相対パスだけを書く。')
      : '';
  final rules =
      '''
【エラー解析の指示・最優先で厳守】
貼り付けたビルド／実行エラーの原因を調べ、**修正案は必ず UI カード用の Begin/End Patch 形式だけ**で出す。
説明だけで終わらない。Markdown の ``` コードブロックや「こう直してください」だけの文章修正はカードにならないため禁止。

手順:
1. エラー文言からファイルパス・行番号・シンボル名を読み取る
$investigate
3. 原因を日本語で短く（2〜4行）書く
4. 続けて修正 Patch を出す（形式は下記のみ。1文字でも崩すとカードが出ない）

【A】既存関数の修正（- と + の両方。関数全体）:
置換範囲: 10-12
*** Begin Patch
*** Update File: ${samples.updateFile}
@@
-void foo() {
-  doOld();
-}
+void foo() {
+  doNew();
+}
*** End Patch

【B】新規関数の追加（+ のみ。- 行なし）:
挿入行: 42
*** Begin Patch
*** Update File: ${samples.updateFile}
@@
+void bar() {
+  doSomething();
+}
*** End Patch

【C】新規ファイルが必要なときだけ:
配置先: ${samples.addFile}
*** Begin Patch
*** Add File: ${samples.addFile}
@@
+...
*** End Patch

正解の条件（すべて満たす）:
- 必ず *** Begin Patch と *** End Patch で囲む（Update File または Add File 行だけでは不可）
- **1 Patch = 関数（メソッド）1つ**。複数直すときは Patch を分ける
- 既存修正: - = 現状の関数全文、+ = 修正後の関数全文（変更行だけの断片禁止）。Patch 直前に `置換範囲: 開始-終了`（${omitReadFile ? '渡された本文' : 'read_file の本文'}を1行目として数えた、置き換える関数の行。両端含む）
- 新規挿入: + のみ＋Patch 直前に `挿入行: N`（1-based）
- パスはワークスペース相対。*** Update File: または *** Add File: を省略しない
- @@ は1 Patch に1回だけ。文脈行（先頭スペース）は不要
- Markdown のコードフェンス（```）でパッチを包まない

禁止（1つでもしたらやり直し）:
- 修正案を文章や通常のコードブロックだけで出す（カードにならない）
- Begin/End Patch・Update File・Add File の省略や別形式（diff -u、unified diff のみ等）
- 変更行だけの断片／クラス全体・ファイル全文の再掲
- 複数関数を1 Patch にまとめる
- 既存修正なのに `置換範囲: 開始-終了` が無い
- 「修正しました」だけで Patch を出さない

$unknown

$regression$autoReads
''';
  final body = errorText.trim();
  if (body.isEmpty) return rules.trim();
  return '【エラー文言】\n$body\n\n$rules'.trim();
}

/// 「簡潔に表示」ボタン用。通常送信に簡潔指示を付与する。
String codingAssistConcisePrompt(String draft) {
  const rules = '【指示】回答は短く簡潔に。冗長な説明は避けてください。';
  final body = draft.trim();
  if (body.isEmpty) return rules;
  return '$body\n\n$rules';
}

/// 「新規ソース提案を期待」ボタン用。新規ソースの形式と配置先の検討を明示する。
String codingAssistExpectFileOutputPrompt(
  String draft, {
  CodingWorkspaceKind kind = CodingWorkspaceKind.flutter,
}) {
  final samples = CodingWorkspaceKindDetect.samplesFor(kind);
  final searchHint = samples.usesFlutterTests
      ? '同機能の features、同種の util、test の並び'
      : '同じ種類のソースが置いてあるディレクトリ';
  final regression = samples.usesFlutterTests
      ? CodingWorkspaceKindDetect.flutterRegressionTestRule
      : '';
  final otherLanguageBan = samples.usesFlutterTests
      ? ''
      : '- lib/ や test/ や pubspec.yaml や *_test.dart は Flutter 用なので使わない\n';
  final rules =
      '''
【新規ソース提案の指示・最優先で厳守】
この依頼では新規ソースファイルの作成案を期待します。
**パスは推測で決めない。** 既存のフォルダ構成を確認してから、どこに作るかを決める。
作成先は必ずワークスペースルートからの相対パスで明示する（ファイル名だけは不可）。

配置の決め方（Patch を出す前に必ず実施）:
1. list_dir または grep で、依頼に近い既存コードの置き場所を調べる（例: $searchHint）
2. そのプロジェクトの慣習に合わせた**ディレクトリ付き**相対パスを選ぶ（例: `${samples.addFile}`）
3. 同名／類似名が既にあるか確認し、衝突や重複配置を避ける
4. Patch の直前に必ず1行で書く: `配置先: ${samples.addFile}`（このパスと Add File 行を一致させる）
5. 必要なら続けて短い日本語1行で「なぜそのパスか」を書く

形式（この形だけ）:
配置先: ${samples.addFile}
*** Begin Patch
*** Add File: ${samples.addFile}
@@
+1行目
+2行目
*** End Patch

必須:
- 必ず *** Begin Patch と *** End Patch で囲む（Add File 行だけでは不可）
- *** Add File: の後ろはディレクトリを含むワークスペース相対パス（`/` を含む）。ファイル名だけは禁止
- パスは常にワークスペースルート基準。直前の list_dir のカレントや開いているファイルからの相対にはしない
- 説明用の記号名・大文字連結名・括弧付きラベルをパスに入れない
- 新規は + 行のみ（文脈行や - 行は不要）
- Markdown のコードフェンスでパッチを包まない
- 既存ソースの修正は「修正ソース提案を期待」を使う
- 文書だけの作成・修正は「ドキュメント作成を期待」「修正ドキュメント提案を期待」を使う

禁止:
- 構成を見ずに ${samples.addFile} の例をそのまま使う、または適当なパスへ置く
- ${samples.layoutHint}を無視した配置
- **UI の左メニュー選択位置・開いているタブの場所を、作成先の根拠にしない**（依頼と既存構成だけで決める）
- `${samples.bareName}` のようにディレクトリ無しのパス
- list_dir したフォルダをカレント扱いして短いパスだけ書く
$otherLanguageBan
$regression
''';
  final body = draft.trim();
  if (body.isEmpty) return rules.trim();
  return '$body\n\n$rules'.trim();
}

/// 「プログラム分析」ボタン用。取り込み／エディタ内容の説明依頼。
String codingAssistProgramAnalyzePrompt([String draft = '']) {
  const rules = '''
【プログラム分析の指示】
取り込まれているソース（なければ直前に付与した開いているファイル）を読み、日本語で分かりやすく説明してください。

含めること:
- ファイルの役割・概要
- 主要な型／関数／クラスとその関係
- 処理の流れ（あれば）
- 注意点や依存関係（分かる範囲）

Begin/End Patch やコード変更案は出さない（説明のみ）。
ツールで別ファイルを広く探索する必要はない。付与された内容を正とする。
''';
  final body = draft.trim();
  if (body.isEmpty) return rules.trim();
  return '$body\n\n$rules'.trim();
}

/// 「タスク分解」ボタン用。最初に目的、続けて実行タスク。ソースは出さない。
String codingAssistTaskDecomposePrompt(
  String draft, {
  CodingWorkspaceKind kind = CodingWorkspaceKind.flutter,
}) {
  final samples = CodingWorkspaceKindDetect.samplesFor(kind);
  final testTask = samples.usesFlutterTests
      ? '- Flutter で振る舞いを追加・修正するタスクがあるときは、対応する test/ の *_test.dart を別タスクにする（（新規）または（既存）。パッチは出さない）'
      : '- テスト用ファイルを別タスクにするのは、このワークスペースに既存のテスト配置があるときだけ。Flutter の test/ に合わせない';
  final rules =
      '''
【タスク分解の指示・最優先で厳守】
与えられた依頼を、あとで一つずつ実行できる小さなタスクに分解して提示してください。
ローカル LLM はまとめて頼むと精度が落ちるため、**クラウド向けより細かく・詳細に**分けることが目的です。粗すぎる分解は不可。
各タスクに「どのファイルで・何をするか」が無いとローカル LLM が混乱するため、**対象パスは必須**。

最初に、この分解が何を達成するためのタスクなのかを書いてください。実行タスクのリストより前です。
実行手順の羅列だけで始めない。

粒度の目安（厳守）:
- 「画面を作る」「API を実装する」のような大きい塊は禁止。さらに分割する
- 1タスク＝ファイル1つへの1種類の作業、または関数／メソッド1つの追加・修正、または設定1項目、までに落とす
- 調査（どのファイルを見るか）・作成・修正・接続・表示 を別タスクにする
- 迷ったら分割する（タスク数が多くてよい。5個未満にまとめない）

必須（各タスクに必ず含める）:
- **どのファイルで**: ディレクトリ付きのワークスペース相対パスを明示（例: `${samples.addFile}`。ファイル名だけは不可）
- **何をするか**: そのファイルでの具体的な作業を1〜2文（関数名や画面要素が分かれば書く）
- 新規作成なら「（新規）相対パス」、既存修正なら「（既存）相対パス」と書く
- パスが未確定なら、想定のディレクトリ付きパスを書いたうえで「配置は既存構成を確認して確定」と1語添える（パス欄を空にしない）
- 1タスクに複数ファイルを詰め込まない（ファイルが違えばタスクを分ける）
$testTask
- 番号付きリストで、実行順に並べる
- 「適切に対応」など曖昧な表現は不可
- 依存がある場合は順序だけで示す

禁止（1つでもしたらやり直し）:
- 対象ファイルパスの無いタスク
- ファイル名だけのパス（例: `${samples.bareName}`）や、UI メニュー選択位置を前提にした曖昧な場所指定
- 粗い大項目のまま（例: 「モデルと UI を実装する」を1タスクにまとめる）
- ソースコード・コード例・パッチ・Begin/End Patch の提示
- ファイル全文や差分の提示
- 実装そのもの／ツール呼び出し／ファイル読取（分解の提示だけ行う）

出力形式（この形だけ）:
目的: （この依頼が達成したいこと。1〜2文。手順は書かない）

1. （新規|既存）相対パス — 何をするか
2. （新規|既存）相対パス — 何をするか
3. …

例:
目的: Todo の追加と一覧表示ができるようにする。

1. （新規）${samples.addFile} — そのファイルに、依頼の中の一つの型または画面を定義する
2. （既存）${samples.updateFile} — 既存の表示または処理を一つ直す

目的のあとは番号付きの実行タスクだけ。目的以外の前置きや締めの長文は不要。
''';
  final body = draft.trim();
  if (body.isEmpty) return rules.trim();
  return '$body\n\n$rules'.trim();
}

/// 「ドキュメント作成を期待」ボタン用。文書の新規ファイルだけを出し、検証は走らせない。
String codingAssistExpectDocumentCreatePrompt(String draft) {
  const rules = '''
【ドキュメント作成の指示・最優先で厳守】
この依頼では文書の新規作成だけを期待します。
ソース、テスト、設定ファイルは出さない。この送信のあと flutter analyze と flutter test は走らない。

配置の決め方（Patch を出す前に必ず実施）:
1. list_dir または grep で、既存の文書の置き場所を調べる（例: document/ 配下の同種の Markdown）
2. その並びの慣習に合わせたディレクトリ付き相対パスを選ぶ（例: `document/notes/example.md`）
3. 同名が既にあるか確認し、衝突を避ける
4. Patch の直前に必ず1行で書く: `配置先: document/.../file.md`（このパスと Add File 行を一致させる）

形式（この形だけ）:
配置先: document/notes/example.md
*** Begin Patch
*** Add File: document/notes/example.md
@@
+# 見出し
+本文
*** End Patch

必須:
- 必ず *** Begin Patch と *** End Patch で囲む
- *** Add File: の後ろはディレクトリを含むワークスペース相対パス（`/` を含む）
- パスは常にワークスペースルート基準。メニュー選択位置や開いているタブは根拠にしない
- 新規は + 行のみ（文脈行や - 行は不要）
- 中身は Markdown などの文書。Dart やソースの実装にしない
- Markdown のコードフェンスでパッチを包まない

禁止:
- lib/ や test/ へのソース、*_test.dart、pubspec.yaml の変更
- 回帰テストの追加
- 既存文書の修正（それは「修正ドキュメント提案を期待」）
- 関数単位の Update File
- ファイル名だけのパス
''';
  final body = draft.trim();
  if (body.isEmpty) return rules.trim();
  return '$body\n\n$rules'.trim();
}

/// 「修正ドキュメント提案を期待」ボタン用。節単位の文書修正。検証は走らせない。
String codingAssistExpectDocumentEditPrompt(String draft) {
  const rules = '''
【ドキュメント修正の指示・最優先で厳守】
既存の文書を、節または連続する範囲で直します。関数単位ではありません。
ソース、テスト、設定ファイルは出さない。この送信のあと flutter analyze と flutter test は走らない。

【A】既存範囲の修正（- と + の両方）:
置換範囲: 10-18
*** Begin Patch
*** Update File: document/notes/example.md
@@
-## 旧見出し
-旧本文
+## 新見出し
+新本文
*** End Patch

【B】新しい節の追加（+ のみ）:
挿入行: 42
*** Begin Patch
*** Update File: document/notes/example.md
@@
+## 追加する節
+本文
*** End Patch

正解の条件（すべて満たす）:
- 1 Patch = 直す範囲1つ。離れた節は Begin/End Patch を分ける
- 既存修正: - = 現状のその範囲全文、+ = 修正後。Patch 直前に `置換範囲: 開始-終了`（read_file の本文を1行目として数えた行。両端含む）
- 新しい節: + のみ。Patch 直前に `挿入行: N`（1-based。その行の先頭に挿入する）
- パスはワークスペース相対。Update File を使う
- 文書の文言だけを変える。ソースの実装に書き換えない
- Markdown のコードフェンスでパッチを包まない

禁止（1つでもしたらやり直し）:
- 前後が読めなくなる変更行だけの断片（直す節は範囲ごと載せる）
- ファイル全文の再掲
- lib/、test/、*_test.dart、pubspec.yaml、回帰テスト
- Add File（新規文書は「ドキュメント作成を期待」）
- 既存修正なのに置換範囲が無い／新しい節なのに挿入行が無い
''';
  final body = draft.trim();
  if (body.isEmpty) return rules.trim();
  return '$body\n\n$rules'.trim();
}

/// 文書だけの指示が本文にあり、ソース系の指示が無い。再実行で＋ ID が無いときの判定。
bool codingTextSkipsFlutterVerify(String text) {
  const documentMarks = ['【ドキュメント作成の指示', '【ドキュメント修正の指示'];
  if (!documentMarks.any(text.contains)) return false;
  const sourceMarks = [
    '【新規ソース提案の指示',
    '【ファイル出力の指示',
    '【修正ソース提案の指示',
    '【エラー解析の指示',
    codingAssistFlutterVerifyMarker,
  ];
  return !sourceMarks.any(text.contains);
}

/// 「修正ソース提案を期待」ボタン用。関数単位の置換／新規挿入前提を明示する。
String codingAssistExpectFixProposalPrompt(
  String draft, {
  CodingWorkspaceKind kind = CodingWorkspaceKind.flutter,
}) {
  final samples = CodingWorkspaceKindDetect.samplesFor(kind);
  final regression = samples.usesFlutterTests
      ? CodingWorkspaceKindDetect.flutterRegressionTestRule
      : '';
  final otherLanguageBan = samples.usesFlutterTests
      ? ''
      : '- lib/ や test/ や pubspec.yaml は Flutter 用なので使わない\n';
  final rules =
      '''
【修正ソース提案の指示・最優先で厳守】
既存関数の修正は関数全体を選択して置換、**新規関数の追加は提案した行へ挿入**します。
1 Patch = 関数（メソッド）1つ。変更行だけの断片は禁止。
単純挿入では「どこに入れるか」が分からないため、**挿入行番号は必須**。

【A】既存関数の修正（- と + の両方）:
置換範囲: 10-12
*** Begin Patch
*** Update File: ${samples.updateFile}
@@
-void foo() {
-  doOld();
-}
+void foo() {
+  doNew();
+}
*** End Patch

【B】新規関数の追加（+ のみ。- 行は出さない）:
挿入行: 42
*** Begin Patch
*** Update File: ${samples.updateFile}
@@
+void bar() {
+  doSomething();
+}
*** End Patch

正解の条件（すべて満たす）:
- **1つの Begin/End Patch に関数（メソッド）を1つだけ**入れる
- 既存修正: - 行 = 現状の関数全文、+ 行 = 修正後の関数全文
- **既存修正は Patch 直前に `置換範囲: 開始-終了` を必ず書く**（read_file の本文を上から1行目として数える。開始と終了は置き換える関数の行で、両端含む。自動実行はこの範囲を + 行で置換する）
- 新規追加: **+ 行のみ**（新規関数全文）。Update File を使う（Add File は新規ファイル用）
- **新規追加は Patch 直前に `挿入行: N` を必ず書く**（N は read_file で確認した 1 始まりの行番号。その行の先頭に挿入し、元の N 行以降は下へずれる）
- 挿入行は「直前の関数の閉じ `}` の次」「クラス末尾の `}` の直前」など、既存構造に合う位置にする
- 文脈行（先頭スペース）は不要。@@ は1 Patch に1回だけ
- パスはワークスペース相対
- トップレベル定数・フィールドのみも同様（修正は -/+、新規追加は + のみ＋挿入行）

複数箇所がある場合:
- **関数ごとに Begin/End Patch を分ける**（同じファイルでも関数が違えば Patch を分ける）
- 各挿入 Patch ごとに `挿入行: N` を付ける

禁止（1つでもしたらやり直し）:
- 変更行だけの断片（関数の一部行だけ）
- 複数関数を1 Patch にまとめる
- クラス全体・ファイル全文の再掲
- 新規関数なのに - 行を付ける／既存修正なのに - を省略する
- **既存修正なのに置換範囲が無い**／開始・終了が read_file の行と対応しない
- **新規挿入なのに挿入行番号が無い**／「適当な場所」「末尾付近」だけの曖昧指定
- @@ を2回以上
- Add File／Markdown の ``` でパッチを包む
- Begin/End や Update File の省略
$otherLanguageBan
$regression
''';
  final body = draft.trim();
  if (body.isEmpty) return rules.trim();
  return '$body\n\n$rules'.trim();
}

/// 開いているファイル取り込み用ブロック（送信時合成。読取上限は tool と同程度）。
String codingAssistOpenFilePromptBlock({
  required String relativePath,
  required String content,
  int maxChars = 80000,
}) {
  return CodingAttachedOpenFile(
    relativePath: relativePath,
    content: content,
  ).toPromptBlock(maxChars: maxChars);
}

/// ＋メニュー「セレクト範囲情報をプロンプトに貼り付け」の説明。
const codingAssistAttachSelectionHint = 'エディタの選択範囲を送信時に付与します（入力欄には書きません）';

/// ＋メニュー「エラー解析」の説明。
const codingAssistErrorAnalyzeHint =
    '押すと適用（もう一度で解除）。他の補助とは同時に適用できません。入力欄のエラー文言に解析・修正指示を付け、送信ボタンで送ります。';

/// ＋メニュー「簡潔に表示」の説明。
const codingAssistConciseHint = '押すと適用（もう一度で解除）。「短く簡潔に」の指示を送信時に付けます。';

/// ＋メニュー「新規ソース提案を期待」の説明。
const codingAssistExpectFileOutputHint = '押すと適用（もう一度で解除）。新規ソースの形式ルールを送信時に付けます。';

/// ＋メニュー「修正ソース提案を期待」の説明。
const codingAssistExpectFixProposalHint =
    '押すと適用（もう一度で解除）。関数単位の修正形式ルールを送信時に付けます。';

/// ＋メニュー「ドキュメント作成を期待」の説明。
const codingAssistExpectDocumentCreateHint =
    '押すと適用（もう一度で解除）。文書の新規作成ルールを送信時に付けます。flutter analyze は走りません。';

/// ＋メニュー「修正ドキュメント提案を期待」の説明。
const codingAssistExpectDocumentEditHint =
    '押すと適用（もう一度で解除）。既存文書の修正ルールを送信時に付けます。flutter analyze は走りません。';

/// ＋メニュー「プログラム分析」の説明。
const codingAssistProgramAnalyzeHint =
    '押すと適用（もう一度で解除）。取り込み、無ければ表示中ファイルを分析する指示を送信時に付けます。';

/// ＋メニュー「タスク分解」の説明。
const codingAssistTaskDecomposeHint =
    '押すと適用（もう一度で解除）。最初に目的、続けて細かい実行タスクを出す指示を送信時に付けます。ソースは出しません。';

/// 「タスク評価」用。分解結果を別会話で見直す。元の依頼文は含めない。
String codingAssistTaskEvaluatePrompt(String tasks) {
  const rules = '''
【タスク評価の指示・最優先で厳守】
これはタスクを出した会話の続きではありません。下のタスク案を、初めて見るものとして評価してください。
同じ流れで出した側が「問題ない」とまとめるのを避けるため、別の会話に移しています。
元の依頼文は渡していません。何のための分解かは、タスク案の先頭にある「目的:」を正としてください。

見ること（添付ファイルと目的に照らす）:
- 目的を達成するのに足りない作業
- 1タスクに複数ファイルや複数種類の作業が混ざっていないか
- パスが添付の内容や書かれている目的と食い違っていないか
- 依存の順序
- Flutter の振る舞いを変えるのに、対応する test/ の *_test.dart が別タスクに無いか
- 目的と関係のないタスク

必須:
- 「問題なし」「このままでよい」の一言だけで終えない
- 添付に無い実装を想像して、足りていることにしない
- 問題が無い観点は、何を確認して問題が無かったかを1行で書く

出力形式（この形だけ）:
判定: 要修正
または
判定: このまま
指摘:
- （タスク番号、または全体）何が足りないか、何が誤っているか。問題が無い確認も1行以上
直し後のタスク:
目的: （元の目的。変えるなら理由を同じ行に短く書く）
1. （新規|既存）相対パス — 何をするか

判定が「このまま」のときは「直し後のタスク: なし」。
要修正のときは、実行できる粒度でタスクを書き直す。

禁止:
- ソースコード・パッチ・Begin/End Patch
- 実装そのもの
- 元の依頼文の再構成
''';
  final body = tasks.trim();
  if (body.isEmpty) return rules.trim();
  return '$body\n\n$rules'.trim();
}

/// ＋メニュー「タスク評価」の説明。
const codingAssistTaskEvaluateHint =
    '押すと、直近のタスク分解をコピーして新しい会話で評価します。添付ファイルは引き継ぎ、元の依頼文は渡しません。';

/// ＋メニュー「テストを実行」の説明。
const codingAssistRunFlutterVerifyHint =
    '押すと適用（もう一度で解除）。送信後に flutter analyze と flutter test を実行し、何をテストしどの結果で合格か不合格かを報告させます。入力が空でも送れます。';

/// 検査・再指示の API に足す、＋の指示本文。下書きは含めない。
String codingAssistFixedPromptRules(
  List<CodingPromptAction> applied, {
  bool omitReadFile = false,
  bool bodiesSupplied = false,
  CodingWorkspaceKind kind = CodingWorkspaceKind.flutter,
}) {
  if (applied.isEmpty) return '';
  return codingAssistApplyPromptActions(
    '',
    applied,
    omitReadFile: omitReadFile,
    bodiesSupplied: bodiesSupplied,
    kind: kind,
  ).trim();
}

/// 適用中の補助を、押した順に下書きへ重ねる。送信ボタンでのみ使う。
String codingAssistApplyPromptActions(
  String draft,
  List<CodingPromptAction> applied, {
  bool omitReadFile = false,
  bool bodiesSupplied = false,
  CodingWorkspaceKind kind = CodingWorkspaceKind.flutter,
}) {
  var text = draft;
  for (final action in applied) {
    text = switch (action) {
      CodingPromptAction.errorAnalyze => codingAssistErrorAnalyzePrompt(
        text,
        omitReadFile: omitReadFile,
        bodiesSupplied: bodiesSupplied,
        kind: kind,
      ),
      CodingPromptAction.concise => codingAssistConcisePrompt(text),
      CodingPromptAction.expectFileOutput => codingAssistExpectFileOutputPrompt(
        text,
        kind: kind,
      ),
      CodingPromptAction.expectFixProposal =>
        codingAssistExpectFixProposalPrompt(text, kind: kind),
      CodingPromptAction.expectDocumentCreate =>
        codingAssistExpectDocumentCreatePrompt(text),
      CodingPromptAction.expectDocumentEdit =>
        codingAssistExpectDocumentEditPrompt(text),
      CodingPromptAction.programAnalyze => codingAssistProgramAnalyzePrompt(
        text,
      ),
      CodingPromptAction.taskDecompose => codingAssistTaskDecomposePrompt(
        text,
        kind: kind,
      ),
      CodingPromptAction.taskEvaluate => text,
      CodingPromptAction.runFlutterVerify => codingAssistRunFlutterVerifyPrompt(
        text,
      ),
      CodingPromptAction.attachSelection => text,
    };
  }
  return text;
}
