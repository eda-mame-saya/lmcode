import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/theme/app_theme_controller.dart';
import 'features/api_settings/data/datasources/api_settings_local_datasource.dart';
import 'features/api_settings/data/datasources/custom_llm_models_local_datasource.dart';
import 'features/api_settings/data/repositories/api_settings_repository_impl.dart';
import 'features/api_settings/domain/repositories/api_settings_repository.dart';
import 'features/api_settings/domain/usecases/get_connection_settings.dart';
import 'features/api_settings/domain/usecases/save_connection_settings.dart';
import 'features/api_settings/presentation/bloc/api_settings_bloc.dart';
import 'features/drive/data/datasources/drive_local_datasource.dart';
import 'features/drive/data/datasources/drive_remote_datasource.dart';
import 'features/drive/data/datasources/local_workspace_datasource.dart';
import 'features/drive/data/repositories/drive_repository_impl.dart';
import 'features/drive/domain/repositories/drive_repository.dart';
import 'features/generative_ai/data/ai_debug_log_store.dart';
import 'features/generative_ai/data/local_llm_client.dart';
import 'features/generative_ai/data/local_llm_server_launcher.dart';
import 'features/coding_assist/data/datasources/coding_assist_local_datasource.dart';
import 'features/coding_assist/data/datasources/coding_ui_settings_local_datasource.dart';
import 'features/coding_assist/data/repositories/coding_assist_repository_impl.dart';
import 'features/coding_assist/domain/repositories/coding_assist_repository.dart';
import 'features/coding_assist/presentation/bloc/coding_assist_bloc.dart';

/// グローバル DI コンテナ。
final getIt = GetIt.instance;

/// DI 登録。アプリ起動時に1回呼び出す。
Future<void> configureDependencies() async {
  final prefs = await SharedPreferences.getInstance();
  getIt.registerSingleton<SharedPreferences>(prefs);
  getIt.registerSingleton<AppThemeController>(
    AppThemeController(preferences: prefs),
  );

  const secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    mOptions: MacOsOptions(
      useDataProtectionKeyChain: false,
    ),
  );
  getIt.registerSingleton<FlutterSecureStorage>(secureStorage);

  getIt.registerLazySingleton(
    () => CustomLlmModelsLocalDataSource(preferences: getIt()),
  );
  getIt.registerLazySingleton<ApiSettingsLocalDataSource>(
    () => ApiSettingsLocalDataSource(
      preferences: getIt(),
    ),
  );
  getIt.registerLazySingleton<ApiSettingsRepository>(
    () => ApiSettingsRepositoryImpl(localDataSource: getIt()),
  );

  getIt.registerLazySingleton<DriveLocalDataSource>(
    () => DriveLocalDataSource(
      secureStorage: getIt(),
      preferences: getIt(),
    ),
  );
  getIt.registerLazySingleton(DriveRemoteDataSource.new);
  getIt.registerLazySingleton(LocalWorkspaceDataSource.new);
  getIt.registerLazySingleton<DriveRepository>(
    () => DriveRepositoryImpl(
      localDataSource: getIt(),
      localWorkspaceDataSource: getIt(),
      remoteDataSource: getIt(),
    ),
  );

  getIt.registerLazySingleton(() => GetConnectionSettings(getIt()));
  getIt.registerLazySingleton(() => SaveConnectionSettings(getIt()));

  getIt.registerLazySingleton(AiDebugLogStore.new);
  getIt.registerLazySingleton(
    () => LocalLlmClient(debugLog: getIt()),
  );
  getIt.registerLazySingleton(LocalLlmServerLauncher.new);

  getIt.registerFactory(
    () => ApiSettingsBloc(
      getConnectionSettings: getIt(),
      saveConnectionSettings: getIt(),
      localLlmClient: getIt(),
      localLlmServerLauncher: getIt(),
    ),
  );

  getIt.registerLazySingleton(CodingAssistLocalDataSource.new);
  getIt.registerLazySingleton(
    () => CodingUiSettingsLocalDataSource(preferences: getIt()),
  );
  getIt.registerLazySingleton<CodingAssistRepository>(
    () => CodingAssistRepositoryImpl(localDataSource: getIt()),
  );
  getIt.registerFactory(
    () => CodingAssistBloc(
      repository: getIt(),
      getConnectionSettings: getIt(),
      saveConnectionSettings: getIt(),
      localLlmClient: getIt(),
      localLlmServerLauncher: getIt(),
      uiSettingsLocalDataSource: getIt(),
    ),
  );
}
