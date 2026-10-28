import '../entities/drive_project.dart';
import '../repositories/drive_repository.dart';

class RenameDriveProject {
  const RenameDriveProject(this._repository);

  final DriveRepository _repository;

  Future<DriveProject> call({
    required String projectFolderId,
    required String newDisplayName,
  }) =>
      _repository.renameProject(projectFolderId, newDisplayName);
}
