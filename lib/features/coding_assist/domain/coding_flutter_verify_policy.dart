import 'coding_workspace_kind.dart';

/// 検証ループの局面。コマンド成否は [afterAnalyze]／[afterTest] で渡す。
enum CodingFlutterVerifyPhase {
  /// Agent ターンが落ち着いた直後（再提案キューは空）。
  afterTurn,

  /// `flutter analyze` の結果を受け取ったあと。
  afterAnalyze,

  /// `flutter test` の結果を受け取ったあと。
  afterTest,
}

/// 次に Bloc が取ってよい動作。
enum CodingFlutterVerifyAction {
  skip,
  runAnalyze,
  runTest,
  startFix,
  stopKeepAuto,
  success,
}

/// 打ち切り・保留の理由。報告文の切り替えに使う。
enum CodingFlutterVerifyStopReason {
  none,
  setsExhausted,
  noUpdateApplied,
  pendingAdd,
  timedOut,
  launchFailed,
  verifyOnlyFailed,
  notFlutter,
  packageInstall,
}

/// 判定入力。プロセス実行の結果はコマンド局面だけで使う。
class CodingFlutterVerifyInput {
  const CodingFlutterVerifyInput({
    required this.phase,
    required this.kind,
    required this.autoApplyEnabled,
    required this.updatesAppliedThisCycle,
    required this.updatesAppliedThisSet,
    required this.pendingAdd,
    required this.setsUsed,
    this.maxSets = CodingFlutterVerifyPolicy.maxSets,
    this.exitCode,
    this.timedOut = false,
    this.launchFailed = false,
    this.verifyRequested = false,
    this.packageInstallNeeded = false,
    this.documentOnly = false,
  });

  final CodingFlutterVerifyPhase phase;
  final CodingWorkspaceKind kind;
  final bool autoApplyEnabled;

  /// 人の送信以降に自動適用できた Update 件数。
  final int updatesAppliedThisCycle;

  /// 直近の修正セットで自動適用できた Update 件数。人の送信直後は周期と同じでよい。
  final int updatesAppliedThisSet;

  /// pending の Add File が残っている。
  final bool pendingAdd;

  /// 開始済みの修正セット数（0〜[maxSets]）。
  final int setsUsed;

  /// この実行で始めてよい修正セット数。
  final int maxSets;

  final int? exitCode;
  final bool timedOut;
  final bool launchFailed;

  /// ＋の「テストを実行」が付いた送信。書き込みが無くても検証する。
  final bool verifyRequested;

  /// `pubspec.yaml` のパッケージ追加、またはログが未インストールを示している。
  final bool packageInstallNeeded;

  /// 文書だけの＋。書き込みがあっても analyze／test に進まない。
  /// 「テストを実行」が同時なら [verifyRequested] 側を優先する。
  final bool documentOnly;
}

class CodingFlutterVerifyDecision {
  const CodingFlutterVerifyDecision(
    this.action, [
    this.reason = CodingFlutterVerifyStopReason.none,
  ]);

  final CodingFlutterVerifyAction action;
  final CodingFlutterVerifyStopReason reason;
}

/// Flutter 自動検証の分岐。副作用は持たない。
abstract final class CodingFlutterVerifyPolicy {
  static const maxSets = 3;

  static CodingFlutterVerifyDecision decide(CodingFlutterVerifyInput input) {
    if (input.phase == CodingFlutterVerifyPhase.afterTurn) {
      return _afterTurn(input);
    }
    return _afterCommand(input);
  }

  static CodingFlutterVerifyDecision _afterTurn(
    CodingFlutterVerifyInput input,
  ) {
    if (input.documentOnly && !input.verifyRequested) {
      return const CodingFlutterVerifyDecision(CodingFlutterVerifyAction.skip);
    }
    if (input.packageInstallNeeded &&
        (input.autoApplyEnabled || input.verifyRequested)) {
      return _packageInstallStop(input)!;
    }
    if (input.kind != CodingWorkspaceKind.flutter) {
      if (input.verifyRequested) {
        return const CodingFlutterVerifyDecision(
          CodingFlutterVerifyAction.stopKeepAuto,
          CodingFlutterVerifyStopReason.notFlutter,
        );
      }
      return const CodingFlutterVerifyDecision(CodingFlutterVerifyAction.skip);
    }
    if (!input.autoApplyEnabled && !input.verifyRequested) {
      return const CodingFlutterVerifyDecision(CodingFlutterVerifyAction.skip);
    }
    if (input.setsUsed > 0 && input.updatesAppliedThisSet <= 0) {
      // このセットで書き込みが無い。繰り返しを破棄して Patch も無いときは、
      // 次の flutter analyze に進まない。
      if (input.pendingAdd) {
        return const CodingFlutterVerifyDecision(
          CodingFlutterVerifyAction.stopKeepAuto,
          CodingFlutterVerifyStopReason.pendingAdd,
        );
      }
      if (!input.autoApplyEnabled) {
        return const CodingFlutterVerifyDecision(
          CodingFlutterVerifyAction.stopKeepAuto,
          CodingFlutterVerifyStopReason.verifyOnlyFailed,
        );
      }
      return const CodingFlutterVerifyDecision(
        CodingFlutterVerifyAction.stopKeepAuto,
        CodingFlutterVerifyStopReason.noUpdateApplied,
      );
    }
    if (input.updatesAppliedThisCycle <= 0 && !input.verifyRequested) {
      return const CodingFlutterVerifyDecision(CodingFlutterVerifyAction.skip);
    }
    if (input.pendingAdd) {
      return const CodingFlutterVerifyDecision(
        CodingFlutterVerifyAction.stopKeepAuto,
        CodingFlutterVerifyStopReason.pendingAdd,
      );
    }
    return const CodingFlutterVerifyDecision(
      CodingFlutterVerifyAction.runAnalyze,
    );
  }

  static CodingFlutterVerifyDecision _afterCommand(
    CodingFlutterVerifyInput input,
  ) {
    final packageStop = _packageInstallStop(input);
    if (packageStop != null) return packageStop;
    if (!input.autoApplyEnabled) {
      if (input.launchFailed) {
        return const CodingFlutterVerifyDecision(
          CodingFlutterVerifyAction.stopKeepAuto,
          CodingFlutterVerifyStopReason.launchFailed,
        );
      }
      if (input.timedOut) {
        return const CodingFlutterVerifyDecision(
          CodingFlutterVerifyAction.stopKeepAuto,
          CodingFlutterVerifyStopReason.timedOut,
        );
      }
      final code = input.exitCode ?? 1;
      if (code == 0) {
        if (input.phase == CodingFlutterVerifyPhase.afterAnalyze) {
          return const CodingFlutterVerifyDecision(
            CodingFlutterVerifyAction.runTest,
          );
        }
        return const CodingFlutterVerifyDecision(
          CodingFlutterVerifyAction.success,
        );
      }
      return const CodingFlutterVerifyDecision(
        CodingFlutterVerifyAction.stopKeepAuto,
        CodingFlutterVerifyStopReason.verifyOnlyFailed,
      );
    }
    if (input.launchFailed) {
      return const CodingFlutterVerifyDecision(
        CodingFlutterVerifyAction.stopKeepAuto,
        CodingFlutterVerifyStopReason.launchFailed,
      );
    }
    if (input.timedOut) {
      return const CodingFlutterVerifyDecision(
        CodingFlutterVerifyAction.stopKeepAuto,
        CodingFlutterVerifyStopReason.timedOut,
      );
    }
    final code = input.exitCode ?? 1;
    if (code == 0) {
      if (input.phase == CodingFlutterVerifyPhase.afterAnalyze) {
        return const CodingFlutterVerifyDecision(
          CodingFlutterVerifyAction.runTest,
        );
      }
      return const CodingFlutterVerifyDecision(
        CodingFlutterVerifyAction.success,
      );
    }
    if (input.setsUsed >= input.maxSets) {
      return const CodingFlutterVerifyDecision(
        CodingFlutterVerifyAction.stopKeepAuto,
        CodingFlutterVerifyStopReason.setsExhausted,
      );
    }
    return const CodingFlutterVerifyDecision(
      CodingFlutterVerifyAction.startFix,
    );
  }

  static CodingFlutterVerifyDecision? _packageInstallStop(
    CodingFlutterVerifyInput input,
  ) {
    if (!input.packageInstallNeeded) return null;
    return const CodingFlutterVerifyDecision(
      CodingFlutterVerifyAction.stopKeepAuto,
      CodingFlutterVerifyStopReason.packageInstall,
    );
  }
}

final RegExp _codingVerifyLogPath = RegExp(
  r'((?:[\w.-]+/)+[\w.-]+\.[A-Za-z0-9]+):\d+',
);

/// 検証ログに出た相対パス。出現順。同じパスは1回。
List<String> codingVerifyLogPaths(String log) {
  final out = <String>[];
  for (final match in _codingVerifyLogPath.allMatches(log)) {
    final path = match.group(1);
    if (path == null || path.isEmpty || path.contains('..')) continue;
    if (out.contains(path)) continue;
    out.add(path);
  }
  return out;
}

/// 修正ターンで先に渡す候補。未開封を先にし、開けなかったパスは除く。
List<String> codingVerifyPreloadPaths({
  required List<String> logPaths,
  required Set<String> opened,
  required Set<String> unopened,
}) {
  final fresh = <String>[];
  final known = <String>[];
  for (final raw in logPaths) {
    final path = raw.trim().replaceAll('\\', '/');
    if (path.isEmpty || unopened.contains(path)) continue;
    if (opened.contains(path)) {
      known.add(path);
    } else {
      fresh.add(path);
    }
  }
  return [...fresh, ...known];
}
