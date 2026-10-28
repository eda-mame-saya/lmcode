/// 自動実行後に Mac をスリープする設定（S16 ツールバー）。
final class CodingAutoSleepSettings {
  const CodingAutoSleepSettings({
    this.sleepWhenFinished = false,
    this.sleepAfterMinutes = 0,
  });

  /// 自動実行の処理が終わったら停止してスリープする。
  final bool sleepWhenFinished;

  /// 開始からこの分数で停止してスリープする。0 は時間指定なし。
  final int sleepAfterMinutes;

  static const maxMinutes = 240;

  bool get enabled => sleepWhenFinished || sleepAfterMinutes > 0;

  CodingAutoSleepSettings normalized() {
    final minutes = sleepAfterMinutes <= 0
        ? 0
        : sleepAfterMinutes.clamp(1, maxMinutes);
    return CodingAutoSleepSettings(
      sleepWhenFinished: sleepWhenFinished,
      sleepAfterMinutes: minutes,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CodingAutoSleepSettings &&
        other.sleepWhenFinished == sleepWhenFinished &&
        other.sleepAfterMinutes == sleepAfterMinutes;
  }

  @override
  int get hashCode => Object.hash(sleepWhenFinished, sleepAfterMinutes);
}

/// 自動実行の周期が終わったとき、スリープするか。
abstract final class CodingAutoSleepPolicy {
  static bool sleepOnCycleEnd({
    required CodingAutoSleepSettings settings,
    required bool armed,
    required bool deadlineReached,
    required bool stoppedByUser,
  }) {
    if (!armed || !settings.enabled) return false;
    if (deadlineReached) return true;
    if (stoppedByUser) return false;
    return settings.sleepWhenFinished;
  }
}
