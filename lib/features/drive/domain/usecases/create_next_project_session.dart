import '../entities/drive_session.dart';
import '../repositories/drive_repository.dart';

class CreateNextProjectSession {
  const CreateNextProjectSession(this._repository);

  final DriveRepository _repository;

  Future<DriveSession> call(String projectFolderId) =>
      _repository.createNextSession(projectFolderId);
}
