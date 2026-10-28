import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

/// HSV＋HEX 入力の色選択ダイアログ。確定色を返す（キャンセルは null）。
Future<Color?> showAppColorPickerDialog({
  required BuildContext context,
  required String title,
  required Color initialColor,
  bool enableAlpha = false,
}) {
  var pending = initialColor;
  return showDialog<Color>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: pending,
            onColorChanged: (color) => pending = color,
            enableAlpha: enableAlpha,
            hexInputBar: true,
            labelTypes: const [],
            pickerAreaHeightPercent: 0.7,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(pending),
            child: const Text('決定'),
          ),
        ],
      );
    },
  );
}
