import '../entities/storage_backend.dart';
import '../repositories/drive_repository.dart';

class GetStorageBackend {
  const GetStorageBackend(this._repository);

  final DriveRepository _repository;

  Future<StorageBackend> call() => _repository.getStorageBackend();
}
