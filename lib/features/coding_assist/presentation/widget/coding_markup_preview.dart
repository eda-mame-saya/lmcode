import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:path/path.dart' as p;

import '../../../../theme.dart';
import 'coding_markdown.dart';

/// Markdown／マークアップ（HTML 系）のプレビュー種別。
enum CodingPreviewKind {
  markdown,
  markup,
}

/// エディタ用 Markdown／マークアップ プレビュー（読み取り専用）。
abstract final class CodingMarkupPreview {
  /// プレビュー対象なら種別、でなければ null。
  static CodingPreviewKind? kindForPath(String? relativePath) {
    if (relativePath == null || relativePath.isEmpty) return null;
    final ext = p.extension(relativePath).toLowerCase().replaceFirst('.', '');
    return switch (ext) {
      'md' || 'markdown' || 'mdx' => CodingPreviewKind.markdown,
      'html' || 'htm' || 'xhtml' || 'svg' => CodingPreviewKind.markup,
      _ => null,
    };
  }

  static bool isPreviewablePath(String? relativePath) =>
      kindForPath(relativePath) != null;

  static String buttonLabel(CodingPreviewKind kind) => switch (kind) {
        CodingPreviewKind.markdown => 'Markdown',
        CodingPreviewKind.markup => 'マークアップ',
      };
}

/// 読み取り専用のビュー表示。
class CodingMarkupPreviewPane extends StatelessWidget {
  const CodingMarkupPreviewPane({
    super.key,
    required this.kind,
    required this.content,
  });

  final CodingPreviewKind kind;
  final String content;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = AppColors.of(context);
    final bg = colors.previewBackground;
    final fg = colors.previewForeground;

    return ColoredBox(
      color: bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                'ビュー（編集不可）· ${CodingMarkupPreview.buttonLabel(kind)}',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          Expanded(
            child: switch (kind) {
              CodingPreviewKind.markdown => _MarkdownPreview(
                  data: content,
                  foreground: fg,
                ),
              CodingPreviewKind.markup => _HtmlPreview(
                  data: content,
                  foreground: fg,
                ),
            },
          ),
        ],
      ),
    );
  }
}

class _MarkdownPreview extends StatelessWidget {
  const _MarkdownPreview({
    required this.data,
    required this.foreground,
  });

  final String data;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final fontSize = 14.0;
    final codeBg = colors.codeBlockBackground;
    final base = TextStyle(
      color: foreground,
      fontSize: fontSize,
      height: 1.5,
    );

    return Markdown(
      data: data.isEmpty ? '_（空のファイル）_' : data,
      selectable: true,
      softLineBreak: true,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      inlineSyntaxes: codingMarkdownInlineSyntaxes(),
      styleSheet: MarkdownStyleSheet(
        p: base,
        pPadding: const EdgeInsets.only(bottom: 8),
        h1: base.copyWith(fontSize: fontSize + 10, fontWeight: FontWeight.w700),
        h2: base.copyWith(fontSize: fontSize + 6, fontWeight: FontWeight.w700),
        h3: base.copyWith(fontSize: fontSize + 3, fontWeight: FontWeight.w700),
        h4: base.copyWith(fontWeight: FontWeight.w700),
        h5: base.copyWith(fontWeight: FontWeight.w700),
        h6: base.copyWith(fontWeight: FontWeight.w600),
        strong: base.copyWith(fontWeight: FontWeight.w700),
        em: base.copyWith(fontStyle: FontStyle.italic),
        del: base.copyWith(decoration: TextDecoration.lineThrough),
        listBullet: base,
        blockquote: base.copyWith(
          color: foreground.withValues(alpha: 0.7),
        ),
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: colors.blockquoteBorder,
              width: 3,
            ),
          ),
        ),
        code: base.copyWith(
          fontSize: fontSize * 0.92,
          fontFamily: 'monospace',
          backgroundColor: codeBg,
        ),
        codeblockPadding: const EdgeInsets.all(12),
        codeblockDecoration: BoxDecoration(
          color: codeBg,
          borderRadius: BorderRadius.circular(6),
        ),
        a: base.copyWith(
          color: colors.primary,
          decoration: TextDecoration.underline,
        ),
        tableHead: base.copyWith(fontWeight: FontWeight.w700),
        tableBody: base,
        horizontalRuleDecoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: colors.ruleBorder),
          ),
        ),
      ),
      imageBuilder: (uri, title, alt) {
        final label = (alt != null && alt.trim().isNotEmpty)
            ? alt.trim()
            : uri.toString();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            '[画像: $label]',
            style: base.copyWith(
              color: foreground.withValues(alpha: 0.6),
              fontStyle: FontStyle.italic,
            ),
          ),
        );
      },
    );
  }
}

class _HtmlPreview extends StatelessWidget {
  const _HtmlPreview({
    required this.data,
    required this.foreground,
  });

  final String data;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final body = data.trim().isEmpty ? '<p>（空のファイル）</p>' : data;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: DefaultTextStyle(
        style: TextStyle(
          color: foreground,
          fontSize: 14,
          height: 1.5,
        ),
        child: HtmlWidget(
          body,
          textStyle: TextStyle(
            color: foreground,
            fontSize: 14,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}
