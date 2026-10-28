import '../entities/connection_settings.dart';
import '../repositories/api_settings_repository.dart';

/// 接続設定の取得。
/// 新規追加：ユースケース
class GetConnectionSettings {
  const GetConnectionSettings(this._repository);

  final ApiSettingsRepository _repository;

  Future<ConnectionSettings> call() => _repository.getSettings();
}
