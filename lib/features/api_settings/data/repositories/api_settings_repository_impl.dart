import '../../domain/entities/connection_settings.dart';
import '../../domain/repositories/api_settings_repository.dart';
import '../datasources/api_settings_local_datasource.dart';

/// 接続設定リポジトリ実装。
/// 新規追加：ローカル永続化への橋渡し
class ApiSettingsRepositoryImpl implements ApiSettingsRepository {
  ApiSettingsRepositoryImpl({
    required ApiSettingsLocalDataSource localDataSource,
  }) : _localDataSource = localDataSource;

  final ApiSettingsLocalDataSource _localDataSource;

  @override
  Future<ConnectionSettings> getSettings() => _localDataSource.load();

  @override
  Future<void> saveSettings(ConnectionSettings settings) =>
      _localDataSource.save(settings);

  // @override
  // Future<bool> isFullyConfigured() async {
  //   final settings = await _localDataSource.load();
  //   return settings.isFullyConfigured;
  // }
}
