enum StorageBackend {
  googleDrive,
  local;

  String get label => switch (this) {
        StorageBackend.googleDrive => 'Googleドライブ',
        StorageBackend.local => 'ローカルフォルダ',
      };
}
