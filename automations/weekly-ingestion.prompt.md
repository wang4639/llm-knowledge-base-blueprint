# 每周知识库增量摄入 Prompt

你正在一个本地 Markdown/Obsidian 知识库中执行受限增量摄入。

必须先阅读：

- `00-系统/自动增量摄入运行规则.md`
- `00-系统/知识库维护规则.md`
- `00-系统/AI Agent 使用指南.md`
- `00-系统/模板/来源笔记模板.md`
- `AI-REPRODUCE.md`

先运行：

```powershell
& ".\scripts\Check-Inbox.ps1" -ProjectRoot "." -ConfigPath ".\config\knowledge-base.local.json"
```

只有 `NewFiles` 为 1–30，且 `DuplicateCopies`、`UpdatedFiles`、`MissingFiles`、`SameNameCandidates` 全部为 0 时，才按规则逐份摄入。新资料为 0 时只运行动态验证。超过 30 或出现任何其他差异时不摄入，只报告原因。

每份资料必须：

1. 处理前后 SHA256 不变；
2. 映射到一个配置允许的板块；
3. 使用模板创建不存在的来源笔记；
4. 区分来源事实、来源观点、AI 概括和 AI 推断；
5. 保持“我的理解”和“我的评价”为空，不自动设 `evergreen`；
6. 更新关联 Wiki、板块 index 和只追加 log；
7. 检查问答卡关系：无影响、强化、补充、冲突或推翻；
8. 用 `Register-IngestedSource.ps1` 追加清单；
9. 再次运行差异检查和动态验证；
10. 写入脱敏维护报告。

出现无法分类、无法读取、哈希变化、目标存在、内容冲突、注册失败或验证失败时，停止本次余下资料，不覆盖或自行修复旧内容。

最终输出必须逐项列出：根目录 ID、原始相对路径、板块、来源笔记、Wiki 页面、问答卡影响关系、状态、风险、维护报告路径和动态验证结果。不得输出绝对资料路径或完整 SHA256；报告最多显示哈希前 12 位。
