# Research index — startup-context-baseline

Nine dispatched runs. Parent owns: re-surfacing `open_questions`, dispatching the sibling verifier,
applying project fit, and writing both results back here (parent-contract.md, post-dispatch boundary).

| Run | Slice | Status | Verification |
|---|---|---|---|
| connectors | `connectors/` | **complete** — 8 sidecars, both gates exit 0 | pending |
| workflows | `workflows/` | **complete** — `RESEARCH.md`, 6 sidecars, coverage complete | pending |
| bundled-skills | `bundled-skills/` | **complete** — 5 sidecars, both gates exit 0 | skillOverrides reproduced in-session |
| artifacts | `artifacts/` | **complete** — 6 sidecars, both gates exit 0 | Artifact deny delta reproduced in-session |
| tool-definitions | `tool-definitions/` | **complete** — 7 sidecars, both gates exit 0 | **reproduced in-session, see MEASUREMENTS.md** |
| plugins-mcp | `plugins-mcp/` | **complete** — 7 sidecars, both gates exit 0 | plugin-disable cap test reproduced in-session |
| auto-mode-gates | `auto-mode-gates/` | **complete** — 5 sidecars, both gates exit 0 | pending |
| context-command | `context-command/` | **complete** — 6 sidecars, coverage exit 0 | System-tools subtraction reproduced in-session |
| system-prompt-agents-styles | `system-prompt-agents-styles/` | **complete** — 7 sidecars, both gates exit 0 | SIMPLE vs SIMPLE_SYSTEM_PROMPT split verified in-session (binary) |

## Cross-cutting finding — the mechanism question is answered for at least one lever

**`disableWorkflows` removes the tool schema from the request payload; it does not merely refuse
invocation.** Evidence is Tier 0 (installed v2.1.232 binary: `isEnabled:()=>jD()`, tool array
filtered by `isEnabled()` before request assembly, two code paths) plus an independent request-body
diff. **The official docs alone do not settle it** — they state behavioral consequences only.

This matters far beyond workflows: it establishes that Claude Code has *both* a schema-removal path
and separate refuse-at-invocation paths (`validateInput`, `checkPermissions`). So "disable it to
save tokens" is true or false **per lever, depending on which path that lever is wired to** — it can
never be assumed. Every remaining run's lever must be classified on this axis before the skill
recommends it. This is the single verification target worth spending a sibling verifier on, because
one answer serves all nine runs.

## Open questions carried forward

- **Q13 remains open.** Whether a *deferred* tool costs prefix tokens is still unresolved. Workflows
  is not a fixed-deferral tool: eligibility comes from server-side config
  (`tengu_non_deferrable_builtins`, local default empty) that the agent could not read. Confirmed
  only that `Workflow` IS in the initial request body under `claude -p`; interactive-session
  behavior unverified.
- **No `/context` row for workflows.** Its cost folds into the generic `System tools` total,
  measurable only by differencing that row across a toggle. Direct confirmation of the attribution
  gap the skill exists to fill — and direct support for the Q12 measure/toggle/re-measure loop,
  which is now the *only* way to price this lever.
- **`CLAUDE_CODE_DISABLE_WORKFLOWS` tests truthiness, not `=== 1`.** So `…=0` also disables. A
  footgun worth surfacing in the report; an operator "turning it off" turns it on.
- **Env var is OR-ed ahead of settings** — nothing re-enables against it. Precedence for the
  wizard's explanation text.
- **Undocumented `enableWorkflows` key** found only in the binary. **Settled by repo doctrine, not
  re-litigated:** `claude-config:unhobble` already handles the identical case for
  `CLAUDE_CODE_SIMPLE=1` — name it, state that it is undocumented and may vanish, neither set it nor
  depend on it. The skill may *report* an undocumented key it detects; it must never *recommend* one.
- **Researcher `skills:` preload did not fire** in the dispatched run — the agent read SKILL.md
  manually. The echoed preload sentinel therefore proves the agent read the file, not that preload
  worked. Do not treat a matching token as proof of preload. Worth a separate issue against
  `discovery`.
- **`www.aihero.dev` is egress-blocked in this environment** (WebFetch EGRESS_BLOCKED, curl 403), so
  the course's own numbers cannot be re-read first-hand. All source figures stay as the operator
  pasted them.
- **Methodology correction to apply to remaining runs:** a `WebFetch` of the settings and env-vars
  reference pages reported both workflow keys absent — wrong, caused by truncation on 334 KB /
  404 KB pages. Enumerate settings keys from downloaded pages, never from a fetch summary. Any
  remaining run that reports a key "absent from the docs" on WebFetch evidence alone must be
  re-checked before that claim is accepted.
