import 'package:equatable/equatable.dart';

/// Drive 上のファイル（フォルダ以外）。
final class DriveFile extends Equatable {
  const DriveFile({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.modifiedTime,
    required this.parentFolderId,
  });

  final String id;
  final String name;
  final String mimeType;
  final DateTime? modifiedTime;
  final String parentFolderId;

  @override
  List<Object?> get props => [id, name, mimeType, modifiedTime, parentFolderId];
}
