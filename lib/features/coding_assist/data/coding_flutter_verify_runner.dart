import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 検証ログは末尾を残してこの文字数までにする。
const codingFlutterVerifyLogMaxChars = 8000;

/// [raw] の末尾を優先して切り詰める。短いログはそのまま返す。
String clipVerifyLog(
  String raw, {
  int maxChars = codingFlutterVerifyLogMaxChars,
}) {
  final text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
  if (text.length <= maxChars) return text;
  final tail = text.substring(text.length - maxChars);
  return '…（先頭を省略）\n$tail';
}

/// ヘッドレス実行の結果。ログは切り詰め済み。
class CodingFlutterVerifyResult {
  const CodingFlutterVerifyResult({
    required this.commandLabel,
    this.exitCode,
    this.timedOut = false,
    this.launchFailed = false,
    this.cancelled = false,
    this.log = '',
    this.launchError,
  });

  final String commandLabel;
  final int? exitCode;
  final bool timedOut;
  final bool launchFailed;
  final bool cancelled;
  final String log;
  final String? launchError;
}

/// `flutter analyze` と `flutter test` をワークスペースで実行する。
/// 下部ターミナルの PTY には流さない。
class CodingFlutterVerifyRunner {
  static const analyzeTimeout = Duration(minutes: 3);
  static const testTimeout = Duration(minutes: 10);

  Future<CodingFlutterVerifyResult> analyze({
    required String flutterExecutable,
    required String workingDirectory,
    required bool Function() isCancelled,
    Duration? timeout,
    int? logMaxChars,
  }) {
    return _run(
      executable: flutterExecutable,
      args: const ['analyze', '--no-fatal-infos', '--no-fatal-warnings'],
      workingDirectory: workingDirectory,
      timeout: timeout ?? analyzeTimeout,
      commandLabel: 'flutter analyze',
      isCancelled: isCancelled,
      logMaxChars: logMaxChars,
    );
  }

  Future<CodingFlutterVerifyResult> test({
    required String flutterExecutable,
    required String workingDirectory,
    required bool Function() isCancelled,
    Duration? timeout,
    int? logMaxChars,
  }) {
    return _run(
      executable: flutterExecutable,
      args: const ['test', '--reporter', 'compact'],
      workingDirectory: workingDirectory,
      timeout: timeout ?? testTimeout,
      commandLabel: 'flutter test',
      isCancelled: isCancelled,
      logMaxChars: logMaxChars,
    );
  }

  Future<CodingFlutterVerifyResult> _run({
    required String executable,
    required List<String> args,
    required String workingDirectory,
    required Duration timeout,
    required String commandLabel,
    required bool Function() isCancelled,
    int? logMaxChars,
  }) async {
    final Process process;
    try {
      process = await Process.start(
        executable,
        args,
        workingDirectory: workingDirectory,
      );
    } catch (e) {
      return CodingFlutterVerifyResult(
        commandLabel: commandLabel,
        launchFailed: true,
        launchError: '$e',
      );
    }

    final buffer = StringBuffer();
    const decoder = Utf8Decoder(allowMalformed: true);
    final streamsDone = Completer<void>();
    var openStreams = 2;
    void markStreamDone() {
      openStreams -= 1;
      if (openStreams <= 0 && !streamsDone.isCompleted) {
        streamsDone.complete();
      }
    }

    final outSub = process.stdout
        .transform(decoder)
        .listen(buffer.write, onDone: markStreamDone, cancelOnError: false);
    final errSub = process.stderr
        .transform(decoder)
        .listen(buffer.write, onDone: markStreamDone, cancelOnError: false);
    final started = DateTime.now();
    var cancelled = false;
    var timedOut = false;
    int? exitCode;

    try {
      while (true) {
        if (isCancelled()) {
          cancelled = true;
          await _killTree(process);
          break;
        }
        if (DateTime.now().difference(started) >= timeout) {
          timedOut = true;
          await _killTree(process);
          break;
        }
        try {
          exitCode = await process.exitCode.timeout(
            const Duration(milliseconds: 200),
          );
          break;
        } on TimeoutException {
          continue;
        }
      }
      await _waitStreams(streamsDone);
    } finally {
      await outSub.cancel();
      await errSub.cancel();
    }

    if (cancelled || timedOut) {
      try {
        await process.exitCode.timeout(const Duration(seconds: 3));
      } catch (_) {}
    }

    return CodingFlutterVerifyResult(
      commandLabel: commandLabel,
      exitCode: cancelled || timedOut ? null : exitCode,
      timedOut: timedOut && !cancelled,
      cancelled: cancelled,
      log: clipVerifyLog(
        buffer.toString(),
        maxChars: logMaxChars ?? codingFlutterVerifyLogMaxChars,
      ),
    );
  }

  Future<void> _waitStreams(Completer<void> streamsDone) async {
    try {
      await streamsDone.future.timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  Future<void> _killTree(Process process) async {
    try {
      if (Platform.isWindows) {
        await Process.run('taskkill', ['/F', '/T', '/PID', '${process.pid}']);
        return;
      }
      await Process.run('pkill', ['-KILL', '-P', '${process.pid}']);
      process.kill(ProcessSignal.sigkill);
    } catch (_) {
      try {
        process.kill();
      } catch (_) {}
    }
  }
}
