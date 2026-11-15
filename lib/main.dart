import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/env/app_env.dart';
import 'core/theme/app_theme_controller.dart';
import 'features/api_settings/domain/usecases/get_connection_settings.dart';
import 'features/generative_ai/data/coding_llm_sidecar_coordinator.dart';
import 'features/generative_ai/data/local_llm_server_launcher.dart';
import 'features/generative_ai/data/strata_server_launcher.dart';
import 'features/oss_licenses/data/oss_license_registry.dart';
import 'injection.dart';
import 'routes.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // アプリ本体（Apache-2.0）＋サイドカー等を LicensePage に載せる
  await registerOssLicenses();
  // macOS: App Sandbox OFF のアルファ配布では file_picker の entitlement
  // 検査が他マシンで失敗しピッカーが開かないため、検査をスキップする。
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
    await FilePicker.skipEntitlementsChecks();
  }
  // アルファ: .env は読まない（AppEnv.load 内で空初期化のみ）
  await AppEnv.load();
  await configureDependencies();
  // Agent バックエンドに応じて llama／Strata の片方だけ起動
  await _bootstrapCodingLlmSidecars();
  runApp(const LmCodeApp());
}

Future<void> _bootstrapCodingLlmSidecars() async {
  try {
    final settings = await getIt<GetConnectionSettings>()();
    final result = await getIt<CodingLlmSidecarCoordinator>().apply(
      settings: settings,
      onStatus: (message) {
        debugPrint('[CodingLlm] $message');
      },
      waitForHealth: true,
    );
    if (result.error != null) {
      debugPrint('[CodingLlm] 起動時の準備に問題: ${result.error}');
    }
  } catch (e, st) {
    debugPrint('[CodingLlm] 起動時のサイドカー準備に失敗: $e');
    debugPrint('$st');
  }
}

Future<void> _shutdownSidecarsForAppExit() async {
  await LocalLlmServerLauncher.shutdownOwnedForAppExit();
  await StrataServerLauncher.shutdownOwnedForAppExit();
}

/// アプリのルートウィジェット。
/// 終了時に自動起動した llama-server／Strata を停止する。
class LmCodeApp extends StatefulWidget {
  const LmCodeApp({super.key});

  @override
  State<LmCodeApp> createState() => _LmCodeAppState();
}

class _LmCodeAppState extends State<LmCodeApp> {
  late final GoRouter _router = createAppRouter();
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onExitRequested: () async {
        await _shutdownSidecarsForAppExit();
        return AppExitResponse.exit;
      },
      onDetach: () {
        unawaited(_shutdownSidecarsForAppExit());
      },
    );
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    unawaited(_shutdownSidecarsForAppExit());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeController = getIt<AppThemeController>();
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) {
        return MaterialApp.router(
          title: 'lmcode',
          theme: buildAppLightTheme(colors: themeController.lightColors),
          darkTheme: buildAppDarkTheme(colors: themeController.darkColors),
          themeMode: themeController.themeMode,
          routerConfig: _router,
        );
      },
    );
  }
}
