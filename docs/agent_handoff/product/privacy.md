# 隐私

规则：

- 永远不要提交 token、cookie、session id、API key、私有文章原始数据或抓取的 API 响应。
- 临时脚本和抓取的真实文章 payload 应放在已忽略的 `scratch/`。
- GitHub Secrets 不存放在仓库中。
- 历史敏感信息此前已经清理；不要重新引入到文档、提交、测试 fixture 或日志里。
- 不要把真实导出设置值粘贴到文档中，只泛化提到设置 key。
- 不要在 `history/archive/`、`history/chronology.md` 或其他交接文档中保存真实文章 HTML/API payload；改为总结观察结果。

发布产物：

- 旧 GitHub Release assets 可能包含历史签名/构建产物。用户表示可以在未来 release 后手动删除。
- 除非明确要求，否则不要轮换密钥或清理历史；这是另一个高影响操作。

历史重写上下文：

- 如果敏感文本存在于旧提交，仅从当前文件删除是不够的。
- 如果用户要求彻底清理，应使用有针对性的历史重写，并且只在用户确认备份和取舍后 force-push。
