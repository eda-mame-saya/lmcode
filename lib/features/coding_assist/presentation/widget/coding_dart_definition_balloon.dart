import 'package:flutter/material.dart';

/// エディタ上に出す定義の吹き出し。別ページには遷移しない。
class CodingDartDefinitionBalloon extends StatelessWidget {
  const CodingDartDefinitionBalloon({
    super.key,
    required this.anchor,
    required this.title,
    required this.body,
    required this.onDismiss,
  });

  final Offset anchor;
  final String title;
  final String body;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = (size.width - 16).clamp(240.0, 560.0).toDouble();
    var left = anchor.dx;
    var top = anchor.dy + 12;
    if (left + width > size.width - 8) left = size.width - width - 8;
    if (left < 8) left = 8;
    if (top + 300 > size.height - 8) {
      top = anchor.dy - 300 - 12;
    }
    if (top < 8) top = 8;

    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onDismiss,
            onSecondaryTap: onDismiss,
          ),
        ),
        Positioned(
          left: left,
          top: top,
          width: width,
          child: GestureDetector(
            onTap: () {},
            child: Material(
              elevation: 8,
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '閉じる',
                          visualDensity: VisualDensity.compact,
                          onPressed: onDismiss,
                          icon: const Icon(Icons.close, size: 18),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      child: SelectableText(
                        body,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          fontFamily: 'monospace',
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
