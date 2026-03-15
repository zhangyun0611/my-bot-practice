<#
  Review Bot - Reviews PRs and merges or rejects them
#>
$ErrorActionPreference = "Stop"

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

Write-Log "===== Review Bot Started ====="
Set-Location $PROJECT_DIR

# Get open PRs with bot-fix label
$prsJson = gh pr list --label "bot-fix" --state open --json number,title,headRefName --limit 5 2>&1
$prs = @()
try { $prs = $prsJson | ConvertFrom-Json } catch {}

if ($prs.Count -eq 0) {
    Write-Log "No PRs to review"
    exit 0
}

Write-Log "Found $($prs.Count) PRs to review"

foreach ($pr in $prs) {
    $prNum = $pr.number
    $prTitle = $pr.title
    $prBranch = $pr.headRefName

    Write-Log "--- Reviewing PR #$prNum : $prTitle ---"

    # Get diff
    $diff = gh pr diff $prNum 2>&1 | Out-String

    # Check mergeability
    $mergeable = gh pr view $prNum --json mergeable --jq ".mergeable" 2>&1 | Out-String
    $mergeable = $mergeable.Trim()
    Write-Log "Mergeable: $mergeable"

    if ($mergeable -eq "CONFLICTING") {
        Write-Log "PR #$prNum has conflicts, closing"
        gh pr comment $prNum --body "Closing: merge conflict detected. Review bot $(Get-Date -Format 'yyyy-MM-dd HH:mm')" 2>&1 | Out-Null
        gh pr close $prNum 2>&1 | Out-Null
        git push origin --delete $prBranch 2>&1 | Out-Null
        continue
    }

    # Truncate diff if too long
    $diffPreview = $diff
    if ($diff.Length -gt 3000) {
        $diffPreview = $diff.Substring(0, 3000) + "`n... (truncated)"
    }

    # Write review prompt to temp file
    $promptFile = Join-Path $env:TEMP "review_prompt.txt"
    $promptContent = @"
You are a code review bot. Review this Pull Request diff.

PR #$prNum : $prTitle

Diff:
$diffPreview

Review criteria:
1. Does the change correctly fix the described problem?
2. Does it introduce new bugs?
3. Is the code style consistent?

Output ONLY a JSON object wrapped in ```json blocks:

```json
{
  "approved": true or false,
  "comment": "Your review comment"
}
```

Unless the code has obvious errors or security issues, approve it (approved: true).
"@
    $promptContent | Set-Content -Path $promptFile -Encoding UTF8

    Write-Log "Calling Claude Code for review..."
    $reviewResult = claude --print (Get-Content $promptFile -Raw) 2>&1
    $reviewResultStr = $reviewResult | Out-String

    try {
        $jsonStr = ""
        if ($reviewResultStr -match '(?s)```json\s*(.*?)\s*```') {
            $jsonStr = $Matches[1]
        } else {
            $jsonStr = $reviewResultStr
        }

        $review = $jsonStr | ConvertFrom-Json

        if ($review.approved -eq $true) {
            Write-Log "PR #$prNum APPROVED, merging..."
            gh pr comment $prNum --body "Approved: $($review.comment) -- Review bot $(Get-Date -Format 'yyyy-MM-dd HH:mm')" 2>&1 | Out-Null
            gh pr merge $prNum --squash --delete-branch 2>&1 | ForEach-Object { Write-Log $_ }
            Write-Log "PR #$prNum merged"
        } else {
            Write-Log "PR #$prNum REJECTED"
            gh pr comment $prNum --body "Changes requested: $($review.comment) -- Review bot $(Get-Date -Format 'yyyy-MM-dd HH:mm')" 2>&1 | Out-Null
            gh pr close $prNum 2>&1 | Out-Null
            git push origin --delete $prBranch 2>&1 | Out-Null
        }
    } catch {
        Write-Log "Failed to parse review: $_"
    }
}

git pull 2>&1 | Out-Null

Write-Log "===== Review Bot Finished ====="
