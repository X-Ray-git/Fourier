import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:fourier/models/article.dart';
import 'package:fourier/pages/article/article_page.dart';

void main() {
  setUp(() => Get.testMode = true);
  tearDown(() async => Get.reset());

  test('A to B to A keeps A alive until its last view closes', () {
    final a = _Controller(_article('a'));
    final b = _Controller(_article('b'));
    Get.put<ArticleController>(a, tag: 'a', permanent: true);
    Get.put<ArticleController>(b, tag: 'b', permanent: true);
    final root = ArticleController.retainForView(a.article);
    final related = ArticleController.retainForView(b.article);
    final repeated = ArticleController.retainForView(a.article);
    expect(root, same(repeated));
    expect(ArticleController.releaseForView(repeated), isFalse);
    expect(a.closed, 0);
    expect(Get.find<ArticleController>(tag: 'a'), same(root));
    expect(ArticleController.releaseForView(related), isTrue);
    expect(b.closed, 1);
    expect(ArticleController.releaseForView(root), isTrue);
    expect(a.closed, 1);
    expect(Get.isRegistered<ArticleController>(tag: 'a'), isFalse);
  });

  test(
    'late release never deletes a replacement controller with the same ID',
    () {
      final old = _Controller(_article('a'));
      Get.put<ArticleController>(old, tag: 'a', permanent: true);
      ArticleController.retainForView(old.article);
      Get.delete<ArticleController>(tag: 'a', force: true);
      final fresh = _Controller(_article('a'));
      Get.put<ArticleController>(fresh, tag: 'a', permanent: true);
      ArticleController.retainForView(fresh.article);
      ArticleController.releaseForView(old);
      expect(Get.find<ArticleController>(tag: 'a'), same(fresh));
      expect(fresh.closed, 0);
      ArticleController.releaseForView(fresh);
      expect(fresh.closed, 1);
    },
  );
}

class _Controller extends ArticleController {
  _Controller(super.article);
  int closed = 0;
  // Deliberately bypass content loading in this lifecycle-only test double.
  @override
  // ignore: must_call_super
  void onInit() {} // Lifetime test: no content loading or external requests.
  @override
  void onClose() {
    closed++;
    super.onClose();
  }
}

ArticleModel _article(String id) => ArticleModel(
  entryId: id,
  feedId: 'feed',
  feedTitle: 'Feed',
  title: id,
  url: '',
  content: '<p>text</p>',
  publishedAt: '',
);
