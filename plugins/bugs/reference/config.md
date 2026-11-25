# bugs: consumer configuration

The single home for the `bugs` plugin's config-key contract. The team layer is
`docs/conventions/bugs.yaml`, validated by [`schemas/bugs.schema.json`](../schemas/bugs.schema.json),
layered per the marketplace's config-cascade convention. It is read by `/bugs:scan` for focus area
selection and rotation, and verified/written by `/bugs:setup`. Filing posture is a work-items key
([Filing posture](#filing-posture)). All layers are
optional: **zero config is a fully working state**, because rotation falls through to the bundled
generic default focus areas.

## Layers and resolution order

Three layers, resolved in this order, where a later layer refines an earlier one:

| Order | Layer | Path | Version control |
|---|---|---|---|
| 1 | `userConfig` | the file the `gotchas_file` option names (its `## Gotchas` only) | outside the worktree, so no git verdict applies |
| 2 | team (tracked) | `${CLAUDE_PROJECT_DIR}/docs/conventions/bugs.yaml` for the keys; `${CLAUDE_PROJECT_DIR}/docs/conventions/bugs.md` for prose and `## Gotchas` | must be tracked, the only layer teammates receive |
| 3 | personal override | `${CLAUDE_PROJECT_DIR}/docs/conventions/bugs.local.md` | must be gitignored, never staged |

### Old paths (dual-read window)

Two old files are still read while they exist:

- `~/.claude/bugs.md`: its `## Gotchas` while the `gotchas_file` file is absent, since that file
  supplies only gotchas; its `areas` and `filing_posture` until it is deleted, since no new
  per-user layer holds them.
- `${CLAUDE_PROJECT_DIR}/.claude/bugs.local.md`, retirement record `bugs-r001`
  ([`retirements.yaml`](../retirements.yaml)): the whole file while `docs/conventions/bugs.local.md`
  is absent.

Every run of `concat-gotchas.sh` prints one `Warning:` line per old file it finds, naming it, the new
location, and `/bugs:setup apply`, which moves it. When both files of a layer exist, the new one wins
and the warning names both. Removing the old-path read is a later change, made once no old file is
reported.

`/bugs:setup apply` moves each old file's settings by what each one is:

| What the old file holds | New home |
|---|---|
| `## Gotchas` in `~/.claude/bugs.md` (prose the model reads in every repository) | a Markdown file of the user's own outside `~/.claude`, named by the `gotchas_file` option |
| `areas` in `~/.claude/bugs.md` (globs about one repository) | the personal override `docs/conventions/bugs.local.md` of the repository it was meant for, or the team file |
| `filing_posture` in either old file | `docs/conventions/work-items.yaml` ([Filing posture](#filing-posture)) |
| anything in `.claude/bugs.local.md` | `docs/conventions/bugs.local.md`, as it is |

The team files sit in `docs/conventions/` whatever convention home the repository binds; a
repository that binds another home still keeps them there.

Resolution anchors at the repo root, never at the CWD: `${CLAUDE_PROJECT_DIR}` when set, otherwise
`git rev-parse --show-toplevel`. Every layer that exists is read and merged;
reading one layer and stopping is not resolution. A malformed layer degrades soft: surface the error,
name the layer, resolve as if that layer were absent. Unknown keys are inert. Whenever the effective
config is surfaced to a human, report which layer supplied each value. `/bugs:scan` and `/bugs:write`
also concatenate each layer's `## Gotchas` section (see below) via
`scripts/concat-gotchas.sh`, which applies the special-root rule: a root that is home (or an
ancestor of it) or outside a git work tree has no team layer or personal override.

## Merge semantics

Declared here per the cascade convention, beside the keys they govern:

- **`areas`** entries **concatenate** across layers, in layer order, deduplicated by focus area `name`
  (a later layer's entry for an existing name replaces that one entry only). A layer that declares
  `areas: []`, an explicit empty list rather than an absent key, is an **opt-out** that drops every focus area
  inherited from earlier layers and from the bundled defaults; it is reported as an opt-out, not as a
  broken layer. When no layer declares `areas` at all, the bundled generic default focus areas apply.
- **`filing_posture`** (deprecated here, see [Filing posture](#filing-posture)) is a scalar, resolved
  **nearest-wins**: the last layer that declares it supplies the value; a layer that omits it keeps
  the earlier value.

Wholesale replacement of an earlier layer is forbidden.

## Key partition: what does *not* belong in this file

`output_dir` stays a native Claude Code `userConfig` option and is **never** duplicated into this
cascade file. The two surfaces answer different questions and have different owners: `output_dir` is
one operator's personal report destination on one machine, set through Claude Code's own plugin
configuration prompt and stored in user settings; `areas` is team policy about
*this repository*, which structurally cannot ride a per-user, per-machine setting. Declaring
`output_dir` here would create two sources of truth for one value with no defined precedence between
them. It is therefore not a recognized key, and a layer that sets it is reported as an inert unknown key.

## File format

The team keys are plain YAML in `docs/conventions/bugs.yaml`, checked against the schema; the
team prose sits beside it in `docs/conventions/bugs.md`. The personal override is Markdown with a
fenced YAML block holding the same keys; prose outside the block is the consumer's own commentary,
except a `## Gotchas` section. The `gotchas_file` file supplies only its `## Gotchas` section.

```yaml
# docs/conventions/bugs.yaml
areas:
  - name: entrypoints
    globs:
      - 'src/api/**/*.ts'
      - 'src/cli/**/*.ts'
  - name: billing-core
    globs:
      - 'src/billing/**/*.ts'
```

### Consumer `## Gotchas` (cascade scope)

A `## Gotchas` section in the `gotchas_file` file, `docs/conventions/bugs.md` or
`docs/conventions/bugs.local.md` (outside any YAML fence) is the **local scope** for repo-specific lines the
model should see when `/bugs:scan` or `/bugs:write` loads. Layers concatenate in cascade order after
the bundled gotchas. Each line records a failure the model actually hit in this repository, the
same failure-driven rule the bundled gotchas follow. Generalizable lines belong in the shipped
skill via an issue to this marketplace; see
[`docs/contracts/config-cascade/consumer-gotchas.md`](../../../docs/contracts/config-cascade/consumer-gotchas.md).

## Filing posture

`filing_posture` is team policy for the explicit filing argument, and it lives in the work-items
plugin's team file, `docs/conventions/work-items.yaml` (schema
`plugins/work-items/schemas/work-items.schema.json`). `manual-only`, the default, means `--track`
files nothing and prints why; a standing autonomous lane must not file into this tracker.
`allowed` permits `--track` to file. Neither value ever makes a bare invocation file: filing always
needs the explicit argument as well. Resolve it highest first:

1. `filing_posture` in `docs/conventions/work-items.yaml`: layer `work-items`.
2. For one release, a `filing_posture` in this plugin's layers above (nearest-wins): layer
   `bugs (deprecated)`, and print "filing_posture read from <file>, which is deprecated; move it
   to docs/conventions/work-items.yaml".
3. The default, `manual-only`: layer `default`.

A value other than `manual-only` or `allowed` is named (file, key, value) and that layer is
skipped.

## Keys

| Key | Type | Default | Meaning |
|---|---|---|---|
| `areas` | list of focus area entries (sub-keys below) | bundled generic default focus areas | The rotation set `/bugs:scan` walks on a bare invocation, in declaration order. Concatenating merge with an empty-list opt-out (above). |
| `filing_posture` | `manual-only` \| `allowed` | none | Deprecated: read only as the fallback in [Filing posture](#filing-posture), for one release. Nearest-wins scalar merge. |
| `verification`, `verification_skills.<skill>` | `off` \| `light` \| `standard` \| `strict` | `light` | How much independent checking `/bugs:scan` runs: `light` and `off` skip the Step 4 gate and report candidates as `unverified`. Read from `docs/conventions/bugs.yaml` on the default branch only, through `lib/read-verification.sh`; no other layer sets it, and a skill entry beats the plugin value ([verification level](../../../docs/contracts/verification-level/README.md)). |

### `areas[]` sub-keys

| Sub-key | Required | Type | Meaning |
|---|---|---|---|
| `name` | yes | string, kebab-case | The focus area's identity: what `--area <name>` selects, what the cursor records, and what the merge deduplicates on. Must be unique within the resolved set. |
| `globs` | yes | list of glob patterns | The files this focus area hunts, relative to the repo root. A focus area whose globs match no files is skipped and recorded as skipped, never as exhausted. |

A focus area entry missing `name` or `globs` is malformed: report it, name its layer, and resolve as if that
one entry were absent. Do not discard the whole layer.

## Consumer `.gitignore`

This recursive line ignores the personal override, `docs/conventions/bugs.local.md`; see
[config locations](config-locations.md). Keep any `.claude/**/*.local.*` line until the old
`.claude/bugs.local.md` is moved.

```gitignore
docs/conventions/**/*.local.*
```

`/bugs:setup` recommends this line; no plugin writes the consumer's `.gitignore`.
