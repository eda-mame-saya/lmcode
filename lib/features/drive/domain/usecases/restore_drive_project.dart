import '../entities/drive_project.dart';
import '../repositories/drive_repository.dart';

class RestoreDriveProject {
  const RestoreDriveProject(this._repository);

  final DriveRepository _repository;

  Future<DriveProject> call(String projectFolderId) =>
      _repository.restoreProject(projectFolderId);
}
