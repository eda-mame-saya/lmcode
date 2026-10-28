import 'package:markdown/markdown.dart';

/// 日本語＋全角句読点でも `**太字**` を strong にする（CommonMark 区切り規則の抜け道）。
final class CodingStrongSyntax extends InlineSyntax {
  CodingStrongSyntax() : super(r'\*\*(.+?)\*\*', startCharacter: 0x2a);

  @override
  bool onMatch(InlineParser parser, Match match) {
    final inner = match[1];
    if (inner == null || inner.isEmpty) return false;
    parser.addNode(Element.text('strong', inner));
    return true;
  }
}

/// Agent 吹き出し／マークアップビュー用のインライン拡張。
List<InlineSyntax> codingMarkdownInlineSyntaxes() => [CodingStrongSyntax()];
