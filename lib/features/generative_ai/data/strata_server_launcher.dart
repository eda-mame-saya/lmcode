import 'dart:async';
import 'dart:io';

import '../../api_settings/domain/entities/strata_connection_settings.dart';
import 'strata_runtime_paths.dart';

/// Strata（`strata serve`）の起動・待機・終了。
///
/// llama-server と同様にアプリが起動したプロセスのみ管理する。
/// 既定ポートは [StrataPresets.defaultPort]（8090）。`--port` で上書きする。
class StrataServerLauncher {
  StrataServerLauncher();

  static Process? _ownedProcess;
  static int? _ownedPid;
  static _StrataLaunchFingerprint? _ownedFingerprint;
  static String? _resolvedModelId;
  static int? _resolvedMaxContext;

  static final _pidFile = File(
    '${Directory.systemTemp.path}/lmcode_strata_server.pid',
  );

  bool get hasOwnedProcess => _ownedPid != null || _ownedProcess != null;

  /// 直近起動で解決した API model id（空なら未解決）。
  String? get resolvedModelId => _resolvedModelId;

  /// run config の `--max-context`（未解決なら null）。
  int? get resolvedMaxContext => _resolvedMaxContext;

  /// ON なら起動／設定差分なら再起動。OFF なら所有プロセスを停止。
  Future<void> applySettings({
    required StrataConnectionSettings settings,
    required Future<bool> Function(StrataConnectionSettings settings)
        isHealthy,
    StrataConnectionSettings? previous,
    void Function(String message)? onStatus,
    bool waitForHealth = true,
  }) async {
    if (!settings.enabled) {
      if (hasOwnedProcess) {
        onStatus?.call('Strata は OFF のため停止します');
      }
      await stopOwnedProcess();
      _resolvedModelId = null;
      _resolvedMaxContext = null;
      return;
    }

    final restartRelevantChanged = previous != null &&
        _StrataLaunchFingerprint.fromSettings(previous) !=
            _StrataLaunchFingerprint.fromSettings(settings);

    await ensureRunning(
      settings: settings,
      isHealthy: () => isHealthy(settings),
      onStatus: onStatus,
      waitForHealth: waitForHealth,
      forceRestart: restartRelevantChanged,
    );
  }

  Future<void> ensureRunning({
    required StrataConnectionSettings settings,
    required Future<bool> Function() isHealthy,
    void Function(String message)? onStatus,
    bool waitForHealth = true,
    bool forceRestart = false,
  }) async {
    final cli = await StrataRuntimePaths.resolveCliPath(
      override: settings.cliPath,
    );
    if (cli == null) {
      await stopOwnedProcess();
      throw StateError(
        'strata CLI が見つかりません。'
        ' /Applications/Strata.app を導入するか、CLI パスを設定してください。',
      );
    }

    final runConfig = await StrataRuntimePaths.resolveRunConfigPath(
      override: settings.runConfigPath,
      cliPath: cli,
    );
    if (runConfig == null) {
      await stopOwnedProcess();
      throw StateError(
        'Strata の run config が見つかりません。'
        ' 先に Strata アプリでモデルを導入してください。',
      );
    }

    final modelFromConfig =
        await StrataRuntimePaths.readModelNameFromRunConfig(runConfig);
    _resolvedMaxContext = await _resolveMaxContext(
      runConfigPath: runConfig,
      cliPath: cli,
    );
    final fingerprint = _StrataLaunchFingerprint.fromSettings(
      settings,
      cliPath: cli,
      runConfigPath: runConfig,
    );

    final healthy = await isHealthy();
    final ownedMatches = hasOwnedProcess && _ownedFingerprint == fingerprint;
    final recordedPid = await _readPidFile();

    if (!forceRestart) {
      if (ownedMatches && healthy) {
        _resolvedModelId = settings.modelId.trim().isNotEmpty
            ? settings.modelId.trim()
            : modelFromConfig;
        return;
      }
      if (!hasOwnedProcess && healthy && recordedPid != null) {
        _ownedPid = recordedPid;
        _ownedFingerprint = fingerprint;
        _resolvedModelId = settings.modelId.trim().isNotEmpty
            ? settings.modelId.trim()
            : modelFromConfig;
        onStatus?.call('既存の Strata に再接続しました（${settings.baseUrl}）');
        return;
      }
      if (healthy && !hasOwnedProcess && recordedPid == null) {
        // 手動起動分は触らない
        _resolvedModelId = settings.modelId.trim().isNotEmpty
            ? settings.modelId.trim()
            : modelFromConfig;
        onStatus?.call('Strata は既に応答しています（${settings.baseUrl}）');
        return;
      }
    }

    if (hasOwnedProcess || recordedPid != null) {
      onStatus?.call('Strata を再起動します…');
      await stopOwnedProcess();
    }

    final listenHost = _listenHost(settings);
    onStatus?.call(
      'Strata を起動しています（$listenHost:${settings.port}）…',
    );

    try {
      final process = await Process.start(
        cli,
        <String>[
          'serve',
          '--profile',
          runConfig,
          '--host',
          listenHost,
          '--port',
          '${settings.port}',
          '--shutdown-timeout',
          '15',
        ],
        workingDirectory: File(cli).parent.path,
        environment: {
          ...Platform.environment,
          if (!Platform.isWindows)
            'PATH':
                '/opt/homebrew/bin:/usr/local/bin:${Platform.environment['PATH'] ?? ''}',
          'LMCODE_PARENT_PID': '$pid',
        },
        mode: ProcessStartMode.normal,
      );
      _ownedProcess = process;
      _ownedPid = process.pid;
      _ownedFingerprint = fingerprint;
      _resolvedModelId = settings.modelId.trim().isNotEmpty
          ? settings.modelId.trim()
          : modelFromConfig;
      await _writePidFile(process.pid);
      unawaited(process.stdout.drain<void>());
      unawaited(process.stderr.drain<void>());
      unawaited(process.exitCode.then((_) {
        if (_ownedPid == process.pid) {
          _ownedProcess = null;
          _ownedPid = null;
          _ownedFingerprint = null;
          unawaited(_clearPidFile());
        }
      }));
    } catch (e) {
      _ownedProcess = null;
      _ownedPid = null;
      _ownedFingerprint = null;
      _resolvedModelId = null;
      _resolvedMaxContext = null;
      await _clearPidFile();
      throw StateError('Strata の起動に失敗しました: $e');
    }

    if (!waitForHealth) return;

    onStatus?.call('Strata の準備を待っています（モデル読込）…');
    final ok = await _waitHealthy(
      isHealthy,
      timeout: const Duration(seconds: 300),
    );
    if (!ok) {
      await stopOwnedProcess();
      throw StateError(
        'Strata は起動しましたがヘルス確認がタイムアウトしました。'
        ' ポート ${settings.port} の衝突やモデル／メモリを確認してください。',
      );
    }
    onStatus?.call('Strata の準備が完了しました（${settings.baseUrl}）');
  }

  Future<String?> resolveCliPathForSettings(
    StrataConnectionSettings settings,
  ) {
    return StrataRuntimePaths.resolveCliPath(override: settings.cliPath);
  }

  Future<String?> resolveRunConfigForSettings(
    StrataConnectionSettings settings,
  ) async {
    final cli = await StrataRuntimePaths.resolveCliPath(
      override: settings.cliPath,
    );
    return StrataRuntimePaths.resolveRunConfigPath(
      override: settings.runConfigPath,
      cliPath: cli,
    );
  }

  /// run config／models list から `--max-context` 相当を解決する（起動しなくても可）。
  Future<int?> resolveMaxContextForSettings(
    StrataConnectionSettings settings,
  ) async {
    final cli = await StrataRuntimePaths.resolveCliPath(
      override: settings.cliPath,
    );
    final runConfig = await StrataRuntimePaths.resolveRunConfigPath(
      override: settings.runConfigPath,
      cliPath: cli,
    );
    if (runConfig == null) {
      return StrataRuntimePaths.readContextTokensFromModelsList(cli);
    }
    final resolved = await _resolveMaxContext(
      runConfigPath: runConfig,
      cliPath: cli,
    );
    _resolvedMaxContext = resolved;
    return resolved;
  }

  static Future<int?> _resolveMaxContext({
    required String runConfigPath,
    String? cliPath,
  }) async {
    final fromConfig =
        await StrataRuntimePaths.readMaxContextFromRunConfig(runConfigPath);
    if (fromConfig != null) return fromConfig;
    return StrataRuntimePaths.readContextTokensFromModelsList(cliPath);
  }

  static Future<void> shutdownOwnedForAppExit() => stopOwnedProcess();

  static Future<void> stopOwnedProcess() async {
    final process = _ownedProcess;
    final ownedPid = _ownedPid ?? process?.pid ?? await _readPidFile();
    _ownedProcess = null;
    _ownedPid = null;
    _ownedFingerprint = null;

    if (ownedPid == null && process == null) {
      await _clearPidFile();
      return;
    }

    if (Platform.isWindows) {
      if (ownedPid != null) {
        try {
          await Process.run(
            'taskkill',
            <String>['/PID', '$ownedPid', '/T', '/F'],
            runInShell: false,
          );
        } catch (_) {
          try {
            Process.killPid(ownedPid);
          } catch (_) {}
        }
      }
      try {
        process?.kill();
      } catch (_) {}
      await _clearPidFile();
      return;
    }

    // SIGINT で serve の drain／エンジン解放を促す
    try {
      process?.kill(ProcessSignal.sigint);
    } catch (_) {}
    if (ownedPid != null) {
      try {
        Process.killPid(ownedPid, ProcessSignal.sigint);
      } catch (_) {}
      await Future<void>.delayed(const Duration(seconds: 2));
      try {
        Process.killPid(ownedPid, ProcessSignal.sigterm);
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 800));
      try {
        Process.killPid(ownedPid, ProcessSignal.sigkill);
      } catch (_) {}
    }

    await _clearPidFile();
  }

  static String _listenHost(StrataConnectionSettings settings) {
    final uri = Uri.tryParse(settings.host.trim());
    if (uri != null && uri.host.isNotEmpty) return uri.host;
    final raw = settings.host.trim();
    if (raw.startsWith('http://')) {
      return raw.substring('http://'.length).split('/').first.split(':').first;
    }
    if (raw.startsWith('https://')) {
      return raw.substring('https://'.length).split('/').first.split(':').first;
    }
    return raw.isEmpty ? '127.0.0.1' : raw.split('/').first.split(':').first;
  }

  Future<bool> _waitHealthy(
    Future<bool> Function() isHealthy, {
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await isHealthy()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 1000));
    }
    return false;
  }

  static Future<void> _writePidFile(int processPid) async {
    try {
      await _pidFile.writeAsString('$processPid\n');
    } catch (_) {}
  }

  static Future<int?> _readPidFile() async {
    try {
      if (!await _pidFile.exists()) return null;
      return int.tryParse((await _pidFile.readAsString()).trim().split('\n').first);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _clearPidFile() async {
    try {
      if (await _pidFile.exists()) await _pidFile.delete();
    } catch (_) {}
  }
}

final class _StrataLaunchFingerprint {
  const _StrataLaunchFingerprint({
    required this.port,
    required this.host,
    required this.cliPath,
    required this.runConfigPath,
  });

  factory _StrataLaunchFingerprint.fromSettings(
    StrataConnectionSettings s, {
    String? cliPath,
    String? runConfigPath,
  }) {
    return _StrataLaunchFingerprint(
      port: s.port,
      host: s.host.trim(),
      cliPath: (cliPath ?? s.cliPath).trim(),
      runConfigPath: (runConfigPath ?? s.runConfigPath).trim(),
    );
  }

  final int port;
  final String host;
  final String cliPath;
  final String runConfigPath;

  @override
  bool operator ==(Object other) {
    return other is _StrataLaunchFingerprint &&
        other.port == port &&
        other.host == host &&
        other.cliPath == cliPath &&
        other.runConfigPath == runConfigPath;
  }

  @override
  int get hashCode => Object.hash(port, host, cliPath, runConfigPath);
}
