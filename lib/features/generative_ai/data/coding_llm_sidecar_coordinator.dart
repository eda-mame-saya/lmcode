import '../../api_settings/domain/entities/coding_llm_backend.dart';
import '../../api_settings/domain/entities/connection_settings.dart';
import '../../api_settings/domain/entities/local_llm_connection_settings.dart';
import '../../api_settings/domain/entities/strata_connection_settings.dart';
import 'local_llm_client.dart';
import 'local_llm_server_launcher.dart';
import 'strata_server_launcher.dart';

/// Agent バックエンドに応じて llama／Strata の片方だけ起動し、もう一方を停止する。
class CodingLlmSidecarCoordinator {
  CodingLlmSidecarCoordinator({
    required LocalLlmClient localLlmClient,
    required LocalLlmServerLauncher localLlmServerLauncher,
    required StrataServerLauncher strataServerLauncher,
  })  : _localLlmClient = localLlmClient,
        _localLlmServerLauncher = localLlmServerLauncher,
        _strataServerLauncher = strataServerLauncher;

  final LocalLlmClient _localLlmClient;
  final LocalLlmServerLauncher _localLlmServerLauncher;
  final StrataServerLauncher _strataServerLauncher;

  /// 選択中バックエンドだけ起動。戻り値は UI 向けのメモ。
  Future<CodingLlmSidecarApplyResult> apply({
    required ConnectionSettings settings,
    LocalLlmConnectionSettings? previousLocalLlm,
    StrataConnectionSettings? previousStrata,
    void Function(String message)? onStatus,
    bool waitForHealth = true,
  }) async {
    switch (settings.codingBackend) {
      case CodingLlmBackend.strata:
        return _applyStrata(
          settings: settings,
          previousLocalLlm: previousLocalLlm,
          previousStrata: previousStrata,
          onStatus: onStatus,
          waitForHealth: waitForHealth,
        );
      case CodingLlmBackend.llamaCpp:
        return _applyLlama(
          settings: settings,
          previousLocalLlm: previousLocalLlm,
          previousStrata: previousStrata,
          onStatus: onStatus,
          waitForHealth: waitForHealth,
        );
    }
  }

  Future<CodingLlmSidecarApplyResult> _applyStrata({
    required ConnectionSettings settings,
    LocalLlmConnectionSettings? previousLocalLlm,
    StrataConnectionSettings? previousStrata,
    void Function(String message)? onStatus,
    required bool waitForHealth,
  }) async {
    String? error;
    // Agent が Strata のときは llama を必ず止めてメモリを返す
    onStatus?.call('llama-server を停止しています…');
    try {
      await _localLlmServerLauncher.applySettings(
        settings: settings.localLlm.copyWith(enabled: false),
        previous: previousLocalLlm?.forServer(),
        isHealthy: _localLlmClient.isReachable,
        onStatus: onStatus,
        waitForHealth: false,
      );
    } catch (e) {
      error = 'llama-server の停止に失敗: $e';
    }

    final strata = settings.strata.copyWith(enabled: true);
    try {
      await _strataServerLauncher.applySettings(
        settings: strata,
        previous: previousStrata,
        isHealthy: (s) => _localLlmClient.isReachable(
          s.toChatClientSettings(
            contextSize: _strataServerLauncher.resolvedMaxContext,
          ),
        ),
        onStatus: onStatus,
        waitForHealth: waitForHealth,
      );
      return CodingLlmSidecarApplyResult(
        strataContextSize: _strataServerLauncher.resolvedMaxContext,
        strataReady: true,
        error: error,
      );
    } catch (e) {
      int? ctx;
      try {
        ctx = await _strataServerLauncher.resolveMaxContextForSettings(strata);
      } catch (_) {}
      return CodingLlmSidecarApplyResult(
        strataContextSize: ctx,
        strataReady: false,
        error: error == null ? 'Strata の起動に失敗: $e' : '$error / Strata: $e',
      );
    }
  }

  Future<CodingLlmSidecarApplyResult> _applyLlama({
    required ConnectionSettings settings,
    LocalLlmConnectionSettings? previousLocalLlm,
    StrataConnectionSettings? previousStrata,
    void Function(String message)? onStatus,
    required bool waitForHealth,
  }) async {
    String? error;
    onStatus?.call('Strata を停止しています…');
    try {
      await _strataServerLauncher.applySettings(
        settings: settings.strata.copyWith(enabled: false),
        previous: previousStrata,
        isHealthy: (s) => _localLlmClient.isReachable(
          s.toChatClientSettings(),
        ),
        onStatus: onStatus,
        waitForHealth: false,
      );
    } catch (e) {
      error = 'Strata の停止に失敗: $e';
    }

    if (!settings.localLlm.enabled) {
      try {
        await _localLlmServerLauncher.applySettings(
          settings: settings.localLlm,
          previous: previousLocalLlm?.forServer(),
          isHealthy: _localLlmClient.isReachable,
          onStatus: onStatus,
          waitForHealth: false,
        );
      } catch (e) {
        error = error == null ? 'llama-server の停止に失敗: $e' : '$error / $e';
      }
      return CodingLlmSidecarApplyResult(
        llamaDraft: null,
        llamaReady: false,
        error: error,
      );
    }

    try {
      final draft = await _localLlmServerLauncher.applySettings(
        settings: settings.localLlm.forServer(),
        previous: previousLocalLlm?.forServer(),
        isHealthy: _localLlmClient.isReachable,
        onStatus: onStatus,
        waitForHealth: waitForHealth,
      );
      return CodingLlmSidecarApplyResult(
        llamaDraft: draft,
        llamaReady: true,
        error: error,
      );
    } catch (e) {
      return CodingLlmSidecarApplyResult(
        llamaDraft: null,
        llamaReady: false,
        error: error == null ? 'llama-server の起動に失敗: $e' : '$error / llama: $e',
      );
    }
  }
}

final class CodingLlmSidecarApplyResult {
  const CodingLlmSidecarApplyResult({
    this.llamaDraft,
    this.llamaReady = false,
    this.strataContextSize,
    this.strataReady = false,
    this.error,
  });

  final String? llamaDraft;
  final bool llamaReady;
  final int? strataContextSize;
  final bool strataReady;
  final String? error;
}
