import 'dart:convert';
import 'dart:typed_data';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;

import '../../../../core/google_oauth_config.dart';
import '../../domain/drive_session_naming.dart';
import '../../domain/entities/drive_file.dart';
import '../../domain/entities/drive_project.dart';
import '../../domain/entities/drive_session.dart';

/// Google Drive API アクセス。
class DriveRemoteDataSource {
  DriveRemoteDataSource({
    GoogleSignIn? googleSignIn,
  }) : _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  final GoogleSignIn _googleSignIn;
  static const _scopes = [drive.DriveApi.driveScope];
  bool _initialized = false;
  GoogleSignInAccount? _currentUser;

  Future<GoogleSignInAccount> connect() async {
    await _ensureInitialized();
    final silentAttempt = _googleSignIn.attemptLightweightAuthentication();
    final silentlySigned = silentAttempt == null ? null : await silentAttempt;
    if (silentlySigned != null) {
      _currentUser = silentlySigned;
      await _ensureAuthorized(silentlySigned);
      return silentlySigned;
    }
    final account = await _googleSignIn.authenticate(scopeHint: _scopes);
    await _ensureAuthorized(account);
    _currentUser = account;
    return account;
  }

  Future<void> disconnect() async {
    await _ensureInitialized();
    await _googleSignIn.signOut();
    await _googleSignIn.disconnect();
    _currentUser = null;
  }

  Future<GoogleSignInAccount?> getCurrentUser() async {
    await _ensureInitialized();
    if (_currentUser != null) return _currentUser;
    final silentAttempt = _googleSignIn.attemptLightweightAuthentication();
    if (silentAttempt == null) return null;
    _currentUser = await silentAttempt;
    return _currentUser;
  }

  Future<String> getAccessToken() async {
    final user = await getCurrentUser();
    if (user == null) return '';
    final authorization = await _ensureAuthorized(user);
    return authorization.accessToken;
  }

  Future<String> ensureAppRootFolderId({
    required String folderName,
  }) async {
    final api = await _driveApi();
    final query = "name='$folderName' and mimeType='application/vnd.google-apps.folder' and trashed=false and 'me' in owners";
    final found = await api.files.list(
      q: query,
      pageSize: 1,
      $fields: 'files(id,name)',
    );
    if (found.files != null && found.files!.isNotEmpty) {
      return found.files!.first.id!;
    }

    final created = await api.files.create(
      drive.File()
        ..name = folderName
        ..mimeType = 'application/vnd.google-apps.folder',
      $fields: 'id',
    );
    if (created.id == null || created.id!.isEmpty) {
      throw Exception('Drive ルートフォルダの作成に失敗しました。');
    }
    return created.id!;
  }

  Future<List<DriveProject>> listProjects({
    required String appRootFolderId,
  }) async {
    final api = await _driveApi();
    final query =
        "'$appRootFolderId' in parents and mimeType='application/vnd.google-apps.folder' and trashed=false";
    final response = await api.files.list(
      q: query,
      orderBy: 'modifiedTime desc',
      pageSize: 200,
      $fields: 'files(id,name,modifiedTime)',
    );
    return (response.files ?? [])
        .where((file) => file.id != null && file.name != null)
        .map(
          (file) => DriveProject(
            id: file.id!,
            name: file.name!,
            updatedAt: file.modifiedTime,
          ),
        )
        .toList();
  }

  Future<DriveProject> createProject({
    required String appRootFolderId,
    required String name,
  }) async {
    final api = await _driveApi();
    final created = await api.files.create(
      drive.File()
        ..name = name
        ..mimeType = 'application/vnd.google-apps.folder'
        ..parents = [appRootFolderId],
      $fields: 'id,name,modifiedTime',
    );

    final id = created.id;
    final createdName = created.name;
    if (id == null || createdName == null) {
      throw Exception('プロジェクトフォルダの作成に失敗しました。');
    }
    return DriveProject(
      id: id,
      name: createdName,
      updatedAt: created.modifiedTime,
    );
  }

  Future<DriveProject> renameProject({
    required String projectFolderId,
    required String newName,
  }) async {
    final api = await _driveApi();
    final updated = await api.files.update(
      drive.File()..name = newName,
      projectFolderId,
      $fields: 'id,name,modifiedTime',
    );

    final id = updated.id;
    final name = updated.name;
    if (id == null || name == null) {
      throw Exception('プロジェクトフォルダ名の変更に失敗しました。');
    }
    return DriveProject(
      id: id,
      name: name,
      updatedAt: updated.modifiedTime,
    );
  }

  Future<List<DriveSession>> listSessions({
    required String projectFolderId,
  }) async {
    final api = await _driveApi();
    final query =
        "'$projectFolderId' in parents and mimeType='application/vnd.google-apps.folder' and trashed=false and name contains '第' and name contains '回'";
    final response = await api.files.list(
      q: query,
      orderBy: 'name desc',
      pageSize: 200,
      $fields: 'files(id,name,modifiedTime)',
    );

    return (response.files ?? [])
        .where((file) => file.id != null && file.name != null)
        .map(
          (file) {
            final index = DriveSessionNaming.extractIndex(file.name!) ?? 0;
            return DriveSession(
              id: file.id!,
              index: index,
              name: file.name!,
              updatedAt: file.modifiedTime,
            );
          },
        )
        .where((session) => session.index > 0)
        .toList()
      ..sort((a, b) => b.index.compareTo(a.index));
  }

  Future<DriveSession> createSession({
    required String projectFolderId,
    required int sessionIndex,
    String deviceLabel = '',
  }) async {
    final api = await _driveApi();
    final sessionName = DriveSessionNaming.folderName(
      sessionIndex: sessionIndex,
      deviceLabel: deviceLabel,
    );
    final created = await api.files.create(
      drive.File()
        ..name = sessionName
        ..mimeType = 'application/vnd.google-apps.folder'
        ..parents = [projectFolderId],
      $fields: 'id,name,modifiedTime',
    );

    final id = created.id;
    final name = created.name;
    if (id == null || name == null) {
      throw Exception('第N回フォルダの作成に失敗しました。');
    }
    return DriveSession(
      id: id,
      index: sessionIndex,
      name: name,
      updatedAt: created.modifiedTime,
    );
  }

  /// 親フォルダ直下に名前付きサブフォルダを作成。同名があればその ID を返す。
  Future<String> ensureChildFolder({
    required String parentFolderId,
    required String folderName,
  }) async {
    final existingId = await findChildFolderId(
      parentFolderId: parentFolderId,
      folderName: folderName,
    );
    if (existingId != null) return existingId;

    final api = await _driveApi();
    final created = await api.files.create(
      drive.File()
        ..name = folderName
        ..mimeType = 'application/vnd.google-apps.folder'
        ..parents = [parentFolderId],
      $fields: 'id,name',
    );
    final id = created.id;
    if (id == null) {
      throw Exception('フォルダ「$folderName」の作成に失敗しました。');
    }
    return id;
  }

  Future<String?> findChildFolderId({
    required String parentFolderId,
    required String folderName,
  }) async {
    final api = await _driveApi();
    final escaped = _escapeDriveQueryValue(folderName);
    final query =
        "'$parentFolderId' in parents and mimeType='application/vnd.google-apps.folder' and trashed=false and name='$escaped'";
    final existing = await api.files.list(
      q: query,
      pageSize: 1,
      $fields: 'files(id,name)',
    );
    return existing.files?.where((f) => f.id != null).map((f) => f.id!).firstOrNull;
  }

  Future<List<DriveFile>> listFilesInFolder({
    required String folderId,
  }) async {
    final api = await _driveApi();
    final query =
        "'$folderId' in parents and mimeType!='application/vnd.google-apps.folder' and trashed=false";
    final response = await api.files.list(
      q: query,
      orderBy: 'name',
      pageSize: 200,
      $fields: 'files(id,name,mimeType,modifiedTime,parents)',
    );

    return (response.files ?? [])
        .where((file) => file.id != null && file.name != null && file.mimeType != null)
        .map(
          (file) => DriveFile(
            id: file.id!,
            name: file.name!,
            mimeType: file.mimeType!,
            modifiedTime: file.modifiedTime,
            parentFolderId: folderId,
          ),
        )
        .toList();
  }

  Future<DriveFile?> findFileInFolder({
    required String folderId,
    required String fileName,
  }) async {
    final api = await _driveApi();
    final escapedName = _escapeDriveQueryValue(fileName);
    final query =
        "'$folderId' in parents and name='$escapedName' and trashed=false";
    final response = await api.files.list(
      q: query,
      pageSize: 1,
      $fields: 'files(id,name,mimeType,modifiedTime,parents)',
    );
    final file = response.files?.isNotEmpty == true
        ? response.files!.first
        : null;
    if (file?.id == null || file?.name == null || file?.mimeType == null) {
      return null;
    }
    return DriveFile(
      id: file!.id!,
      name: file.name!,
      mimeType: file.mimeType!,
      modifiedTime: file.modifiedTime,
      parentFolderId: folderId,
    );
  }

  Future<String> readFileAsText({
    required String fileId,
    required String mimeType,
  }) async {
    final api = await _driveApi();
    final exportMime = _exportMimeType(mimeType);
    if (exportMime != null) {
      final media = await api.files.export(
        fileId,
        exportMime,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;
      return await _decodeMedia(media);
    }

    if (!_isDirectlyReadable(mimeType)) {
      throw UnsupportedError('この形式はテキスト読込に未対応です: $mimeType');
    }

    final media = await api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    return await _decodeMedia(media);
  }

  Future<DriveFile> saveTextFile({
    required String folderId,
    required String fileName,
    required String content,
  }) async {
    final api = await _driveApi();
    final bytes = utf8.encode(content);
    final media = drive.Media(
      Stream.value(bytes),
      bytes.length,
      contentType: 'text/markdown; charset=utf-8',
    );

    final existing = await findFileInFolder(
      folderId: folderId,
      fileName: fileName,
    );
    if (existing != null) {
      final updated = await api.files.update(
        drive.File()..name = fileName,
        existing.id,
        uploadMedia: media,
        $fields: 'id,name,mimeType,modifiedTime',
      );
      return DriveFile(
        id: updated.id ?? existing.id,
        name: updated.name ?? fileName,
        mimeType: updated.mimeType ?? 'text/markdown',
        modifiedTime: updated.modifiedTime,
        parentFolderId: folderId,
      );
    }

    final created = await api.files.create(
      drive.File()
        ..name = fileName
        ..mimeType = 'text/markdown'
        ..parents = [folderId],
      uploadMedia: media,
      $fields: 'id,name,mimeType,modifiedTime',
    );
    final id = created.id;
    final name = created.name;
    if (id == null || name == null) {
      throw Exception('ファイルの保存に失敗しました。');
    }
    return DriveFile(
      id: id,
      name: name,
      mimeType: created.mimeType ?? 'text/markdown',
      modifiedTime: created.modifiedTime,
      parentFolderId: folderId,
    );
  }

  Future<Uint8List> readFileAsBytes({required String fileId}) async {
    final api = await _driveApi();
    final media = await api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in media.stream) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  Future<DriveFile> saveBinaryFile({
    required String folderId,
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final api = await _driveApi();
    final media = drive.Media(
      Stream.value(bytes),
      bytes.length,
      contentType: mimeType,
    );

    final existing = await findFileInFolder(
      folderId: folderId,
      fileName: fileName,
    );
    if (existing != null) {
      final updated = await api.files.update(
        drive.File()
          ..name = fileName
          ..mimeType = mimeType,
        existing.id,
        uploadMedia: media,
        $fields: 'id,name,mimeType,modifiedTime',
      );
      return DriveFile(
        id: updated.id ?? existing.id,
        name: updated.name ?? fileName,
        mimeType: updated.mimeType ?? mimeType,
        modifiedTime: updated.modifiedTime,
        parentFolderId: folderId,
      );
    }

    final created = await api.files.create(
      drive.File()
        ..name = fileName
        ..mimeType = mimeType
        ..parents = [folderId],
      uploadMedia: media,
      $fields: 'id,name,mimeType,modifiedTime',
    );
    final id = created.id;
    final name = created.name;
    if (id == null || name == null) {
      throw Exception('ファイルの保存に失敗しました。');
    }
    return DriveFile(
      id: id,
      name: name,
      mimeType: created.mimeType ?? mimeType,
      modifiedTime: created.modifiedTime,
      parentFolderId: folderId,
    );
  }

  String? _exportMimeType(String mimeType) {
    return switch (mimeType) {
      'application/vnd.google-apps.document' => 'text/plain',
      'application/vnd.google-apps.spreadsheet' => 'text/csv',
      'application/vnd.google-apps.presentation' => 'text/plain',
      _ => null,
    };
  }

  /// Drive `q` 内の単一引用符リテラル用エスケープ。
  /// `\` を先に、次に `'` をエスケープする（公式 Search files の注意どおり）。
  static String _escapeDriveQueryValue(String value) {
    return value.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
  }

  bool _isDirectlyReadable(String mimeType) {
    return mimeType.startsWith('text/') ||
        mimeType == 'application/json' ||
        mimeType == 'application/markdown';
  }

  Future<String> _decodeMedia(drive.Media media) {
    return media.stream.transform(utf8.decoder).join();
  }

  Future<drive.DriveApi> _driveApi() async {
    final user = await getCurrentUser();
    if (user == null) throw Exception('Google Drive の認証情報がありません。');
    final authorization = await _ensureAuthorized(user);
    final client = authorization.authClient(scopes: _scopes);
    return drive.DriveApi(client);
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await _googleSignIn.initialize(
      clientId: GoogleOAuthConfig.iosMacClientId,
      serverClientId: GoogleOAuthConfig.webClientId,
    );
    _initialized = true;
  }

  Future<GoogleSignInClientAuthorization> _ensureAuthorized(
    GoogleSignInAccount user,
  ) async {
    final existing =
        await user.authorizationClient.authorizationForScopes(_scopes);
    if (existing != null) {
      return existing;
    }
    return user.authorizationClient.authorizeScopes(_scopes);
  }
}
