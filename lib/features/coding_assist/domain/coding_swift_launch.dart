import 'dart:convert';

/// ワークスペース直下を見て、Swift 補完をどの経路で起動するか決める。
class CodingSwiftRootPlan {
  const CodingSwiftRootPlan._({
    required this.kind,
    this.xcodeprojName,
    this.message,
  });

  const CodingSwiftRootPlan.inactive()
      : this._(kind: CodingSwiftRootKind.inactive);

  const CodingSwiftRootPlan.package()
      : this._(kind: CodingSwiftRootKind.swiftPackage);

  const CodingSwiftRootPlan.xcode(String name)
      : this._(kind: CodingSwiftRootKind.xcodeProject, xcodeprojName: name);

  const CodingSwiftRootPlan.blocked(String message)
      : this._(kind: CodingSwiftRootKind.blocked, message: message);

  final CodingSwiftRootKind kind;
  final String? xcodeprojName;
  final String? message;

  static CodingSwiftRootPlan from({
    required List<String> xcodeprojNames,
    required bool hasPackageSwift,
  }) {
    if (xcodeprojNames.length > 1) {
      return const CodingSwiftRootPlan.blocked(
        'Swift補完: .xcodeproj が複数のためオフ',
      );
    }
    if (xcodeprojNames.length == 1) {
      return CodingSwiftRootPlan.xcode(xcodeprojNames.single);
    }
    if (hasPackageSwift) return const CodingSwiftRootPlan.package();
    return const CodingSwiftRootPlan.inactive();
  }
}

enum CodingSwiftRootKind { inactive, swiftPackage, xcodeProject, blocked }

/// `xcodebuild -list -json` の標準出力からスキーム名を取る。
List<String> codingSwiftSchemes(String stdout) {
  final decoded = _decodeObject(stdout);
  if (decoded == null) return const [];
  final project = decoded['project'] ?? decoded['workspace'];
  if (project is! Map) return const [];
  final schemes = project['schemes'];
  if (schemes is! List) return const [];
  return [
    for (final name in schemes)
      if ('$name'.trim().isNotEmpty) '$name'.trim(),
  ];
}

/// `xcodebuild -showBuildSettingsForIndex` からファイルごとのコンパイラ引数を取る。
Map<String, List<String>> codingSwiftCompilerArguments(String stdout) {
  final decoded = _decodeObject(stdout);
  if (decoded == null) return const {};
  final out = <String, List<String>>{};
  decoded.forEach((key, value) {
    if (value is! Map) return;
    final args = value['swiftASTCommandArguments'];
    if (args is! List) return;
    final list = <String>[
      for (final arg in args) '$arg',
    ];
    if (list.isEmpty) return;
    out[key] = list;
  });
  return out;
}

Map<String, dynamic>? _decodeObject(String stdout) {
  final start = stdout.indexOf('{');
  final end = stdout.lastIndexOf('}');
  if (start < 0 || end <= start) return null;
  try {
    final decoded = jsonDecode(stdout.substring(start, end + 1));
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } catch (_) {
    return null;
  }
  return null;
}
