# macOS 说明

macOS 是近期 UI 工作的主要验证目标。

当前 UI：

- 分栏：左侧应用侧边栏，中间时间线列表，右侧文章详情。
- macOS 窗口使用透明/full-size content view 和原生 visual effect 背景。
- 红黄绿按钮是 AppKit 标准窗口按钮，只是重新定位以匹配自定义窗口/侧边栏几何。
- 红色关闭应隐藏窗口，而不是退出应用。
- 侧边栏是悬浮圆角面板；它的间距和外侧圆角关系会影响其他 macOS 边缘间距决策。

近期 macOS 专属行为：

- 时间线 header 有 `未读 / 全部` 快速切换。
- 已读文章入口/页面仍然存在，但中间 header 快速切换不包含 `已读`。
- 时间线排序按钮位于同步按钮左侧。
- 即使同步在 widget 订阅前已经开始，同步按钮也应开始旋转。
- 文章图片 hover 不再缩小图片，也不显示边框；可点击图片通过 native channel 使用 macOS zoom-in 光标。
- 中间时间线/列表 header 不再使用玻璃背景；保留分隔线。
- 文章详情 header 暂时保留当前处理，除非用户要求再次调整。
- macOS max fling velocity 是用户可配置项，并应全局应用于 macOS。

验证清单：

- 红黄绿按钮：位置、hover 符号、非激活灰色状态、关闭/最小化/缩放行为。
- 时间线：未读/全部切换、排序菜单、同步旋转。
- 文章详情：工具栏 hover、图片光标、表格渲染、目录行为。
- 设置/任务中心：滚动行为、轻量面板、没有重复 scrollbar。

已知坑：

- 除非有强理由，否则不要用自绘 Flutter/AppKit 按钮替代系统红黄绿按钮；自绘版本曾无法正确处理 hover/非激活/zoom 语义。
- 本地 macOS release 构建可能因为签名/framework 原因失败；本地 UI 验证使用 debug build。
- 如果 `flutter run -d macos` 看似卡住，先检查 debug 日志量或 foregrounding 问题，不要直接归因于应用启动失败。
- AppKit 窗口几何变化可能被仍在运行的应用缓存。验证红黄绿按钮位置前应完全退出应用。
