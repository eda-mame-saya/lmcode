import '../entities/drive_connection_state.dart';
import '../repositories/drive_repository.dart';

class ConnectDrive {
  const ConnectDrive(this._repository);

  final DriveRepository _repository;

  Future<DriveConnectionState> call() => _repository.connect();
}
