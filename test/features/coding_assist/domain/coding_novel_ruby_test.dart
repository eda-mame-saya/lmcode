import 'package:flutter_test/flutter_test.dart';
import 'package:lmcode/features/coding_assist/domain/coding_novel_ruby.dart';

void main() {
  group('CodingNovelRuby.emphasize', () {
    test('一文字ずつ強調ルビを振る', () {
      expect(CodingNovelRuby.emphasize('異世界物語'), '|異《・》|世《・》|界《・》|物《・》|語《・》');
    });

    test('空白・改行はそのまま残す', () {
      expect(CodingNovelRuby.emphasize('あ い\nう'), '|あ《・》 |い《・》\n|う《・》');
      expect(CodingNovelRuby.emphasize(''), '');
    });

    test('既存ルビは親文字だけを強調に置き換える', () {
      expect(CodingNovelRuby.emphasize('|漢字《かんじ》だ'), '|漢《・》|字《・》|だ《・》');
    });

    test('サロゲートペアの漢字も1文字として扱う', () {
      expect(CodingNovelRuby.emphasize('𠮷野'), '|𠮷《・》|野《・》');
    });

    test('結果は parse で1文字ずつのルビとして読める', () {
      final spans = CodingNovelRuby.parse(CodingNovelRuby.emphasize('異世'));
      expect(spans, hasLength(2));
      for (final span in spans) {
        expect(span, isA<CodingNovelRubySpan>());
        expect((span as CodingNovelRubySpan).ruby, '・');
        expect(span.baseString, hasLength(1));
      }
    });
  });
}
