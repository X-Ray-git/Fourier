# Android 说明

macOS UI 演进时，Android 必须保持稳定。

当前规则：

- 避免把 macOS 重型 Liquid Glass 渲染引入 Android。
- Android 文章底部间距仍需要给移动端浮动控件留空间。
- package id 已迁移到 `io.github.xraygit.autofolo`。
- 安装签名 key 不同但包名相同的 APK 会和现有安装冲突。本项目的 GitHub 内部构建使用已约定的签名设置。

验证清单：

- 应用可启动，时间线可加载。
- 文章打开过渡可接受。
- 翻译/摘要控件可用。
- 设置导入/导出可用。
- 文章底部内容不会被浮动控件遮住。
