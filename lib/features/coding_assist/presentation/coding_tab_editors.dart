import 'package:flutter/widgets.dart';
import 'package:re_editor/re_editor.dart';

typedef CodingTabEditorReplace =
    void Function(CodeLineEditingController controller, String text);

/// 開いているファイルごとの [CodeLineEditingController]。
///
/// 画面のエディタは1つだが、Undo はコントローラに紐づく。タブ切替で同じ
/// コントローラへ本文を書き込むと、閉じたファイルが ⌘Z で戻る。
class CodingTabEditors {
  CodingTabEditors({int indentSize = 4, this.onSelectionChanged})
    : _indentSize = indentSize == 2 ? 2 : 4 {
    _idle = _createEmpty();
    active = _idle;
    findController = CodeFindController(active);
    active.addListener(_onSelection);
  }

  final VoidCallback? onSelectionChanged;

  final Map<String, CodeLineEditingController> _byPath = {};
  final List<CodeLineEditingController> _retiredControllers = [];
  final List<CodeFindController> _retiredFind = [];

  late CodeLineEditingController _idle;
  late CodeLineEditingController active;
  late CodeFindController findController;
  String? activePath;
  int _indentSize;
  bool _closed = false;

  CodeLineOptions get _options => CodeLineOptions(indentSize: _indentSize);

  CodeLineEditingController controllerFor(String path, String content) {
    final existing = _byPath[path];
    if (existing != null) return existing;
    final created = CodeLineEditingController.fromText(content, _options);
    _byPath[path] = created;
    return created;
  }

  CodeLineEditingController? peek(String path) => _byPath[path];

  void sync({
    required String? activePath,
    required List<({String path, String content})> tabs,
    required CodingTabEditorReplace replaceText,
  }) {
    final open = <String, String>{
      for (final tab in tabs) tab.path: tab.content,
    };
    final closed = _byPath.keys
        .where((path) => !open.containsKey(path))
        .toList();
    for (final path in closed) {
      _retiredControllers.add(_byPath.remove(path)!);
    }
    for (final entry in open.entries) {
      final existing = _byPath[entry.key];
      if (existing != null && existing.text != entry.value) {
        // IME 変換中や連打入力中に、遅れて届いた BLoC 本文でコントローラを
        // 上書きすると、変換が壊れ insert っぽい挙動やスペース欠落になる。
        if (existing.isComposing) continue;
        replaceText(existing, entry.value);
      }
    }
    if (activePath == null || !open.containsKey(activePath)) {
      if (_idle.text.isNotEmpty) {
        replaceText(_idle, '');
        _idle.clearHistory();
      }
      _bind(_idle, null);
      return;
    }
    final content = open[activePath]!;
    final controller = _byPath.putIfAbsent(
      activePath,
      () => CodeLineEditingController.fromText(content, _options),
    );
    _bind(controller, activePath);
  }

  /// インデント幅の変更時だけ作り直す。タブごとの Undo は捨てる（従来どおり）。
  void rebindIndent(int indentSize) {
    final size = indentSize == 2 ? 2 : 4;
    if (_indentSize == size) return;
    _indentSize = size;
    final snapshots = <String, ({String text, CodeLineSelection selection})>{
      for (final entry in _byPath.entries)
        entry.key: (text: entry.value.text, selection: entry.value.selection),
    };
    final previousPath = activePath;
    for (final controller in _byPath.values) {
      _retiredControllers.add(controller);
    }
    _byPath.clear();
    _retiredControllers.add(_idle);
    _idle = _createEmpty();
    for (final entry in snapshots.entries) {
      final controller = CodeLineEditingController.fromText(
        entry.value.text,
        _options,
      );
      try {
        controller.selection = entry.value.selection;
      } catch (_) {}
      controller.clearHistory();
      _byPath[entry.key] = controller;
    }
    if (previousPath != null && _byPath.containsKey(previousPath)) {
      _bind(_byPath[previousPath]!, previousPath);
    } else {
      _bind(_idle, null);
    }
  }

  /// 前フレームの [CodeEditor] がリスナーを外したあとで呼ぶ。
  void disposeRetired() {
    if (_closed) return;
    final finds = List<CodeFindController>.of(_retiredFind);
    _retiredFind.clear();
    for (final find in finds) {
      find.dispose();
    }
    final controllers = List<CodeLineEditingController>.of(_retiredControllers);
    _retiredControllers.clear();
    for (final controller in controllers) {
      if (identical(controller, active) ||
          identical(controller, _idle) ||
          _byPath.containsValue(controller)) {
        continue;
      }
      controller.dispose();
    }
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    active.removeListener(_onSelection);
    findController.dispose();
    for (final find in _retiredFind) {
      find.dispose();
    }
    _retiredFind.clear();
    final controllers = <CodeLineEditingController>{
      ..._byPath.values,
      _idle,
      ..._retiredControllers,
    };
    _byPath.clear();
    _retiredControllers.clear();
    for (final controller in controllers) {
      controller.dispose();
    }
  }

  void _bind(CodeLineEditingController next, String? path) {
    if (identical(active, next) && activePath == path) return;
    active.removeListener(_onSelection);
    _retiredFind.add(findController);
    active = next;
    activePath = path;
    findController = CodeFindController(active);
    active.addListener(_onSelection);
    _onSelection();
  }

  void _onSelection() {
    onSelectionChanged?.call();
  }

  CodeLineEditingController _createEmpty() {
    return CodeLineEditingController(options: _options);
  }
}
