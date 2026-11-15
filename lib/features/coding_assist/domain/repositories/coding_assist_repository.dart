import '../entities/coding_assist_entities.dart';

abstract class CodingAssistRepository {
  Future<List<CodingThreadSummary>> listSummaries();
  Future<List<String>> listRecentWorkspaces();
  Future<CodingThread?> loadThread(String id);
  Future<void> saveThread(CodingThread thread);
  Future<void> deleteThread(String id);
  Future<void> rememberWorkspace(String rootPath);
  Future<void> removeRecentWorkspace(String rootPath);

  /// 未記録なら null。空 Map は記録済みで中身が無い。
  Future<Map<String, bool>?> loadFolderExpansion(String workspaceRoot);

  Future<void> saveFolderExpansion(
    String workspaceRoot,
    Map<String, bool> expandedByPath,
  );
}
