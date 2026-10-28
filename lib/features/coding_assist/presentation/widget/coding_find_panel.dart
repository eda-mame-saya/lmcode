import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:re_editor/re_editor.dart';

/// エディタ右上に重ねる検索／置換バー（全画面にしない）。
/// 一致箇所への自動スクロールは re_editor 側。
/// 前へ／次へ／Enter 後もフォーカスは検索（または置換）欄に戻す（連続順送用）。
class CodingFindPanel extends StatelessWidget implements PreferredSizeWidget {
  const CodingFindPanel({
    super.key,
    required this.controller,
    required this.readOnly,
  });

  final CodeFindController controller;
  final bool readOnly;

  static const _barWidth = 432.0;
  static const _findRowHeight = 40.0;
  static const _replaceRowHeight = 36.0;
  static const _margin = EdgeInsets.only(top: 4, right: 8);
  static const _iconSize = 18.0;

  @override
  Size get preferredSize {
    if (controller.value == null) {
      return Size.zero;
    }
    return Size(
      double.infinity,
      _findRowHeight + _replaceRowHeight + _margin.vertical,
    );
  }

  /// re_editor が一致へ選択・スクロールしたあとも入力欄フォーカスを維持する。
  void _runKeepingFocus(FocusNode focus, VoidCallback action) {
    action();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!focus.canRequestFocus) return;
      focus.requestFocus();
    });
  }

  void _nextMatchKeepFindFocus() {
    _runKeepingFocus(controller.findInputFocusNode, controller.nextMatch);
  }

  void _previousMatchKeepFindFocus() {
    _runKeepingFocus(controller.findInputFocusNode, controller.previousMatch);
  }

  void _replaceMatchKeepReplaceFocus() {
    _runKeepingFocus(controller.replaceInputFocusNode, controller.replaceMatch);
  }

  @override
  Widget build(BuildContext context) {
    if (controller.value == null) {
      return const SizedBox(width: 0, height: 0);
    }
    final scheme = Theme.of(context).colorScheme;
    final value = controller.value!;
    final caseSensitive = value.option.caseSensitive;
    final result = value.result;
    final resultLabel = result == null
        ? '—'
        : '${result.index + 1}/${result.matches.length}';
    final canReplace = !readOnly && result != null && result.matches.isNotEmpty;

    return Container(
      margin: _margin,
      alignment: Alignment.topRight,
      height: preferredSize.height,
      child: Material(
        elevation: 2,
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: _barWidth,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 2, 2, 4),
            child: Column(
              children: [
                SizedBox(
                  height: _findRowHeight - 4,
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller.findInputController,
                          focusNode: controller.findInputFocusNode,
                          style: const TextStyle(fontSize: 13),
                          textInputAction: TextInputAction.search,
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: '検索',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                          ),
                          onSubmitted: (_) => _nextMatchKeepFindFocus(),
                        ),
                      ),
                      ExcludeFocus(
                        child: CodingMatchCaseButton(
                          selected: caseSensitive,
                          onPressed: controller.toggleCaseSensitive,
                        ),
                      ),
                      const SizedBox(width: 4),
                      SizedBox(
                        width: 48,
                        child: Text(
                          resultLabel,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      ExcludeFocus(
                        child: IconButton(
                          tooltip: '前へ',
                          onPressed: result == null
                              ? null
                              : _previousMatchKeepFindFocus,
                          icon: const Icon(
                            Icons.keyboard_arrow_up,
                            size: _iconSize,
                          ),
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          splashRadius: max(16.0, _iconSize),
                        ),
                      ),
                      ExcludeFocus(
                        child: IconButton(
                          tooltip: '次へ',
                          onPressed: result == null
                              ? null
                              : _nextMatchKeepFindFocus,
                          icon: const Icon(
                            Icons.keyboard_arrow_down,
                            size: _iconSize,
                          ),
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          splashRadius: max(16.0, _iconSize),
                        ),
                      ),
                      IconButton(
                        tooltip: '閉じる',
                        onPressed: controller.close,
                        icon: const Icon(Icons.close, size: _iconSize),
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        splashRadius: max(16.0, _iconSize),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: _replaceRowHeight,
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller.replaceInputController,
                          focusNode: controller.replaceInputFocusNode,
                          enabled: !readOnly,
                          style: const TextStyle(fontSize: 13),
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: '置換',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                          ),
                          onSubmitted: canReplace
                              ? (_) => _replaceMatchKeepReplaceFocus()
                              : null,
                        ),
                      ),
                      const SizedBox(width: 4),
                      ExcludeFocus(
                        child: IconButton(
                          tooltip: '置換',
                          onPressed: canReplace
                              ? _replaceMatchKeepReplaceFocus
                              : null,
                          icon: const Icon(Icons.find_replace, size: _iconSize),
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          splashRadius: max(16.0, _iconSize),
                        ),
                      ),
                      ExcludeFocus(
                        child: IconButton(
                          tooltip: 'すべて置換',
                          onPressed: canReplace
                              ? () => _runKeepingFocus(
                                  controller.replaceInputFocusNode,
                                  controller.replaceAllMatches,
                                )
                              : null,
                          icon: const Icon(Icons.done_all, size: _iconSize),
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          splashRadius: max(16.0, _iconSize),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 検索の「大文字小文字を区別」トグル。オンのときだけ大小も一致させる。
class CodingMatchCaseButton extends StatelessWidget {
  const CodingMatchCaseButton({
    super.key,
    required this.selected,
    required this.onPressed,
  });

  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    return IconButton(
      tooltip: '大文字小文字を区別',
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: selected ? scheme.primaryContainer : null,
        foregroundColor: selected
            ? scheme.onPrimaryContainer
            : (enabled ? scheme.onSurfaceVariant : scheme.outline),
        visualDensity: VisualDensity.compact,
        minimumSize: const Size(32, 32),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: const Text(
        'Aa',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
    );
  }
}
