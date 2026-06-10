# continuous-learn — Claude Code 自学习系统

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform: Claude Code](https://img.shields.io/badge/Platform-Claude%20Code-blue)](https://claude.ai/code)
[![Version](https://img.shields.io/badge/version-1.0.0-green)]()

> **安装即忘。** Claude Code 静默观察你的操作习惯，自动发现重复工作流，下次开会话主动汇报。你只需回复一句"帮我自动化这个"。

## 🎯 解决的问题

你用 Claude Code 干活，总有一些操作反复做：
- 改完代码 → `git commit` → `git push` → SSH 重启服务器
- 搜 GitHub 技能 → 分析 README → 手动复制安装
- 电气截图 → 分析 → ezdxf 生成 DXF

**每次都手动？系统应该学会。**

continuous-learn 三个 Hook 静默运行，自动采集 → 分析 → 汇报。你正常干活，它自己学习。

## ⚡ 快速开始

### Windows
```powershell
# 国内用户（ghproxy 加速）
irm https://raw.ghproxy.com/lin1835561-droid/continuous-learn/main/install.ps1 | iex

# 国际用户（直连 GitHub）
irm https://raw.githubusercontent.com/lin1835561-droid/continuous-learn/main/install.ps1 | iex
```

### macOS / Linux
```bash
# 国内用户（ghproxy 加速）
curl -fsSL https://raw.ghproxy.com/lin1835561-droid/continuous-learn/main/install.sh | bash

# 国际用户（直连 GitHub）
curl -fsSL https://raw.githubusercontent.com/lin1835561-droid/continuous-learn/main/install.sh | bash
```

**安装完成。** 没有下一步。下次会话开始时，它自己会来找你。

## 📖 怎么用

### 1. 正常干活（零操作）
你的每次工具调用被静默记录到 `.omc/learned/sessions/`。跳过只读操作。

### 2. 等它找你
过几次会话后，开新会话时看到：
```
[持续学习] 上次会话发现 3 个新模式: Git提交推送, 远程部署, DXF生成
回复 /learn-review 查看详情，/learn-apply <编号> 固化为技能
```

### 3. 三个命令
| 命令 | 作用 |
|------|------|
| `/learn-analyze` | 立刻分析当前会话 + 历史记忆 |
| `/learn-review` | 浏览所有已发现的模式 |
| `/learn-apply p-002` | 把指定模式固化为 Skill |

## 🏗 架构

```
PostToolUse → session-logger.js  → .omc/learned/sessions/{date}.jsonl
SessionEnd  → session-analyzer.js → 检测重复链 → patterns.json
SessionStart→ pattern-reporter.js → 汇报新模式
```

三个轻量 Node.js Hook，不依赖任何框架。与 OMC、claude-mem 互补不冲突。

## 📊 检测什么

- **重复命令链**：2-5 步连续操作在同一会话出现 ≥2 次
- **高频单操作**：同一操作出现 ≥3 次
- **跨会话模式**：配合 claude-mem 查证历史

## 📁 文件结构

```
continuous-learn/
├── SKILL.md                    # 技能定义（给 Claude Code 看的）
├── README.md                   # 本文件（给人看的）
├── install.ps1                 # Windows 一键安装
├── install.sh                  # macOS/Linux 一键安装
├── hooks/
│   ├── session-logger.js       # PostToolUse：采集器
│   ├── session-analyzer.js     # SessionEnd：分析器
│   └── pattern-reporter.js     # SessionStart：汇报器
└── templates/
    └── patterns.json           # 初始模式库模板
```

## 🔧 依赖

- **Node.js** — 运行 Hook 脚本
- **Claude Code** — 目标平台
- *(可选)* oh-my-claudecode — 与 `/learn-apply` 联动
- *(可选)* claude-mem — 跨会话记忆增强

## 🆚 对比

| | ECC 持续学习 | continuous-learn |
|---|---|---|
| 文件数 | 261 个 Skill + 运行时 | 1 个 Skill + 3 个 Hook |
| 耦合度 | 依赖 ECC 完整运行时 | 零依赖（仅 Node.js） |
| 安装 | 复杂（需 ECC 生态） | 一行命令 |
| OMC 兼容 | ❌ 完全冲突 | ✅ 互补 |
| 代码量 | 数万行 | ~300 行 |

## 🛣 路线图

- [ ] 多项目管理（工作区间模式隔离）
- [ ] 可视化面板（Web UI 查看模式积累）
- [ ] 团队共享（导出/导入模式库）
- [ ] 通知集成（飞书/Slack/钉钉）
- [ ] 自动生成模式报告 PDF

## 📄 许可

MIT License © 2026 Jay Liu

---

*Built for makers who repeat themselves. Let Claude Code learn your flow.*
