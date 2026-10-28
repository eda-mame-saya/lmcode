import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// ビルド環境ファイル（`.env.*`）の読込結果。
/// 新規追加：欠落時も起動継続し、ホームで通知するための状態
class AppEnv {
  AppEnv._({
    required this.fileName,
    required this.isFileLoaded,
  });

  /// テスト用インスタンス。
  @visibleForTesting
  factory AppEnv.forTest({
    required String fileName,
    required bool isFileLoaded,
  }) {
    return AppEnv._(fileName: fileName, isFileLoaded: isFileLoaded);
  }

  static AppEnv? _instance;

  /// アプリ全体で共有する読込結果。
  static AppEnv get instance {
    final current = _instance;
    if (current == null) {
      throw StateError('AppEnv.load() を先に呼び出してください');
    }
    return current;
  }

  /// テスト用に差し替える。
  @visibleForTesting
  static void debugOverride(AppEnv env) {
    _instance = env;
  }

  /// テスト用にクリアする。
  @visibleForTesting
  static void debugReset() {
    _instance = null;
  }

  /// 読み込もうとした（または読めた）ファイル名。
  final String fileName;

  /// 指定のビルド環境ファイルを asset から読めたか。
  final bool isFileLoaded;

  /// 起動時に1回呼ぶ。対象ファイルが無くても例外は外へ出さない。
  static Future<AppEnv> load() async {
    // アルファ（Mac・ローカルのみ）: .env / dotenv 読込を停止。
    // AmiVoice / Gemini キーは使わない。再有効化時は下のコメントアウトを戻す。
    dotenv.testLoad(fileInput: '');
    final env = AppEnv._(fileName: '（未使用・ローカル運用）', isFileLoaded: true);
    _instance = env;
    return env;

  }

  // static String _read(String key) {
  //   try {
  //     return dotenv.env[key]?.trim() ?? '';
  //   } catch (_) {
  //     return '';
  //   }
  // }
}
