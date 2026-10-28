import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../api_settings/domain/entities/local_llm_connection_settings.dart';
import '../domain/ai_generation_progress.dart';
import 'ai_debug_log_store.dart';

/// Ollama HTTP クライアント（`/api/chat` ストリーム＋モデル一覧）。
class OllamaClient {
  OllamaClient({
    http.Client? httpClient,
    AiDebugLogStore? debugLog,
  })  : _http = httpClient ?? http.Client(),
        _debugLog = debugLog;

  final http.Client _http;
  final AiDebugLogStore? _debugLog;

  Future<bool> isReachable(OllamaConnectionSettings settings) async {
    try {
      final uri = settings.resolvedBaseUri.resolve('/api/tags');
      final response = await _http
          .get(uri)
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (e, st) {
      _debugLog?.warn(
        'OllamaClient.isReachable',
        'Ollama 疎通確認に失敗',
        error: e,
        stackTrace: st,
        details: {'baseUrl': settings.baseUrl},
      );
      return false;
    }
  }

  Future<List<String>> listModelNames(OllamaConnectionSettings settings) async {
    final uri = settings.resolvedBaseUri.resolve('/api/tags');
    try {
      final response = await _http.get(uri).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) {
        throw StateError(
          'Ollama モデル一覧の取得に失敗しました（HTTP ${response.statusCode}） body=${_clip(response.body)}',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return const [];
      final models = decoded['models'];
      if (models is! List) return const [];
      final names = <String>[];
      for (final item in models) {
        if (item is Map && item['name'] is String) {
          names.add(item['name'] as String);
        }
      }
      names.sort();
      return names;
    } catch (e, st) {
      _debugLog?.error(
        'OllamaClient.listModelNames',
        'モデル一覧取得失敗',
        error: e,
        stackTrace: st,
        details: {'url': uri.toString()},
      );
      rethrow;
    }
  }

  /// ストリーミングチャット。進捗コールバックで経過・部分テキストを通知。
  ///
  /// [think] は Gemma4 等の思考モード。会議アシストでは既定 OFF
  /// （ON だと思考だけで num_predict を使い切り content が空になることがある）。
  Future<String> chat({
    required OllamaConnectionSettings settings,
    required String prompt,
    void Function(AiGenerationProgress progress)? onProgress,
    String systemPrompt =
        '簡潔な会議アシスタント。前置き・挨拶・結び・思考タグ・ツール呼び出しは禁止。指定形式のみ出力。',
    int? numPredict,
    bool think = false,
    bool allowRetryOnEmpty = true,
  }) async {
    final model = settings.modelName.trim();
    final base = settings.baseUrl.trim();
    if (base.isEmpty) {
      throw StateError('Ollama のベースURLが未設定です');
    }
    if (model.isEmpty) {
      throw StateError('Ollama のモデル名が未設定です');
    }

    final stopwatch = Stopwatch()..start();
    final uri = settings.resolvedBaseUri.resolve('/api/chat');
    final effectiveNumPredict = (numPredict != null && numPredict > 0)
        ? numPredict
        : null;
    final options = <String, dynamic>{
      'temperature': 0.2,
      'num_predict': ?effectiveNumPredict,
    };

    _debugLog?.info(
      'OllamaClient.chat',
      'リクエスト開始',
      details: {
        'url': uri.toString(),
        'model': model,
        'promptChars': '${prompt.length}',
        'systemChars': '${systemPrompt.length}',
        'numPredict': '${effectiveNumPredict ?? '(default)'}',
        'think': '$think',
        'promptPreview': _clip(prompt, 240),
      },
    );

    void emitProgress({
      required AiGenerationPhase phase,
      int outputChars = 0,
      String partialText = '',
      int? evalCount,
      int? promptEvalCount,
      double? tokensPerSecond,
      String? statusLabel,
    }) {
      onProgress?.call(
        AiGenerationProgress(
          phase: phase,
          elapsed: stopwatch.elapsed,
          outputChars: outputChars,
          partialText: partialText,
          evalCount: evalCount,
          promptEvalCount: promptEvalCount,
          tokensPerSecond: tokensPerSecond,
          statusLabel: statusLabel,
        ),
      );
    }

    emitProgress(phase: AiGenerationPhase.connecting);

    final request = http.Request('POST', uri)
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({
        'model': model,
        'stream': true,
        // Gemma4 等: 思考トークンで枠を使い切ると content が空になるため OFF
        'think': think,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': prompt},
        ],
        'options': options,
      });

    late http.StreamedResponse streamed;
    try {
      streamed = await _http.send(request).timeout(const Duration(minutes: 5));
    } catch (e, st) {
      emitProgress(phase: AiGenerationPhase.failed, statusLabel: '接続に失敗しました');
      _debugLog?.error(
        'OllamaClient.chat',
        'HTTP送信／タイムアウト失敗',
        error: e,
        stackTrace: st,
        details: {
          'url': uri.toString(),
          'model': model,
          'elapsedMs': '${stopwatch.elapsedMilliseconds}',
        },
      );
      rethrow;
    }

    if (streamed.statusCode != 200) {
      final body = await streamed.stream.bytesToString();
      emitProgress(phase: AiGenerationPhase.failed);
      final message =
          'Ollama 呼び出しに失敗しました（HTTP ${streamed.statusCode}）: ${_clip(body)}';
      _debugLog?.error(
        'OllamaClient.chat',
        message,
        details: {
          'url': uri.toString(),
          'model': model,
          'status': '${streamed.statusCode}',
          'body': _clip(body, 2000),
          'elapsedMs': '${stopwatch.elapsedMilliseconds}',
        },
      );
      throw StateError(message);
    }

    emitProgress(phase: AiGenerationPhase.waitingFirstToken);

    final buffer = StringBuffer();
    final thinkingBuffer = StringBuffer();
    var sawContent = false;
    final lineBuffer = StringBuffer();
    String? doneReason;
    int? lastEvalCount;
    int? lastPromptEvalCount;
    double? lastTps;

    try {
      await for (final chunk in streamed.stream.transform(utf8.decoder)) {
        lineBuffer.write(chunk);
        var text = lineBuffer.toString();
        var newline = text.indexOf('\n');
        while (newline >= 0) {
          final line = text.substring(0, newline).trim();
          text = text.substring(newline + 1);
          newline = text.indexOf('\n');
          if (line.isEmpty) continue;

          late final Map<String, dynamic> json;
          try {
            final decoded = jsonDecode(line);
            if (decoded is! Map<String, dynamic>) continue;
            json = decoded;
          } catch (e) {
            _debugLog?.warn(
              'OllamaClient.chat',
              'ストリーム行のJSON解析に失敗（スキップ）',
              error: e,
              details: {'linePreview': _clip(line, 200)},
            );
            continue;
          }

          if (json['error'] != null) {
            final err = json['error'].toString();
            _debugLog?.error(
              'OllamaClient.chat',
              'ストリーム内エラー',
              error: err,
              details: {'raw': _clip(line, 1000)},
            );
            throw StateError('Ollama ストリームエラー: $err');
          }

          final message = json['message'];
          if (message is Map) {
            final piece = message['content'];
            if (piece is String && piece.isNotEmpty) {
              buffer.write(piece);
              sawContent = true;
              emitProgress(
                phase: AiGenerationPhase.generating,
                outputChars: buffer.length,
                partialText: buffer.toString(),
              );
            }
            final thinking = message['thinking'];
            if (thinking is String && thinking.isNotEmpty) {
              thinkingBuffer.write(thinking);
            }
          }

          if (json['done'] == true) {
            doneReason = json['done_reason']?.toString();
            lastEvalCount = _asInt(json['eval_count']);
            final evalDurationNs = _asInt(json['eval_duration']);
            lastPromptEvalCount = _asInt(json['prompt_eval_count']);
            if (lastEvalCount != null &&
                evalDurationNs != null &&
                evalDurationNs > 0) {
              lastTps = lastEvalCount / (evalDurationNs / 1e9);
            }
            emitProgress(
              phase: AiGenerationPhase.done,
              outputChars: buffer.length,
              partialText: buffer.toString(),
              evalCount: lastEvalCount,
              promptEvalCount: lastPromptEvalCount,
              tokensPerSecond: lastTps,
            );
          }
        }
        lineBuffer
          ..clear()
          ..write(text);

        if (!sawContent) {
          final thinkingChars = thinkingBuffer.length;
          emitProgress(
            phase: AiGenerationPhase.waitingFirstToken,
            statusLabel: thinkingChars > 0
                ? 'モデル思考中…（思考 $thinkingChars 文字）'
                : null,
          );
        }
      }
    } catch (e, st) {
      if (e is StateError) rethrow;
      _debugLog?.error(
        'OllamaClient.chat',
        'ストリーム読取失敗',
        error: e,
        stackTrace: st,
        details: {
          'model': model,
          'elapsedMs': '${stopwatch.elapsedMilliseconds}',
          'outputCharsSoFar': '${buffer.length}',
          'thinkingCharsSoFar': '${thinkingBuffer.length}',
        },
      );
      rethrow;
    }

    final result = buffer.toString().trim();
    if (result.isEmpty) {
      emitProgress(phase: AiGenerationPhase.failed);
      final thinkingChars = thinkingBuffer.length;
      final lengthExhausted = doneReason == 'length';
      _debugLog?.error(
        'OllamaClient.chat',
        '空の応答',
        details: {
          'model': model,
          'elapsedMs': '${stopwatch.elapsedMilliseconds}',
          'doneReason': doneReason ?? '(none)',
          'evalCount': '${lastEvalCount ?? '(n/a)'}',
          'promptEvalCount': '${lastPromptEvalCount ?? '(n/a)'}',
          'thinkingChars': '$thinkingChars',
          'think': '$think',
          'numPredict': '${effectiveNumPredict ?? '(default)'}',
          if (thinkingChars > 0)
            'thinkingPreview': _clip(thinkingBuffer.toString(), 240),
        },
      );

      // 思考だけで枠を使い切った場合は1回だけ再試行（think OFF + 枠拡大）
      if (lengthExhausted && allowRetryOnEmpty) {
        final retryPredict = (effectiveNumPredict == null ||
                effectiveNumPredict < 2048)
            ? 2048
            : effectiveNumPredict * 2;
        _debugLog?.warn(
          'OllamaClient.chat',
          '空応答（done_reason=length）のため再試行',
          details: {
            'model': model,
            'thinkingChars': '$thinkingChars',
            'prevThink': '$think',
            'prevNumPredict': '${effectiveNumPredict ?? '(default)'}',
            'retryNumPredict': '$retryPredict',
          },
        );
        return chat(
          settings: settings,
          prompt: prompt,
          onProgress: onProgress,
          systemPrompt: systemPrompt,
          numPredict: retryPredict,
          think: false,
          allowRetryOnEmpty: false,
        );
      }

      if (lengthExhausted && thinkingChars > 0) {
        throw StateError(
          'Ollama が思考だけで出力枠（num_predict=${effectiveNumPredict ?? "default"}）を使い切り、本文が空でした。',
        );
      }
      throw StateError('Ollama から空の応答が返りました');
    }

    _debugLog?.info(
      'OllamaClient.chat',
      '完了',
      details: {
        'model': model,
        'elapsedMs': '${stopwatch.elapsedMilliseconds}',
        'outputChars': '${result.length}',
        'evalCount': '${lastEvalCount ?? '(n/a)'}',
        'promptEvalCount': '${lastPromptEvalCount ?? '(n/a)'}',
        'tokensPerSec': lastTps == null ? '(n/a)' : lastTps.toStringAsFixed(2),
        'doneReason': doneReason ?? '(none)',
        'think': '$think',
        'thinkingChars': '${thinkingBuffer.length}',
        'responsePreview': _clip(result, 240),
      },
    );
    return result;
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  static String _clip(String value, [int max = 500]) {
    final trimmed = value.replaceAll('\n', r'\n');
    if (trimmed.length <= max) return trimmed;
    return '${trimmed.substring(0, max)}…(${value.length} chars)';
  }
}
