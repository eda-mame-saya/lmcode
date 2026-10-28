import '../../../drive/domain/usecases/get_drive_connection_state.dart';
import '../../domain/entities/coding_assist_entities.dart';
import '../../domain/repositories/coding_assist_repository.dart';
import '../datasources/coding_assist_local_datasource.dart';

class CodingAssistRepositoryImpl implements CodingAssistRepository {
  CodingAssistRepositoryImpl({
    required CodingAssistLocalDataSource localDataSource,
    required GetDriveConnectionState getDriveConnectionState,
  }) : _local = localDataSource,
       _getDrive = getDriveConnectionState;

  final CodingAssistLocalDataSource _local;
  final GetDriveConnectionState _getDrive;

  Future<String> _appRoot() async {
    final state = await _getDrive();
    final root = state.appRootFolderId.trim();
    if (root.isEmpty) {
      throw StateError('ローカル保存先が未設定です。設定画面でベースフォルダを指定してください。');
    }
    return root;
  }

  @override
  Future<List<CodingThreadSummary>> listSummaries() async {
    return _local.listSummaries(await _appRoot());
  }

  @override
  Future<List<String>> listRecentWorkspaces() async {
    return _local.listRecentWorkspaces(await _appRoot());
  }

  @override
  Future<CodingThread?> loadThread(String id) async {
    return _local.loadThread(await _appRoot(), id);
  }

  @override
  Future<void> saveThread(CodingThread thread) async {
    await _local.saveThread(await _appRoot(), thread);
  }

  @override
  Future<void> deleteThread(String id) async {
    await _local.deleteThread(await _appRoot(), id);
  }

  @override
  Future<void> rememberWorkspace(String rootPath) async {
    await _local.rememberWorkspace(await _appRoot(), rootPath);
  }

  @override
  Future<void> removeRecentWorkspace(String rootPath) async {
    await _local.removeRecentWorkspace(await _appRoot(), rootPath);
  }

  @override
  Future<Map<String, bool>?> loadFolderExpansion(String workspaceRoot) async {
    return _local.loadFolderExpansion(await _appRoot(), workspaceRoot);
  }

  @override
  Future<void> saveFolderExpansion(
    String workspaceRoot,
    Map<String, bool> expandedByPath,
  ) async {
    await _local.saveFolderExpansion(
      await _appRoot(),
      workspaceRoot,
      expandedByPath,
    );
  }
}
