import 'package:equatable/equatable.dart';

import '../drive_unsorted_folders.dart';

/// `LMCode/未整理フォルダ/` 配下の退避フォルダ1件。
final class DriveUnsortedCapture extends Equatable {
  const DriveUnsortedCapture({
    required this.id,
    required this.name,
    this.updatedAt,
  });

  /// ローカルでは絶対パス。
  final String id;
  final String name;
  final DateTime? updatedAt;

  /// UI 表示用（タイムスタンプ形式なら読みやすい日時）。
  String get displayLabel {
    final match = DriveUnsortedFolders.captureFolderPattern.firstMatch(name);
    if (match == null) return name;
    final y = match.group(1);
    final mo = match.group(2);
    final d = match.group(3);
    final h = match.group(4);
    final mi = match.group(5);
    final s = match.group(6);
    return '$y/$mo/$d $h:$mi:$s';
  }

  @override
  List<Object?> get props => [id, name, updatedAt];
}
