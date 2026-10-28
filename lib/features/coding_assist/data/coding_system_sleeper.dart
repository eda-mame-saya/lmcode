import 'dart:io';

/// macOS をスリープさせる。失敗時は利用者向けの文言を返す。
abstract final class CodingSystemSleeper {
  static Future<String?> sleepNow() async {
    if (!Platform.isMacOS) {
      return 'スリープは macOS でのみ実行します';
    }
    final pmset = await Process.run('/usr/bin/pmset', ['sleepnow']);
    if (pmset.exitCode == 0) return null;
    final osa = await Process.run('/usr/bin/osascript', [
      '-e',
      'tell application "System Events" to sleep',
    ]);
    if (osa.exitCode == 0) return null;
    final detail = '${pmset.stderr}'.trim();
    if (detail.isEmpty) return 'スリープできませんでした';
    return 'スリープできませんでした: $detail';
  }
}
