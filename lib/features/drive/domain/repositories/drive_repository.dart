import 'dart:typed_data';

import '../entities/drive_connection_state.dart';
import '../entities/drive_file.dart';
import '../entities/drive_project.dart';
import '../entities/drive_session.dart';
import '../entities/drive_unsorted_capture.dart';
import '../entities/storage_backend.dart';

abstract interface class DriveRepository {
  Future<DriveConnectionState> getConnectionState();
  Future<DriveConnectionState> connect();
  Future<void> disconnect();
  Future<StorageBackend> getStorageBackend();
  Future<DriveConnectionState> setStorageBackend(StorageBackend backend);
  Future<DriveConnectionState> setLocalBasePath(String basePath);

  /// [includeHidden] が false のとき表示中のみ、true のとき非表示のみ返す。
  Future<List<DriveProject>> listProjects({bool includeHidden = false});
  Future<DriveProject> createProject(String name);
  Future<DriveProject> renameProject(String projectFolderId, String newDisplayName);
  Future<DriveProject> hideProject(String projectFolderId);
  Future<DriveProject> restoreProject(String projectFolderId);

  Future<List<DriveSession>> listSessions(String projectFolderId);
  Future<DriveSession> createNextSession(String projectFolderId);

  /// プロジェクト／第N回未選択時の退避先。
  /// `LMCode/未整理フォルダ/YYYY_MM_DD_hh_mm_ss/` を確保してそのフォルダ ID を返す。
  Future<String> ensureUnsortedCaptureFolder({DateTime? at});

  /// `未整理フォルダ/` 配下の退避フォルダ一覧。
  Future<List<DriveUnsortedCapture>> listUnsortedCaptures();

  /// 未整理フォルダを既存プロジェクトの次の第N回として移動する。
  Future<DriveSession> assignUnsortedCaptureToProject({
    required String captureFolderId,
    required String projectFolderId,
  });

  /// 未整理フォルダを新規プロジェクト化し、第01回として取り込む。
  /// 戻り値は作成したプロジェクト。
  Future<DriveProject> promoteUnsortedCaptureToProject({
    required String captureFolderId,
    required String projectName,
  });

  /// 文字起こし無しで作られた退避フォルダを削除する。
  /// [captureFolderId] が `未整理フォルダ/` 配下でない場合は何もしない。
  Future<void> deleteUnsortedCaptureFolder(String captureFolderId);

  Future<List<DriveFile>> listFilesInFolder(String folderId);
  Future<DriveFile?> findFileInFolder({
    required String folderId,
    required String fileName,
  });
  Future<String> readFileAsText({
    required String fileId,
    required String mimeType,
  });
  Future<DriveFile> saveTextFile({
    required String folderId,
    required String fileName,
    required String content,
  });

  /// バイナリファイル（.xlsx 等）の読込。
  Future<Uint8List> readFileAsBytes({required String fileId});

  /// バイナリファイルの新規作成または同名上書き。
  Future<DriveFile> saveBinaryFile({
    required String folderId,
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  });
}
