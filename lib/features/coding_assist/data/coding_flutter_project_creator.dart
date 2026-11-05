import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// `flutter create` でアプリプロジェクトを新規作成する。
class CodingFlutterProjectCreator {
  CodingFlutterProjectCreator();

  static const createTimeout = Duration(minutes: 10);

  /// Dart パッケージ名として使えるフォルダ名か。
  static bool isValidProjectName(String raw) {
    final name = raw.trim();
    if (name.isEmpty) return false;
    return RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name);
  }

  /// 作成先絶対パス。親＋フォルダ名。
  static String projectPath({
    required String parentDirectory,
    required String projectName,
  }) {
    return p.normalize(p.join(parentDirectory.trim(), projectName.trim()));
  }

  Future<CodingFlutterCreateResult> create({
    required String flutterExecutable,
    required String parentDirectory,
    required String projectName,
    required List<String> platforms,
    Duration? timeout,
  }) async {
    final name = projectName.trim();
    final parent = parentDirectory.trim();
    if (!isValidProjectName(name)) {
      return const CodingFlutterCreateResult(
        ok: false,
        errorMessage:
            'フォルダ名は小文字の英字で始め、英小文字・数字・アンダースコアのみにしてください。',
      );
    }
    if (parent.isEmpty) {
      return const CodingFlutterCreateResult(
        ok: false,
        errorMessage: '作成先フォルダを選択してください。',
      );
    }
    final selected = platforms
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    if (selected.isEmpty) {
      return const CodingFlutterCreateResult(
        ok: false,
        errorMessage: '対象プラットフォームを1つ以上選んでください。',
      );
    }

    final parentDir = Directory(parent);
    if (!await parentDir.exists()) {
      return CodingFlutterCreateResult(
        ok: false,
        errorMessage: '作成先フォルダが見つかりません: $parent',
      );
    }

    final outputPath = projectPath(
      parentDirectory: parent,
      projectName: name,
    );
    final existing = Directory(outputPath);
    if (await existing.exists()) {
      final entries = await existing.list(followLinks: false).toList();
      if (entries.isNotEmpty) {
        return CodingFlutterCreateResult(
          ok: false,
          errorMessage: '作成先が既に存在し、空ではありません: $outputPath',
        );
      }
    }

    final args = <String>[
      'create',
      '--platforms=${selected.join(',')}',
      '--project-name=$name',
      outputPath,
    ];

    final Process process;
    try {
      process = await Process.start(flutterExecutable, args);
    } catch (e) {
      return CodingFlutterCreateResult(
        ok: false,
        errorMessage: 'flutter create を起動できませんでした: $e',
      );
    }

    final buffer = StringBuffer();
    const decoder = Utf8Decoder(allowMalformed: true);
    final outSub = process.stdout.transform(decoder).listen(buffer.write);
    final errSub = process.stderr.transform(decoder).listen(buffer.write);

    try {
      final code = await process.exitCode.timeout(
        timeout ?? createTimeout,
        onTimeout: () {
          process.kill();
          return -1;
        },
      );
      await outSub.cancel();
      await errSub.cancel();
      final log = buffer.toString().trim();
      if (code == -1) {
        return CodingFlutterCreateResult(
          ok: false,
          projectPath: outputPath,
          log: log,
          errorMessage: 'flutter create がタイムアウトしました。',
        );
      }
      if (code != 0) {
        return CodingFlutterCreateResult(
          ok: false,
          projectPath: outputPath,
          log: log,
          errorMessage: log.isEmpty
              ? 'flutter create が失敗しました（exit $code）。'
              : 'flutter create が失敗しました（exit $code）。\n$log',
        );
      }
      return CodingFlutterCreateResult(
        ok: true,
        projectPath: outputPath,
        log: log,
      );
    } catch (e) {
      try {
        process.kill();
      } catch (_) {}
      await outSub.cancel();
      await errSub.cancel();
      return CodingFlutterCreateResult(
        ok: false,
        projectPath: outputPath,
        log: buffer.toString().trim(),
        errorMessage: 'flutter create 中にエラー: $e',
      );
    }
  }
}

class CodingFlutterCreateResult {
  const CodingFlutterCreateResult({
    required this.ok,
    this.projectPath,
    this.log = '',
    this.errorMessage,
  });

  final bool ok;
  final String? projectPath;
  final String log;
  final String? errorMessage;
}

/// `flutter create --platforms` で選べるアプリ向けプラットフォーム。
enum CodingFlutterCreatePlatform {
  ios('ios', 'iOS'),
  android('android', 'Android'),
  web('web', 'Web'),
  macos('macos', 'macOS'),
  windows('windows', 'Windows'),
  linux('linux', 'Linux');

  const CodingFlutterCreatePlatform(this.id, this.label);

  final String id;
  final String label;
}
