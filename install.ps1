# continuous-learn v1.0.0 — 一键安装脚本 (Windows PowerShell)
# 用法: irm https://raw.ghproxy.com/lin1835561-droid/continuous-learn/main/install.ps1 | iex

$ErrorActionPreference = "Stop"
Write-Host "`n  continuous-learn v1.0.0 — Claude Code 自学习系统" -ForegroundColor Cyan
Write-Host "==============================================`n" -ForegroundColor Cyan

# 1. 检测 Claude Code 配置目录
$ClaudeDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME ".claude" }
Write-Host "[1/5] Claude Code 目录: $ClaudeDir" -ForegroundColor Gray

if (-not (Test-Path $ClaudeDir)) {
    Write-Host "  ❌ 未找到 .claude 目录，请先安装 Claude Code" -ForegroundColor Red
    exit 1
}

# 2. 创建目录结构
Write-Host "[2/5] 创建目录结构..." -ForegroundColor Gray
$SkillDir = Join-Path $ClaudeDir "skills\continuous-learn"
$HooksDir = Join-Path $ClaudeDir "hooks"
$LearnDir = Join-Path $HOME ".omc\learned"
$SessionsDir = Join-Path $LearnDir "sessions"
$TemplatesDir = Join-Path $SkillDir "templates"

$dirs = @($SkillDir, (Join-Path $SkillDir "hooks"), $TemplatesDir, $HooksDir, $LearnDir, $SessionsDir)
foreach ($d in $dirs) {
    if (-not (Test-Path $d)) {
        New-Item -ItemType Directory -Force -Path $d | Out-Null
    }
}
Write-Host "  ✅ 目录就绪" -ForegroundColor Green

# 3. 写入文件
Write-Host "[3/5] 写入 Hook 脚本..." -ForegroundColor Gray

# session-logger.js
@'
// session-logger.js — PostToolUse hook: 静默记录工具调用
const fs = require('fs');
const path = require('path');

let input = '';
process.stdin.on('data', chunk => input += chunk);
process.stdin.on('end', () => {
  try {
    const data = JSON.parse(input);
    const toolName = data.tool_name || data.tool || '';
    const skip = ['Read','Glob','Grep','AskUserQuestion','TaskList','TaskGet',
                  'CronList','NotebookEdit','lsp_diagnostics','lsp_hover',
                  'lsp_document_symbols','lsp_find_references','lsp_goto_definition'];
    if (skip.includes(toolName)) return;

    const toolInput = data.tool_input || {};
    let desc = '';
    if (toolInput.description) { desc = toolInput.description.substring(0, 120); }
    else if (toolInput.command) { desc = toolInput.command.substring(0, 120); }
    else if (toolInput.file_path) { desc = path.basename(toolInput.file_path); }
    else if (toolInput.pattern) { desc = toolInput.pattern.substring(0, 60); }
    else { desc = toolName; }

    const entry = { t: new Date().toISOString(), tool: toolName, desc: desc };
    if (toolInput.command) entry.cmd = toolInput.command.substring(0, 200);
    if (toolInput.file_path) entry.file = toolInput.file_path;

    const logDir = path.join(process.env.HOME || process.env.USERPROFILE, '.omc', 'learned', 'sessions');
    fs.mkdirSync(logDir, { recursive: true });
    const logFile = path.join(logDir, `${new Date().toISOString().slice(0, 10)}.jsonl`);
    fs.appendFileSync(logFile, JSON.stringify(entry) + '\n');
  } catch (e) {}
});
'@ | Out-File -FilePath (Join-Path $HooksDir "session-logger.js") -Encoding utf8

# session-analyzer.js
@'
// session-analyzer.js — SessionEnd hook: 分析会话日志,检测重复模式
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
    const name = generateName(steps, info.sample);
    newPatterns.push({
      id: `p-${String(nextId).padStart(3, '0')}`, name,
      domain: guessDomain(steps, info.sample),
      trigger: '自动检测（重复命令链）', actions: steps,
      files_affected: [...new Set(info.sample.map(e => e.file).filter(Boolean))],
      frequency: info.count,
      confidence: Math.max(0.5, Math.min(0.9, 0.5 + info.count * 0.12)),
      first_seen: today, last_seen: today,
      automation_suggestion: `建议固化: /${name.replace(/\s+/g, '-').toLowerCase()}`,
      status: 'identified', auto_captured: true
    });
    nextId++;
  });

  const singleFreq = new Map();
  signatures.forEach(s => singleFreq.set(s, (singleFreq.get(s) || 0) + 1));
  singleFreq.forEach((count, sig) => {
    if (count < 3) return;
    if (existingSigs.has(JSON.stringify([sig]))) return;
    const [tool, desc] = sig.split(':');
    newPatterns.push({
      id: `p-${String(nextId).padStart(3, '0')}`, name: desc || `${tool} 高频操作`,
      domain: 'general', trigger: `自动检测（单会话高频: ${count}次）`, actions: [sig],
      files_affected: [], frequency: count,
      confidence: Math.max(0.5, Math.min(0.8, 0.4 + count * 0.1)),
      first_seen: today, last_seen: today,
      automation_suggestion: `是否将"${desc}"固化为快捷命令？`,
      status: 'identified', auto_captured: true
    });
    nextId++;
  });

  if (newPatterns.length > 0) {
    patterns.patterns.push(...newPatterns);
    patterns.stats = patterns.stats || {};
    patterns.stats.total_patterns_found = patterns.patterns.length;
    patterns.stats.last_analyzed = today;
    patterns.stats.total_sessions_analyzed = (patterns.stats.total_sessions_analyzed || 0) + 1;
    fs.writeFileSync(patternsFile, JSON.stringify(patterns, null, 2));
    fs.writeFileSync(flagFile, JSON.stringify({
      count: newPatterns.length, names: newPatterns.map(p => p.name), date: today
    }));
  }

  const thirtyDaysAgo = new Date(Date.now() - 30 * 86400000);
  try {
    fs.readdirSync(logDir).forEach(f => {
      if (!f.endsWith('.jsonl')) return;
      if (f.replace('.jsonl', '') < thirtyDaysAgo.toISOString().slice(0, 10)) {
        fs.unlinkSync(path.join(logDir, f));
      }
    });
  } catch (e) {}
} catch (e) {}

function generateName(steps, sample) {
  const all = steps.join(' ').toLowerCase() + sample.map(e => (e.desc || '')).join(' ').toLowerCase();
  if (all.includes('git') && all.includes('commit') && all.includes('push')) return 'Git提交推送';
  if (all.includes('git') && all.includes('commit')) return 'Git提交';
  if (all.includes('git') && all.includes('push')) return 'Git推送';
  if (all.includes('ssh') && all.includes('restart')) return '远程服务重启';
  if (all.includes('ssh') && all.includes('deploy')) return '远程部署';
  if (all.includes('ssh')) return 'SSH远程操作';
  if (all.includes('npm') && all.includes('install')) return '依赖安装';
  if (all.includes('npm') && all.includes('test')) return '测试执行';
  if (all.includes('pip') && all.includes('install')) return 'Python包安装';
  if (all.includes('edit') || all.includes('write')) return '文件编辑';
  if (all.includes('deploy') || all.includes('部署')) return '部署流程';
  if (all.includes('dxf')) return 'DXF生成';
  return '重复操作序列';
}

function guessDomain(steps, sample) {
  const all = steps.join(' ').toLowerCase() + sample.map(e => (e.file || '') + (e.desc || '')).join(' ').toLowerCase();
  if (all.includes('tuoguan') || all.includes('托管')) return 'tuoguan';
  if (all.includes('dxf') || all.includes('plc') || all.includes('hmi') || all.includes('电气')) return 'electrical';
  return 'general';
}
'@ | Out-File -FilePath (Join-Path $HooksDir "session-analyzer.js") -Encoding utf8

# pattern-reporter.js
@'
// pattern-reporter.js — SessionStart hook: 汇报新发现的模式
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
'@ | Out-File -FilePath (Join-Path $HooksDir "pattern-reporter.js") -Encoding utf8

Write-Host "  ✅ Hook 脚本已写入" -ForegroundColor Green

# 4. 初始化 patterns.json（如果不存在）
Write-Host "[4/5] 初始化模式数据库..." -ForegroundColor Gray
$PatternsFile = Join-Path $LearnDir "patterns.json"
if (-not (Test-Path $PatternsFile)) {
    @'
{
  "version": "1.0",
  "created": "__DATE__",
  "patterns": [],
  "stats": {
    "total_sessions_analyzed": 0,
    "total_patterns_found": 0,
    "total_automations_created": 0
  }
}
'@ -replace '__DATE__', (Get-Date -Format 'yyyy-MM-dd') | Out-File -FilePath $PatternsFile -Encoding utf8
    Write-Host "  ✅ patterns.json 已初始化" -ForegroundColor Green
} else {
    Write-Host "  ⏭  patterns.json 已存在，跳过" -ForegroundColor Gray
}

# 5. 注册 Hooks 到 settings.json
Write-Host "[5/5] 注册 Hook 到 settings.json..." -ForegroundColor Gray
$SettingsFile = Join-Path $ClaudeDir "settings.json"

if (-not (Test-Path $SettingsFile)) {
    Write-Host "  ❌ settings.json 不存在，请手动添加 Hook 配置" -ForegroundColor Red
    Write-Host "     参考: https://github.com/lin1835561-droid/continuous-learn#manual-install" -ForegroundColor Yellow
    exit 1
}

$Settings = Get-Content $SettingsFile -Raw | ConvertFrom-Json

# 确保 hooks 对象存在
if (-not $Settings.hooks) {
    $Settings | Add-Member -MemberType NoteProperty -Name 'hooks' -Value @{}
}

$NodeExe = "C:\Program Files\nodejs\node.exe"

# 添加 PostToolUse hook
if (-not ($Settings.hooks.PostToolUse | Where-Object { $_.hooks.command -like "*session-logger*" })) {
    $hook = @{
        hooks = @(@{
            async = $true
            command = "& `"$NodeExe`" `"$HooksDir\session-logger.js`"" -replace '\\', '\\'
            shell = "powershell"
            timeout = 10
            type = "command"
        })
        matcher = ""
    }
    if (-not $Settings.hooks.PostToolUse) { $Settings.hooks | Add-Member -MemberType NoteProperty -Name 'PostToolUse' -Value @() }
    $Settings.hooks.PostToolUse += $hook
    Write-Host "  ✅ PostToolUse → session-logger.js" -ForegroundColor Green
} else {
    Write-Host "  ⏭  PostToolUse 已注册，跳过" -ForegroundColor Gray
}

# 添加 SessionEnd hook
if (-not ($Settings.hooks.SessionEnd | Where-Object { $_.hooks.command -like "*session-analyzer*" })) {
    $hook = @{
        hooks = @(@{
            async = $true
            command = "& `"$NodeExe`" `"$HooksDir\session-analyzer.js`"" -replace '\\', '\\'
            shell = "powershell"
            timeout = 30
            type = "command"
        })
        matcher = ""
    }
    if (-not $Settings.hooks.SessionEnd) { $Settings.hooks | Add-Member -MemberType NoteProperty -Name 'SessionEnd' -Value @() }
    $Settings.hooks.SessionEnd += $hook
    Write-Host "  ✅ SessionEnd → session-analyzer.js" -ForegroundColor Green
} else {
    Write-Host "  ⏭  SessionEnd 已注册，跳过" -ForegroundColor Gray
}

# 添加 SessionStart hook
if (-not ($Settings.hooks.SessionStart | Where-Object { $_.hooks.command -like "*pattern-reporter*" })) {
    $hook = @{
        hooks = @(@{
            async = $true
            command = "& `"$NodeExe`" `"$HooksDir\pattern-reporter.js`"" -replace '\\', '\\'
            shell = "powershell"
            timeout = 10
            type = "command"
        })
        matcher = ""
    }
    if (-not $Settings.hooks.SessionStart) { $Settings.hooks | Add-Member -MemberType NoteProperty -Name 'SessionStart' -Value @() }
    $Settings.hooks.SessionStart += $hook
    Write-Host "  ✅ SessionStart → pattern-reporter.js" -ForegroundColor Green
} else {
    Write-Host "  ⏭  SessionStart 已注册，跳过" -ForegroundColor Gray
}

$Settings | ConvertTo-Json -Depth 10 | Out-File -FilePath $SettingsFile -Encoding utf8

Write-Host "`n==============================================" -ForegroundColor Cyan
Write-Host "  ✅ continuous-learn v1.0.0 安装完成！" -ForegroundColor Green
Write-Host "`n  无需任何操作。下次会话开始时，系统会自动汇报。"
Write-Host "  手动触发命令:"
Write-Host "    /learn-analyze  — 立即分析"
Write-Host "    /learn-review   — 浏览模式库"
Write-Host "    /learn-apply    — 固化为技能`n"
