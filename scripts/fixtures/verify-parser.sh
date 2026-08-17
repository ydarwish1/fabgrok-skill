#!/bin/bash
# Parser + dry-run + lifecycle checks. Never calls the real grok binary for a
# run: the two lifecycle drills use a fake GROK_BIN. Temp dirs are left under
# /tmp for the OS to purge.
set -u
S="/Users/yusifdarwish/.claude/skills/fabgrok/scripts/run-implementer.sh"
SPEC="/Users/yusifdarwish/.claude/skills/fabgrok/scripts/fixtures/dry-spec.md"
CWD="/Users/yusifdarwish/.claude/skills/fabgrok/scripts/fixtures"
fails=0

check_bad() {
  local name="$1"
  shift
  "$S" "$@" >"/tmp/fabgrok-verify-out.txt" 2>"/tmp/fabgrok-verify-err.txt"
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
  "$S" --dry-run --spec "$SPEC" --cwd "$CWD" "$@" >"/tmp/fabgrok-verify-out.txt" 2>"/tmp/fabgrok-verify-err.txt"
  local ec=$?
  if [ "$ec" -ne 0 ]; then
    echo "FAIL dry $name (exit=$ec)"
    /bin/cat /tmp/fabgrok-verify-err.txt
    fails=$((fails + 1))
    return
  fi
  if /usr/bin/grep -q -e "effort=$expect" /tmp/fabgrok-verify-out.txt && \
     /usr/bin/grep -q -e "--effort $expect" /tmp/fabgrok-verify-out.txt && \
     /usr/bin/grep -q -e "--model grok-4.6" /tmp/fabgrok-verify-out.txt && \
     /usr/bin/grep -q -e "DRY-RUN OK" /tmp/fabgrok-verify-out.txt; then
    echo "PASS dry $name -> $expect"
  else
    echo "FAIL dry $name expected effort=$expect"
    /bin/cat /tmp/fabgrok-verify-out.txt
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
    >"/tmp/fabgrok-verify-out.txt" 2>"/tmp/fabgrok-verify-err.txt"
  if /usr/bin/grep -q -e '--sandbox workspace' /tmp/fabgrok-verify-out.txt; then
    echo "PASS sandbox flag on by default"
  else
    echo "FAIL sandbox flag missing"
    fails=$((fails + 1))
  fi
  local r
  # Publishing class + discarding class. Both must survive edits.
  for r in 'git push' 'git commit' 'git reset' 'git stash' 'git restore' \
           'git checkout' 'git switch' 'git clean' 'rm -rf' 'sudo' 'curl' 'wget'; do
    if /usr/bin/grep -q -e "--deny Bash($r" /tmp/fabgrok-verify-out.txt; then
      echo "PASS deny rule: $r"
    else
      echo "FAIL deny rule missing: $r"
      fails=$((fails + 1))
    fi
  done
  # Session id must be pre-assigned so the resume handle exists before launch.
  if /usr/bin/grep -q -e '--session-id' /tmp/fabgrok-verify-out.txt; then
    echo "PASS session id pre-assigned"
  else
    echo "FAIL --session-id missing from pinned command"
    fails=$((fails + 1))
  fi
}

check_sandbox_off() {
  FABGROK_SANDBOX=off "$S" --dry-run --spec "$SPEC" --cwd "$CWD" --effort xhigh \
    >"/tmp/fabgrok-verify-out.txt" 2>"/tmp/fabgrok-verify-err.txt"
  if /usr/bin/grep -q -e '--sandbox' /tmp/fabgrok-verify-out.txt; then
    echo "FAIL FABGROK_SANDBOX=off still passed --sandbox"
    fails=$((fails + 1))
  else
    echo "PASS FABGROK_SANDBOX=off drops --sandbox"
  fi
}

check_guards
check_sandbox_off

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

DRILL="$(/usr/bin/mktemp -d /tmp/fabgrok-drill.XXXXXX)"

# Fake grok: answers preflight's `models` probe, exits 0 fast as a run.
FAST="$DRILL/grok-fast"
{
  echo '#!/bin/bash'
  echo 'if [ "${1:-}" = "models" ]; then echo "grok-4.6"; exit 0; fi'
  echo 'echo "fake grok run"'
  echo 'exit 0'
} > "$FAST"
/bin/chmod +x "$FAST"

# Fake grok that hangs, for the kill drill.
SLOW="$DRILL/grok-slow"
{
  echo '#!/bin/bash'
  echo 'if [ "${1:-}" = "models" ]; then echo "grok-4.6"; exit 0; fi'
  echo 'sleep 60'
} > "$SLOW"
/bin/chmod +x "$SLOW"

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
