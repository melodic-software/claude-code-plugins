# E2E run configuration — `.claude/testing/e2e.md`

The consumer-tracked config surface for `/testing:run-e2e`. It carries two per-operator / per-repo preferences: how a run captures evidence, and whether the browser is visible. The surface identity is its whole path relative to `.claude/` — `testing/e2e.md` — so its layers live at `~/.claude/testing/e2e.md` (user-global), `${CLAUDE_PROJECT_DIR}/.claude/testing/e2e.md` (team), and `${CLAUDE_PROJECT_DIR}/.claude/testing/e2e.local.md` (local overlay).

This file owns the keys — their meaning, allowed values, defaults, and precedence. How the layers merge is owned by the layering contract; see the [consumer-config layering contract](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/consumer-config-layering/README.md). The two compose: this doc declares the keys and points there for layer mechanics.

## Keys

| Key | Values | Default | Merge |
|---|---|---|---|
| `recording` | `video` \| `gif` \| `off` | `off` | per-key override |
| `browser_mode` | `headed` \| `headless` | `headless` | per-key override |

This surface merges by **per-key override**: a later layer replaces an earlier layer's value key by key, and a key absent from a later layer keeps the earlier value. The values are closed scalars — concatenation would be meaningless — so per-key override is the sanctioned form. The layering contract requires a surface to declare its merge form next to its keys; this is that declaration.

### `recording`

Selects whether a run captures a moving record in addition to the mandatory screenshot evidence.

- `off` (default) — no recording; the evidence-contract screenshots stay the floor.
- `video` — record via the playwright CLI. Preferred for long or multi-page flows where a screenshot set loses the sequence.
- `gif` — record via `gif_creator`. Preferred for short demos worth showing inline.

A recording always supplements screenshot evidence; it never replaces it.

### `browser_mode`

Selects whether the driven browser is visible.

- `headless` (default) — drive without a visible window; preserves current behavior.
- `headed` — surface the browser window for direct observation.

`run-e2e` resolves the value and passes it through to the executor, which owns the flag that realizes it.

## Key ownership — policy, not mechanics

`run-e2e` owns capture **policy**: what evidence a run produces, which recording format, and the visibility preference. `/playwright:playwright` owns the **mechanics**: how the browser is launched and driven. These keys are policy inputs — `run-e2e` resolves them and passes the resolved values through; the executor realizes them. A key here names a preference the executor honors, never a browser flag.

## Precedence

The file layers merge per the layering contract — a later layer refines an earlier one, so `local overlay` > `team` > `user-global`. Above the file layers, `run-e2e` treats these keys as **defaults only**: an explicit instruction in the session prompt always wins. "Run this headed" overrides a `browser_mode: headless` resolved from any file layer.

The full ladder, highest authority first:

1. Explicit session prompt
2. Local overlay (`.claude/testing/e2e.local.md`)
3. Team (`.claude/testing/e2e.md`)
4. User-global (`~/.claude/testing/e2e.md`)
5. Bundled default (`recording: off`, `browser_mode: headless`)
