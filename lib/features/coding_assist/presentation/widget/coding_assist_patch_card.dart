part of '../pages/coding_assist_page.dart';

/// Update のうち削除行がなく追加だけ → 新規関数挿入案。
bool codingAssistIsNewFunctionInsertPatch(CodingProposedPatch patch) {
  if (patch.isAddFile) return false;
  return CodingPatchApplier.isInsertOnlyPatch(patch);
}

/// 人手の「選択範囲を置換」用。先頭 hunk の **+ 行**（修正後）。取れないときは緩和フォールバック。
String? codingAssistPatchReplacementBody(CodingProposedPatch patch) {
  if (patch.isAddFile) {
    final addBody =
        CodingPatchApplier.addFileContent(patch) ??
        patch.newSnippet?.replaceAll('\r\n', '\n');
    if (addBody != null && addBody.isNotEmpty) return addBody;
  }
  if (patch.rawDiff.trim().isNotEmpty) {
    final changed = CodingPatchApplier.firstHunkInsertedContent(patch.rawDiff);
    if (changed != null && changed.isNotEmpty) return changed;
    final first = CodingPatchApplier.firstHunkNewContent(patch.rawDiff);
    if (first != null && first.isNotEmpty) return first;
    final loose = _looseReplacementFromRawDiff(patch.rawDiff);
    if (loose != null && loose.isNotEmpty) return loose;
  }
  final fromSnippet = patch.newSnippet?.replaceAll('\r\n', '\n');
  if (fromSnippet != null && fromSnippet.isNotEmpty) return fromSnippet;
  return null;
}

/// hunk 解析に失敗したとき用。`+` 行、無ければヘッダ／`-` 以外をコードとして拾う。
String? _looseReplacementFromRawDiff(String rawDiff) {
  final lines = rawDiff.replaceAll('\r\n', '\n').split('\n');
  final plus = <String>[];
  final plain = <String>[];
  for (final line in lines) {
    if (line.startsWith('***')) continue;
    if (line.startsWith('@@')) continue;
    if (line.startsWith('--- ') || line.startsWith('+++ ')) continue;
    if (line.startsWith('diff ') || line.startsWith('index ')) continue;
    if (line.trimRight() == '```' || line.startsWith('```')) continue;
    if (line.startsWith('-')) continue;
    if (line.startsWith('+')) {
      plus.add(line.substring(1));
      continue;
    }
    // +/- 無しの提案: 先頭スペースはインデントとして残す（文脈行として捨てない）
    if (line.trim().isEmpty) {
      if (plus.isNotEmpty) plus.add('');
      if (plain.isNotEmpty) plain.add('');
      continue;
    }
    plain.add(line);
  }
  String joinTrim(List<String> xs) {
    while (xs.isNotEmpty && xs.last.isEmpty) {
      xs.removeLast();
    }
    return xs.join('\n');
  }

  if (plus.isNotEmpty) {
    final t = joinTrim(plus);
    if (t.isNotEmpty) return t;
  }
  if (plain.isNotEmpty) {
    final t = joinTrim(plain);
    if (t.isNotEmpty) return t;
  }
  return null;
}

/// カード表示用。先頭 hunk の -/+ だけ（修正項目の一覧）。
String? codingAssistPatchChangedItemsPreview(CodingProposedPatch patch) {
  if (patch.isAddFile) return null;
  if (patch.rawDiff.trim().isEmpty) return null;
  return CodingPatchApplier.firstHunkChangedLinesPreview(patch.rawDiff);
}

/// カード差分プレビュー用。取れないときは置換本文を追加側だけに載せる。
CodingPatchDiffPreview? codingAssistPatchDiffPreview(
  CodingProposedPatch patch,
) {
  if (patch.rawDiff.trim().isNotEmpty) {
    final fromHunk = CodingPatchApplier.firstHunkDiffPreview(patch.rawDiff);
    if (fromHunk != null && !fromHunk.isEmpty) return fromHunk;
  }
  if (patch.isAddFile) {
    final add =
        CodingPatchApplier.addFileContent(patch) ??
        patch.newSnippet?.replaceAll('\r\n', '\n');
    if (add != null && add.isNotEmpty) {
      return CodingPatchDiffPreview(
        deletedLines: const [],
        insertedLines: add.split('\n'),
      );
    }
  }
  final body = codingAssistPatchReplacementBody(patch);
  if (body != null && body.isNotEmpty) {
    return CodingPatchDiffPreview(
      deletedLines: const [],
      insertedLines: body.split('\n'),
    );
  }
  return null;
}

class _PatchCard extends StatelessWidget {
  const _PatchCard({
    required this.patch,
    required this.onReplaceSelection,
    required this.onInsertAtCursor,
  });
  final CodingProposedPatch patch;
  final Future<void> Function(CodingProposedPatch patch) onReplaceSelection;
  final Future<void> Function(CodingProposedPatch patch) onInsertAtCursor;

  @override
  Widget build(BuildContext context) {
    final isCreate = patch.isAddFile;
    final isInsert = !isCreate && codingAssistIsNewFunctionInsertPatch(patch);
    final isApplied = patch.status == CodingPatchStatus.applied;
    final insertLine = patch.suggestedInsertLine;
    final title = isCreate
        ? 'ファイル作成案'
        : isInsert
        ? '新規関数案（挿入）'
        : '修正ソース案（関数単位）';
    final diffCaption = isCreate
        ? '追加プレビュー'
        : isInsert
        ? (insertLine != null
              ? '追加プレビュー（$insertLine 行目へ挿入）'
              : '追加プレビュー（カーソル位置へ挿入）')
        : '差分プレビュー（関数単位）';
    final diff = codingAssistPatchDiffPreview(patch);
    final source = codingAssistPatchReplacementBody(patch);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  if (isApplied)
                    Text(
                      '適用済み',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                ],
              ),
            ),
            Text(
              isCreate ? '作成先: ${patch.relativePath}' : patch.relativePath,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (isInsert) ...[
              const SizedBox(height: 2),
              Text(
                insertLine != null
                    ? '挿入行: $insertLine（この行の先頭に挿入）'
                    : '挿入行: 未指定（カーソル位置へ挿入）',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ] else if (patch.suggestedReplaceStart != null &&
                patch.suggestedReplaceEnd != null) ...[
              const SizedBox(height: 2),
              Text(
                '置換範囲: ${patch.suggestedReplaceStart}-${patch.suggestedReplaceEnd} 行'
                '（自動実行でこの範囲を置換）',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 4),
            if (diff != null)
              _PatchDiffPreviewPane(caption: diffCaption, diff: diff)
            else
              SizedBox(
                height: 200,
                child: SingleChildScrollView(
                  child: SelectableText(
                    source ?? patch.rawDiff,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            if (patch.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  patch.errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (isApplied) ...[
                  OutlinedButton(
                    onPressed: () => context.read<CodingAssistBloc>().add(
                      CodingAssistRejectPatchRequested(patch.id),
                    ),
                    child: const Text('閉じる'),
                  ),
                ] else if (isCreate) ...[
                  if (patch.errorMessage == codingAddFileExistsMessage) ...[
                    FilledButton(
                      onPressed: () => context.read<CodingAssistBloc>().add(
                        CodingAssistAddFileConflictChoiceRequested(
                          patch.id,
                          CodingAddFileConflictChoice.reviseExisting,
                        ),
                      ),
                      child: const Text('既存を修正'),
                    ),
                    FilledButton.tonal(
                      onPressed: () => context.read<CodingAssistBloc>().add(
                        CodingAssistAddFileConflictChoiceRequested(
                          patch.id,
                          CodingAddFileConflictChoice.chooseNewPath,
                        ),
                      ),
                      child: const Text('別パスで作成'),
                    ),
                  ] else
                    FilledButton(
                      onPressed: () => context.read<CodingAssistBloc>().add(
                        CodingAssistApproveCreateFileRequested(patch.id),
                      ),
                      child: const Text('作成'),
                    ),
                  OutlinedButton(
                    onPressed: () => context.read<CodingAssistBloc>().add(
                      CodingAssistRejectPatchRequested(patch.id),
                    ),
                    child: const Text('却下'),
                  ),
                ] else ...[
                  FilledButton(
                    onPressed: () => isInsert
                        ? onInsertAtCursor(patch)
                        : onReplaceSelection(patch),
                    child: Text(
                      isInsert
                          ? (insertLine != null
                                ? '$insertLine 行目に挿入'
                                : 'カーソル位置に挿入')
                          : '選択範囲を置換',
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () => context.read<CodingAssistBloc>().add(
                      CodingAssistRejectPatchRequested(patch.id),
                    ),
                    child: const Text('却下'),
                  ),
                  if (!isInsert)
                    TextButton(
                      onPressed: () => context.read<CodingAssistBloc>().add(
                        CodingAssistApplyPatchRequested(patch.id),
                      ),
                      child: const Text('自動適用'),
                    ),
                  TextButton(
                    onPressed: () => context.read<CodingAssistBloc>().add(
                      CodingAssistReproposePatchRequested(patch.id),
                    ),
                    child: const Text('現状で再提案'),
                  ),
                ],
                if (source != null && source.isNotEmpty)
                  TextButton(
                    onPressed: () => _copyPatchSource(context, source),
                    child: const Text('ソースをコピー'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _copyPatchSource(BuildContext context, String source) async {
  await Clipboard.setData(ClipboardData(text: source));
  if (!context.mounted) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: Text('ソースをコピーしました')));
}

/// カード内の行色分け差分（Phase 1）。
class _PatchDiffPreviewPane extends StatelessWidget {
  const _PatchDiffPreviewPane({required this.caption, required this.diff});

  final String caption;
  final CodingPatchDiffPreview diff;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          caption,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colors.contentMuted,
              ),
        ),
        const SizedBox(height: 4),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: colors.subtleBorder),
            borderRadius: BorderRadius.circular(4),
          ),
          child: SizedBox(
            height: 220,
            child: SelectionArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final line in diff.deletedLines)
                      _PatchDiffLine(
                        prefix: '-',
                        text: line,
                        background: colors.diffRemoveBackground,
                        foreground: colors.diffRemoveForeground,
                        selectable: false,
                      ),
                    for (final line in diff.insertedLines)
                      _PatchDiffLine(
                        prefix: '+',
                        text: line,
                        background: colors.diffAddBackground,
                        foreground: colors.diffAddForeground,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PatchDiffLine extends StatelessWidget {
  const _PatchDiffLine({
    required this.prefix,
    required this.text,
    required this.background,
    required this.foreground,
    this.selectable = true,
  });

  final String prefix;
  final String text;
  final Color background;
  final Color foreground;

  /// 追加側だけ選択できる。削除行と `+`／`-` はコピーに含めない。
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: 'monospace',
      fontSize: 11,
      height: 1.35,
      color: foreground,
    );
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectionContainer.disabled(child: Text(prefix, style: style)),
        Expanded(child: Text(text, style: style)),
      ],
    );
    return ColoredBox(
      color: background,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        child: selectable ? row : SelectionContainer.disabled(child: row),
      ),
    );
  }
}
