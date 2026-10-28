import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// 最小 LSP クライアント（initialize / document sync / completion）。
class DartAnalysisServerClient {
  Process? _process;
  final _stdoutBuf = BytesBuilder(copy: false);
  final _pending = <int, Completer<Object?>>{};
  int _nextId = 1;
  bool _started = false;
  String? _workspaceRoot;
  StreamSubscription<List<int>>? _stdoutSub;
  StreamSubscription<List<int>>? _stderrSub;

  bool get isRunning => _started && _process != null;

  String? get workspaceRoot => _workspaceRoot;

  Future<void> start({
    required String executable,
    List<String> arguments = const ['language-server', '--protocol=lsp'],
    required String workspaceRoot,
    Map<String, String>? environment,
  }) async {
    await stop();
    final root = workspaceRoot.trim();
    if (root.isEmpty) {
      throw StateError('workspaceRoot が空です');
    }
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: root,
      environment: environment ?? Platform.environment,
    );
    _process = process;
    _workspaceRoot = root;
    _stdoutSub = process.stdout.listen(_onStdout);
    _stderrSub = process.stderr.listen((_) {});

    final rootUri = Uri.file(root, windows: Platform.isWindows).toString();
    await _request('initialize', {
      'processId': pid,
      'rootUri': rootUri,
      'capabilities': {
        'textDocument': {
          'completion': {
            'completionItem': {
              'snippetSupport': false,
            },
          },
          'definition': {'linkSupport': true},
          'documentSymbol': {
            'hierarchicalDocumentSymbolSupport': true,
          },
          'references': {},
          'synchronization': {
            'didSave': false,
            'willSave': false,
          },
        },
        'workspace': {
          'workspaceFolders': true,
          'symbol': {},
        },
      },
      'workspaceFolders': [
        {'uri': rootUri, 'name': 'workspace'},
      ],
      'clientInfo': {'name': 'lmcode', 'version': '1.0'},
    });
    await _notify('initialized', {});
    _started = true;
  }

  Future<void> stop() async {
    _started = false;
    for (final c in _pending.values) {
      if (!c.isCompleted) {
        c.completeError(StateError('Dart language-server 停止'));
      }
    }
    _pending.clear();
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    final proc = _process;
    _process = null;
    _workspaceRoot = null;
    _stdoutBuf.clear();
    if (proc != null) {
      proc.kill(ProcessSignal.sigterm);
      // ignore: unawaited_futures
      proc.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          proc.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
    }
  }

  Future<void> didOpen({
    required String uri,
    required String text,
    required int version,
    String languageId = 'dart',
  }) {
    return _notify('textDocument/didOpen', {
      'textDocument': {
        'uri': uri,
        'languageId': languageId,
        'version': version,
        'text': text,
      },
    });
  }

  Future<void> didChange({
    required String uri,
    required String text,
    required int version,
  }) {
    return _notify('textDocument/didChange', {
      'textDocument': {
        'uri': uri,
        'version': version,
      },
      'contentChanges': [
        {'text': text},
      ],
    });
  }

  Future<void> didClose({required String uri}) {
    return _notify('textDocument/didClose', {
      'textDocument': {'uri': uri},
    });
  }

  Future<List<DartLspCompletionItem>> completion({
    required String uri,
    required int line,
    required int character,
  }) async {
    if (!isRunning) return const [];
    final result = await _request('textDocument/completion', {
      'textDocument': {'uri': uri},
      'position': {'line': line, 'character': character},
    });
    return _parseCompletionList(result);
  }

  Future<Object?> definition({
    required String uri,
    required int line,
    required int character,
  }) {
    return _request('textDocument/definition', {
      'textDocument': {'uri': uri},
      'position': {'line': line, 'character': character},
    });
  }

  Future<Object?> documentSymbol({required String uri}) {
    return _request(
      'textDocument/documentSymbol',
      {
        'textDocument': {'uri': uri},
      },
      timeout: const Duration(seconds: 30),
    );
  }

  Future<Object?> workspaceSymbol({required String query}) {
    return _request(
      'workspace/symbol',
      {'query': query},
      timeout: const Duration(seconds: 45),
    );
  }

  Future<Object?> references({
    required String uri,
    required int line,
    required int character,
    bool includeDeclaration = true,
  }) {
    return _request(
      'textDocument/references',
      {
        'textDocument': {'uri': uri},
        'position': {'line': line, 'character': character},
        'context': {'includeDeclaration': includeDeclaration},
      },
      timeout: const Duration(seconds: 30),
    );
  }

  List<DartLspCompletionItem> _parseCompletionList(Object? result) {
    if (result == null) return const [];
    List<dynamic> items;
    if (result is List) {
      items = result;
    } else if (result is Map) {
      final list = result['items'];
      if (list is! List) return const [];
      items = list;
    } else {
      return const [];
    }
    final out = <DartLspCompletionItem>[];
    for (final raw in items) {
      if (raw is! Map) continue;
      final label = '${raw['label'] ?? ''}'.trim();
      if (label.isEmpty) continue;
      String insertText = label;
      final insert = raw['insertText'];
      if (insert is String && insert.isNotEmpty) {
        insertText = insert;
      } else {
        final te = raw['textEdit'];
        if (te is Map && te['newText'] is String) {
          insertText = te['newText'] as String;
        }
      }
      // スニペット $0 等は簡易除去
      insertText = insertText.replaceAll(RegExp(r'\$\{?\d+:?[^}]*\}?'), '');
      final detail = raw['detail'] is String ? raw['detail'] as String : null;
      final kind = raw['kind'] is int ? raw['kind'] as int : null;
      out.add(
        DartLspCompletionItem(
          label: label,
          insertText: insertText,
          detail: detail,
          kind: kind,
        ),
      );
      if (out.length >= 80) break;
    }
    return out;
  }

  Future<Object?> _request(
    String method,
    Map<String, dynamic> params, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _writeMessage({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    });
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('LSP $method timeout');
      },
    );
  }

  Future<void> _notify(String method, Map<String, dynamic> params) async {
    _writeMessage({
      'jsonrpc': '2.0',
      'method': method,
      'params': params,
    });
  }

  void _writeMessage(Map<String, dynamic> message) {
    final proc = _process;
    if (proc == null) return;
    final body = jsonEncode(message);
    final header = 'Content-Length: ${utf8.encode(body).length}\r\n\r\n';
    proc.stdin.add(utf8.encode(header));
    proc.stdin.add(utf8.encode(body));
  }

  void _onStdout(List<int> chunk) {
    _stdoutBuf.add(chunk);
    while (true) {
      final bytes = _stdoutBuf.toBytes();
      final sep = _indexOfHeaderBodySep(bytes);
      if (sep < 0) {
        _stdoutBuf.clear();
        _stdoutBuf.add(bytes);
        return;
      }
      final header = utf8.decode(bytes.sublist(0, sep), allowMalformed: true);
      final match = RegExp(
        r'Content-Length:\s*(\d+)',
        caseSensitive: false,
      ).firstMatch(header);
      if (match == null) {
        // 壊れたヘッダは破棄して継続
        _stdoutBuf.clear();
        _stdoutBuf.add(bytes.sublist(sep + 4));
        continue;
      }
      final length = int.parse(match.group(1)!);
      final bodyStart = sep + 4;
      if (bytes.length < bodyStart + length) {
        _stdoutBuf.clear();
        _stdoutBuf.add(bytes);
        return;
      }
      final bodyBytes = bytes.sublist(bodyStart, bodyStart + length);
      final rest = bytes.sublist(bodyStart + length);
      _stdoutBuf.clear();
      if (rest.isNotEmpty) _stdoutBuf.add(rest);
      try {
        final decoded = jsonDecode(utf8.decode(bodyBytes));
        if (decoded is Map<String, dynamic>) {
          _handleMessage(decoded);
        } else if (decoded is Map) {
          _handleMessage(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {
        // 無視して次へ
      }
    }
  }

  int _indexOfHeaderBodySep(List<int> bytes) {
    for (var i = 0; i + 3 < bytes.length; i++) {
      if (bytes[i] == 13 &&
          bytes[i + 1] == 10 &&
          bytes[i + 2] == 13 &&
          bytes[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }

  void _handleMessage(Map<String, dynamic> message) {
    if (message.containsKey('id') &&
        (message.containsKey('result') || message.containsKey('error'))) {
      final id = message['id'];
      final idInt = id is int ? id : int.tryParse('$id');
      if (idInt == null) return;
      final completer = _pending.remove(idInt);
      if (completer == null || completer.isCompleted) return;
      if (message.containsKey('error')) {
        completer.completeError(
          StateError('LSP error: ${message['error']}'),
        );
      } else {
        completer.complete(message['result']);
      }
      return;
    }
    // server → client 通知は無視（diagnostics 等）
  }
}

class DartLspCompletionItem {
  const DartLspCompletionItem({
    required this.label,
    required this.insertText,
    this.detail,
    this.kind,
  });

  final String label;
  final String insertText;
  final String? detail;
  final int? kind;
}
