import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'app_version_service.dart';

class AppUpdateAsset {
  const AppUpdateAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
    required this.sha256,
  });

  final String name;
  final Uri downloadUrl;
  final int size;
  final String sha256;
}

class AppUpdateRelease {
  const AppUpdateRelease({
    required this.version,
    required this.name,
    required this.notes,
    required this.publishedAt,
    required this.asset,
  });

  final String version;
  final String name;
  final String notes;
  final DateTime? publishedAt;
  final AppUpdateAsset asset;

  bool get isNewerThanInstalled =>
      AppUpdateService.compareVersions(version, AppVersionService.version) > 0;
}

abstract final class AppUpdateService {
  static const _latestReleaseUrl =
      'https://api.github.com/repos/X-Ray-git/Fourier/releases/latest';
  static const _platformChannel = MethodChannel(
    'io.github.xraygit.fourier/app_update',
  );

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: const {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    ),
  );

  static Future<AppUpdateRelease> checkLatestAndroidRelease() async {
    final response = await _dio.get<Map<String, dynamic>>(_latestReleaseUrl);
    final data = response.data;
    if (data == null) {
      throw const FormatException('GitHub 没有返回版本信息');
    }

    return parseAndroidReleaseData(data);
  }

  static AppUpdateRelease parseAndroidReleaseData(Map<String, dynamic> data) {
    final rawTag = data['tag_name'];
    final rawAssets = data['assets'];
    if (rawTag is! String || rawAssets is! List) {
      throw const FormatException('GitHub Release 信息格式不完整');
    }

    final version = rawTag.startsWith('v') ? rawTag.substring(1) : rawTag;
    final expectedSuffix = '-android-v$version.apk';
    Map<String, dynamic>? matchedAsset;
    for (final rawAsset in rawAssets) {
      if (rawAsset is! Map) continue;
      final asset = Map<String, dynamic>.from(rawAsset);
      final assetName = asset['name'];
      if (assetName is String && assetName.endsWith(expectedSuffix)) {
        matchedAsset = asset;
        break;
      }
    }
    if (matchedAsset == null) {
      throw FormatException('Release v$version 中没有 Android 安装包');
    }

    final assetName = matchedAsset['name'];
    final downloadUrl = matchedAsset['browser_download_url'];
    final size = matchedAsset['size'];
    final digest = matchedAsset['digest'];
    if (assetName is! String ||
        downloadUrl is! String ||
        size is! int ||
        digest is! String ||
        !digest.startsWith('sha256:')) {
      throw const FormatException('Android 安装包缺少可验证的 SHA-256 摘要');
    }

    return AppUpdateRelease(
      version: version,
      name: data['name'] is String ? data['name'] as String : rawTag,
      notes: data['body'] is String ? data['body'] as String : '',
      publishedAt: DateTime.tryParse(data['published_at']?.toString() ?? ''),
      asset: AppUpdateAsset(
        name: assetName,
        downloadUrl: Uri.parse(downloadUrl),
        size: size,
        sha256: digest.substring('sha256:'.length).toLowerCase(),
      ),
    );
  }

  static Future<bool> downloadAndInstallAndroid(
    AppUpdateRelease release, {
    required void Function(int received, int total) onProgress,
    CancelToken? cancelToken,
  }) async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/${release.asset.name}');
    final alreadyDownloaded =
        await file.exists() && await _sha256Of(file) == release.asset.sha256;

    try {
      if (!alreadyDownloaded) {
        if (await file.exists()) await file.delete();
        await _dio.downloadUri(
          release.asset.downloadUrl,
          file.path,
          onReceiveProgress: onProgress,
          cancelToken: cancelToken,
          options: Options(
            followRedirects: true,
            receiveTimeout: Duration.zero,
          ),
        );
      }
      final actualDigest = await _sha256Of(file);
      if (actualDigest != release.asset.sha256) {
        throw const FormatException('安装包校验失败，请重新下载');
      }
      return await _platformChannel.invokeMethod<bool>(
            'installAndroidApk',
            file.path,
          ) ??
          false;
    } catch (_) {
      if (await file.exists() &&
          await _sha256Of(file) != release.asset.sha256) {
        await file.delete();
      }
      rethrow;
    }
  }

  static Future<void> checkForMacOSUpdate() =>
      _platformChannel.invokeMethod<void>('checkForMacOSUpdate');

  static int compareVersions(String left, String right) {
    final leftParts = _parseVersion(left);
    final rightParts = _parseVersion(right);
    for (var index = 0; index < 3; index++) {
      final comparison = leftParts[index].compareTo(rightParts[index]);
      if (comparison != 0) return comparison;
    }
    return 0;
  }

  static List<int> _parseVersion(String value) {
    final normalized = value.startsWith('v') ? value.substring(1) : value;
    final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)$').firstMatch(normalized);
    if (match == null) throw FormatException('无法识别版本号：$value');
    return [
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    ];
  }

  static Future<String> _sha256Of(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();
}
