/// Agent プロンプト補助アクション（S16 §2.3.0）。
enum CodingPromptAction {
  attachSelection,
  errorAnalyze,
  concise,
  expectFileOutput,
  expectFixProposal,
  expectDocumentCreate,
  expectDocumentEdit,
  programAnalyze,
  taskDecompose,
  taskEvaluate,
  runFlutterVerify;

  /// お気に入り登録の上限（入力欄下は1行に収める）。
  static const maxFavorites = 2;

  /// SharedPreferences 用 ID（[name] と同一）。
  String get id => name;

  /// ＋隣のお気に入りボタン用の短いラベル。
  String get shortLabel => switch (this) {
    attachSelection => '選択',
    errorAnalyze => 'エラー',
    concise => '簡潔',
    expectFileOutput => '新規',
    expectFixProposal => '修正',
    expectDocumentCreate => '作成',
    expectDocumentEdit => '文書',
    programAnalyze => '分析',
    taskDecompose => '分解',
    taskEvaluate => '評価',
    runFlutterVerify => 'テスト',
  };

  /// ＋メニュー内の表示名。
  String get menuLabel => switch (this) {
    attachSelection => 'セレクト範囲情報をプロンプトに貼り付け',
    errorAnalyze => 'エラー解析',
    concise => '簡潔に表示',
    expectFileOutput => '新規ソース提案を期待',
    expectFixProposal => '修正ソース提案を期待',
    expectDocumentCreate => 'ドキュメント作成を期待',
    expectDocumentEdit => '修正ドキュメント提案を期待',
    programAnalyze => 'プログラム分析',
    taskDecompose => 'タスク分解',
    taskEvaluate => 'タスク評価',
    runFlutterVerify => 'テストを実行',
  };

  static CodingPromptAction? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final v in values) {
      if (v.id == raw) return v;
    }
    return null;
  }

  /// 不正 ID を除き、最大 [maxFavorites] 件に正規化（登録順を維持）。
  static List<CodingPromptAction> normalizeFavorites(Iterable<String> ids) {
    final out = <CodingPromptAction>[];
    final seen = <CodingPromptAction>{};
    for (final id in ids) {
      final action = tryParse(id);
      if (action == null || seen.contains(action)) continue;
      out.add(action);
      seen.add(action);
      if (out.length >= maxFavorites) break;
    }
    return List<CodingPromptAction>.unmodifiable(out);
  }

  /// ソースや文書の具体的な出力を期待する＋。タスク分解と同時には付けない。
  bool get conflictsWithTaskDecompose => switch (this) {
    expectFileOutput ||
    expectFixProposal ||
    expectDocumentCreate ||
    expectDocumentEdit => true,
    _ => false,
  };

  /// 文書だけの＋なら、書き込み後の flutter analyze／test は走らせない。
  ///
  /// 新規ソース・修正ソース・エラー解析・テスト実行が同時なら検証する。
  static bool skipsFlutterVerify(Iterable<CodingPromptAction> actions) {
    final set = actions.toSet();
    final document =
        set.contains(expectDocumentCreate) || set.contains(expectDocumentEdit);
    if (!document) return false;
    return !set.contains(expectFileOutput) &&
        !set.contains(expectFixProposal) &&
        !set.contains(errorAnalyze) &&
        !set.contains(runFlutterVerify);
  }

  /// 適用中の補助をトグルする。
  ///
  /// エラー解析は、最初の指示では他の補助と同時に付けない。
  /// タスク分解と、ソース／文書の出力期待も同時に付けない。
  /// 後から押した方がもう一方を外す。
  static CodingPromptToggle toggleApplied({
    required List<CodingPromptAction> current,
    required CodingPromptAction action,
  }) {
    final next = List<CodingPromptAction>.from(current);
    if (next.remove(action)) {
      return CodingPromptToggle(
        applied: List<CodingPromptAction>.unmodifiable(next),
        removed: const [],
      );
    }
    final removed = <CodingPromptAction>[];
    if (action == CodingPromptAction.errorAnalyze) {
      for (final other in values) {
        if (other != CodingPromptAction.errorAnalyze && next.remove(other)) {
          removed.add(other);
        }
      }
    } else if (next.remove(CodingPromptAction.errorAnalyze)) {
      removed.add(CodingPromptAction.errorAnalyze);
    }
    if (action == CodingPromptAction.taskDecompose) {
      for (final other in values) {
        if (other.conflictsWithTaskDecompose && next.remove(other)) {
          removed.add(other);
        }
      }
    } else if (action.conflictsWithTaskDecompose) {
      if (next.remove(CodingPromptAction.taskDecompose)) {
        removed.add(CodingPromptAction.taskDecompose);
      }
    }
    next.add(action);
    return CodingPromptToggle(
      applied: List<CodingPromptAction>.unmodifiable(next),
      removed: List<CodingPromptAction>.unmodifiable(removed),
    );
  }

  /// お気に入りをトグルする。
  ///
  /// 追加時に上限超過なら `null`（変更なし）。解除／追加成功時は新しいリスト。
  static List<CodingPromptAction>? toggleFavorite({
    required List<CodingPromptAction> current,
    required CodingPromptAction action,
  }) {
    final next = List<CodingPromptAction>.from(current);
    if (next.contains(action)) {
      next.remove(action);
      return List<CodingPromptAction>.unmodifiable(next);
    }
    if (next.length >= maxFavorites) return null;
    next.add(action);
    return List<CodingPromptAction>.unmodifiable(next);
  }
}

/// [CodingPromptAction.toggleApplied] の結果。
final class CodingPromptToggle {
  const CodingPromptToggle({required this.applied, required this.removed});

  final List<CodingPromptAction> applied;

  /// 同時適用できないため外した項目。押した順のあとに残す。
  final List<CodingPromptAction> removed;
}
