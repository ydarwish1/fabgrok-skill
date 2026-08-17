#!/bin/bash
# Parser + dry-run + lifecycle checks. Fully hermetic: every check runs against
# a fake GROK_BIN built below, so the suite passes on a machine (or CI runner)
# with no grok installed and never spends an API call. Paths are derived from
# this file's own location — the suite tests the tree it lives in, wherever
# that tree is. Temp dirs are left under the system temp dir for the OS to
# purge.
set -u
FIX_DIR="$(cd "$(dirname "$0")" && pwd)"
S="$(cd "$FIX_DIR/../.." && pwd)/scripts/run-implementer.sh"
SPEC="$FIX_DIR/dry-spec.md"
CWD="$FIX_DIR"
fails=0

DRILL="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/fabgrok-drill.XXXXXX")"
OUT="$DRILL/out.txt"
ERR="$DRILL/err.txt"

# Fakes first: even --dry-run runs preflight, which needs a grok that answers
# `models`. Exporting the fast fake keeps the whole suite grok-free; the two
# lifecycle drills override it per call.
FAST="$DRILL/grok-fast"
{
  echo '#!/bin/bash'
  echo 'if [ "${1:-}" = "models" ]; then echo "grok-4.6"; exit 0; fi'
  echo 'echo "fake grok run"'
  echo 'exit 0'
} > "$FAST"
/bin/chmod +x "$FAST"

SLOW="$DRILL/grok-slow"
{
  echo '#!/bin/bash'
  echo 'if [ "${1:-}" = "models" ]; then echo "grok-4.6"; exit 0; fi'
  echo 'sleep 60'
} > "$SLOW"
/bin/chmod +x "$SLOW"

export GROK_BIN="$FAST"

check_bad() {
  local name="$1"
  shift
  "$S" "$@" >"$OUT" 2>"$ERR"
  local ec=$?
  if [ "$ec" -eq 2 ]; then
    echo "PASS reject $name (exit=2)"
  else
    echo "FAIL reject $name (exit=$ec)"
    fails=$((fails + 1))
  fi
}

check_dry() {
  local name="$1"
  local expect="$2"
  shift 2
  "$S" --dry-run --spec "$SPEC" --cwd "$CWD" "$@" >"$OUT" 2>"$ERR"
  local ec=$?
  if [ "$ec" -ne 0 ]; then
    echo "FAIL dry $name (exit=$ec)"
    /bin/cat "$ERR"
    fails=$((fails + 1))
    return
  fi
  if /usr/bin/grep -q -e "effort=$expect" "$OUT" && \
     /usr/bin/grep -q -e "--effort $expect" "$OUT" && \
     /usr/bin/grep -q -e "--model grok-4.6" "$OUT" && \
     /usr/bin/grep -q -e "DRY-RUN OK" "$OUT"; then
    echo "PASS dry $name -> $expect"
  else
    echo "FAIL dry $name expected effort=$expect"
    /bin/cat "$OUT"
    fails=$((fails + 1))
  fi
}

check_bad missing-effort --spec "$SPEC"
check_bad max --effort max --spec "$SPEC"
check_bad none --effort none --spec "$SPEC"
check_bad minimal --effort minimal --spec "$SPEC"
check_bad deep --effort deep --spec "$SPEC"

check_dry low low --effort low
check_dry medium medium --effort medium
check_dry high high --effort high
check_dry xhigh xhigh --effort xhigh
check_dry alias-x-high xhigh --effort x-high
check_dry alias-extra-high xhigh --effort extra-high

check_guards() {
  "$S" --dry-run --spec "$SPEC" --cwd "$CWD" --effort xhigh \
    >"$OUT" 2>"$ERR"
  if /usr/bin/grep -q -e '--sandbox workspace' "$OUT"; then
    echo "PASS sandbox flag on by default"
  else
    echo "FAIL sandbox flag missing"
    fails=$((fails + 1))
  fi
  local r
  # Publishing class + discarding class. Both must survive edits.
  for r in 'git push' 'git commit' 'git reset' 'git stash' 'git restore' \
           'git checkout' 'git switch' 'git clean' \
           'rm -rf' 'rm -fr' 'rm -R' 'rm -r ' 'rm -f -r' \
           'sudo' 'curl' 'wget' 'gh ' 'ssh' 'scp' 'rsync'; do
    if /usr/bin/grep -q -e "--deny Bash($r" "$OUT"; then
      echo "PASS deny rule: $r"
    else
      echo "FAIL deny rule missing: $r"
      fails=$((fails + 1))
    fi
  done
  # Session id must be pre-assigned so the resume handle exists before launch.
  if /usr/bin/grep -q -e '--session-id' "$OUT"; then
    echo "PASS session id pre-assigned"
  else
    echo "FAIL --session-id missing from pinned command"
    fails=$((fails + 1))
  fi
}

check_sandbox_off() {
  FABGROK_SANDBOX=off "$S" --dry-run --spec "$SPEC" --cwd "$CWD" --effort xhigh \
    >"$OUT" 2>"$ERR"
  if /usr/bin/grep -q -e '--sandbox' "$OUT"; then
    echo "FAIL FABGROK_SANDBOX=off still passed --sandbox"
    fails=$((fails + 1))
  else
    echo "PASS FABGROK_SANDBOX=off drops --sandbox"
  fi
}

check_resume() {
  # --resume must swap the pre-assigned --session-id for --resume <id>.
  # The DRY-RUN dump spans many lines (the --rules arg embeds the contract),
  # so grep the whole output — minus the "session:" header, which always
  # echoes a "--resume <id>" hint and would make the first check vacuous.
  "$S" --dry-run --spec "$SPEC" --cwd "$CWD" --effort xhigh --resume abc-123 \
    >"$OUT" 2>"$ERR"
  if /usr/bin/grep -v -e '^session:' "$OUT" | /usr/bin/grep -q -e '--resume abc-123'; then
    echo "PASS resume flag passed through"
  else
    echo "FAIL --resume abc-123 missing from pinned command"
    fails=$((fails + 1))
  fi
  if /usr/bin/grep -q -e '--session-id' "$OUT"; then
    echo "FAIL resume run still pins --session-id"
    fails=$((fails + 1))
  else
    echo "PASS resume run drops --session-id"
  fi
}

check_guards
check_sandbox_off
check_resume

if [ -d "$CWD/.fabgrok" ]; then
  echo "FAIL dry-run created $CWD/.fabgrok"
  fails=$((fails + 1))
else
  echo "PASS dry-run created no .fabgrok dir"
fi

# ---------------------------------------------------------------------------
# Lifecycle drills. A meta.txt line that has never been demanded by a failing
# check is indistinguishable from one that cannot be written.
# ---------------------------------------------------------------------------

drill_assert() {
  local name="$1" cond="$2"
  if eval "$cond"; then
    echo "PASS drill $name"
  else
    echo "FAIL drill $name"
    fails=$((fails + 1))
  fi
}

# Drill 1: clean exit. meta.txt must record the whole lifecycle, the spec must
# be snapshotted, and .fabgrok/ must not dirty a git tree.
W1="$DRILL/work-clean"
/bin/mkdir -p "$W1"
git -C "$W1" init -q
GROK_BIN="$FAST" "$S" --effort low --spec "$SPEC" --cwd "$W1" \
  >"$DRILL/clean.out" 2>&1
ec=$?
RD1="$(ls -d "$W1"/.fabgrok/runs/* 2>/dev/null | /usr/bin/head -1)"
drill_assert "clean wrapper exit 0"    "[ $ec -eq 0 ]"
drill_assert "clean run dir exists"    "[ -n \"$RD1\" ] && [ -d \"$RD1\" ]"
drill_assert "clean meta exit=0"       "/usr/bin/grep -q -e '^exit=0$' \"$RD1/meta.txt\""
drill_assert "clean meta session uuid" "/usr/bin/grep -q -E -e '^session=[0-9a-f-]{36}$' \"$RD1/meta.txt\""
drill_assert "clean meta dirty_after"  "/usr/bin/grep -q -e '^dirty_after=' \"$RD1/meta.txt\""
drill_assert "clean spec snapshot"     "/usr/bin/cmp -s \"$SPEC\" \"$RD1/SPEC.md\""
if git -C "$W1" status --porcelain | /usr/bin/grep -q -e 'fabgrok'; then
  echo "FAIL drill .fabgrok dirties the tree"
  fails=$((fails + 1))
else
  echo "PASS drill .fabgrok excluded from git status"
fi

# Drill 2: plant the real 2026-08-17 failure — the wrapper is killed mid-run —
# and require the record to survive it.
W2="$DRILL/work-kill"
/bin/mkdir -p "$W2"
GROK_BIN="$SLOW" "$S" --effort low --spec "$SPEC" --cwd "$W2" \
  >"$DRILL/kill.out" 2>&1 &
WPID=$!
sleep 3
kill -TERM "$WPID" 2>/dev/null
wait "$WPID" 2>/dev/null
ec=$?
RD2="$(ls -d "$W2"/.fabgrok/runs/* 2>/dev/null | /usr/bin/head -1)"
drill_assert "kill wrapper exit 143"    "[ $ec -eq 143 ]"
drill_assert "kill run dir exists"      "[ -n \"$RD2\" ] && [ -d \"$RD2\" ]"
drill_assert "kill meta killed:SIGTERM" "/usr/bin/grep -q -e '^exit=killed:SIGTERM$' \"$RD2/meta.txt\""
drill_assert "kill meta session uuid"   "/usr/bin/grep -q -E -e '^session=[0-9a-f-]{36}$' \"$RD2/meta.txt\""
drill_assert "kill heartbeat written"   "[ -s \"$RD2/heartbeat\" ]"

if [ "$fails" -eq 0 ]; then
  echo "VERIFY PARSER OK"
  exit 0
fi
echo "VERIFY PARSER FAILED count=$fails"
exit 1
