import '../../domain/coding_agent_tools.dart';
import '../../domain/coding_custom_prompt_id.dart';
import '../../domain/coding_custom_prompts.dart';
import '../../domain/coding_workspace_kind.dart';
import 'coding_assist_prompts.dart';

/// S17 用の組み込み既定テキスト（カスタム未適用）。
abstract final class CodingCustomPromptDefaults {
  static String text(
    CodingCustomPromptId id, {
    CodingWorkspaceKind kind = CodingWorkspaceKind.flutter,
  }) {
    switch (id) {
      case CodingCustomPromptId.systemFlutter:
        return CodingWorkspaceKindDetect.systemPrompt(
          CodingWorkspaceKind.flutter,
          applyCustom: false,
        );
      case CodingCustomPromptId.systemSwiftXcode:
        return CodingWorkspaceKindDetect.systemPrompt(
          CodingWorkspaceKind.swiftXcode,
          applyCustom: false,
        );
      case CodingCustomPromptId.systemReact:
        return CodingWorkspaceKindDetect.systemPrompt(
          CodingWorkspaceKind.react,
          applyCustom: false,
        );
      case CodingCustomPromptId.systemAndroid:
        return CodingWorkspaceKindDetect.systemPrompt(
          CodingWorkspaceKind.android,
          applyCustom: false,
        );
      case CodingCustomPromptId.systemPython:
        return CodingWorkspaceKindDetect.systemPrompt(
          CodingWorkspaceKind.python,
          applyCustom: false,
        );
      case CodingCustomPromptId.systemGeneric:
        return CodingWorkspaceKindDetect.systemPrompt(
          CodingWorkspaceKind.generic,
          applyCustom: false,
        );
      case CodingCustomPromptId.systemNovel:
        return CodingWorkspaceKindDetect.systemPrompt(
          CodingWorkspaceKind.novel,
          applyCustom: false,
        );
      case CodingCustomPromptId.symbolTools:
        return CodingWorkspaceKindDetect.symbolToolsFor(
          kind,
          applyCustom: false,
        );
      case CodingCustomPromptId.flutterRegression:
        return CodingWorkspaceKindDetect.flutterRegressionTestRuleBuiltIn;
      case CodingCustomPromptId.deliverable:
        return codingDeliverableSystemSuffixBuiltIn;
      case CodingCustomPromptId.deliverableClose:
        return codingDeliverableCloseSystemSuffixBuiltIn;
      case CodingCustomPromptId.errorAnalyze:
        return codingAssistErrorAnalyzePrompt(
          '',
          kind: kind,
          applyCustom: false,
        );
      case CodingCustomPromptId.errorAnalyzeAuto:
        return codingAssistErrorAnalyzePrompt(
          '',
          omitReadFile: true,
          kind: kind,
          applyCustom: false,
        );
      case CodingCustomPromptId.errorAnalyzeBodies:
        return codingAssistErrorAnalyzePrompt(
          '',
          omitReadFile: true,
          bodiesSupplied: true,
          kind: kind,
          applyCustom: false,
        );
      case CodingCustomPromptId.concise:
        return codingAssistConcisePrompt('', applyCustom: false);
      case CodingCustomPromptId.expectFileOutput:
        return codingAssistExpectFileOutputPrompt(
          '',
          kind: kind,
          applyCustom: false,
        );
      case CodingCustomPromptId.expectFixProposal:
        return codingAssistExpectFixProposalPrompt(
          '',
          kind: kind,
          applyCustom: false,
        );
      case CodingCustomPromptId.expectDocumentCreate:
        return codingAssistExpectDocumentCreatePrompt(
          '',
          applyCustom: false,
        );
      case CodingCustomPromptId.expectDocumentEdit:
        return codingAssistExpectDocumentEditPrompt(
          '',
          applyCustom: false,
        );
      case CodingCustomPromptId.programAnalyze:
        return codingAssistProgramAnalyzePrompt('', applyCustom: false);
      case CodingCustomPromptId.taskDecompose:
        return codingAssistTaskDecomposePrompt(
          '',
          kind: kind,
          applyCustom: false,
        );
      case CodingCustomPromptId.taskEvaluate:
        return codingAssistTaskEvaluatePrompt('', applyCustom: false);
      case CodingCustomPromptId.runFlutterVerify:
        return codingAssistRunFlutterVerifyPrompt('', applyCustom: false);
      case CodingCustomPromptId.flutterVerifyReport:
        return codingAssistFlutterVerifyReportPrompt(
          passed: true,
          commands: const [
            (
              label: 'flutter analyze',
              exitCode: 0,
              timedOut: false,
              log: 'No issues found!',
            ),
          ],
          applyCustom: false,
        );
      case CodingCustomPromptId.autoLoopContinue:
        return codingAssistAutoLoopContinuePrompt(
          lastBody: '（直前の内容の例）',
          currentBody: '（現在の内容の例）',
          applyCustom: false,
        );
    }
  }

  /// 編集中テキスト＋サンプル下書きで「適用後」の合成結果を返す。
  static String previewApplied({
    required CodingCustomPromptId id,
    required String promptText,
    required String sampleDraft,
    CodingWorkspaceKind kind = CodingWorkspaceKind.flutter,
  }) {
    final rules =
        promptText.trim().isEmpty ? text(id, kind: kind) : promptText;
    switch (id) {
      case CodingCustomPromptId.systemFlutter ||
          CodingCustomPromptId.systemSwiftXcode ||
          CodingCustomPromptId.systemReact ||
          CodingCustomPromptId.systemAndroid ||
          CodingCustomPromptId.systemPython ||
          CodingCustomPromptId.systemGeneric ||
          CodingCustomPromptId.systemNovel ||
          CodingCustomPromptId.symbolTools ||
          CodingCustomPromptId.flutterRegression ||
          CodingCustomPromptId.deliverable ||
          CodingCustomPromptId.deliverableClose:
        return rules;
      case CodingCustomPromptId.flutterVerifyReport:
        return CodingCustomPrompts.substitute(rules, {
          'verdict': '合格',
          'blocks': '### flutter analyze\n終了コード: 0\nNo issues found!',
        });
      case CodingCustomPromptId.autoLoopContinue:
        return CodingCustomPrompts.substitute(rules, {
          'lastBody': sampleDraft.trim().isEmpty
              ? '（直前の内容）'
              : sampleDraft.trim(),
          'currentBody': '（現在の内容）',
        });
      case CodingCustomPromptId.errorAnalyze ||
          CodingCustomPromptId.errorAnalyzeAuto ||
          CodingCustomPromptId.errorAnalyzeBodies:
        final body = sampleDraft.trim();
        if (body.isEmpty) return rules;
        return '【エラー文言】\n$body\n\n$rules';
      default:
        final body = sampleDraft.trim();
        if (body.isEmpty) return rules;
        return '$body\n\n$rules';
    }
  }
}
