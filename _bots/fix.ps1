# ============================================================
# 修复机器人 (fix.ps1)
# 功能：读取 GitHub Issue，用 Claude Code 修复代码，提交 PR
# ============================================================

$ErrorActionPreference = "Stop"

# --- 配置 ---
$PROJECT_DIR = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$LOG_DIR = Join-Path $PROJECT_DIR "_bots\logs"
$TIMESTAMP = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$LOG_FILE = Join-Path $LOG_DIR "fix_$TIMESTAMP.log"

if (-not (Test-Path $LOG_DIR)) { New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null }

function Write-Log {
    param([string]$Message)
    $entry = "[$(Get-Date -Format 'HH:mm:ss')] $Message"
    Write-Host $entry
    Add-Content -Path $LOG_FILE -Value $entry
}

# --- 开始修复 ---
Write-Log "===== 修复机器人启动 ====="
Write-Log "项目目录: $PROJECT_DIR"

Set-Location $PROJECT_DIR

# 确保在 main 分支上，拉取最新
git checkout main 2>&1 | ForEach-Object { Write-Log $_ }
git pull origin main 2>&1 | ForEach-Object { Write-Log $_ }

# 获取所有 bot-audit 标签的未关闭 Issue
$issuesJson = gh issue list --label "bot-audit" --state open --json number,title,body --limit 3 2>&1
$issues = $issuesJson | ConvertFrom-Json

if ($issues.Count -eq 0) {
    Write-Log "没有需要修复的 Issue"
    Write-Log "===== 修复机器人结束 ====="
    exit 0
}

Write-Log "找到 $($issues.Count) 个待修复的 Issue"

# 逐个修复（每次只修一个，降低冲突风险）
$issue = $issues[0]
$issueNum = $issue.number
$issueTitle = $issue.title
$issueBody = $issue.body

Write-Log "正在处理 Issue #$issueNum : $issueTitle"

# 创建修复分支
$branchName = "bot-fix/issue-$issueNum"

# 检查远程分支是否已存在（说明之前已经在修了）
$existingBranch = git branch -r --list "origin/$branchName" 2>&1
if ($existingBranch) {
    Write-Log "分支 $branchName 已存在，跳过这个 Issue"
    Write-Log "===== 修复机器人结束 ====="
    exit 0
}

git checkout -b $branchName 2>&1 | ForEach-Object { Write-Log $_ }

# 用 Claude Code 修复问题
Write-Log "调用 Claude Code 进行修复..."

$FIX_PROMPT = @"
你是一个代码修复机器人。请根据以下 Issue 描述，修复代码中的问题。

## Issue #$issueNum
**标题**: $issueTitle

**描述**:
$issueBody

## 要求：
1. 只修改必要的代码，不要做额外的重构
2. 确保修改后代码能正常运行
3. 如果需要，添加适当的注释说明你的修改
4. 修改完成后，直接保存文件即可

请直接修改相关文件。
"@

# 使用 claude 的非交互模式修复代码
# --print 只看输出，但我们需要它真正改文件，所以用管道
$fixResult = claude --print $FIX_PROMPT 2>&1
Write-Log "Claude 修复输出: $fixResult"

# 检查是否有文件变更
$changes = git diff --name-only 2>&1
$stagedChanges = git diff --cached --name-only 2>&1
$allChanges = @($changes) + @($stagedChanges) | Where-Object { $_ -and $_ -ne "" }

if ($allChanges.Count -eq 0) {
    Write-Log "没有检测到文件变更，Claude 可能没有成功修改文件"
    Write-Log "尝试回退到 main 分支..."
    git checkout main 2>&1 | ForEach-Object { Write-Log $_ }
    git branch -D $branchName 2>&1 | ForEach-Object { Write-Log $_ }
    Write-Log "===== 修复机器人结束 ====="
    exit 0
}

Write-Log "检测到以下文件变更:"
$allChanges | ForEach-Object { Write-Log "  - $_" }

# 提交变更
git add -A 2>&1 | ForEach-Object { Write-Log $_ }
git commit -m "fix: 修复 Issue #$issueNum - $issueTitle`n`n由修复机器人自动修复" 2>&1 | ForEach-Object { Write-Log $_ }

# 推送分支
Write-Log "推送分支到远程..."
git push origin $branchName 2>&1 | ForEach-Object { Write-Log $_ }

# 创建 PR
$prBody = @"
## 修复 Issue #$issueNum

**关联 Issue**: closes #$issueNum

### 修改的文件：
$($allChanges | ForEach-Object { "- ``$_``" } | Out-String)

### 修改说明：
$fixResult

---
_此 PR 由修复机器人自动创建于 $(Get-Date -Format 'yyyy-MM-dd HH:mm')_
_等待审查机器人 review_
"@

Write-Log "创建 Pull Request..."
gh pr create --title "fix: 修复 Issue #$issueNum - $issueTitle" --body $prBody --label "bot-fix" --base main --head $branchName 2>&1 | ForEach-Object { Write-Log $_ }

# 回到 main 分支
git checkout main 2>&1 | ForEach-Object { Write-Log $_ }

Write-Log "===== 修复机器人结束 ====="
