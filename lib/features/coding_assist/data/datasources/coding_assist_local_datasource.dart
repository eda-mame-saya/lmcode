import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../drive/domain/drive_system_folders.dart';
import '../../domain/coding_folder_expansion.dart';
import '../../domain/entities/coding_assist_entities.dart';

class CodingAssistLocalDataSource {
  Future<Directory> _ensureRoot(String appRootFolderPath) async {
    final root = Directory(
      p.join(appRootFolderPath, DriveSystemFolders.codingAssist),
    );
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    final threads = Directory(p.join(root.path, 'threads'));
    if (!await threads.exists()) {
      await threads.create(recursive: true);
    }
    return root;
  }

  File _indexFile(String rootPath) => File(p.join(rootPath, 'index.json'));

  File _threadFile(String rootPath, String id) =>
      File(p.join(rootPath, 'threads', '$id.json'));

  Future<Map<String, dynamic>> _readIndexMap(String rootPath) async {
    final index = _indexFile(rootPath);
    if (!await index.exists()) {
      return {'version': 1, 'threads': [], 'recentWorkspaces': []};
    }
    try {
      final decoded = jsonDecode(await index.readAsString());
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return {'version': 1, 'threads': [], 'recentWorkspaces': []};
  }

  Future<void> _writeIndexMap(String rootPath, Map<String, dynamic> map) async {
    await _indexFile(
      rootPath,
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(map));
  }

  /// 一覧を返す。メッセージの無い「新規」は index と threads ファイルから外す。
  Future<List<CodingThreadSummary>> listSummaries(
    String appRootFolderPath,
  ) async {
    final root = await _ensureRoot(appRootFolderPath);
    final map = await _readIndexMap(root.path);
    final threads = map['threads'];
    final list = <CodingThreadSummary>[];
    if (threads is List) {
      for (final item in threads) {
        if (item is Map<String, dynamic>) {
          list.add(CodingThreadSummary.fromJson(item));
        } else if (item is Map) {
          list.add(
            CodingThreadSummary.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    final kept = <CodingThreadSummary>[];
    final dropIds = <String>[];
    for (final summary in list) {
      if (!CodingThread.isPlaceholderTitle(summary.title)) {
        kept.add(summary);
        continue;
      }
      if (summary.id.trim().isEmpty ||
          summary.id.contains('/') ||
          summary.id.contains('\\') ||
          summary.id.contains('..')) {
        dropIds.add(summary.id);
        continue;
      }
      final thread = await loadThread(appRootFolderPath, summary.id);
      if (thread != null && thread.persists) {
        kept.add(summary);
        continue;
      }
      final file = _threadFile(root.path, summary.id);
      if (thread == null && await file.exists()) {
        kept.add(summary);
        continue;
      }
      dropIds.add(summary.id);
    }
    if (dropIds.isNotEmpty) {
      for (final id in dropIds) {
        if (id.trim().isEmpty ||
            id.contains('/') ||
            id.contains('\\') ||
            id.contains('..')) {
          continue;
        }
        final file = _threadFile(root.path, id);
        if (await file.exists()) await file.delete();
      }
      map['threads'] = kept.map((s) => s.toJson()).toList();
      await _writeIndexMap(root.path, map);
    }
    kept.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return kept;
  }

  Future<List<String>> listRecentWorkspaces(String appRootFolderPath) async {
    final root = await _ensureRoot(appRootFolderPath);
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

  Future<CodingThread?> loadThread(String appRootFolderPath, String id) async {
    final root = await _ensureRoot(appRootFolderPath);
    final file = _threadFile(root.path, id);
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic>) {
        return CodingThread.fromJson(decoded);
      }
      if (decoded is Map) {
        return CodingThread.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {}
    return null;
  }

  Future<void> saveThread(String appRootFolderPath, CodingThread thread) async {
    if (!thread.persists) {
      await _discardIfPresent(appRootFolderPath, thread.id);
      return;
    }
    final root = await _ensureRoot(appRootFolderPath);
    await _threadFile(root.path, thread.id).writeAsString(
      const JsonEncoder.withIndent('  ').convert(thread.toJson()),
    );
    final map = await _readIndexMap(root.path);
    final summaries = await listSummaries(appRootFolderPath);
    final next = [
      CodingThreadSummary(
        id: thread.id,
        title: thread.title,
        workspaceRootPath: thread.workspaceRootPath,
        updatedAt: thread.updatedAt,
      ),
      ...summaries.where((s) => s.id != thread.id),
    ];
    map['threads'] = next.map((s) => s.toJson()).toList();
    await _writeIndexMap(root.path, map);
  }

  /// 未保存の空会話では index を書き換えない。
  Future<void> _discardIfPresent(String appRootFolderPath, String id) async {
    if (id.trim().isEmpty ||
        id.contains('/') ||
        id.contains('\\') ||
        id.contains('..')) {
      return;
    }
    final root = await _ensureRoot(appRootFolderPath);
    final file = _threadFile(root.path, id);
    final existed = await file.exists();
    final map = await _readIndexMap(root.path);
    final threads = map['threads'];
    final inIndex =
        threads is List &&
        threads.any((item) => item is Map && '${item['id']}' == id);
    if (!existed && !inIndex) return;
    if (existed) {
      final loaded = await loadThread(appRootFolderPath, id);
      // 同じ id にメッセージがある会話は、空の保存では消さない。
      if (loaded == null || loaded.persists) return;
      await file.delete();
    }
    if (threads is List && inIndex) {
      map['threads'] = threads.where((item) {
        if (item is Map) return '${item['id']}' != id;
        return true;
      }).toList();
      await _writeIndexMap(root.path, map);
    }
  }

  Future<void> deleteThread(String appRootFolderPath, String id) async {
    final root = await _ensureRoot(appRootFolderPath);
    final file = _threadFile(root.path, id);
    if (await file.exists()) {
      await file.delete();
    }
    final map = await _readIndexMap(root.path);
    final threads = map['threads'];
    if (threads is List) {
      map['threads'] = threads.where((item) {
        if (item is Map) return '${item['id']}' != id;
        return true;
      }).toList();
      await _writeIndexMap(root.path, map);
    }
  }

  Future<void> rememberWorkspace(
    String appRootFolderPath,
    String workspaceRoot,
  ) async {
    final root = await _ensureRoot(appRootFolderPath);
    final map = await _readIndexMap(root.path);
    final path = workspaceRoot.trim();
    if (path.isEmpty) return;
    final existing = await listRecentWorkspaces(appRootFolderPath);
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

  //  フォルダを開いていない場合に表示している最近開いたフォルダリストを削除する
  Future<void> removeRecentWorkspace(
    String appRootFolderPath,
    String workspaceRoot,
  ) async {
    final root = await _ensureRoot(appRootFolderPath);
    final map = await _readIndexMap(root.path);
    final path = workspaceRoot.trim();
    if (path.isEmpty) return;
    final existing = await listRecentWorkspaces(appRootFolderPath);
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
  Future<Map<String, bool>?> loadFolderExpansion(
    String appRootFolderPath,
    String workspaceRoot,
  ) async {
    final root = await _ensureRoot(appRootFolderPath);
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
    String appRootFolderPath,
    String workspaceRoot,
    Map<String, bool> expandedByPath,
  ) async {
    final root = await _ensureRoot(appRootFolderPath);
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
