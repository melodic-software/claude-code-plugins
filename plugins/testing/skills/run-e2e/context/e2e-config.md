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
- `feature_map_dir` is a top-level key of the same YAML config, set only in team
  `docs/conventions/testing.yaml` or the local overlay `.claude/testing.local.yaml`. It is a path
  inside one repository, so the user-global file is not read for it and it has no `userConfig`
  option. `scripts/resolve-config.sh e2e` resolves it with the other two.

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
| `feature_map_dir` | a relative directory path | `.claude/skills/feature-map` | per-key override |

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

Selects what a run does when the app already answers at the URL or port it would use. The answer
also depends on whether origin's default branch declares a Workspace environment entry, which gives
each worktree its own instance through `up` and `info`.

- `true`, and `auto` on an attended run: drive the running app. An unattended run labels its
  evidence "instance not started by this run".
- `auto` on an unattended run: with an entry, start this run's own instance (`up`, then the URL
  `info` reports) and never drive the app that answered; with no entry, drive the running app with
  the label above.
- `false`: with an entry, start this run's own instance the same way, attended or not; with no
  entry, stop with the gap report naming the collision.

The decision table is in SKILL.md's Native step, under Already running.

### `feature_map_dir`

The directory, relative to the repository root, that `/testing:map-features` writes the feature map
to and that a run reads it from. The format is the plugin's `reference/feature-map.md`. The default,
`.claude/skills/feature-map`, makes the map a project skill agents in the repository find without a
pointer.

The map must be its own directory, so these values are refused: an absolute path (`/`, `\`, `~` or
a drive letter first), any value containing `..`, the repository root (`.`), a character outside
`A-Z a-z 0-9 . _ - /`, and any path segment that starts with `run-` (a launch recipe's directory) or
ends in `verify` (a recorded `verify` skill). A refused value is handled like an unknown one: the
warning names the file, the key and the value, that layer is dropped, and with no valid higher
layer the key takes the default.

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

`feature_map_dir`, highest authority first:

1. Explicit session prompt
2. Local overlay (`.claude/testing.local.yaml`)
3. Team (`docs/conventions/testing.yaml`)
4. Bundled default (`.claude/skills/feature-map`)

When a feature map exists, the driver it records sits between the session prompt and every
`e2e_driver` layer: a session instruction wins, then the map's recorded driver for that app, then
the resolved `e2e_driver`. The map keeps the driver it was written with; changing `e2e_driver`
later does not change it, so re-run `/testing:map-features` or edit the map's index.

The highest layer that sets a key decides it. A value outside the key's list is named with its file
and key, and the key takes its default: a lower layer's value is never used in its place, and the
run never stops on it. An unrendered `${user_config.<key>}` reads as unset.

## Older releases

A testing release older than these two keys does not read `docs/conventions/testing.yaml` at all,
and it refuses an unknown key in the files it does read, which stops its test scan. So the two keys
are never read from the `docs/conventions/testing.md` config block or `.claude/testing.yaml`, the
team files an older teammate's release reads. Set them in `docs/conventions/testing.yaml`; set them
in `~/.claude/testing.yaml` or `.claude/testing.local.yaml` only on a machine that runs this release
or later. `feature_map_dir` follows the same rule: a release older than it refuses it as an unknown
key, so set it only once every member runs a release that knows it.
