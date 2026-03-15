<#
  Fix Bot - Reads GitHub Issues and creates PRs with fixes
#>
$ErrorActionPreference = "Stop"

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

Write-Log "===== Fix Bot Started ====="
Set-Location $PROJECT_DIR

cmd /c "git checkout main 2>nul"
git pull 2>&1 | ForEach-Object { Write-Log $_ }

# Get open audit issues
$issuesJson = gh issue list --label "bot-audit" --state open --json number,title,body --limit 3 2>&1
$issues = @()
try { $issues = $issuesJson | ConvertFrom-Json } catch {}

if ($issues.Count -eq 0) {
    Write-Log "No issues to fix"
    exit 0
}

# Fix one issue at a time
$issue = $issues[0]
$issueNum = $issue.number
$issueTitle = $issue.title
$issueBody = $issue.body

Write-Log "Fixing Issue #$issueNum : $issueTitle"

$branchName = "bot-fix/issue-$issueNum"

# Skip if branch already exists
$existingBranch = git branch -r --list "origin/$branchName" 2>&1
if ($existingBranch -and $existingBranch.ToString().Trim() -ne "") {
    Write-Log "Branch $branchName already exists, skipping"
    exit 0
}

cmd /c "git checkout -b $branchName 2>nul"

# Write prompt to temp file
$promptFile = Join-Path $env:TEMP "fix_prompt.txt"
$promptContent = @"
You are a code fix bot. Fix the following issue in this project.

Issue #$issueNum
Title: $issueTitle

Description:
$issueBody

Rules:
1. Only change what is necessary to fix this issue
2. Make sure the code still works after your changes
3. Add a brief comment explaining what you changed
4. Save the files directly

Fix the code now.
"@
$promptContent | Set-Content -Path $promptFile -Encoding UTF8

Write-Log "Calling Claude Code to fix..."
$fixResult = claude --print (Get-Content $promptFile -Raw) 2>&1
$fixResultStr = $fixResult | Out-String
Write-Log "Claude fix output length: $($fixResultStr.Length) chars"

# Check for changes
$changes = git diff --name-only 2>&1 | Out-String
$stagedChanges = git diff --cached --name-only 2>&1 | Out-String
$allChanges = ($changes + $stagedChanges).Trim()

if ([string]::IsNullOrWhiteSpace($allChanges)) {
    Write-Log "No file changes detected, rolling back"
    git checkout main 2>&1 | Out-Null
    git branch -D $branchName 2>&1 | Out-Null
    exit 0
}

Write-Log "Changed files: $allChanges"

git add -A 2>&1 | Out-Null
git commit -m "fix: Issue #$issueNum - $issueTitle" 2>&1 | ForEach-Object { Write-Log $_ }

Write-Log "Pushing branch..."
git push origin $branchName 2>&1 | ForEach-Object { Write-Log $_ }

$prBody = "Fixes #$issueNum`n`nChanged files:`n$allChanges`n`n---`nCreated by fix bot at $(Get-Date -Format 'yyyy-MM-dd HH:mm')"

Write-Log "Creating PR..."
gh pr create --title "fix: Issue #$issueNum - $issueTitle" --body $prBody --label "bot-fix" --base main --head $branchName 2>&1 | ForEach-Object { Write-Log $_ }

git checkout main 2>&1 | Out-Null

Write-Log "===== Fix Bot Finished ====="


