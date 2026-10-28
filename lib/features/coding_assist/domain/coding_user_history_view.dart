import 'entities/coding_assist_entities.dart';

/// ユーザー吹き出しの表示。API 用の結合文（[CodingChatMessage.content]）とは分ける。
final class CodingUserHistoryView {
  const CodingUserHistoryView({
    required this.text,
    required this.chips,
    required this.split,
  });

  /// 入力欄に書いた文。分割しないときは結合文そのもの。
  final String text;

  /// ファイル・選択範囲・フォルダ構造の表示ラベル。
  final List<CodingHistoryChip> chips;

  /// true のとき吹き出しは [text] と [chips] だけを出す。
  final bool split;
}

/// 編集で送信前の付与へ戻すスナップショット。
final class CodingRestoredComposer {
  const CodingRestoredComposer({
    required this.files,
    this.selection,
    required this.folders,
  });

  final List<CodingAttachedOpenFile> files;
  final CodingAttachedSelection? selection;
  final List<CodingAttachedFolderStructure> folders;
}

final _openFileBlock = RegExp(
  r'【開いているファイル: ([^】]+)】\n(?:```\n([\s\S]*?)\n```|（空ファイル）)',
);

final _selectionBlock = RegExp(
  r'【選択範囲】\nファイル: ([^\n]+)\n行: L(\d+)(?:[–-]L(\d+))?\n```\n([\s\S]*?)\n```',
);

final _folderBlock = RegExp(
  r'【プロジェクトのフォルダ構造】\n```text\n([\s\S]*?)\n```',
);

CodingUserHistoryView codingUserHistoryView(CodingChatMessage message) {
  final stored = message.historyChips;
  final typed = message.requestText;
  final split = typed != null || stored.isNotEmpty;
  if (!split) {
    return CodingUserHistoryView(
      text: message.content,
      chips: const [],
      split: false,
    );
  }
  final chips = stored.isNotEmpty
      ? stored
      : codingHistoryChipsIn(message.content);
  return CodingUserHistoryView(text: typed ?? '', chips: chips, split: true);
}

/// 結合文から添付ラベルを拾う。チップ未保存の過去発言用。
List<CodingHistoryChip> codingHistoryChipsIn(String content) {
  final out = <CodingHistoryChip>[];
  for (final match in _openFileBlock.allMatches(content)) {
    final path = (match.group(1) ?? '').trim();
    if (path.isEmpty) continue;
    out.add(
      CodingHistoryChip(
        kind: CodingHistoryChipKind.file,
        label: path,
        path: path,
      ),
    );
  }
  final selection = _selectionBlock.firstMatch(content);
  if (selection != null) {
    final path = (selection.group(1) ?? '').trim();
    if (path.isNotEmpty) {
      out.add(
        CodingHistoryChip(
          kind: CodingHistoryChipKind.selection,
          label: '選択範囲: $path',
          path: path,
        ),
      );
    }
  }
  for (final match in _folderBlock.allMatches(content)) {
    final inner = match.group(1) ?? '';
    final name = inner.split('\n').first.trim();
    final path = name == '.' || name.isEmpty ? '' : name;
    out.add(
      CodingHistoryChip(
        kind: CodingHistoryChipKind.folder,
        label: 'フォルダ構造: ${path.isEmpty ? 'ワークスペース' : path}',
        path: path,
      ),
    );
  }
  return List<CodingHistoryChip>.unmodifiable(out);
}

/// 結合文から、編集時に戻す添付スナップショットを取る。
CodingRestoredComposer codingRestoreComposerAttachments(
  String content, {
  List<CodingHistoryChip> chips = const [],
}) {
  final files = <CodingAttachedOpenFile>[];
  for (final match in _openFileBlock.allMatches(content)) {
    final path = (match.group(1) ?? '').trim().replaceAll('\\', '/');
    if (path.isEmpty) continue;
    files.add(
      CodingAttachedOpenFile(relativePath: path, content: match.group(2) ?? ''),
    );
  }

  CodingAttachedSelection? selection;
  final selectionMatch = _selectionBlock.firstMatch(content);
  if (selectionMatch != null) {
    final path = (selectionMatch.group(1) ?? '').trim();
    final start = int.tryParse(selectionMatch.group(2) ?? '') ?? 1;
    final end = int.tryParse(selectionMatch.group(3) ?? '') ?? start;
    if (path.isNotEmpty) {
      selection = CodingAttachedSelection(
        relativePath: path,
        startLine: start,
        endLine: end,
        selectedText: selectionMatch.group(4) ?? '',
      );
    }
  }

  final folderPaths = [
    for (final chip in chips)
      if (chip.kind == CodingHistoryChipKind.folder) chip.path ?? chip.label,
  ];
  final folders = <CodingAttachedFolderStructure>[];
  var folderIndex = 0;
  for (final match in _folderBlock.allMatches(content)) {
    final inner = match.group(1) ?? '';
    final block = '【プロジェクトのフォルダ構造】\n```text\n$inner\n```';
    final fallback = inner.split('\n').first.trim();
    final fromChip = folderIndex < folderPaths.length
        ? folderPaths[folderIndex]
        : null;
    folderIndex++;
    final path = (fromChip ?? (fallback == '.' ? '' : fallback)).replaceAll(
      '\\',
      '/',
    );
    folders.add(CodingAttachedFolderStructure(relativePath: path, block: block));
  }

  return CodingRestoredComposer(
    files: List<CodingAttachedOpenFile>.unmodifiable(files),
    selection: selection,
    folders: List<CodingAttachedFolderStructure>.unmodifiable(folders),
  );
}
