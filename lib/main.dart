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
import 'features/generative_ai/data/local_llm_client.dart';
import 'features/generative_ai/data/local_llm_server_launcher.dart';
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
  // 生成AI ON なら llama-server を起動（失敗してもアプリは継続）
  await _bootstrapLocalLlmServer();
  runApp(const LmCodeApp());
}

Future<void> _bootstrapLocalLlmServer() async {
  try {
    final settings = await getIt<GetConnectionSettings>()();
    final local = settings.localLlm;
    if (!local.enabled || !local.isConfigured) return;
    await getIt<LocalLlmServerLauncher>().applySettings(
      settings: local.forServer(),
      isHealthy: getIt<LocalLlmClient>().isReachable,
      onStatus: (message) {
        debugPrint('[LocalLlm] $message');
      },
      waitForHealth: true,
    );
  } catch (e, st) {
    debugPrint('[LocalLlm] 起動時の llama-server 準備に失敗: $e');
    debugPrint('$st');
  }
}

/// アプリのルートウィジェット。
/// 終了時に自動起動した llama-server を停止する。
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
        await LocalLlmServerLauncher.shutdownOwnedForAppExit();
        return AppExitResponse.exit;
      },
      onDetach: () {
        unawaited(LocalLlmServerLauncher.shutdownOwnedForAppExit());
      },
    );
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    unawaited(LocalLlmServerLauncher.shutdownOwnedForAppExit());
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
