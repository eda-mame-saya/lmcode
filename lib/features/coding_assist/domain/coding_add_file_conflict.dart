import 'coding_patch.dart';

/// 既存ファイルへの Add File を、モデルに二択させずに一つの Patch へ決める。
enum CodingAddConflictAction {
  /// 対象が同じ。そのパスの Update だけ。
  updateExisting,

  /// 対象が違う。空いている別パスへの Add だけ。
  addElsewhere,

  /// 対象が違う。別パスは既にあるので、その Update だけ。
  updateElsewhere,

  /// 別パスを決められない、または開けない。再提案しない。
  drop,
}

/// 自動実行の再提案で、Agent に出させる一つの動作。
class CodingAddConflictPlan {
  const CodingAddConflictPlan({
    required this.action,
    required this.path,
    required this.instruction,
    this.avoidPath = '',
  });

  final CodingAddConflictAction action;

  /// Update または Add の対象パス。 [CodingAddConflictAction.drop] のときは空。
  final String path;

  /// その対象だけを書く指示。二択は含めない。
  final String instruction;

  /// 触らせない衝突パス。別パスへ出すときだけ入る。
  final String avoidPath;
}

final RegExp _codingDeclSymbol = RegExp(
  r'\b(?:class|enum|mixin|extension)\s+([A-Z][A-Za-z0-9_]*)',
);
final RegExp _codingGroupSymbol = RegExp(
  '''group\\(\\s*['"]([A-Za-z_][A-Za-z0-9_]*)['"]''',
);
final RegExp _codingLateSymbol = RegExp(r'\blate\s+([A-Z][A-Za-z0-9_]*)\b');
final RegExp _codingPackageImport = RegExp(
  '''import\\s+['"]package:([^/'"]+)/([^'"]+)['"]''',
);

const Set<String> _codingFrameworkSymbols = {
  'Widget',
  'StatelessWidget',
  'StatefulWidget',
  'State',
  'MaterialApp',
  'BuildContext',
  'Text',
  'Scaffold',
  'Column',
  'Row',
  'Icon',
  'IconButton',
  'TextField',
  'TextButton',
  'AlertDialog',
  'Padding',
  'Expanded',
  'EdgeInsets',
  'Duration',
  'DateTime',
  'Navigator',
  'Key',
  'Object',
  'String',
  'Future',
  'Stream',
};

/// Add File 提案の本文。`+` 省略行も含める（[CodingPatchApplier.addFileContent] と同じ方針）。
String codingProposedAddedText(String rawDiff) {
  final fromAdd = CodingPatchApplier.addFileContent(
    CodingProposedPatch(
      id: '_',
      relativePath: '_',
      rawDiff: rawDiff,
      isAddFile: true,
    ),
  );
  if (fromAdd != null && fromAdd.trim().isNotEmpty) return fromAdd;
  return rawDiff;
}

/// 宣言・`group`・`late` から、フレームワーク名を除いたシンボル。
Set<String> codingLeadingSymbols(String source) {
  final found = <String>{};
  void take(RegExp re) {
    for (final match in re.allMatches(source)) {
      final name = match.group(1);
      if (name == null || name.isEmpty) continue;
      if (_codingFrameworkSymbols.contains(name)) continue;
      found.add(name);
    }
  }

  take(_codingDeclSymbol);
  take(_codingGroupSymbol);
  take(_codingLateSymbol);
  return found;
}

/// 提案と既存の対象が違うとき、作成または修正する相対パス。
///
/// テストなら package import を `test/..._test.dart` に対応させる。
/// 同じパスしか出ないときは null。
String? codingConflictDestination({
  required String existingPath,
  required String proposedText,
  required Set<String> newSymbols,
}) {
  final existing = existingPath.replaceAll('\\', '/');
  final isTest =
      existing.startsWith('test/') || existing.endsWith('_test.dart');
  final fromImports = <String>[];
  for (final match in _codingPackageImport.allMatches(proposedText)) {
    final pkg = match.group(1) ?? '';
    final rest = match.group(2) ?? '';
    if (pkg == 'flutter' || pkg == 'flutter_test') continue;
    if (!rest.endsWith('.dart')) continue;
    final dest = isTest
        ? 'test/${rest.substring(0, rest.length - 5)}_test.dart'
        : 'lib/$rest';
    if (dest == existing || fromImports.contains(dest)) continue;
    fromImports.add(dest);
  }
  for (final symbol in newSymbols) {
    final stem = _codingSnake(symbol);
    for (final dest in fromImports) {
      if (_codingFileStem(dest) == stem) return dest;
    }
  }
  if (fromImports.isNotEmpty) return fromImports.first;
  if (newSymbols.isEmpty) return null;
  final stem = _codingSnake(newSymbols.first);
  final slash = existing.lastIndexOf('/');
  final dir = slash < 0 ? '' : existing.substring(0, slash);
  final file = isTest ? '${stem}_test.dart' : '$stem.dart';
  final dest = dir.isEmpty ? file : '$dir/$file';
  if (dest == existing) return null;
  return dest;
}

/// 既存の Add 衝突を、一つの Patch 指示にする。
///
/// [destinationOccupied] はそのパスに空でないファイルがあるとき true。
/// [destinationUnavailable] は開けないと分かっていて、中身も無いとき true。
CodingAddConflictPlan codingPlanAddFileConflict({
  required String existingPath,
  required String existingContent,
  required String proposedDiff,
  required bool Function(String path) destinationOccupied,
  bool Function(String path) destinationUnavailable = _neverUnavailable,
}) {
  final existing = existingPath.replaceAll('\\', '/');
  final proposed = codingProposedAddedText(proposedDiff);
  final currentSymbols = codingLeadingSymbols(existingContent);
  final proposedSymbols = codingLeadingSymbols(proposed);
  final sameSubject =
      currentSymbols.isEmpty ||
      proposedSymbols.isEmpty ||
      currentSymbols.intersection(proposedSymbols).isNotEmpty;
  if (sameSubject) {
    return CodingAddConflictPlan(
      action: CodingAddConflictAction.updateExisting,
      path: existing,
      instruction: _updateOnly(existing),
    );
  }
  final dest = codingConflictDestination(
    existingPath: existing,
    proposedText: proposed,
    newSymbols: proposedSymbols.difference(currentSymbols),
  );
  if (dest == null || destinationUnavailable(dest)) {
    return const CodingAddConflictPlan(
      action: CodingAddConflictAction.drop,
      path: '',
      instruction: '',
    );
  }
  if (destinationOccupied(dest)) {
    return CodingAddConflictPlan(
      action: CodingAddConflictAction.updateElsewhere,
      path: dest,
      avoidPath: existing,
      instruction: _updateElsewhere(existing: existing, dest: dest),
    );
  }
  return CodingAddConflictPlan(
    action: CodingAddConflictAction.addElsewhere,
    path: dest,
    avoidPath: existing,
    instruction: _addOnly(existing: existing, dest: dest),
  );
}

bool _neverUnavailable(String path) => false;

String _updateOnly(String path) =>
    'このパスだけを *** Update File: $path で直す。'
    'Add File は出さない。別パスは出さない。説明だけで終わらない。'
    '既存関数は 置換範囲 と -/+。+ のみは禁止。';

String _addOnly({required String existing, required String dest}) =>
    '提案の対象は既存ファイルと違う。$existing は触らない。'
    '*** Add File: $dest だけを出す。直前に 配置先: $dest を書き、Add File 行と一致させる。'
    'Update File は出さない。説明だけで終わらない。';

String _updateElsewhere({required String existing, required String dest}) =>
    '提案の対象は $dest に既にある。*** Update File: $dest だけを出す。'
    '$existing への Add File と Update File は出さない。説明だけで終わらない。'
    '既存関数は 置換範囲 と -/+。+ のみは禁止。';

String _codingSnake(String name) {
  final spaced = name
      .replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'),
        (m) => '${m.group(1)}_${m.group(2)}',
      )
      .replaceAllMapped(
        RegExp(r'([A-Z]+)([A-Z][a-z])'),
        (m) => '${m.group(1)}_${m.group(2)}',
      );
  return spaced.toLowerCase();
}

String _codingFileStem(String path) {
  final name = path.split('/').last;
  if (name.endsWith('_test.dart')) {
    return name.substring(0, name.length - '_test.dart'.length);
  }
  if (name.endsWith('.dart')) {
    return name.substring(0, name.length - '.dart'.length);
  }
  return name;
}
