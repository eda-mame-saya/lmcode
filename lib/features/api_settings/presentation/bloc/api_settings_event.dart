import 'package:equatable/equatable.dart';

import '../../domain/entities/custom_llm_model.dart';
import '../../domain/entities/generative_ai_provider.dart';

/// 接続・API設定画面のイベント。
sealed class ApiSettingsEvent extends Equatable {
  const ApiSettingsEvent();

  @override
  List<Object?> get props => [];
}

final class ApiSettingsStarted extends ApiSettingsEvent {
  const ApiSettingsStarted();
}

final class ApiSettingsIntervalChanged extends ApiSettingsEvent {
  const ApiSettingsIntervalChanged(this.value);
  final String value;

  @override
  List<Object?> get props => [value];
}

final class ApiSettingsProviderChanged extends ApiSettingsEvent {
  const ApiSettingsProviderChanged(this.provider);
  final GenerativeAiProvider provider;

  @override
  List<Object?> get props => [provider];
}

final class ApiSettingsLocalLlmEnabledChanged extends ApiSettingsEvent {
  const ApiSettingsLocalLlmEnabledChanged(this.value);
  final bool value;

  @override
  List<Object?> get props => [value];
}

final class ApiSettingsLocalLlmHostChanged extends ApiSettingsEvent {
  const ApiSettingsLocalLlmHostChanged(this.value);
  final String value;

  @override
  List<Object?> get props => [value];
}

final class ApiSettingsLocalLlmPortChanged extends ApiSettingsEvent {
  const ApiSettingsLocalLlmPortChanged(this.value);
  final String value;

  @override
  List<Object?> get props => [value];
}

final class ApiSettingsLocalLlmCodingCustomModelChanged extends ApiSettingsEvent {
  const ApiSettingsLocalLlmCodingCustomModelChanged(this.model);
  final CustomLlmModel model;

  @override
  List<Object?> get props => [model.id, model.ggufFileName];
}

final class ApiSettingsLocalLlmCodingContextChanged extends ApiSettingsEvent {
  const ApiSettingsLocalLlmCodingContextChanged(this.value);
  final int value;

  @override
  List<Object?> get props => [value];
}

final class ApiSettingsDartSdkPathChanged extends ApiSettingsEvent {
  const ApiSettingsDartSdkPathChanged(this.value);
  final String value;

  @override
  List<Object?> get props => [value];
}

final class ApiSettingsSaveRequested extends ApiSettingsEvent {
  const ApiSettingsSaveRequested();
}

final class ApiSettingsConnectionTestRequested extends ApiSettingsEvent {
  const ApiSettingsConnectionTestRequested();
}

final class ApiSettingsSaveMessageConsumed extends ApiSettingsEvent {
  const ApiSettingsSaveMessageConsumed();
}
