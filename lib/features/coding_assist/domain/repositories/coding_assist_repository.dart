abstract class CodingAssistRepository {
  Future<List<String>> listRecentWorkspaces();
  Future<void> rememberWorkspace(String rootPath);
  Future<void> removeRecentWorkspace(String rootPath);

  /// 未記録なら null。空 Map は記録済みで中身が無い。
  Future<Map<String, bool>?> loadFolderExpansion(String workspaceRoot);

  Future<void> saveFolderExpansion(
    String workspaceRoot,
    Map<String, bool> expandedByPath,
  );
}
