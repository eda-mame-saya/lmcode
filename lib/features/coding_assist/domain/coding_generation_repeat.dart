/// 1回の生成の中で、同じ段落が繰り返されたときの扱い。
///
/// ターンが終わってから比べる同一実行検知では、この繰り返しは止まらない。
const codingGenerationRepeatMinChars = 40;

/// この回数に達したら生成を切る。
const codingGenerationRepeatTimes = 3;

/// 破棄した応答の代わりに履歴へ残す短い文。Patch も `不足:` も含まない。
const codingGenerationRepeatDiscarded = '（同じ段落が3回続いたため、この応答は破棄しました）';

/// [reply] が、繰り返しで破棄したあとの定型文か。
bool codingReplyWasRepeatDiscard(String reply) =>
    reply.trim() == codingGenerationRepeatDiscarded;

/// 空白を畳んだ 40 字以上の段落、または「。」で区切った文が [times] 回あるか。
bool codingGenerationRepeats(
  String text, {
  int minChars = codingGenerationRepeatMinChars,
  int times = codingGenerationRepeatTimes,
}) {
  if (minChars < 1 || times < 2) return false;
  if (text.length < minChars * times) return false;
  final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final counts = <String, int>{};
  void add(String raw) {
    final key = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (key.length < minChars) return;
    final next = (counts[key] ?? 0) + 1;
    counts[key] = next;
  }

  for (final paragraph in normalized.split(RegExp(r'\n\s*\n'))) {
    add(paragraph);
  }
  for (final sentence in normalized.split('。')) {
    add(sentence);
  }
  for (final count in counts.values) {
    if (count >= times) return true;
  }
  return false;
}
