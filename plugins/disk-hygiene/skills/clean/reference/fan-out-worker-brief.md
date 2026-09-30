# Fan-out worker brief (paste into spawn prompts)

Evidence-only subtree worker for `/disk-hygiene:clean` home or large-target audits. The parent
owns classification, the single report, approvals, preview, and execution. You return scan
evidence only.

## Parent: fill the placeholders before spawning

A worker cannot expand `${...}` tokens (the guard rejects shell expansion), so every value it needs
must be a literal in its spawn prompt. Before spawning, replace `<hook-python>` and `<data-root>`
with the literal values from the guard-values note (the probe in `SKILL.md` only when the note is absent). Fill
`<engine>` with `${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/` plus the engine filename, `<run-dir>`
with the run directory you chose, and, when it applies, `<project-dir>` with `${CLAUDE_PROJECT_DIR}`,
each as a literal absolute path.

## Bash contract (instructions to you; the belt may not enforce them in a subagent)

The session's skill-frontmatter belt is not reliably active inside a subagent, so nothing here is
enforced for you by that belt. The plugin-level engine gate still checks any call that names the
engine. Follow the contract yourself.

Make every engine call a **single** invocation of the engine with no shell chaining, redirection,
or extra commands in the same tool call. Required flags on every scan:

- `--data-root "<data-root>"` (the plugin data directory the engine gate authorizes)
- `--output "<run-dir>/snapshot.json"` under `<data-root>/runs/…`, never inside the target

`--project-dir` is optional: pass it (as a literal absolute path filled by the parent) only when the
session's project has standing policy that should apply to the target, and omit it otherwise, for
example in a home-directory session; the engine then skips the project policy layer.

Use the hook Python launcher the parent filled in for `<hook-python>`, not a bare `python3` on PATH.

Do not run `apply`, `preview`, `handoff-verify`, `handoff-apply`, `catalog`, `rm`, `del`, moves, or any
command that mutates the target. Do not wrap the engine in compound shells (`;`, `&&`, `|`).

## Scan invocation templates

**Exact subtree sizing (no per-entry inventory, no entry cap):**

```text
"<hook-python>" "<engine>" scan \
  --target "<subtree-path>" --output "<run-dir>/sizes.json" \
  --data-root "<data-root>" [--project-dir "<project-dir>"] \
  --sizes-only
```

Read `inventory_mode: sizes-only` and `rollup_precision` on stdout. `partial` means a subtree was
cut or failed to scan. `children_rollup` rows with `walked: true` are exact totals, not depth-cut
floors.

**Bounded inventory (hints + handoff paths):**

```text
"<hook-python>" "<engine>" scan \
  --target "<subtree-path>" --output "<run-dir>/snapshot.json" \
  --data-root "<data-root>" [--project-dir "<project-dir>"] \
  [--max-depth <N>] [--confirmed-large-scan]
```

Depth-cut rollups carry `walked: false` and `unwalked_reasons`; do not treat them as exact sizes.

**Home fan-out after depth-1 (selected top-level children only):**

```text
"<hook-python>" "<engine>" scan \
  --target "<home-path>" --output "<run-dir>/snapshot.json" \
  --data-root "<data-root>" [--project-dir "<project-dir>"] \
  --root-children --root-child "<ChildName>" [--root-child "<Other>"]...
```

## Evidence-only rules

- Report only what the snapshot JSON and stdout payload state; quote `children_rollup`, `status`,
  and `truncated_paths` (or their quiet counts) without ranking subtrees for deletion.
- Do not approve removals, write plans, or call `preview` / `apply`.
- Treat `truncated-not-inventoried` and `walked: false` rollups as coverage gaps, not zero bytes.
- Return a short structured summary: target path, scan mode, rollup table, and any engine errors.
