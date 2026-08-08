import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../common/widgets/feedback_toast.dart';
import '../utils/security_utils.dart';

/// 外链打开失败分类。
enum ExternalLinkFailureType {
  /// URL 非法或协议不受支持（非 http/https、无主机等）。
  invalidUrl,

  /// 平台找不到能处理该链接的应用（没有浏览器等处理程序）。
  noHandler,

  /// 平台拒绝打开（PlatformException，但明确不是找不到处理程序）。
  platformDenied,

  /// 其他未知异常。
  error,
}

/// 外链打开结果。
class ExternalLinkResult {
  const ExternalLinkResult.opened()
    : opened = true,
      failure = null,
      detail = null;

  const ExternalLinkResult.failed(this.failure, {this.detail}) : opened = false;

  final bool opened;
  final ExternalLinkFailureType? failure;
  final String? detail;
}

/// 共享外链服务：校验 http/https 后直接尝试
/// `launchUrl(externalApplication)`，根据真实的 false 返回值或异常反馈，
/// 不再把 `canLaunchUrl=false` 直接解释为「未找到默认浏览器」。
abstract final class ExternalLinkService {
  static const String _noHandlerCode = 'ACTIVITY_NOT_FOUND';

  static Future<ExternalLinkResult> openUrl(String? rawUrl) async {
    if (rawUrl == null || rawUrl.trim().isEmpty) {
      return const ExternalLinkResult.failed(
        ExternalLinkFailureType.invalidUrl,
        detail: '链接为空',
      );
    }
    final uri = SecurityUtils.parseHttpUrl(rawUrl);
    if (uri == null) {
      return const ExternalLinkResult.failed(
        ExternalLinkFailureType.invalidUrl,
        detail: '链接格式无效或协议不受支持',
      );
    }

    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (opened) return const ExternalLinkResult.opened();
      // Android 11+ 上未声明 queries 或确实没有处理程序时 launchUrl 返回 false。
      return const ExternalLinkResult.failed(
        ExternalLinkFailureType.noHandler,
        detail: '系统未找到可用的浏览器',
      );
    } on PlatformException catch (e) {
      // 平台级拒绝：找不到 Activity 与真实拒绝分开处理。
      if (e.code == _noHandlerCode) {
        return const ExternalLinkResult.failed(
          ExternalLinkFailureType.noHandler,
          detail: '系统未找到可用的浏览器',
        );
      }
      return ExternalLinkResult.failed(
        ExternalLinkFailureType.platformDenied,
        detail: e.message ?? '平台拒绝打开该链接',
      );
    } catch (e) {
      return ExternalLinkResult.failed(
        ExternalLinkFailureType.error,
        detail: e.toString(),
      );
    }
  }

  /// 打开链接并统一反馈错误提示（各页面共用，避免重复拼装文案）。
  static Future<bool> openUrlWithFeedback(String? rawUrl) async {
    final result = await openUrl(rawUrl);
    if (result.opened) return true;
    reportOpenFailure(result.failure);
    return false;
  }

  static void reportOpenFailure(ExternalLinkFailureType? failure) {
    switch (failure) {
      case ExternalLinkFailureType.invalidUrl:
        AppFeedback.warning('无法打开链接', '仅支持有效的 HTTP/HTTPS 地址');
      case ExternalLinkFailureType.noHandler:
        AppFeedback.warning('无法打开链接', '系统未找到可用的浏览器');
      case ExternalLinkFailureType.platformDenied:
        AppFeedback.error('无法打开链接', '系统拒绝打开该链接，请稍后重试');
      case ExternalLinkFailureType.error:
        AppFeedback.error('无法打开链接', '打开失败，请稍后重试');
      case null:
        break;
    }
  }
}
