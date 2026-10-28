import 'package:equatable/equatable.dart';

import '../drive_project_naming.dart';

/// Drive 上のプロジェクトフォルダ。
final class DriveProject extends Equatable {
  const DriveProject({
    required this.id,
    required this.name,
    required this.updatedAt,
  });

  final String id;
  /// Drive 上のフォルダ名（非表示時は `非表示_` 接頭辞付き）。
  final String name;
  final DateTime? updatedAt;

  bool get isHidden => DriveProjectNaming.isHidden(name);

  /// UI 表示用名称。
  String get displayName => DriveProjectNaming.displayName(name);

  @override
  List<Object?> get props => [id, name, updatedAt];
}
