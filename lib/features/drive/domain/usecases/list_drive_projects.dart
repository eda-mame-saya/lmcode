import '../entities/drive_project.dart';
import '../repositories/drive_repository.dart';

class ListDriveProjects {
  const ListDriveProjects(this._repository);

  final DriveRepository _repository;

  Future<List<DriveProject>> call({bool includeHidden = false}) =>
      _repository.listProjects(includeHidden: includeHidden);
}
