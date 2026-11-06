import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:path/path.dart' as p;

import '../../../../theme.dart';
import '../../domain/coding_novel_ruby.dart';
import '../../domain/coding_workspace_kind.dart';
import 'coding_markdown.dart';

/// Markdown／マークアップ／小説のプレビュー種別。
enum CodingPreviewKind {
  markdown,
  markup,
  novel,
}

/// エディタ用 Markdown／マークアップ／小説 プレビュー（読み取り専用）。
abstract final class CodingMarkupPreview {
  /// プレビュー対象なら種別、でなければ null。
  ///
  /// `.txt` は小説ワークスペースのときだけビュー表示（ルビ確認用）。
  static CodingPreviewKind? kindForPath(
    String? relativePath, {
    CodingWorkspaceKind? workspaceKind,
  }) {
    if (relativePath == null || relativePath.isEmpty) return null;
    final ext = p.extension(relativePath).toLowerCase().replaceFirst('.', '');
    return switch (ext) {
      'md' || 'markdown' || 'mdx' => CodingPreviewKind.markdown,
      'html' || 'htm' || 'xhtml' || 'svg' => CodingPreviewKind.markup,
      'txt' when workspaceKind == CodingWorkspaceKind.novel =>
        CodingPreviewKind.novel,
      _ => null,
    };
  }

  static bool isPreviewablePath(
    String? relativePath, {
    CodingWorkspaceKind? workspaceKind,
  }) =>
      kindForPath(relativePath, workspaceKind: workspaceKind) != null;

  static String buttonLabel(CodingPreviewKind kind) => switch (kind) {
        CodingPreviewKind.markdown => 'Markdown',
        CodingPreviewKind.markup => 'マークアップ',
        CodingPreviewKind.novel => '小説',
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
              CodingPreviewKind.novel => _NovelPreview(
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

/// 小説ビュー。なろう記法のルビを振り仮名として表示する。
class _NovelPreview extends StatelessWidget {
  const _NovelPreview({
    required this.data,
    required this.foreground,
  });

  final String data;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final lines = data.isEmpty ? const ['（空のファイル）'] : data.split('\n');
    final base = TextStyle(
      color: foreground,
      fontSize: 16,
      height: 1.9,
    );
    final rubyStyle = TextStyle(
      color: foreground.withValues(alpha: 0.85),
      fontSize: 10,
      height: 1.0,
    );

    return SelectionArea(
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 32),
        itemCount: lines.length,
        itemBuilder: (context, index) {
          final line = lines[index];
          if (line.isEmpty) {
            return const SizedBox(height: 16);
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text.rich(
              TextSpan(
                children: [
                  for (final span in CodingNovelRuby.parse(line))
                    switch (span) {
                      CodingNovelPlainSpan(:final text) => TextSpan(
                          text: text,
                          style: base,
                        ),
                      CodingNovelRubySpan(:final baseString, :final ruby) =>
                        WidgetSpan(
                          alignment: PlaceholderAlignment.baseline,
                          baseline: TextBaseline.alphabetic,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(ruby, style: rubyStyle),
                              Text(baseString, style: base),
                            ],
                          ),
                        ),
                    },
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
