import 'package:flutter_test/flutter_test.dart';
import 'package:lmcode/features/coding_assist/domain/coding_agent_tools.dart';
import 'package:lmcode/features/coding_assist/domain/coding_harness_settings.dart';
import 'package:lmcode/features/coding_assist/domain/coding_pattern.dart';
import 'package:lmcode/features/coding_assist/domain/coding_workspace_kind.dart';

/// 13_ハーネス数値棚卸し_パターン分け一覧.md の採用値と一致していること。
void main() {
  CodingPatternProfile p(CodingPatternSystem s, CodingPatternLevel l) =>
      CodingPatternProfiles.of(s, l);

  group('CodingPatternProfiles', () {
    test('coding: ctx / steps / verify / thinking', () {
      const c = CodingPatternSystem.coding;
      expect(
        [for (final l in CodingPatternLevel.values) p(c, l).contextSize],
        [32768, 65536, 131072],
      );
      expect(
        [
          for (final l in CodingPatternLevel.values)
            p(c, l).harness.maxAgentSteps,
        ],
        [6, 12, 16],
      );
      expect(
        [
          for (final l in CodingPatternLevel.values)
            p(c, l).harness.maxVerifySets,
        ],
        [2, 3, 4],
      );
      expect(
        [for (final l in CodingPatternLevel.values) p(c, l).harness.maxTokens],
        [4096, 8192, 12288],
      );
      // コーディングは thinking 常時 OFF（14 DR-07）。
      for (final l in CodingPatternLevel.values) {
        expect(p(c, l).thinkingEnabled, isFalse);
      }
    });

    test('writing: thinking は深掘りのみ', () {
      const w = CodingPatternSystem.writing;
      expect(p(w, CodingPatternLevel.light).thinkingEnabled, isFalse);
      expect(p(w, CodingPatternLevel.standard).thinkingEnabled, isFalse);
      expect(p(w, CodingPatternLevel.deep).thinkingEnabled, isTrue);
      expect(p(w, CodingPatternLevel.deep).harness.maxTokens, 16384);
      expect(p(w, CodingPatternLevel.standard).harness.charsPerToken, 1.5);
      expect(p(w, CodingPatternLevel.standard).harness.temperature, 0.7);
    });

    test('steps は maxAgentSteps と maxAgentStepsAuto が一致する', () {
      for (final s in CodingPatternSystem.values) {
        for (final l in CodingPatternLevel.values) {
          final h = p(s, l).harness;
          expect(h.maxAgentSteps, h.maxAgentStepsAuto, reason: '$s $l');
          expect(h.maxReadChars, h.openFileMaxChars, reason: '$s $l');
        }
      }
    });

    test('normalized() で値が変わらない（クランプされない）', () {
      for (final s in CodingPatternSystem.values) {
        for (final l in CodingPatternLevel.values) {
          final h = p(s, l).harness;
          expect(h.normalized(), h, reason: '$s $l');
        }
      }
    });

    test('toJson → fromJson で往復できる', () {
      final h = p(CodingPatternSystem.coding, CodingPatternLevel.light).harness;
      final json = Map<String, dynamic>.from(h.toJson());
      expect(CodingHarnessSettings.fromJson(json), h);
    });

    test('1 回の読取予算が ctx の半分以内に収まる', () {
      for (final s in CodingPatternSystem.values) {
        for (final l in CodingPatternLevel.values) {
          final prof = p(s, l);
          final h = prof.harness;
          final budget = codingReadBudgetChars(
            contextSize: prof.contextSize,
            charsPerToken: h.charsPerToken,
            ratio: h.readBudgetRatio,
          );
          expect(budget, isNotNull);
          expect(budget, lessThanOrEqualTo(prof.contextSize * h.charsPerToken));
          // 1 ファイル上限は予算より小さい（1 回目の読取は必ず通る）。
          expect(h.maxReadChars, lessThan(budget!), reason: '$s $l');
        }
      }
    });

    test('systemFor: 小説のみ文章', () {
      expect(
        CodingPatternProfiles.systemFor(CodingWorkspaceKind.novel),
        CodingPatternSystem.writing,
      );
      expect(CodingPatternProfiles.systemFor(null), CodingPatternSystem.coding);
    });
  });

  group('CodingPatternSelection', () {
    test('既定は標準 / 標準、withLevel は系統ごと', () {
      const d = CodingPatternSelection.defaults;
      expect(d.coding, CodingPatternLevel.standard);
      expect(d.writing, CodingPatternLevel.standard);
      final next = d.withLevel(
        CodingPatternSystem.writing,
        CodingPatternLevel.deep,
      );
      expect(
        next.levelOf(CodingPatternSystem.writing),
        CodingPatternLevel.deep,
      );
      expect(
        next.levelOf(CodingPatternSystem.coding),
        CodingPatternLevel.standard,
      );
    });
  });

  group('codingReadBudgetChars', () {
    test('ctx × cpt × ratio（切り捨て）', () {
      expect(
        codingReadBudgetChars(contextSize: 65536, charsPerToken: 2, ratio: 0.5),
        65536,
      );
    });
    test('無効値は null', () {
      expect(
        codingReadBudgetChars(contextSize: 0, charsPerToken: 2, ratio: 0.5),
        isNull,
      );
      expect(
        codingReadBudgetChars(contextSize: 1000, charsPerToken: 2, ratio: 0),
        isNull,
      );
    });
  });
}
