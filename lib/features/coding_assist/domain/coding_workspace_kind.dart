import 'dart:io';

import 'package:path/path.dart' as p;

/// S16 ワークスペースの開発プロファイル。
enum CodingWorkspaceKind {
  /// `pubspec.yaml` がある（第一ターゲット）。
  flutter,

  /// `.xcodeproj` / `.xcworkspace` / `Package.swift` がある。
  swiftXcode,

  /// React（`package.json`＋JSX/TSX、または Next 等の設定）。
  react,

  /// Android（Java / Kotlin）。`settings.gradle(.kts)` / `AndroidManifest.xml` 等。
  android,

  /// `pyproject.toml` / `requirements.txt` / `setup.py` / `Pipfile` がある。
  python,

  /// 上記以外。
  generic,
}

/// ルート検出とプロファイル別 system prompt（S16）。
abstract final class CodingWorkspaceKindDetect {
  static const _pythonRootMarkers = <String>{
    'pyproject.toml',
    'requirements.txt',
    'setup.py',
    'setup.cfg',
    'Pipfile',
  };

  /// React / Next 系のルート設定ファイル。
  static const _reactRootConfigMarkers = <String>{
    'next.config.js',
    'next.config.mjs',
    'next.config.cjs',
    'next.config.ts',
    'remix.config.js',
    'remix.config.mjs',
  };

  /// 索引のパス一覧から判定。`pubspec.yaml` があれば Flutter 優先（`ios/` 同梱対策）。
  /// 優先順: Flutter → Swift/Xcode → React → Android → Python → generic。
  static CodingWorkspaceKind fromLists({
    required List<String> relativeFiles,
    required List<String> relativeDirectories,
  }) {
    if (relativeFiles.contains('pubspec.yaml')) {
      return CodingWorkspaceKind.flutter;
    }
    if (relativeFiles.contains('Package.swift')) {
      return CodingWorkspaceKind.swiftXcode;
    }
    for (final d in relativeDirectories) {
      final name = p.basename(d);
      if (name.endsWith('.xcodeproj') || name.endsWith('.xcworkspace')) {
        return CodingWorkspaceKind.swiftXcode;
      }
    }
    for (final f in relativeFiles) {
      if (f.endsWith('.swift')) {
        return CodingWorkspaceKind.swiftXcode;
      }
    }
    if (_looksLikeReact(relativeFiles)) {
      return CodingWorkspaceKind.react;
    }
    if (_looksLikeAndroid(relativeFiles)) {
      return CodingWorkspaceKind.android;
    }
    for (final marker in _pythonRootMarkers) {
      if (relativeFiles.contains(marker)) {
        return CodingWorkspaceKind.python;
      }
    }
    // ルート直下に .py があり、他マーカーが無い場合も Python 扱い
    final hasRootPy = relativeFiles.any(
      (f) => !f.contains('/') && f.endsWith('.py'),
    );
    if (hasRootPy) return CodingWorkspaceKind.python;
    return CodingWorkspaceKind.generic;
  }

  static bool _looksLikeReact(List<String> relativeFiles) {
    for (final marker in _reactRootConfigMarkers) {
      if (relativeFiles.contains(marker)) return true;
    }
    final hasPackageJson = relativeFiles.contains('package.json');
    if (!hasPackageJson) return false;
    return relativeFiles.any((f) => f.endsWith('.tsx') || f.endsWith('.jsx'));
  }

  /// Android / Gradle（Java・Kotlin）系。
  static bool _looksLikeAndroid(List<String> relativeFiles) {
    if (relativeFiles.any(
      (f) => f == 'AndroidManifest.xml' || f.endsWith('/AndroidManifest.xml'),
    )) {
      return true;
    }
    if (relativeFiles.contains('settings.gradle') ||
        relativeFiles.contains('settings.gradle.kts')) {
      return true;
    }
    final hasRootBuildGradle =
        relativeFiles.contains('build.gradle') ||
        relativeFiles.contains('build.gradle.kts');
    if (!hasRootBuildGradle) return false;
    return relativeFiles.any((f) => f.endsWith('.kt') || f.endsWith('.java'));
  }

  /// ルート直下だけ見て判定（走査前・単体テスト用）。
  static Future<CodingWorkspaceKind> fromRoot(String rootPath) async {
    final root = Directory(rootPath);
    if (!await root.exists()) return CodingWorkspaceKind.generic;
    var hasPubspec = false;
    var hasSwiftMarker = false;
    var hasPythonMarker = false;
    var hasRootPy = false;
    var hasReactConfig = false;
    var hasPackageJson = false;
    var hasReactDepInPackageJson = false;
    var hasRootJsxTsx = false;
    var hasAndroidMarker = false;
    var hasRootBuildGradle = false;
    var hasRootKtJava = false;
    try {
      await for (final entity in root.list(followLinks: false)) {
        final name = p.basename(entity.path);
        if (entity is File && name == 'pubspec.yaml') {
          hasPubspec = true;
        } else if (entity is File && name == 'Package.swift') {
          hasSwiftMarker = true;
        } else if (entity is Directory &&
            (name.endsWith('.xcodeproj') || name.endsWith('.xcworkspace'))) {
          hasSwiftMarker = true;
        } else if (entity is File && _reactRootConfigMarkers.contains(name)) {
          hasReactConfig = true;
        } else if (entity is File && name == 'package.json') {
          hasPackageJson = true;
          try {
            final text = await File(entity.path).readAsString();
            if (_packageJsonMentionsReact(text)) {
              hasReactDepInPackageJson = true;
            }
          } catch (_) {}
        } else if (entity is File &&
            (name.endsWith('.tsx') || name.endsWith('.jsx'))) {
          hasRootJsxTsx = true;
        } else if (entity is File &&
            (name == 'settings.gradle' ||
                name == 'settings.gradle.kts' ||
                name == 'AndroidManifest.xml')) {
          hasAndroidMarker = true;
        } else if (entity is File &&
            (name == 'build.gradle' || name == 'build.gradle.kts')) {
          hasRootBuildGradle = true;
        } else if (entity is File &&
            (name.endsWith('.kt') || name.endsWith('.java'))) {
          hasRootKtJava = true;
        } else if (entity is File && _pythonRootMarkers.contains(name)) {
          hasPythonMarker = true;
        } else if (entity is File && name.endsWith('.py')) {
          hasRootPy = true;
        }
      }
    } catch (_) {
      return CodingWorkspaceKind.generic;
    }
    if (hasPubspec) return CodingWorkspaceKind.flutter;
    if (hasSwiftMarker) return CodingWorkspaceKind.swiftXcode;
    if (hasReactConfig ||
        hasReactDepInPackageJson ||
        (hasPackageJson && hasRootJsxTsx)) {
      return CodingWorkspaceKind.react;
    }
    if (hasAndroidMarker || (hasRootBuildGradle && hasRootKtJava)) {
      return CodingWorkspaceKind.android;
    }
    if (hasPythonMarker || hasRootPy) return CodingWorkspaceKind.python;
    return CodingWorkspaceKind.generic;
  }

  /// `package.json` 本文に react 依存の気配があるか（軽量ヒューリスティック）。
  static bool _packageJsonMentionsReact(String text) {
    // "react" / "react-dom" / "next" を依存キーとしてざっくり検出
    return RegExp(r'''["'](react|react-dom|next)["']\s*:''').hasMatch(text);
  }

  static String displayLabel(CodingWorkspaceKind kind) => switch (kind) {
    CodingWorkspaceKind.flutter => 'Flutter',
    CodingWorkspaceKind.swiftXcode => 'Xcode / Swift',
    CodingWorkspaceKind.react => 'React',
    CodingWorkspaceKind.android => 'Android (Java/Kotlin)',
    CodingWorkspaceKind.python => 'Python',
    CodingWorkspaceKind.generic => '汎用',
  };

  /// Flutter の機能追加・修正で、`test/` に回帰テストを同梱する指示。
  /// 平文送信は system に、＋メニューの実装系は user 側にも載せる。
  static const flutterRegressionTestRule = '''
Flutter の回帰テスト（Flutter ワークスペースで、Dart の振る舞いを追加または修正するときだけ）:
- 実装と同じ応答で test/ の *_test.dart も追加または更新する。一部の修正で他の機能が壊れないことを、あとから走る flutter test で見つける
- 出す前に list_dir または grep で test/ を見る。対象の *_test.dart があれば Update File、無ければ Add File
- 配置は lib に合わせる（lib/features/foo/bar.dart → test/features/foo/bar_test.dart）。ファイル名だけは不可
- テストするのは今回変える振る舞いと、その変更で壊れうる隣接の振る舞い
- import は package:flutter_test とテスト対象。pubspec.yaml にパッケージ行を足さない
- 新規ファイルは Add File（+ のみ、直前に 配置先:）。既存テスト関数の修正は 1 Patch = 関数1つ
- コメント・文書・プロンプト文言だけ、テスト自身だけの修正、文法エラーだけで振る舞いが変わらないときは、新しいテストを足さない
''';

  /// Agent 用 system prompt 本文（ワークスペースパス／樹は呼び出し側で追記）。
  static String systemPrompt(CodingWorkspaceKind kind) => switch (kind) {
    CodingWorkspaceKind.flutter => _flutterPrompt,
    CodingWorkspaceKind.swiftXcode => _swiftXcodePrompt,
    CodingWorkspaceKind.react => _reactPrompt,
    CodingWorkspaceKind.android => _androidPrompt,
    CodingWorkspaceKind.python => _pythonPrompt,
    CodingWorkspaceKind.generic => _genericPrompt,
  };

  static String _promptBody({
    required String roleLine,
    required String listDirExample,
    required String readFileExample,
    required String grepPathExample,
    required String updateFileExample,
    required String pathNotes,
  }) =>
      '''
$roleLine
ビルドやターミナルは実行できません。コードの調査と編集案のみ担当します。

ツールを使うときは必ず次のフェンスだけを出力してください（他の説明の前後に置いてよい）:
```tool
{"name":"list_dir","args":{"path":"$listDirExample"}}
```
```tool
{"name":"read_file","args":{"path":"$readFileExample"}}
```
```tool
{"name":"grep","args":{"pattern":"ClassName","path":"$grepPathExample"}}
```
grep の pattern は**既定でリテラル**（部分一致）。正規表現が必要なときだけ `"regex":true` を付ける。

ファイル変更案は次の形式のみ（カードに出します。自動実行 ON ならアプリが Update と Add を書き、OFF なら人が適用／作成します）:
*** Begin Patch
*** Update File: $updateFileExample
@@
 前後の文脈行（先頭にスペース1つ）
-削除する行（ファイル内の文字列と完全一致）
+追加する行
*** End Patch

注意:
- ワークスペースはユーザーが開いたフォルダ直下（相対パス。例: README.md, $readFileExample）
- ファイルの有無は推測しない。無い／読めないと言う前に list_dir・grep・read_file を使う
- ツールが「候補」を返したら、その相対パスを使ってやり直す
- 同一相対パスの read_file が連続3回失敗（本文が返らない）したら、そのパスは再試行せず tool を出さず中断する。回数はパスごと（read_file 全体の3回ではない。別パスは数えない。そのパスで成功したら回数は戻す）
- 中断時は、この依頼で読むと分かっているファイルをすべて、開いて取り込みするよう頼む（失敗した1件だけにしない。A が3回失敗し B と C も読む予定なら A・B・C を全部書く）
- 頼むパスはリンクだけ。例: [lib/foo.dart](coding-file:lib/foo.dart)。コードフェンスで包まない。クリックでエディタが開く。続けてタブ行の取り込みをする旨を1行
- ユーザー発言に【開いているファイル: 相対パス】があるパスは、その本文を正とし read_file しない。載っていないパスだけ read_file してよい
$pathNotes
- **既存関数の修正**: `-` と `+` の両方（関数全体）。変更行だけの断片・クラス／ファイル全文の再掲は禁止。Patch 直前に `置換範囲: 開始-終了`（read_file 本文を1行目から数えた関数の行。自動実行はこの範囲を + 行で置換する）
- **新規関数の追加だけ例外で + のみ**（- なし）。Patch 直前に `挿入行: N`（1-based）。既存関数の修正に + だけの追記は禁止
- read_file の該当箇所をそのまま - 行に使う。文脈行（先頭スペース）は不要。@@ は1 Patch に1回
- **1 Patch = 関数1つ**。複数は Begin/End Patch を分ける。Markdown の ``` でパッチを包まない
- **新規ファイル**: *** Add File: ディレクトリ付き相対パス と + のみ。直前に `配置先:`。パスは WS ルート基準（メニュー選択位置は根拠にしない）
- 既存への関数追加は Update File（+ のみ）。既存修正に Add File を使わない
- `.pbxproj` の深い編集はしない

思考モードでもルールの逐条照合や長考は不要。すぐに tool か Patch へ進む。日本語で簡潔に。
絵文字・顔文字・装飾記号は使わない。
''';

  /// ＋メニューのパス例。Flutter 以外に `lib/` を出さない。
  static CodingWorkspacePathSamples samplesFor(
    CodingWorkspaceKind kind,
  ) => switch (kind) {
    CodingWorkspaceKind.flutter => const CodingWorkspacePathSamples(
      addFile: 'lib/features/foo/foo_service.dart',
      updateFile: 'lib/foo.dart',
      layoutHint: '既存の features／domain／data 等の並び',
      bareName: 'foo.dart',
      usesFlutterTests: true,
    ),
    CodingWorkspaceKind.swiftXcode => const CodingWorkspacePathSamples(
      addFile: 'App/Views/ContentView.swift',
      updateFile: 'App/ContentView.swift',
      layoutHint:
          '既存の Swift の並び（App、Sources、プロジェクト名と同じフォルダ）。lib/ や test/ や features/ は使わない',
      bareName: 'ContentView.swift',
      usesFlutterTests: false,
    ),
    CodingWorkspaceKind.react => const CodingWorkspacePathSamples(
      addFile: 'src/components/Example.tsx',
      updateFile: 'src/App.tsx',
      layoutHint: '既存の src／app／components の並び。lib/ や test/ の Dart 配置は使わない',
      bareName: 'Example.tsx',
      usesFlutterTests: false,
    ),
    CodingWorkspaceKind.android => const CodingWorkspacePathSamples(
      addFile: 'app/src/main/java/com/example/MainActivity.kt',
      updateFile: 'app/src/main/java/com/example/MainActivity.kt',
      layoutHint: '既存の app/src 配下。lib/ や features/ の Dart 配置は使わない',
      bareName: 'MainActivity.kt',
      usesFlutterTests: false,
    ),
    CodingWorkspaceKind.python => const CodingWorkspacePathSamples(
      addFile: 'src/app/main.py',
      updateFile: 'src/app/main.py',
      layoutHint: '既存の src／tests の並び。lib/ の Dart 配置は使わない',
      bareName: 'main.py',
      usesFlutterTests: false,
    ),
    CodingWorkspaceKind.generic => const CodingWorkspacePathSamples(
      addFile: 'src/foo/bar.txt',
      updateFile: 'src/example.txt',
      layoutHint: 'list_dir で見えた既存の並び。lib/ を既定にしない',
      bareName: 'bar.txt',
      usesFlutterTests: false,
    ),
  };

  static String symbolToolsFor(CodingWorkspaceKind kind) {
    if (kind == CodingWorkspaceKind.flutter) return symbolToolsPrompt;
    return symbolToolsPrompt.replaceAll(
      'lib/example.dart',
      samplesFor(kind).updateFile,
    );
  }

  /// 言語サーバ起動時だけ system に足す（S16 検討: シンボル探索）。
  static const symbolToolsPrompt = '''
シンボル探索（起動中の言語サーバのみ。失敗したら list_dir / read_file / grep）:
```tool
{"name":"file_outline","args":{"path":"lib/example.dart"}}
```
```tool
{"name":"workspace_symbol","args":{"query":"ClassName"}}
```
```tool
{"name":"go_to_definition","args":{"path":"lib/example.dart","line":10,"symbol":"methodName"}}
```
```tool
{"name":"find_references","args":{"path":"lib/example.dart","line":10,"symbol":"methodName"}}
```
- 影響範囲は find_references。同名の別シンボルやコメントは返さない
- 編集する関数の原文は read_file。参照一覧だけでは - 行を作らない
- line は 1 始まり。symbol はその行にある識別子。column は 1 始まりで任意
''';

  static final _flutterPrompt = _promptBody(
    roleLine: 'あなたは Flutter（iOS/Android）開発向けのローカル・コーディングアシスタントです。',
    listDirExample: 'lib',
    readFileExample: 'lib/main.dart',
    grepPathExample: 'lib',
    updateFileExample: 'lib/example.dart',
    pathNotes:
        '- ルートの README.md / pubspec.yaml も対象。無いと決めつけない\n'
        '- 優先候補: pubspec.yaml、lib/**、test/**\n'
        '$flutterRegressionTestRule',
  );

  static final _swiftXcodePrompt = _promptBody(
    roleLine:
        'あなたは Xcode（Swift / SwiftUI / UIKit）開発向けのローカル・コーディングアシスタントです。'
        'xcodebuild・シミュレータは対象外です。',
    listDirExample: 'Sources',
    readFileExample: 'Sources/App/ContentView.swift',
    grepPathExample: 'Sources',
    updateFileExample: 'Sources/App/ContentView.swift',
    pathNotes:
        '- ルートの README.md / Package.swift / Info.plist も対象。無いと決めつけない\n'
        '- 優先候補: Package.swift、Sources/**、App/**、プロジェクト名と同じフォルダ/**/*.swift\n'
        '- 新規ファイルはディレクトリ付き（例: App/ContentView.swift や プロジェクト名/ContentView.swift）。ファイル名だけは不可\n'
        '- ワークスペースのフォルダ名と同じ先頭ディレクトリは残す。落とすとファイル名だけになる\n'
        '- lib/ や test/ や pubspec.yaml は Flutter 用。Swift では使わない',
  );

  static final _reactPrompt = _promptBody(
    roleLine:
        'あなたは React（React / Next.js / Vite 等）開発向けのローカル・コーディングアシスタントです。'
        'npm install・ビルド・開発サーバ起動は対象外です。',
    listDirExample: 'src',
    readFileExample: 'src/App.tsx',
    grepPathExample: 'src',
    updateFileExample: 'src/App.tsx',
    pathNotes:
        '- ルートの README.md / package.json / tsconfig.json も対象。無いと決めつけない\n'
        '- 優先候補: package.json、src/**、app/**、pages/**、components/**、*.tsx／*.jsx\n'
        '- node_modules / .next / dist は除外済みのことが多い',
  );

  static final _androidPrompt = _promptBody(
    roleLine:
        'あなたは Android（Java / Kotlin）開発向けのローカル・コーディングアシスタントです。'
        'Gradle ビルド・エミュレータ起動は対象外です。',
    listDirExample: 'app/src/main',
    readFileExample: 'app/src/main/java/com/example/MainActivity.kt',
    grepPathExample: 'app/src',
    updateFileExample: 'app/src/main/java/com/example/MainActivity.kt',
    pathNotes:
        '- ルートの README.md / settings.gradle(.kts) / build.gradle(.kts) / gradle.properties も対象。無いと決めつけない\n'
        '- 優先候補: AndroidManifest.xml、app/src/**、*.kt／*.java、app/build.gradle(.kts)\n'
        '- .gradle / build / .cxx は除外済みのことが多い',
  );

  static final _pythonPrompt = _promptBody(
    roleLine:
        'あなたは Python 開発向けのローカル・コーディングアシスタントです。'
        'pip install・仮想環境作成・テスト実行は対象外です。',
    listDirExample: 'src',
    readFileExample: 'src/app/main.py',
    grepPathExample: 'src',
    updateFileExample: 'src/app/main.py',
    pathNotes:
        '- ルートの README.md / pyproject.toml / requirements.txt / setup.py も対象。無いと決めつけない\n'
        '- 優先候補: pyproject.toml、requirements.txt、src/**、tests/**、*.py\n'
        '- __pycache__ / .venv は除外済みのことが多い',
  );

  static final _genericPrompt = _promptBody(
    roleLine: 'あなたはローカル・コーディングアシスタントです。',
    listDirExample: '.',
    readFileExample: 'README.md',
    grepPathExample: '.',
    updateFileExample: 'src/example.txt',
    pathNotes:
        '- ルートの README.md も対象。無いと決めつけない\n'
        '- 新規ファイルはディレクトリ付き。ファイル名だけは不可。lib/ を既定にしない',
  );
}

/// ＋メニューがパス例に使う、ワークスペース種別ごとの見本。
final class CodingWorkspacePathSamples {
  const CodingWorkspacePathSamples({
    required this.addFile,
    required this.updateFile,
    required this.layoutHint,
    required this.bareName,
    required this.usesFlutterTests,
  });

  final String addFile;
  final String updateFile;
  final String layoutHint;
  final String bareName;
  final bool usesFlutterTests;
}
