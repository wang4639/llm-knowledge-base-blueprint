# AI Agent 从零复现协议

> 如果你是接手此仓库的 AI Agent：先完整阅读本文，再执行任何写入。你的目标是复现机制，不是替使用者预填知识。

## 1. 完成标准

只有以下条件全部满足，才算复现完成：

1. 五层目录和系统文件齐全；
2. 使用者已在本地配置至少一个资料根目录和至少一个板块；
3. 一份虚构或用户明确授权的资料能完成“检测→来源笔记→Wiki→问答卡→清单→复检”；
4. 问答默认走 `总索引→板块→问答索引→问答卡→必要时来源`；
5. 只读维护与受限摄入职责分离；
6. 动态验证从当前清单推导数量，不依赖某个固定历史基线；
7. 无密钥、Cookie、私人路径或未经授权资料进入 Git。

## 2. 启动前必须确认

- 操作系统能运行 Windows PowerShell 5.1 或 PowerShell 7；
- 当前目录是本仓库根目录；
- `config/knowledge-base.local.json` 不会被 Git 跟踪；
- 资料根目录由使用者明确授权，原文件始终只读；
- 不读取、不移动、不改名、不删除资料根目录中的文件；
- 不把 Horizon、RAG、数据库或模型 API 当作本版本的必要组件。

## 3. 初始化

若本地配置不存在：

```powershell
Copy-Item ".\config\knowledge-base.example.json" ".\config\knowledge-base.local.json"
```

请让使用者在本地配置中填写：

- `source_roots`：一个或多个被授权的 Markdown 资料目录；
- `boards`：允许使用的知识板块；
- `max_batch_size`：默认 30，不得自动调大；
- `source_note_prefix`：默认 `10-来源笔记`。

然后运行：

```powershell
& ".\scripts\Initialize-KnowledgeBase.ps1" -ProjectRoot "." -ConfigPath ".\config\knowledge-base.local.json"
& ".\scripts\Validate-KnowledgeBase.ps1" -ProjectRoot "." -ConfigPath ".\config\knowledge-base.local.json"
```

初始化器只创建缺失目录和初始文件；发现同名非空文件时不得覆盖。

## 4. 新资料检测

```powershell
& ".\scripts\Check-Inbox.ps1" -ProjectRoot "." -ConfigPath ".\config\knowledge-base.local.json"
```

必须报告五项：

- `NewFiles`
- `DuplicateCopies`
- `UpdatedFiles`
- `MissingFiles`
- `SameNameCandidates`

只读维护任务只要发现任一项不为 0，就停止在报告阶段，不做语义摄入或修复。

## 5. 单份摄入协议

只有专用摄入任务可以继续，并且必须满足：

- `NewFiles` 为 1–30；
- 其余四项均为 0；
- 文件可完整读取，处理前后 SHA256 不变；
- 能映射到一个明确板块；
- 来源笔记目标不存在；
- 没有冲突或需要覆盖的旧内容。

对每份资料执行：

1. 使用 `00-系统/模板/来源笔记模板.md` 创建来源笔记；
2. 把事实、来源观点、AI 概括和 AI 推断分开；
3. “我的理解”和“我的评价”保持空白；
4. 优先更新现有 Wiki，无法承载时才新建页面；
5. 检查现有问答卡，标记 `无影响/强化/补充/冲突/推翻`；
6. 更新板块 `index.md`，向 `log.md` 追加记录；
7. 调用注册工具追加清单，不改写旧行；
8. 再次检查资料差异并运行动态验证；
9. 在 `90-维护报告` 写入脱敏的摄入结果。

注册示例：

```powershell
& ".\scripts\Register-IngestedSource.ps1" `
  -ProjectRoot "." `
  -ConfigPath ".\config\knowledge-base.local.json" `
  -SourceRootId "inbox" `
  -RelativePath "示例资料.md" `
  -Board "示例板块" `
  -SourceNote "10-来源笔记/示例板块/示例资料.md" `
  -Wiki "20-Wiki/示例板块/主题/示例主题.md"
```

## 6. 问答协议

任何日常问答都按以下顺序：

```text
根目录 index.md
→ 20-Wiki/<板块>/index.md
→ 问答索引.md
→ 问题与假设/<卡片>.md
→ 只有证据不足、存在冲突或用户明确要求时读取 1–3 份来源笔记
```

禁止默认扫描全部 `10-来源笔记`。若本地材料不足，明确说明不足，不用模型记忆补成“知识库结论”。

## 7. 自动化复现

为使用者的调度平台创建两个任务：

1. 每周维护：使用 `automations/weekly-maintenance.prompt.md`，只读、只报告；
2. 每周摄入：使用 `automations/weekly-ingestion.prompt.md`，最多 30 份，逐项记录并在任何异常时停止。

不要复制模板作者的任务 ID、模型名、电脑路径或执行环境。调度时间由使用者决定。

## 8. 验收

```powershell
& ".\tests\Test-KnowledgeBase.ps1" -ProjectRoot "."
& ".\tests\Test-PublicRelease.ps1" -ProjectRoot "."
```

未出现两个成功签名时，不得声称系统已复现或可公开发布。
