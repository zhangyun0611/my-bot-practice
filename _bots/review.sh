#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$PROJECT_DIR/_bots/logs"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_FILE="$LOG_DIR/review_$TIMESTAMP.log"
log() { local e="[$(date +%H:%M:%S)] $1"; echo "$e"; echo "$e" >> "$LOG_FILE"; }
log "===== Review Bot Started ====="
cd "$PROJECT_DIR"
PRS_JSON=$(gh pr list --label "bot-fix" --state open --json number,title,headRefName --limit 5 2>/dev/null)
PR_COUNT=$(echo "$PRS_JSON" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
if [ "$PR_COUNT" -eq 0 ]; then log "No PRs to review"; exit 0; fi
log "Found $PR_COUNT PRs"
echo "$PRS_JSON" | python3 -c "import sys,json; [print(f\"{p['number']}|{p['title']}|{p['headRefName']}\") for p in json.load(sys.stdin)]" | while IFS='|' read -r PR_NUM PR_TITLE PR_BRANCH; do
    log "--- Reviewing PR #$PR_NUM : $PR_TITLE ---"
    DIFF=$(gh pr diff "$PR_NUM" 2>/dev/null)
    MERGEABLE=$(gh pr view "$PR_NUM" --json mergeable --jq ".mergeable" 2>/dev/null)
    log "Mergeable: $MERGEABLE"
    if [ "$MERGEABLE" = "CONFLICTING" ]; then
        log "Conflicts, closing"; gh pr close "$PR_NUM" 2>/dev/null; git push origin --delete "$PR_BRANCH" 2>/dev/null; continue
    fi
    DIFF_PREVIEW="$DIFF"
    [ ${#DIFF} -gt 3000 ] && DIFF_PREVIEW="${DIFF:0:3000}"
    PROMPT_FILE=$(mktemp)
    cat > "$PROMPT_FILE" << ENDPROMPT
You are a code review bot. Review this PR diff.
PR #$PR_NUM : $PR_TITLE
Diff:
$DIFF_PREVIEW
Output ONLY JSON in \`\`\`json fences: \`\`\`json {"approved":true,"comment":"reason"} \`\`\`
Unless obvious errors, approve it.
ENDPROMPT
    log "Calling Claude Code..."
    REVIEW_RESULT=$(claude --print "$(cat "$PROMPT_FILE")" 2>/dev/null)
    rm -f "$PROMPT_FILE"
    JSON_STR=$(echo "$REVIEW_RESULT" | sed -n '/```json/,/```/p' | sed '1d;$d')
    [ -z "$JSON_STR" ] && JSON_STR="$REVIEW_RESULT"
    APPROVED=$(echo "$JSON_STR" | python3 -c "import sys,json; print(json.load(sys.stdin).get('approved',False))" 2>/dev/null || echo "False")
    COMMENT=$(echo "$JSON_STR" | python3 -c "import sys,json; print(json.load(sys.stdin).get('comment',''))" 2>/dev/null || echo "")
    if [ "$APPROVED" = "True" ]; then
        log "PR #$PR_NUM APPROVED, merging..."
        gh pr comment "$PR_NUM" --body "Approved: $COMMENT -- Review bot" 2>/dev/null
        gh pr merge "$PR_NUM" --squash --delete-branch 2>/dev/null
        log "PR #$PR_NUM merged!"
    else
        log "PR #$PR_NUM REJECTED: $COMMENT"
        gh pr comment "$PR_NUM" --body "Changes requested: $COMMENT -- Review bot" 2>/dev/null
        gh pr close "$PR_NUM" 2>/dev/null
        git push origin --delete "$PR_BRANCH" 2>/dev/null
    fi
done
git pull 2>/dev/null
log "===== Review Bot Finished ====="
