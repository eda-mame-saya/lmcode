import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lmcode/features/coding_assist/data/datasources/coding_assist_local_datasource.dart';
import 'package:lmcode/features/coding_assist/domain/entities/coding_assist_entities.dart';

void main() {
  late Directory temp;
  late CodingAssistLocalDataSource store;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('coding_threads_');
    store = CodingAssistLocalDataSource(rootPathOverride: temp.path);
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  CodingThread thread({
    required String id,
    required String title,
    List<CodingChatMessage> messages = const [],
    DateTime? updatedAt,
  }) {
    return CodingThread(
      id: id,
      title: title,
      workspaceRootPath: '/ws',
      messages: messages,
      updatedAt: updatedAt ?? DateTime.utc(2026, 10, 22, 1),
    );
  }

  CodingChatMessage userMessage(String content) {
    return CodingChatMessage(
      role: CodingMessageRole.user,
      content: content,
      at: DateTime.utc(2026, 10, 22, 1, 5),
    );
  }

  Future<void> plant(CodingThread value) async {
    final root = Directory('${temp.path}/coding_assist');
    final threads = Directory('${root.path}/threads');
    await threads.create(recursive: true);
    await File(
      '${threads.path}/${value.id}.json',
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(value.toJson()));
    final indexFile = File('${root.path}/index.json');
    final map = await indexFile.exists()
        ? Map<String, dynamic>.from(
            jsonDecode(await indexFile.readAsString()) as Map,
          )
        : <String, dynamic>{
            'version': 1,
            'threads': <dynamic>[],
            'recentWorkspaces': [
              {
                'rootPath': '/ws',
                'displayName': 'ws',
                'lastOpenedAt': '2026-10-22T00:00:00.000Z',
              },
            ],
          };
    final list = List<dynamic>.from(map['threads'] as List? ?? const []);
    list.add(
      CodingThreadSummary(
        id: value.id,
        title: value.title,
        workspaceRootPath: value.workspaceRootPath,
        updatedAt: value.updatedAt,
      ).toJson(),
    );
    map['threads'] = list;
    await indexFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(map),
    );
  }

  test('空の新規は保存しない', () async {
    await store.saveThread(
      thread(id: 'empty-new', title: CodingThread.placeholderTitle),
    );

    expect(await store.listSummaries(), isEmpty);
    expect(
      await File('${temp.path}/coding_assist/threads/empty-new.json').exists(),
      isFalse,
    );
  });

  test('一覧で保存済みの空新規を消し、メッセージがある会話は残す', () async {
    await plant(thread(id: 'blank-a', title: '新規'));
    await plant(
      thread(
        id: 'blank-b',
        title: '新規',
        updatedAt: DateTime.utc(2026, 10, 22, 2),
      ),
    );
    await plant(
      thread(
        id: 'titled-new',
        title: '新規',
        messages: [userMessage('新規')],
        updatedAt: DateTime.utc(2026, 10, 22, 3),
      ),
    );
    await plant(
      thread(
        id: 'real',
        title: 'ログイン検証を追加',
        messages: [userMessage('バリデーションを追加して')],
        updatedAt: DateTime.utc(2026, 10, 22, 4),
      ),
    );

    final first = await store.listSummaries();
    expect(first.map((s) => s.id).toList(), ['real', 'titled-new']);

    expect(
      await File('${temp.path}/coding_assist/threads/blank-a.json').exists(),
      isFalse,
    );
    expect(
      await File('${temp.path}/coding_assist/threads/blank-b.json').exists(),
      isFalse,
    );
    expect(await store.listRecentWorkspaces(), ['/ws']);

    final second = await store.listSummaries();
    expect(second.map((s) => s.id).toList(), ['real', 'titled-new']);
  });

  test('空の保存は同じ id の空ファイルだけ外し、中身がある会話は残す', () async {
    await plant(thread(id: 'gone', title: '新規'));
    await plant(
      thread(id: 'keep', title: '新規', messages: [userMessage('続きがある')]),
    );

    await store.saveThread(
      thread(id: 'gone', title: CodingThread.placeholderTitle),
    );
    await store.saveThread(
      thread(id: 'keep', title: CodingThread.placeholderTitle),
    );

    final left = await store.listSummaries();
    expect(left.map((s) => s.id).toList(), ['keep']);
    expect(
      await File('${temp.path}/coding_assist/threads/keep.json').exists(),
      isTrue,
    );
  });

  test('メッセージがある会話は保存され、空の新規は一緒に残らない', () async {
    await plant(thread(id: 'old-blank', title: '新規'));
    await store.saveThread(
      thread(
        id: 'saved',
        title: 'ファイルを直す',
        messages: [userMessage('直して')],
        updatedAt: DateTime.utc(2026, 10, 22, 5),
      ),
    );

    final list = await store.listSummaries();
    expect(list.map((s) => s.id).toList(), ['saved']);
    final loaded = await store.loadThread('saved');
    expect(loaded?.messages.single.content, '直して');
  });

  test('フォルダ展開はワークスペースごとに残り、最近一覧の更新では消えない', () async {
    expect(await store.loadFolderExpansion('/ws'), isNull);

    await store.saveFolderExpansion('/ws', {
      'lib': false,
      'document': true,
      '../secret': false,
    });
    expect(await store.loadFolderExpansion('/ws'), {
      'lib': false,
      'document': true,
    });

    await store.rememberWorkspace('/other');
    expect(await store.loadFolderExpansion('/ws'), {
      'lib': false,
      'document': true,
    });

    await store.removeRecentWorkspace('/other');
    expect(await store.loadFolderExpansion('/ws'), {
      'lib': false,
      'document': true,
    });
  });

  test('フォルダ展開の記録は古いワークスペースから捨てる', () async {
    for (var i = 0; i < 33; i++) {
      await store.saveFolderExpansion('/ws/$i', {'lib': i.isEven});
    }
    expect(await store.loadFolderExpansion('/ws/0'), isNull);
    expect(await store.loadFolderExpansion('/ws/1'), {'lib': false});
    expect(await store.loadFolderExpansion('/ws/32'), {'lib': true});
  });
}
