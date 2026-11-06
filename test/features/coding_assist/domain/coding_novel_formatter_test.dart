import 'package:flutter_test/flutter_test.dart';
import 'package:lmcode/features/coding_assist/domain/coding_novel_formatter.dart';
import 'package:lmcode/features/coding_assist/domain/coding_novel_ruby.dart';
import 'package:lmcode/features/coding_assist/domain/coding_novel_settings.dart';

void main() {
  group('CodingNovelFormatter', () {
    test('地の文とセリフのあいだに空行を入れる', () {
      const settings = CodingNovelSettings(
        indentCount: 1,
        indentSpace: CodingNovelIndentSpace.fullWidth,
        indentDialogue: false,
      );
      final out = CodingNovelFormatter.format(
        '朝が来た。\n「おはよう」\n彼は答えた。',
        settings: settings,
      );
      expect(
        out,
        '　朝が来た。\n\n「おはよう」\n\n　彼は答えた。',
      );
    });

    test('セリフにもインデントする設定', () {
      const settings = CodingNovelSettings(
        indentCount: 1,
        indentSpace: CodingNovelIndentSpace.fullWidth,
        indentDialogue: true,
      );
      final out = CodingNovelFormatter.format(
        '朝が来た。\n「おはよう」',
        settings: settings,
      );
      expect(out, '　朝が来た。\n\n　「おはよう」');
    });

    test('半角スペース複数', () {
      const settings = CodingNovelSettings(
        indentCount: 2,
        indentSpace: CodingNovelIndentSpace.halfWidth,
        indentDialogue: false,
      );
      final out = CodingNovelFormatter.format(
        '本文',
        settings: settings,
      );
      expect(out, '  本文');
    });

    test('先頭と末尾が組と一致するときだけセリフ', () {
      const settings = CodingNovelSettings(
        indentDialogue: false,
        dialogueDelimiters: [
          CodingNovelDialogueDelimiter(open: '「', close: '」'),
          CodingNovelDialogueDelimiter(open: '（', close: '）'),
        ],
      );
      expect(
        CodingNovelFormatter.isDialogueLine('「こんにちは」', settings: settings),
        isTrue,
      );
      expect(
        CodingNovelFormatter.isDialogueLine('（小声で）', settings: settings),
        isTrue,
      );
      // 地の文の途中に鉤括弧
      expect(
        CodingNovelFormatter.isDialogueLine(
          '彼は「こんにちは」と言った。',
          settings: settings,
        ),
        isFalse,
      );
      // 開きだけ
      expect(
        CodingNovelFormatter.isDialogueLine('「続きは', settings: settings),
        isFalse,
      );
    });

    test('登録していない記号はセリフにしない', () {
      const settings = CodingNovelSettings(
        dialogueDelimiters: [
          CodingNovelDialogueDelimiter(open: '「', close: '」'),
        ],
      );
      expect(
        CodingNovelFormatter.isDialogueLine('『こんばんは』', settings: settings),
        isFalse,
      );
    });
  });

  group('CodingNovelRuby', () {
    test('なろう記法のラップとパース', () {
      final wrapped = CodingNovelRuby.wrap(base: '漢字', ruby: 'かんじ');
      expect(wrapped, '|漢字《かんじ》');
      final spans = CodingNovelRuby.parse('彼は$wrappedを読んだ。');
      expect(spans, hasLength(3));
      expect(spans[0], isA<CodingNovelPlainSpan>());
      expect(spans[1], isA<CodingNovelRubySpan>());
      final ruby = spans[1] as CodingNovelRubySpan;
      expect(ruby.base, '漢字');
      expect(ruby.ruby, 'かんじ');
    });
  });
}
