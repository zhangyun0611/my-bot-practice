#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$PROJECT_DIR/_bots/logs"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_FILE="$LOG_DIR/audit_$TIMESTAMP.log"
log() { local e="[$(date +%H:%M:%S)] $1"; echo "$e"; echo "$e" >> "$LOG_FILE"; }
log "===== Audit Bot Started ====="
cd "$PROJECT_DIR"
git pull 2>/dev/null
ISSUE_COUNT=$(gh issue list --label "bot-audit" --state open --json number 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
if [ "$ISSUE_COUNT" -ge 5 ]; then log "Already $ISSUE_COUNT open issues, skipping"; exit 0; fi
PROMPT_FILE=$(mktemp)
cat > "$PROMPT_FILE" << 'EOF'
You are a code audit bot. Review all source code in this project. Pick 1 to 3 specific issues. Output ONLY a JSON array inside ```json fences: ```json [{"title":"Short title","body":"File, line, problem, fix","severity":"high or medium or low"}] ``` If perfect, output []. Nothing else.
EOF
log "Calling Claude Code..."
AUDIT_RESULT=$(claude --print "$(cat "$PROMPT_FILE")" 2>/dev/null)
rm -f "$PROMPT_FILE"
log "Result length: ${#AUDIT_RESULT} chars"
JSON_STR=$(echo "$AUDIT_RESULT" | sed -n '/```json/,/```/p' | sed '1d;$d')
[ -z "$JSON_STR" ] && JSON_STR="$AUDIT_RESULT"
echo "$JSON_STR" | python3 -c "
import sys,json,subprocess
try:
    issues=json.load(sys.stdin)
except: sys.exit(0)
if not issues: print('No issues found'); sys.exit(0)
for i in issues:
    t='[Bot Audit] '+i['title']
    b='Severity: '+i['severity']+'\n\n'+i['body']+'\n\n---\nAudit bot'
    print(f'Creating: {t}')
    subprocess.run(['gh','issue','create','--title',t,'--body',b,'--label','bot-audit'],capture_output=True)
"
log "===== Audit Bot Finished ====="
