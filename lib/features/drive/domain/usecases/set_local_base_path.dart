import '../entities/drive_connection_state.dart';
import '../repositories/drive_repository.dart';

class SetLocalBasePath {
  const SetLocalBasePath(this._repository);

  final DriveRepository _repository;

  Future<DriveConnectionState> call(String basePath) =>
      _repository.setLocalBasePath(basePath);
}
