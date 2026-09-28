# Fan-out worker brief (paste into spawn prompts)

Evidence-only subtree worker for `/disk-hygiene:clean` home or large-target audits. The parent
owns classification, the single report, approvals, preview, and execution. You return scan
evidence only.

## Bash contract (guard-admitted shapes only)

Every engine call must be a **single** guarded invocation of `hygiene.py` with no shell chaining,
redirection, or extra commands in the same tool call. Required flags on every scan:

- `--data-root "${CLAUDE_PLUGIN_DATA}"` (must match the plugin data directory the belt authorized)
- `--project-dir "${CLAUDE_PROJECT_DIR}"` when the consumer project has standing policy files
- `--output "<run-dir>/snapshot.json"` under `${CLAUDE_PLUGIN_DATA}/runs/…`, never inside the target

Use the hook Python launcher from the skill (`<hook-python>` in `SKILL.md`), not a bare `python3`
on PATH.

Denied: `apply`, `preview`, `handoff-verify`, `rm`, `del`, moves, or any command that mutates the
target. Denied: compound shells (`;`, `&&`, `|`) wrapping the engine.

## Scan invocation templates

**Exact subtree sizing (no per-entry inventory, no entry cap):**

```text
"<hook-python>" "${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/hygiene.py" scan \
  --target "<subtree-path>" --output "<run-dir>/sizes.json" \
  --project-dir "${CLAUDE_PROJECT_DIR}" --data-root "${CLAUDE_PLUGIN_DATA}" \
  --sizes-only
```

Read `inventory_mode: sizes-only` and `rollup_precision: exact` on stdout. `children_rollup` rows
with `walked: true` are exact totals, not depth-cut floors.

**Bounded inventory (hints + handoff paths):**

```text
"<hook-python>" "${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/hygiene.py" scan \
  --target "<subtree-path>" --output "<run-dir>/snapshot.json" \
  --project-dir "${CLAUDE_PROJECT_DIR}" --data-root "${CLAUDE_PLUGIN_DATA}" \
  [--max-depth <N>] [--confirmed-large-scan]
```

Depth-cut rollups carry `walked: false` and `unwalked_reasons`; do not treat them as exact sizes.

**Home fan-out after depth-1 (selected top-level children only):**

```text
"<hook-python>" "${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/hygiene.py" scan \
  --target "<home-path>" --output "<run-dir>/snapshot.json" \
  --project-dir "${CLAUDE_PROJECT_DIR}" --data-root "${CLAUDE_PLUGIN_DATA}" \
  --root-children --root-child "<ChildName>" [--root-child "<Other>"]...
```

## Evidence-only rules

- Report only what the snapshot JSON and stdout payload state; quote `children_rollup`, `status`,
  and `truncated_paths` (or their quiet counts) without ranking subtrees for deletion.
- Do not approve removals, write plans, or call `preview` / `apply`.
- Treat `truncated-not-inventoried` and `walked: false` rollups as coverage gaps, not zero bytes.
- Return a short structured summary: target path, scan mode, rollup table, and any engine errors.
