# YouTube 播放运行时

此目录包含 Auto Folo 内嵌 YouTube 播放器的可复现构建源。应用不在运行时
依赖 Node.js；Flutter 只打包 `assets/youtube_player/` 中的生产构建产物。

## 构建

```bash
npm ci
npm run typecheck
npm run build
```

构建会固定输出：

- `assets/youtube_player/index.html`
- `assets/youtube_player/youtube_player.js`
- `assets/youtube_player/youtube_player.css`

依赖版本由 `package-lock.json` 锁定。更新依赖时必须同步检查
`THIRD_PARTY_NOTICES.md`、许可文本、macOS 和 Android 实机播放及官方 iframe
回退。

## 运行边界

- 运行时源基于 YouTube.js、googlevideo 的 SABR 适配思路和 Shaka Player。
- 页面仅从应用内 `127.0.0.1` 服务加载，不开放到局域网。
- YouTube API 和 GoogleVideo 媒体请求经过带随机能力路径的同源代理，以适配
  WKWebView/Android WebView 的跨域限制。
- Dart 代理只允许明确的 YouTube/GoogleVideo HTTPS 域名，媒体响应保持流式
  转发。
- VOD 的 SABR 加载失败时，先在同一个 Shaka 控件内尝试普通自适应 DASH；
  两条自定义链都失败、直播失败或超时后，Flutter 才回退到现有 YouTube
  官方 iframe 播放器。
