# 网络

Folo API：

- Base URL：`https://api.folo.is`
- 认证使用 cookie 加 `X-Client-Id` 和 `X-Session-Id`。
- `lib/http/init.dart` 中的 `Request` 设置通用请求头并安装认证 interceptor。

DeepSeek API：

- Base URL：`https://api.deepseek.com`
- 用于翻译、摘要和 AI 过滤服务。
- API key 以 `deepseek_api_key` 存在 settings 中。

YouTube embed：

- 不抓取或解析 YouTube 真实媒体流；只使用官方 iframe/WebView 播放器。
- WebView 请求必须保留可识别的 Referer。当前本地 HTML 以公开仓库地址为 base URL，使用 `strict-origin-when-cross-origin`，避免错误 `153`。
- 默认使用 `youtube-nocookie.com`。只有用户点击播放后才创建 WebView，但这仍会与 YouTube 建立网络连接；不要在文章初始渲染时静默加载播放器。

Debug 日志：

- Debug Dio 日志刻意不打印请求头、请求体或响应体。
- 原因：启动同步时的大量日志曾导致 `flutter run -d macos` 不稳定，而且 headers/body 可能包含敏感用户数据。

安全：

- 外部链接应经过 URL 校验 helper。
- Debug 和 Release 都必须使用系统 HTTPS 证书校验。不要设置无条件返回 `true` 的 `badCertificateCallback`；抓包代理应通过系统信任证书配置，不应让应用全局接受无效证书。
- 不要在提交的代码里记录凭据或原始响应体。
