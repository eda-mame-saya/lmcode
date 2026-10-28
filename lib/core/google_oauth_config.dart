/// Google OAuth クライアント ID（公開識別子）。
/// Google Cloud Console の OAuth 2.0 クライアントから取得。
abstract final class GoogleOAuthConfig {
  /// iOS / macOS 用クライアント ID
  static const iosMacClientId =
      '97261711675-8uc2jb1bpu92md4bn8eh7gligs0kbaj4.apps.googleusercontent.com';

  /// Android 用クライアント ID（Console 登録値。Dart では serverClientId を使用）
  static const androidClientId =
      '97261711675-7ljj1m4fd40p8e0s1sknk5731a9ferpm.apps.googleusercontent.com';

  /// Web 用クライアント ID（Android の serverClientId 兼用）
  static const webClientId =
      '97261711675-a3ij0cd3fl6g3n349su0tbrp0lh6ivil.apps.googleusercontent.com';

  /// iOS / macOS の URL スキーム（REVERSED_CLIENT_ID）
  static const iosMacReversedClientId =
      'com.googleusercontent.apps.97261711675-8uc2jb1bpu92md4bn8eh7gligs0kbaj4';
}
