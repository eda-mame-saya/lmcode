import '../entities/drive_project.dart';
import '../repositories/drive_repository.dart';

class CreateDriveProject {
  const CreateDriveProject(this._repository);

  final DriveRepository _repository;

  Future<DriveProject> call(String name) => _repository.createProject(name);
}
