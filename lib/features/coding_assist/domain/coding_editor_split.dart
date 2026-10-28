/// エディタ左右分割の、どのファイルをどちらに出すか。
final class CodingEditorSplit {
  const CodingEditorSplit._();

  /// [current] 以外で、並びの次を優先した開いているパス。
  static String? otherPath(List<String> openPaths, String current) {
    final index = openPaths.indexOf(current);
    if (index >= 0 && index + 1 < openPaths.length) {
      return openPaths[index + 1];
    }
    for (final path in openPaths) {
      if (path != current) return path;
    }
    return null;
  }

  /// まだ分割していないとき。選択中を右、別ファイルを左にする。
  static ({String left, String right})? placeSelectedOnRight({
    required String selected,
    required List<String> openPaths,
  }) {
    final moved = moveToRight(
      current: selected,
      rightPaths: const [],
      openPaths: openPaths,
    );
    final left = moved?.left;
    if (moved == null || left == null) return null;
    return (left: left, right: moved.shown);
  }

  /// 選択中のファイルを右へ加える。すでに右にあるファイルは右に残す。
  ///
  /// 左は、右に入っていない開いているファイル。無ければ null。
  static ({String? left, String shown, List<String> rightPaths})? moveToRight({
    required String current,
    required List<String> rightPaths,
    required List<String> openPaths,
  }) {
    if (openPaths.length < 2 || !openPaths.contains(current)) return null;
    final right = <String>[
      for (final path in rightPaths)
        if (path != current && openPaths.contains(path)) path,
      current,
    ];
    return (
      left: leftCandidate(
        openPaths: openPaths,
        rightPaths: right,
        prefer: otherPath(openPaths, current),
      ),
      shown: current,
      rightPaths: right,
    );
  }

  /// 右で選択中のファイルを右から外す。残りがあれば右の表示を続ける。
  static ({String? shown, List<String> rightPaths})? moveBackToLeft({
    required String current,
    required String? shown,
    required List<String> rightPaths,
    required List<String> openPaths,
  }) {
    if (!openPaths.contains(current) || !rightPaths.contains(current)) {
      return null;
    }
    final right = <String>[
      for (final path in rightPaths)
        if (path != current && openPaths.contains(path)) path,
    ];
    final nextShown = right.isEmpty
        ? null
        : (shown != null && shown != current && right.contains(shown)
              ? shown
              : right.last);
    return (shown: nextShown, rightPaths: right);
  }

  /// 新しく開いたファイル、または選び直したファイルは左。
  ///
  /// 右に出しているファイルを選び直したときは、そのファイルを右に残す。
  static String? splitAfterLeftChanged({
    required String? split,
    required String nextLeft,
    required List<String> openPaths,
  }) {
    if (split == null ||
        openPaths.length < 2 ||
        !openPaths.contains(nextLeft)) {
      return null;
    }
    if (openPaths.contains(split)) return split;
    return otherPath(openPaths, nextLeft);
  }

  /// 右に入っていないファイルから、左に出すパスを選ぶ。
  static String? leftCandidate({
    required List<String> openPaths,
    required List<String> rightPaths,
    required String? prefer,
  }) {
    if (prefer != null &&
        openPaths.contains(prefer) &&
        !rightPaths.contains(prefer)) {
      return prefer;
    }
    for (final path in openPaths) {
      if (!rightPaths.contains(path)) return path;
    }
    return null;
  }

  /// 右のファイルを選び直したとき、左に残すパス。
  static String? keptLeft({
    required String right,
    required String? previousLeft,
    required List<String> openPaths,
  }) {
    return leftCandidate(
      openPaths: openPaths,
      rightPaths: [right],
      prefer: previousLeft,
    );
  }

  /// 同じコントローラを、破棄前のエディタと新しいエディタが同じフレームで持つか。
  ///
  /// エディタ生成時にコントローラへ通知が飛ぶ。前のエディタの破棄はフレーム末なので、
  /// その通知がビルド中の setState になる。
  static bool mountConflicts({
    required Object? nextLeft,
    required Object? nextRight,
    required Object? shownLeft,
    required Object? shownRight,
  }) {
    if (nextRight != null && identical(nextLeft, nextRight)) return true;
    if (shownRight != null && identical(nextLeft, shownRight)) return true;
    if (nextRight != null && identical(nextRight, shownLeft)) return true;
    return false;
  }
}
