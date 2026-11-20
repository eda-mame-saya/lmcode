import 'package:equatable/equatable.dart';

/// 自動実行の段階（ステータスバーの進行表示用）。
enum CodingAgentPhase {
  generate('生成'),
  apply('適用'),
  analyze('analyze'),
  test('test'),
  report('報告');

  const CodingAgentPhase(this.label);

  final String label;

  /// Flutter の自動検証で通る段階（報告は検証後だけ）。
  static const verifyStages = [generate, apply, analyze, test];
}

/// いまどの段階か。自動修正中は何セット目かも持つ。
class CodingAgentProgress extends Equatable {
  const CodingAgentProgress(this.phase, {this.fixSet = 0, this.fixMax = 0});

  final CodingAgentPhase phase;

  /// 自動修正の何セット目か。0 は初回（修正ループの外）。
  final int fixSet;

  /// 修正セットの上限。
  final int fixMax;

  bool get inFix => fixSet > 0 && fixMax > 0;

  String get fixLabel => '修正 $fixSet/$fixMax';

  /// 表示する段階の並び。
  ///
  /// [verifyExpected] は自動検証に進む見込み（自動実行 ON の Flutter）。
  /// 見込みが無いときは、いまの段階だけ見せる。
  List<CodingAgentPhase> stages({required bool verifyExpected}) {
    if (phase == CodingAgentPhase.report) {
      return [...CodingAgentPhase.verifyStages, CodingAgentPhase.report];
    }
    if (verifyExpected || phase == CodingAgentPhase.analyze ||
        phase == CodingAgentPhase.test) {
      return CodingAgentPhase.verifyStages;
    }
    return [phase];
  }

  @override
  List<Object?> get props => [phase, fixSet, fixMax];
}
