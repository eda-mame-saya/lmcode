import '../entities/drive_session.dart';
import '../repositories/drive_repository.dart';

class AssignUnsortedCaptureToProject {
  const AssignUnsortedCaptureToProject(this._repository);

  final DriveRepository _repository;

  Future<DriveSession> call({
    required String captureFolderId,
    required String projectFolderId,
  }) =>
      _repository.assignUnsortedCaptureToProject(
        captureFolderId: captureFolderId,
        projectFolderId: projectFolderId,
      );
}
