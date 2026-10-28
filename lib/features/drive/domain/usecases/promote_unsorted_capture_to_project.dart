import '../entities/drive_project.dart';
import '../repositories/drive_repository.dart';

class PromoteUnsortedCaptureToProject {
  const PromoteUnsortedCaptureToProject(this._repository);

  final DriveRepository _repository;

  Future<DriveProject> call({
    required String captureFolderId,
    required String projectName,
  }) =>
      _repository.promoteUnsortedCaptureToProject(
        captureFolderId: captureFolderId,
        projectName: projectName,
      );
}
