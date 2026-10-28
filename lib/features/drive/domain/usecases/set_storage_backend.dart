import '../entities/drive_connection_state.dart';
import '../entities/storage_backend.dart';
import '../repositories/drive_repository.dart';

class SetStorageBackend {
  const SetStorageBackend(this._repository);

  final DriveRepository _repository;

  Future<DriveConnectionState> call(StorageBackend backend) =>
      _repository.setStorageBackend(backend);
}
