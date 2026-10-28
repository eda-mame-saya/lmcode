import 'entities/coding_assist_entities.dart';

/// デバッグ用に、入力・Agent の生出力・ツール結果・生成ログを一括の本文にする。
String codingDebugExchangeText(
  List<CodingChatMessage> messages, {
  String generationTrace = '',
}) {
  final blocks = <String>[];
  for (final message in messages) {
    switch (message.role) {
      case CodingMessageRole.user:
        final body = message.content.trim();
        if (body.isEmpty) continue;
        blocks.add('【入力】\n$body');
      case CodingMessageRole.assistant:
        final body = message.contentForLlm.trim();
        if (body.isEmpty) continue;
        blocks.add('【Agent出力】\n$body');
      case CodingMessageRole.tool:
        final body = message.content.trim();
        if (body.isEmpty) continue;
        final name = message.toolName?.trim();
        final label = (name == null || name.isEmpty) ? 'ツール' : 'ツール: $name';
        blocks.add('【$label】\n$body');
      case CodingMessageRole.system:
        final body = message.content.trim();
        if (body.isEmpty) continue;
        blocks.add('【system】\n$body');
    }
  }
  final trace = generationTrace.trim();
  if (trace.isNotEmpty) {
    blocks.add('【生成ログ】\n$trace');
  }
  return blocks.join('\n\n');
}
