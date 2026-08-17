#!/bin/bash
# Launch Grok 4.6 as the FabGrok implementer. Effort IDs must match grok-4.6.
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONTRACT="$SKILL_DIR/GROK-CONTRACT.md"
GROK_BIN="${GROK_BIN:-$HOME/.grok/bin/grok}"
MODEL="grok-4.6"

# --always-approve means the implementer runs every tool call unattended, and it
# runs as a child process where Claude Code's PreToolUse hooks (redline-guard)
# never see it. These two mechanisms are the only brake on it.
#
# Sandbox: OS-level (Seatbelt on macOS). "workspace" = read anywhere, write only
# to --cwd + /tmp + ~/.grok. Set FABGROK_SANDBOX=off to disable, or name another
# profile (read-only, strict, or a custom one from ~/.grok/sandbox.toml).
SANDBOX="${FABGROK_SANDBOX:-workspace}"

# Deny rules: two threat classes. Deny beats --always-approve.
#  1. Publishing — nothing leaves the machine or lands in history:
#     push, commit, sudo, curl, wget.
#  2. Discarding — nothing throws away the working tree. Lanes may sit
#     UNCOMMITTED in a shared tree; one stash/checkout/clean would erase them
#     all (hand-written into every spec until 2026-08-17, now enforced here).
#     "git reset*" covers --hard plus --merge/--keep, which also move files.
# A run dying on a denied command is the guard working. If a build genuinely
# needs one, edit this list and say so in the report.
DENY_RULES=(
  "Bash(git push*)"
  "Bash(git commit*)"
  "Bash(git reset*)"
  "Bash(git stash*)"
  "Bash(git restore*)"
  "Bash(git checkout*)"
  "Bash(git switch*)"
  "Bash(git clean*)"
  "Bash(rm -rf*)"
  "Bash(sudo*)"
  "Bash(curl*)"
  "Bash(wget*)"
)

usage() {
  cat <<'EOF'
Usage:
  run-implementer.sh --preflight
  run-implementer.sh --dry-run --effort <low|medium|high|xhigh> --spec <file> [--cwd <dir>]
  run-implementer.sh --effort <id> --spec <file> [--cwd <dir>] [--resume <session>] [--max-turns N]

Effort IDs (grok-4.6 only): low, medium, high, xhigh
Aliases: x-high, extra-high, extra_high, extrahigh → xhigh
EOF
}

normalize_effort() {
  local raw
  raw="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d ' ')"
  case "$raw" in
    low|medium|high|xhigh) printf '%s' "$raw" ;;
    x-high|x_high|extrahigh|extra-high|extra_high) printf 'xhigh' ;;
    *) return 1 ;;
  esac
}

turns_for() {
  case "$1" in
    low) echo 25 ;;
    medium) echo 40 ;;
    high) echo 60 ;;
    xhigh) echo 80 ;;
    *) return 1 ;;
  esac
}

preflight() {
  if [ ! -x "$GROK_BIN" ]; then
    if command -v grok >/dev/null 2>&1; then
      GROK_BIN="$(command -v grok)"
    else
      echo "PREFLIGHT FAILED: grok binary not found at $HOME/.grok/bin/grok and not on PATH"
      return 1
    fi
  fi
  if [ ! -f "$CONTRACT" ]; then
    echo "PREFLIGHT FAILED: missing $CONTRACT"
    return 1
  fi
  local listing
  listing="$("$GROK_BIN" models 2>&1)" || {
    echo "PREFLIGHT FAILED: grok models failed"
    echo "$listing"
    return 1
  }
  if ! printf '%s\n' "$listing" | /usr/bin/grep -q -e 'grok-4.6'; then
    echo "PREFLIGHT FAILED: grok-4.6 not in grok models"
    echo "$listing"
    return 1
  fi
  echo "PREFLIGHT OK: $MODEL via $GROK_BIN"
}

EFFORT=""
SPEC=""
CWD=""
RESUME=""
MAX_TURNS=""
MODE="run"

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --preflight) MODE="preflight"; shift ;;
    --dry-run) MODE="dry-run"; shift ;;
    --effort) EFFORT="${2:-}"; shift 2 ;;
    --spec) SPEC="${2:-}"; shift 2 ;;
    --cwd) CWD="${2:-}"; shift 2 ;;
    --resume) RESUME="${2:-}"; shift 2 ;;
    --max-turns) MAX_TURNS="${2:-}"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [ "$MODE" = "preflight" ]; then
  preflight
  exit $?
fi

if [ -z "$EFFORT" ] || [ -z "$SPEC" ]; then
  echo "error: --effort and --spec are required" >&2
  usage >&2
  exit 2
fi

NORM=""
if ! NORM="$(normalize_effort "$EFFORT")"; then
  echo "error: invalid effort '$EFFORT' — grok-4.6 accepts low, medium, high, xhigh" >&2
  exit 2
fi
EFFORT="$NORM"

if [ ! -f "$SPEC" ]; then
  echo "error: spec not found: $SPEC" >&2
  exit 2
fi

if [ -z "$CWD" ]; then
  CWD="$(pwd)"
fi
if [ ! -d "$CWD" ]; then
  echo "error: cwd is not a directory: $CWD" >&2
  exit 2
fi

if [ -z "$MAX_TURNS" ]; then
  MAX_TURNS="$(turns_for "$EFFORT")"
fi

if ! preflight; then
  exit 1
fi

SPEC="$(cd "$(dirname "$SPEC")" && pwd)/$(basename "$SPEC")"
CWD="$(cd "$CWD" && pwd)"

# Pre-assign the session id (grok --session-id) so the resume handle exists in
# meta.txt from second zero. A killed run's id is otherwise unrecoverable — no
# UUID ever appears in grok.log (verified across seven real runs, 2026-08-17).
if [ -n "$RESUME" ]; then
  SESSION_ID="$RESUME"
else
  SESSION_ID="$(/usr/bin/uuidgen | /usr/bin/tr '[:upper:]' '[:lower:]')"
fi

CMD=(
  "$GROK_BIN"
  --prompt-file "$SPEC"
  --model "$MODEL"
  --effort "$EFFORT"
  --always-approve
  --no-plan
  --cwd "$CWD"
  --rules "$(cat "$CONTRACT")"
  --output-format plain
  --max-turns "$MAX_TURNS"
)

if [ "$SANDBOX" != "off" ]; then
  CMD+=(--sandbox "$SANDBOX")
fi

for rule in "${DENY_RULES[@]}"; do
  CMD+=(--deny "$rule")
done

if [ -n "$RESUME" ]; then
  CMD+=(--resume "$RESUME")
else
  CMD+=(--session-id "$SESSION_ID")
fi

echo "FabGrok implementer: $MODEL effort=$EFFORT turns=$MAX_TURNS sandbox=$SANDBOX"
echo "spec: $SPEC"
echo "session: $SESSION_ID  (resume: --resume $SESSION_ID)"

if [ "$MODE" = "dry-run" ]; then
  printf 'DRY-RUN:'
  for p in "${CMD[@]}"; do
    printf ' %s' "$p"
  done
  printf '\n'
  echo "DRY-RUN OK"
  exit 0
fi

# Run bookkeeping lives INSIDE the workspace so the log sits next to the work
# it describes — and the tree stays clean anyway, because .fabgrok/ is added to
# .git/info/exclude (local-only, never a tracked file) below. Decided
# 2026-08-17 after .fabgrok/runs/ blocked a dirty-tree gate in a real build.
# $$ suffix: two runs launched in the same second get distinct dirs.
STAMP="$(date +%Y%m%dT%H%M%S)-$$"
RUN_DIR="$CWD/.fabgrok/runs/$STAMP"
/bin/mkdir -p "$RUN_DIR"
LOG="$RUN_DIR/grok.log"
META="$RUN_DIR/meta.txt"
HEARTBEAT="$RUN_DIR/heartbeat"

IS_REPO=""
if command -v git >/dev/null 2>&1 && git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1; then
  IS_REPO=1
  EXCLUDE_FILE="$(cd "$CWD" && git rev-parse --git-path info/exclude)"
  case "$EXCLUDE_FILE" in /*) : ;; *) EXCLUDE_FILE="$CWD/$EXCLUDE_FILE" ;; esac
  /bin/mkdir -p "$(dirname "$EXCLUDE_FILE")"
  if ! /usr/bin/grep -qs -e '^\.fabgrok/$' "$EXCLUDE_FILE"; then
    echo ".fabgrok/" >> "$EXCLUDE_FILE"
  fi
fi

dirty_count() {
  if [ -n "$IS_REPO" ]; then
    (cd "$CWD" && git status --porcelain 2>/dev/null) | /usr/bin/wc -l | /usr/bin/tr -d ' '
  else
    echo "n/a"
  fi
}

# Snapshot the exact spec text this run received — the source file may be
# edited later for a follow-up round.
/bin/cp "$SPEC" "$RUN_DIR/SPEC.md"

{
  echo "model=$MODEL"
  echo "effort=$EFFORT"
  echo "max_turns=$MAX_TURNS"
  echo "sandbox=$SANDBOX"
  echo "cwd=$CWD"
  echo "spec=$SPEC"
  echo "log=$LOG"
  echo "session=$SESSION_ID"
  echo "pid=$$"
  echo "started=$(date +%s)"
  echo "dirty_before=$(dirty_count)"
} > "$META"
echo "run:  $RUN_DIR"
echo "log:  $LOG"

GROK_PID=""
MON_PID=""

finish_meta() {
  {
    echo "exit=$1"
    echo "finished=$(date +%s)"
    echo "dirty_after=$(dirty_count)"
  } >> "$META"
}

# A trapped kill still leaves a readable record and the resume handle.
# SIGKILL cannot be trapped: a meta.txt with no exit= line and a dead pid=
# means killed hard — resume with the session= id.
on_signal() {
  local sig="$1"
  [ -n "$GROK_PID" ] && kill "$GROK_PID" 2>/dev/null
  [ -n "$MON_PID" ] && kill "$MON_PID" 2>/dev/null
  finish_meta "killed:SIG$sig"
  echo "implementer killed by SIG$sig — resume: --resume $SESSION_ID"
  case "$sig" in
    INT) exit 130 ;;
    HUP) exit 129 ;;
    *)   exit 143 ;;
  esac
}
trap 'on_signal INT' INT
trap 'on_signal TERM' TERM
trap 'on_signal HUP' HUP

set +e
"${CMD[@]}" > "$LOG" 2>&1 &
GROK_PID=$!
echo "grok_pid=$GROK_PID" >> "$META"

# Heartbeat: a plain-format run can sit log-silent for 15+ minutes while the
# model reads context. CPU time climbing under a quiet log = thinking, not hung.
(
  while kill -0 "$GROK_PID" 2>/dev/null; do
    cpu="$(ps -o time= -p "$GROK_PID" 2>/dev/null | /usr/bin/tr -d ' ')"
    bytes="$(/usr/bin/wc -c < "$LOG" 2>/dev/null | /usr/bin/tr -d ' ')"
    echo "hb=$(date +%s) cpu=${cpu:-gone} log_bytes=${bytes:-0}" >> "$HEARTBEAT"
    sleep 30
  done
) &
MON_PID=$!

wait "$GROK_PID"
EC=$?
kill "$MON_PID" 2>/dev/null
wait "$MON_PID" 2>/dev/null
set -e

finish_meta "$EC"
echo "implementer exit=$EC"
/usr/bin/tail -n 40 "$LOG"
exit "$EC"
