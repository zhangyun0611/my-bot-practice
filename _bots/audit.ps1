# ============================================================
# 审核机器人 (audit.ps1)
# 功能：用 Claude Code 审查代码，发现问题后在 GitHub 提 Issue
# ============================================================

$ErrorActionPreference = "Stop"

# --- 配置 ---
$PROJECT_DIR = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$LOG_DIR = Join-Path $PROJECT_DIR "_bots\logs"
$TIMESTAMP = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$LOG_FILE = Join-Path $LOG_DIR "audit_$TIMESTAMP.log"

# 确保日志目录存在
if (-not (Test-Path $LOG_DIR)) { New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null }

function Write-Log {
    param([string]$Message)
    $entry = "[$(Get-Date -Format 'HH:mm:ss')] $Message"
    Write-Host $entry
    Add-Content -Path $LOG_FILE -Value $entry
}

# --- 开始审核 ---
Write-Log "===== 审核机器人启动 ====="
Write-Log "项目目录: $PROJECT_DIR"

Set-Location $PROJECT_DIR

# 先拉取最新代码
Write-Log "拉取最新代码..."
git pull origin main 2>&1 | ForEach-Object { Write-Log $_ }

# 检查是否已有未关闭的 bot 创建的 issue（避免重复提）
$existingIssues = gh issue list --label "bot-audit" --state open --json number,title 2>&1
Write-Log "现有未关闭的审核 Issue: $existingIssues"

$issueCount = ($existingIssues | ConvertFrom-Json).Count
if ($issueCount -ge 5) {
    Write-Log "已有 $issueCount 个未修复的 Issue，暂停审核，等修复机器人处理完再说"
    Write-Log "===== 审核机器人结束 ====="
    exit 0
}

# 用 Claude Code 审核代码
# --print 模式：非交互式，直接输出结果
Write-Log "调用 Claude Code 进行代码审核..."

$AUDIT_PROMPT = @"
你是一个代码审核机器人。请审查这个项目的代码，从以下5个方面逐一检查：

1. **代码质量**：变量命名是否清晰、是否有重复代码、函数是否过长
2. **错误处理**：是否缺少 try-catch、是否有未处理的边界情况
3. **安全问题**：是否有硬编码的密钥、是否有注入风险
4. **性能问题**：是否有明显的性能瓶颈、不必要的循环
5. **文档与注释**：是否缺少必要的注释、README 是否完善

请挑出 1~3 个最值得修复的具体问题（不要泛泛而谈），每个问题用以下 JSON 格式输出，用 ```json 包裹：

```json
[
  {
    "title": "问题的简短标题",
    "body": "详细描述：问题在哪个文件的哪一行，现在是什么样的，应该改成什么样",
    "severity": "high 或 medium 或 low"
  }
]
```

只输出 JSON，不要输出其他内容。如果代码完全没问题，输出空数组 []。
"@

$auditResult = claude --print $AUDIT_PROMPT 2>&1
Write-Log "Claude 审核结果: $auditResult"

# 解析 JSON 结果
try {
    # 提取 ```json ... ``` 中间的内容
    if ($auditResult -match '```json\s*([\s\S]*?)\s*```') {
        $jsonStr = $Matches[1]
    } else {
        # 尝试直接解析
        $jsonStr = $auditResult
    }
    
    $issues = $jsonStr | ConvertFrom-Json
    
    if ($issues.Count -eq 0) {
        Write-Log "审核通过，没有发现问题"
        Write-Log "===== 审核机器人结束 ====="
        exit 0
    }
    
    Write-Log "发现 $($issues.Count) 个问题，准备提 Issue..."
    
    foreach ($issue in $issues) {
        $title = "[Bot Audit] $($issue.title)"
        $body = @"
## 审核机器人发现的问题

**严重程度**: $($issue.severity)

$($issue.body)

---
_此 Issue 由审核机器人自动创建于 $(Get-Date -Format 'yyyy-MM-dd HH:mm')_
_等待修复机器人处理_
"@
        
        # 创建 GitHub Issue
        Write-Log "创建 Issue: $title"
        gh issue create --title $title --body $body --label "bot-audit" 2>&1 | ForEach-Object { Write-Log $_ }
    }
    
} catch {
    Write-Log "解析审核结果失败: $_"
    Write-Log "原始输出: $auditResult"
}

Write-Log "===== 审核机器人结束 ====="
