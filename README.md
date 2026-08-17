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
  `sudo`, `curl`, `wget`, `gh`, `ssh`, `scp`, `rsync`) and *discarding*
  (`git stash`, `restore`, `checkout`, `switch`, `clean`, `reset`, recursive
  `rm` in its common spellings). Deny beats `--always-approve`.
- **Known limit**: deny rules match the text of Bash commands only. A Python
  or Node script that opens a socket is not caught, and the sandbox limits
  writes, not network. The rules brake accidents; they are not a wall against
  a determined bypass.
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

```bash
git clone https://github.com/ydarwish1/fabgrok-skill ~/.claude/skills/fabgrok
```

The target folder name is load-bearing. It must be exactly `fabgrok`, matching
the `name:` in SKILL.md's frontmatter — Claude Code silently ignores a skill
whose folder and name disagree. A default clone creates `fabgrok-skill`, which
would do exactly that.

Then verify:

```bash
bash ~/.claude/skills/fabgrok/scripts/run-implementer.sh --preflight
bash ~/.claude/skills/fabgrok/scripts/fixtures/verify-parser.sh
```

Both must end green (`PREFLIGHT OK`, `VERIFY PARSER OK`). The fixture suite is
hermetic — it fakes the grok binary — so it passes before Grok Build is even
installed. `--preflight` is the check that the real binary is ready.
