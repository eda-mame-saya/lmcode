import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Google Drive 連携情報のローカル保持。
class DriveLocalDataSource {
  DriveLocalDataSource({
    required FlutterSecureStorage secureStorage,
    required SharedPreferences preferences,
  })  : _secureStorage = secureStorage,
        _preferences = preferences;

  final FlutterSecureStorage _secureStorage;
  final SharedPreferences _preferences;

  static const _prefDriveUserId = 'drive_user_id';
  static const _prefDriveAppRootFolderId = 'drive_app_root_folder_id';
  static const _prefStorageBackend = 'storage_backend';
  static const _prefLocalBasePath = 'local_base_path';
  static const _prefDeviceLabel = 'device_label';
  static const _keyDriveAccessToken = 'drive_access_token';

  Future<String> readUserId() async => _preferences.getString(_prefDriveUserId) ?? '';

  Future<String> readAppRootFolderId() async =>
      _preferences.getString(_prefDriveAppRootFolderId) ?? '';

  Future<String> readAccessToken() async {
    try {
      return await _secureStorage
              .read(key: _keyDriveAccessToken)
              .timeout(const Duration(seconds: 10)) ??
          '';
    } catch (_) {
      return '';
    }
  }

  Future<void> saveUserId(String value) async {
    await _preferences.setString(_prefDriveUserId, value);
  }

  Future<void> saveAppRootFolderId(String value) async {
    await _preferences.setString(_prefDriveAppRootFolderId, value);
  }

  Future<void> saveAccessToken(String value) async {
    await _secureStorage
        .write(key: _keyDriveAccessToken, value: value)
        .timeout(const Duration(seconds: 10));
  }

  Future<String> readStorageBackend() async =>
      _preferences.getString(_prefStorageBackend) ?? 'googleDrive';

  Future<void> saveStorageBackend(String value) async {
    await _preferences.setString(_prefStorageBackend, value);
  }

  Future<String> readLocalBasePath() async =>
      _preferences.getString(_prefLocalBasePath) ?? '';

  Future<void> saveLocalBasePath(String value) async {
    await _preferences.setString(_prefLocalBasePath, value);
  }

  /// 端末ラベル（第N回フォルダのサフィックス用）。
  Future<String> readDeviceLabel() async =>
      _preferences.getString(_prefDeviceLabel) ?? '';

  Future<void> saveDeviceLabel(String value) async {
    await _preferences.setString(_prefDeviceLabel, value.trim());
  }

  Future<void> clearAll() async {
    await _preferences.remove(_prefDriveUserId);
    await _preferences.remove(_prefDriveAppRootFolderId);
    await _secureStorage
        .delete(key: _keyDriveAccessToken)
        .timeout(const Duration(seconds: 10));
  }
}
