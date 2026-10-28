import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';

import '../../data/coding_lsp_symbol_index.dart';
import '../../data/dart_analysis_server_client.dart';
import '../../data/dart_sdk_resolver.dart';
import '../../domain/coding_dart_definition.dart';

/// 入力中補完が読む LSP。Dart と Swift で共有する。
abstract class CodingLspCompletionSource {
  bool get isReady;
  Map<String, CodeAutocompleteEditingValue> get cache;
  Set<String> get emptyKeys;
  Future<List<DartLspCompletionItem>> requestCompletion({
    required String absolutePath,
    required String content,
    required int line,
    required int character,
  });
}

/// WS オープン時に起動し、Dart 補完を橋渡しする（キャッシュ＋デバウンス＋ notifier 更新）。
class CodingDartLspController extends ChangeNotifier
    implements CodingLspCompletionSource {
  DartAnalysisServerClient? _client;
  CodingLspSymbolIndex? _symbols;
  String? _status;
  String? _workspaceRoot;
  bool _disposed = false;
  final _docVersions = <String, int>{};
  final _openUris = <String>{};

  /// 補完キャッシュ（key → prompts）。
  @override
  final Map<String, CodeAutocompleteEditingValue> cache = {};

  /// 候補0件だったキー（リスト非表示用）。
  @override
  final Set<String> emptyKeys = {};

  String? get statusMessage => _status;
  @override
  bool get isReady => _client?.isRunning == true;
  CodingLspSymbolIndex? get symbols => isReady ? _symbols : null;
  String? get workspaceRoot => _workspaceRoot;

  Future<void> attachWorkspace({
    required String workspaceRoot,
    required String? dartSdkPathSetting,
  }) async {
    final root = workspaceRoot.trim();
    if (root.isEmpty) {
      await detach();
      return;
    }
    if (_workspaceRoot == root && isReady) return;

    await detach();
    if (_disposed) return;
    _workspaceRoot = root;
    _setStatus('Dart補完: SDK を解決中…');

    final dartBin = await DartSdkResolver.resolveDartExecutable(
      dartSdkPathSetting,
    );
    if (_disposed) return;
    if (dartBin == null) {
      _setStatus('Dart補完: SDK 未検出（S11 でパスを設定）');
      return;
    }

    final client = DartAnalysisServerClient();
    try {
      await client.start(executable: dartBin, workspaceRoot: root);
      if (_disposed) {
        await client.stop();
        return;
      }
      _client = client;
      _symbols = CodingLspSymbolIndex(
        client: client,
        workspaceRoot: root,
        syncDocument: syncDocument,
      );
      _setStatus('Dart補完: 準備完了');
    } catch (e) {
      await client.stop();
      if (_disposed) return;
      _client = null;
      _setStatus('Dart補完: 起動失敗（$e）');
    }
  }

  Future<void> detach() async {
    cache.clear();
    emptyKeys.clear();
    _docVersions.clear();
    _openUris.clear();
    final client = _client;
    _client = null;
    _symbols = null;
    _workspaceRoot = null;
    if (client != null) {
      await client.stop();
    }
    _setStatus(null);
  }

  static String fileUriFor(String absolutePath) {
    return Uri.file(
      p.normalize(absolutePath),
      windows: Platform.isWindows,
    ).toString();
  }

  Future<void> syncDocument({
    required String absolutePath,
    required String content,
  }) async {
    final client = _client;
    if (client == null || !client.isRunning) return;
    if (!absolutePath.toLowerCase().endsWith('.dart')) return;

    final uri = fileUriFor(absolutePath);
    final next = (_docVersions[uri] ?? 0) + 1;
    _docVersions[uri] = next;
    try {
      if (_openUris.contains(uri)) {
        await client.didChange(uri: uri, text: content, version: next);
      } else {
        await client.didOpen(uri: uri, text: content, version: next);
        _openUris.add(uri);
      }
    } catch (_) {
      // 補完のみ失敗扱いにし、編集は継続
    }
  }

  Future<void> closeDocument(String absolutePath) async {
    final client = _client;
    if (client == null) return;
    final uri = fileUriFor(absolutePath);
    _openUris.remove(uri);
    _docVersions.remove(uri);
    try {
      await client.didClose(uri: uri);
    } catch (_) {}
  }

  @override
  Future<List<DartLspCompletionItem>> requestCompletion({
    required String absolutePath,
    required String content,
    required int line,
    required int character,
  }) async {
    final client = _client;
    if (client == null || !client.isRunning) return const [];
    await syncDocument(absolutePath: absolutePath, content: content);
    try {
      return await client.completion(
        uri: fileUriFor(absolutePath),
        line: line,
        character: character,
      );
    } catch (_) {
      return const [];
    }
  }

  /// 選択位置の定義（宣言範囲）を、開いているファイルまたはディスクから抜粋する。
  Future<CodingDartDefinitionSnippet?> definitionAt({
    required String absolutePath,
    required String content,
    required int line,
    required int character,
  }) async {
    final client = _client;
    if (client == null || !client.isRunning) return null;
    await syncDocument(absolutePath: absolutePath, content: content);
    Object? raw;
    try {
      raw = await client.definition(
        uri: fileUriFor(absolutePath),
        line: line,
        character: character,
      );
    } catch (_) {
      return null;
    }
    final location = codingDartDefinitionLocation(raw);
    if (location == null) return null;
    final targetPath = _filePathFromUri(location.uri);
    if (targetPath == null) return null;
    final openPath = p.normalize(absolutePath);
    final resolved = p.normalize(targetPath);
    String source;
    if (resolved == openPath) {
      source = content;
    } else {
      final file = File(resolved);
      if (!await file.exists()) return null;
      try {
        source = await file.readAsString();
      } catch (_) {
        return null;
      }
    }
    return codingDartDefinitionSnippet(
      source: source,
      location: location,
      fileLabel: p.basename(resolved),
    );
  }

  String? _filePathFromUri(String uri) {
    final parsed = Uri.tryParse(uri);
    if (parsed == null || parsed.scheme != 'file') return null;
    try {
      return parsed.toFilePath(windows: Platform.isWindows);
    } catch (_) {
      return null;
    }
  }

  void _setStatus(String? value) {
    if (_disposed) return;
    if (_status == value) return;
    _status = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    // 画面を閉じたあとも language-server は止める。通知は _disposed で抑止する。
    // ignore: discarded_futures
    detach();
    super.dispose();
  }
}

/// 同期 build ← キャッシュ、非同期 LSP で埋めて notifier を更新。
class CodingDartLspPromptsBuilder implements CodeAutocompletePromptsBuilder {
  CodingDartLspPromptsBuilder({
    required this.lsp,
    required this.absolutePath,
    required this.fullText,
    required this.onNotifierReady,
    this.pathSuffix = '.dart',
  });

  final CodingLspCompletionSource lsp;
  final String absolutePath;
  final String pathSuffix;
  String fullText;

  /// show() 直後の viewBuilder から notifier を受け取り、LSP 結果で更新する。
  final void Function(ValueNotifier<CodeAutocompleteEditingValue> notifier)
      onNotifierReady;

  ValueNotifier<CodeAutocompleteEditingValue>? _activeNotifier;
  int _seq = 0;
  Timer? _debounce;

  /// LSP 待ち中（リストは出さない。Enter しても入力を変えにくいスタブ）。
  bool awaitingFetch = false;

  void bindNotifier(ValueNotifier<CodeAutocompleteEditingValue> notifier) {
    _activeNotifier = notifier;
    onNotifierReady(notifier);
  }

  @override
  CodeAutocompleteEditingValue? build(
    BuildContext context,
    CodeLine codeLine,
    CodeLineSelection selection,
  ) {
    if (!lsp.isReady) return null;
    if (!absolutePath.toLowerCase().endsWith(pathSuffix)) return null;
    if (!selection.isCollapsed) return null;

    final parsed = _parsePrefix(codeLine.text, selection.extentOffset);
    if (parsed == null) return null;

    final key = _cacheKey(
      absolutePath: absolutePath,
      line: selection.extentIndex,
      offset: selection.extentOffset,
      input: parsed.input,
      afterDot: parsed.afterDot,
    );

    if (lsp.emptyKeys.contains(key)) return null;

    final cached = lsp.cache[key];
    if (cached != null) {
      awaitingFetch = false;
      return cached;
    }

    _scheduleFetch(
      key: key,
      line: selection.extentIndex,
      character: selection.extentOffset,
      input: parsed.input,
    );

    // オーバーレイ枠だけ用意。表示は候補到着後。word=input で誤確定しても無変化。
    awaitingFetch = true;
    return CodeAutocompleteEditingValue(
      input: parsed.input,
      prompts: [CodeKeywordPrompt(word: parsed.input)],
      index: 0,
    );
  }

  void _scheduleFetch({
    required String key,
    required int line,
    required int character,
    required String input,
  }) {
    _debounce?.cancel();
    final seq = ++_seq;
    _debounce = Timer(const Duration(milliseconds: 80), () async {
      final items = await lsp.requestCompletion(
        absolutePath: absolutePath,
        content: fullText,
        line: line,
        character: character,
      );
      if (seq != _seq) return;

      final prompts = <CodePrompt>[];
      for (final item in items) {
        final word = item.insertText.isNotEmpty ? item.insertText : item.label;
        if (input.isNotEmpty &&
            !word.toLowerCase().startsWith(input.toLowerCase()) &&
            !item.label.toLowerCase().startsWith(input.toLowerCase())) {
          // メンバ補完（. 直後）は prefix 空なので通す
          if (input.isNotEmpty) continue;
        }
        final type = item.detail?.trim();
        if (type != null && type.isNotEmpty) {
          prompts.add(CodeFieldPrompt(word: word, type: type));
        } else {
          prompts.add(CodeKeywordPrompt(word: word));
        }
      }
      if (prompts.isEmpty) {
        awaitingFetch = false;
        lsp.cache.remove(key);
        lsp.emptyKeys.add(key);
        // 開いているオーバーレイを、テキスト変更なしで閉じる
        _dismissOverlayWithoutEdit(input);
        return;
      }

      awaitingFetch = false;
      lsp.emptyKeys.remove(key);
      final value = CodeAutocompleteEditingValue(
        input: input,
        prompts: prompts,
        index: 0,
      );
      lsp.cache[key] = value;
      final notifier = _activeNotifier;
      if (notifier != null) {
        notifier.value = value;
      }
    });
  }

  /// re_editor の onSelected 経由で dismiss（入力内容は変えない）。
  void _dismissOverlayWithoutEdit(String input) {
    final dismiss = _dismissOverlay;
    if (dismiss == null) return;
    dismiss(
      CodeAutocompleteResult(
        input: input,
        word: input,
        selection: const TextSelection.collapsed(offset: 0),
      ),
    );
  }

  ValueChanged<CodeAutocompleteResult>? _dismissOverlay;

  void bindDismissOverlay(
    ValueChanged<CodeAutocompleteResult> onSelected,
  ) {
    _dismissOverlay = onSelected;
  }

  static String _cacheKey({
    required String absolutePath,
    required int line,
    required int offset,
    required String input,
    required bool afterDot,
  }) {
    return '$absolutePath|$line|$offset|$afterDot|$input';
  }

  static ({String input, bool afterDot})? _parsePrefix(String text, int offset) {
    if (offset < 0 || offset > text.length) return null;
    final before = text.substring(0, offset);
    if (before.isEmpty) return null;

    if (before.endsWith('.')) {
      return (input: '', afterDot: true);
    }

    var start = before.length - 1;
    while (start >= 0) {
      final ch = before[start];
      if (!_isIdentChar(ch)) break;
      start--;
    }
    final input = before.substring(start + 1);
    if (input.isEmpty) return null;
    final afterDot = start >= 0 && before[start] == '.';
    return (input: input, afterDot: afterDot);
  }

  static bool _isIdentChar(String ch) {
    if (ch.length != 1) return false;
    final c = ch.codeUnitAt(0);
    return (c >= 65 && c <= 90) ||
        (c >= 97 && c <= 122) ||
        (c >= 48 && c <= 57) ||
        c == 95 ||
        c == 36;
  }
}

/// LSP 結果で notifier を更新する候補リスト。
class CodingDartCompletionListView extends StatefulWidget
    implements PreferredSizeWidget {
  const CodingDartCompletionListView({
    super.key,
    required this.notifier,
    required this.onSelected,
    required this.promptsBuilder,
  });

  final ValueNotifier<CodeAutocompleteEditingValue> notifier;
  final ValueChanged<CodeAutocompleteResult> onSelected;
  final CodingDartLspPromptsBuilder promptsBuilder;

  static const double _itemHeight = 28;

  @override
  Size get preferredSize {
    if (promptsBuilder.awaitingFetch || notifier.value.prompts.isEmpty) {
      return Size.zero;
    }
    final n = math.min(notifier.value.prompts.length, 10);
    return Size(320, _itemHeight * n + 2);
  }

  @override
  State<CodingDartCompletionListView> createState() =>
      _CodingDartCompletionListViewState();
}

class _CodingDartCompletionListViewState
    extends State<CodingDartCompletionListView> {
  @override
  void initState() {
    super.initState();
    widget.promptsBuilder.bindNotifier(widget.notifier);
    widget.promptsBuilder.bindDismissOverlay(widget.onSelected);
    widget.notifier.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant CodingDartCompletionListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notifier != widget.notifier ||
        oldWidget.onSelected != widget.onSelected ||
        oldWidget.promptsBuilder != widget.promptsBuilder) {
      oldWidget.notifier.removeListener(_onChanged);
      widget.notifier.addListener(_onChanged);
      widget.promptsBuilder.bindNotifier(widget.notifier);
      widget.promptsBuilder.bindDismissOverlay(widget.onSelected);
    }
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.notifier.value;
    final prompts = value.prompts;
    // 読込中・候補0件はリストを出さない
    if (widget.promptsBuilder.awaitingFetch || prompts.isEmpty) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final height = math.min(
      CodingDartCompletionListView._itemHeight * prompts.length,
      CodingDartCompletionListView._itemHeight * 10,
    );
    return Material(
      elevation: 6,
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints.tightFor(width: 320, height: height + 2),
        child: ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: value.prompts.length,
          itemBuilder: (context, index) {
            final prompt = value.prompts[index];
            final selected = index == value.index;
            final type = prompt is CodeFieldPrompt ? prompt.type : null;
            return InkWell(
              onTap: () {
                widget.onSelected(
                  value.copyWith(index: index).autocomplete,
                );
              },
              child: Container(
                height: CodingDartCompletionListView._itemHeight,
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                color: selected
                    ? scheme.primaryContainer.withValues(alpha: 0.55)
                    : null,
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        prompt.word,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontFamily: 'monospace',
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                    if (type != null && type.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        flex: 2,
                        child: Text(
                          type,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
