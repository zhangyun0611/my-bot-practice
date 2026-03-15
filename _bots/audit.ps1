<#
  Audit Bot - Scans code and creates GitHub Issues
#>
$ErrorActionPreference = "Continue"

$PROJECT_DIR = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$LOG_DIR = Join-Path $PROJECT_DIR "_bots\logs"
$TIMESTAMP = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$LOG_FILE = Join-Path $LOG_DIR "audit_$TIMESTAMP.log"

if (-not (Test-Path $LOG_DIR)) { New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null }

function Write-Log {
    param([string]$Message)
    $entry = "[$(Get-Date -Format 'HH:mm:ss')] $Message"
    Write-Host $entry
    Add-Content -Path $LOG_FILE -Value $entry
}

Write-Log "===== Audit Bot Started ====="
Set-Location $PROJECT_DIR

Write-Log "Pulling latest code..."
git pull 2>&1 | ForEach-Object { Write-Log $_ }

# Check existing open issues to avoid duplicates
$existingIssues = gh issue list --label "bot-audit" --state open --json number 2>&1
$issueCount = 0
try { $issueCount = ($existingIssues | ConvertFrom-Json).Count } catch {}

if ($issueCount -ge 5) {
    Write-Log "Already $issueCount open issues, skipping audit"
    exit 0
}

# Write prompt to a temp file to avoid encoding issues
$promptFile = Join-Path $env:TEMP "audit_prompt.txt"
@'
You are a code audit bot. Review all source code in this project from these 5 angles:
1. Code quality: naming, duplication, function length
2. Error handling: missing try-catch, unhandled edge cases
3. Security: hardcoded secrets, injection risks
4. Performance: unnecessary loops, bottlenecks
5. Documentation: missing comments, incomplete README

Pick 1 to 3 specific issues worth fixing. Output ONLY a JSON array wrapped in ```json blocks:

```json
[
  {
    "title": "Short title of the issue",
    "body": "Which file, which line, what is wrong, how to fix it",
    "severity": "high or medium or low"
  }
]
```

If the code is perfect, output an empty array []. Output nothing else.
'@ | Set-Content -Path $promptFile -Encoding UTF8

Write-Log "Calling Claude Code for audit..."
$auditResult = claude --print (Get-Content $promptFile -Raw) 2>&1
$auditResultStr = $auditResult | Out-String
Write-Log "Claude result length: $($auditResultStr.Length) chars"

# Parse JSON from result
try {
    $jsonStr = ""
    if ($auditResultStr -match '(?s)```json\s*(.*?)\s*```') {
        $jsonStr = $Matches[1]
    } else {
        $jsonStr = $auditResultStr
    }

    $issues = $jsonStr | ConvertFrom-Json

    if ($issues.Count -eq 0) {
        Write-Log "Audit passed, no issues found"
        exit 0
    }

    Write-Log "Found $($issues.Count) issues, creating GitHub Issues..."

    foreach ($issue in $issues) {
        $title = "[Bot Audit] $($issue.title)"
        $body = "Severity: $($issue.severity)`n`n$($issue.body)`n`n---`nCreated by audit bot at $(Get-Date -Format 'yyyy-MM-dd HH:mm')"

        Write-Log "Creating Issue: $title"
        gh issue create --title $title --body $body --label "bot-audit" 2>&1 | ForEach-Object { Write-Log $_ }
    }
} catch {
    Write-Log "Failed to parse result: $_"
}

Write-Log "===== Audit Bot Finished ====="
