import 'package:flutter_test/flutter_test.dart';
import 'package:lmcode/features/coding_assist/domain/coding_library_docs.dart';

void main() {
  test('query に合う段落を優先して切り出す', () {
    final raw = [
      '# Intro\n\n一般的な説明です。',
      '## Client\n\nClient クラスで get を呼びます。',
      '## Other\n\n無関係な段落。',
      '```dart\nfinal c = Client();\nc.get(url);\n```',
    ].join('\n\n');
    final out = codingLibraryDocsSelectPassages(
      raw: raw,
      query: 'Client get',
      maxChars: 400,
    );
    expect(out, contains('Client'));
    expect(out, contains('get'));
    expect(out.length, lessThanOrEqualTo(420));
  });

  test('短い本文はそのまま返す', () {
    const raw = 'hello docs';
    expect(
      codingLibraryDocsSelectPassages(raw: raw, query: 'x'),
      raw,
    );
  });

  test('結果ヘッダに版と URL を含める', () {
    final text = codingLibraryDocsFormatResult(
      library: 'http',
      version: '1.2.2',
      ecosystem: 'dart',
      source: 'local:package_config',
      sourceUrl: '',
      body: 'body',
      query: 'Client',
    );
    expect(text, contains('library: http'));
    expect(text, contains('version: 1.2.2'));
    expect(text, contains('source: local:package_config'));
    expect(text, contains('---\nbody'));
  });
}
