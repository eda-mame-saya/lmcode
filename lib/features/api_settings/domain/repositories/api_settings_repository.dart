import '../entities/connection_settings.dart';

/// 接続設定リポジトリ（抽象）。
/// 新規追加：ドメイン層の依存逆転用インターフェース
abstract class ApiSettingsRepository {
  Future<ConnectionSettings> getSettings();

  Future<void> saveSettings(ConnectionSettings settings);

  // Future<bool> isFullyConfigured();
}
