# 网络

Folo API：

- Base URL：`https://api.folo.is`
- 认证只使用 `__Secure-better-auth.session_token` cookie。2026-07-16
  以订阅源、文章、收件箱和空写操作做过对照实验：省略或伪造
  `X-Client-Id`、`X-Session-Id` 均不影响结果，无 token 或伪造 token
  则返回 `401`，因此请求不再发送这两个无效 header。
- `lib/http/init.dart` 中的 `Request` 设置通用请求头并安装认证 interceptor。

DeepSeek API：

- Base URL：`https://api.deepseek.com`
- 用于翻译、摘要和 AI 过滤服务。
- API key 以 `deepseek_api_key` 存在 settings 中。

YouTube 播放：

- macOS 与 Android 首选仓库内可复现构建的 YouTube.js + googlevideo SABR +
  Shaka Player 运行时；应用不依赖 Node.js，生产产物位于
  `assets/youtube_player/`，构建源和锁文件位于
  `tool/youtube_player_runtime/`。
- 运行时页面由进程内 `127.0.0.1` 随机端口提供。路径包含每次进程随机生成的
  256-bit 能力令牌；代理只接受 YouTube/GoogleVideo 明确白名单内的 HTTPS
  目标，拒绝用户信息、非 443 端口和相似域名，POST 请求体限制为 2 MiB，
  媒体响应保持流式转发。不要把它改成局域网监听或通用开放代理。
- loopback 服务只在用户点击 YouTube 播放后启动。macOS Release 需要
  `com.apple.security.network.server` 与 `NSAllowsLocalNetworking`；Android
  的 network security config 只对 `localhost/127.0.0.1` 允许明文 HTTP，
  外部目标继续强制 HTTPS。
- VOD 的 SABR 取流失败时，先在同一个 Shaka 控件内关闭 SABR 请求改写并
  尝试普通自适应 DASH；SABR 与普通 DASH 都失败，或 BotGuard、超时、主
  frame 加载失败时，才切到现有 YouTube 官方 iframe。官方回退仍使用
  `youtube-nocookie.com` 和可识别 Referer，以避免错误 `153`；不要删除
  这两层兼容兜底。
- 两条链路都必须懒加载。文章初始渲染只显示缩略图，不得静默创建 WebView
  或请求 YouTube API。

Bilibili embed：

- 不抓取或解析 Bilibili 真实媒体流；只识别官方 `player.bilibili.com/player.html` iframe，并使用其站外播放器。
- `BilibiliEmbedInfo` 必须要求有效 `bvid` 或 `aid`，只保留 `cid`、分 P 等明确视频参数；不要把普通 Bilibili 页面或任意 iframe 当作播放器。
- 只有用户点击播放后才创建 WebView。未播放态不额外请求 Bilibili API 获取
  封面，避免隐式联网、接口限流和额外缓存复杂度。当前没有接入 PiliPlus 的
  登录态接口或自行解析真实媒体流，不要把 YouTube SABR 代理泛化给 Bilibili。

Debug 日志：

- Debug Dio 日志刻意不打印请求头、请求体或响应体。
- 原因：启动同步时的大量日志曾导致 `flutter run -d macos` 不稳定，而且 headers/body 可能包含敏感用户数据。

安全：

- 外部链接应经过 URL 校验 helper。
- Debug 和 Release 都必须使用系统 HTTPS 证书校验。不要设置无条件返回 `true` 的 `badCertificateCallback`；抓包代理应通过系统信任证书配置，不应让应用全局接受无效证书。
- 不要在提交的代码里记录凭据或原始响应体。
