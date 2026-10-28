import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../api_settings/domain/entities/local_llm_connection_settings.dart';
import '../domain/gemma_mtp_draft.dart';
import 'local_llm_runtime_paths.dart';

/// llama-server の起動・待機・終了。
/// アプリが自動起動したプロセスのみ管理する（手動起動分は触らない）。
class LocalLlmServerLauncher {
  LocalLlmServerLauncher();

  static Process? _ownedProcess;
  static int? _ownedPid;
  static _LaunchFingerprint? _ownedFingerprint;

  static final _pidFile = File(
    '${Directory.systemTemp.path}/lmcode_llama_server.pid',
  );

  bool get hasOwnedProcess => _ownedPid != null || _ownedProcess != null;

  /// 生成AI ON なら起動／設定差分なら再起動。OFF なら所有プロセスを停止。
  ///
  /// 併用中の MTP 下書き係のファイル名を返す。無いときは null。
  Future<String?> applySettings({
    required LocalLlmConnectionSettings settings,
    required Future<bool> Function(LocalLlmConnectionSettings settings)
        isHealthy,
    LocalLlmConnectionSettings? previous,
    void Function(String message)? onStatus,
    bool waitForHealth = true,
  }) async {
    if (!settings.enabled) {
      if (hasOwnedProcess) {
        onStatus?.call('ローカル LLM は OFF のため llama-server を停止します');
      }
      await stopOwnedProcess();
      return null;
    }
    if (!settings.isConfigured) {
      if (hasOwnedProcess) {
        onStatus?.call('モデル未設定のため llama-server を停止します');
      }
      await stopOwnedProcess();
      onStatus?.call('GGUF モデルが未設定です。エンジン設定からモデルを追加してください');
      return null;
    }

    final restartRelevantChanged = previous != null &&
        _LaunchFingerprint.fromSettings(previous) !=
            _LaunchFingerprint.fromSettings(settings);

    return ensureRunning(
      settings: settings,
      isHealthy: () => isHealthy(settings),
      onStatus: onStatus,
      waitForHealth: waitForHealth,
      forceRestart: restartRelevantChanged,
    );
  }

  /// 未起動、または起動引数（モデル／port／ctx／thinking）が違う場合に起動する。
  ///
  /// 併用中の MTP 下書き係のファイル名を返す。無いときは null。
  Future<String?> ensureRunning({
    required LocalLlmConnectionSettings settings,
    required Future<bool> Function() isHealthy,
    void Function(String message)? onStatus,
    bool waitForHealth = true,
    bool forceRestart = false,
  }) async {
    final modelPath = await resolveModelPathForSettings(settings);
    final draftPath = modelPath == null
        ? null
        : await resolveMtpDraftPath(modelPath);
    final fingerprint = _LaunchFingerprint.fromSettings(
      settings,
      draftPath: draftPath,
    );
    final draftLabel =
        draftPath == null ? null : p.basename(draftPath);
    final healthy = await isHealthy();
    final ownedMatches = hasOwnedProcess && _ownedFingerprint == fingerprint;
    final recordedPid = await _readPidFile();
    final recordedDraft = await _readRecordedDraftPath();
    final recordedLaunchMatches =
        recordedPid != null && recordedDraft == (draftPath ?? '');

    if (!forceRestart) {
      if (ownedMatches && healthy) return draftLabel;
      if (!hasOwnedProcess && healthy && recordedLaunchMatches) {
        // ホットリスタート等で Process 参照は消えても、pid ファイルがあれば次回の
        // 思考切替で止められるように所有を戻す。下書き係の有無が違うときは再起動する。
        _ownedPid = recordedPid;
        _ownedFingerprint = fingerprint;
        onStatus?.call(
          draftLabel == null
              ? '既存の llama-server に接続します（${settings.baseUrl}）'
              : '既存の llama-server に接続します（MTP: $draftLabel）',
        );
        return draftLabel;
      }
    }

    // 再起動が必要、または未起動。
    // 思考 ON/OFF は起動引数 `--reasoning` なので、生きているプロセスを止めてから起動し直す。
    final canStopRecorded = recordedPid != null &&
        (forceRestart || !recordedLaunchMatches);
    if (hasOwnedProcess || canStopRecorded) {
      onStatus?.call(
        forceRestart || !ownedMatches
            ? 'llama-server を再起動しています…'
            : 'llama-server を再試行しています…',
      );
      await stopOwnedProcess();
      await Future<void>.delayed(const Duration(milliseconds: 800));
    } else if (healthy) {
      throw StateError(
        'ポート ${settings.port} で別の llama-server が動作中です。'
        '手動で停止するか、設定のポートを変更してください。',
      );
    }

    onStatus?.call('llama-server を起動しています…');
    final binary = await resolveBinaryPath();
    if (binary == null) {
      throw StateError(
        'llama-server が見つかりません。'
        ' LMCode/local_llm/${LocalLlmRuntimePaths.binaryFileName} を配置するか、'
        'PATH に通してください（macOS: brew install llama.cpp）。',
      );
    }

    if (modelPath == null) {
      final root = await LocalLlmRuntimePaths.resolveInstalledRoot();
      final modelsDir = root == null
          ? 'LMCode/local_llm/models'
          : LocalLlmRuntimePaths.modelsDirUnder(root);
      final fileHint = settings.customGgufFileName ?? '';
      throw StateError(
        'GGUF モデルが見つかりません（${settings.resolvedModelLabel}）。'
        ' エンジン設定の「モデルを追加」で取り込み、'
        ' $modelsDir/ に $fileHint があることを確認してください。',
      );
    }
    if (GemmaMtpDraft.isDraftFileName(p.basename(modelPath))) {
      throw StateError(
        '選択中のファイルは MTP 下書き係です（${p.basename(modelPath)}）。'
        '会話用には Gemma 4 本体の GGUF を選んでください。',
      );
    }

    final listenHost = _listenHost(settings);
    if (draftPath != null) {
      onStatus?.call(
        'MTP 下書き係を併用します（${p.basename(draftPath)}）',
      );
    }
    try {
      final process = await Process.start(
        binary,
        <String>[
          '--host',
          listenHost,
          '--port',
          '${settings.port}',
          '--ctx-size',
          '${settings.contextSize}',
          '--jinja',
          '--reasoning',
          settings.thinkingEnabled ? 'on' : 'off',
          '--model',
          modelPath,
          if (draftPath != null) ...<String>[
            '--model-draft',
            draftPath,
            '--spec-type',
            'draft-mtp',
            '--spec-draft-n-max',
            '${GemmaMtpDraft.specDraftNMax}',
          ],
        ],
        workingDirectory: File(binary).parent.path,
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
      await _writePidFile(process.pid, draftPath: draftPath);
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
      await _clearPidFile();
      throw StateError('llama-server の起動に失敗しました: $e');
    }

    if (!waitForHealth) return draftLabel;

    onStatus?.call('llama-server の準備を待っています（モデル読込）…');
    final ok = await _waitHealthy(
      isHealthy,
      timeout: const Duration(seconds: 180),
    );
    if (!ok) {
      await stopOwnedProcess();
      throw StateError(
        'llama-server は起動しましたがヘルス確認がタイムアウトしました。'
        ' ポート ${settings.port} の衝突や GGUF／メモリを確認してください。',
      );
    }
    onStatus?.call(
      draftLabel == null
          ? 'llama-server の準備が完了しました（${settings.baseUrl}）'
          : 'MTP 下書き係を併用します（$draftLabel）',
    );
    return draftLabel;
  }

  /// `llama-server` バイナリを探索する。
  Future<String?> resolveBinaryPath() async {
    final candidates = <String>[];

    final installed = await LocalLlmRuntimePaths.resolveInstalledRoot();
    if (installed != null) {
      candidates.add(LocalLlmRuntimePaths.binaryPathUnder(installed));
    }

    final cwd = Directory.current.path;
    candidates.add(
      p.join(cwd, 'document/llama_cpp調査/poc', LocalLlmRuntimePaths.binaryFileName),
    );

    try {
      var dir = File(Platform.resolvedExecutable).parent;
      for (var i = 0; i < 8; i++) {
        candidates.add(
          p.join(dir.path, 'local_llm', LocalLlmRuntimePaths.binaryFileName),
        );
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
    } catch (_) {}

    if (!Platform.isWindows) {
      candidates.addAll(const [
        '/opt/homebrew/bin/llama-server',
        '/usr/local/bin/llama-server',
      ]);
    }

    for (final path in candidates) {
      final file = File(path);
      if (await file.exists()) return file.absolute.path;
    }

    try {
      final result = await Process.run(
        Platform.isWindows ? 'where' : 'which',
        [LocalLlmRuntimePaths.binaryFileName],
        environment: {
          ...Platform.environment,
          if (!Platform.isWindows)
            'PATH':
                '/opt/homebrew/bin:/usr/local/bin:${Platform.environment['PATH'] ?? ''}',
        },
      );
      if (result.exitCode == 0) {
        final line = (result.stdout as String)
            .split(RegExp(r'\r?\n'))
            .map((e) => e.trim())
            .firstWhere((e) => e.isNotEmpty, orElse: () => '');
        if (line.isNotEmpty && await File(line).exists()) return line;
      }
    } catch (_) {}

    return null;
  }

  /// 設定に応じた GGUF パスを解決する（ユーザー取り込みのみ）。
  Future<String?> resolveModelPathForSettings(
    LocalLlmConnectionSettings settings,
  ) async {
    if (!settings.usesCustomModel) return null;
    final name = settings.customGgufFileName!.trim();
    for (final dirPath in await _modelSearchDirs()) {
      final exact = File(p.join(dirPath, name));
      if (await exact.exists()) return exact.absolute.path;
    }
    return null;
  }

  /// 本体 GGUF と同じディレクトリから、系統が一致する MTP 下書き係を探す。
  Future<String?> resolveMtpDraftPath(String modelPath) async {
    final dir = Directory(File(modelPath).parent.path);
    if (!await dir.exists()) return null;
    final names = <String>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      names.add(p.basename(entity.path));
    }
    final picked = GemmaMtpDraft.selectDraftFileName(
      targetFileName: p.basename(modelPath),
      siblingFileNames: names,
    );
    if (picked == null) return null;
    return File(p.join(dir.path, picked)).absolute.path;
  }

  Future<List<String>> _modelSearchDirs() async {
    final dirs = <String>[];
    final installed = await LocalLlmRuntimePaths.resolveInstalledRoot();
    if (installed != null) {
      dirs.add(LocalLlmRuntimePaths.modelsDirUnder(installed));
      try {
        await Directory(dirs.last).create(recursive: true);
      } catch (_) {}
    }
    // 配布 zip: exe 横 local_llm/models（Documents 未コピーでも動く）
    try {
      var dir = File(Platform.resolvedExecutable).parent;
      for (var i = 0; i < 8; i++) {
        dirs.add(
          LocalLlmRuntimePaths.modelsDirUnder(
            p.join(dir.path, LocalLlmRuntimePaths.installedFolderName),
          ),
        );
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
    } catch (_) {}
    final cwd = Directory.current.path;
    dirs.add(p.join(cwd, LocalLlmRuntimePaths.pocModelsDirectory));
    return dirs;
  }

  static String _listenHost(LocalLlmConnectionSettings settings) {
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

    try {
      process?.kill(ProcessSignal.sigterm);
    } catch (_) {}

    if (ownedPid != null) {
      try {
        Process.killPid(ownedPid, ProcessSignal.sigterm);
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 600));
      try {
        Process.killPid(ownedPid, ProcessSignal.sigkill);
      } catch (_) {}
    }

    await _clearPidFile();
  }

  static Future<void> _writePidFile(int processPid, {String? draftPath}) async {
    try {
      final draft = (draftPath ?? '').replaceAll('\n', '');
      await _pidFile.writeAsString('$processPid\n$draft\n');
    } catch (_) {}
  }

  static Future<List<String>> _readPidLines() async {
    for (final file in [_pidFile]) {
      try {
        if (!await file.exists()) continue;
        return (await file.readAsString()).split(RegExp(r'\r?\n'));
      } catch (_) {}
    }
    return const [];
  }

  static Future<int?> _readPidFile() async {
    final lines = await _readPidLines();
    if (lines.isEmpty) return null;
    return int.tryParse(lines.first.trim());
  }

  static Future<String> _readRecordedDraftPath() async {
    final lines = await _readPidLines();
    if (lines.length < 2) return '';
    return lines[1].trim();
  }

  static Future<void> _clearPidFile() async {
    for (final file in [_pidFile]) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }
}

final class _LaunchFingerprint {
  const _LaunchFingerprint({
    required this.port,
    required this.modelKey,
    required this.contextSize,
    required this.thinkingEnabled,
    required this.draftPath,
  });

  factory _LaunchFingerprint.fromSettings(
    LocalLlmConnectionSettings s, {
    String? draftPath,
  }) {
    final modelKey = s.usesCustomModel
        ? 'custom:${s.customGgufFileName}'
        : 'unset';
    return _LaunchFingerprint(
      port: s.port,
      modelKey: modelKey,
      contextSize: s.contextSize,
      thinkingEnabled: s.thinkingEnabled,
      draftPath: draftPath ?? '',
    );
  }

  final int port;
  final String modelKey;
  final int contextSize;
  final bool thinkingEnabled;
  final String draftPath;

  @override
  bool operator ==(Object other) {
    return other is _LaunchFingerprint &&
        other.port == port &&
        other.modelKey == modelKey &&
        other.contextSize == contextSize &&
        other.thinkingEnabled == thinkingEnabled &&
        other.draftPath == draftPath;
  }

  @override
  int get hashCode =>
      Object.hash(port, modelKey, contextSize, thinkingEnabled, draftPath);
}
