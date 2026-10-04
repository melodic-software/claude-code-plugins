# E2E run configuration

The consumer config for `/testing:run-e2e`: how a run captures evidence, whether the browser is
visible, who drives the run, and whether it drives an app that is already running. The keys live on
two surfaces:

- `recording` and `browser_mode` stay on `.claude/testing/e2e.md`. That surface's identity is its
  path relative to `.claude/`, `testing/e2e.md`, so its layers are `~/.claude/testing/e2e.md`
  (user-global), `${CLAUDE_PROJECT_DIR}/.claude/testing/e2e.md` (team), and
  `${CLAUDE_PROJECT_DIR}/.claude/testing/e2e.local.md` (local overlay).
- `e2e_driver` and `reuse_running_instance` are top-level keys of the testing plugin's YAML config,
  the file the scan settings share: team `docs/conventions/testing.yaml` (schema
  [`schemas/testing.schema.json`](../../../schemas/testing.schema.json)), user-global
  `~/.claude/testing.yaml`, and local overlay `.claude/testing.local.yaml`; per user, the plugin
  `userConfig` options of the same names. `scripts/resolve-config.sh e2e` resolves them.

This file owns the keys: their meaning, allowed values, defaults, and precedence. How the layers
merge is owned by the layering contract; see the
[config-cascade contract](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/config-cascade/README.md).
The two compose: this doc declares the keys and points there for layer mechanics.

## Keys

| Key | Values | Default | Merge |
|---|---|---|---|
| `recording` | `video` \| `gif` \| `off` | `off` | per-key override |
| `browser_mode` | `headed` \| `headless` | `headless` | per-key override |
| `e2e_driver` | `auto` \| `harness` \| `run` \| `playwright` \| `chrome` | `auto` | per-key override |
| `reuse_running_instance` | `auto` \| `true` \| `false` | `auto` | per-key override |

Both surfaces merge by **per-key override**: a later layer replaces an earlier layer's value key by
key, and a key absent from a later layer keeps the earlier value. The values are closed scalars, so
concatenation would be meaningless. The layering contract requires a surface to declare its merge
form next to its keys; this is that declaration.

### `recording`

Selects whether a run captures a moving record in addition to the mandatory screenshot evidence.

- `off` (default): no recording; the evidence-contract screenshots stay the floor.
- `video`: record via the playwright CLI. Preferred for long or multi-page flows where a screenshot set loses the sequence.
- `gif`: record via `gif_creator`. Preferred for short demos worth showing inline.

A recording always supplements screenshot evidence; it never replaces it.

### `browser_mode`

Selects whether the driven browser is visible.

- `headless` (default): drive without a visible window.
- `headed`: surface the browser window for direct observation.

`run-e2e` resolves the value and passes it through to the executor, which owns the flag that realizes it.

### `e2e_driver`

Selects what drives the flows once the app is up. How `auto` picks, and when a pinned value cannot
serve the target, is the Driver ranking section of [e2e.md](e2e.md).

- `auto` (default): the repository's own harness when a spec or script covers the changed flow;
  otherwise `run` for a CLI, TUI or service and `playwright` for a browser.
- `harness`: the repository's own end-to-end specs or scripts.
- `run`: this skill's own pseudo-terminal and HTTP recipe in [non-ui.md](non-ui.md). It never means
  the bundled `run` skill drives.
- `playwright`: the playwright CLI path, `/playwright:playwright` when the playwright plugin is
  enabled.
- `chrome`: Claude in Chrome, for an attended run only.

### `reuse_running_instance`

Selects what a run does when the app already answers at the URL or port it would use.

- `auto` (default) and `true`: drive the running app. An unattended run labels its evidence
  "instance not started by this run".
- `false`: stop with the gap report naming the collision. Starting a second instance beside the
  running one needs an isolated workspace, which this skill does not provide yet.

## Precedence

Above the file layers, `run-e2e` treats every key as a **default only**: an explicit instruction in
the session prompt always wins. "Run this headed" overrides a `browser_mode: headless` resolved from
any file layer, and "drive it with playwright" overrides `e2e_driver`.

`recording` and `browser_mode`, highest authority first:

1. Explicit session prompt
2. Local overlay (`.claude/testing/e2e.local.md`)
3. Team (`.claude/testing/e2e.md`)
4. User-global (`~/.claude/testing/e2e.md`)
5. Bundled default (`recording: off`, `browser_mode: headless`)

`e2e_driver` and `reuse_running_instance`, highest authority first:

1. Explicit session prompt
2. Local overlay (`.claude/testing.local.yaml`)
3. Team (`docs/conventions/testing.yaml`)
4. User-global (`~/.claude/testing.yaml`)
5. The plugin `userConfig` option of the same name
6. Bundled default (`auto` for both)

The highest layer that sets a key decides it. A value outside the key's list is named with its file
and key, and the key takes its default: a lower layer's value is never used in its place, and the
run never stops on it. An unrendered `${user_config.<key>}` reads as unset.

## Older releases

A testing release older than these two keys does not read `docs/conventions/testing.yaml` at all,
and it refuses an unknown key in the files it does read, which stops its test scan. So the two keys
are never read from the `docs/conventions/testing.md` config block or `.claude/testing.yaml`, the
team files an older teammate's release reads. Set them in `docs/conventions/testing.yaml`; set them
in `~/.claude/testing.yaml` or `.claude/testing.local.yaml` only on a machine that runs this release
or later.
