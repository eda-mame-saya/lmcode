import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../api_settings/domain/entities/local_llm_connection_settings.dart';
import '../domain/ai_generation_progress.dart';
import 'ai_debug_log_store.dart';

/// llama-server OpenAI 互換クライアント（`/v1/chat/completions`）。
class LocalLlmClient {
  LocalLlmClient({
    http.Client? httpClient,
    AiDebugLogStore? debugLog,
  })  : _http = httpClient ?? http.Client(),
        _debugLog = debugLog;

  final http.Client _http;
  final AiDebugLogStore? _debugLog;

  Future<bool> isReachable(LocalLlmConnectionSettings settings) async {
    try {
      final health = settings.resolvedBaseUri.resolve('/health');
      final response = await _http
          .get(health)
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) return true;
    } catch (_) {
      // /health が無いビルド向けに /v1/models も試す
    }
    try {
      final models = settings.resolvedBaseUri.resolve('/v1/models');
      final response = await _http
          .get(models)
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (e, st) {
      _debugLog?.warn(
        'LocalLlmClient.isReachable',
        'llama-server 疎通確認に失敗',
        error: e,
        stackTrace: st,
        details: {'baseUrl': settings.baseUrl},
      );
      return false;
    }
  }

  /// 会議定型向け（非 stream）。S13 は [chatStream] を使う。
  Future<String> chat({
    required LocalLlmConnectionSettings settings,
    required String prompt,
    void Function(AiGenerationProgress progress)? onProgress,
    String systemPrompt =
        '簡潔な会議アシスタント。前置き・挨拶・結び・思考タグ・ツール呼び出しは禁止。指定形式のみ出力。',
    int? maxTokens,
    bool allowRetryOnEmpty = true,
  }) async {
    if (!settings.hasEndpoint) {
      throw StateError('ローカル LLM の接続先が未設定です');
    }

    final stopwatch = Stopwatch()..start();
    final uri = settings.resolvedBaseUri.resolve('/v1/chat/completions');
    final effectiveMax = (maxTokens != null && maxTokens > 0) ? maxTokens : null;

    _debugLog?.info(
      'LocalLlmClient.chat',
      'リクエスト開始',
      details: {
        'url': uri.toString(),
        'model': settings.modelName,
        'promptChars': '${prompt.length}',
        'systemChars': '${systemPrompt.length}',
        'maxTokens': '${effectiveMax ?? '(default)'}',
        'thinking': '${settings.thinkingEnabled}',
        'promptPreview': _clip(prompt, 240),
      },
    );

    void emitProgress({
      required AiGenerationPhase phase,
      int outputChars = 0,
      String partialText = '',
      String? statusLabel,
    }) {
      onProgress?.call(
        AiGenerationProgress(
          phase: phase,
          elapsed: stopwatch.elapsed,
          outputChars: outputChars,
          partialText: partialText,
          statusLabel: statusLabel,
        ),
      );
    }

    emitProgress(phase: AiGenerationPhase.connecting);

    final body = <String, dynamic>{
      'model': settings.modelName,
      'stream': false,
      'temperature': 0.2,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': prompt},
      ],
      if (effectiveMax != null) 'max_tokens': effectiveMax,
    };

    late http.Response response;
    try {
      emitProgress(
        phase: AiGenerationPhase.waitingFirstToken,
        statusLabel: 'llama-server で生成中…',
      );
      response = await _http
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(minutes: 5));
    } catch (e, st) {
      emitProgress(phase: AiGenerationPhase.failed, statusLabel: '接続に失敗しました');
      _debugLog?.error(
        'LocalLlmClient.chat',
        'HTTP送信／タイムアウト失敗',
        error: e,
        stackTrace: st,
        details: {
          'url': uri.toString(),
          'model': settings.modelName,
          'elapsedMs': '${stopwatch.elapsedMilliseconds}',
        },
      );
      rethrow;
    }

    if (response.statusCode != 200) {
      emitProgress(phase: AiGenerationPhase.failed);
      final message =
          'llama-server 呼び出しに失敗しました（HTTP ${response.statusCode}）: ${_clip(response.body)}';
      _debugLog?.error(
        'LocalLlmClient.chat',
        message,
        details: {
          'url': uri.toString(),
          'model': settings.modelName,
          'status': '${response.statusCode}',
          'body': _clip(response.body, 2000),
        },
      );
      throw StateError(message);
    }

    late final Map<String, dynamic> decoded;
    try {
      final raw = jsonDecode(response.body);
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('応答がオブジェクトではありません');
      }
      decoded = raw;
    } catch (e, st) {
      emitProgress(phase: AiGenerationPhase.failed);
      _debugLog?.error(
        'LocalLlmClient.chat',
        'JSON解析失敗',
        error: e,
        stackTrace: st,
        details: {'body': _clip(response.body, 1000)},
      );
      throw StateError('llama-server の応答を解析できませんでした');
    }

    final content = _extractMessageContent(decoded);
    final finishReason = _extractFinishReason(decoded);
    final result = content.trim();

    if (result.isEmpty) {
      emitProgress(phase: AiGenerationPhase.failed);
      _debugLog?.error(
        'LocalLlmClient.chat',
        '空の応答',
        details: {
          'model': settings.modelName,
          'elapsedMs': '${stopwatch.elapsedMilliseconds}',
          'finishReason': finishReason ?? '(none)',
          'thinkingEnabled': '${settings.thinkingEnabled}',
          'maxTokens': '${effectiveMax ?? '(default)'}',
        },
      );

      if (finishReason == 'length' && allowRetryOnEmpty) {
        final retryMax = (effectiveMax == null || effectiveMax < 2048)
            ? 2048
            : effectiveMax * 2;
        _debugLog?.warn(
          'LocalLlmClient.chat',
          '空応答（finish_reason=length）のため再試行',
          details: {'retryMaxTokens': '$retryMax'},
        );
        return chat(
          settings: settings.copyWith(codingThinkingEnabled: false),
          prompt: prompt,
          onProgress: onProgress,
          systemPrompt: systemPrompt,
          maxTokens: retryMax,
          allowRetryOnEmpty: false,
        );
      }
      throw StateError('llama-server から空の応答が返りました');
    }

    emitProgress(
      phase: AiGenerationPhase.done,
      outputChars: result.length,
      partialText: result,
    );
    _debugLog?.info(
      'LocalLlmClient.chat',
      '完了',
      details: {
        'model': settings.modelName,
        'elapsedMs': '${stopwatch.elapsedMilliseconds}',
        'outputChars': '${result.length}',
        'finishReason': finishReason ?? '(none)',
        'responsePreview': _clip(result, 240),
      },
    );
    return result;
  }

  /// S13 向け SSE stream（単発プロンプト）。
  Future<String> chatStream({
    required LocalLlmConnectionSettings settings,
    required String prompt,
    void Function(AiGenerationProgress progress)? onProgress,
    String systemPrompt =
        '簡潔な会議アシスタント。前置き・挨拶・結びは禁止。ユーザーの質問に答える。',
    int? maxTokens,
    bool Function()? isCancelled,
  }) {
    return chatMessagesStream(
      settings: settings,
      messages: [
        {'role': 'user', 'content': prompt},
      ],
      onProgress: onProgress,
      systemPrompt: systemPrompt,
      maxTokens: maxTokens,
      isCancelled: isCancelled,
    );
  }

  /// 思考（reasoning）がこの文字数を超え、本文が未だ空なら長考打ち切り。
  /// Qwen 系 thinking ON で数万字の思考に入り content が出ないのを防ぐ。
  static const maxReasoningCharsBeforeAbort = 8000;

  /// S13／S16 向け SSE stream（会話履歴付き）。
  Future<String> chatMessagesStream({
    required LocalLlmConnectionSettings settings,
    required List<Map<String, String>> messages,
    void Function(AiGenerationProgress progress)? onProgress,
    String systemPrompt =
        'あなたは社内向けの有用なアシスタントです。簡潔に答えてください。',
    int? maxTokens,
    bool Function()? isCancelled,
    bool allowRetryOnEmpty = true,
    double? temperature,
    Duration? requestTimeout,
    int? maxReasoningChars,
  }) async {
    if (!settings.hasEndpoint) {
      throw StateError('ローカル LLM の接続先が未設定です');
    }

    final stopwatch = Stopwatch()..start();
    final uri = settings.resolvedBaseUri.resolve('/v1/chat/completions');
    final effectiveMax = (maxTokens != null && maxTokens > 0) ? maxTokens : null;
    final effectiveTemperature = temperature ?? 0.2;
    final effectiveTimeout = requestTimeout ?? const Duration(minutes: 5);
    final reasoningAbort = maxReasoningChars ?? maxReasoningCharsBeforeAbort;

    void emitProgress({
      required AiGenerationPhase phase,
      int outputChars = 0,
      String partialText = '',
      String? statusLabel,
    }) {
      onProgress?.call(
        AiGenerationProgress(
          phase: phase,
          elapsed: stopwatch.elapsed,
          outputChars: outputChars,
          partialText: partialText,
          statusLabel: statusLabel,
        ),
      );
    }

    emitProgress(phase: AiGenerationPhase.connecting);

    final apiMessages = <Map<String, String>>[
      {'role': 'system', 'content': systemPrompt},
      ...messages,
    ];

    final request = http.Request('POST', uri)
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({
        'model': settings.modelName,
        'stream': true,
        'temperature': effectiveTemperature,
        'messages': apiMessages,
        if (effectiveMax != null) 'max_tokens': effectiveMax,
      });

    // 停止（Stop）用に専用 Client を使う（閉じるとストリームが切れる）
    final client = http.Client();
    late http.StreamedResponse streamed;
    try {
      streamed = await client.send(request).timeout(effectiveTimeout);
    } catch (e, st) {
      client.close();
      emitProgress(phase: AiGenerationPhase.failed, statusLabel: '接続に失敗しました');
      _debugLog?.error(
        'LocalLlmClient.chatMessagesStream',
        'HTTP送信失敗',
        error: e,
        stackTrace: st,
        details: {'url': uri.toString()},
      );
      rethrow;
    }

    if (streamed.statusCode != 200) {
      final body = await streamed.stream.bytesToString();
      client.close();
      emitProgress(phase: AiGenerationPhase.failed);
      final message =
          'llama-server stream 失敗（HTTP ${streamed.statusCode}）: ${_clip(body)}';
      _debugLog?.error(
        'LocalLlmClient.chatMessagesStream',
        message,
        details: {
          'url': uri.toString(),
          'model': settings.modelName,
          'status': '${streamed.statusCode}',
          'messageCount': '${apiMessages.length}',
          'body': _clip(body, 2000),
          'elapsedMs': '${stopwatch.elapsedMilliseconds}',
        },
      );
      throw StateError(message);
    }

    emitProgress(phase: AiGenerationPhase.waitingFirstToken);
    final contentBuffer = StringBuffer();
    final reasoningBuffer = StringBuffer();
    final lineBuffer = StringBuffer();
    var cancelled = false;
    var reasoningRunaway = false;
    String? finishReason;

    void ingestSseDataLine(String line) {
      if (!line.startsWith('data:')) return;
      final payload = line.substring(5).trim();
      if (payload.isEmpty || payload == '[DONE]') return;
      try {
        final decoded = jsonDecode(payload);
        if (decoded is! Map<String, dynamic>) return;
        finishReason = _extractFinishReason(decoded) ?? finishReason;
        final parts = _extractDeltaParts(decoded);
        if (parts.content != null && parts.content!.isNotEmpty) {
          contentBuffer.write(parts.content);
          emitProgress(
            phase: AiGenerationPhase.generating,
            outputChars: contentBuffer.length,
            partialText: contentBuffer.toString(),
          );
        } else if (parts.reasoning != null && parts.reasoning!.isNotEmpty) {
          reasoningBuffer.write(parts.reasoning);
          if (contentBuffer.isEmpty &&
              reasoningBuffer.length >= reasoningAbort) {
            reasoningRunaway = true;
          }
          emitProgress(
            phase: AiGenerationPhase.generating,
            outputChars: contentBuffer.length,
            partialText: contentBuffer.isEmpty
                ? '（思考中… ${reasoningBuffer.length}文字）'
                : contentBuffer.toString(),
            statusLabel: reasoningRunaway
                ? '思考が長すぎるため打ち切り…'
                : 'モデル思考中…',
          );
        }
      } catch (_) {
        // 不正チャンクはスキップ
      }
    }

    try {
      await for (final chunk in streamed.stream.transform(utf8.decoder)) {
        if (isCancelled?.call() == true) {
          cancelled = true;
          break;
        }
        if (reasoningRunaway) {
          break;
        }
        lineBuffer.write(chunk);
        var text = lineBuffer.toString();
        var newline = text.indexOf('\n');
        while (newline >= 0) {
          final line = text.substring(0, newline).trimRight();
          text = text.substring(newline + 1);
          newline = text.indexOf('\n');
          if (line.isEmpty) continue;
          ingestSseDataLine(line);
          if (reasoningRunaway) break;
        }
        lineBuffer
          ..clear()
          ..write(text);
        if (reasoningRunaway) break;
      }
      // 末尾に改行が無い data: 行を取りこぼさない
      if (!reasoningRunaway) {
        final trailing = lineBuffer.toString().trimRight();
        if (trailing.isNotEmpty) {
          ingestSseDataLine(trailing);
        }
      }
    } finally {
      client.close();
    }

    var result = contentBuffer.toString().trim();
    // content が空で reasoning に本文相当がある場合の救済（thinking モデル）
    if (result.isEmpty) {
      final reasoning = reasoningBuffer.toString().trim();
      if (reasoning.isNotEmpty && _looksLikeAgentPayload(reasoning)) {
        result = reasoning;
      }
    }

    if (cancelled) {
      emitProgress(
        phase: AiGenerationPhase.done,
        outputChars: result.length,
        partialText: result,
        statusLabel: '停止しました',
      );
      return result;
    }

    if (result.isEmpty) {
      _debugLog?.error(
        'LocalLlmClient.chatMessagesStream',
        reasoningRunaway ? '思考長考で打ち切り・本文なし' : 'stream から空の応答',
        details: {
          'url': uri.toString(),
          'model': settings.modelName,
          'messageCount': '${apiMessages.length}',
          'elapsedMs': '${stopwatch.elapsedMilliseconds}',
          'finishReason': finishReason ?? '(none)',
          'reasoningChars': '${reasoningBuffer.length}',
          'thinkingEnabled': '${settings.thinkingEnabled}',
          'reasoningRunaway': '$reasoningRunaway',
        },
      );
      // 長考打ち切り時は同じ thinking ON サーバーへ再試行しても再発しやすいので即失敗にする
      if (reasoningRunaway) {
        emitProgress(phase: AiGenerationPhase.failed);
        throw StateError(
          '思考が長すぎて応答が完了しませんでした'
          '（${reasoningBuffer.length}文字で打ち切り）。'
          'S16 の「思考」を OFF にしてから再送信してください',
        );
      }
      if (allowRetryOnEmpty) {
        _debugLog?.warn(
          'LocalLlmClient.chatMessagesStream',
          '空応答のため続行指示付きで1回再試行',
          details: {
            'finishReason': finishReason ?? '(none)',
            'reasoningChars': '${reasoningBuffer.length}',
          },
        );
        emitProgress(
          phase: AiGenerationPhase.connecting,
          statusLabel: '空応答のため再試行中…',
        );
        return chatMessagesStream(
          settings: settings,
          messages: [
            ...messages,
            {
              'role': 'user',
              'content':
                  '前の応答が空でした。ツール結果を踏まえて必ず続行してください。'
                  'ファイル作成が必要なら *** Begin Patch で Add File を出し、'
                  '既に読んだパスは read_file しない。'
                  '【読み取りの報告】が未読を挙げているときだけ、そのパスを read_file する。'
                  '前置きだけの返答は不可です。',
            },
          ],
          onProgress: onProgress,
          systemPrompt: systemPrompt,
          maxTokens: effectiveMax == null
              ? 4096
              : (effectiveMax < 4096 ? 4096 : effectiveMax),
          isCancelled: isCancelled,
          allowRetryOnEmpty: false,
        );
      }
      emitProgress(phase: AiGenerationPhase.failed);
      throw StateError('llama-server stream から空の応答が返りました');
    }
    emitProgress(
      phase: AiGenerationPhase.done,
      outputChars: result.length,
      partialText: result,
    );
    return result;
  }

  /// Agent 向けペイロードらしいか（reasoning だけの空応答救済用）。
  static bool _looksLikeAgentPayload(String text) {
    return text.contains('*** Begin Patch') ||
        text.contains('```tool') ||
        text.contains('*** Update File') ||
        text.contains('*** Add File');
  }

  static String _extractMessageContent(Map<String, dynamic> decoded) {
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) return '';
    final first = choices.first;
    if (first is! Map) return '';
    final message = first['message'];
    if (message is! Map) return '';
    final content = message['content'];
    if (content is String && content.trim().isNotEmpty) return content;
    // thinking / reasoning モデルのフォールバック
    for (final key in const [
      'reasoning_content',
      'reasoning',
      'thinking',
    ]) {
      final v = message[key];
      if (v is String && v.trim().isNotEmpty && _looksLikeAgentPayload(v)) {
        return v;
      }
    }
    return content is String ? content : '';
  }

  static String? _extractFinishReason(Map<String, dynamic> decoded) {
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final first = choices.first;
    if (first is! Map) return null;
    return first['finish_reason']?.toString();
  }

  /// delta.content と reasoning 系を分離して取り出す。
  static ({String? content, String? reasoning}) _extractDeltaParts(
    Map<String, dynamic> decoded,
  ) {
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      return (content: null, reasoning: null);
    }
    final first = choices.first;
    if (first is! Map) return (content: null, reasoning: null);
    final delta = first['delta'];
    if (delta is! Map) return (content: null, reasoning: null);
    final content = delta['content'] is String ? delta['content'] as String : null;
    String? reasoning;
    for (final key in const [
      'reasoning_content',
      'reasoning',
      'thinking',
    ]) {
      final v = delta[key];
      if (v is String && v.isNotEmpty) {
        reasoning = v;
        break;
      }
    }
    return (content: content, reasoning: reasoning);
  }

  static String _clip(String value, [int max = 500]) {
    final trimmed = value.replaceAll('\n', r'\n');
    if (trimmed.length <= max) return trimmed;
    return '${trimmed.substring(0, max)}…(${value.length} chars)';
  }
}
