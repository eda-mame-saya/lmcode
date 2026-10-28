import '../entities/drive_project.dart';
import '../repositories/drive_repository.dart';

class HideDriveProject {
  const HideDriveProject(this._repository);

  final DriveRepository _repository;

  Future<DriveProject> call(String projectFolderId) =>
      _repository.hideProject(projectFolderId);
}
