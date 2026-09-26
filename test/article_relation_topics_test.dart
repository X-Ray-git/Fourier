import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fourier/common/widgets/article_relation_topics.dart';
import 'package:fourier/models/article_relation.dart';

void main() {
  testWidgets('旧空概述有占位，重叠组概述全部展示，长概述在窄宽布局自然换行', (tester) async {
    const overview = '这些文章重复收录同一篇关于长时程机器人操作与可扩展训练监督的研究论文。';
    final groups = [
      _group('old-event', overview),
      _group('old-duplicate', ''),
      _group('overlap', '另一份原文的概述。'),
      _group('same-topic', overview),
    ];
    for (final width in [280.0, 900.0]) {
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: width,
                  child: ArticleRelationTopics(groups: groups),
                ),
              ),
            ),
          ),
        );
        expect(find.text(overview), findsOneWidget);
        expect(find.text('暂无关系概述'), findsOneWidget);
        expect(find.text('另一份原文的概述。'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    }
    await tester.pumpWidget(
      const MaterialApp(home: ArticleRelationTopics(groups: [])),
    );
    expect(find.text('暂无关系概述'), findsNothing);
  });
}

ArticleRelationGroup _group(String id, String topic) => ArticleRelationGroup(
  id: id,
  batchId: 'old',
  memberIds: const ['a', 'b'],
  reason: '',
  confidence: .9,
  createdAt: 1,
  topic: topic,
);
