# FabGrok spec template

Fable fills every section. Grok 4.6 never sees the chat — only this file.

```markdown
# SPEC

## Goal
One paragraph. What exists when this is done.

## Implement
Numbered work items. Each item names exact paths to create or edit.

## Do not touch
Paths and concerns that are out of scope.

## Constraints
Stack, style, existing conventions, forbidden approaches.

## Acceptance
Checkable bullets. A command, a file existing, a string present, a test passing.
End with one composite bullet that executes the entire deliverable end to end.

## Verify
Commands Grok should run after editing (it can use the shell).

## Report
End with:
- FILES CHANGED: one path per line
- VERIFY: pass/fail per acceptance bullet
- COULD NOT: anything blocked, with the reason
```

Rules for the spec itself:

- Self-contained. No "as we discussed". Name files, strings, and commands.
- Implementation contract, not a vibe. If two readings are possible, pick one in the spec.
- Size one delegation so it can finish. Split a 10-file rewrite into two specs.
- Do not tell Grok to redesign, "improve as you see fit", or invent extra features.
- Acceptance ends with a composite check: run the whole deliverable (the full
  suite, the entire script), not only its parts. Per-item bullets cannot catch
  a defect in the wrapper they live in — one suite passed every bullet yet
  aborted at 86/268 drills and exited 0 (2026-08-17).
