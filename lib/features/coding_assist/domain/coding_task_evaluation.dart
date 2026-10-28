import 'coding_user_history_view.dart';
import 'coding_prompt_action.dart';
import 'entities/coding_assist_entities.dart';

/// タスク評価へ渡す、タスク分解の応答と添付ファイル。
final class CodingTaskEvaluationSource {
  const CodingTaskEvaluationSource({required this.tasks, required this.files});

  /// Agent が出したタスク分解（目的と実行タスク）。元の依頼文は含まない。
  final String tasks;

  /// そのタスク分解の送信に付いていたファイル。
  final List<CodingAttachedOpenFile> files;
}

const _taskReplyPlaceholders = {'ツールを実行します…', '（応答本文なし）'};

/// 直近のタスク分解から、評価用のタスク文と添付ファイルを取る。
///
/// 分解の応答が無いときは null。ファイルが無い分解でもタスク文があれば返す。
CodingTaskEvaluationSource? codingTaskEvaluationSource(
  List<CodingChatMessage> messages,
) {
  var userIndex = -1;
  for (var i = messages.length - 1; i >= 0; i--) {
    final message = messages[i];
    if (message.role != CodingMessageRole.user) continue;
    if (!message.fixedPrompts.contains(CodingPromptAction.taskDecompose)) {
      continue;
    }
    userIndex = i;
    break;
  }
  if (userIndex < 0) return null;

  String? tasks;
  for (var i = userIndex + 1; i < messages.length; i++) {
    final message = messages[i];
    if (message.role == CodingMessageRole.user) break;
    if (message.role != CodingMessageRole.assistant) continue;
    final text = message.content.trim();
    if (text.isEmpty || _taskReplyPlaceholders.contains(text)) continue;
    tasks = text;
  }
  if (tasks == null) return null;

  final user = messages[userIndex];
  final restored = codingRestoreComposerAttachments(
    user.content,
    chips: user.historyChips,
  );
  return CodingTaskEvaluationSource(
    tasks: tasks,
    files: restored.files,
  );
}
