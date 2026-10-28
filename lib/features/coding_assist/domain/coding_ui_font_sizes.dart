/// S16 メニュー／エディタ／Agent の表示フォントサイズ（pt 相当）。
final class CodingUiFontSizes {
  const CodingUiFontSizes({
    required this.menu,
    required this.editor,
    required this.agent,
  });

  static const min = 10.0;
  static const max = 22.0;

  static const defaults = CodingUiFontSizes(
    menu: 12,
    editor: 13,
    agent: 13,
  );

  final double menu;
  final double editor;
  final double agent;

  CodingUiFontSizes copyWith({
    double? menu,
    double? editor,
    double? agent,
  }) {
    return CodingUiFontSizes(
      menu: clamp(menu ?? this.menu),
      editor: clamp(editor ?? this.editor),
      agent: clamp(agent ?? this.agent),
    );
  }

  static double clamp(double value) => value.clamp(min, max).toDouble();

  @override
  bool operator ==(Object other) {
    return other is CodingUiFontSizes &&
        other.menu == menu &&
        other.editor == editor &&
        other.agent == agent;
  }

  @override
  int get hashCode => Object.hash(menu, editor, agent);
}
