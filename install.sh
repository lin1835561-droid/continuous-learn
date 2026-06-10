#!/usr/bin/env bash
# continuous-learn v1.0.0 — 一键安装脚本 (macOS/Linux)
# 用法: curl -fsSL https://raw.ghproxy.com/lin1835561-droid/continuous-learn/main/install.sh | bash

set -e

echo ""
echo "  continuous-learn v1.0.0 — Claude Code 自学习系统"
echo "=============================================="
echo ""

# 检测 Claude Code 目录
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
echo "[1/5] Claude Code 目录: $CLAUDE_DIR"

if [ ! -d "$CLAUDE_DIR" ]; then
    echo "  ❌ 未找到 .claude 目录"
    exit 1
fi

# 创建目录
echo "[2/5] 创建目录结构..."
SKILL_DIR="$CLAUDE_DIR/skills/continuous-learn"
HOOKS_DIR="$CLAUDE_DIR/hooks"
LEARN_DIR="$HOME/.omc/learned"
SESSIONS_DIR="$LEARN_DIR/sessions"

mkdir -p "$SKILL_DIR/hooks" "$SKILL_DIR/templates" "$HOOKS_DIR" "$LEARN_DIR" "$SESSIONS_DIR"
echo "  ✅ 目录就绪"

# 写入 Hook 脚本
echo "[3/5] 写入 Hook 脚本..."

cat > "$HOOKS_DIR/session-logger.js" << 'ENDSCRIPT'
// session-logger.js — PostToolUse hook: 静默记录工具调用
const fs = require('fs');
const path = require('path');
let input = '';
process.stdin.on('data', chunk => input += chunk);
process.stdin.on('end', () => {
  try {
    const data = JSON.parse(input);
    const toolName = data.tool_name || data.tool || '';
    const skip = ['Read','Glob','Grep','AskUserQuestion','TaskList','TaskGet'];
    if (skip.includes(toolName)) return;
    const toolInput = data.tool_input || {};
    let desc = '';
    if (toolInput.description) { desc = toolInput.description.substring(0, 120); }
    else if (toolInput.command) { desc = toolInput.command.substring(0, 120); }
    else if (toolInput.file_path) { desc = path.basename(toolInput.file_path); }
    else { desc = toolName; }
    const entry = { t: new Date().toISOString(), tool: toolName, desc: desc };
    if (toolInput.command) entry.cmd = toolInput.command.substring(0, 200);
    if (toolInput.file_path) entry.file = toolInput.file_path;
    const home = process.env.HOME || process.env.USERPROFILE;
    const logDir = path.join(home, '.omc', 'learned', 'sessions');
    fs.mkdirSync(logDir, { recursive: true });
    const logFile = path.join(logDir, `${new Date().toISOString().slice(0, 10)}.jsonl`);
    fs.appendFileSync(logFile, JSON.stringify(entry) + '\n');
  } catch (e) {}
});
ENDSCRIPT

cat > "$HOOKS_DIR/session-analyzer.js" << 'ENDSCRIPT'
// session-analyzer.js — SessionEnd hook
const fs = require('fs');
const path = require('path');
const home = process.env.HOME || process.env.USERPROFILE;
const logDir = path.join(home, '.omc', 'learned', 'sessions');
const patternsFile = path.join(home, '.omc', 'learned', 'patterns.json');
const flagFile = path.join(home, '.omc', 'learned', '.new-patterns-flag');
try {
  const today = new Date().toISOString().slice(0, 10);
  const logFile = path.join(logDir, `${today}.jsonl`);
  if (!fs.existsSync(logFile)) process.exit(0);
  const raw = fs.readFileSync(logFile, 'utf8').trim();
  if (!raw) process.exit(0);
  const events = raw.split('\n').filter(Boolean).map(l => {
    try { return JSON.parse(l); } catch (e) { return null; }
  }).filter(Boolean);
  if (events.length < 8) process.exit(0);
  let patterns = { version: '1.0', patterns: [], stats: {} };
  if (fs.existsSync(patternsFile)) {
    try { patterns = JSON.parse(fs.readFileSync(patternsFile, 'utf8')); } catch (e) {}
  }
  const existingSigs = new Set(patterns.patterns.map(p => JSON.stringify(p.actions)));
  const signatures = events.map(e => {
    const descShort = (e.desc || '').substring(0, 50).replace(/['"]/g, '');
    return `${e.tool}:${descShort}`;
  });
  const chainFreq = new Map();
  for (let len = 2; len <= 5; len++) {
    for (let i = 0; i <= signatures.length - len; i++) {
      const chain = signatures.slice(i, i + len).join(' → ');
      if (!chainFreq.has(chain)) chainFreq.set(chain, { count: 0, sample: events.slice(i, i + len) });
      chainFreq.get(chain).count++;
    }
  }
  const newPatterns = [];
  let nextId = patterns.patterns.length + 1;
  chainFreq.forEach((info, chainSig) => {
    if (info.count < 2) return;
    if (existingSigs.has(JSON.stringify(chainSig.split(' → ')))) return;
    const steps = chainSig.split(' → ');
    const name = (() => {
      const all = steps.join(' ').toLowerCase();
      if (all.includes('git') && all.includes('commit')) return 'Git提交流程';
      if (all.includes('ssh') && all.includes('restart')) return '远程服务重启';
      if (all.includes('ssh') && all.includes('deploy')) return '远程部署';
      if (all.includes('npm') && all.includes('install')) return '依赖安装';
      return '重复操作序列';
    })();
    newPatterns.push({
      id: `p-${String(nextId).padStart(3, '0')}`, name, domain: 'general',
      trigger: '自动检测', actions: steps, files_affected: [],
      frequency: info.count,
      confidence: Math.max(0.5, Math.min(0.9, 0.5 + info.count * 0.12)),
      first_seen: today, last_seen: today,
      automation_suggestion: `建议固化: /${name.replace(/\s+/g, '-').toLowerCase()}`,
      status: 'identified', auto_captured: true
    });
    nextId++;
  });
  if (newPatterns.length > 0) {
    patterns.patterns.push(...newPatterns);
    patterns.stats.total_patterns_found = patterns.patterns.length;
    patterns.stats.last_analyzed = today;
    fs.writeFileSync(patternsFile, JSON.stringify(patterns, null, 2));
    fs.writeFileSync(flagFile, JSON.stringify({
      count: newPatterns.length, names: newPatterns.map(p => p.name), date: today
    }));
  }
} catch (e) {}
ENDSCRIPT

cat > "$HOOKS_DIR/pattern-reporter.js" << 'ENDSCRIPT'
// pattern-reporter.js — SessionStart hook
const fs = require('fs');
const path = require('path');
const home = process.env.HOME || process.env.USERPROFILE;
const flagFile = path.join(home, '.omc', 'learned', '.new-patterns-flag');
const reportedFile = path.join(home, '.omc', 'learned', '.last-reported');
try {
  if (!fs.existsSync(flagFile)) process.exit(0);
  const flag = JSON.parse(fs.readFileSync(flagFile, 'utf8'));
  let lastReported = '';
  if (fs.existsSync(reportedFile)) lastReported = fs.readFileSync(reportedFile, 'utf8').trim();
  if (lastReported === flag.date) process.exit(0);
  fs.writeFileSync(reportedFile, flag.date);
  const names = flag.names.join('、');
  process.stderr.write(
    `\n[持续学习] 上次会话发现 ${flag.count} 个新模式: ${names}\n` +
    `回复 /learn-review 查看详情，/learn-apply <编号> 固化为技能\n\n`
  );
} catch (e) {}
ENDSCRIPT

echo "  ✅ Hook 脚本已写入"

# 初始化 patterns.json
echo "[4/5] 初始化模式数据库..."
PATTERNS_FILE="$LEARN_DIR/patterns.json"
if [ ! -f "$PATTERNS_FILE" ]; then
    cat > "$PATTERNS_FILE" << 'ENDJSON'
{
  "version": "1.0",
  "patterns": [],
  "stats": {
    "total_sessions_analyzed": 0,
    "total_patterns_found": 0,
    "total_automations_created": 0
  }
}
ENDJSON
    echo "  ✅ patterns.json 已初始化"
else
    echo "  ⏭  patterns.json 已存在，跳过"
fi

echo ""
echo "=============================================="
echo "  ✅ continuous-learn v1.0.0 安装完成！"
echo ""
echo "  请手动在 ~/.claude/settings.json 的 hooks 中添加："
echo "    PostToolUse:   node ~/.claude/hooks/session-logger.js"
echo "    SessionEnd:    node ~/.claude/hooks/session-analyzer.js"
echo "    SessionStart:  node ~/.claude/hooks/pattern-reporter.js"
echo ""
echo "  命令参考:"
echo "    /learn-analyze  — 立即分析"
echo "    /learn-review   — 浏览模式库"
echo "    /learn-apply    — 固化为技能"
echo ""
