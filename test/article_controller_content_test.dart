import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:fourier/http/public_content_http.dart';
import 'package:fourier/models/article.dart';
import 'package:fourier/pages/article/article_page.dart';
import 'package:fourier/services/account_session_guard.dart';
import 'package:fourier/services/summary_service.dart';
import 'package:fourier/services/translation_service.dart';
import 'package:fourier/utils/storage.dart';

import 'support/hive_test_helper.dart';

const _excerpt = '<p>A short feed description.</p>';
final _longBody =
    '<section><p>${'The complete article has more detail. ' * 12}'
    '</p><p>A second paragraph and an ordinary '
    '<a href="https://example.com/details">reference</a>.</p></section>';

ArticleModel _article({String content = _excerpt}) => ArticleModel(
  entryId: 'entry-content',
  feedId: 'feed-content',
  feedTitle: 'Example Feed',
  title: 'Example article',
  url: 'https://example.com/article',
  content: content,
);

String _text(String content) => html.parse(content).body!.text.trim();

Future<void> _waitForContent(
  ArticleController controller,
  String content,
) async {
  await expectLater(() async {
    for (var i = 0; i < 100; i++) {
      if (!controller.isParsingContent.value &&
          _text(controller.normalizedContent) == _text(content)) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('Article body did not become available');
  }(), completes);
}

void main() {
  late HttpClientAdapter previousAdapter;
  late _NoNetworkAdapter adapter;
  ArticleController? controller;

  setUp(() async {
    await HiveTestHelper.setUp();
    AccountSessionGuard.finishAccountChange();
    SummaryService.resetForAccountChange();
    TranslationService.resetForAccountChange();
    previousAdapter = PublicContentHttp.dio.httpClientAdapter;
    adapter = _NoNetworkAdapter();
    PublicContentHttp.dio.httpClientAdapter = adapter;
  });
  tearDown(() async {
    controller?.onClose();
    controller = null;
    PublicContentHttp.dio.httpClientAdapter = previousAdapter;
    await HiveTestHelper.tearDown();
  });

  test(
    'opens the persisted body when the list still contains an excerpt',
    () async {
      final incoming = _article();
      final persisted = incoming.copyWith(content: _longBody, isRead: true);
      await GStorage.articleDb.put(incoming.entryId, persisted.toJson());
      controller = ArticleController(incoming)..onInit();
      await _waitForContent(controller!, _longBody);

      expect(
        html.parse(controller!.normalizedContent).querySelectorAll('p').length,
        2,
      );
      expect(
        controller!.normalizedContent,
        contains('https://example.com/details'),
      );
      expect(controller!.article, same(incoming));
      expect(controller!.isRead.value, false);
      expect(GStorage.articleDb.get(incoming.entryId), persisted.toJson());
      expect(adapter.requests, 0);
    },
  );

  test(
    'empty list content uses the stored body without another fetch',
    () async {
      final incoming = _article(content: '   ');
      await GStorage.articleDb.put(
        incoming.entryId,
        incoming.copyWith(content: _longBody).toJson(),
      );
      controller = ArticleController(incoming)..onInit();
      await _waitForContent(controller!, _longBody);
      expect(controller!.isFetchingContent.value, false);
      expect(controller!.isFetchingReadability.value, false);
      expect(adapter.requests, 0);
    },
  );

  test(
    'a newer longer incoming body is not replaced by an older excerpt',
    () async {
      final incoming = _article(content: _longBody);
      await GStorage.articleDb.put(
        incoming.entryId,
        incoming.copyWith(content: _excerpt).toJson(),
      );
      controller = ArticleController(incoming)..onInit();
      await _waitForContent(controller!, _longBody);
      expect(adapter.requests, 0);
    },
  );

  test('background content completion updates the mounted reader', () async {
    final incoming = _article();
    await GStorage.translations.put(
      incoming.entryId,
      const TranslationRecord(
        status: TranslationStatus.done,
        translatedContent: '<p>A translated description.</p>',
        updatedAt: 1,
      ).toJson(),
    );
    await GStorage.summaries.put(incoming.entryId, 'An existing summary.');
    await GStorage.articleDb.put(incoming.entryId, incoming.toJson());
    controller = ArticleController(incoming)..onInit();
    await _waitForContent(controller!, _excerpt);
    expect(controller!.isTranslated.value, true);
    expect(controller!.isSummarized.value, true);
    controller!.showTranslation.value = false;
    controller!.showSummary.value = false;
    await GStorage.articleDb.put(
      incoming.entryId,
      incoming.copyWith(content: _longBody).toJson(),
    );
    await _waitForContent(controller!, _longBody);
    expect(controller!.showTranslation.value, false);
    expect(controller!.showSummary.value, false);
    expect(adapter.requests, 0);
  });

  test(
    'short snapshots and cache eviction cannot downgrade the mounted body',
    () async {
      final incoming = _article();
      await GStorage.articleDb.put(
        incoming.entryId,
        incoming.copyWith(content: _longBody).toJson(),
      );
      controller = ArticleController(incoming)..onInit();
      await _waitForContent(controller!, _longBody);
      final firstChunk = controller!.chunks.first;
      await GStorage.articleDb.put(incoming.entryId, incoming.toJson());
      await GStorage.articleDb.delete(incoming.entryId);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(controller!.chunks.first, same(firstChunk));
      expect(_text(controller!.normalizedContent), _text(_longBody));
    },
  );

  test(
    'read state and other articles do not restart content parsing',
    () async {
      final incoming = _article(content: _longBody);
      await GStorage.articleDb.put(incoming.entryId, incoming.toJson());
      controller = ArticleController(incoming)..onInit();
      await _waitForContent(controller!, _longBody);
      final firstChunk = controller!.chunks.first;
      await GStorage.articleDb.put(
        incoming.entryId,
        incoming.copyWith(isRead: true).toJson(),
      );
      await GStorage.articleDb.put(
        'other',
        incoming.copyWith(entryId: 'other', content: 'Other').toJson(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(controller!.chunks.first, same(firstChunk));
      expect(controller!.isParsingContent.value, false);
    },
  );

  test('closed readers ignore later content completion', () async {
    final incoming = _article();
    await GStorage.articleDb.put(incoming.entryId, incoming.toJson());
    controller = ArticleController(incoming)..onInit();
    await _waitForContent(controller!, _excerpt);
    final closed = controller!;
    closed.onClose();
    controller = null;
    await GStorage.articleDb.put(
      incoming.entryId,
      incoming.copyWith(content: _longBody).toJson(),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(_text(closed.normalizedContent), _text(_excerpt));
  });

  test(
    'old account readers ignore a new account body with the same ID',
    () async {
      final incoming = _article();
      await GStorage.articleDb.put(incoming.entryId, incoming.toJson());
      controller = ArticleController(incoming)..onInit();
      await _waitForContent(controller!, _excerpt);
      AccountSessionGuard.invalidate();
      await GStorage.articleDb.put(
        incoming.entryId,
        incoming.copyWith(content: _longBody).toJson(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(_text(controller!.normalizedContent), _text(_excerpt));
    },
  );
}

class _NoNetworkAdapter implements HttpClientAdapter {
  int requests = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    throw StateError('Unexpected public page request in a content cache test');
  }

  @override
  void close({bool force = false}) {}
}
