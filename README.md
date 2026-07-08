# Auto Folo — Folo RSS 阅读器

<p align="center">
  <img src="assets/readme-icon.png" alt="Auto Folo" width="256">
</p>

基于 Flutter 的 Folo RSS 聚合阅读客户端，支持 Android 和 macOS。聚焦高密度信息流阅读：同步 Folo 未读、按源筛选、逐块渲染长文，并用 DeepSeek 完成自动翻译和摘要。

> Auto Folo 是个人用途的非官方二次开发客户端，不隶属于 Folo、RSSNext 或其运营方，也不代表官方发布版本。

## 主要功能

- **时间线** — 未读 / 全部 / 已读三态视图，无限滚动，macOS 分栏阅读
- **订阅源** — view → 分类 → 订阅源三级分组，搜索，按源筛选
- **文章阅读** — DOM 拆块懒渲染，图片画廊 + 手势缩放，视频播放
- **已读同步** — 本地 + Folo 云端双向同步
- **AI 翻译** — DeepSeek 逐篇翻译（保留 HTML 结构），可按订阅源开关
- **AI 摘要** — DeepSeek 一句话摘要，后台自动队列
- **桌面体验** — macOS 原生分栏布局、键盘快捷键、同步状态反馈

## 快速开始

```bash
flutter pub get
flutter run
```

构建桌面版：

```bash
flutter build macos --release
```

## 首次配置

1. 打开应用 → 设置页
2. 填写 **Folo API 凭据**（Session Token / Client ID / Session ID）— 从 Folo Web 应用的 Cookie 中获取
3. 填写 **DeepSeek API Key**（翻译和摘要功能需要）

## 开发

```bash
flutter run          # 调试运行
flutter test         # 运行测试
```

## 文档

- 功能演进与实现细节详见 [`AGENT_HANDOFF.md`](AGENT_HANDOFF.md)
