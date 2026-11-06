/// 小説執筆モードの改行インデント設定。
enum CodingNovelIndentSpace {
  /// 半角スペース。
  halfWidth,

  /// 全角スペース（U+3000）。
  fullWidth,
}

/// セリフ行を判定する開き／閉じ記号の組。
final class CodingNovelDialogueDelimiter {
  const CodingNovelDialogueDelimiter({
    required this.open,
    required this.close,
  });

  /// 既定: 「」と『』。
  static const defaults = <CodingNovelDialogueDelimiter>[
    CodingNovelDialogueDelimiter(open: '「', close: '」'),
    CodingNovelDialogueDelimiter(open: '『', close: '』'),
  ];

  final String open;
  final String close;

  String get label => '$open$close';

  bool get isValid =>
      open.isNotEmpty && close.isNotEmpty && open != close;

  CodingNovelDialogueDelimiter copyWith({String? open, String? close}) {
    return CodingNovelDialogueDelimiter(
      open: open ?? this.open,
      close: close ?? this.close,
    );
  }

  Map<String, dynamic> toJson() => {'open': open, 'close': close};

  static CodingNovelDialogueDelimiter? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final open = '${raw['open'] ?? ''}'.trim();
    final close = '${raw['close'] ?? ''}'.trim();
    if (open.isEmpty || close.isEmpty) return null;
    return CodingNovelDialogueDelimiter(open: open, close: close);
  }

  @override
  bool operator ==(Object other) {
    return other is CodingNovelDialogueDelimiter &&
        other.open == open &&
        other.close == close;
  }

  @override
  int get hashCode => Object.hash(open, close);
}

/// 小説ワークスペース向けの表示・整形設定（永続）。
final class CodingNovelSettings {
  const CodingNovelSettings({
    this.indentCount = defaultIndentCount,
    this.indentSpace = CodingNovelIndentSpace.fullWidth,
    this.indentDialogue = false,
    this.dialogueDelimiters = CodingNovelDialogueDelimiter.defaults,
  });

  static const defaults = CodingNovelSettings();

  /// 改行時に入れるインデント文字数の既定（全角1文字＝一段落字下げ）。
  static const defaultIndentCount = 1;

  static const minIndentCount = 0;
  static const maxIndentCount = 8;
  static const maxDialogueDelimiters = 12;

  /// インデント文字数（0〜8）。
  final int indentCount;

  /// 半角／全角スペース。
  final CodingNovelIndentSpace indentSpace;

  /// セリフ行にもインデントするか。
  final bool indentDialogue;

  /// セリフ判定に使う開き／閉じ記号の組（複数可）。
  final List<CodingNovelDialogueDelimiter> dialogueDelimiters;

  String get indentUnit => switch (indentSpace) {
        CodingNovelIndentSpace.halfWidth => ' ',
        CodingNovelIndentSpace.fullWidth => '　',
      };

  /// 改行直後に挿入するインデント文字列。
  String get newlineIndent {
    final n = indentCount.clamp(minIndentCount, maxIndentCount);
    if (n <= 0) return '';
    return indentUnit * n;
  }

  /// 有効なセリフ記号組（空や不正は除く）。空なら既定にフォールバック。
  List<CodingNovelDialogueDelimiter> get effectiveDialogueDelimiters {
    final valid = [
      for (final d in dialogueDelimiters)
        if (d.isValid) d,
    ];
    if (valid.isEmpty) return CodingNovelDialogueDelimiter.defaults;
    return valid;
  }

  CodingNovelSettings copyWith({
    int? indentCount,
    CodingNovelIndentSpace? indentSpace,
    bool? indentDialogue,
    List<CodingNovelDialogueDelimiter>? dialogueDelimiters,
  }) {
    final nextDelims = dialogueDelimiters == null
        ? this.dialogueDelimiters
        : _normalizeDelimiters(dialogueDelimiters);
    return CodingNovelSettings(
      indentCount: (indentCount ?? this.indentCount)
          .clamp(minIndentCount, maxIndentCount),
      indentSpace: indentSpace ?? this.indentSpace,
      indentDialogue: indentDialogue ?? this.indentDialogue,
      dialogueDelimiters: nextDelims,
    );
  }

  static List<CodingNovelDialogueDelimiter> _normalizeDelimiters(
    List<CodingNovelDialogueDelimiter> raw,
  ) {
    final seen = <String>{};
    final out = <CodingNovelDialogueDelimiter>[];
    for (final d in raw) {
      if (!d.isValid) continue;
      final key = '${d.open}\u0000${d.close}';
      if (!seen.add(key)) continue;
      out.add(d);
      if (out.length >= maxDialogueDelimiters) break;
    }
    return List.unmodifiable(out);
  }

  Map<String, dynamic> toJson() => {
        'indentCount': indentCount,
        'indentSpace': indentSpace.name,
        'indentDialogue': indentDialogue,
        'dialogueDelimiters': [
          for (final d in dialogueDelimiters) d.toJson(),
        ],
      };

  static CodingNovelSettings fromJson(Map<String, dynamic> json) {
    final count = json['indentCount'];
    final spaceRaw = '${json['indentSpace'] ?? ''}';
    var space = CodingNovelIndentSpace.fullWidth;
    for (final v in CodingNovelIndentSpace.values) {
      if (v.name == spaceRaw) {
        space = v;
        break;
      }
    }
    final delimsRaw = json['dialogueDelimiters'];
    final delims = <CodingNovelDialogueDelimiter>[];
    if (delimsRaw is List) {
      for (final item in delimsRaw) {
        final d = CodingNovelDialogueDelimiter.fromJson(item);
        if (d != null) delims.add(d);
      }
    }
    return CodingNovelSettings(
      indentCount: count is int
          ? count.clamp(minIndentCount, maxIndentCount)
          : defaultIndentCount,
      indentSpace: space,
      indentDialogue: json['indentDialogue'] == true,
      dialogueDelimiters: delims.isEmpty
          ? CodingNovelDialogueDelimiter.defaults
          : _normalizeDelimiters(delims),
    );
  }

  @override
  bool operator ==(Object other) {
    if (other is! CodingNovelSettings) return false;
    if (other.indentCount != indentCount ||
        other.indentSpace != indentSpace ||
        other.indentDialogue != indentDialogue) {
      return false;
    }
    if (other.dialogueDelimiters.length != dialogueDelimiters.length) {
      return false;
    }
    for (var i = 0; i < dialogueDelimiters.length; i++) {
      if (other.dialogueDelimiters[i] != dialogueDelimiters[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        indentCount,
        indentSpace,
        indentDialogue,
        Object.hashAll(dialogueDelimiters),
      );
}
