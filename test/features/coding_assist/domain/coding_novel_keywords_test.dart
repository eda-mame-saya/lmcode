import 'package:flutter_test/flutter_test.dart';
import 'package:lmcode/features/coding_assist/domain/coding_novel_keywords.dart';

void main() {
  test('見出し階層と本文をパースする', () {
    const md = '''
# 登場人物
## 主人公（名前：タロウ）
物語の主人公
**重要**
### 所持スキル
魔法
剣術
# 地名
## 王都
首都
''';
    final roots = CodingNovelKeywordParser.parse(md);
    expect(roots, hasLength(2));
    expect(roots[0].title, '登場人物');
    expect(roots[0].children, hasLength(1));
    final hero = roots[0].children.single;
    expect(hero.title, '主人公（名前：タロウ）');
    expect(hero.body, contains('物語の主人公'));
    expect(hero.body, contains('**重要**'));
    expect(hero.children, hasLength(1));
    expect(hero.children.single.title, '所持スキル');
    expect(hero.children.single.body, contains('魔法'));
    expect(roots[1].title, '地名');
    expect(roots[1].children.single.title, '王都');
  });
}
