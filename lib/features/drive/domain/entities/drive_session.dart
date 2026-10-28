import 'package:equatable/equatable.dart';

/// プロジェクト配下の第N回フォルダ。
final class DriveSession extends Equatable {
  const DriveSession({
    required this.id,
    required this.index,
    required this.name,
    required this.updatedAt,
  });

  final String id;
  final int index;
  final String name;
  final DateTime? updatedAt;

  @override
  List<Object?> get props => [id, index, name, updatedAt];
}
