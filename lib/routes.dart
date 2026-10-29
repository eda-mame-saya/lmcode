import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'features/api_settings/presentation/pages/add_llm_model_page.dart';
import 'features/api_settings/presentation/pages/api_settings_page.dart';
import 'features/coding_assist/domain/coding_assist_availability.dart';
import 'features/coding_assist/presentation/pages/coding_assist_page.dart';

/// ルートパス定数。
abstract final class AppRoutes {
  static const apiKeys = '/settings/api-keys';
  static const addLlmModel = '/settings/add-llm-model';
  static const codingAssist = '/coding-assist';
}

/// 画面遷移アニメーションなしのページ。
NoTransitionPage<void> _noAnim(GoRouterState state, Widget child) {
  return NoTransitionPage<void>(
    key: state.pageKey,
    child: child,
  );
}

/// アプリのルーティング定義（S16 起動・S11／S11a のみ）。
GoRouter createAppRouter() {
  return GoRouter(
    initialLocation: AppRoutes.codingAssist,
    routes: [
      GoRoute(
        path: '/',
        redirect: (context, state) => AppRoutes.codingAssist,
      ),
      GoRoute(
        path: AppRoutes.codingAssist,
        redirect: (context, state) {
          // Web 等で非提供のときのみ設定へ。
          if (!CodingAssistAvailability.isUiEnabled) {
            return AppRoutes.apiKeys;
          }
          return null;
        },
        pageBuilder: (context, state) =>
            _noAnim(state, const CodingAssistPage()),
      ),
      GoRoute(
        path: AppRoutes.apiKeys,
        pageBuilder: (context, state) =>
            _noAnim(state, const ApiSettingsPage()),
      ),
      GoRoute(
        path: AppRoutes.addLlmModel,
        pageBuilder: (context, state) =>
            _noAnim(state, const AddLlmModelPage()),
      ),
    ],
  );
}
