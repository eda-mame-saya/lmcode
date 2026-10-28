import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../../domain/drive_session_naming.dart';
import '../../domain/drive_unsorted_folders.dart';
import '../../domain/entities/drive_file.dart';
import '../../domain/entities/drive_project.dart';
import '../../domain/entities/drive_session.dart';
import '../../domain/entities/drive_unsorted_capture.dart';

class LocalWorkspaceDataSource {
  /// アプリデータルート（`~/Documents/LMCode` 等）。
  static const appRootFolderName = 'LMCode';

  static bool isAppRootFolderName(String name) =>
      name == appRootFolderName;

  /// iOS / Android 向け: アプリ Documents の絶対パスを返す。
  Future<String> resolveAppDocumentsBasePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  /// [basePath] 配下に `LMCode` ルートを確保してその絶対パスを返す。
  ///
  /// - 通常: `{base}/LMCode`
  /// - [basePath] 自体が既に `LMCode`のときは追加しない
  /// - `…/LMCode/LMCode` のように冗長な場合は一段に畳む
  Future<String> ensureAppRootFolderPath(String basePath) async {
    final normalized = basePath.trim();
    if (normalized.isEmpty) {
      throw Exception('ローカル保存先フォルダを入力してください。');
    }

    var rootPath = isAppRootFolderName(_basename(normalized))
        ? normalized
        : _joinPath(normalized, appRootFolderName);

    // 過去の二重作成を一段に正規化
    while (isAppRootFolderName(_basename(rootPath)) &&
        isAppRootFolderName(_basename(_parentPath(rootPath)))) {
      rootPath = _parentPath(rootPath);
    }

    final rootDir = Directory(rootPath);
    if (!await rootDir.exists()) {
      await rootDir.create(recursive: true);
    }
    return rootDir.path;
  }

  Future<List<DriveProject>> listProjects(String appRootFolderPath) async {
    final root = Directory(appRootFolderPath);
    if (!await root.exists()) return const [];
    final entities = await root.list().toList();
    final dirs = entities.whereType<Directory>().toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    return dirs
        .map(
          (dir) => DriveProject(
            id: dir.path,
            name: _basename(dir.path),
            updatedAt: dir.statSync().modified,
          ),
        )
        .toList();
  }

  Future<DriveProject> createProject({
    required String appRootFolderPath,
    required String name,
  }) async {
    final dir = Directory(_joinPath(appRootFolderPath, name));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return DriveProject(
      id: dir.path,
      name: name,
      updatedAt: DateTime.now(),
    );
  }

  Future<DriveProject> renameProject({
    required String projectFolderPath,
    required String newName,
  }) async {
    final source = Directory(projectFolderPath);
    if (!await source.exists()) {
      throw Exception('プロジェクトフォルダが見つかりません。');
    }
    final parent = source.parent.path;
    final targetPath = _joinPath(parent, newName);
    final renamed = await source.rename(targetPath);
    return DriveProject(
      id: renamed.path,
      name: _basename(renamed.path),
      updatedAt: DateTime.now(),
    );
  }

  Future<List<DriveSession>> listSessions(String projectFolderPath) async {
    final projectDir = Directory(projectFolderPath);
    if (!await projectDir.exists()) return const [];
    final entities = await projectDir.list().toList();
    final sessions = <DriveSession>[];
    for (final dir in entities.whereType<Directory>()) {
      final name = _basename(dir.path);
      final index = DriveSessionNaming.extractIndex(name);
      if (index == null) continue;
      sessions.add(
        DriveSession(
          id: dir.path,
          index: index,
          name: name,
          updatedAt: dir.statSync().modified,
        ),
      );
    }
    sessions.sort((a, b) => b.index.compareTo(a.index));
    return sessions;
  }

  Future<DriveSession> createSession({
    required String projectFolderPath,
    required int sessionIndex,
    String deviceLabel = '',
  }) async {
    final name = DriveSessionNaming.folderName(
      sessionIndex: sessionIndex,
      deviceLabel: deviceLabel,
    );
    final dir = Directory(_joinPath(projectFolderPath, name));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return DriveSession(
      id: dir.path,
      index: sessionIndex,
      name: name,
      updatedAt: DateTime.now(),
    );
  }

  /// 親フォルダ直下に名前付きサブフォルダを作成（既存ならそのまま返す）。
  Future<String> ensureChildFolder({
    required String parentFolderPath,
    required String folderName,
  }) async {
    final dir = Directory(_joinPath(parentFolderPath, folderName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  /// `未整理フォルダ/` 配下の退避フォルダ一覧（新しい順）。
  /// 中身が空（または `.` 始まりのみ）のフォルダは一覧時に削除する。
  Future<List<DriveUnsortedCapture>> listUnsortedCaptures(
    String appRootFolderPath,
  ) async {
    final unsorted = Directory(
      _joinPath(appRootFolderPath, DriveUnsortedFolders.projectName),
    );
    if (!await unsorted.exists()) return const [];
    final entities = await unsorted.list().toList();
    final captures = <DriveUnsortedCapture>[];
    for (final dir in entities.whereType<Directory>()) {
      final name = _basename(dir.path);
      if (name.startsWith('.')) continue;
      if (await _isEffectivelyEmptyFolder(dir)) {
        try {
          await dir.delete(recursive: true);
        } catch (_) {}
        continue;
      }
      captures.add(
        DriveUnsortedCapture(
          id: dir.path,
          name: name,
          updatedAt: dir.statSync().modified,
        ),
      );
    }
    captures.sort((a, b) {
      final au = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bu = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bu.compareTo(au);
    });
    return captures;
  }

  Future<bool> _isEffectivelyEmptyFolder(Directory dir) async {
    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        final name = _basename(entity.path);
        if (name.startsWith('.')) continue;
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// フォルダを別親配下へ移動（リネーム）。同一ボリューム前提。
  Future<String> moveFolder({
    required String sourceFolderPath,
    required String destParentFolderPath,
    required String destFolderName,
  }) async {
    final source = Directory(sourceFolderPath);
    if (!await source.exists()) {
      throw Exception('移動元フォルダが見つかりません。');
    }
    final parent = Directory(destParentFolderPath);
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    final destPath = _joinPath(destParentFolderPath, destFolderName);
    if (await Directory(destPath).exists()) {
      throw Exception('移動先に同名フォルダが既にあります: $destFolderName');
    }
    final moved = await source.rename(destPath);
    return moved.path;
  }

  /// フォルダを再帰削除（存在しなければ何もしない）。
  Future<void> deleteFolder(String folderPath) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) return;
    await dir.delete(recursive: true);
  }

  Future<bool> childFolderExists({
    required String parentFolderPath,
    required String folderName,
  }) async {
    return Directory(_joinPath(parentFolderPath, folderName)).exists();
  }

  Future<List<DriveFile>> listFilesInFolder(String folderPath) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) return const [];
    final entities = await dir.list().toList();
    final files = entities.whereType<File>().toList()
      ..sort((a, b) => _basename(a.path).compareTo(_basename(b.path)));
    return files
        .map(
          (file) => DriveFile(
            id: file.path,
            name: _basename(file.path),
            mimeType: _guessMimeType(file.path),
            modifiedTime: file.statSync().modified,
            parentFolderId: folderPath,
          ),
        )
        .toList();
  }

  Future<DriveFile?> findFileInFolder({
    required String folderPath,
    required String fileName,
  }) async {
    final file = File(_joinPath(folderPath, fileName));
    if (!await file.exists()) return null;
    return DriveFile(
      id: file.path,
      name: fileName,
      mimeType: _guessMimeType(file.path),
      modifiedTime: file.statSync().modified,
      parentFolderId: folderPath,
    );
  }

  Future<String> readFileAsText(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('ファイルが見つかりません。');
    }
    return file.readAsString();
  }

  Future<DriveFile> saveTextFile({
    required String folderPath,
    required String fileName,
    required String content,
  }) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File(_joinPath(folderPath, fileName));
    await file.writeAsString(content);
    return DriveFile(
      id: file.path,
      name: fileName,
      mimeType: 'text/markdown',
      modifiedTime: file.statSync().modified,
      parentFolderId: folderPath,
    );
  }

  Future<Uint8List> readFileAsBytes(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('ファイルが見つかりません。');
    }
    return file.readAsBytes();
  }

  Future<DriveFile> saveBinaryFile({
    required String folderPath,
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File(_joinPath(folderPath, fileName));
    await file.writeAsBytes(bytes, flush: true);
    return DriveFile(
      id: file.path,
      name: fileName,
      mimeType: mimeType,
      modifiedTime: file.statSync().modified,
      parentFolderId: folderPath,
    );
  }

  String _basename(String path) => path.split(Platform.pathSeparator).last;

  String _parentPath(String path) {
    final normalized = path.trim();
    if (normalized.isEmpty) return normalized;
    final sep = Platform.pathSeparator;
    final parts = normalized.split(sep).where((p) => p.isNotEmpty).toList();
    if (parts.length <= 1) {
      return normalized.startsWith(sep) ? sep : '';
    }
    parts.removeLast();
    final joined = parts.join(sep);
    return normalized.startsWith(sep) ? '$sep$joined' : joined;
  }

  String _joinPath(String base, String child) {
    if (base.endsWith(Platform.pathSeparator)) return '$base$child';
    return '$base${Platform.pathSeparator}$child';
  }

  String _guessMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.md')) return 'text/markdown';
    if (lower.endsWith('.txt')) return 'text/plain';
    if (lower.endsWith('.json')) return 'application/json';
    if (lower.endsWith('.csv')) return 'text/csv';
    if (lower.endsWith('.html') || lower.endsWith('.htm')) return 'text/html';
    if (lower.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    return 'application/octet-stream';
  }
}
