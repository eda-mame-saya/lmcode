import '../../domain/repositories/coding_assist_repository.dart';
import '../datasources/coding_assist_local_datasource.dart';

class CodingAssistRepositoryImpl implements CodingAssistRepository {
  CodingAssistRepositoryImpl({
    required CodingAssistLocalDataSource localDataSource,
  }) : _local = localDataSource;

  final CodingAssistLocalDataSource _local;

  @override
  Future<List<String>> listRecentWorkspaces() {
    return _local.listRecentWorkspaces();
  }

  @override
  Future<void> rememberWorkspace(String rootPath) {
    return _local.rememberWorkspace(rootPath);
  }

  @override
  Future<void> removeRecentWorkspace(String rootPath) {
    return _local.removeRecentWorkspace(rootPath);
  }

  @override
  Future<Map<String, bool>?> loadFolderExpansion(String workspaceRoot) {
    return _local.loadFolderExpansion(workspaceRoot);
  }

  @override
  Future<void> saveFolderExpansion(
    String workspaceRoot,
    Map<String, bool> expandedByPath,
  ) {
    return _local.saveFolderExpansion(workspaceRoot, expandedByPath);
  }
}
