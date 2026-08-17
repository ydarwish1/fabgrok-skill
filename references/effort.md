# Grok 4.6 effort names

These are the only effort IDs grok-4.6 accepts (`~/.grok/models_cache.json` → `reasoning_efforts`). Do not invent `max`, `none`, `minimal`, or `deep`.

| ID | Label | Use for |
|---|---|---|
| `low` | Low Effort | Tiny, obvious edits. Fast. |
| `medium` | Medium Effort | One scoped feature with standard tests. |
| `high` | High Effort | Multi-file work that needs careful reasoning. |
| `xhigh` | Extra High Effort | Long-running / hard implementation. **The default** — used whenever `/fabgrok` is invoked with no effort token (Yusif, 2026-08-16). |

Aliases the parser accepts → official ID:

- `x-high`, `x_high`, `extra-high`, `extra_high`, `extrahigh`, `extra high` → `xhigh`

`/fabgrok <id>` must use one of the four IDs (or an alias above). The script rejects everything else. `/fabgrok <task>` with no ID runs at `xhigh`.
