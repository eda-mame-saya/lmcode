import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../drive/domain/drive_system_folders.dart';
import '../../domain/coding_folder_expansion.dart';

/// 直近ワークスペースとフォルダ展開。会話は保存しない。
class CodingAssistLocalDataSource {
  /// `~/Documents/LMCode/coding_assist`。ベースフォルダ設定は使わない。
  Future<Directory> _ensureRoot() async {
    final home = (Platform.environment['HOME'] ??
            Platform.environment['USERPROFILE'])
        ?.trim();
    final base = (home == null || home.isEmpty)
        ? Directory.systemTemp.path
        : p.join(home, 'Documents');
    final root = Directory(
      p.join(base, 'LMCode', DriveSystemFolders.codingAssist),
    );
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    return root;
  }

  File _indexFile(String rootPath) => File(p.join(rootPath, 'index.json'));

  Future<Map<String, dynamic>> _readIndexMap(String rootPath) async {
    final index = _indexFile(rootPath);
    if (!await index.exists()) {
      return {'version': 1, 'recentWorkspaces': []};
    }
    try {
      final decoded = jsonDecode(await index.readAsString());
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return {'version': 1, 'recentWorkspaces': []};
  }

  Future<void> _writeIndexMap(String rootPath, Map<String, dynamic> map) async {
    await _indexFile(
      rootPath,
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(map));
  }

  Future<List<String>> listRecentWorkspaces() async {
    final root = await _ensureRoot();
    final map = await _readIndexMap(root.path);
    final recent = map['recentWorkspaces'];
    final out = <String>[];
    if (recent is List) {
      for (final item in recent) {
        if (item is Map) {
          final path = '${item['rootPath'] ?? ''}'.trim();
          if (path.isNotEmpty) out.add(path);
        } else if (item is String && item.trim().isNotEmpty) {
          out.add(item.trim());
        }
      }
    }
    return out;
  }

  Future<void> rememberWorkspace(String workspaceRoot) async {
    final root = await _ensureRoot();
    final map = await _readIndexMap(root.path);
    final path = workspaceRoot.trim();
    if (path.isEmpty) return;
    final existing = await listRecentWorkspaces();
    final next = [path, ...existing.where((e) => e != path)].take(8).toList();
    map['recentWorkspaces'] = [
      for (final r in next)
        {
          'rootPath': r,
          'displayName': p.basename(r),
          'lastOpenedAt': DateTime.now().toIso8601String(),
        },
    ];
    await _writeIndexMap(root.path, map);
  }

  Future<void> removeRecentWorkspace(String workspaceRoot) async {
    final root = await _ensureRoot();
    final map = await _readIndexMap(root.path);
    final path = workspaceRoot.trim();
    if (path.isEmpty) return;
    final existing = await listRecentWorkspaces();
    final next = existing.where((e) => e != path).toList();
    map['recentWorkspaces'] = [
      for (final r in next)
        {
          'rootPath': r,
          'displayName': p.basename(r),
          'lastOpenedAt': DateTime.now().toIso8601String(),
        },
    ];
    await _writeIndexMap(root.path, map);
  }

  static const _folderTreeExpandedKey = 'folderTreeExpanded';

  /// このワークスペースを一度も記録していなければ null。
  Future<Map<String, bool>?> loadFolderExpansion(String workspaceRoot) async {
    final root = await _ensureRoot();
    final map = await _readIndexMap(root.path);
    final path = workspaceRoot.trim();
    if (path.isEmpty) return null;
    final stored = map[_folderTreeExpandedKey];
    if (stored is! Map) return null;
    final raw = stored[path];
    if (raw is! Map) return null;
    return _decodeFolderExpansion(raw);
  }

  /// 直近に書いたワークスペースを残し、上限を超えた古い記録は捨てる。
  Future<void> saveFolderExpansion(
    String workspaceRoot,
    Map<String, bool> expandedByPath,
  ) async {
    final root = await _ensureRoot();
    final map = await _readIndexMap(root.path);
    final path = workspaceRoot.trim();
    if (path.isEmpty) return;
    final stored = <String, dynamic>{};
    final existing = map[_folderTreeExpandedKey];
    if (existing is Map) {
      existing.forEach((key, value) {
        final workspace = '$key'.trim();
        if (workspace.isEmpty) return;
        stored[workspace] = value;
      });
    }
    stored.remove(path);
    stored[path] = _encodeFolderExpansion(expandedByPath);
    while (stored.length > CodingFolderExpansion.maxRememberedWorkspaces) {
      stored.remove(stored.keys.first);
    }
    map[_folderTreeExpandedKey] = stored;
    await _writeIndexMap(root.path, map);
  }

  Map<String, bool> _decodeFolderExpansion(Map raw) {
    final out = <String, bool>{};
    raw.forEach((key, value) {
      if (value is! bool) return;
      final path = CodingFolderExpansion.normalizeRelative('$key');
      if (path == null) return;
      out[path] = value;
    });
    return out;
  }

  Map<String, bool> _encodeFolderExpansion(Map<String, bool> expandedByPath) {
    final out = <String, bool>{};
    for (final entry in expandedByPath.entries) {
      final path = CodingFolderExpansion.normalizeRelative(entry.key);
      if (path == null) continue;
      out[path] = entry.value;
    }
    return out;
  }
}
