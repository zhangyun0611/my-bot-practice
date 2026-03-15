#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$PROJECT_DIR/_bots/logs"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_FILE="$LOG_DIR/fix_$TIMESTAMP.log"
log() { local e="[$(date +%H:%M:%S)] $1"; echo "$e"; echo "$e" >> "$LOG_FILE"; }
log "===== Fix Bot Started ====="
cd "$PROJECT_DIR"
git checkout -- . 2>/dev/null
git checkout main 2>/dev/null
git pull 2>/dev/null
ISSUES_JSON=$(gh issue list --label "bot-audit" --state open --json number,title,body --limit 3 2>/dev/null)
ISSUE_COUNT=$(echo "$ISSUES_JSON" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
if [ "$ISSUE_COUNT" -eq 0 ]; then log "No issues to fix"; exit 0; fi
ISSUE_NUM=$(echo "$ISSUES_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['number'])")
ISSUE_TITLE=$(echo "$ISSUES_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['title'])")
ISSUE_BODY=$(echo "$ISSUES_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['body'])")
log "Fixing Issue #$ISSUE_NUM : $ISSUE_TITLE"
BRANCH_NAME="bot-fix/issue-$ISSUE_NUM"
if git branch -r 2>/dev/null | grep -q "$BRANCH_NAME"; then log "Branch exists remotely, skipping"; exit 0; fi
git branch -D "$BRANCH_NAME" 2>/dev/null
git checkout -b "$BRANCH_NAME" 2>/dev/null
log "Created branch $BRANCH_NAME"
PROMPT_FILE=$(mktemp)
cat > "$PROMPT_FILE" << ENDPROMPT
You are a code fix bot. Fix this issue:
Issue #$ISSUE_NUM - $ISSUE_TITLE
$ISSUE_BODY
Only change what is necessary. Save files directly.
ENDPROMPT
log "Calling Claude Code to fix..."
FIX_RESULT=$(claude --print "$(cat "$PROMPT_FILE")" 2>/dev/null)
rm -f "$PROMPT_FILE"
log "Fix output length: ${#FIX_RESULT} chars"
CHANGES=$(git diff --name-only -- src/ 2>/dev/null)
if [ -z "$CHANGES" ]; then log "No changes, rolling back"; git checkout main 2>/dev/null; git branch -D "$BRANCH_NAME" 2>/dev/null; exit 0; fi
log "Changed: $CHANGES"
git add src/ 2>/dev/null
git commit -m "fix: Issue #$ISSUE_NUM - $ISSUE_TITLE" 2>/dev/null
log "Pushing..."
git push origin "$BRANCH_NAME" 2>/dev/null
log "Creating PR..."
PR_URL=$(gh pr create --title "fix: Issue #$ISSUE_NUM - $ISSUE_TITLE" --body "Fixes #$ISSUE_NUM" --label "bot-fix" --base main --head "$BRANCH_NAME" 2>/dev/null)
log "PR: $PR_URL"
git checkout main 2>/dev/null
log "===== Fix Bot Finished ====="
