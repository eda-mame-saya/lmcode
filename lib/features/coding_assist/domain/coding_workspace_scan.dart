import 'dart:io';

import 'package:path/path.dart' as p;

import 'coding_workspace_kind.dart';

/// ワークスペース走査（S16）。Flutter / Xcode(Swift) / React / Android / Python 共通除外＋テキスト拡張。
abstract final class CodingWorkspaceScan {
  static const maxListedFiles = 5000;
  static const maxTreeLines = 400;

  static const excludedDirNames = <String>{
    '.git',
    '.dart_tool',
    'build',
    '.idea',
    '.vscode',
    'Pods',
    '.symlinks',
    '.gradle',
    'node_modules',
    '.flutter-plugins-dependencies',
    // Xcode / SPM
    'DerivedData',
    'xcuserdata',
    '.swiftpm',
    // React / JS
    '.next',
    'dist',
    'coverage',
    '.turbo',
    '.cache',
    '.parcel-cache',
    '.vercel',
    // Android / NDK
    '.cxx',
    '.externalNativeBuild',
    'captures',
    // Python
    '__pycache__',
    '.venv',
    'venv',
    '.mypy_cache',
    '.pytest_cache',
    '.ruff_cache',
    '.tox',
    '.eggs',
    'htmlcov',
  };

  /// パス単位の除外（ディレクトリ名だけでは足りない例）。
  static const excludedRelativeDirs = <String>{
    'Carthage/Build',
  };

  static const excludedFileNames = <String>{
    '.flutter-plugins',
    '.flutter-plugins-dependencies',
    '.packages',
  };

  static const textExtensions = <String>{
    'dart',
    'yaml',
    'yml',
    'json',
    'md',
    'markdown',
    'mdx',
    'txt',
    'xml',
    'xhtml',
    'gradle',
    'kts',
    'kt',
    'java',
    'swift',
    'm',
    'h',
    'mm',
    'plist',
    'pbxproj',
    'xcworkspacedata',
    'xcscheme',
    'storyboard',
    'xib',
    'properties',
    'cmake',
    'html',
    'css',
    'js',
    'mjs',
    'cjs',
    'ts',
    'tsx',
    'jsx',
    'scss',
    'sass',
    'less',
    'svg',
    'sh',
    'py',
    'pyi',
    'toml',
    'cfg',
    'ini',
    'gitignore',
    'metadata',
  };

  /// ツリー先頭に寄せるファイル名（ルート／各ディレクトリ内）。
  static const highPriorityFileNames = <String>{
    'pubspec.yaml',
    'analysis_options.yaml',
    'Package.swift',
    'README.md',
    'Info.plist',
    'pyproject.toml',
    'requirements.txt',
    'setup.py',
    'setup.cfg',
    'Pipfile',
    'package.json',
    'package-lock.json',
    'pnpm-lock.yaml',
    'yarn.lock',
    'tsconfig.json',
    'vite.config.ts',
    'vite.config.js',
    'next.config.js',
    'next.config.mjs',
    'next.config.ts',
    'index.html',
    'settings.gradle',
    'settings.gradle.kts',
    'build.gradle',
    'build.gradle.kts',
    'gradle.properties',
    'AndroidManifest.xml',
    'proguard-rules.pro',
  };

  /// ツリー先頭に寄せるディレクトリ名。
  static const highPriorityDirNames = <String>{
    'lib',
    'test',
    'tests',
    'Sources',
    'App',
    'Tests',
    'src',
    'app',
    'pages',
    'components',
    'public',
    'java',
    'kotlin',
    'res',
  };

  static bool isExcludedDirName(String name) {
    final n = name.trim();
    if (n.isEmpty) return true;
    if (n.endsWith('.egg-info')) return true;
    if (n.startsWith('.') && n != '.') {
      // 隠しディレクトリは原則除外（.git 等）。設定ファイルはファイル側で許可。
      return excludedDirNames.contains(n) || n == '.git';
    }
    return excludedDirNames.contains(n);
  }

  /// 相対パス（`/` 区切り）でのディレクトリ除外。
  static bool isExcludedDir(String relativePath) {
    final normalized = relativePath.replaceAll('\\', '/');
    if (normalized.isEmpty) return false;
    final name = p.basename(normalized);
    if (isExcludedDirName(name)) return true;
    if (excludedRelativeDirs.contains(normalized)) return true;
    for (final ex in excludedRelativeDirs) {
      if (normalized.endsWith('/$ex')) return true;
    }
    return false;
  }

  static bool isTextFile(String path) {
    final name = p.basename(path);
    if (excludedFileNames.contains(name)) return false;
    if (name == 'pubspec.yaml' ||
        name == 'analysis_options.yaml' ||
        name == 'Package.swift' ||
        name == 'Info.plist' ||
        name == 'pyproject.toml' ||
        name == 'requirements.txt' ||
        name == 'setup.py' ||
        name == 'setup.cfg' ||
        name == 'Pipfile' ||
        name == 'Pipfile.lock' ||
        name == 'poetry.lock' ||
        name == 'package.json' ||
        name == 'package-lock.json' ||
        name == 'pnpm-lock.yaml' ||
        name == 'yarn.lock' ||
        name == 'tsconfig.json' ||
        name == 'index.html' ||
        name == 'settings.gradle' ||
        name == 'settings.gradle.kts' ||
        name == 'build.gradle' ||
        name == 'build.gradle.kts' ||
        name == 'gradle.properties' ||
        name == 'AndroidManifest.xml' ||
        name == 'proguard-rules.pro' ||
        name.startsWith('vite.config.') ||
        name.startsWith('next.config.') ||
        name.startsWith('tsconfig.')) {
      return true;
    }
    if (name.startsWith('.') && name != '.gitignore') {
      // .env 等は読めるが索引には入れない方針でも可。MVP は .gitignore のみ。
      return name == '.gitignore';
    }
    final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
    // 拡張子なし（Makefile / LICENSE / ユーザー作成ファイル等）も索引に含める
    if (ext.isEmpty) return true;
    return textExtensions.contains(ext);
  }

  static int _fileSortKey(String name) {
    if (highPriorityFileNames.contains(name)) return 0;
    final lower = name.toLowerCase();
    if (lower.endsWith('.dart') ||
        lower.endsWith('.swift') ||
        lower.endsWith('.py') ||
        lower.endsWith('.tsx') ||
        lower.endsWith('.jsx') ||
        lower.endsWith('.ts') ||
        lower.endsWith('.js') ||
        lower.endsWith('.kt') ||
        lower.endsWith('.java')) {
      return 1;
    }
    return 2;
  }

  static int _dirSortKey(String name) {
    if (highPriorityDirNames.contains(name)) return 0;
    return 1;
  }

  static Future<CodingWorkspaceIndex> scan(
    String rootPath, {
    int? listedFileLimit,
    int? treeLineLimit,
  }) async {
    final fileCap = listedFileLimit ?? maxListedFiles;
    final treeCap = treeLineLimit ?? maxTreeLines;
    final root = Directory(rootPath);
    if (!await root.exists()) {
      throw StateError('フォルダが見つかりません: $rootPath');
    }
    final files = <String>[];
    final dirs = <String>[];
    final treeLines = <String>[];
    var truncated = false;

    Future<void> walk(Directory dir, String rel, int depth) async {
      if (files.length >= fileCap) {
        truncated = true;
        return;
      }
      List<FileSystemEntity> kids;
      try {
        kids = await dir.list(followLinks: false).toList();
      } catch (_) {
        return;
      }
      // 先にファイル・後でディレクトリ（深い document/ 等で tree が埋まり
      // ルートの README.md / pubspec.yaml が要約から消えるのを防ぐ）
      final fileKids = <File>[];
      final dirKids = <Directory>[];
      for (final entity in kids) {
        if (entity is File) {
          fileKids.add(entity);
        } else if (entity is Directory) {
          dirKids.add(entity);
        }
      }
      fileKids.sort((a, b) {
        final na = p.basename(a.path);
        final nb = p.basename(b.path);
        final byPri = _fileSortKey(na).compareTo(_fileSortKey(nb));
        if (byPri != 0) return byPri;
        return na.compareTo(nb);
      });
      dirKids.sort((a, b) {
        final na = p.basename(a.path);
        final nb = p.basename(b.path);
        final byPri = _dirSortKey(na).compareTo(_dirSortKey(nb));
        if (byPri != 0) return byPri;
        return na.compareTo(nb);
      });
      for (final entity in fileKids) {
        if (files.length >= fileCap) {
          truncated = true;
          return;
        }
        final name = p.basename(entity.path);
        if (!isTextFile(entity.path)) continue;
        final childRel =
            (rel.isEmpty ? name : p.join(rel, name)).replaceAll('\\', '/');
        files.add(childRel);
        if (treeLines.length < treeCap) {
          treeLines.add('${'  ' * depth}$name');
        }
      }
      for (final entity in dirKids) {
        if (files.length >= fileCap) {
          truncated = true;
          return;
        }
        final name = p.basename(entity.path);
        final childRel =
            (rel.isEmpty ? name : p.join(rel, name)).replaceAll('\\', '/');
        if (isExcludedDir(childRel)) continue;
        dirs.add(childRel);
        if (treeLines.length < treeCap) {
          treeLines.add('${'  ' * depth}$name/');
        }
        await walk(entity, childRel, depth + 1);
      }
    }

    await walk(root, '', 0);
    final label = p.basename(root.path);
    final tree = StringBuffer()
      ..writeln('$label/')
      ..writeAll(treeLines, '\n');
    if (truncated) {
      tree.writeln('\n…（ファイル数上限のため省略）');
    }
    final kind = CodingWorkspaceKindDetect.fromLists(
      relativeFiles: files,
      relativeDirectories: dirs,
    );
    return CodingWorkspaceIndex(
      rootPath: root.path,
      rootLabel: label,
      relativeFiles: files,
      relativeDirectories: dirs,
      treeText: tree.toString(),
      truncated: truncated,
      kind: kind,
    );
  }
}

final class CodingWorkspaceIndex {
  const CodingWorkspaceIndex({
    required this.rootPath,
    required this.rootLabel,
    required this.relativeFiles,
    this.relativeDirectories = const [],
    required this.treeText,
    required this.truncated,
    this.kind = CodingWorkspaceKind.generic,
  });

  final String rootPath;
  final String rootLabel;
  final List<String> relativeFiles;

  /// 空フォルダ表示用。除外済みディレクトリの相対パス一覧。
  final List<String> relativeDirectories;
  final String treeText;
  final bool truncated;

  /// 走査結果から判定したプロファイル。
  final CodingWorkspaceKind kind;
}
