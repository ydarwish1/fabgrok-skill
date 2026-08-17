---
name: fabgrok
description: >
  Fable writes a frozen spec; Grok 4.6 implements it in Grok Build. Use ONLY
  on explicit invocation — "/fabgrok", "fabgrok", "/fabgrok low|medium|high|xhigh",
  "fable grok", or "Fable specs, Grok types". Never the default for ordinary
  builds. Effort IDs are Grok 4.6's: low, medium, high, xhigh.
---

# FabGrok — Fable specs, Grok 4.6 types

You are the orchestrator (Fable). You do not write implementation code. Grok 4.6
does, through the Grok Build CLI (`grok`), which is the harness people use for
this split.

Read [references/effort.md](references/effort.md) and
[references/spec-template.md](references/spec-template.md) when you need the
tables. Do not restate them.

## 0. Effort (default `xhigh`)

Parse the invocation. Consume a leading effort token if present:

- `/fabgrok xhigh add login` → effort `xhigh`, brief `add login`
- `/fabgrok --effort high add login` / `effort=high` → same
- Aliases in `references/effort.md` normalize to the official ID

**No effort token → use `xhigh`.** Do not ask. Say which effort you picked in
one line, then continue. Yusif set xhigh as the standing default (2026-08-16) —
he drops to a lower ID explicitly when he wants one.

Only these four IDs are legal: `low`, `medium`, `high`, `xhigh`. An invalid ID
(`max`, `none`, `minimal`, `deep`) is a typo, not a request — say the ID is not
real, name the four, and stop. Do not silently fall back to `xhigh`.

If there is an effort but no task, ask "build what?" and stop.

`/fabgrok <task>` is the go signal. Do not ask a confirmation.

## 1. Preflight

Run the script's preflight before writing the spec:

```bash
bash "$HOME/.claude/skills/fabgrok/scripts/run-implementer.sh" --preflight
```

`PREFLIGHT OK` is the only pass. Anything else: stop and report. Do not fall
back to writing the code yourself — that defeats the skill.

## 2. You plan, Grok types

- Read the repo enough to name exact paths. One batched probe, then spec.
- Write a spec that follows `references/spec-template.md`. Save it to any
  durable absolute path (a scratchpad works) and pass it with `--spec`; the
  script snapshots it into the run dir as `SPEC.md`, so every run records the
  exact spec text it received even if you edit the source for a later round.
- You never edit product code. Misses go back as a new spec + another `grok` run.
- Do not spawn an Antigravity/Claude subagent as the implementer. The
  implementer is `grok` (Grok Build). Native harness, not a Gemini/Claude worker.
- Skip this skill for a one-line typo you can see. `/fabgrok` is for a real build.

## 3. Invoke Grok 4.6

```bash
bash "$HOME/.claude/skills/fabgrok/scripts/run-implementer.sh" \
  --effort <id> \
  --spec /abs/path/to/.fabgrok/runs/<stamp>/SPEC.md \
  --cwd /abs/path/to/workspace
```

The script pins `--model grok-4.6`, `--effort <id>`, `--always-approve`,
`--no-plan`, `--prompt-file`, and `--rules` from `GROK-CONTRACT.md`. Do not
invent a different `grok` command.

**Guardrails the script also pins** (Grok runs as a child process, so Claude
Code's redline-guard hook never sees its commands — these are the only brake):

- `--sandbox workspace` — Seatbelt-enforced: Grok reads anywhere but writes only
  under `--cwd`, `/tmp`, and `~/.grok`. Override with `FABGROK_SANDBOX=<profile>`
  or `FABGROK_SANDBOX=off`; profiles are `workspace`, `read-only`, `strict`.
- `--deny` rules in two classes: **publishing** (`git push`, `git commit`,
  `sudo`, `curl`, `wget`) and **discarding** (`git stash`, `restore`,
  `checkout`, `switch`, `clean`, `reset` in all forms, `rm -rf`). The discard
  class exists because lanes may sit uncommitted in a shared tree — one stash
  would erase them all (2026-08-17, six lanes). Deny beats `--always-approve`
  (proven 2026-08-16 with both controls). If a build genuinely needs one, edit
  `DENY_RULES` at the top of the script and say so in the report.

A run that dies on a denied command is the guard working. Do not disable a rule
to get past it without telling Yusif.

**Known sandbox effect:** `workspace` blocks installs that write outside the
workspace — `pip install --user` fails with `Operation not permitted` on
`~/Library/Python/...` (seen live 2026-08-16). Node is unaffected because
`npm install` writes `node_modules/` inside the cwd. If a spec needs Python
packages, tell Grok to build a venv **inside the workspace**, or name an
interpreter that already has them. Do not turn the sandbox off for this.

**Launching:** foreground if it should finish in a few minutes. For anything
longer, do not trust the harness's background flag — the host has reaped a
backgrounded wrapper mid-run (2026-08-17, a lane died with ~9 files of edits
and no notes). Launch with `nohup` and poll the run dir instead:

```bash
nohup bash "$HOME/.claude/skills/fabgrok/scripts/run-implementer.sh" \
  --effort <id> --spec /abs/spec.md --cwd /abs/workspace \
  > /tmp/fabgrok-launch.log 2>&1 &
```

**Reading a run from outside** — everything is in `<cwd>/.fabgrok/runs/<stamp>/`
(the dir is auto-added to `.git/info/exclude`, so it never dirties the tree):

- `meta.txt` gains `exit=` the moment the run ends on any path, including
  trapped kills (`exit=killed:SIGTERM`). No `exit=` and `pid=` dead = killed
  hard (SIGKILL). No `exit=` and pid alive = still working.
- `heartbeat` gets a line every 30s with Grok's CPU time — CPU climbing under
  a silent log is thinking, not hung (a healthy run once sat at 302 log bytes
  for fifteen minutes).
- `dirty_before=` / `dirty_after=` in `meta.txt` bracket the run's git
  footprint; after an interrupted run, `git status` tells you what it left.
- `session=` in `meta.txt` is the way back in: rerun the same command with
  `--resume <session>` — only when the run died mid-task and the spec is
  unchanged.

## 4. Check (you)

Judge the artifacts, not Grok's prose.

- Read `FILES CHANGED` / the log.
- Confirm each Acceptance bullet with a command (`ls`, `grep`, the test the
  spec named).
- **Run the composite artifact end to end, not only the bullets.** An
  acceptance list is checked item by item, so it structurally cannot catch a
  defect in the wrapper the items live in — a drills suite once passed every
  bullet yet aborted at 86/268 and exited 0 (2026-08-17). If the deliverable
  is a script, run the whole script; if a suite, the whole suite — and read
  its tail, not just its exit code.
- Failures: write a fix spec (what failed, evidence, exact repair). Invoke
  again. You still do not patch the code.
- Report in 5 lines or fewer: effort used, what shipped, how you checked,
  anything still open.

## Antigravity

This skill is global for Claude Code agents (`~/.claude/skills/fabgrok`) and
for native Antigravity agents (`~/.gemini/config/skills/fabgrok` — a symlink
to the same directory, so edits land in both automatically).
Invoke on Fable, then let the script start Grok 4.6. `/fabgrok xhigh` skips
the effort question.
