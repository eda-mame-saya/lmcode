import 'package:flutter_test/flutter_test.dart';
import 'package:lmcode/features/coding_assist/domain/coding_agent_flow.dart';
import 'package:lmcode/features/coding_assist/domain/coding_prompt_action.dart';
import 'package:lmcode/features/coding_assist/domain/coding_workspace_kind.dart';

/// 10 §4.1 の代表経路と、CodingFlutterVerifyPolicy／skipsFlutterVerify の分岐に一致すること。
void main() {
  CodingAgentFlowPreview flow({
    List<CodingPromptAction> actions = const [],
    String draft = 'ログイン画面を直して',
    CodingWorkspaceKind kind = CodingWorkspaceKind.flutter,
    bool auto = true,
    bool allowRead = false,
    int sets = 3,
  }) => CodingAgentFlow.build(
    CodingAgentFlowInput(
      actions: actions,
      draft: draft,
      kind: kind,
      autoApply: auto,
      autoAllowReadFile: allowRead,
      maxVerifySets: sets,
    ),
  );

  List<CodingFlowStepKind> kinds(CodingAgentFlowPreview p) => [
    for (final s in p.steps) s.kind,
  ];

  group('経路1+2: 自動実行 ON・Flutter・修正提案', () {
    final p = flow(actions: [CodingPromptAction.expectFixProposal]);

    test('適用 → analyze → test まで進み、失敗時は自動修正', () {
      expect(kinds(p), [
        CodingFlowStepKind.send,
        CodingFlowStepKind.read,
        CodingFlowStepKind.generate,
        CodingFlowStepKind.apply,
        CodingFlowStepKind.analyze,
        CodingFlowStepKind.test,
      ]);
      expect(p.verdict.writes, CodingFlowWrites.auto);
      expect(p.verdict.verifies, CodingFlowVerifies.yes);
      expect(p.verdict.autoFixSets, 3);
      expect(p.loop?.maxSets, 3);
      expect(
        p.endings.map((e) => e.kind),
        containsAll([CodingFlowEndingKind.success, CodingFlowEndingKind.stop]),
      );
    });

    test('セット数はハーネス値に追従', () {
      final q = flow(actions: [CodingPromptAction.expectFixProposal], sets: 2);
      expect(q.loop?.maxSets, 2);
      expect(q.verdict.autoFixSets, 2);
    });
  });

  group('経路3: 自動実行 OFF', () {
    test('承認待ちで止まり、test まで行かない', () {
      final p = flow(
        actions: [CodingPromptAction.expectFixProposal],
        auto: false,
      );
      expect(p.verdict.writes, CodingFlowWrites.approval);
      expect(p.verdict.verifies, CodingFlowVerifies.none);
      expect(p.loop, isNull);
      expect(kinds(p), contains(CodingFlowStepKind.manual));
      expect(kinds(p), isNot(contains(CodingFlowStepKind.test)));
    });

    test('「テストを実行」付きなら検証は走るが自動修正はしない', () {
      final p = flow(
        actions: [CodingPromptAction.runFlutterVerify],
        draft: '',
        auto: false,
      );
      expect(p.verdict.verifies, CodingFlowVerifies.yes);
      expect(p.verdict.autoFixSets, 0);
      expect(p.loop, isNull);
    });
  });

  group('経路4: 検証スキップ', () {
    test('文書だけなら適用して終わり（analyze／test なし）', () {
      final p = flow(actions: [CodingPromptAction.expectDocumentCreate]);
      expect(p.verdict.writes, CodingFlowWrites.auto);
      expect(p.verdict.verifies, CodingFlowVerifies.none);
      expect(kinds(p), contains(CodingFlowStepKind.skip));
      expect(kinds(p), isNot(contains(CodingFlowStepKind.analyze)));
    });

    test('文書＋テストを実行 なら検証する', () {
      final p = flow(
        actions: [
          CodingPromptAction.expectDocumentCreate,
          CodingPromptAction.runFlutterVerify,
        ],
      );
      expect(p.verdict.verifies, CodingFlowVerifies.yes);
    });

    test('エラーの再現だけなら検証ループに入らない', () {
      final p = flow(actions: [CodingPromptAction.reproduceError]);
      expect(p.verdict.verifies, CodingFlowVerifies.none);
      expect(p.steps.map((s) => s.title), contains('test/ に再現テストを Patch で生成'));
    });

    test('Flutter 以外では自動実行でも検証しない', () {
      final p = flow(
        actions: [CodingPromptAction.expectFixProposal],
        kind: CodingWorkspaceKind.python,
      );
      expect(p.verdict.writes, CodingFlowWrites.auto);
      expect(p.verdict.verifies, CodingFlowVerifies.none);
    });

    test('Flutter 以外で「テストを実行」は実行しない旨を示す', () {
      final p = flow(
        actions: [CodingPromptAction.runFlutterVerify],
        draft: '',
        kind: CodingWorkspaceKind.generic,
      );
      expect(p.verdict.verifies, CodingFlowVerifies.none);
      expect(kinds(p), contains(CodingFlowStepKind.skip));
    });
  });

  group('その他', () {
    test('エラー解析は修正まで進み検証する', () {
      final p = flow(actions: [CodingPromptAction.errorAnalyze]);
      expect(p.verdict.verifies, CodingFlowVerifies.yes);
    });

    test('タスク分解は書き込まない', () {
      final p = flow(actions: [CodingPromptAction.taskDecompose]);
      expect(p.verdict.writes, CodingFlowWrites.none);
      expect(p.verdict.verifies, CodingFlowVerifies.none);
    });

    test('プログラム分析は書き込まない', () {
      final p = flow(actions: [CodingPromptAction.programAnalyze]);
      expect(p.verdict.writes, CodingFlowWrites.none);
    });

    test('＋なしの自動実行 ON は、書き込みがあれば検証（回答だけなら何も起きない）', () {
      final p = flow();
      expect(p.verdict.verifies, CodingFlowVerifies.ifWritten);
      expect(p.steps.where((s) => s.conditional), isNotEmpty);
      expect(
        p.endings.map((e) => e.kind),
        contains(CodingFlowEndingKind.info),
      );
    });

    test('読取: 自動実行 ON は既定でアプリが渡す。許可すると read_file', () {
      final off = flow(actions: [CodingPromptAction.expectFixProposal]);
      expect(
        off.steps.firstWhere((s) => s.kind == CodingFlowStepKind.read).title,
        contains('アプリが渡す'),
      );
      final on = flow(
        actions: [CodingPromptAction.expectFixProposal],
        allowRead: true,
      );
      expect(
        on.steps.firstWhere((s) => s.kind == CodingFlowStepKind.read).title,
        contains('read_file'),
      );
    });

    test('入力なしは注意書きを出す', () {
      final p = flow(draft: '');
      expect(p.notes.any((n) => n.contains('空')), isTrue);
    });
  });
}
