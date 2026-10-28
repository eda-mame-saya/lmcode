import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/c.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/gradle.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/ruby.dart';
import 'package:re_highlight/languages/swift.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';

/// 拡張子 → ハイライト言語。
abstract final class CodingSyntax {
  static ({String id, Mode mode})? languageForPath(String relativePath) {
    final name = p.basename(relativePath).toLowerCase();
    final ext = p.extension(relativePath).toLowerCase().replaceFirst('.', '');

    if (name == 'podfile' || name == 'gemfile') {
      return (id: 'ruby', mode: langRuby);
    }

    return switch (ext) {
      'dart' => (id: 'dart', mode: langDart),
      'json' => (id: 'json', mode: langJson),
      'yaml' || 'yml' => (id: 'yaml', mode: langYaml),
      'xml' || 'plist' || 'html' || 'htm' || 'xhtml' || 'svg' =>
        (id: 'xml', mode: langXml),
      'css' || 'scss' => (id: 'css', mode: langCss),
      'js' || 'mjs' || 'cjs' || 'jsx' => (id: 'javascript', mode: langJavascript),
      'ts' || 'tsx' => (id: 'typescript', mode: langTypescript),
      'kt' || 'kts' => (id: 'kotlin', mode: langKotlin),
      'swift' => (id: 'swift', mode: langSwift),
      'java' => (id: 'java', mode: langJava),
      'py' => (id: 'python', mode: langPython),
      'c' || 'h' || 'm' => (id: 'c', mode: langC),
      'cpp' || 'cc' || 'cxx' || 'hpp' || 'hh' || 'mm' =>
        (id: 'cpp', mode: langCpp),
      'md' || 'markdown' || 'mdx' => (id: 'markdown', mode: langMarkdown),
      'sh' || 'bash' || 'zsh' => (id: 'bash', mode: langBash),
      'gradle' => (id: 'gradle', mode: langGradle),
      'rb' => (id: 'ruby', mode: langRuby),
      'storyboard' || 'xib' || 'pbxproj' || 'xcworkspacedata' || 'xcscheme' =>
        (id: 'xml', mode: langXml),
      _ => null,
    };
  }

  static CodeHighlightTheme? themeForPath(String? relativePath, {required bool dark}) {
    if (relativePath == null || relativePath.isEmpty) return null;
    final lang = languageForPath(relativePath);
    if (lang == null) return null;
    return CodeHighlightTheme(
      languages: {
        lang.id: CodeHighlightThemeMode(mode: lang.mode),
      },
      theme: dark ? atomOneDarkTheme : atomOneLightTheme,
    );
  }

  static String labelForPath(String? relativePath) {
    if (relativePath == null) return '';
    final lang = languageForPath(relativePath);
    return lang?.id ?? 'plain';
  }

  /// ⌘/ / Ctrl+/（行コメント）用。拡張子に応じた記号。
  /// ブロックコメントショートカットはオミット（macOS Help 検索と競合）。
  /// 不明拡張子は `null`（コメント操作なし）。
  static CodeCommentFormatter? commentFormatterForPath(String? relativePath) {
    final style = commentStyleForPath(relativePath);
    if (style == null) return null;
    return DefaultCodeCommentFormatter(
      singleLinePrefix: style.singleLinePrefix,
      multiLinePrefix: style.multiLinePrefix,
      multiLineSuffix: style.multiLineSuffix,
    );
  }

  /// テスト／表示用のコメント記号。
  static ({
    String? singleLinePrefix,
    String? multiLinePrefix,
    String? multiLineSuffix,
  })? commentStyleForPath(String? relativePath) {
    if (relativePath == null || relativePath.isEmpty) return null;
    final name = p.basename(relativePath).toLowerCase();
    final ext = p.extension(relativePath).toLowerCase().replaceFirst('.', '');

    if (name == 'podfile' || name == 'gemfile' || name == 'rakefile') {
      return (
        singleLinePrefix: '#',
        multiLinePrefix: '=begin',
        multiLineSuffix: '=end',
      );
    }
    if (name == 'dockerfile' || name == 'makefile' || name == 'cmakelists.txt') {
      return (
        singleLinePrefix: '#',
        multiLinePrefix: null,
        multiLineSuffix: null,
      );
    }

    return switch (ext) {
      // C 系・Dart・JS/TS・JVM・Swift・CSS・Gradle
      'dart' ||
      'js' ||
      'mjs' ||
      'cjs' ||
      'jsx' ||
      'ts' ||
      'tsx' ||
      'java' ||
      'kt' ||
      'kts' ||
      'swift' ||
      'c' ||
      'h' ||
      'm' ||
      'cpp' ||
      'cc' ||
      'cxx' ||
      'hpp' ||
      'hh' ||
      'mm' ||
      'css' ||
      'scss' ||
      'gradle' ||
      'json' ||
      'jsonc' =>
        (
          singleLinePrefix: '//',
          multiLinePrefix: '/*',
          multiLineSuffix: '*/',
        ),
      // シェル・Python・YAML・Ruby
      'py' ||
      'yaml' ||
      'yml' ||
      'sh' ||
      'bash' ||
      'zsh' ||
      'rb' ||
      'toml' ||
      'gitignore' ||
      'env' =>
        (
          singleLinePrefix: '#',
          multiLinePrefix: null,
          multiLineSuffix: null,
        ),
      // XML / HTML / Markdown（行コメントは無し。ブロックのみ）
      'xml' ||
      'plist' ||
      'html' ||
      'htm' ||
      'xhtml' ||
      'svg' ||
      'md' ||
      'markdown' ||
      'mdx' ||
      'storyboard' ||
      'xib' =>
        (
          singleLinePrefix: null,
          multiLinePrefix: '<!--',
          multiLineSuffix: '-->',
        ),
      _ => null,
    };
  }
}
