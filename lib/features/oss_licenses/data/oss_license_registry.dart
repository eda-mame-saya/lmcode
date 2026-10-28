import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'sidecar_license_texts.dart';

/// アプリ本体（Apache-2.0）とサイドカー等のライセンスを [LicenseRegistry] へ登録する。
/// Flutter 依存パッケージの条文は SDK／各パッケージ側が別途提供する。
Future<void> registerOssLicenses() async {
  if (_registered) return;
  _registered = true;

  final appText = await _loadAppLicenseText();

  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const ['LMCode'], appText);
    for (final entry in kSidecarLicenseEntries) {
      yield LicenseEntryWithLineBreaks(
        [entry.packageName],
        entry.licenseText,
      );
    }
  });
}

Future<String> _loadAppLicenseText() async {
  try {
    final notice = await rootBundle.loadString('NOTICE');
    final license = await rootBundle.loadString('LICENSE');
    return '$notice\n\n---\n\n$license';
  } catch (e, st) {
    debugPrint('[OSS] LICENSE/NOTICE の読込に失敗: $e\n$st');
    return '''LMCode
Copyright 2026 The LMCode Authors

Licensed under the Apache License, Version 2.0.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

(アプリ同梱の LICENSE / NOTICE を読めませんでした。リポジトリルートの
LICENSE を参照してください。)
''';
  }
}

bool _registered = false;
