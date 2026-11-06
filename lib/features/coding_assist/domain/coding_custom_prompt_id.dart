/// Agent が使うカスタム可能なプロンプト枠（S17）。
enum CodingCustomPromptId {
  /// Flutter 用 system。
  systemFlutter,

  /// Swift / Xcode 用 system。
  systemSwiftXcode,

  /// React 用 system。
  systemReact,

  /// Android 用 system。
  systemAndroid,

  /// Python 用 system。
  systemPython,

  /// 汎用 system。
  systemGeneric,

  /// 小説執筆用 system。
  systemNovel,

  /// 言語サーバ起動時のシンボル探索ツール説明。
  symbolTools,

  /// Flutter 回帰テスト同梱ルール（system／実装系＋に共有）。
  flutterRegression,

  /// 検査・再指示（未着手 read を許可）。
  deliverable,

  /// 本文供給後の検査・再指示（read 禁止）。
  deliverableClose,

  /// ＋ エラー解析（通常）。
  errorAnalyze,

  /// ＋ エラー解析（自動実行・read 禁止）。
  errorAnalyzeAuto,

  /// ＋ エラー解析（本文供給後）。
  errorAnalyzeBodies,

  /// ＋ 簡潔に表示。
  concise,

  /// ＋ 新規ソース提案を期待。
  expectFileOutput,

  /// ＋ 修正ソース提案を期待。
  expectFixProposal,

  /// ＋ ドキュメント作成を期待。
  expectDocumentCreate,

  /// ＋ 修正ドキュメント提案を期待。
  expectDocumentEdit,

  /// ＋ プログラム分析。
  programAnalyze,

  /// ＋ タスク分解。
  taskDecompose,

  /// タスク評価（別会話）。
  taskEvaluate,

  /// ＋ テストを実行。
  runFlutterVerify,

  /// 検証結果の報告依頼。
  flutterVerifyReport,

  /// ループ検知後の続行。
  autoLoopContinue;

  /// SharedPreferences 用キー。
  String get key => name;

  CodingCustomPromptCategory get category => switch (this) {
        systemFlutter ||
        systemSwiftXcode ||
        systemReact ||
        systemAndroid ||
        systemPython ||
        systemGeneric ||
        systemNovel ||
        symbolTools ||
        flutterRegression =>
          CodingCustomPromptCategory.system,
        errorAnalyze ||
        errorAnalyzeAuto ||
        errorAnalyzeBodies ||
        concise ||
        expectFileOutput ||
        expectFixProposal ||
        expectDocumentCreate ||
        expectDocumentEdit ||
        programAnalyze ||
        taskDecompose ||
        taskEvaluate ||
        runFlutterVerify =>
          CodingCustomPromptCategory.action,
        deliverable ||
        deliverableClose ||
        flutterVerifyReport ||
        autoLoopContinue =>
          CodingCustomPromptCategory.internal,
      };

  String get title => switch (this) {
        systemFlutter => 'System（Flutter）',
        systemSwiftXcode => 'System（Swift / Xcode）',
        systemReact => 'System（React）',
        systemAndroid => 'System（Android）',
        systemPython => 'System（Python）',
        systemGeneric => 'System（汎用）',
        systemNovel => 'System（小説）',
        symbolTools => 'シンボル探索ツール',
        flutterRegression => 'Flutter 回帰テスト規則',
        deliverable => '検査・再指示（未読許可）',
        deliverableClose => '検査・再指示（本文供給後）',
        errorAnalyze => 'エラー解析',
        errorAnalyzeAuto => 'エラー解析（自動実行）',
        errorAnalyzeBodies => 'エラー解析（本文供給後）',
        concise => '簡潔に表示',
        expectFileOutput => '新規ソース提案を期待',
        expectFixProposal => '修正ソース提案を期待',
        expectDocumentCreate => 'ドキュメント作成を期待',
        expectDocumentEdit => '修正ドキュメント提案を期待',
        programAnalyze => 'プログラム分析',
        taskDecompose => 'タスク分解',
        taskEvaluate => 'タスク評価',
        runFlutterVerify => 'テストを実行',
        flutterVerifyReport => '検証結果の報告',
        autoLoopContinue => 'ループ検知後の続行',
      };

  String get description => switch (this) {
        systemFlutter ||
        systemSwiftXcode ||
        systemReact ||
        systemAndroid ||
        systemPython ||
        systemGeneric ||
        systemNovel =>
          'Agent の system 役割・ツール／Patch 形式。ワークスペース種別に応じて選ばれる。',
        symbolTools => '言語サーバ起動時だけ system に足すツール説明。',
        flutterRegression =>
          'Flutter 実装系の＋や system に埋め込まれる回帰テスト同梱ルール。',
        deliverable => '検査 API の system 末尾（未着手の read_file は可）。',
        deliverableClose => '本文を渡したあとの検査 API の system 末尾。',
        errorAnalyze => '＋「エラー解析」通常送信時の指示本文。',
        errorAnalyzeAuto => '自動実行 ON 時のエラー解析（read_file 禁止）。',
        errorAnalyzeBodies => '不足ファイル本文を渡したあとのエラー解析。',
        concise => '＋「簡潔に表示」の指示。',
        expectFileOutput => '＋「新規ソース提案を期待」の形式ルール。',
        expectFixProposal => '＋「修正ソース提案を期待」の形式ルール。',
        expectDocumentCreate => '＋「ドキュメント作成を期待」の形式ルール。',
        expectDocumentEdit => '＋「修正ドキュメント提案を期待」の形式ルール。',
        programAnalyze => '＋「プログラム分析」の指示。',
        taskDecompose => '＋「タスク分解」の指示。',
        taskEvaluate => 'タスク評価用の別会話指示。',
        runFlutterVerify => '＋「テストを実行」の指示。',
        flutterVerifyReport => 'analyze／test 実行後の報告依頼。',
        autoLoopContinue => '同一応答ループ検知後に新しい会話へ載せる文。',
      };

  static CodingCustomPromptId? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final v in values) {
      if (v.key == raw) return v;
    }
    return null;
  }

  static String categoryLabel(CodingCustomPromptCategory category) =>
      switch (category) {
        CodingCustomPromptCategory.system => 'System／共有ルール',
        CodingCustomPromptCategory.action => '＋メニュー／送信時指示',
        CodingCustomPromptCategory.internal => '内部フロー',
      };
}

/// 設定画面のグループ。
enum CodingCustomPromptCategory {
  system,
  action,
  internal,
}
