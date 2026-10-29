import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';

import '../../data/coding_lsp_symbol_index.dart';
import '../../data/dart_analysis_server_client.dart';
import '../../data/sourcekit_toolchain.dart';
import '../../data/swift_build_server.dart';
import '../../domain/coding_dart_definition.dart';
import '../../domain/coding_swift_launch.dart';
import 'coding_dart_completion.dart';

/// WS オープン時に sourcekit-lsp を起動し、Swift の補完と定義を橋渡しする。
class CodingSwiftLspController extends ChangeNotifier
    implements CodingLspCompletionSource {
  DartAnalysisServerClient? _client;
  CodingLspSymbolIndex? _symbols;
  SwiftBuildServerFiles? _bridge;
  String? _status;
  String? _workspaceRoot;
  bool _disposed = false;
  int _attachTicket = 0;
  final _docVersions = <String, int>{};
  final _openUris = <String>{};

  @override
  final Map<String, CodeAutocompleteEditingValue> cache = {};

  @override
  final Set<String> emptyKeys = {};

  String? get statusMessage => _status;

  @override
  bool get isReady => _client?.isRunning == true;
  CodingLspSymbolIndex? get symbols => isReady ? _symbols : null;

  String? get workspaceRoot => _workspaceRoot;

  Future<void> attachWorkspace({required String workspaceRoot}) async {
    final ticket = ++_attachTicket;
    await _shutdown();
    if (!_current(ticket)) return;
    // SourceKit-LSP は macOS＋Xcode のみ。Windows／Linux では起動しない。
    if (!Platform.isMacOS) {
      _setStatus(null);
      return;
    }
    final root = workspaceRoot.trim();
    if (root.isEmpty) {
      _setStatus(null);
      return;
    }
    _workspaceRoot = root;
    _setStatus('Swift補完: Xcode を解決中…');

    final toolchain = await SourceKitToolchain.resolve();
    if (!_current(ticket)) return;
    if (toolchain == null) {
      _setStatus('Swift補完: sourcekit-lsp 未検出（xcode-select で Xcode を選んでください）');
      return;
    }

    final plan = inspectSwiftWorkspaceRoot(root);
    if (!_current(ticket)) return;
    if (plan.kind == CodingSwiftRootKind.inactive) {
      _workspaceRoot = null;
      _setStatus(null);
      return;
    }
    if (plan.kind == CodingSwiftRootKind.blocked) {
      _setStatus(plan.message);
      return;
    }

    if (plan.kind == CodingSwiftRootKind.xcodeProject) {
      _setStatus('Swift補完: 索引設定を取得中…');
      final projectPath = p.join(root, plan.xcodeprojName!);
      final settings = await loadXcodeIndexSettings(
        toolchain: toolchain,
        projectPath: projectPath,
      );
      if (!_current(ticket)) return;
      if (settings == null) {
        _setStatus('Swift補完: 索引設定の取得に失敗');
        return;
      }
      if (settings.schemes.length != 1) {
        _setStatus(
          settings.schemes.isEmpty
              ? 'Swift補完: スキームが無いためオフ'
              : 'Swift補完: スキームが複数のためオフ',
        );
        return;
      }
      if (!settings.loaded) {
        _setStatus('Swift補完: 索引設定の取得に失敗');
        return;
      }
      final bridge = await SwiftBuildServerFiles.install(
        workspaceRoot: root,
        compilerArguments: settings.compilerArguments,
      );
      if (!_current(ticket)) {
        await bridge?.removeOwnedBuildServer();
        return;
      }
      if (bridge == null) {
        _setStatus('Swift補完: python3 未検出');
        return;
      }
      _bridge = bridge;
    }

    final client = DartAnalysisServerClient();
    try {
      await client.start(
        executable: toolchain.sourceKitLsp,
        arguments: const [],
        workspaceRoot: root,
        environment: toolchain.environment,
      );
      if (!_current(ticket)) {
        await client.stop();
        await _bridge?.removeOwnedBuildServer();
        _bridge = null;
        return;
      }
      _client = client;
      _symbols = CodingLspSymbolIndex(
        client: client,
        workspaceRoot: root,
        syncDocument: syncDocument,
      );
      _setStatus('Swift補完: 準備完了');
    } catch (e) {
      await client.stop();
      await _bridge?.removeOwnedBuildServer();
      _bridge = null;
      if (!_current(ticket)) return;
      _client = null;
      _setStatus('Swift補完: 起動失敗');
    }
  }

  Future<void> detach() async {
    _attachTicket++;
    await _shutdown();
    _setStatus(null);
  }

  bool _current(int ticket) => !_disposed && ticket == _attachTicket;

  Future<void> _shutdown() async {
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
    final bridge = _bridge;
    _bridge = null;
    if (bridge != null) {
      await bridge.removeOwnedBuildServer();
    }
  }

  static String fileUriFor(String absolutePath) {
    return Uri.file(p.normalize(absolutePath), windows: false).toString();
  }

  Future<void> syncDocument({
    required String absolutePath,
    required String content,
  }) async {
    final client = _client;
    if (client == null || !client.isRunning) return;
    if (!absolutePath.toLowerCase().endsWith('.swift')) return;

    final uri = fileUriFor(absolutePath);
    final next = (_docVersions[uri] ?? 0) + 1;
    _docVersions[uri] = next;
    try {
      if (_openUris.contains(uri)) {
        await client.didChange(uri: uri, text: content, version: next);
      } else {
        await client.didOpen(
          uri: uri,
          text: content,
          version: next,
          languageId: 'swift',
        );
        _openUris.add(uri);
      }
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
    final located = codingDartDefinitionLocation(raw);
    if (located == null) return null;
    final targetPath = _filePathFromUri(located.uri);
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
    final location = codingSwiftExpandPointDefinition(
      location: located,
      source: source,
    );
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
      return parsed.toFilePath(windows: false);
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
    // ignore: discarded_futures
    detach();
    super.dispose();
  }
}
