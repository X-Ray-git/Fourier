# 网络

Folo API：

- Base URL：`https://api.folo.is`
- 认证使用 cookie 加 `X-Client-Id` 和 `X-Session-Id`。
- `lib/http/init.dart` 中的 `Request` 设置通用请求头并安装认证 interceptor。

DeepSeek API：

- Base URL：`https://api.deepseek.com`
- 用于翻译、摘要和 AI 过滤服务。
- API key 以 `deepseek_api_key` 存在 settings 中。

Debug 日志：

- Debug Dio 日志刻意不打印请求头、请求体或响应体。
- 原因：启动同步时的大量日志曾导致 `flutter run -d macos` 不稳定，而且 headers/body 可能包含敏感用户数据。

安全：

- 外部链接应经过 URL 校验 helper。
- 不要在提交的代码里记录凭据或原始响应体。
