#!/usr/bin/env bash
# Usage: worker.sh <prompt-file> [session-id]   (run from inside the target git repository)
#   With a session id the worker continues that opencode session (fix rounds, plan -> build).
# Settings: environment variables, then KEY=VALUE lines in worker.local.env next to this script (environment wins):
#   WORKER_MODEL        opencode model (default: opencode-go/deepseek-v4.1-flash)
#   WORKER_VARIANT      model variant (default: max; empty = none)
#   WORKER_AGENT        build | plan (default: build; plan = read only, returns a plan or report)
#   WORKER_LOG          log file (default: <prompt-file>.log)
#   WORKER_TIMEOUT      hard limit in seconds (default: 5400)
#   WORKER_STALL        stop the worker when its log does not grow for this many seconds (default: 1200)
#   WORKER_TAIL         log lines printed at the end (default: 40; use 200 for review/research reports)
#   WORKER_BLOCK_FREE   1 = refuse model names containing "free" (default: 0)
set -uo pipefail

SKILL_DIR=$(cd "$(dirname "$0")" && pwd -P)
if [ -f "$SKILL_DIR/worker.local.env" ]; then
  while IFS='=' read -r KEY VALUE || [ -n "$KEY" ]; do
    VALUE=${VALUE%$'\r'}
    case "$KEY" in WORKER_*) [ -z "${!KEY+x}" ] && export "$KEY=$VALUE" ;; esac
  done < "$SKILL_DIR/worker.local.env"
fi

PROMPT=${1:-}
SESSION=${2:-}
WORKER_MODEL=${WORKER_MODEL:-opencode-go/deepseek-v4.1-flash}
WORKER_VARIANT=${WORKER_VARIANT-max}
WORKER_AGENT=${WORKER_AGENT:-build}
WORKER_TIMEOUT=${WORKER_TIMEOUT:-5400}
WORKER_STALL=${WORKER_STALL:-1200}
WORKER_TAIL=${WORKER_TAIL:-40}
WORKER_BLOCK_FREE=${WORKER_BLOCK_FREE:-0}

[ -n "$PROMPT" ] || { echo "usage: worker.sh <prompt-file> [session-id]" >&2; exit 2; }
[ -f "$PROMPT" ] || { echo "prompt file not found: $PROMPT" >&2; exit 2; }
PROMPT=$(cd "$(dirname "$PROMPT")" && pwd -P)/$(basename "$PROMPT")
WORKER_LOG=${WORKER_LOG:-$PROMPT.log}
if [ "$WORKER_BLOCK_FREE" = 1 ]; then
  case "$WORKER_MODEL" in *free*) echo "free models are blocked (WORKER_BLOCK_FREE=1): $WORKER_MODEL" >&2; exit 2 ;; esac
fi
command -v opencode > /dev/null || { echo "opencode CLI not found in PATH" >&2; exit 2; }

ROOT=$(git rev-parse --show-toplevel) || { echo "not inside a git repository" >&2; exit 2; }
cd "$ROOT"
BEFORE=$(git rev-parse HEAD)
TITLE="worker $(basename "$PROMPT" .md) $(date +%H%M%S)"
MESSAGE="$(cat "$PROMPT")

$(cat "$SKILL_DIR/WORKER_RULES.md")"

export OPENCODE_CONFIG="$SKILL_DIR/worker-opencode.json"
ARGS=(run --auto -m "$WORKER_MODEL" --agent "$WORKER_AGENT")
[ -n "$WORKER_VARIANT" ] && ARGS+=(--variant "$WORKER_VARIANT")
if [ -n "$SESSION" ]; then ARGS+=(--session "$SESSION"); else ARGS+=(--title "$TITLE"); fi

kill_tree() {
  local child
  for child in $(ps -ef | awk -v p="$1" '$3 == p {print $2}'); do kill_tree "$child"; done
  if [ -r "/proc/$1/winpid" ] && command -v taskkill > /dev/null; then
    taskkill //F //T //PID "$(cat "/proc/$1/winpid")" > /dev/null 2>&1
  fi
  kill -9 "$1" 2> /dev/null
}

echo "MODEL=$WORKER_MODEL VARIANT=$WORKER_VARIANT AGENT=$WORKER_AGENT BRANCH=$(git branch --show-current) HEAD=$BEFORE"
opencode "${ARGS[@]}" "$MESSAGE" < /dev/null > "$WORKER_LOG" 2>&1 &
PID=$!
STOPPED=""
START=$SECONDS
LAST_SIZE=-1
LAST_CHANGE=$SECONDS
while kill -0 "$PID" 2> /dev/null; do
  sleep 5
  SIZE=$(wc -c < "$WORKER_LOG" 2> /dev/null | tr -d ' ')
  if [ "$SIZE" != "$LAST_SIZE" ]; then
    LAST_SIZE=$SIZE
    LAST_CHANGE=$SECONDS
  elif [ $((SECONDS - LAST_CHANGE)) -ge "$WORKER_STALL" ]; then
    STOPPED="STALL: no worker output for ${WORKER_STALL}s, worker stopped"
  fi
  if [ -z "$STOPPED" ] && [ $((SECONDS - START)) -ge "$WORKER_TIMEOUT" ]; then
    STOPPED="TIMEOUT: worker stopped after ${WORKER_TIMEOUT}s"
  fi
  if [ -n "$STOPPED" ]; then
    kill_tree "$PID"
    break
  fi
done
wait "$PID" 2> /dev/null
CODE=$?
if [ -n "$STOPPED" ]; then
  CODE=124
  echo "$STOPPED"
fi

if [ -z "$SESSION" ]; then
  SESSION=$(opencode session list 2> /dev/null | grep -F "$TITLE" | awk '{print $1}' | head -1)
fi
ESC=$(printf '\033')
echo "OPENCODE_EXIT=$CODE"
echo "SESSION=$SESSION"
echo "--- commits"
git log --oneline "$BEFORE"..HEAD
echo "--- stat"
git diff --stat "$BEFORE"..HEAD
echo "--- uncommitted"
git status --short
echo "--- risky commands (review these)"
grep -a '\$ ' "$WORKER_LOG" | sed "s/${ESC}\[[0-9;]*m//g" \
  | grep -aiE '(mysql|psql|redis-cli|sqlcmd|sqlite3|mongosh).*(DELETE|UPDATE|INSERT|TRUNCATE|DROP|ALTER|FLUSH|GRANT|REVOKE|[^a-z]DEL )|curl .*-X *(DELETE|PUT|PATCH)|Invoke-(RestMethod|WebRequest).*-Method *(Delete|Put|Patch)|(^\$ |[;&|] *)rm |Remove-Item|git (checkout --|checkout \.|restore|stash|reset|clean|commit --amend|update-ref)|>>? *(~|[A-Za-z]:|/c/|/home|/Users|/tmp|\.\./)' \
  | grep -avE '^\$ (grep|rg|cat|sed -n|head|tail|ls) ' \
  | cut -c1-240 | head -40 || true
echo "--- worker summary (tail)"
tail -n "$WORKER_TAIL" "$WORKER_LOG"
