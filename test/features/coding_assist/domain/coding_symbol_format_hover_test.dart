import 'package:flutter_test/flutter_test.dart';
import 'package:lmcode/features/coding_assist/domain/coding_symbol_format.dart';

void main() {
  group('CodingSymbolFormat.hover / library context', () {
    test('parseHoverContents reads MarkupContent value', () {
      final text = CodingSymbolFormat.parseHoverContents({
        'contents': {'kind': 'markdown', 'value': '```dart\nint foo()\n```'},
      });
      expect(text, contains('int foo()'));
    });

    test('formatHover marks package paths', () {
      final out = CodingSymbolFormat.formatHover(
        path: '/Users/me/.pub-cache/hosted/pub.dev/foo-1.0.0/lib/foo.dart',
        line: 12,
        raw: {
          'contents': {'kind': 'plaintext', 'value': 'class Foo'},
        },
      );
      expect(out, contains('パッケージ／SDK'));
      expect(out, contains('class Foo'));
    });

    test('libraryContextBlock includes doc comments above', () {
      const source = '''
/// Docs for bar.
/// Second line.
int bar() {
  return 1;
}
''';
      final block = CodingSymbolFormat.libraryContextBlock(source, 3);
      expect(block, contains('Docs for bar'));
      expect(block, contains('>   3|'));
      expect(block, contains('int bar()'));
    });
  });
}
