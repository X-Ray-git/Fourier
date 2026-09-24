import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// One cache for foreground images and article prefetch, retaining existing keys.
class ImageNetworkCache extends CacheManager with ImageCacheManager {
  ImageNetworkCache._()
    : super(
        Config(DefaultCacheManager.key, fileService: BoundedImageFileService()),
      );

  static final instance = ImageNetworkCache._();

  static void initialize() {
    CachedNetworkImageProvider.defaultCacheManager = instance;
  }
}

/// Each download owns its client, so cancelling a stalled transfer does not
/// terminate another image's connection. Both headers and streamed bodies are
/// bounded; a total deadline also handles servers that trickle bytes forever.
class BoundedImageFileService extends FileService {
  BoundedImageFileService({
    this.headerTimeout = const Duration(seconds: 20),
    this.readTimeout = const Duration(seconds: 20),
    this.totalTimeout = const Duration(seconds: 90),
  });

  final Duration headerTimeout;
  final Duration readTimeout;
  final Duration totalTimeout;

  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    final client = IOClient();
    Duration? expiredTimeout;
    final deadline = Timer(totalTimeout, () {
      expiredTimeout = totalTimeout;
      client.close();
    });
    void close() {
      deadline.cancel();
      client.close();
    }

    try {
      final request = http.Request('GET', Uri.parse(url));
      if (headers != null) request.headers.addAll(headers);
      final response = await client
          .send(request)
          .timeout(
            headerTimeout,
            onTimeout: () {
              close();
              throw TimeoutException(
                'Image response headers timed out',
                headerTimeout,
              );
            },
          );
      // CacheManager never consumes bodies for 304 or error responses.
      if (response.statusCode != 200 && response.statusCode != 202) {
        close();
        return HttpGetResponse(response);
      }
      Stream<List<int>> content() async* {
        try {
          await for (final chunk in response.stream.timeout(
            readTimeout,
            onTimeout: (sink) {
              expiredTimeout = readTimeout;
              sink.addError(
                TimeoutException('Image body stalled', readTimeout),
              );
              sink.close();
              close();
            },
          )) {
            yield chunk;
          }
        } catch (_) {
          if (expiredTimeout != null) {
            throw TimeoutException('Image transfer timed out', expiredTimeout);
          }
          rethrow;
        } finally {
          close();
        }
      }

      return HttpGetResponse(
        http.StreamedResponse(
          content(),
          response.statusCode,
          contentLength: response.contentLength,
          headers: response.headers,
        ),
      );
    } catch (_) {
      close();
      if (expiredTimeout != null) {
        throw TimeoutException('Image transfer timed out', expiredTimeout);
      }
      rethrow;
    }
  }
}
