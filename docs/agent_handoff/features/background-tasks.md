# 后台任务

任务中心是 macOS 上可见的后台任务管理界面，用于展示正在进行或排队中的工作。

## 当前设计

- 应和设置页共享同一种轻量面板语言。
- 列表内部避免密集 Liquid Glass 表面；使用简单描边和微弱 hover 状态。
- 作为 overlay 打开时，背景应保证可读。
- Scrollbar 不应造成左右 padding 不对称或出现重复条。

## 交互注意点

- 如果 overlay 更能保留上下文，任务中心可以作为 overlay 打开，而不是完整跳转页面。
- “去审核”等操作应符合当前 macOS 控件语言，不要使用旧的移动端按钮样式。
- 如果某个操作被刻意隐藏或移除，应记录产品原因；否则把它当作 bug。

## 相关页面

- `features/settings.md`
- `design/macos-ui.md`
- `design/liquid-glass.md`
