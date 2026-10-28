import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../domain/drive_project_naming.dart';
import '../../domain/drive_session_naming.dart';
import '../../domain/drive_system_folders.dart';
import '../../domain/drive_unsorted_folders.dart';
import '../../domain/entities/drive_connection_state.dart';
import '../../domain/entities/drive_file.dart';
import '../../domain/entities/drive_project.dart';
import '../../domain/entities/drive_session.dart';
import '../../domain/entities/drive_unsorted_capture.dart';
import '../../domain/entities/storage_backend.dart';
import '../../domain/local_storage_policy.dart';
import '../../domain/repositories/drive_repository.dart';
import '../datasources/drive_local_datasource.dart';
import '../datasources/local_workspace_datasource.dart';
import '../datasources/drive_remote_datasource.dart';

class DriveRepositoryImpl implements DriveRepository {
  DriveRepositoryImpl({
    required DriveLocalDataSource localDataSource,
    required LocalWorkspaceDataSource localWorkspaceDataSource,
    required DriveRemoteDataSource remoteDataSource,
  })  : _localDataSource = localDataSource,
        _localWorkspaceDataSource = localWorkspaceDataSource,
        _remoteDataSource = remoteDataSource;

  final DriveLocalDataSource _localDataSource;
  final LocalWorkspaceDataSource _localWorkspaceDataSource;
  final DriveRemoteDataSource _remoteDataSource;

  @override
  Future<StorageBackend> getStorageBackend() async {
    final raw = await _localDataSource.readStorageBackend();
    return raw == StorageBackend.local.name
        ? StorageBackend.local
        : StorageBackend.googleDrive;
  }

  @override
  Future<DriveConnectionState> setStorageBackend(StorageBackend backend) async {
    await _localDataSource.saveStorageBackend(backend.name);
    // iOS / Android: ローカル切替時にアプリ Documents を自動確保（検討10 §3.2）
    if (backend == StorageBackend.local &&
        LocalStoragePolicy.usesFixedAppDocumentsBase) {
      return setLocalBasePath('');
    }
    return getConnectionState();
  }

  @override
  Future<DriveConnectionState> setLocalBasePath(String basePath) async {
    final effectiveBase = LocalStoragePolicy.usesFixedAppDocumentsBase
        ? await _localWorkspaceDataSource.resolveAppDocumentsBasePath()
        : basePath.trim();
    final rootPath =
        await _localWorkspaceDataSource.ensureAppRootFolderPath(effectiveBase);
    // 設定画面に出す「ベース」は LMCode の親（例: ~/Documents）。
    // ルート自体を渡された場合も親を保存し、LMCode の二重化を防ぐ。
    final baseToStore = _localBasePathToStore(
      requestedBase: effectiveBase,
      appRootPath: rootPath,
    );
    await _localDataSource.saveLocalBasePath(baseToStore);
    await _localDataSource.saveAppRootFolderId(rootPath);
    await _localDataSource.saveStorageBackend(StorageBackend.local.name);
    return getConnectionState();
  }

  /// 保存するベースパス（LMCode 直下を作る親フォルダ）。
  static String _localBasePathToStore({
    required String requestedBase,
    required String appRootPath,
  }) {
    final root = appRootPath.trim();
    final sep = Platform.pathSeparator;
    final segments = root.split(sep).where((p) => p.isNotEmpty).toList();
    if (segments.isNotEmpty &&
        LocalWorkspaceDataSource.isAppRootFolderName(segments.last)) {
      final parent = Directory(root).parent.path;
      if (parent.isNotEmpty && parent != root) return parent;
    }
    return requestedBase.trim();
  }

  @override
  Future<DriveConnectionState> getConnectionState() async {
    final backend = await getStorageBackend();
    if (backend == StorageBackend.local) {
      final basePath = await _localDataSource.readLocalBasePath();
      final rootId = await _localDataSource.readAppRootFolderId();
      final connected = basePath.isNotEmpty && rootId.isNotEmpty;
      return DriveConnectionState(
        isConnected: connected,
        userId: connected ? 'local' : '',
        appRootFolderId: rootId,
        storageBackend: StorageBackend.local,
        localBasePath: basePath,
      );
    }

    final userId = await _localDataSource.readUserId();
    final rootId = await _localDataSource.readAppRootFolderId();
    final token = await _localDataSource.readAccessToken();
    final connected = userId.isNotEmpty && rootId.isNotEmpty && token.isNotEmpty;

    if (!connected) {
      return const DriveConnectionState.disconnected();
    }
    return DriveConnectionState(
      isConnected: true,
      userId: userId,
      appRootFolderId: rootId,
      storageBackend: StorageBackend.googleDrive,
    );
  }

  @override
  Future<DriveConnectionState> connect() async {
    final backend = await getStorageBackend();
    if (backend == StorageBackend.local) {
      if (LocalStoragePolicy.usesFixedAppDocumentsBase) {
        return setLocalBasePath('');
      }
      final basePath = await _localDataSource.readLocalBasePath();
      if (basePath.isEmpty) {
        throw Exception('ローカル保存先フォルダを設定してください。');
      }
      return setLocalBasePath(basePath);
    }

    final user = await _remoteDataSource.connect();
    final accessToken = await _remoteDataSource.getAccessToken();
    if (accessToken.isEmpty) {
      throw Exception('Google のアクセストークン取得に失敗しました。');
    }

    final appRootId = await _remoteDataSource.ensureAppRootFolderId(
      folderName: LocalWorkspaceDataSource.appRootFolderName,
    );

    await _localDataSource.saveUserId(user.id);
    await _localDataSource.saveAccessToken(accessToken);
    await _localDataSource.saveAppRootFolderId(appRootId);
    await _localDataSource.saveStorageBackend(StorageBackend.googleDrive.name);

    return DriveConnectionState(
      isConnected: true,
      userId: user.id,
      appRootFolderId: appRootId,
      storageBackend: StorageBackend.googleDrive,
    );
  }

  @override
  Future<void> disconnect() async {
    final backend = await getStorageBackend();
    if (backend == StorageBackend.local) {
      await _localDataSource.saveLocalBasePath('');
      await _localDataSource.saveAppRootFolderId('');
      return;
    }
    await _remoteDataSource.disconnect();
    await _localDataSource.clearAll();
  }

  @override
  Future<List<DriveProject>> listProjects({bool includeHidden = false}) async {
    final state = await getConnectionState();
    if (!state.isConnected) {
      throw Exception('保存先が未接続です。');
    }
    final all = state.storageBackend == StorageBackend.local
        ? await _localWorkspaceDataSource.listProjects(state.appRootFolderId)
        : await _remoteDataSource.listProjects(
            appRootFolderId: state.appRootFolderId,
          );
    return all
        .where((project) => !DriveSystemFolders.isReserved(project.name))
        .where((project) => project.isHidden == includeHidden)
        .toList();
  }

  Future<DriveConnectionState> _requireConnectedState() async {
    final state = await getConnectionState();
    if (!state.isConnected) {
      throw Exception('保存先が未接続です。');
    }
    return state;
  }

  @override
  Future<DriveProject> createProject(String name) async {
    final normalized = name.trim();
    if (!DriveProjectNaming.isAllowedNewProjectName(normalized)) {
      if (normalized.isEmpty) {
        throw Exception('プロジェクト名を入力してください。');
      }
      if (DriveSystemFolders.isReserved(normalized)) {
        throw Exception('「$normalized」はシステム用のためプロジェクト名に使えません。');
      }
      throw Exception('プロジェクト名に「${DriveProjectNaming.hiddenPrefix}」は使えません。');
    }

    final state = await _requireConnectedState();
    if (state.storageBackend == StorageBackend.local) {
      return _localWorkspaceDataSource.createProject(
        appRootFolderPath: state.appRootFolderId,
        name: normalized,
      );
    }
    return _remoteDataSource.createProject(
      appRootFolderId: state.appRootFolderId,
      name: normalized,
    );
  }

  @override
  Future<DriveProject> renameProject(
    String projectFolderId,
    String newDisplayName,
  ) async {
    String newFolderName;
    try {
      final project = await _requireProject(projectFolderId);
      newFolderName = DriveProjectNaming.folderNameForDisplayName(
        displayName: newDisplayName,
        keepHidden: project.isHidden,
      );
      if (newFolderName == project.name) return project;
    } on FormatException catch (error) {
      throw Exception(error.message);
    }

    final state = await _requireConnectedState();
    if (state.storageBackend == StorageBackend.local) {
      return _localWorkspaceDataSource.renameProject(
        projectFolderPath: projectFolderId,
        newName: newFolderName,
      );
    }
    return _remoteDataSource.renameProject(
      projectFolderId: projectFolderId,
      newName: newFolderName,
    );
  }

  @override
  Future<DriveProject> hideProject(String projectFolderId) async {
    final project = await _requireProject(projectFolderId);
    if (project.isHidden) return project;

    final state = await _requireConnectedState();
    final hiddenName = DriveProjectNaming.toHiddenFolderName(project.name);
    if (state.storageBackend == StorageBackend.local) {
      return _localWorkspaceDataSource.renameProject(
        projectFolderPath: projectFolderId,
        newName: hiddenName,
      );
    }
    return _remoteDataSource.renameProject(
      projectFolderId: projectFolderId,
      newName: hiddenName,
    );
  }

  @override
  Future<DriveProject> restoreProject(String projectFolderId) async {
    final project = await _requireProject(projectFolderId);
    if (!project.isHidden) return project;

    final state = await _requireConnectedState();
    final visibleName = DriveProjectNaming.toVisibleFolderName(project.name);
    if (state.storageBackend == StorageBackend.local) {
      return _localWorkspaceDataSource.renameProject(
        projectFolderPath: projectFolderId,
        newName: visibleName,
      );
    }
    return _remoteDataSource.renameProject(
      projectFolderId: projectFolderId,
      newName: visibleName,
    );
  }

  Future<DriveProject> _requireProject(String projectFolderId) async {
    final state = await _requireConnectedState();
    final all = state.storageBackend == StorageBackend.local
        ? await _localWorkspaceDataSource.listProjects(state.appRootFolderId)
        : await _remoteDataSource.listProjects(
            appRootFolderId: state.appRootFolderId,
          );
    return all.firstWhere(
      (project) => project.id == projectFolderId,
      orElse: () => throw Exception('プロジェクトが見つかりません。'),
    );
  }

  @override
  Future<List<DriveSession>> listSessions(String projectFolderId) async {
    final state = await _requireConnectedState();
    if (state.storageBackend == StorageBackend.local) {
      return _localWorkspaceDataSource.listSessions(projectFolderId);
    }
    return _remoteDataSource.listSessions(projectFolderId: projectFolderId);
  }

  @override
  Future<DriveSession> createNextSession(String projectFolderId) async {
    final sessions = await listSessions(projectFolderId);
    final maxIndex = sessions.isEmpty
        ? 0
        : sessions.map((item) => item.index).reduce((a, b) => a > b ? a : b);
    final deviceLabel = await _localDataSource.readDeviceLabel();
    final state = await _requireConnectedState();
    if (state.storageBackend == StorageBackend.local) {
      return _localWorkspaceDataSource.createSession(
        projectFolderPath: projectFolderId,
        sessionIndex: maxIndex + 1,
        deviceLabel: deviceLabel,
      );
    }
    return _remoteDataSource.createSession(
      projectFolderId: projectFolderId,
      sessionIndex: maxIndex + 1,
      deviceLabel: deviceLabel,
    );
  }

  @override
  Future<String> ensureUnsortedCaptureFolder({DateTime? at}) async {
    final state = await _requireConnectedState();
    final stamp = DriveUnsortedFolders.captureFolderName(at ?? DateTime.now());

    if (state.storageBackend == StorageBackend.local) {
      final unsortedPath = await _localWorkspaceDataSource.ensureChildFolder(
        parentFolderPath: state.appRootFolderId,
        folderName: DriveUnsortedFolders.projectName,
      );
      final captureName = await _uniqueLocalChildName(
        parentFolderPath: unsortedPath,
        baseName: stamp,
      );
      return _localWorkspaceDataSource.ensureChildFolder(
        parentFolderPath: unsortedPath,
        folderName: captureName,
      );
    }

    final unsortedId = await _remoteDataSource.ensureChildFolder(
      parentFolderId: state.appRootFolderId,
      folderName: DriveUnsortedFolders.projectName,
    );
    final captureName = await _uniqueRemoteChildName(
      parentFolderId: unsortedId,
      baseName: stamp,
    );
    return _remoteDataSource.ensureChildFolder(
      parentFolderId: unsortedId,
      folderName: captureName,
    );
  }

  @override
  Future<List<DriveUnsortedCapture>> listUnsortedCaptures() async {
    final state = await _requireConnectedState();
    if (state.storageBackend != StorageBackend.local) {
      // アルファはローカル専用。Drive 側の未整理整理は対象外。
      return const [];
    }
    return _localWorkspaceDataSource.listUnsortedCaptures(state.appRootFolderId);
  }

  @override
  Future<DriveSession> assignUnsortedCaptureToProject({
    required String captureFolderId,
    required String projectFolderId,
  }) async {
    final state = await _requireConnectedState();
    if (state.storageBackend != StorageBackend.local) {
      throw Exception('未整理フォルダの整理はローカル保存でのみ利用できます。');
    }
    await _requireProject(projectFolderId);
    final captureDir = Directory(captureFolderId);
    if (!await captureDir.exists()) {
      throw Exception('未整理フォルダが見つかりません。');
    }
    final captureName = p.basename(captureFolderId);

    final sessions = await listSessions(projectFolderId);
    final maxIndex = sessions.isEmpty
        ? 0
        : sessions.map((item) => item.index).reduce((a, b) => a > b ? a : b);
    final sessionIndex = maxIndex + 1;
    final existingNames = sessions.map((s) => s.name).toSet();
    var destName = DriveSessionNaming.folderName(
      sessionIndex: sessionIndex,
      deviceLabel: captureName,
    );
    if (existingNames.contains(destName)) {
      destName = DriveSessionNaming.nextImportAlias(
        originalName: destName,
        existingNames: existingNames,
      );
    }

    final movedPath = await _localWorkspaceDataSource.moveFolder(
      sourceFolderPath: captureFolderId,
      destParentFolderPath: projectFolderId,
      destFolderName: destName,
    );
    return DriveSession(
      id: movedPath,
      index: sessionIndex,
      name: destName,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<DriveProject> promoteUnsortedCaptureToProject({
    required String captureFolderId,
    required String projectName,
  }) async {
    final state = await _requireConnectedState();
    if (state.storageBackend != StorageBackend.local) {
      throw Exception('未整理フォルダの整理はローカル保存でのみ利用できます。');
    }
    final captureDir = Directory(captureFolderId);
    if (!await captureDir.exists()) {
      throw Exception('未整理フォルダが見つかりません。');
    }

    final project = await createProject(projectName);
    final captureName = p.basename(captureFolderId);
    final destName = DriveSessionNaming.folderName(
      sessionIndex: 1,
      deviceLabel: captureName,
    );
    await _localWorkspaceDataSource.moveFolder(
      sourceFolderPath: captureFolderId,
      destParentFolderPath: project.id,
      destFolderName: destName,
    );
    return project;
  }

  @override
  Future<void> deleteUnsortedCaptureFolder(String captureFolderId) async {
    final state = await _requireConnectedState();
    if (state.storageBackend != StorageBackend.local) return;

    final normalized = p.normalize(captureFolderId);
    final unsortedRoot = p.normalize(
      p.join(state.appRootFolderId, DriveUnsortedFolders.projectName),
    );
    // 親そのものや、未整理配下以外は誤削除防止のため拒否。
    if (normalized == unsortedRoot) return;
    if (!p.isWithin(unsortedRoot, normalized)) return;

    await _localWorkspaceDataSource.deleteFolder(normalized);
  }

  Future<String> _uniqueLocalChildName({
    required String parentFolderPath,
    required String baseName,
  }) async {
    var name = baseName;
    for (var n = 2; n <= 100; n++) {
      final exists = await _localWorkspaceDataSource.childFolderExists(
        parentFolderPath: parentFolderPath,
        folderName: name,
      );
      if (!exists) return name;
      name = '${baseName}_$n';
    }
    return '${baseName}_${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<String> _uniqueRemoteChildName({
    required String parentFolderId,
    required String baseName,
  }) async {
    var name = baseName;
    for (var n = 2; n <= 100; n++) {
      final existing = await _remoteDataSource.findChildFolderId(
        parentFolderId: parentFolderId,
        folderName: name,
      );
      if (existing == null) return name;
      name = '${baseName}_$n';
    }
    return '${baseName}_${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  Future<List<DriveFile>> listFilesInFolder(String folderId) async {
    final state = await _requireConnectedState();
    if (state.storageBackend == StorageBackend.local) {
      return _localWorkspaceDataSource.listFilesInFolder(folderId);
    }
    return _remoteDataSource.listFilesInFolder(folderId: folderId);
  }

  @override
  Future<DriveFile?> findFileInFolder({
    required String folderId,
    required String fileName,
  }) async {
    final state = await _requireConnectedState();
    if (state.storageBackend == StorageBackend.local) {
      return _localWorkspaceDataSource.findFileInFolder(
        folderPath: folderId,
        fileName: fileName,
      );
    }
    return _remoteDataSource.findFileInFolder(
      folderId: folderId,
      fileName: fileName,
    );
  }

  @override
  Future<String> readFileAsText({
    required String fileId,
    required String mimeType,
  }) async {
    final state = await _requireConnectedState();
    if (state.storageBackend == StorageBackend.local) {
      return _localWorkspaceDataSource.readFileAsText(fileId);
    }
    return _remoteDataSource.readFileAsText(
      fileId: fileId,
      mimeType: mimeType,
    );
  }

  @override
  Future<DriveFile> saveTextFile({
    required String folderId,
    required String fileName,
    required String content,
  }) async {
    final state = await _requireConnectedState();
    if (state.storageBackend == StorageBackend.local) {
      return _localWorkspaceDataSource.saveTextFile(
        folderPath: folderId,
        fileName: fileName,
        content: content,
      );
    }
    return _remoteDataSource.saveTextFile(
      folderId: folderId,
      fileName: fileName,
      content: content,
    );
  }

  @override
  Future<Uint8List> readFileAsBytes({required String fileId}) async {
    final state = await _requireConnectedState();
    if (state.storageBackend == StorageBackend.local) {
      return _localWorkspaceDataSource.readFileAsBytes(fileId);
    }
    return _remoteDataSource.readFileAsBytes(fileId: fileId);
  }

  @override
  Future<DriveFile> saveBinaryFile({
    required String folderId,
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final state = await _requireConnectedState();
    if (state.storageBackend == StorageBackend.local) {
      return _localWorkspaceDataSource.saveBinaryFile(
        folderPath: folderId,
        fileName: fileName,
        bytes: bytes,
        mimeType: mimeType,
      );
    }
    return _remoteDataSource.saveBinaryFile(
      folderId: folderId,
      fileName: fileName,
      bytes: bytes,
      mimeType: mimeType,
    );
  }
}
