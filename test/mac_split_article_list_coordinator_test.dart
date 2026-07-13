import 'package:autofolo/common/widgets/mac_split_article_list_coordinator.dart';
import 'package:autofolo/models/article.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<ArticleModel> articles;
  ArticleModel? selected;
  late List<String> revealed;
  late MacSplitArticleListCoordinator coordinator;

  setUp(() {
    articles = [_article('a'), _article('b'), _article('c')];
    selected = articles[1];
    revealed = [];
    coordinator = MacSplitArticleListCoordinator(
      articles: () => articles,
      selectedArticle: () => selected,
      setSelectedArticle: (article) => selected = article,
      revealArticle: revealed.add,
    );
  });

  tearDown(() => coordinator.dispose());

  test('keeps outgoing selection until removal animation ends', () {
    expect(coordinator.beginRemoval('b'), isTrue);
    articles = [articles[0], articles[2]];

    coordinator.reconcileSelection();
    expect(selected?.entryId, 'b');
    expect(revealed, isEmpty);

    coordinator.onRemoveEnd(_article('b'));
    expect(selected?.entryId, 'c');
    expect(revealed, ['c']);
  });

  test('falls back to previous article when removing the last item', () {
    selected = articles.last;
    expect(coordinator.beginRemoval('c'), isTrue);
    articles = articles.sublist(0, 2);

    coordinator.onRemoveEnd(_article('c'));
    expect(selected?.entryId, 'b');
    expect(revealed, ['b']);
  });

  test('clears selection when the final article is removed', () {
    articles = [_article('a')];
    selected = articles.single;
    expect(coordinator.beginRemoval('a'), isTrue);
    articles = [];

    coordinator.onRemoveEnd(_article('a'));
    expect(selected, isNull);
    expect(revealed, isEmpty);
  });

  test('blocks another selected removal until completion', () {
    expect(coordinator.beginRemoval('b'), isTrue);
    expect(coordinator.beginRemoval('b'), isFalse);
    expect(coordinator.beginRemoval('a'), isFalse);
  });

  test('relative selection and restoration share reveal behavior', () {
    expect(coordinator.selectRelative(1), isTrue);
    expect(selected?.entryId, 'c');
    expect(revealed, ['c']);

    revealed.clear();
    expect(coordinator.restoreSelection('a'), isTrue);
    expect(selected?.entryId, 'a');
    expect(revealed, ['a']);
  });
}

ArticleModel _article(String entryId) {
  return ArticleModel(
    entryId: entryId,
    feedId: 'feed',
    feedTitle: 'Feed',
    title: entryId,
    url: 'https://example.com/$entryId',
    publishedAt: '2026-07-13T00:00:00Z',
    isRead: false,
    category: 'article',
    subscriptionCategory: '',
  );
}
