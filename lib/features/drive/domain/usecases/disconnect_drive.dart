import '../repositories/drive_repository.dart';

class DisconnectDrive {
  const DisconnectDrive(this._repository);

  final DriveRepository _repository;

  Future<void> call() => _repository.disconnect();
}
