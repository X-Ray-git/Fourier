import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fourier/models/article.dart';
import 'package:fourier/services/translation_service.dart';
import 'package:fourier/utils/storage.dart';

import 'support/hive_test_helper.dart';

/// 临时 Hive box 的重启/重新 hydrate 测试：
/// 完成后立即退出（重置服务状态再重新水合）也不会丢失翻译。

const _successBody = '''
{
  "choices": [
    {
      "message": {
        "role": "assistant",
        "content": "{\\"translated_title\\":\\"标题译文\\",\\"translated_html\\":\\"<p>译文内容</p>\\"}"
      },
      "finish_reason": "stop"
    }
  ]
}
''';

ArticleModel _article({String content = '<p>原文内容</p>'}) {
  return ArticleModel(
    entryId: 'entry-persist',
    feedId: 'feed-1',
    feedTitle: '测试源',
    title: '标题',
    url: 'https://example.com/article',
    content: content,
    publishedAt: '2026-08-01T00:00:00Z',
  );
}

void main() {
  setUp(() async {
    await HiveTestHelper.setUp();
    // 不重试，避免失败路径的 1s 退避拖慢测试。
    await GStorage.setting.put('auto_retry_max_count', 0);
    TranslationService.setApiKey('test-key');
    HttpOverrides.global = _FakeHttpOverrides();
    _FakeResponseSpec.current = const _FakeResponseSpec(
      statusCode: 200,
      body: _successBody,
    );
  });

  tearDown(() async {
    HttpOverrides.global = null;
    _FakeResponseSpec.current = null;
    TranslationService.resetForAccountChange();
    await HiveTestHelper.tearDown();
  });

  test('普通翻译：完成后立即重启，译文不丢失', () async {
    final record = await TranslationService.translateArticle(_article());
    expect(record.isTranslated, isTrue);
    expect(record.translatedContent, contains('译文内容'));

    // 模拟完成立即退出：清空内存态并重新水合（从磁盘读取）。
    TranslationService.resetForAccountChange();
    final reloaded = TranslationService.recordOf('entry-persist');
    expect(reloaded, isNotNull);
    expect(reloaded!.isTranslated, isTrue);
    expect(reloaded.translatedContent, contains('译文内容'));
    expect(reloaded.translatedTitle, '标题译文');
  });

  test('分块翻译：完成后立即重启，分块译文不丢失', () async {
    // 超过 35KB 触发分块翻译。
    final bigContent = '<p>${'块内容。' * 12000}</p>';
    final record = await TranslationService.translateArticle(
      _article(content: bigContent),
    );
    expect(record.isTranslated, isTrue);

    TranslationService.resetForAccountChange();
    final reloaded = TranslationService.recordOf('entry-persist');
    expect(reloaded, isNotNull);
    expect(reloaded!.isTranslated, isTrue);
    expect(reloaded.translatedContent, isNotEmpty);
  });

  test('错误态：完成后立即重启，错误状态不丢失', () async {
    _FakeResponseSpec.current = const _FakeResponseSpec(
      statusCode: 500,
      body: '{"error":"boom"}',
    );

    final record = await TranslationService.translateArticle(_article());
    expect(record.status, TranslationStatus.error);

    TranslationService.resetForAccountChange();
    final reloaded = TranslationService.recordOf('entry-persist');
    expect(reloaded, isNotNull);
    expect(reloaded!.status, TranslationStatus.error);
    expect(reloaded.errorMessage, isNotNull);
  });

  test('pending 只存在内存中，重启后不恢复', () async {
    TranslationService.markPending('entry-pending');
    expect(TranslationService.isPending('entry-pending'), isTrue);

    TranslationService.resetForAccountChange();
    expect(TranslationService.isPending('entry-pending'), isFalse);
    expect(TranslationService.recordOf('entry-pending'), isNull);
  });
}

// ─── 内存级 Fake HttpClient（不产生真实网络请求） ────────────────
//
// dio 的 IOHttpClientAdapter 会缓存 HttpClient 实例，因此 fake 通过
// 可变的当前响应规格（[ _FakeResponseSpec.current]）按请求时刻取值。

class _FakeResponseSpec {
  final int statusCode;
  final String body;

  const _FakeResponseSpec({required this.statusCode, required this.body});

  static _FakeResponseSpec? current;
}

class _FakeHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _FakeHttpClient();
}

class _FakeHttpClient implements HttpClient {
  @override
  bool autoUncompress = true;

  @override
  Duration? connectionTimeout;

  @override
  Duration idleTimeout = const Duration(seconds: 15);

  @override
  int? maxConnectionsPerHost;

  @override
  String? userAgent;

  @override
  Future<HttpClientRequest> postUrl(Uri url) async => _FakeRequest(this);

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _FakeRequest(this);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _FakeRequest(this);

  @override
  Future<void> close({bool force = false}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError(
      'Unsupported HttpClient member: ${invocation.memberName}',
    );
  }
}

class _FakeRequest implements HttpClientRequest {
  final _FakeHttpClient client;
  final HttpHeaders _headers = _FakeHeaders();
  final BytesBuilder _body = BytesBuilder();

  _FakeRequest(this.client);

  @override
  bool followRedirects = false;

  @override
  int maxRedirects = 0;

  @override
  bool persistentConnection = false;

  @override
  HttpHeaders get headers => _headers;

  @override
  void write(Object? object) => _body.add(utf8.encode(object.toString()));

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {
    var first = true;
    for (final object in objects) {
      if (!first && separator.isNotEmpty) write(separator);
      write(object);
      first = false;
    }
  }

  @override
  void add(List<int> data) => _body.add(data);

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      _body.add(chunk);
    }
  }

  @override
  Future<HttpClientResponse> close() async {
    final spec =
        _FakeResponseSpec.current ??
        const _FakeResponseSpec(statusCode: 500, body: 'no fake spec');
    return _FakeResponse(statusCode: spec.statusCode, body: spec.body);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError(
      'Unsupported HttpClientRequest member: ${invocation.memberName}',
    );
  }
}

class _FakeHeaders implements HttpHeaders {
  final Map<String, List<String>> _values = {};

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    _values.putIfAbsent(name.toLowerCase(), () => []).add(value.toString());
  }

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _values[name.toLowerCase()] = [value.toString()];
  }

  @override
  String? value(String name) {
    final values = _values[name.toLowerCase()];
    return values == null || values.isEmpty ? null : values.first;
  }

  @override
  void forEach(void Function(String name, List<String> values) action) {
    _values.forEach(action);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError(
      'Unsupported HttpHeaders member: ${invocation.memberName}',
    );
  }
}

class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  @override
  final int statusCode;
  final String body;
  late final List<List<int>> _chunks;

  _FakeResponse({required this.statusCode, required this.body}) {
    _chunks = body.isEmpty ? <List<int>>[] : <List<int>>[utf8.encode(body)];
  }

  @override
  int get contentLength => body.length;

  @override
  HttpHeaders get headers =>
      _FakeHeaders()
        ..set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');

  @override
  bool get isRedirect => false;

  @override
  bool get persistentConnection => true;

  @override
  String get reasonPhrase => statusCode == 200 ? 'OK' : 'Error';

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable(_chunks).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError(
      'Unsupported HttpClientResponse member: ${invocation.memberName}',
    );
  }
}
