import 'dart:io';

import 'package:path/path.dart' as p;

/// ワークスペース上の git 操作（name/email は端末側で設定済み前提）。
abstract final class CodingGit {
  /// 現在ブランチ名。git でない／取得失敗時は null。
  /// detached HEAD のときは `detached@<shortSha>`。
  static Future<String?> currentBranch(String workspaceRoot) async {
    final root = workspaceRoot.trim();
    if (root.isEmpty) return null;
    try {
      final inside = await _run(root, ['rev-parse', '--is-inside-work-tree']);
      if (inside.exitCode != 0 ||
          inside.stdout.toString().trim() != 'true') {
        return null;
      }
      final show = await _run(root, ['branch', '--show-current']);
      if (show.exitCode == 0) {
        final name = show.stdout.toString().trim();
        if (name.isNotEmpty) return name;
      }
      final head = await _run(root, ['rev-parse', '--short', 'HEAD']);
      if (head.exitCode == 0) {
        final sha = head.stdout.toString().trim();
        if (sha.isNotEmpty) return 'detached@$sha';
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  /// ファイルまたはフォルダを `git add` する（相対パス）。
  static Future<void> add({
    required String workspaceRoot,
    required String relativePath,
  }) async {
    final root = workspaceRoot.trim();
    if (root.isEmpty) {
      throw const CodingGitException('ワークスペースが選択されていません');
    }
    final rel = relativePath.replaceAll('\\', '/').trim();
    if (rel.isEmpty || rel.startsWith('..') || p.isAbsolute(rel)) {
      throw const CodingGitException('パスが不正です');
    }

    final inside = await _run(root, ['rev-parse', '--is-inside-work-tree']);
    if (inside.exitCode != 0 ||
        inside.stdout.toString().trim() != 'true') {
      throw CodingGitException(
        _preferStderr(inside) ?? 'Git リポジトリではありません',
      );
    }

    final result = await _run(root, ['add', '--', rel]);
    if (result.exitCode != 0) {
      throw CodingGitException(
        _preferStderr(result) ?? 'git add に失敗しました',
      );
    }
  }

  /// 変更を stage して [message] で commit する。
  /// 失敗時は [CodingGitException]。
  static Future<void> commit({
    required String workspaceRoot,
    required String message,
  }) async {
    final msg = message.trim();
    if (msg.isEmpty) {
      throw const CodingGitException('コミットメッセージを入力してください');
    }
    final root = workspaceRoot.trim();
    if (root.isEmpty) {
      throw const CodingGitException('ワークスペースが選択されていません');
    }

    final inside = await _run(root, ['rev-parse', '--is-inside-work-tree']);
    if (inside.exitCode != 0 ||
        inside.stdout.toString().trim() != 'true') {
      throw CodingGitException(
        _preferStderr(inside) ?? 'Git リポジトリではありません',
      );
    }

    final add = await _run(root, ['add', '-A']);
    if (add.exitCode != 0) {
      throw CodingGitException(_preferStderr(add) ?? 'git add に失敗しました');
    }

    final commit = await _run(root, ['commit', '-m', msg]);
    if (commit.exitCode != 0) {
      throw CodingGitException(
        _preferStderr(commit) ?? 'git commit に失敗しました',
      );
    }
  }

  static Future<ProcessResult> _run(String root, List<String> args) {
    return Process.run(
      'git',
      args,
      workingDirectory: root,
      runInShell: false,
    );
  }

  static String? _preferStderr(ProcessResult r) {
    final err = r.stderr.toString().trim();
    if (err.isNotEmpty) return err;
    final out = r.stdout.toString().trim();
    if (out.isNotEmpty) return out;
    return null;
  }
}

final class CodingGitException implements Exception {
  const CodingGitException(this.message);
  final String message;

  @override
  String toString() => message;
}
