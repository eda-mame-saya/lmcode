import 'package:flutter/foundation.dart';

/// ローカル保存の端末別方針（検討10 §3.2 / §5.1.3）。
class LocalStoragePolicy {
  const LocalStoragePolicy._();

  /// iOS / Android はアプリ Documents 固定。デスクトップはユーザーがベースフォルダを指定。
  static bool get usesFixedAppDocumentsBase {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
  }
}
