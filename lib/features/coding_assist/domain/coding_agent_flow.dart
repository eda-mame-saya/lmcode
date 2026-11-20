import 'coding_prompt_action.dart';
import 'coding_workspace_kind.dart';

/// Agent 行動プレビューの 1 手順の種類（UI がアイコンと色に写像する）。
enum CodingFlowStepKind {
  send,
  docs,
  read,
  generate,
  apply,

  /// 人の操作が必要。
  manual,
  analyze,
  test,

  /// 検証失敗後の自動修正。
  fix,

  /// 走らない手順（理由つきで見せる）。
  skip,
}

class CodingFlowStep {
  const CodingFlowStep(
    this.kind,
    this.title, {
    this.detail,
    this.conditional = false,
  });

  final CodingFlowStepKind kind;
  final String title;
  final String? detail;

  /// 「Patch を出したときだけ」のように、条件つきで走る手順。
  final bool conditional;
}

enum CodingFlowEndingKind {
  /// 目的どおりに終わる。
  success,

  /// 打ち切り・失敗報告。
  stop,

  /// 人の操作待ち。
  manual,

  /// 補足（回答だけで終わる等）。
  info,
}

class CodingFlowEnding {
  const CodingFlowEnding(this.kind, this.label, {this.detail});

  final CodingFlowEndingKind kind;
  final String label;
  final String? detail;
}

/// 失敗時の自動修正ループ（自動実行 ON のときだけ）。
class CodingFlowLoop {
  const CodingFlowLoop({required this.maxSets, required this.steps});

  final int maxSets;
  final List<CodingFlowStep> steps;
}

/// ファイルを書き換えるか。
enum CodingFlowWrites {
  /// 書き換えない。
  none,

  /// Patch が出たら自動で書き込む。
  auto,

  /// Patch カードを人が承認して書き込む。
  approval,
}

/// analyze／test まで走るか。
enum CodingFlowVerifies {
  none,

  /// 書き込みが起きたときだけ。
  ifWritten,
  yes,
}

/// 3 つの「結論」。ポップアップ上部にそのまま出す。
class CodingFlowVerdict {
  const CodingFlowVerdict({
    required this.writes,
    required this.writesMaybe,
    required this.verifies,
    required this.autoFixSets,
  });

  final CodingFlowWrites writes;

  /// Patch を出すかどうかがモデル任せ（＋を選んでいない）。
  final bool writesMaybe;
  final CodingFlowVerifies verifies;

  /// 検証失敗時の自動修正セット数。0 は自動修正なし。
  final int autoFixSets;
}

/// プレビューの入力。bloc の状態から作る（domain は状態型に依存しない）。
class CodingAgentFlowInput {
  const CodingAgentFlowInput({
    required this.actions,
    required this.draft,
    this.hasAttachments = false,
    this.kind = CodingWorkspaceKind.generic,
    this.autoApply = false,
    this.autoAllowReadFile = false,
    this.webLibraryDocs = false,
    this.maxRounds = 12,
    this.maxVerifySets = 3,
    this.maxReproposals = 1,
    this.readFilesPerBatch = 5,
    this.patternLabel = '',
  });

  final List<CodingPromptAction> actions;
  final String draft;
  final bool hasAttachments;
  final CodingWorkspaceKind kind;
  final bool autoApply;
  final bool autoAllowReadFile;
  final bool webLibraryDocs;

  /// モデル往復の上限（自動実行 ON は OFF／ON の大きい方）。
  final int maxRounds;
  final int maxVerifySets;
  final int maxReproposals;
  final int readFilesPerBatch;

  /// 例: `コーディング・標準`。
  final String patternLabel;
}

class CodingAgentFlowPreview {
  const CodingAgentFlowPreview({
    required this.headline,
    required this.verdict,
    required this.steps,
    required this.loop,
    required this.endings,
    required this.notes,
    required this.assumptions,
  });

  /// 一文の結論。
  final String headline;
  final CodingFlowVerdict verdict;
  final List<CodingFlowStep> steps;
  final CodingFlowLoop? loop;
  final List<CodingFlowEnding> endings;
  final List<String> notes;

  /// 前提のチップ（自動実行・種別・パターン・上限）。
  final List<String> assumptions;
}

/// 現在の入力から Agent の代表的な動きを組み立てる。副作用なし。
///
/// 分岐は実装の正本に合わせる:
/// - 検証の要否: [CodingPromptAction.skipsFlutterVerify]／`CodingFlutterVerifyPolicy`
/// - 読取方針: `codingAutoOmitsReadFile`（自動実行 ON かつ read_file 禁止）
/// - 往復上限: 自動実行 ON は `max(maxAgentSteps, maxAgentStepsAuto)`
abstract final class CodingAgentFlow {
  static const _proposeActions = {
    CodingPromptAction.errorAnalyze,
    CodingPromptAction.reproduceError,
    CodingPromptAction.expectFileOutput,
    CodingPromptAction.expectFixProposal,
    CodingPromptAction.expectDocumentCreate,
    CodingPromptAction.expectDocumentEdit,
  };

  static CodingAgentFlowPreview build(CodingAgentFlowInput i) {
    final a = i.actions.toSet();
    final draft = i.draft.trim();
    final isFlutter = i.kind == CodingWorkspaceKind.flutter;
    final kindLabel = CodingWorkspaceKindDetect.displayLabel(i.kind);

    final verifyRequested = a.contains(CodingPromptAction.runFlutterVerify);
    final decompose = a.contains(CodingPromptAction.taskDecompose);
    final explicitPropose = a.any(_proposeActions.contains);
    final analyzeOnly =
        !decompose &&
        !explicitPropose &&
        a.contains(CodingPromptAction.programAnalyze);
    final verifyOnly = verifyRequested && !explicitPropose && !decompose;
    final freeform = !decompose && !explicitPropose && !analyzeOnly && !verifyOnly;

    // Patch を出すか: ＋で明示 → 出す、指定なし → モデル任せ、それ以外 → 出さない。
    final writesDefinite = explicitPropose;
    final writesMaybe = freeform;
    final expectsPatch = writesDefinite || writesMaybe;

    final skipVerify = CodingPromptAction.skipsFlutterVerify(a);
    final reproduceOnly =
        a.contains(CodingPromptAction.reproduceError) &&
        skipVerify &&
        !a.contains(CodingPromptAction.expectDocumentCreate) &&
        !a.contains(CodingPromptAction.expectDocumentEdit);

    // 検証の判定（CodingFlutterVerifyPolicy._afterTurn と同じ順）。
    var verifyRuns = false;
    var verifyIfWritten = false;
    String? verifySkipReason;
    String? verifyStopNote;
    if (skipVerify && !verifyRequested) {
      verifySkipReason = reproduceOnly
          ? '再現テストを残すため、analyze／test は走りません（確認は「テストを実行」）'
          : '文書だけの指示のため、analyze／test は走りません';
    } else if (!isFlutter) {
      if (verifyRequested) {
        verifyStopNote =
            '$kindLabel は Flutter ではないため、analyze／test は実行しません';
      } else if (i.autoApply && expectsPatch) {
        verifySkipReason = '$kindLabel は Flutter ではないため、analyze／test は走りません';
      }
    } else if (verifyRequested) {
      verifyRuns = true;
    } else if (i.autoApply && expectsPatch) {
      verifyRuns = true;
      verifyIfWritten = writesMaybe;
    }

    final steps = <CodingFlowStep>[];
    final notes = <String>[];
    final endings = <CodingFlowEnding>[];
    CodingFlowLoop? loop;

    // 1. 送信
    final picked = [
      for (final action in i.actions) action.shortLabel,
    ];
    final sendParts = <String>[
      if (draft.isNotEmpty) '「${_clip(draft, 36)}」',
      if (i.hasAttachments) '添付あり',
      if (picked.isNotEmpty) '＋: ${picked.join('・')}',
    ];
    steps.add(
      CodingFlowStep(
        CodingFlowStepKind.send,
        '指示を送信',
        detail: sendParts.isEmpty ? '（入力なし）' : sendParts.join('　'),
      ),
    );

    // 2. 最新情報
    if (a.contains(CodingPromptAction.fetchLatestDocs)) {
      steps.add(
        CodingFlowStep(
          CodingFlowStepKind.docs,
          '最新ドキュメントを取得',
          detail: i.webLibraryDocs
              ? 'fetch_library_docs を最初に呼び、版付きの根拠を得てから回答'
              : '歯車の「版付きライブラリ docs」が OFF のため、実際には取得できません',
        ),
      );
    }

    // 3. 読取
    if (!verifyOnly) {
      final appSupplies = i.autoApply && !i.autoAllowReadFile;
      steps.add(
        CodingFlowStep(
          CodingFlowStepKind.read,
          appSupplies ? '対象ファイルの本文をアプリが渡す' : '必要なファイルを read_file で読む',
          detail: appSupplies
              ? '自動実行中は read_file を使いません（歯車で許可すると読取も可）'
              : '1 応答で新規に ${i.readFilesPerBatch} 件まで。合計は ctx の半分まで',
        ),
      );
    }

    // 4. 生成
    if (verifyOnly) {
      steps.add(
        const CodingFlowStep(
          CodingFlowStepKind.generate,
          'テスト観点を説明',
          detail: '実行はアプリ側。モデルは「実行した」ことにしません',
        ),
      );
    } else if (decompose) {
      steps.add(
        CodingFlowStep(
          CodingFlowStepKind.generate,
          '目的 → 実行タスクを出力',
          detail: 'ソースは出しません（最大 ${i.maxRounds} 往復）',
        ),
      );
    } else if (analyzeOnly) {
      steps.add(
        CodingFlowStep(
          CodingFlowStepKind.generate,
          '分析結果を文章で回答',
          detail: '取り込み、無ければ表示中のファイルが対象（最大 ${i.maxRounds} 往復）',
        ),
      );
    } else if (a.contains(CodingPromptAction.reproduceError)) {
      steps.add(
        CodingFlowStep(
          CodingFlowStepKind.generate,
          'test/ に再現テストを Patch で生成',
          detail: '本番コードは直しません（最大 ${i.maxRounds} 往復）',
        ),
      );
    } else if (explicitPropose) {
      steps.add(
        CodingFlowStep(
          CodingFlowStepKind.generate,
          'Patch（Update／Add）を生成',
          detail: '最大 ${i.maxRounds} 往復。ツール結果を踏まえた再生成を含む',
        ),
      );
    } else {
      steps.add(
        CodingFlowStep(
          CodingFlowStepKind.generate,
          '回答を生成（必要なら Patch も出す）',
          detail: '＋を選ばない場合はモデルが判断（最大 ${i.maxRounds} 往復）',
        ),
      );
    }

    // 5. 書き込み
    CodingFlowWrites writes = CodingFlowWrites.none;
    if (expectsPatch) {
      if (i.autoApply) {
        writes = CodingFlowWrites.auto;
        steps.add(
          CodingFlowStep(
            CodingFlowStepKind.apply,
            'Patch を自動適用',
            detail:
                'Update は適用、Add は作成。現状と合わないときは最大 ${i.maxReproposals} 回、自動で出し直し',
            conditional: writesMaybe,
          ),
        );
      } else {
        writes = CodingFlowWrites.approval;
        steps.add(
          CodingFlowStep(
            CodingFlowStepKind.manual,
            'Patch カードを確認して「適用」「作成」を押す',
            detail: '人の操作。押すまでファイルは変わりません',
            conditional: writesMaybe,
          ),
        );
      }
    }

    // 6. 検証
    if (verifyRuns) {
      steps.add(
        CodingFlowStep(
          CodingFlowStepKind.analyze,
          'flutter analyze',
          detail: !i.autoApply && expectsPatch
              ? '未適用の Patch は含まれません（現状のコードが対象）'
              : 'エラーがあれば失敗として扱う',
          conditional: verifyIfWritten,
        ),
      );
      steps.add(
        CodingFlowStep(
          CodingFlowStepKind.test,
          'flutter test',
          detail: 'analyze が通ったときだけ実行',
          conditional: verifyIfWritten,
        ),
      );
      endings.add(
        const CodingFlowEnding(
          CodingFlowEndingKind.success,
          'analyze・test とも成功 → 完了',
          detail: '成功を報告して終わり',
        ),
      );
      if (i.autoApply) {
        loop = CodingFlowLoop(
          maxSets: i.maxVerifySets,
          steps: const [
            CodingFlowStep(
              CodingFlowStepKind.fix,
              '失敗ログの該当ファイルをアプリが先に渡す',
            ),
            CodingFlowStep(CodingFlowStepKind.fix, '修正 Patch を生成'),
            CodingFlowStep(CodingFlowStepKind.apply, '自動適用'),
            CodingFlowStep(CodingFlowStepKind.analyze, 'analyze → test をやり直し'),
          ],
        );
        endings.add(
          CodingFlowEnding(
            CodingFlowEndingKind.stop,
            '${i.maxVerifySets} セットで直らなければ打ち切り',
            detail: '失敗ログを報告。自動実行は ON のまま',
          ),
        );
      } else {
        endings.add(
          const CodingFlowEnding(
            CodingFlowEndingKind.stop,
            '失敗したらここで止まり、結果を報告するだけ',
            detail: '自動実行が OFF のため、自動修正はしません',
          ),
        );
      }
      endings.add(
        const CodingFlowEnding(
          CodingFlowEndingKind.manual,
          '新規パッケージが必要なら人が追加して止まる',
          detail: 'pubspec.yaml の追記とインストールは自動では行いません',
        ),
      );
    } else if (verifyStopNote != null) {
      steps.add(
        CodingFlowStep(CodingFlowStepKind.skip, 'analyze／test は実行しない',
            detail: verifyStopNote),
      );
    } else if (verifySkipReason != null) {
      steps.add(
        CodingFlowStep(CodingFlowStepKind.skip, 'analyze／test は走らない',
            detail: verifySkipReason, conditional: writesMaybe),
      );
    }

    // 7. 検証以外の終わり方
    if (!verifyRuns) {
      if (decompose) {
        endings.add(
          const CodingFlowEnding(
            CodingFlowEndingKind.success,
            'タスク一覧を示して終了',
            detail: 'ソースは変更しません',
          ),
        );
      } else if (analyzeOnly) {
        endings.add(
          const CodingFlowEnding(
            CodingFlowEndingKind.success,
            '分析結果を回答して終了',
            detail: 'ファイルは変更しません',
          ),
        );
      } else if (expectsPatch && writes == CodingFlowWrites.approval) {
        endings.add(
          const CodingFlowEnding(
            CodingFlowEndingKind.manual,
            'Patch の承認待ちで終了',
            detail: '自動では analyze／test は走りません（「テストを実行」は別操作）',
          ),
        );
      } else if (expectsPatch && writes == CodingFlowWrites.auto) {
        endings.add(
          CodingFlowEnding(
            CodingFlowEndingKind.success,
            '適用して終了',
            detail: verifySkipReason ?? 'analyze／test は走りません',
          ),
        );
      }
    }
    if (writesMaybe) {
      endings.add(
        const CodingFlowEnding(
          CodingFlowEndingKind.info,
          'Patch が無い（回答だけ）ならそこで終了',
          detail: 'この場合、書き込みも検証も起きません',
        ),
      );
    }

    // 注意書き
    if (draft.isEmpty && !verifyRequested && !i.hasAttachments) {
      notes.add('入力が空です。このままでは送信できません。');
    }
    if (a.contains(CodingPromptAction.errorAnalyze) && draft.isEmpty) {
      notes.add('「エラー解析」は、エラー文を入力欄に貼り付けてから送信します。');
    }
    if (i.autoApply) {
      if (expectsPatch && !verifyRuns && verifySkipReason == null) {
        notes.add('自動実行を OFF にすると、適用の前で止まり、人が承認します。');
      }
    } else if (expectsPatch) {
      notes.add(
        '自動実行を ON にすると、適用後に（Flutter なら）analyze → test まで進み、失敗時は自動修正します。',
      );
    }

    final verdict = CodingFlowVerdict(
      writes: writes,
      writesMaybe: writesMaybe,
      verifies: verifyRuns
          ? (verifyIfWritten ? CodingFlowVerifies.ifWritten : CodingFlowVerifies.yes)
          : CodingFlowVerifies.none,
      autoFixSets: verifyRuns && i.autoApply ? i.maxVerifySets : 0,
    );

    final assumptions = <String>[
      '自動実行 ${i.autoApply ? 'ON' : 'OFF'}',
      kindLabel,
      if (i.patternLabel.isNotEmpty) i.patternLabel,
      '往復 最大 ${i.maxRounds}',
      if (verifyRuns && i.autoApply) '検証 最大 ${i.maxVerifySets} セット',
    ];

    return CodingAgentFlowPreview(
      headline: _headline(
        verdict: verdict,
        decompose: decompose,
        analyzeOnly: analyzeOnly,
        verifyOnly: verifyOnly,
        verifyStopNote: verifyStopNote != null,
      ),
      verdict: verdict,
      steps: List.unmodifiable(steps),
      loop: loop,
      endings: List.unmodifiable(endings),
      notes: List.unmodifiable(notes),
      assumptions: List.unmodifiable(assumptions),
    );
  }

  static String _headline({
    required CodingFlowVerdict verdict,
    required bool decompose,
    required bool analyzeOnly,
    required bool verifyOnly,
    required bool verifyStopNote,
  }) {
    if (decompose) return 'タスクを分解して示すだけです。ファイルは変わりません。';
    if (analyzeOnly) return '分析して回答するだけです。ファイルは変わりません。';
    if (verifyStopNote) return 'このワークスペースでは analyze／test を実行できません。';
    if (verifyOnly) {
      return verdict.autoFixSets > 0
          ? '現状を analyze → test で確認します。'
          : '現状を analyze → test で確認し、結果を報告します（自動修正なし）。';
    }
    switch (verdict.verifies) {
      case CodingFlowVerifies.yes:
        return verdict.autoFixSets > 0
            ? 'Patch を適用し、テストまで自動で進みます。失敗時は最大 ${verdict.autoFixSets} セット自動修正します。'
            : 'テストまで進みます。';
      case CodingFlowVerifies.ifWritten:
        return 'Patch を出したら自動で適用し、テストまで進みます。回答だけなら何も変わりません。';
      case CodingFlowVerifies.none:
        break;
    }
    return switch (verdict.writes) {
      CodingFlowWrites.approval =>
        verdict.writesMaybe
            ? '回答します。Patch が出たら、承認するまでファイルは変わりません。'
            : 'Patch を提案して止まります。承認するまでファイルは変わりません。テストは走りません。',
      CodingFlowWrites.auto =>
        verdict.writesMaybe
            ? '回答します。Patch が出たら自動で適用しますが、テストは走りません。'
            : 'Patch を自動で適用して終わります。テストは走りません。',
      CodingFlowWrites.none => '回答するだけです。',
    };
  }

  static String _clip(String text, int max) {
    final oneLine = text.replaceAll(RegExp(r'\s+'), ' ');
    return oneLine.length <= max ? oneLine : '${oneLine.substring(0, max)}…';
  }
}
