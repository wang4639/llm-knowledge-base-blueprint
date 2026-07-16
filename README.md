# LLM 知识库蓝图

一套可以被 AI Agent 直接接手、完全本地运行、以 Markdown/Obsidian 为核心的个人知识库模板。

本仓库公开的是知识库的**运行机制**，不是作者的私人知识。仓库不包含原作者的来源资料、已摄入知识、个人笔记、维护历史、Cookie、API Key 或本机配置。

> English summary: A privacy-safe, Markdown-native blueprint for building and maintaining an AI-operable personal knowledge base without shipping the author's private corpus.

## 它解决什么问题

- 把原始资料转成可追溯的结构化来源笔记；
- 把多个来源编译成 Wiki、主题页和问答卡；
- 回答问题时优先走 Wiki/问答卡，不默认全文扫描所有来源；
- 新资料进入后检查它是强化、补充、冲突还是推翻现有结论；
- 用“只读维护”和“受限摄入”两条自动化分离检查与写入权限；
- 用确定性脚本检测新增、重复、更新、缺失和同名候选；
- 所有真实资料、模型选择和 API Key 都留在使用者自己的本地环境。

## 五层结构

```text
00-系统/       规则、模板、清单和 Agent 指令
10-来源笔记/   单份资料的结构化记录与证据入口
20-Wiki/       跨来源编译后的主题、概念、索引和问答卡
30-输出/       文章、方案、决策记录等可复用成品
90-维护报告/   健康检查、冲突和摄入报告
```

默认问答路径：

```text
根目录 index.md
  → 20-Wiki/<板块>/index.md
  → 问答索引.md
  → 问题与假设/<问答卡>.md
  → 仅在核验、冲突或用户要求溯源时读取少量来源笔记
```

## 快速开始

运行环境：Windows PowerShell 5.1 或 PowerShell 7；无第三方依赖。

```powershell
Copy-Item ".\config\knowledge-base.example.json" ".\config\knowledge-base.local.json"
& ".\scripts\Initialize-KnowledgeBase.ps1" -ProjectRoot "." -ConfigPath ".\config\knowledge-base.local.json"
& ".\scripts\Validate-KnowledgeBase.ps1" -ProjectRoot "." -ConfigPath ".\config\knowledge-base.local.json"
```

然后让 AI Agent 完整阅读根目录 [`AI-REPRODUCE.md`](AI-REPRODUCE.md)，按其中协议配置资料入口、板块和自动化。

## 自动化

- `automations/weekly-maintenance.prompt.md`：只读检查；出现任一差异就只报告。
- `automations/weekly-ingestion.prompt.md`：只有新资料为 1–30 且其他四项为 0 时才允许受限摄入。

两份文件是调度器无关的运行规范。模型名称、任务 ID 和本机路径由使用者自行配置，不写进公开模板。

## 验证

```powershell
& ".\tests\Test-KnowledgeBase.ps1" -ProjectRoot "."
& ".\tests\Test-PublicRelease.ps1" -ProjectRoot "."
```

成功签名应分别为：

- `ALL_TESTS_PASSED`
- `PUBLIC_RELEASE_SCAN_PASSED`

测试只使用纯虚构资料，在新的临时沙盒中运行，不读取或修改使用者的真实知识库。

## 隐私边界

- 仓库不需要任何 API Key；
- 真实资料根目录只写入被 Git 忽略的 `config/knowledge-base.local.json`；
- 不提交 `.env`、Cookie、Token、私钥、数据库、日志或运行报告；
- 原始资料保持只读；删除、移动、覆盖和合并都不属于自动维护权限；
- 发布前运行秘密、本机路径、隐私目录和 Horizon 实现扫描。

详见 [`docs/security-and-privacy.md`](docs/security-and-privacy.md)。

## Horizon 边界

本版本不包含 Horizon 的代码、配置、数据、Cookie、密钥、日报或自动化。若使用者未来需要外部信息雷达，只提供接口方向，参见 [`docs/optional-information-radar.md`](docs/optional-information-radar.md)。

## 作者与许可证

原始蓝图与公开实现作者：[`wang4639`](https://github.com/wang4639)。

本项目采用 Apache License 2.0。再分发或创建衍生版本时，应遵守 [`LICENSE`](LICENSE) 并保留 [`NOTICE`](NOTICE) 中适用的作者归属信息。正确引用方式见 [`CITATION.cff`](CITATION.cff)。

许可证不能垄断抽象思想，也不能从技术上阻止恶意抄袭；它与 Git 提交、版本标签、GitHub 首发时间和作者元数据共同构成可追溯的原创证据链。
