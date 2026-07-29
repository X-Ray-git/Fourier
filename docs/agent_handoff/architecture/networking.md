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
  `assets/embed_video_player/`，构建源和锁文件位于
  `tool/embed_video_player_runtime/`。该运行时的 Shaka 控件壳也由
  Bilibili 共用。
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

Bilibili 播放：

- `BilibiliEmbedInfo` 必须要求有效 `bvid` 或 `aid`，只保留 `cid`、分 P 等
  明确视频参数；不要把普通 Bilibili 页面或任意 iframe 当作播放器。
- 只有用户点击后才调用匿名 `x/web-interface/view`（缺少 `cid` 时）、
  `x/player/playurl` 和 `x/player/v2`。不复用 Folo 登录信息，不接入
  Bilibili 登录态，不在未播放态预取封面或媒体。
- 播放地址响应转换成静态 DASH MPD；为保证 macOS WKWebView 和 Android
  WebView 的共同兼容性，每个画质只选 AVC 轨，并搭配一条最高码率普通音轨。
  匿名接口实际返回哪些画质就展示哪些，不伪造会员画质。可用字幕会从
  Bilibili JSON 转成 WebVTT 后加入同一个 Shaka 设置菜单；字幕准备最多
  等待 4 秒，超时只舍弃字幕，不能阻塞视频播放。
- Bilibili 使用独立的 `127.0.0.1` 随机能力路径服务。媒体代理只接受当前
  播放 session 中由官方 API 实际返回的完整 HTTPS URL；重定向还必须落在
  `bilivideo.com` 或明确的 Akamai 镜像。请求补充 Bilibili Referer/Origin，
  Range 响应保持流式转发。不要放宽为通用 URL 代理。
- 弹幕使用匿名 `x/v2/dm/web/seg.so` Protobuf 接口，以 `cid` 为对象、每
  6 分钟一段。loopback 只允许当前播放 session 的正整数分段号，并按视频
  时长限制最大段；共享网页运行时通过 Protobuf-ES 结构化解析。当前段按需
  获取并预取下一段，弹幕失败只舍弃该段，不能阻塞视频、触发播放器回退或
  改变字幕状态。当前只读，不接登录态和发送弹幕。
- 详情、播放地址、字幕、MPD、媒体或 Shaka 播放任一环节失败时，自动回退
  `player.bilibili.com` 官方 iframe。匿名接口属于兼容性能力而非稳定公开
  SDK，因此官方 iframe 必须长期保留。

Debug 日志：

- Debug Dio 日志刻意不打印请求头、请求体或响应体。
- 原因：启动同步时的大量日志曾导致 `flutter run -d macos` 不稳定，而且 headers/body 可能包含敏感用户数据。

安全：

- 外部链接应经过 URL 校验 helper。
- Debug 和 Release 都必须使用系统 HTTPS 证书校验。不要设置无条件返回 `true` 的 `badCertificateCallback`；抓包代理应通过系统信任证书配置，不应让应用全局接受无效证书。
- 不要在提交的代码里记录凭据或原始响应体。
