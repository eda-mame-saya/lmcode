import 'package:flutter_test/flutter_test.dart';
import 'package:lmcode/features/api_settings/domain/entities/local_llm_connection_settings.dart';

void main() {
  test('codingAutoOmitsReadFile is true only when auto ON and allow OFF', () {
    const off = LocalLlmConnectionSettings();
    expect(off.codingAutoOmitsReadFile, isFalse);

    const autoOnly = LocalLlmConnectionSettings(codingAutoApplyPatches: true);
    expect(autoOnly.codingAutoOmitsReadFile, isTrue);

    const allow = LocalLlmConnectionSettings(
      codingAutoApplyPatches: true,
      codingAutoAllowReadFile: true,
    );
    expect(allow.codingAutoOmitsReadFile, isFalse);
  });
}
