import 'package:flutter_test/flutter_test.dart';
import 'package:lmcode/features/coding_assist/domain/coding_agent_progress.dart';
import 'package:lmcode/features/coding_assist/domain/coding_flutter_verify_policy.dart';
import 'package:lmcode/features/coding_assist/domain/coding_verify_next_steps.dart';

void main() {
  group('CodingAgentProgress.stages', () {
    test('検証に進む見込みなら 4 段階を並べる', () {
      const p = CodingAgentProgress(CodingAgentPhase.apply);
      expect(p.stages(verifyExpected: true), CodingAgentPhase.verifyStages);
    });

    test('見込みが無ければ、いまの段階だけ', () {
      const p = CodingAgentProgress(CodingAgentPhase.generate);
      expect(p.stages(verifyExpected: false), [CodingAgentPhase.generate]);
    });

    test('analyze／test は見込みに関わらず 4 段階（検証が始まっている）', () {
      const p = CodingAgentProgress(CodingAgentPhase.test);
      expect(p.stages(verifyExpected: false), CodingAgentPhase.verifyStages);
    });

    test('報告は 4 段階のあとに付く', () {
      const p = CodingAgentProgress(CodingAgentPhase.report);
      expect(p.stages(verifyExpected: true).last, CodingAgentPhase.report);
      expect(p.stages(verifyExpected: true).length, 5);
    });

    test('修正セットの表示', () {
      const first = CodingAgentProgress(CodingAgentPhase.generate);
      expect(first.inFix, isFalse);
      const fix = CodingAgentProgress(
        CodingAgentPhase.generate,
        fixSet: 2,
        fixMax: 3,
      );
      expect(fix.inFix, isTrue);
      expect(fix.fixLabel, '修正 2/3');
    });
  });

  group('codingVerifyFirstError', () {
    test('flutter analyze の error 行', () {
      const log = '''
Analyzing app...

  info • Unused import • lib/a.dart:1:8 • unused_import
  error • The method 'foo' isn't defined • lib/b.dart:12:5 • undefined_method
  error • Another • lib/c.dart:3:1 • x
''';
      expect(
        codingVerifyFirstError(log),
        "The method 'foo' isn't defined • lib/b.dart:12:5 • undefined_method",
      );
    });

    test('flutter test の失敗行', () {
      const log = '00:02 +3 -1: foo [E]\n  Expected: 1\nSome tests failed.';
      expect(codingVerifyFirstError(log), contains('[E]'));
    });

    test('見つからなければ null、長い行は切る', () {
      expect(codingVerifyFirstError('all good'), isNull);
      final long = 'error • ${'x' * 300}';
      expect(codingVerifyFirstError(long, maxChars: 20)!.length, 21);
    });
  });

  group('codingVerifyNextStepsText', () {
    String text(
      CodingFlutterVerifyStopReason reason, {
      bool autoOn = true,
      int maxSets = 3,
      String? log,
    }) => codingVerifyNextStepsText(
      reason: reason,
      autoOn: autoOn,
      maxSets: maxSets,
      log: log,
      command: 'flutter analyze',
    );

    test('打ち切りは最初のエラーと手順を返す', () {
      final t = text(
        CodingFlutterVerifyStopReason.setsExhausted,
        log: 'error • 型が合わない • lib/a.dart:1:1 • x',
      );
      expect(t, startsWith('【次にやること】'));
      expect(t, contains('最初のエラー（flutter analyze）: 型が合わない'));
      expect(t, contains('1. '));
    });

    test('運用パターンの案内は、検証セットが 4 未満のときだけ', () {
      expect(
        text(CodingFlutterVerifyStopReason.setsExhausted, maxSets: 3),
        contains('深掘り'),
      );
      expect(
        text(CodingFlutterVerifyStopReason.setsExhausted, maxSets: 4),
        isNot(contains('深掘り')),
      );
    });

    test('自動実行 OFF の失敗は、ON を案内する', () {
      expect(
        text(CodingFlutterVerifyStopReason.verifyOnlyFailed, autoOn: false),
        contains('自動実行を ON'),
      );
      expect(
        text(CodingFlutterVerifyStopReason.verifyOnlyFailed, autoOn: true),
        isNot(contains('自動実行を ON')),
      );
    });

    test('次の手段が無い理由は空', () {
      expect(text(CodingFlutterVerifyStopReason.notFlutter), isEmpty);
      expect(text(CodingFlutterVerifyStopReason.none), isEmpty);
    });

    test('他の理由はすべて手順を持つ', () {
      for (final reason in CodingFlutterVerifyStopReason.values) {
        if (reason == CodingFlutterVerifyStopReason.none ||
            reason == CodingFlutterVerifyStopReason.notFlutter) {
          continue;
        }
        expect(text(reason), contains('1. '), reason: '$reason');
      }
    });

    test('繰り返し停止にも手順がある', () {
      expect(codingRepeatedStopNextStepsText(), contains('3. '));
    });
  });
}
