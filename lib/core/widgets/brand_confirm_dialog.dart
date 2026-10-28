import 'package:flutter/material.dart';

import '../../theme.dart';

/// UI共通_モーダル基本系：プライマリ帯タイトル＋キャンセル／確定。
Future<bool> showBrandConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String cancelLabel = 'キャンセル',
  String confirmLabel = 'OK',
  bool isDestructive = false,
}) async {
  final colors = AppColors.of(context);
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: colors.dialogBarrier,
    builder: (dialogContext) {
      final dialogColors = AppColors.of(dialogContext);
      return Dialog(
        backgroundColor: dialogColors.dialogSurface,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: dialogColors.primary,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(8)),
                ),
                child: Text(
                  title,
                  style: TextStyle(
                    color: dialogColors.onPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Text(message, style: const TextStyle(height: 1.45)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: dialogColors.dialogCancel,
                          foregroundColor: dialogColors.onPrimary,
                        ),
                        onPressed: () =>
                            Navigator.of(dialogContext).pop(false),
                        child: Text(cancelLabel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: isDestructive
                              ? dialogColors.destructive
                              : dialogColors.primary,
                          foregroundColor: dialogColors.onPrimary,
                        ),
                        onPressed: () =>
                            Navigator.of(dialogContext).pop(true),
                        child: Text(confirmLabel),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  return result == true;
}
