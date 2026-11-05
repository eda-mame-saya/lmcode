import 'dart:io';

/// コーディングアシスト内蔵ターミナルのシェル起動設定。
abstract final class CodingTerminalShell {
  /// OS 既定シェル。macOS/Linux は `$SHELL`、無ければ zsh／bash。
  static String executable({
    Map<String, String>? environment,
    String Function()? operatingSystem,
  }) {
    final env = environment ?? Platform.environment;
    final os = operatingSystem?.call() ?? Platform.operatingSystem;
    if (os == 'windows') {
      final comspec = env['COMSPEC']?.trim();
      if (comspec != null && comspec.isNotEmpty) return comspec;
      return 'powershell.exe';
    }
    final shell = env['SHELL']?.trim();
    if (shell != null && shell.isNotEmpty) return shell;
    if (os == 'macos' || os == 'ios') return '/bin/zsh';
    return '/bin/bash';
  }

  /// ログインシェル相当（PATH をプロファイルから読む）。Windows は空。
  static List<String> arguments({
    String Function()? operatingSystem,
  }) {
    final os = operatingSystem?.call() ?? Platform.operatingSystem;
    if (os == 'windows') return const [];
    return const ['-l'];
  }

  /// WS 未選択時の初期 cwd。`$HOME`／`USERPROFILE`、無ければ一時ディレクトリ。
  static String defaultWorkingDirectory({
    Map<String, String>? environment,
  }) {
    final env = environment ?? Platform.environment;
    final home = (env['HOME'] ?? env['USERPROFILE'])?.trim();
    if (home != null && home.isNotEmpty) return home;
    return Directory.systemTemp.path;
  }
}
