# ============================================================
# 审查机器人 (review.ps1)
# 功能：审查 PR，没问题就合并，有问题就评论要求修改
# ============================================================

$ErrorActionPreference = "Stop"

# --- 配置 ---
$PROJECT_DIR = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$LOG_DIR = Join-Path $PROJECT_DIR "_bots\logs"
$TIMESTAMP = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$LOG_FILE = Join-Path $LOG_DIR "review_$TIMESTAMP.log"

if (-not (Test-Path $LOG_DIR)) { New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null }

function Write-Log {
    param([string]$Message)
    $entry = "[$(Get-Date -Format 'HH:mm:ss')] $Message"
    Write-Host $entry
    Add-Content -Path $LOG_FILE -Value $entry
}

# --- 开始审查 ---
Write-Log "===== 审查机器人启动 ====="
Write-Log "项目目录: $PROJECT_DIR"

Set-Location $PROJECT_DIR

# 获取所有 bot-fix 标签的 PR
$prsJson = gh pr list --label "bot-fix" --state open --json number,title,headRefName,body,diff --limit 5 2>&1
$prs = $prsJson | ConvertFrom-Json

if ($prs.Count -eq 0) {
    Write-Log "没有需要审查的 PR"
    Write-Log "===== 审查机器人结束 ====="
    exit 0
}

Write-Log "找到 $($prs.Count) 个待审查的 PR"

foreach ($pr in $prs) {
    $prNum = $pr.number
    $prTitle = $pr.title
    $prBranch = $pr.headRefName
    
    Write-Log "---------- 审查 PR #$prNum : $prTitle ----------"
    
    # 获取 PR 的 diff
    $diff = gh pr diff $prNum 2>&1
    Write-Log "获取到 diff，长度: $($diff.Length) 字符"
    
    # 检查是否有合并冲突
    $mergeCheck = gh pr view $prNum --json mergeable --jq '.mergeable' 2>&1
    Write-Log "合并状态: $mergeCheck"
    
    if ($mergeCheck -eq "CONFLICTING") {
        Write-Log "PR #$prNum 有合并冲突，添加评论"
        gh pr comment $prNum --body "❌ 此 PR 有合并冲突，请修复机器人重新处理。`n`n_审查机器人 $(Get-Date -Format 'yyyy-MM-dd HH:mm')_" 2>&1 | ForEach-Object { Write-Log $_ }
        gh pr close $prNum 2>&1 | ForEach-Object { Write-Log $_ }
        
        # 删除远程分支
        git push origin --delete $prBranch 2>&1 | ForEach-Object { Write-Log $_ }
        continue
    }
    
    # 用 Claude Code 审查 diff
    Write-Log "调用 Claude Code 审查代码变更..."
    
    # 截取 diff 前 3000 字符（防止太长）
    $diffPreview = $diff
    if ($diff.Length -gt 3000) {
        $diffPreview = $diff.Substring(0, 3000) + "`n... (截断)"
    }
    
    $REVIEW_PROMPT = @"
你是一个代码审查机器人。请审查以下 Pull Request 的代码变更。

## PR #$prNum : $prTitle

## 代码变更 (diff):
$diffPreview

## 审查标准：
1. 修改是否正确解决了描述中的问题？
2. 是否引入了新的 bug？
3. 代码风格是否一致？
4. 是否有遗漏的边界情况？

## 请用以下 JSON 格式输出，用 ```json 包裹：

```json
{
  "approved": true 或 false,
  "comment": "审查意见（如果通过就写通过的理由，不通过就写具体问题）"
}
```

只输出 JSON，不要输出其他内容。
除非代码有明显的错误或安全隐患，否则默认通过（approved: true）。
"@

    $reviewResult = claude --print $REVIEW_PROMPT 2>&1
    Write-Log "Claude 审查结果: $reviewResult"
    
    # 解析结果
    try {
        if ($reviewResult -match '```json\s*([\s\S]*?)\s*```') {
            $jsonStr = $Matches[1]
        } else {
            $jsonStr = $reviewResult
        }
        
        $review = $jsonStr | ConvertFrom-Json
        
        if ($review.approved -eq $true) {
            Write-Log "✅ PR #$prNum 审查通过，准备合并"
            
            # 添加审查通过评论
            $approveComment = "✅ **审查通过**`n`n$($review.comment)`n`n---`n_审查机器人 $(Get-Date -Format 'yyyy-MM-dd HH:mm')_"
            gh pr comment $prNum --body $approveComment 2>&1 | ForEach-Object { Write-Log $_ }
            
            # 合并 PR（使用 squash merge 保持历史整洁）
            Write-Log "合并 PR #$prNum ..."
            gh pr merge $prNum --squash --delete-branch 2>&1 | ForEach-Object { Write-Log $_ }
            
            Write-Log "PR #$prNum 已合并并删除分支"
            
        } else {
            Write-Log "❌ PR #$prNum 审查未通过"
            
            # 添加审查未通过评论
            $rejectComment = "❌ **审查未通过，需要修改**`n`n$($review.comment)`n`n---`n_审查机器人 $(Get-Date -Format 'yyyy-MM-dd HH:mm')_"
            gh pr comment $prNum --body $rejectComment 2>&1 | ForEach-Object { Write-Log $_ }
            
            # 关闭 PR（让修复机器人重新来过）
            gh pr close $prNum 2>&1 | ForEach-Object { Write-Log $_ }
            git push origin --delete $prBranch 2>&1 | ForEach-Object { Write-Log $_ }
            
            Write-Log "PR #$prNum 已关闭，等待下轮修复"
        }
        
    } catch {
        Write-Log "解析审查结果失败: $_"
        Write-Log "跳过此 PR"
    }
}

# 拉取最新（可能刚合并了东西）
git pull origin main 2>&1 | ForEach-Object { Write-Log $_ }

Write-Log "===== 审查机器人结束 ====="
