import 'package:equatable/equatable.dart';

import 'coding_harness_settings.dart';
import 'coding_workspace_kind.dart';

/// 運用パターンの段階（軽快／標準／深掘り）。
///
/// 値の正本: `document/基本設計/13_ハーネス数値棚卸し_パターン分け一覧.md`。
/// 根拠・見直し手順: `document/基本設計/14_ハーネス初期値の根拠_決定記録.md`。
enum CodingPatternLevel {
  light('light', '軽快'),
  standard('standard', '標準'),
  deep('deep', '深掘り');

  const CodingPatternLevel(this.id, this.label);

  /// SharedPreferences 用。
  final String id;

  /// UI 表示名。
  final String label;

  static CodingPatternLevel fromId(String? id) {
    for (final level in values) {
      if (level.id == id) return level;
    }
    return CodingPatternLevel.standard;
  }
}

/// パターンの系統。文章とコーディングは別プロファイル（14 DR-01）。
enum CodingPatternSystem {
  coding('coding', 'コーディング'),
  writing('writing', '文章');

  const CodingPatternSystem(this.id, this.label);

  final String id;
  final String label;

  static CodingPatternSystem? tryFromId(String? id) {
    for (final system in values) {
      if (system.id == id) return system;
    }
    return null;
  }
}

/// Web 参照の強さ（14 DR-14）。**現状は未適用**（機能側が未実装）。将来の接続用。
enum CodingWebMode { off, onDemand, failOnly, docs, docsCommunity }

/// ローカル RAG の深さ（14 DR-14）。**現状は未適用**（11 の R1〜R4 が未実装）。
enum CodingRagDepth { recent, keyword, workspace, deep }

/// ユーザーが選ぶ運用パターン（系統ごとに 1 つ）。
class CodingPatternSelection extends Equatable {
  const CodingPatternSelection({
    this.coding = CodingPatternLevel.standard,
    this.writing = CodingPatternLevel.standard,
  });

  static const defaults = CodingPatternSelection();

  final CodingPatternLevel coding;
  final CodingPatternLevel writing;

  CodingPatternLevel levelOf(CodingPatternSystem system) => switch (system) {
    CodingPatternSystem.coding => coding,
    CodingPatternSystem.writing => writing,
  };

  CodingPatternSelection withLevel(
    CodingPatternSystem system,
    CodingPatternLevel level,
  ) => switch (system) {
    CodingPatternSystem.coding => CodingPatternSelection(
      coding: level,
      writing: writing,
    ),
    CodingPatternSystem.writing => CodingPatternSelection(
      coding: coding,
      writing: level,
    ),
  };

  @override
  List<Object?> get props => [coding, writing];
}

/// パターンが束ねる値一式。適用時に ctx／thinking／ハーネスへ展開する。
class CodingPatternProfile extends Equatable {
  const CodingPatternProfile({
    required this.system,
    required this.level,
    required this.contextSize,
    required this.thinkingEnabled,
    required this.harness,
    required this.webMode,
    required this.ragDepth,
    required this.summary,
  });

  final CodingPatternSystem system;
  final CodingPatternLevel level;

  /// `llama-server --ctx-size`。変更時はサーバ再起動。
  final int contextSize;

  /// thinking。コーディングは常に OFF（14 DR-07）。
  final bool thinkingEnabled;

  /// 展開後のハーネス全値。
  final CodingHarnessSettings harness;

  /// 将来接続用（現状は未適用）。
  final CodingWebMode webMode;

  /// 将来接続用（現状は未適用）。
  final CodingRagDepth ragDepth;

  /// UI の説明（実際に効いている項目のみ記載）。
  final String summary;

  @override
  List<Object?> get props => [
    system,
    level,
    contextSize,
    thinkingEnabled,
    harness,
    webMode,
    ragDepth,
    summary,
  ];
}

/// 運用パターンの定義。数値は 13 の一覧表と一致させること。
abstract final class CodingPatternProfiles {
  /// 既定ハーネスをベースに、パターン値だけを上書きして返す。
  static CodingPatternProfile of(
    CodingPatternSystem system,
    CodingPatternLevel level,
  ) => switch (system) {
    CodingPatternSystem.coding => _coding(level),
    CodingPatternSystem.writing => _writing(level),
  };

  /// ワークスペース種別から系統を決める（14 DR-15）。小説のみ文章。
  static CodingPatternSystem systemFor(CodingWorkspaceKind? kind) =>
      kind == CodingWorkspaceKind.novel
      ? CodingPatternSystem.writing
      : CodingPatternSystem.coding;

  static const _ctxLight = 32768;
  static const _ctxStandard = 65536;
  static const _ctxDeep = 131072;

  static CodingPatternProfile _coding(CodingPatternLevel level) {
    const base = CodingHarnessSettings.defaults;
    return switch (level) {
      CodingPatternLevel.light => CodingPatternProfile(
        system: CodingPatternSystem.coding,
        level: level,
        contextSize: _ctxLight,
        thinkingEnabled: false,
        harness: base.copyWith(
          maxTokens: 4096,
          replyReserveRatio: 0.15,
          reasoningAbortChars: 4000,
          maxAgentSteps: 6,
          maxAgentStepsAuto: 6,
          maxReadChars: 13000,
          openFileMaxChars: 13000,
          readFilesPerBatch: 3,
          toolResultClipChars: 6000,
          reproposeMaxChars: 12000,
          systemTreeChars: 3000,
          keepRecentUserTurns: 2,
          compactKeepRecentUserTurns: 1,
          summaryPurposeCount: 3,
          maxVerifySets: 2,
        ),
        webMode: CodingWebMode.failOnly,
        ragDepth: CodingRagDepth.recent,
        summary: '待たせない。小さな修正・質問向け。ctx 32k・短いループ・検証は薄め。',
      ),
      CodingPatternLevel.standard => CodingPatternProfile(
        system: CodingPatternSystem.coding,
        level: level,
        contextSize: _ctxStandard,
        thinkingEnabled: false,
        harness: base.copyWith(
          maxTokens: 8192,
          replyReserveRatio: 0.15,
          reasoningAbortChars: 4000,
          maxAgentSteps: 12,
          maxAgentStepsAuto: 12,
          maxReadChars: 26000,
          openFileMaxChars: 26000,
          readFilesPerBatch: 5,
          toolResultClipChars: 12000,
          reproposeMaxChars: 24000,
          systemTreeChars: 6000,
          keepRecentUserTurns: 3,
          compactKeepRecentUserTurns: 1,
          summaryPurposeCount: 5,
          maxVerifySets: 3,
        ),
        webMode: CodingWebMode.docs,
        ragDepth: CodingRagDepth.workspace,
        summary: '日常の実装・修正向け。ctx 64k・標準のループと検証（最大 3 セット）。',
      ),
      CodingPatternLevel.deep => CodingPatternProfile(
        system: CodingPatternSystem.coding,
        level: level,
        contextSize: _ctxDeep,
        thinkingEnabled: false,
        harness: base.copyWith(
          maxTokens: 12288,
          replyReserveRatio: 0.12,
          reasoningAbortChars: 4000,
          maxAgentSteps: 16,
          maxAgentStepsAuto: 16,
          maxReadChars: 52000,
          openFileMaxChars: 52000,
          readFilesPerBatch: 5,
          toolResultClipChars: 24000,
          reproposeMaxChars: 48000,
          systemTreeChars: 8000,
          keepRecentUserTurns: 4,
          compactKeepRecentUserTurns: 2,
          summaryPurposeCount: 8,
          maxVerifySets: 4,
        ),
        webMode: CodingWebMode.docsCommunity,
        ragDepth: CodingRagDepth.deep,
        summary: '横断調査・根拠厚め。ctx 128k・読取と履歴を厚く・検証 4 セット。思考は使いません。',
      ),
    };
  }

  static CodingPatternProfile _writing(CodingPatternLevel level) {
    // 文章は日本語中心のため charsPerToken=1.5（14 DR-11）。
    final base = CodingHarnessSettings.defaults.copyWith(
      temperature: 0.7,
      charsPerToken: 1.5,
      thinkingGuideChars: 800,
      reasoningAbortChars: 12000,
      replyReserveRatio: 0.15,
    );
    return switch (level) {
      CodingPatternLevel.light => CodingPatternProfile(
        system: CodingPatternSystem.writing,
        level: level,
        contextSize: _ctxLight,
        thinkingEnabled: false,
        harness: base.copyWith(
          maxTokens: 4096,
          maxAgentSteps: 4,
          maxAgentStepsAuto: 4,
          maxReadChars: 9800,
          openFileMaxChars: 9800,
          readFilesPerBatch: 3,
          toolResultClipChars: 4500,
          reproposeMaxChars: 9000,
          systemTreeChars: 2200,
          keepRecentUserTurns: 3,
          compactKeepRecentUserTurns: 1,
          summaryPurposeCount: 5,
        ),
        webMode: CodingWebMode.off,
        ragDepth: CodingRagDepth.keyword,
        summary: '短文・言い換え向け。ctx 32k・短いループ。思考は使いません。',
      ),
      CodingPatternLevel.standard => CodingPatternProfile(
        system: CodingPatternSystem.writing,
        level: level,
        contextSize: _ctxStandard,
        thinkingEnabled: false,
        harness: base.copyWith(
          maxTokens: 8192,
          maxAgentSteps: 8,
          maxAgentStepsAuto: 8,
          maxReadChars: 19600,
          openFileMaxChars: 19600,
          readFilesPerBatch: 5,
          toolResultClipChars: 9000,
          reproposeMaxChars: 18000,
          systemTreeChars: 4500,
          keepRecentUserTurns: 4,
          compactKeepRecentUserTurns: 2,
          summaryPurposeCount: 8,
        ),
        webMode: CodingWebMode.onDemand,
        ragDepth: CodingRagDepth.workspace,
        summary: '通常の文書作成・修正向け。ctx 64k・履歴を長めに保持。思考は使いません。',
      ),
      CodingPatternLevel.deep => CodingPatternProfile(
        system: CodingPatternSystem.writing,
        level: level,
        contextSize: _ctxDeep,
        thinkingEnabled: true,
        harness: base.copyWith(
          maxTokens: 16384,
          maxAgentSteps: 12,
          maxAgentStepsAuto: 12,
          maxReadChars: 39000,
          openFileMaxChars: 39000,
          readFilesPerBatch: 5,
          toolResultClipChars: 18000,
          reproposeMaxChars: 36000,
          systemTreeChars: 8000,
          keepRecentUserTurns: 6,
          compactKeepRecentUserTurns: 3,
          summaryPurposeCount: 10,
        ),
        webMode: CodingWebMode.docsCommunity,
        ragDepth: CodingRagDepth.deep,
        summary: '長文の一貫・構成向け。ctx 128k・履歴を厚く保持。思考を使います（切替時は再起動）。',
      ),
    };
  }
}
