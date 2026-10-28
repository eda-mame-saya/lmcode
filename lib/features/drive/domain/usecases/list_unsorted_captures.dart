import '../entities/drive_unsorted_capture.dart';
import '../repositories/drive_repository.dart';

class ListUnsortedCaptures {
  const ListUnsortedCaptures(this._repository);

  final DriveRepository _repository;

  Future<List<DriveUnsortedCapture>> call() =>
      _repository.listUnsortedCaptures();
}
