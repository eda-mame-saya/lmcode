import 'package:equatable/equatable.dart';
import 'storage_backend.dart';

/// Google Drive 連携状態。
final class DriveConnectionState extends Equatable {
  const DriveConnectionState({
    required this.isConnected,
    required this.userId,
    required this.appRootFolderId,
    this.storageBackend = StorageBackend.googleDrive,
    this.localBasePath = '',
  });

  const DriveConnectionState.disconnected()
      : isConnected = false,
        userId = '',
        appRootFolderId = '',
        storageBackend = StorageBackend.googleDrive,
        localBasePath = '';

  final bool isConnected;
  final String userId;
  final String appRootFolderId;
  final StorageBackend storageBackend;
  final String localBasePath;

  @override
  List<Object?> get props => [
        isConnected,
        userId,
        appRootFolderId,
        storageBackend,
        localBasePath,
      ];
}
