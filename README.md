# fabgrok

**Fable specs, Grok types.**

A [Claude Code](https://claude.com/claude-code) / Antigravity skill that splits a
build between two models: the orchestrating model (Claude Fable) plans and writes
a frozen spec, and **Grok 4.6 in Grok Build does 100% of the implementation
typing**. The orchestrator never edits product code — misses go back as a new
spec and another run.

## How it works

1. `/fabgrok <task>` — the orchestrator reads the repo, then writes a
   self-contained spec (`references/spec-template.md`).
2. `scripts/run-implementer.sh` launches the Grok Build CLI headless with the
   spec, a pinned model and effort, an OS-level sandbox, and deny rules.
3. The orchestrator judges the artifacts, not the prose: it confirms every
   acceptance bullet with a command and runs the composite deliverable end to
   end.

## Safety model

- **Sandbox** (macOS Seatbelt): Grok reads anywhere, writes only under the
  workspace, `/tmp`, and `~/.grok`.
- **Deny rules** in two classes — *publishing* (`git push`, `git commit`,
  `sudo`, `curl`, `wget`) and *discarding* (`git stash`, `restore`, `checkout`,
  `switch`, `clean`, `reset`, `rm -rf`). Deny beats `--always-approve`.
- **Honest refusals**: a spec item the implementer cannot verify is recorded
  under `COULD NOT`, never shipped as a check that cannot fail.
- **Every run leaves a record** in `<cwd>/.fabgrok/runs/<stamp>/`: `meta.txt`
  (pre-assigned resume session id, pid, exit code — written even when the run
  is killed), a 30-second `heartbeat` with CPU time, a snapshot of the exact
  spec used, and the full log. The run dir is auto-excluded from git.

## Layout

```
SKILL.md                      the skill entry point
GROK-CONTRACT.md              the implementer's standing rules
references/effort.md          effort IDs and aliases
references/spec-template.md   spec structure the orchestrator fills
scripts/run-implementer.sh    the launcher: sandbox, deny rules, lifecycle
scripts/fixtures/             parser checks + lifecycle drills (no API calls)
```

## Requirements

- Grok Build CLI (`grok`) with access to `grok-4.6`
- bash, git, macOS (for the Seatbelt sandbox profiles)

## Install

Copy or clone this directory to `~/.claude/skills/fabgrok`. Then verify:

```bash
bash scripts/run-implementer.sh --preflight
bash scripts/fixtures/verify-parser.sh
```

Both must end green (`PREFLIGHT OK`, `VERIFY PARSER OK`).
