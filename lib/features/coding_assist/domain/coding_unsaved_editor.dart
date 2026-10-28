import 'entities/coding_assist_entities.dart';

/// ページを離れる前に確認が要るか。
///
/// タブの dirty に加え、入力イベントが状態へ届く前のバッファ差分も見る。
/// 分割中の右ペインは [secondPath]／[secondBuffer]。
bool codingEditorHasUnsavedChanges({
  required Iterable<CodingOpenTab> tabs,
  String? editorPath,
  String? editorBuffer,
  String? secondPath,
  String? secondBuffer,
}) {
  if (tabs.any((tab) => tab.dirty)) return true;
  if (_bufferDiffers(tabs, editorPath, editorBuffer)) return true;
  if (_bufferDiffers(tabs, secondPath, secondBuffer)) return true;
  return false;
}

bool _bufferDiffers(
  Iterable<CodingOpenTab> tabs,
  String? editorPath,
  String? editorBuffer,
) {
  if (editorPath == null || editorBuffer == null) return false;
  for (final tab in tabs) {
    if (tab.relativePath == editorPath) {
      return tab.content != editorBuffer;
    }
  }
  return false;
}
