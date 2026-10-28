import 'coding_agent_tools.dart';
import 'coding_harness_settings.dart';
import 'entities/coding_assist_entities.dart';

/// Agent 向け API 履歴の組み立て（S16 §5.7 P0／P1／自動実行の毎回圧縮）。
///
/// UI／永続の [CodingChatMessage] は変更せず、送信ビューだけ圧縮する。
/// - 直近 [keepRecentUserTurns] ユーザーターン以外の tool 本文をスタブ化
/// - 同一相対 path の `read_file` は最新 1 件だけ全文
/// - [CodingThread.compactedSummary] がある場合、[compactedUpToExclusive] 未満を要約へ畳む
/// - [autoExecute] のときは 85% を待たず、各送信で作業記憶へ組み直す（§5.7.6）
/// - 検査・再指示は [buildDeliverableMessages]。ツール往復は載せず、成功本文を同梱する（§5.4）
abstract final class CodingApiContextBuilder {
  /// 直近何ユーザーターン分の tool を全文維持するか。
  static const keepRecentUserTurns = 3;

  /// 手動／自動圧縮時に残す直近ユーザーターン数。
  static const compactKeepRecentUserTurns = 1;

  /// 自動実行の作業記憶で、直前バッチ以外に全文で残す `read_file` の件数。
  static const autoExecuteKeptReads = 2;

  /// 検証ログから残す error 行の上限。
  static const autoExecuteMaxErrorLines = 40;

  static final RegExp _errorLine = RegExp(
    r'error|warning|failed|failure|exception|expected|fatal',
    caseSensitive: false,
  );

  static final RegExp _patchFile = RegExp(
    r'\*\*\*\s+(Update|Add)\s+File:\s*(\S+)',
  );

  static final RegExp _attachedFileBlock = RegExp(
    r'【開いているファイル: ([^】]+)】\n(?:```\n([\s\S]*?)\n```|（空ファイル）)',
  );

  static final RegExp _selectionBlock = RegExp(
    r'(【選択範囲】\nファイル: [^\n]+\n行: [^\n]+\n)```[\s\S]*?```',
  );

  static final RegExp _verifyHeader = RegExp(
    r'^【自動検証 (\d+)/(\d+)】(.*)$',
    multiLine: true,
  );

  static final RegExp _targetFile = RegExp(
    r'^対象ファイル:\s*(\S+)',
    multiLine: true,
  );

  static final RegExp _relPath = RegExp(r'(?:[\w.-]+/)+[\w.-]+\.[A-Za-z0-9]+');

  /// LLM 送信用 messages（system は別引数）。
  static List<Map<String, String>> buildApiMessages(
    List<CodingChatMessage> messages, {
    int? keepRecentUserTurns,
    String? compactedSummary,
    int compactedUpToExclusive = 0,
    bool symbolTools = false,
    bool autoExecute = false,
    List<String> pendingPatchPaths = const [],
    CodingHarnessSettings harness = CodingHarnessSettings.defaults,
    Set<String> restoreReadPaths = const {},
  }) {
    final keepTurns = keepRecentUserTurns ?? harness.keepRecentUserTurns;
    if (autoExecute) {
      return _buildAutoExecuteApiMessages(
        messages,
        compactedSummary: compactedSummary,
        compactedUpToExclusive: compactedUpToExclusive,
        symbolTools: symbolTools,
        pendingPatchPaths: pendingPatchPaths,
        harness: harness,
        restoreReadPaths: restoreReadPaths,
      );
    }
    final start = compactedUpToExclusive.clamp(0, messages.length);
    final slice = start > 0 ? messages.sublist(start) : messages;
    final fullTool = _toolIndicesKeptFull(
      slice,
      keepRecentUserTurns: keepTurns,
    );
    final out = <Map<String, String>>[];
    final summary = compactedSummary?.trim();
    if (summary != null && summary.isNotEmpty && start > 0) {
      out.add({'role': 'user', 'content': summary});
      out.add({'role': 'assistant', 'content': '了解しました。要約を踏まえて続けます。'});
    }
    for (var i = 0; i < slice.length; i++) {
      final m = slice[i];
      switch (m.role) {
        case CodingMessageRole.user:
          out.add({'role': 'user', 'content': m.content});
        case CodingMessageRole.assistant:
          // UI 用 display ではなく生応答（tool フェンス付き）を優先して渡す
          out.add({'role': 'assistant', 'content': m.contentForLlm});
        case CodingMessageRole.tool:
          final body = fullTool.contains(i) ? m.content : stubToolContent(m);
          out.add({
            'role': 'user',
            'content': '[tool:${m.toolName ?? 'tool'}]\n$body',
          });
        case CodingMessageRole.system:
          break;
      }
    }
    if (slice.isNotEmpty && slice.last.role == CodingMessageRole.tool) {
      out.add({'role': 'user', 'content': _continueNudge(symbolTools)});
    }
    return out;
  }

  /// 見積用: API に載る各メッセージ本文（role オーバーヘッドは呼び出し側で +4）。
  static List<String> apiContentBodies(
    List<CodingChatMessage> messages, {
    int? keepRecentUserTurns,
    String? compactedSummary,
    int compactedUpToExclusive = 0,
    bool symbolTools = false,
    bool autoExecute = false,
    List<String> pendingPatchPaths = const [],
    CodingHarnessSettings harness = CodingHarnessSettings.defaults,
    Set<String> restoreReadPaths = const {},
  }) {
    return [
      for (final m in buildApiMessages(
        messages,
        keepRecentUserTurns: keepRecentUserTurns,
        compactedSummary: compactedSummary,
        compactedUpToExclusive: compactedUpToExclusive,
        symbolTools: symbolTools,
        autoExecute: autoExecute,
        harness: harness,
        pendingPatchPaths: pendingPatchPaths,
        restoreReadPaths: restoreReadPaths,
      ))
        m['content'] ?? '',
    ];
  }

  /// 検査・再指示で全文に戻すパス。
  ///
  /// [readPaths] があるときは、このターンで開いた成功本文のうち未適用パッチ以外。
  /// 依頼文にフルパスが無くても載せる。無いときは [requestText] に相対パスがあるもの。
  /// 再読取のスタブは含めない。
  static Set<String> readPathsToRestore(
    List<CodingChatMessage> messages, {
    required String requestText,
    Iterable<String> pendingPatchPaths = const [],
    Iterable<String> readPaths = const [],
  }) {
    final request = requestText.replaceAll('\\', '/');
    final opened = <String>{
      for (final path in readPaths)
        if (path.trim().isNotEmpty) path.trim().replaceAll('\\', '/'),
    };
    if (opened.isEmpty && request.trim().isEmpty) return const <String>{};
    final pending = <String>{
      for (final path in pendingPatchPaths)
        if (path.trim().isNotEmpty) path.trim().replaceAll('\\', '/'),
    };
    final latest = <String, int>{};
    for (var i = 0; i < messages.length; i++) {
      final message = messages[i];
      if (message.role != CodingMessageRole.tool ||
          message.toolName != 'read_file') {
        continue;
      }
      if (!_readFileHasSourceBody(message.content)) continue;
      final path = extractToolPath(message);
      if (path == null || path.isEmpty || pending.contains(path)) continue;
      final named =
          opened.contains(path) || (opened.isEmpty && request.contains(path));
      if (!named) continue;
      latest[path] = i;
    }
    return latest.keys.toSet();
  }

  /// 検査・再指示の API。依頼文、成功した `read_file` の本文、指示だけを1件の user にする。
  ///
  /// それまでの assistant の ```tool と `[tool:]` は載せない。
  /// [promptRules] は＋の指示本文。チャットには出さず、指示のあとに足す。
  static List<Map<String, String>> buildDeliverableMessages({
    required String requestText,
    required List<({String path, String body})> reads,
    required String instruction,
    String promptRules = '',
    bool forbidReadFile = false,
  }) {
    final buf = StringBuffer();
    final request = requestText.trim();
    if (request.isNotEmpty) {
      buf
        ..writeln('【依頼】')
        ..writeln(request)
        ..writeln();
    }
    if (reads.isNotEmpty) {
      buf
        ..writeln('【既読の本文】')
        ..writeln(
          forbidReadFile
              ? '次が渡された本文です。read_file は出さない。行番号はこの本文の1行目から数える。'
              : '次が既読の本文です。これらのパスは read_file しない。',
        )
        ..writeln(
          forbidReadFile
              ? '不足: は書かない。'
              : 'まだ開いていないパスが必要なら、そのパスだけ read_file する。',
        )
        ..writeln();
      for (final read in reads) {
        buf
          ..writeln('【ファイル: ${read.path}】')
          ..writeln(read.body.trimRight())
          ..writeln();
      }
    }
    final pointed = instruction
        .replaceAll('本文はこれまでのツール結果にあります。', '本文は上の【既読の本文】です。')
        .trim();
    if (pointed.isNotEmpty) buf.writeln(pointed);
    final rules = promptRules.trim();
    if (rules.isNotEmpty) {
      if (buf.isNotEmpty) buf.writeln();
      buf.writeln(rules);
    }
    if (forbidReadFile) {
      if (buf.isNotEmpty) buf.writeln();
      buf.writeln(codingDeliverableCloseSystemSuffix.trim());
    }
    return [
      {'role': 'user', 'content': buf.toString().trimRight()},
    ];
  }

  /// [restorePaths] の成功本文。既読スタブは含めない。パス順。
  static List<({String path, String body})> restoredReadBodies(
    List<CodingChatMessage> messages,
    Set<String> restorePaths,
  ) {
    final indices = _latestSourceReadIndices(messages, restorePaths);
    final entries = indices.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return [
      for (final entry in entries)
        (
          path: entry.key,
          body: _readFileSourceBody(messages[entry.value].content),
        ),
    ];
  }

  static String _readFileSourceBody(String content) {
    final sep = content.indexOf('\n---\n');
    if (sep < 0) return content.trimRight();
    return content.substring(sep + 5).trimRight();
  }

  /// 古い対話をテンプレ要約に畳む（P1。LLM 要約は P2）。
  ///
  /// 戻り値の [upToExclusive] は畳む終端 index。畳めなければ null。
  static ({String summary, int upToExclusive})? buildTemplateCompact({
    required List<CodingChatMessage> messages,
    int? keepRecentUserTurns,
    String? existingSummary,
    CodingHarnessSettings harness = CodingHarnessSettings.defaults,
  }) {
    final keepTurns = keepRecentUserTurns ?? harness.compactKeepRecentUserTurns;
    final recentStart = _recentUserTurnStartIndex(
      messages,
      keepRecentUserTurns: keepTurns,
    );
    if (recentStart <= 0) return null;

    final purposes = <String>[];
    final files = <String>{};
    for (var i = 0; i < recentStart; i++) {
      final m = messages[i];
      switch (m.role) {
        case CodingMessageRole.user:
          final clipped = _clipOneLine(m.content, harness.summaryLineChars);
          if (clipped.isNotEmpty) purposes.add(clipped);
        case CodingMessageRole.tool:
          final path = extractToolPath(m);
          if (path != null && path.isNotEmpty) {
            files.add(path);
          }
        case CodingMessageRole.assistant:
        case CodingMessageRole.system:
          break;
      }
    }

    final purposeLine = purposes.isEmpty
        ? '（不明）'
        : purposes.take(harness.summaryPurposeCount).join(' ／ ');
    final filesLine = files.isEmpty
        ? '（なし）'
        : files.take(harness.summaryFileCount).join(', ');
    final prior = existingSummary?.trim();
    final buf = StringBuffer()
      ..writeln('【これまでの要約】')
      ..writeln('- 目的: $purposeLine')
      ..writeln('- 触ったファイル: $filesLine')
      ..writeln('- 適用済み変更の要点: （差分カード／履歴を参照）')
      ..writeln('- 未解決: （直近の依頼を参照）')
      ..writeln('- 却下した案／やってはいけないこと: （なし）');
    if (prior != null && prior.isNotEmpty) {
      buf
        ..writeln()
        ..writeln('（前回要約の要点）')
        ..writeln(
          _clipOneLine(prior.replaceAll('\n', ' '), harness.priorSummaryChars),
        );
    }
    return (summary: buf.toString().trim(), upToExclusive: recentStart);
  }

  /// tool 吹き出しをスタブ文言に変換（単体テスト・手動確認用）。
  static String stubToolContent(CodingChatMessage message) {
    final name = message.toolName ?? 'tool';
    final path = extractToolPath(message);
    final lines = _approxLineCount(message.content);
    final pathLine = (path == null || path.isEmpty)
        ? ''
        : '${path.replaceAll('\\', '/')}\n';
    if (name == 'read_file') {
      return '$pathLine（圧縮済み・約 $lines 行。このパスは read_file しない）';
    }
    return '$pathLine（圧縮済み。必要なら再実行）';
  }

  /// `read_file` の UI 形式 `path\\n---\\n本文`、または先頭行が相対パスらしい場合。
  static String? extractToolPath(CodingChatMessage message) {
    final content = message.content;
    if (content.isEmpty) return null;
    if (message.toolName == 'read_file') {
      final sep = content.indexOf('\n---\n');
      if (sep > 0) {
        return content.substring(0, sep).trim().replaceAll('\\', '/');
      }
    }
    final first = content.split('\n').first.trim().replaceAll('\\', '/');
    if (_looksLikeRelativePath(first)) return first;
    return null;
  }

  static Set<int> _toolIndicesKeptFull(
    List<CodingChatMessage> messages, {
    required int keepRecentUserTurns,
  }) {
    final recentStart = _recentUserTurnStartIndex(
      messages,
      keepRecentUserTurns: keepRecentUserTurns,
    );
    final latestReadByPath = <String, int>{};
    for (var i = 0; i < messages.length; i++) {
      final m = messages[i];
      if (m.role != CodingMessageRole.tool) continue;
      if (m.toolName != 'read_file') continue;
      final path = extractToolPath(m);
      if (path == null || path.isEmpty) continue;
      latestReadByPath[path] = i;
    }

    final keep = <int>{};
    for (var i = 0; i < messages.length; i++) {
      final m = messages[i];
      if (m.role != CodingMessageRole.tool) continue;
      if (i < recentStart) continue;

      if (m.toolName == 'read_file') {
        final path = extractToolPath(m);
        if (path != null && path.isNotEmpty) {
          if (latestReadByPath[path] != i) continue;
        }
      }
      keep.add(i);
    }
    return keep;
  }

  /// 直近 [keepRecentUserTurns] 個の user メッセージのうち最古の index。
  /// user が足りなければ 0。
  static int _recentUserTurnStartIndex(
    List<CodingChatMessage> messages, {
    required int keepRecentUserTurns,
  }) {
    if (keepRecentUserTurns <= 0) return messages.length;
    final userIndices = <int>[];
    for (var i = 0; i < messages.length; i++) {
      if (messages[i].role == CodingMessageRole.user) {
        userIndices.add(i);
      }
    }
    if (userIndices.isEmpty) return 0;
    if (userIndices.length <= keepRecentUserTurns) return 0;
    return userIndices[userIndices.length - keepRecentUserTurns];
  }

  static int _approxLineCount(String content) {
    if (content.isEmpty) return 0;
    var body = content;
    final sep = content.indexOf('\n---\n');
    if (sep >= 0 && sep + 5 < content.length) {
      body = content.substring(sep + 5);
    }
    if (body.isEmpty) return 0;
    return '\n'.allMatches(body).length + 1;
  }

  static bool _looksLikeRelativePath(String s) {
    if (s.isEmpty || s.length > 260) return false;
    if (s.contains(' ') || s.contains('（') || s.contains('[')) return false;
    if (s.startsWith('/') || s.contains('://')) return false;
    return s.contains('/') || s.contains('.');
  }

  static String _clipOneLine(String raw, int maxChars) {
    final one = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (one.length <= maxChars) return one;
    return '${one.substring(0, maxChars)}…';
  }

  /// tool 結果直後はローカル LLM が即 EOS（空応答）しやすいので続行指示を付ける。
  static String _continueNudge(bool symbolTools) {
    final moreTools = symbolTools
        ? 'file_outline / find_references / go_to_definition / workspace_symbol、足りなければ '
        : '';
    return 'ツール結果を踏まえて作業を続行してください。'
        'ファイル作成が必要なら、先に「配置先: ディレクトリ付き相対パス」を1行書き、'
        '続けて *** Begin Patch / *** Add File: 同じ相対パス を出力してください'
        '（ファイル名だけ・メニュー選択位置への配置は禁止。パスはワークスペースルート基準）。'
        '既に読んだパスは read_file しない。'
        '【読み取りの報告】があるときはその末尾に従う。'
        'このバッチで開かなかったパスがあるときは、そのパスだけ read_file する。'
        'まだ開いていない別のパスが必要なら、そのパスだけ read_file する。'
        '報告が無いときだけ、まだ読んでいないパスを '
        '${moreTools}list_dir / read_file / grep できる。'
        '「確認しました」だけで終わらないでください。';
  }

  /// 自動実行 ON の API ビュー。messages は変更しない。
  static List<Map<String, String>> _buildAutoExecuteApiMessages(
    List<CodingChatMessage> messages, {
    required String? compactedSummary,
    required int compactedUpToExclusive,
    required bool symbolTools,
    required List<String> pendingPatchPaths,
    required CodingHarnessSettings harness,
    Set<String> restoreReadPaths = const {},
  }) {
    final start = compactedUpToExclusive.clamp(0, messages.length);
    final slice = start > 0 ? messages.sublist(start) : messages;
    final out = <Map<String, String>>[];
    final summary = compactedSummary?.trim();
    if (summary != null && summary.isNotEmpty && start > 0) {
      out.add({'role': 'user', 'content': summary});
      out.add({'role': 'assistant', 'content': '了解しました。要約を踏まえて続けます。'});
    }
    if (slice.isEmpty) return out;
    out.addAll(
      _autoExecuteView(
        slice,
        pendingPatchPaths: pendingPatchPaths,
        harness: harness,
        restoreReadPaths: restoreReadPaths,
      ),
    );
    if (slice.last.role == CodingMessageRole.tool) {
      out.add({'role': 'user', 'content': _continueNudge(symbolTools)});
    }
    return out;
  }

  static List<Map<String, String>> _autoExecuteView(
    List<CodingChatMessage> slice, {
    required List<String> pendingPatchPaths,
    required CodingHarnessSettings harness,
    Set<String> restoreReadPaths = const {},
  }) {
    final pending = <String>{
      for (final path in pendingPatchPaths)
        if (path.trim().isNotEmpty) path.trim().replaceAll('\\', '/'),
    };
    final anchor = _autoExecuteAnchor(slice);
    final sendAnchorSeparately = anchor != null && anchor == slice.length - 1;
    final laterUser =
        anchor != null &&
        slice.skip(anchor + 1).any((m) => m.role == CodingMessageRole.user);
    final protectRepropose =
        anchor != null && !laterUser && _isReproposeUser(slice[anchor].content);

    final lastToolBatch = _lastToolBatch(slice);
    final latestSpecial = _latestSpecialUserAfter(slice, anchor);
    final lastAssistant = _assistantBeforeToolBatch(slice, lastToolBatch);
    final preferPaths = <String>{
      ...pending,
      ..._pathsIn(latestSpecial == null ? '' : slice[latestSpecial].content),
      if (protectRepropose) ..._pathsIn(slice[anchor].content),
    };
    final keptReads = _priorityReadIndices(
      slice,
      exclude: lastToolBatch,
      preferPaths: preferPaths,
      keptReads: harness.autoExecuteKeptReads,
    );
    final restoredReads = _latestSourceReadIndices(slice, restoreReadPaths);
    final window = <int>{
      ...keptReads,
      ...lastToolBatch,
      ...restoredReads.values,
      if (latestSpecial != null) latestSpecial,
      if (lastAssistant != null) lastAssistant,
    };

    final purposes = <String>[];
    final done = <String, String>{};
    final verifyLines = <String>[];
    final investigated = <String>[];
    final shownFullPaths = <String>{};
    for (final i in {...lastToolBatch, ...keptReads, ...restoredReads.values}) {
      final path = extractToolPath(slice[i]);
      if (path != null && path.isNotEmpty) shownFullPaths.add(path);
    }

    for (var i = 0; i < slice.length; i++) {
      if (window.contains(i)) continue;
      if (anchor != null && i == anchor) continue;
      final m = slice[i];
      switch (m.role) {
        case CodingMessageRole.user:
          if (_isAutoVerifyFix(m.content)) {
            verifyLines.add(_verifyLedgerLine(m.content));
          } else if (_isVerifyReport(m.content)) {
            verifyLines.add(_reportLedgerLine(m.content));
          } else if (_isReproposeUser(m.content)) {
            final clipped = _clipOneLine(
              _stubReproposeBodies(m.content),
              harness.summaryLineChars,
            );
            if (clipped.isNotEmpty) purposes.add(clipped);
          } else {
            final clipped = _clipOneLine(m.content, harness.summaryLineChars);
            if (clipped.isNotEmpty) purposes.add(clipped);
          }
        case CodingMessageRole.assistant:
          _collectPatchPaths(m.contentForLlm, done);
        case CodingMessageRole.tool:
          final path = extractToolPath(m);
          if (path != null &&
              path.isNotEmpty &&
              !shownFullPaths.contains(path) &&
              !investigated.contains(path)) {
            investigated.add(path);
          }
        case CodingMessageRole.system:
          break;
      }
    }

    final requestSection = _requestSection(
      slice: slice,
      anchor: anchor,
      sendAnchorSeparately: sendAnchorSeparately,
      protectRepropose: protectRepropose,
      harness: harness,
    );
    final doneLines = [
      for (final entry in done.entries)
        if (!pending.contains(entry.key)) '- ${entry.key}: ${entry.value} 提案',
    ];
    final investigatedShown = [
      for (final path in investigated)
        if (!pending.contains(path) && !done.containsKey(path)) path,
    ];

    final hasLedger =
        purposes.isNotEmpty ||
        doneLines.isNotEmpty ||
        verifyLines.isNotEmpty ||
        pending.isNotEmpty ||
        investigatedShown.isNotEmpty ||
        requestSection != null;

    final windowMaps = <Map<String, String>>[];
    final ordered = window.toList()..sort();
    for (final i in ordered) {
      if (_isSupersededRestoredRead(slice, i, restoredReads)) continue;
      windowMaps.add(
        _windowMessage(
          slice[i],
          fullTool:
              lastToolBatch.contains(i) ||
              keptReads.contains(i) ||
              restoredReads.containsValue(i),
          harness: harness,
        ),
      );
    }
    if (sendAnchorSeparately) {
      windowMaps.add(
        _windowMessage(
          slice[anchor],
          fullTool: false,
          keepUserBodies: true,
          harness: harness,
        ),
      );
    }

    if (!hasLedger) return windowMaps;

    final ledger = StringBuffer()
      ..writeln('【自動実行の作業記憶】')
      ..writeln('古いツール結果は省略した。既に読んだパスは read_file しない。');
    if (purposes.isNotEmpty) {
      ledger
        ..writeln('【これまでの依頼】')
        ..writeln(purposes.take(harness.summaryPurposeCount).join(' ／ '));
    }
    if (requestSection != null) {
      ledger
        ..writeln('【依頼】')
        ..writeln(requestSection);
    }
    ledger.writeln('【実施済み】');
    if (doneLines.isEmpty) {
      ledger.writeln('（なし）');
    } else {
      ledger.writeln(doneLines.join('\n'));
    }
    ledger.writeln('【検証】');
    if (verifyLines.isEmpty) {
      ledger.writeln('（なし）');
    } else {
      ledger.writeln(verifyLines.map((line) => '- $line').join('\n'));
    }
    ledger.writeln('【未適用】');
    if (pending.isEmpty) {
      ledger.writeln('（なし）');
    } else {
      ledger.writeln(pending.map((path) => '- $path').join('\n'));
    }
    if (investigatedShown.isNotEmpty) {
      ledger
        ..writeln('【調査したパス】')
        ..writeln(
          investigatedShown.take(harness.investigatedPathCount).join(', '),
        );
    }

    final out = <Map<String, String>>[
      {'role': 'user', 'content': ledger.toString().trim()},
    ];
    if (windowMaps.isEmpty || windowMaps.first['role'] != 'assistant') {
      out.add({'role': 'assistant', 'content': '了解しました。作業記憶を踏まえて続けます。'});
    }
    out.addAll(windowMaps);
    return out;
  }

  /// [restorePaths] ごとに、ソース本文がある最新の `read_file`。
  static Map<String, int> _latestSourceReadIndices(
    List<CodingChatMessage> slice,
    Set<String> restorePaths,
  ) {
    if (restorePaths.isEmpty) return const {};
    final want = <String>{
      for (final path in restorePaths)
        if (path.trim().isNotEmpty) path.trim().replaceAll('\\', '/'),
    };
    if (want.isEmpty) return const {};
    final latest = <String, int>{};
    for (var i = 0; i < slice.length; i++) {
      final message = slice[i];
      if (message.role != CodingMessageRole.tool ||
          message.toolName != 'read_file') {
        continue;
      }
      if (!_readFileHasSourceBody(message.content)) continue;
      final path = extractToolPath(message);
      if (path == null || !want.contains(path)) continue;
      latest[path] = i;
    }
    return latest;
  }

  /// 同じパスの成功本文を戻すとき、それ以外の `read_file`（古い本文や既読スタブ）は API に出さない。
  static bool _isSupersededRestoredRead(
    List<CodingChatMessage> slice,
    int index,
    Map<String, int> restoredByPath,
  ) {
    if (restoredByPath.isEmpty) return false;
    final message = slice[index];
    if (message.role != CodingMessageRole.tool ||
        message.toolName != 'read_file') {
      return false;
    }
    final path = extractToolPath(message);
    if (path == null) return false;
    final source = restoredByPath[path];
    return source != null && source != index;
  }

  static bool _readFileHasSourceBody(String content) {
    final sep = content.indexOf('\n---\n');
    if (sep < 0) return false;
    final body = content.substring(sep + 5).trimLeft();
    if (body.isEmpty) return false;
    if (body.contains('このファイルは開いていません')) return false;
    if (body.contains('このバッチの read_file')) return false;
    return true;
  }

  static int? _autoExecuteAnchor(List<CodingChatMessage> slice) {
    for (var i = slice.length - 1; i >= 0; i--) {
      final m = slice[i];
      if (m.role != CodingMessageRole.user) continue;
      if (_isAutoVerifyFix(m.content) || _isVerifyReport(m.content)) continue;
      return i;
    }
    return null;
  }

  static int? _latestSpecialUserAfter(
    List<CodingChatMessage> slice,
    int? anchor,
  ) {
    for (var i = slice.length - 1; i >= 0; i--) {
      if (anchor != null && i <= anchor) break;
      final m = slice[i];
      if (m.role != CodingMessageRole.user) continue;
      if (_isAutoVerifyFix(m.content) ||
          _isVerifyReport(m.content) ||
          _isReproposeUser(m.content)) {
        return i;
      }
    }
    return null;
  }

  static Set<int> _lastToolBatch(List<CodingChatMessage> slice) {
    if (slice.isEmpty || slice.last.role != CodingMessageRole.tool) {
      return const {};
    }
    final batch = <int>{};
    for (var i = slice.length - 1; i >= 0; i--) {
      if (slice[i].role != CodingMessageRole.tool) break;
      batch.add(i);
    }
    return batch;
  }

  static int? _assistantBeforeToolBatch(
    List<CodingChatMessage> slice,
    Set<int> lastToolBatch,
  ) {
    if (lastToolBatch.isEmpty) return null;
    final first = lastToolBatch.reduce((a, b) => a < b ? a : b);
    for (var i = first - 1; i >= 0; i--) {
      if (slice[i].role == CodingMessageRole.assistant) return i;
      if (slice[i].role == CodingMessageRole.user) return null;
    }
    return null;
  }

  static List<int> _priorityReadIndices(
    List<CodingChatMessage> slice, {
    required Set<int> exclude,
    required Set<String> preferPaths,
    int keptReads = CodingApiContextBuilder.autoExecuteKeptReads,
  }) {
    final batchPaths = <String>{
      for (final i in exclude)
        if (slice[i].toolName == 'read_file') extractToolPath(slice[i]) ?? '',
    };
    final latestByPath = <String, int>{};
    for (var i = 0; i < slice.length; i++) {
      if (exclude.contains(i)) continue;
      final m = slice[i];
      if (m.role != CodingMessageRole.tool || m.toolName != 'read_file') {
        continue;
      }
      final path = extractToolPath(m);
      if (path == null || path.isEmpty) continue;
      if (batchPaths.contains(path)) continue;
      latestByPath[path] = i;
    }
    final ranked = latestByPath.entries.toList()
      ..sort((a, b) {
        final prefer =
            (preferPaths.contains(b.key) ? 1 : 0) -
            (preferPaths.contains(a.key) ? 1 : 0);
        if (prefer != 0) return prefer;
        return b.value.compareTo(a.value);
      });
    return [for (final entry in ranked.take(keptReads)) entry.value];
  }

  static String? _requestSection({
    required List<CodingChatMessage> slice,
    required int? anchor,
    required bool sendAnchorSeparately,
    required bool protectRepropose,
    CodingHarnessSettings harness = CodingHarnessSettings.defaults,
  }) {
    if (anchor == null || sendAnchorSeparately) return null;
    final raw = slice[anchor].content;
    if (protectRepropose) return raw;
    if (_isReproposeUser(raw)) return _stubReproposeBodies(raw);
    return _compressUserForMemory(raw, harness);
  }

  static Map<String, String> _windowMessage(
    CodingChatMessage message, {
    required bool fullTool,
    bool keepUserBodies = false,
    CodingHarnessSettings harness = CodingHarnessSettings.defaults,
  }) {
    switch (message.role) {
      case CodingMessageRole.user:
        final content = keepUserBodies || _isReproposeUser(message.content)
            ? message.content
            : _compressUserForMemory(message.content, harness);
        return {'role': 'user', 'content': content};
      case CodingMessageRole.assistant:
        return {
          'role': 'assistant',
          'content': _slimLastAssistant(message.contentForLlm, harness),
        };
      case CodingMessageRole.tool:
        final body = fullTool ? message.content : stubToolContent(message);
        return {
          'role': 'user',
          'content': '[tool:${message.toolName ?? 'tool'}]\n$body',
        };
      case CodingMessageRole.system:
        return {'role': 'user', 'content': ''};
    }
  }

  static void _collectPatchPaths(String raw, Map<String, String> done) {
    for (final match in _patchFile.allMatches(raw)) {
      final kind = match.group(1);
      final path = match.group(2)?.trim().replaceAll('\\', '/');
      if (kind == null || path == null || path.isEmpty) continue;
      done[path] = kind;
    }
  }

  static String _compressUserForMemory(
    String content, [
    CodingHarnessSettings harness = CodingHarnessSettings.defaults,
  ]) {
    final withoutSelection = _stubSelectionBodies(content);
    if (_isVerifyReport(withoutSelection)) {
      return _compressReport(withoutSelection, harness);
    }
    return _compressErrorSection(withoutSelection, harness);
  }

  /// 書いたあとの本文で、同じパスの当初添付を置き換える。載っていないパスは残す。
  static String replaceAttachedFileBodies(
    String content,
    Map<String, String> freshByPath,
  ) {
    if (freshByPath.isEmpty || !content.contains('【開いているファイル:')) {
      return content;
    }
    final fresh = <String, String>{
      for (final entry in freshByPath.entries)
        entry.key.trim().replaceAll('\\', '/'): entry.value,
    };
    return content.replaceAllMapped(_attachedFileBlock, (match) {
      final path = (match.group(1) ?? '').trim().replaceAll('\\', '/');
      final body = fresh[path];
      if (body == null) return match.group(0)!;
      final trimmed = body.trimRight();
      if (trimmed.isEmpty) {
        return '【開いているファイル: $path】\n（空ファイル）';
      }
      return '【開いているファイル: $path】\n```\n$trimmed\n```';
    });
  }

  /// 選択範囲の本文だけ落とす。取り込みファイルの本文はソース修正に使うので残す。
  static String _stubSelectionBodies(String content) {
    return content.replaceAllMapped(_selectionBlock, (match) {
      return '${match.group(1)}（本文は省略。このパスは read_file しない）';
    });
  }

  static String _stubReproposeBodies(String content) {
    final paths = _targetFile
        .allMatches(content)
        .map((match) => match.group(1)!.replaceAll('\\', '/'))
        .join(', ');
    return '現状を正として再提案済: ${paths.isEmpty ? '（パス不明）' : paths}';
  }

  static String _compressErrorSection(
    String content, [
    CodingHarnessSettings harness = CodingHarnessSettings.defaults,
  ]) {
    const marker = '【エラー文言】\n';
    const endMarker = '\n\n【エラー解析の指示';
    final start = content.indexOf(marker);
    if (start < 0) return content;
    final bodyStart = start + marker.length;
    final end = content.indexOf(endMarker, bodyStart);
    if (end < 0) return content;
    final excerpt = _extractErrorExcerpt(
      content.substring(bodyStart, end),
      harness,
    );
    return content.replaceRange(bodyStart, end, excerpt);
  }

  static String _compressReport(
    String content, [
    CodingHarnessSettings harness = CodingHarnessSettings.defaults,
  ]) {
    final lines = content.split('\n');
    final out = <String>[];
    var i = 0;
    while (i < lines.length) {
      final line = lines[i];
      if (!line.startsWith('### ')) {
        out.add(line);
        i++;
        continue;
      }
      out.add(line);
      i++;
      var exit = '';
      var timedOut = false;
      if (i < lines.length && lines[i].startsWith('終了コード:')) {
        exit = lines[i];
        out.add(exit);
        i++;
      }
      if (i < lines.length && lines[i].startsWith('タイムアウト:')) {
        timedOut = true;
        out.add(lines[i]);
        i++;
      }
      final log = <String>[];
      while (i < lines.length && !lines[i].startsWith('### ')) {
        log.add(lines[i]);
        i++;
      }
      final code = RegExp(r'終了コード:\s*(\d+)').firstMatch(exit)?.group(1);
      if (code == '0' && !timedOut) {
        out.add('成功');
      } else {
        out.add(_extractErrorExcerpt(log.join('\n'), harness));
      }
    }
    return out.join('\n');
  }

  static String _extractErrorExcerpt(
    String log, [
    CodingHarnessSettings harness = CodingHarnessSettings.defaults,
  ]) {
    final kept = <String>[];
    for (final line in log.split('\n')) {
      if (!_errorLine.hasMatch(line)) continue;
      kept.add(line.trimRight());
      if (kept.length >= harness.autoExecuteMaxErrorLines) break;
    }
    if (kept.isNotEmpty) return kept.join('\n');
    final tail = [
      for (final line in log.split('\n'))
        if (line.trim().isNotEmpty) line.trimRight(),
    ];
    if (tail.isEmpty) return '（ログなし）';
    final keep = harness.verifyLogTailLines;
    final start = tail.length > keep ? tail.length - keep : 0;
    return tail.sublist(start).join('\n');
  }

  static String _verifyLedgerLine(String content) {
    final match = _verifyHeader.firstMatch(content);
    if (match == null) return '検証: 失敗（修正依頼済）';
    final command = (match.group(3) ?? '').trim();
    return '${match.group(1)}/${match.group(2)} $command: 失敗（修正依頼済）';
  }

  static String _reportLedgerLine(String content) {
    if (content.contains('判定: 合格')) return '検証レポート: 合格';
    if (content.contains('判定: 不合格')) return '検証レポート: 不合格';
    return '検証レポート';
  }

  static Set<String> _pathsIn(String content) {
    return {
      for (final match in _relPath.allMatches(content))
        match.group(0)!.replaceAll('\\', '/'),
      for (final match in _targetFile.allMatches(content))
        match.group(1)!.replaceAll('\\', '/'),
    };
  }

  static String _slimLastAssistant(
    String raw, [
    CodingHarnessSettings harness = CodingHarnessSettings.defaults,
  ]) {
    if (raw.length <= harness.slimAssistantChars) return raw;
    final lines = raw.split('\n');
    final keep = <String>[];
    var inTool = false;
    for (final line in lines) {
      final trimmed = line.trim();
      if (!inTool && trimmed.startsWith('```tool')) {
        inTool = true;
        keep.add(line);
        continue;
      }
      if (inTool) {
        keep.add(line);
        if (trimmed == '```') inTool = false;
        continue;
      }
      if (trimmed.startsWith('***') ||
          trimmed.startsWith('置換範囲:') ||
          trimmed.startsWith('挿入行:') ||
          trimmed.startsWith('配置先:') ||
          trimmed.startsWith('@@')) {
        keep.add(line);
      }
    }
    if (keep.isEmpty) {
      final cap = harness.slimAssistantFallbackChars;
      return raw.length <= cap ? raw : '${raw.substring(0, cap)}…';
    }
    return keep.join('\n');
  }

  static bool _isAutoVerifyFix(String content) => content.startsWith('【自動検証');

  static bool _isVerifyReport(String content) =>
      content.startsWith('【検証結果の報告】');

  static bool _isReproposeUser(String content) =>
      content.contains('【現状（これを正とする）】');
}
