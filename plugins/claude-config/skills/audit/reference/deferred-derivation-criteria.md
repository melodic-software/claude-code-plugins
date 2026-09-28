# Deferred audit derivation criteria (D1–D8)

The claude-config audit engine derived settings-reference and env-var checks from
`llms.txt` in PR #4419. The items below were deferred and remain **hardcoded or
manual** at base `5f2533764`. This file is the tracking slice for
[#4514](https://github.com/melodic-software/claude-code-plugins/issues/4514); it
does not change engine behavior.

Paths are under `plugins/claude-config/skills/audit/` unless noted.

| ID | Open work | Primary touchpoints | Done when |
| --- | --- | --- | --- |
| **D1** | Route Phase 5 `--fix` through `update-config` with the `[Self-Modification]` handshake | `SKILL.md`, `context/procedures.md` | Procedures name the handshake; `--fix` never writes settings without it |
| **D2** | Follow out-of-page links; crawl `llms.txt` beyond the two pages `acquire_page` fetches | `scripts/audit-engine.sh` (~586) | New pages feed the same derivation pipeline as settings-reference |
| **D3** | Apply "derive from docs" to prose in `reference/` and `context/`, including category **D** criteria | `reference/audit-checklist.md`, `context/validation-categories.md` | Each category-D row cites a doc URL or binary describe string, not author memory |
| **D4** | Derive `fallbackModel` raw-length cap (3), model family list, generic enum validation, SchemaStore validation | `scripts/audit-engine.sh` (~1399–1406) | Caps and enums come from docs or schema, with a recorded fallback when docs are silent |
| **D5** | For an undocumented key, quote the binary's describe string (`@internal …`) | `scripts/audit-engine.sh` finding text | Report body includes the describe line when docs lack the key |
| **D6** | Check nested keys beyond `permissions.*` | `scripts/audit-engine.sh` (~765–803) | Nested paths in settings are validated against docs/schema |
| **D7** | Check fix versions in `reference/known-issues.md` against the Claude Code version the engine records | `reference/known-issues.md`, engine version stamp | Stale "fixed in" lines fail or warn with the recorded binary version |
| **D8** | Derive `SECRET_RE` from docs (literal today ~1089) | `scripts/audit-engine.sh` | Pattern documented and sourced; literal is fallback only |

## Known defects from the #4419 merge gate (same issue, separate from D1–D8)

| Defect | Location | Risk today |
| --- | --- | --- |
| `sr_section` rescans the whole page on every call | `scripts/audit-engine.sh` ~695 | Low while settings-reference ≈445 KB; high if a multi-MB page is fetched |
| Key name containing U+0000 splits into two rows in the NUL-delimited key stream | `scripts/audit-engine.sh` ~803 | The CLI cannot use such a key |

## Related docs

- [audit-checklist.md](audit-checklist.md) — category tables the engine implements today
- [context/validation-categories.md](../context/validation-categories.md) — reasoning behind categories
- Issue [#4514](https://github.com/melodic-software/claude-code-plugins/issues/4514)

## Next

When implementing D1–D8, extend `scripts/audit-engine.test.sh` for each criterion and link
the row here to the deriving function or doc URL in the same PR.
