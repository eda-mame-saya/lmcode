/// `pubspec.yaml` のパッケージ行。name や version などの構造キーは含めない。
const _pubspecStructuralKeys = <String>{
  'name',
  'description',
  'version',
  'publish_to',
  'homepage',
  'repository',
  'issue_tracker',
  'documentation',
  'environment',
  'sdk',
  'flutter',
  'dependencies',
  'dev_dependencies',
  'dependency_overrides',
  'assets',
  'fonts',
  'uses-material-design',
  'executables',
  'topics',
  'platforms',
  'resolution',
  'screenshots',
  'funding',
  'false_secrets',
  'hooks',
};

final _dependencyKey = RegExp(r'^([A-Za-z_][\w-]*)\s*:');

/// カードに残す。同じ文が既についている提案では、自動実行を再度止めない。
const codingPackageInstallHandoffMessage =
    'パッケージの追加は人が pubspec.yaml に書いてインストールしてください。自動では書きません。';

/// 追加行がパッケージ依存（`http:` など）なら true。人が yaml とインストールを行う対象。
bool codingPatchNeedsPackageInstall({
  required String relativePath,
  required String rawDiff,
}) {
  final norm = relativePath.replaceAll('\\', '/');
  if (norm.split('/').last != 'pubspec.yaml') return false;
  for (final raw in rawDiff.split(RegExp(r'\r?\n'))) {
    if (!raw.startsWith('+') || raw.startsWith('+++')) continue;
    final line = raw.substring(1).trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final key = _dependencyKey.firstMatch(line)?.group(1);
    if (key == null || _pubspecStructuralKeys.contains(key)) continue;
    return true;
  }
  return false;
}

/// コマンド出力が「パッケージが無く pub get / yaml 追加が必要」なら true。
bool codingLogNeedsPackageInstall(String log) {
  final text = log.toLowerCase();
  return text.contains('could not find package') ||
      text.contains("couldn't resolve the package") ||
      text.contains('could not resolve the package') ||
      text.contains('version solving failed') ||
      text.contains('flutter pub get') ||
      text.contains('pub get failed');
}
