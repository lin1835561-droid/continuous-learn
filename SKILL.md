---
name: continuous-learn
description: >
  Claude Code 自学习系统。静默观察你的操作习惯，自动发现重复工作流，
  一键固化为技能/脚本。零配置，安装即忘，自动汇报。
  GitHub: (你的仓库地址)
  Version: 1.0.0
author: Jay Liu (佳龙科技)
license: MIT
tags: [automation, workflow, self-learning, productivity, patterns]
triggers:
  - "分析我的工作习惯"
  - "有什么可以自动化的"
  - "learn my patterns"
  - "建议自动化"
  - "我经常做什么"
  - "帮我看看哪些操作可以自动化"
  - "/learn-analyze"
  - "/learn-review"
  - "/learn-apply"
---

# continuous-learn — 轻量自学习系统

## 一句话

**安装即忘。** 系统静默观察你的 Claude Code 操作，自动发现重复工作流，下次开会话主动汇报。你只需回复一句"帮我自动化这个"。

## 架构

```
你正常干活（零感知）
       │
       ▼
PostToolUse → session-logger.js  → .omc/learned/sessions/{date}.jsonl
       │
       ▼
SessionEnd  → session-analyzer.js → 检测重复链 → 更新 patterns.json → 写标记
       │
       ▼
SessionStart→ pattern-reporter.js → "上次发现 3 个新模式，回复 /learn-review 查看"
       │
       ▼
你回复 /learn-apply p-003 → 自动生成 Skill 脚本，固化完成
```

## 三个自动 Hook

| Hook | 触发点 | 脚本 | 功能 |
|------|--------|------|------|
| 采集器 | PostToolUse | `hooks/session-logger.js` | 记录每次有副作用的工具调用（跳过 Read/Glob/Grep） |
| 分析器 | SessionEnd | `hooks/session-analyzer.js` | 检测重复命令链（2-5步）+ 高频单操作 |
| 汇报器 | SessionStart | `hooks/pattern-reporter.js` | 从上次分析结果中提取新模式并展示 |

## 三个斜杠命令

### `/learn-analyze` — 立即分析
手动触发一次完整分析。扫描当前会话 + claude-mem 历史 + notepad 工作记忆。
输出格式：
```
📊 会话分析报告
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🆕 新发现模式：2 个
📈 已有模式更新：1 个
⚡ 可立即自动化：3 个
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. [tuoguan] 托管系统部署 (confidence: 95%)
   触发: 代码改完 → git push → SSH 重启
   → 建议: /tuoguan-deploy 一键部署
2. ...
```

### `/learn-review` — 浏览模式库
读取 `patterns.json`，按置信度排序显示所有已识别模式。
每个模式提供 4 个选项：
1. 固化为 OMC Skill
2. 固化为独立脚本
3. 写入 CLAUDE.md 指令
4. 忽略（不再提示）

### `/learn-apply <pattern-id>` — 固化为技能
读取指定 pattern，自动生成对应的 Skill 文件并写入 `.claude/skills/`。

## 数据存储

```
.omc/learned/
├── patterns.json              # 模式数据库（手动+自动）
├── sessions/
│   ├── 2026-06-10.jsonl       # 每日操作日志（30天清理）
│   └── ...
├── .new-patterns-flag         # 新发现标记（内部用）
└── .last-reported             # 上次汇报日期（防重复）
```

### Pattern Schema

```json
{
  "id": "p-001",
  "name": "简短描述",
  "domain": "tuoguan|electrical|general",
  "trigger": "什么场景触发",
  "actions": ["步骤1", "步骤2"],
  "files_affected": ["涉及路径"],
  "frequency": 5,
  "confidence": 0.95,
  "first_seen": "2026-06-10",
  "last_seen": "2026-06-10",
  "automation_suggestion": "建议固化方案",
  "status": "identified|confirmed|automated|archived|ignored"
}
```

### 状态流转
```
identified → confirmed → automated → archived
                  ↓
              ignored (不再提示)
```

## 检测算法

### 重复命令链
- 滑窗提取 2-5 步连续操作
- 同一次会话出现 ≥2 次 → 记录
- 过滤只读操作（Read/Glob/Grep/AskUserQuestion）

### 高频单操作
- 同一次会话出现 ≥3 次
- 跳过查询类工具

### 领域自动分类
- 文件路径含 `tuoguan`/`托管` → tuoguan
- 含 `dxf`/`plc`/`hmi`/`电气` → electrical
- 其他 → general

## 安装

### Windows (PowerShell)
```powershell
irm https://raw.ghproxy.com/lin1835561-droid/continuous-learn/main/install.ps1 | iex
```

### macOS/Linux
```bash
curl -fsSL https://raw.ghproxy.com/lin1835561-droid/continuous-learn/main/install.sh | bash
```

### 手动安装
1. 复制 `hooks/*.js` 到 `~/.claude/hooks/`
2. 复制 `templates/patterns.json` 到 `~/.omc/learned/`
3. 在 `~/.claude/settings.json` 的 `hooks` 中添加 PostToolUse、SessionEnd、SessionStart 条目（见 `install.ps1`）

## 依赖

- Node.js（运行 hook 脚本）
- Claude Code（目标平台）
- 可选：oh-my-claudecode（OMC，与 /learn-apply 联动）
- 可选：claude-mem（跨会话记忆增强）

## 配置

无需配置。安装即用。

环境变量（可选）：
- `CONTINUOUS_LEARN_DEBUG=1` — 开启调试日志

## 对比 ECC 持续学习模块

| | ECC | continuous-learn |
|---|---|---|
| 触发方式 | hook 全自动 | hook 全自动 |
| 存储 | ECC 运行时耦合 | 裸 JSON + JSONL |
| 技能数 | 261 个（完整 ECC） | 1 个 Skill，3 个 Hook |
| 依赖 | ECC 全套 | Node.js only |
| 冲突 | 与 OMC 完全冲突 | 与 OMC 互补 |
| 安装 | 复杂（依赖 ECC 运行时） | 一行命令 |

## 定价建议

- GitHub 开源免费（MIT License）
- 可提供付费高级版：多项目管理、团队模式共享、可视化面板、Slack/飞书通知

## 边界规则

- 不存储敏感信息（密码、token、密钥）
- 单次出现的操作不记录（frequency ≥ 2）
- 忽略的模式不再提示
- 30 天自动清理操作日志
- patterns.json 保持干净，定期归档旧条目
