import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// ユーザー入力プロンプトの簡易表示行数。
const codingUserPromptPreviewLineCount = 10;

/// 改行区切りの行数。空文字は 0。
int codingUserPromptLineCount(String text) {
  if (text.isEmpty) return 0;
  return text.split('\n').length;
}

/// 簡易表示に折り返す長さか。
bool codingUserPromptExceedsPreview(String text) {
  return codingUserPromptLineCount(text) > codingUserPromptPreviewLineCount;
}

/// 先頭 [codingUserPromptPreviewLineCount] 行＋省略記号。短い文はそのまま。
String codingUserPromptPreview(String text) {
  if (!codingUserPromptExceedsPreview(text)) return text;
  final lines = text.split('\n').take(codingUserPromptPreviewLineCount);
  return '${lines.join('\n')}\n…';
}

/// Agent 入力欄。10行を超えるときだけ簡易（10行）と全文を切り替える。
class CodingDraftPromptField extends StatefulWidget {
  const CodingDraftPromptField({
    super.key,
    required this.controller,
    required this.enabled,
    required this.fontSize,
    required this.onChanged,
    required this.onSubmitShortcut,
    required this.sendButton,
  });

  final TextEditingController controller;
  final bool enabled;
  final double fontSize;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitShortcut;
  final Widget sendButton;

  @override
  State<CodingDraftPromptField> createState() => _CodingDraftPromptFieldState();
}

class _CodingDraftPromptFieldState extends State<CodingDraftPromptField> {
  bool _full = false;
  int _lines = 0;

  @override
  void initState() {
    super.initState();
    _lines = codingUserPromptLineCount(widget.controller.text);
    widget.controller.addListener(_onText);
  }

  @override
  void didUpdateWidget(covariant CodingDraftPromptField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_onText);
    widget.controller.addListener(_onText);
    _lines = codingUserPromptLineCount(widget.controller.text);
    if (_lines <= codingUserPromptPreviewLineCount) _full = false;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    super.dispose();
  }

  void _onText() {
    final next = codingUserPromptLineCount(widget.controller.text);
    final wasLong = _lines > codingUserPromptPreviewLineCount;
    final long = next > codingUserPromptPreviewLineCount;
    if (next == _lines && (long || !_full)) return;
    setState(() {
      _lines = next;
      if (!long && wasLong) _full = false;
      if (!long) _full = false;
    });
  }

  bool get _long => _lines > codingUserPromptPreviewLineCount;

  @override
  Widget build(BuildContext context) {
    final full = _full && _long;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.4;
    final field = TextField(
      controller: widget.controller,
      minLines: full ? null : 2,
      maxLines: full ? null : codingUserPromptPreviewLineCount,
      expands: full,
      enabled: widget.enabled,
      style: TextStyle(fontSize: widget.fontSize),
      textInputAction: TextInputAction.newline,
      decoration: const InputDecoration(
        hintText: 'テキストを入力（添付のみでも送信可）',
        border: OutlineInputBorder(),
        isDense: true,
        alignLabelWithHint: true,
      ),
      onChanged: widget.onChanged,
    );
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                  widget.onSubmitShortcut,
              const SingleActivator(LogicalKeyboardKey.enter, control: true):
                  widget.onSubmitShortcut,
            },
            child: field,
          ),
        ),
        const SizedBox(width: 8),
        widget.sendButton,
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (full)
          SizedBox(height: maxHeight, child: row)
        else
          IntrinsicHeight(child: row),
        if (_long)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _full = !_full),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                full ? '簡易' : '全文',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
      ],
    );
  }
}
