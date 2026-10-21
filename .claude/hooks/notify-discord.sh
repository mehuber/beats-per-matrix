#!/bin/sh
# Claude Code "Stop" hook: posts a one-line summary to Discord when Claude finishes a reply.
#
# This is the entry point on every OS (configured in .claude/settings.json):
#   - Windows (Claude Code runs hooks in Git Bash): hands off to notify-discord.ps1.
#   - macOS / Linux: does the work here, using jq (preferred) or python3 to handle JSON.
#
# The webhook is read from the DISCORD_WEBHOOK environment variable. Never hard-code it.
# Always exits 0: a notification problem must never block Claude.
#
# Test it without posting:
#   NOTIFY_DISCORD_DRY_RUN=1 sh .claude/hooks/notify-discord.sh < sample-stop-input.json

# ---- Windows: delegate to PowerShell (stdin is passed through) ----
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*)
    if command -v powershell.exe >/dev/null 2>&1; then
      ps1="${0%.sh}.ps1"
      if command -v cygpath >/dev/null 2>&1; then ps1=$(cygpath -w "$ps1"); fi
      powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$ps1"
    fi
    exit 0
    ;;
esac

# ---- macOS / Linux ----
webhook="${DISCORD_WEBHOOK:-}"
[ -n "$webhook" ] || exit 0
command -v curl >/dev/null 2>&1 || exit 0

input=$(cat)

# Reads the hook JSON from $input and prints: stop_hook_active, cwd, cleaned summary (one per line).
# Summary = first non-empty line of Claude's last message, markdown stripped, max 180 characters.
parse_input() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -r '
      (.stop_hook_active // false | tostring),
      (.cwd // ""),
      ((.last_assistant_message // "")
        | split("\n")
        | map(gsub("^[#>\\-\\s]+"; "") | gsub("[*`]"; "") | gsub("^\\s+|\\s+$"; ""))
        | map(select(length > 0))
        | (.[0] // "")
        | if length > 180 then .[0:177] + "..." else . end)' 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$input" | python3 -c '
import json, re, sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
lines = [re.sub(r"[*`]", "", re.sub(r"^[#>\-\s]+", "", l)).strip()
         for l in (d.get("last_assistant_message") or "").splitlines()]
lines = [l for l in lines if l]
s = lines[0] if lines else ""
if len(s) > 180:
    s = s[:177] + "..."
print(str(bool(d.get("stop_hook_active"))).lower())
print(d.get("cwd") or "")
print(s)
' 2>/dev/null
  fi
}

parsed=$(parse_input)
active=$(printf '%s\n' "$parsed" | sed -n '1p')
cwd=$(printf '%s\n' "$parsed" | sed -n '2p')
summary=$(printf '%s\n' "$parsed" | sed -n '3p')

[ "$active" = "true" ] && exit 0
[ -n "$cwd" ] || cwd="${CLAUDE_PROJECT_DIR:-$PWD}"
[ -n "$summary" ] || summary="finished a task"

branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "no-git")
user=$(git -C "$cwd" config user.name 2>/dev/null || true)
[ -n "$user" ] || user="${USER:-unknown}"
top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || echo "$cwd")
repo=$(basename "$top")

message="🤖 ${repo} (${branch}, ${user}): ${summary}"

# Build the JSON payload safely (no hand-escaping). allowed_mentions stops @everyone pings.
if command -v jq >/dev/null 2>&1; then
  payload=$(jq -n --arg c "$message" '{content: $c, allowed_mentions: {parse: []}}')
elif command -v python3 >/dev/null 2>&1; then
  payload=$(MSG="$message" python3 -c 'import json, os; print(json.dumps({"content": os.environ["MSG"], "allowed_mentions": {"parse": []}}))')
else
  payload='{"content":"Claude finished a task","allowed_mentions":{"parse":[]}}'
fi

if [ "${NOTIFY_DISCORD_DRY_RUN:-}" = "1" ]; then
  # Testing aid: print the payload instead of posting it.
  printf 'DRY RUN payload: %s\n' "$payload"
  exit 0
fi

curl -sS -m 8 -o /dev/null -H "Content-Type: application/json" -d "$payload" "$webhook" 2>/dev/null || true
exit 0
