# 平台视频播放运行时

此目录包含 Fourier 内嵌 YouTube/Bilibili 播放器的可复现构建源。应用不在
运行时依赖 Node.js；Flutter 只打包 `assets/embed_video_player/` 中的生产
构建产物。

## 构建

```bash
npm ci
npm run typecheck
npm run build
```

构建会固定输出：

- `assets/embed_video_player/index.html`
- `assets/embed_video_player/embed_video_player.js`
- `assets/embed_video_player/embed_video_player.css`

依赖版本由 `package-lock.json` 锁定。更新依赖时必须同步检查
`THIRD_PARTY_NOTICES.md`、许可文本、macOS 和 Android 实机播放及官方 iframe
回退。

## 运行边界

- 运行时源基于 YouTube.js、googlevideo 的 SABR 适配思路和 Shaka Player。
- Bilibili 使用匿名详情、播放地址和字幕接口生成同源 DASH/VTT；媒体仍由
  同一 Shaka 控件播放。弹幕通过 Bilibili 的 6 分钟 Protobuf 分段接口按需
  加载，由 Protobuf-ES 解析并在同一页面 Canvas 内绘制；当前只读，不发送。
- 页面仅从应用内 `127.0.0.1` 服务加载，不开放到局域网。
- YouTube API 和 GoogleVideo 媒体请求经过带随机能力路径的同源代理，以适配
  WKWebView/Android WebView 的跨域限制。
- Dart 代理只允许明确的 YouTube/GoogleVideo HTTPS 域名，媒体响应保持流式
  转发。
- VOD 的 SABR 加载失败时，先在同一个 Shaka 控件内尝试普通自适应 DASH；
  两条自定义链都失败、直播失败或超时后，Flutter 才回退到现有 YouTube
  官方 iframe 播放器。
