# 后台任务

任务中心在 macOS 和 Android 上都可见，用于展示正在进行或排队中的工作。

## 当前设计

- 应和设置页共享同一种轻量面板语言。
- 列表内部避免密集 Liquid Glass 表面；使用简单描边和微弱 hover 状态。
- 作为 overlay 打开时，背景应保证可读。
- Scrollbar 不应造成左右 padding 不对称或出现重复条。
- Android 保持设置页进入的二级页面，使用 `MobileBlurAppBar`、`12px` 页面边距和 `MobileSettingsPanel` 轻量外壳。AI 失败记录继续作为下一级页面；不要用旧式透明 Card 或密集实时玻璃重做。

## 交互注意点

- macOS 如需保留上下文可以继续使用 overlay；Android 已确认采用完整二级页面，不应为了跨平台形式一致强行改成 overlay。
- “去审核”等操作应符合当前 macOS 控件语言，不要使用旧的移动端按钮样式。
- 如果某个操作被刻意隐藏或移除，应记录产品原因；否则把它当作 bug。

## 相关页面

- `features/settings.md`
- `design/macos-ui.md`
- `design/liquid-glass.md`
