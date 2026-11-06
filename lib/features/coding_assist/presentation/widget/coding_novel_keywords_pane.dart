part of '../pages/coding_assist_page.dart';

/// 小説キーワード一覧（Agent 左隣・折りたたみ可）。
class _NovelKeywordsPane extends StatelessWidget {
  const _NovelKeywordsPane({
    required this.content,
    required this.onCollapse,
    required this.onOpenFile,
    required this.onRefresh,
  });

  final String content;
  final VoidCallback onCollapse;
  final VoidCallback onOpenFile;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final nodes = CodingNovelKeywordParser.parse(content);
    return Material(
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 40,
            child: Row(
              children: [
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'キーワード',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'keywords.md を開く',
                  onPressed: onOpenFile,
                  icon: const Icon(Icons.edit_note_outlined, size: 20),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  tooltip: 'ディスクから再読込',
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  tooltip: 'キーワードを折りたたむ',
                  onPressed: onCollapse,
                  icon: const Icon(Icons.chevron_right, size: 20),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
            child: Text(
              '編集は ${CodingNovelKeywords.relativePath} を直接編集します。'
              '見出し（#〜####）で展開できます。',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: nodes.isEmpty
                ? Center(
                    child: Text(
                      '見出しがありません\n${CodingNovelKeywords.relativePath} を編集してください',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                    children: [
                      for (final node in nodes)
                        _NovelKeywordNodeTile(node: node, depth: 0),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _NovelKeywordsCollapsedStrip extends StatelessWidget {
  const _NovelKeywordsCollapsedStrip({required this.onExpand});

  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Column(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onExpand,
              child: RotatedBox(
                quarterTurns: 3,
                child: Center(
                  child: Text(
                    'キーワード',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).hintColor,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NovelKeywordNodeTile extends StatefulWidget {
  const _NovelKeywordNodeTile({
    required this.node,
    required this.depth,
  });

  final CodingNovelKeywordNode node;
  final int depth;

  @override
  State<_NovelKeywordNodeTile> createState() => _NovelKeywordNodeTileState();
}

class _NovelKeywordNodeTileState extends State<_NovelKeywordNodeTile> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    // 上位見出しは既定で開く
    _expanded = widget.node.level <= 2;
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final scheme = Theme.of(context).colorScheme;
    final hasChildren = node.children.isNotEmpty || node.hasBody;
    final titleStyle = TextStyle(
      fontSize: (15 - (node.level - 1)).clamp(12, 15).toDouble(),
      fontWeight: FontWeight.w600,
      color: scheme.onSurface,
    );

    return Padding(
      padding: EdgeInsets.only(left: widget.depth * 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: hasChildren
                ? () => setState(() => _expanded = !_expanded)
                : null,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasChildren)
                    Icon(
                      _expanded
                          ? Icons.expand_more
                          : Icons.chevron_right,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    )
                  else
                    const SizedBox(width: 18),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Text(node.title, style: titleStyle),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            if (node.hasBody)
              Padding(
                padding: const EdgeInsets.fromLTRB(26, 0, 8, 8),
                child: _NovelKeywordMarkdownBody(data: node.body),
              ),
            for (final child in node.children)
              _NovelKeywordNodeTile(node: child, depth: widget.depth + 1),
          ],
        ],
      ),
    );
  }
}

class _NovelKeywordMarkdownBody extends StatelessWidget {
  const _NovelKeywordMarkdownBody({required this.data});

  final String data;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final foreground = colors.contentForeground;
    const fontSize = 12.5;
    final base = TextStyle(color: foreground, fontSize: fontSize, height: 1.45);
    final codeBg = colors.codeBlockBackground;

    return MarkdownBody(
      data: data,
      selectable: true,
      shrinkWrap: true,
      softLineBreak: true,
      inlineSyntaxes: codingMarkdownInlineSyntaxes(),
      styleSheet: MarkdownStyleSheet(
        p: base,
        pPadding: const EdgeInsets.only(bottom: 4),
        h1: base.copyWith(fontSize: fontSize + 2, fontWeight: FontWeight.w700),
        h2: base.copyWith(fontWeight: FontWeight.w700),
        h3: base.copyWith(fontWeight: FontWeight.w700),
        strong: base.copyWith(fontWeight: FontWeight.w700),
        em: base.copyWith(fontStyle: FontStyle.italic),
        del: base.copyWith(decoration: TextDecoration.lineThrough),
        listBullet: base,
        code: base.copyWith(
          fontSize: fontSize * 0.92,
          fontFamily: 'monospace',
          backgroundColor: codeBg,
        ),
        a: base.copyWith(
          color: colors.primary,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }
}
