import '../entities/connection_settings.dart';
import '../repositories/api_settings_repository.dart';

/// 接続設定の保存。
/// 新規追加：ユースケース
class SaveConnectionSettings {
  const SaveConnectionSettings(this._repository);

  final ApiSettingsRepository _repository;

  Future<void> call(ConnectionSettings settings) =>
      _repository.saveSettings(settings);
}
