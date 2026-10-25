# bugs: consumer configuration

The single home for the `bugs` plugin's config-key contract. The team layer is
`docs/conventions/bugs.yaml`, validated by [`schemas/bugs.schema.json`](../schemas/bugs.schema.json),
layered per the marketplace's config-cascade convention. It is read by `/bugs:scan` for lane
selection and rotation, plus filing posture, and verified/written by `/bugs:setup`. All layers are
optional: **zero config is a fully working state**, because rotation falls through to the bundled
generic default lanes.

## Layers and resolution order

Three layers, resolved in this order, where a later layer refines an earlier one:

| Order | Layer | Path | Version control |
|---|---|---|---|
| 1 | user-global | `~/.claude/bugs.md` | outside the worktree, so no git verdict applies |
| 2 | team (tracked) | `${CLAUDE_PROJECT_DIR}/docs/conventions/bugs.yaml` for the keys; `${CLAUDE_PROJECT_DIR}/docs/conventions/bugs.md` for prose and `## Gotchas` | must be tracked, the only layer teammates receive |
| 3 | local overlay | `${CLAUDE_PROJECT_DIR}/.claude/bugs.local.md` | must be gitignored, never staged |

**One-release fallback.** The team layer used to be `.claude/bugs.md`. For one release that file
is still read: its YAML block only while `docs/conventions/bugs.yaml` is absent, and its
`## Gotchas` section only while `docs/conventions/bugs.md` is absent. When the new file exists the
old one is ignored for what the new one holds, and a report of the effective config names it as
ignored. `/bugs:setup apply` moves the old file's values into `docs/conventions/bugs.yaml` and
leaves the old file for the operator to delete.

The team files sit in `docs/conventions/` whatever convention home the repository binds; a
repository that binds another home still keeps them there.

Resolution anchors at the repo root, never at the CWD: `${CLAUDE_PROJECT_DIR}` when set, otherwise
`git rev-parse --show-toplevel`. Every layer that exists is read and merged;
reading one layer and stopping is not resolution. A malformed layer degrades soft: surface the error,
name the layer, resolve as if that layer were absent. Unknown keys are inert. Whenever the effective
config is surfaced to a human, report which layer supplied each value. `/bugs:scan` and `/bugs:write`
also concatenate each layer's `## Gotchas` section (see below) via
`scripts/concat-gotchas.sh`, which applies the special-root rule: a root that is home (or an
ancestor of it) or outside a git work tree has no team or overlay layer.

## Merge semantics

Declared here per the cascade convention, beside the keys they govern:

- **`lanes`** entries **concatenate** across layers, in layer order, deduplicated by lane `name`
  (a later layer's entry for an existing name replaces that one entry only). A layer that declares
  `lanes: []`, an explicit empty list rather than an absent key, is an **opt-out** that drops every lane
  inherited from earlier layers and from the bundled defaults; it is reported as an opt-out, not as a
  broken layer. When no layer declares `lanes` at all, the bundled generic default lanes apply.
- **`filing_posture`** is a scalar, resolved **nearest-wins**: the last layer that declares it supplies
  the value; a layer that omits it keeps the earlier value.

Wholesale replacement of an earlier layer is forbidden.

## Key partition: what does *not* belong in this file

`output_dir` stays a native Claude Code `userConfig` option and is **never** duplicated into this
cascade file. The two surfaces answer different questions and have different owners: `output_dir` is
one operator's personal report destination on one machine, set through Claude Code's own plugin
configuration prompt and stored in user settings; `lanes` and `filing_posture` are team policy about
*this repository*, which structurally cannot ride a per-user, per-machine setting. Declaring
`output_dir` here would create two sources of truth for one value with no defined precedence between
them. It is therefore not a recognized key, and a layer that sets it is reported as an inert unknown key.

## File format

The team keys are plain YAML in `docs/conventions/bugs.yaml`, checked against the schema; the
team prose sits beside it in `docs/conventions/bugs.md`. The user-global and local-overlay layers
are Markdown with a fenced YAML block holding the same keys; prose outside the block is the
consumer's own commentary, except a `## Gotchas` section.

```yaml
# docs/conventions/bugs.yaml
lanes:
  - name: entrypoints
    globs:
      - 'src/api/**/*.ts'
      - 'src/cli/**/*.ts'
  - name: billing-core
    globs:
      - 'src/billing/**/*.ts'
filing_posture: manual-only
```

### Consumer `## Gotchas` (cascade tier, #3547)

A `## Gotchas` section in `docs/conventions/bugs.md`, `~/.claude/bugs.md` or
`.claude/bugs.local.md` (outside any YAML fence) is the **local tier** for repo-specific lines the
model should see when `/bugs:scan` or `/bugs:write` loads. Layers concatenate in cascade order after
the bundled gotchas. Each line records a failure the model actually hit in this repository, the
same failure-driven rule the bundled gotchas follow. Generalizable lines belong in the shipped
skill via an issue to this marketplace; see
[`docs/conventions/config-cascade/consumer-gotchas.md`](../../../docs/conventions/config-cascade/consumer-gotchas.md).

## Keys

| Key | Type | Default | Meaning |
|---|---|---|---|
| `lanes` | list of lane entries (sub-keys below) | bundled generic default lanes | The rotation set `/bugs:scan` walks on a bare invocation, in declaration order. Concatenating merge with an empty-list opt-out (above). |
| `filing_posture` | `manual-only` \| `allowed` | `manual-only` | Team policy for the explicit filing argument. `manual-only` means `--track` files nothing and prints why. A standing autonomous lane must not file into this tracker. `allowed` permits `--track` to file. Neither value ever makes a bare invocation file: filing always needs the explicit argument as well. Nearest-wins scalar merge. |

### `lanes[]` sub-keys

| Sub-key | Required | Type | Meaning |
|---|---|---|---|
| `name` | yes | string, kebab-case | The lane's identity: what `--lane <name>` selects, what the cursor records, and what the merge deduplicates on. Must be unique within the resolved set. |
| `globs` | yes | list of glob patterns | The files this lane hunts, relative to the repo root. A lane whose globs match no files is skipped and recorded as skipped, never as exhausted. |

A lane entry missing `name` or `globs` is malformed: report it, name its layer, and resolve as if that
one entry were absent. Do not discard the whole layer.

## Consumer `.gitignore`

One recursive line covers the overlay here and every other cascade surface:

```gitignore
.claude/**/*.local.*
```

`/bugs:setup` recommends this line; no plugin writes the consumer's `.gitignore`.
