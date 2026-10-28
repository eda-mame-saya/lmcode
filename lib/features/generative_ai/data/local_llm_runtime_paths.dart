import 'dart:io';

import 'package:path/path.dart' as p;

import '../../drive/domain/drive_system_folders.dart';

/// ローカル LLM（llama-server／GGUF）の配置規約。
abstract final class LocalLlmRuntimePaths {
  /// LMCode 直下の展開フォルダ名。
  static const installedFolderName = DriveSystemFolders.localLlm;

  /// 開発用 PoC モデル置き場。
  static const pocModelsDirectory = 'document/llama_cpp調査/poc/models';

  static String get binaryFileName =>
      Platform.isWindows ? 'llama-server.exe' : 'llama-server';

  static String modelsDirUnder(String localLlmDir) =>
      p.join(localLlmDir, 'models');

  static String binaryPathUnder(String localLlmDir) =>
      p.join(localLlmDir, binaryFileName);

  /// `~/Documents/LMCode/local_llm` 候補
  static Future<String?> resolveInstalledRoot() async {
    final home = (Platform.environment['HOME'] ??
            Platform.environment['USERPROFILE'])
        ?.trim();
    if (home == null || home.isEmpty) return null;
    final preferred = Directory(
      p.join(home, 'Documents', 'LMCode', installedFolderName),
    );
    if (await preferred.exists()) return preferred.path;
    // 未作成でも既定パス（LMCode）として返す（models 作成用）
    return preferred.path;
  }
}
