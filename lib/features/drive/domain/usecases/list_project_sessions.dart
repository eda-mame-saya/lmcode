import '../entities/drive_session.dart';
import '../repositories/drive_repository.dart';

class ListProjectSessions {
  const ListProjectSessions(this._repository);

  final DriveRepository _repository;

  Future<List<DriveSession>> call(String projectFolderId) =>
      _repository.listSessions(projectFolderId);
}
