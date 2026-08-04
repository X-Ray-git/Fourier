# 迁移

## 包与命名空间迁移

当前 app id 命名空间：

- Android namespace/applicationId：`io.github.xraygit.autofolo`
- macOS bundle id：`io.github.xraygit.autofolo`
- MethodChannel 命名空间：`io.github.xraygit.autofolo/...`

历史 `com.folo.*` 和 `com.autofolo` 引用已经废弃。

原因：

- 避免暗示官方 Folo 命名空间所有权。
- 明确 Auto Folo 是 X-Ray 个人所有/个人使用的软件。

## 设置迁移

设置导入/导出使用剪贴板 JSON 和受控白名单。

当前重要新增设置：

- `appearance_mode`
- `article_content_max_width`
- `macos_max_fling_velocity`
- LLM 配置和 prompt key

已使用的迁移流程：

- 在改变 app identifier 前先加入导出/导入，因为旧包和新包无法自动共享平台存储。
- 用户从旧桌面/移动端 build 导出 JSON，安装迁移后的包，再导入设置。
- 缓存/内容数据刻意不属于设置备份。

## 文章字段迁移

- `ArticleModel.userAction`（`'k'/'m'/'n_keep'/'n_spam'/null`）为本地统计字段，Hive 无 schema，无需数据迁移，缺失时默认 null。
- `upsertMany` 合并策略：`item.userAction ?? existing?.userAction`，网络数据恒为 null，不覆盖本地动作标记。
- 旧版本二进制不认识该字段，任何旧版重写（同步、标已读、undo）都会把它从文章 JSON 中静默剥掉；这是二进制层面的不可修复行为，统计以"有记录即真实信号"为准，不做跨版本数量对齐。

## Android 签名对齐

问题：

- GitHub 构建 APK 和本地 debug APK 最初使用不同签名 key，导致安装冲突。

解决：

- 用户同意通过 GitHub Secrets 使用本地 debug keystore 材料进行内部构建。

重要点：

- Secrets 不在仓库中。
- 单纯提高版本号不能解决签名不匹配。

## Git 历史隐私清理

仓库是公开仓库。过去交接文档中的敏感内容被视为最终应从历史中清理，而不是只从最新文件删除。

重要概念：

- 从当前文件删除 secret，不等于从旧提交删除。
- 重写历史可以让敏感文本看起来从未提交过，但 commit hash 会变化。
- 用户没有协作者，不需要照顾旧 clone 兼容性。
- 执行这类工作时，优先采用只影响敏感文件的定向历史重写。
