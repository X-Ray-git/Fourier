import 'package:flutter_test/flutter_test.dart';

import 'package:fourier/models/article_relation.dart';
import 'package:fourier/services/article_relation_worker.dart';

void main() {
  test('解析有效关系并忽略不含新文章的关系组', () {
    final labels = {
      'N001': _node('new-1'),
      'H001': _node('history-1'),
      'H002': _node('history-2'),
    };
    final result = ArticleRelationWorker.parseResponse({
      'choices': [
        {
          'finish_reason': 'stop',
          'message': {
            'content':
                '{"groups":['
                '{"members":["N001","H001"],"reason":"同一事件","confidence":0.91},'
                '{"members":["H001","H002"],"reason":"历史内部","confidence":0.8}'
                ']}',
          },
        },
      ],
      'usage': {
        'prompt_tokens': 100,
        'completion_tokens': 20,
        'prompt_cache_hit_tokens': 80,
        'prompt_cache_miss_tokens': 20,
        'total_tokens': 120,
      },
    }, labels);

    expect(result.groups, hasLength(1));
    expect(result.groups.single.memberIds, ['new-1', 'history-1']);
    expect(result.groups.single.confidence, 0.91);
    expect(result.cacheHitTokens, 80);
    expect(result.cacheMissTokens, 20);
    expect(result.totalTokens, 120);
  });

  test('截断响应不能被当成成功批次', () {
    expect(
      () => ArticleRelationWorker.parseResponse(
        {
          'choices': [
            {
              'finish_reason': 'length',
              'message': {'content': '{"groups":[]}'},
            },
          ],
        },
        {'N001': _node('new-1')},
      ),
      throwsFormatException,
    );
  });
}

ArticleRelationNode _node(String id) {
  return ArticleRelationNode(
    articleId: id,
    sequence: 1,
    title: id,
    feedId: 'feed',
    feedTitle: '来源',
    url: 'https://example.com/$id',
    summary: '摘要',
    summaryDigest: 'digest',
    summaryUpdatedAt: 1,
  );
}
