import 'dart:io';

import 'package:path/path.dart' as p;

/// システム RAM のスナップショット（S16 表示用）。
final class CodingMemorySnapshot {
  const CodingMemorySnapshot({
    required this.usagePercent,
    required this.topProcesses,
  });

  /// 0〜100。取得失敗時は null。
  final int? usagePercent;
  final List<CodingProcessMemory> topProcesses;
}

final class CodingProcessMemory {
  const CodingProcessMemory({
    required this.name,
    required this.rssBytes,
  });

  final String name;
  final int rssBytes;

  String get rssLabel {
    if (rssBytes >= 1024 * 1024 * 1024) {
      return '${(rssBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (rssBytes >= 1024 * 1024) {
      return '${(rssBytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(rssBytes / 1024).toStringAsFixed(0)} KB';
  }
}

/// OS 別コマンドから RAM 使用率と上位プロセスを取る。
///
/// * macOS: `vm_stat` / `ps`
/// * Windows: PowerShell（`Win32_OperatingSystem` / `Get-Process`）
abstract final class CodingSystemMemory {
  static const topProcessLimit = 30;

  static Future<CodingMemorySnapshot> sample({
    bool includeTopProcesses = false,
  }) async {
    try {
      if (Platform.isMacOS) {
        final percent = await _macUsagePercent();
        final tops = includeTopProcesses
            ? await _macTopProcesses(limit: topProcessLimit)
            : const <CodingProcessMemory>[];
        return CodingMemorySnapshot(usagePercent: percent, topProcesses: tops);
      }
      if (Platform.isWindows) {
        final percent = await _windowsUsagePercent();
        final tops = includeTopProcesses
            ? await _windowsTopProcesses(limit: topProcessLimit)
            : const <CodingProcessMemory>[];
        return CodingMemorySnapshot(usagePercent: percent, topProcesses: tops);
      }
      return const CodingMemorySnapshot(usagePercent: null, topProcesses: []);
    } catch (_) {
      return const CodingMemorySnapshot(usagePercent: null, topProcesses: []);
    }
  }

  static Future<int?> _macUsagePercent() async {
    final totalOut = await Process.run('sysctl', ['-n', 'hw.memsize']);
    if (totalOut.exitCode != 0) return null;
    final total = int.tryParse((totalOut.stdout as String).trim());
    if (total == null || total <= 0) return null;

    final vmOut = await Process.run('vm_stat', []);
    if (vmOut.exitCode != 0) return null;
    final text = vmOut.stdout as String;
    final pageSize = _parsePageSize(text) ?? 16384;
    final pages = _parseVmStatPages(text);

    // Activity Monitor に近い「使用中」: active + wired + compressor
    final usedPages = (pages['Pages active'] ?? 0) +
        (pages['Pages wired down'] ?? 0) +
        (pages['Pages occupied by compressor'] ?? 0);
    final used = usedPages * pageSize;
    final ratio = (used / total).clamp(0.0, 1.0);
    return (ratio * 100).round();
  }

  static int? _parsePageSize(String text) {
    final m = RegExp(r'page size of (\d+) bytes').firstMatch(text);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  static Map<String, int> _parseVmStatPages(String text) {
    final out = <String, int>{};
    final re = RegExp(r'^(.+?):\s+(\d+)\.?$', multiLine: true);
    for (final m in re.allMatches(text)) {
      final key = m.group(1)!.trim();
      final n = int.tryParse(m.group(2)!);
      if (n != null) out[key] = n;
    }
    return out;
  }

  static Future<List<CodingProcessMemory>> _macTopProcesses({
    required int limit,
  }) async {
    final result = await Process.run('ps', ['-axo', 'rss=,comm=']);
    if (result.exitCode != 0) return const [];
    final lines = (result.stdout as String).split('\n');
    final byName = <String, int>{};

    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final match = RegExp(r'^(\d+)\s+(.+)$').firstMatch(line);
      if (match == null) continue;
      final rssKb = int.tryParse(match.group(1)!);
      if (rssKb == null || rssKb <= 0) continue;
      final name = _appDisplayName(match.group(2)!);
      if (name.isEmpty) continue;
      byName[name] = (byName[name] ?? 0) + rssKb * 1024;
    }

    final sorted = byName.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final e in sorted.take(limit))
        CodingProcessMemory(name: e.key, rssBytes: e.value),
    ];
  }

  /// `.app` 名優先。Helper は本体名に寄せて合算しやすくする。
  static String _appDisplayName(String comm) {
    final trimmed = comm.trim();
    if (trimmed.isEmpty) return '';
    final app = RegExp(r'/([^/]+)\.app/').firstMatch(trimmed);
    if (app != null) return app.group(1)!;

    var head = trimmed;
    final colon = head.indexOf(':');
    if (colon >= 0) head = head.substring(0, colon).trim();
    if (head.startsWith('/')) {
      head = p.basename(head);
    }
    head = head.replaceFirst(RegExp(r'\s+Helper(\s*\(.*\))?$'), '').trim();
    return head.isEmpty ? p.basename(trimmed) : head;
  }

  static Future<int?> _windowsUsagePercent() async {
    final out = await _runPowerShell(
      r"(Get-CimInstance Win32_OperatingSystem | "
      r"ForEach-Object { '{0}|{1}' -f $_.TotalVisibleMemorySize, $_.FreePhysicalMemory })",
    );
    if (out == null) return null;
    final parts = out.trim().split('|');
    if (parts.length < 2) return null;
    final totalKb = int.tryParse(parts[0].trim());
    final freeKb = int.tryParse(parts[1].trim());
    if (totalKb == null || freeKb == null || totalKb <= 0) return null;
    final usedKb = (totalKb - freeKb).clamp(0, totalKb);
    return ((usedKb / totalKb) * 100).round();
  }

  static Future<List<CodingProcessMemory>> _windowsTopProcesses({
    required int limit,
  }) async {
    final out = await _runPowerShell(
      'Get-Process | Sort-Object WorkingSet64 -Descending | '
      'Select-Object -First $limit | '
      r"ForEach-Object { '{0}|{1}' -f $_.WorkingSet64, $_.ProcessName }",
    );
    if (out == null || out.trim().isEmpty) return const [];

    final byName = <String, int>{};
    for (final raw in out.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final sep = line.indexOf('|');
      if (sep <= 0) continue;
      final rss = int.tryParse(line.substring(0, sep).trim());
      final name = line.substring(sep + 1).trim();
      if (rss == null || rss <= 0 || name.isEmpty) continue;
      byName[name] = (byName[name] ?? 0) + rss;
    }

    final sorted = byName.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final e in sorted.take(limit))
        CodingProcessMemory(name: e.key, rssBytes: e.value),
    ];
  }

  /// PowerShell を非対話で実行し、標準出力を返す。失敗時は null。
  static Future<String?> _runPowerShell(String command) async {
    final result = await Process.run(
      'powershell',
      <String>[
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        command,
      ],
      runInShell: false,
    );
    if (result.exitCode != 0) return null;
    final stdout = result.stdout;
    if (stdout is! String) return null;
    return stdout;
  }
}
