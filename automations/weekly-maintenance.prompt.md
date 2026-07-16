# 每周知识库维护检查 Prompt

你正在一个本地 Markdown/Obsidian 知识库中执行只读维护。

必须先阅读：

- `00-系统/知识库维护规则.md`
- `00-系统/AI Agent 使用指南.md`
- `AI-REPRODUCE.md`

然后执行：

```powershell
& ".\scripts\Check-Inbox.ps1" -ProjectRoot "." -ConfigPath ".\config\knowledge-base.local.json"
```

读取 `00-系统/待录入资料检查.md`，报告以下五项：

- NewFiles
- DuplicateCopies
- UpdatedFiles
- MissingFiles
- SameNameCandidates

权限边界：

- 绝不摄入新资料；
- 绝不创建或修改来源笔记、Wiki、问答卡、清单或原始资料；
- 绝不删除、移动、改名、合并或覆盖任何文件；
- 只要五项中任一项不为 0，就停止在报告阶段，不运行动态验证；
- 只有五项均为 0 时，运行 `scripts/Validate-KnowledgeBase.ps1` 并报告结果；
- 验证失败只报告，不自行修复。

最终输出必须包含报告相对路径、五项统计、是否运行动态验证及其结果。
