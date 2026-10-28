import 'package:flutter/widgets.dart';
import 'package:re_editor/re_editor.dart';

/// S16 用。ブロックコメント（⌘⇧/）は macOS Help 検索と競合するため無効化。
class CodingAssistShortcutsActivatorsBuilder
    extends DefaultCodeShortcutsActivatorsBuilder {
  const CodingAssistShortcutsActivatorsBuilder();

  @override
  List<ShortcutActivator>? build(CodeShortcutType type) {
    if (type == CodeShortcutType.multiLineComment) {
      return const [];
    }
    return super.build(type);
  }
}
