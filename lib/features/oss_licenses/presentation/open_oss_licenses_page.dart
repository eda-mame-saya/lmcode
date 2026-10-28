import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Material の [LicensePage] を開き、アプリ本体・依存パッケージ・サイドカー分を表示する。
Future<void> openOssLicensesPage(BuildContext context) async {
  final info = await PackageInfo.fromPlatform();
  if (!context.mounted) return;
  showLicensePage(
    context: context,
    applicationName: info.appName.isNotEmpty ? info.appName : 'LMCode',
    applicationVersion: info.version,
    applicationLegalese:
        'Copyright 2026 The LMCode Authors\n'
        'Licensed under the Apache License, Version 2.0.\n'
        'ローカル LLM の GGUF モデルのライセンスは本一覧に含まれません。'
        'モデルの利用条件は利用者自身の責任で確認してください。',
  );
}
