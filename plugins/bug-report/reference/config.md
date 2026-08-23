# bug-report — consumer configuration

The single home for the `bug-report` plugin's config-key contract. The surface is
`.claude/bug-report.md`, layered per the marketplace's config-cascade convention. It is read by
`/bug-report:scan` — lane selection and rotation, plus filing posture — and verified/written by
`/bug-report:setup`. All layers are optional: **zero config is a fully working state**, because
rotation falls through to the bundled generic default lanes.

## Layers and resolution order

Three layers, resolved in this order — a later layer refines an earlier one:

| Order | Layer | Path | Version control |
|---|---|---|---|
| 1 | user-global | `~/.claude/bug-report.md` | outside the worktree — no git verdict applies |
| 2 | team (tracked) | `${CLAUDE_PROJECT_DIR}/.claude/bug-report.md` | must be tracked — it is the only layer teammates receive |
| 3 | local overlay | `${CLAUDE_PROJECT_DIR}/.claude/bug-report.local.md` | must be gitignored, never staged |

Resolution anchors at the repo root — `${CLAUDE_PROJECT_DIR}` when set, otherwise
`git rev-parse --show-toplevel` — never at the CWD. Every layer that exists is read and merged;
reading one layer and stopping is not resolution. A malformed layer degrades soft: surface the error,
name the layer, resolve as if that layer were absent. Unknown keys are inert. Whenever the effective
config is surfaced to a human, report which layer supplied each value.

## Merge semantics

Declared here per the cascade convention, beside the keys they govern:

- **`lanes`** — entries **concatenate** across layers, in layer order, deduplicated by lane `name`
  (a later layer's entry for an existing name replaces that one entry only). A layer that declares
  `lanes: []` — an explicit empty list, not an absent key — is an **opt-out** that drops every lane
  inherited from earlier layers and from the bundled defaults; it is reported as an opt-out, not as a
  broken layer. When no layer declares `lanes` at all, the bundled generic default lanes apply.
- **`filing_posture`** — a scalar, resolved **nearest-wins**: the last layer that declares it supplies
  the value; a layer that omits it keeps the earlier value.

Wholesale replacement of an earlier layer is forbidden.

## Key partition — what does *not* belong in this file

`output_dir` stays a native Claude Code `userConfig` option and is **never** duplicated into this
cascade file. The two surfaces answer different questions and have different owners: `output_dir` is
one operator's personal report destination on one machine, set through Claude Code's own plugin
configuration prompt and stored in user settings; `lanes` and `filing_posture` are team policy about
*this repository*, which structurally cannot ride a per-user, per-machine setting. Declaring
`output_dir` here would create two sources of truth for one value with no defined precedence between
them — so it is not a recognized key, and a layer that sets it is reported as an inert unknown key.

## File format

Markdown with a fenced YAML block (human-readable, shell-greppable). Prose outside the block is the
consumer's own commentary and is not parsed.

````markdown
# bug-report config

```yaml
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
````

## Keys

| Key | Type | Default | Meaning |
|---|---|---|---|
| `lanes` | list of lane entries (sub-keys below) | bundled generic default lanes | The rotation set `/bug-report:scan` walks on a bare invocation, in declaration order. Concatenating merge with an empty-list opt-out (above). |
| `filing_posture` | `manual-only` \| `allowed` | `manual-only` | Team policy for the explicit filing argument. `manual-only` means `--track` files nothing and prints why — a standing autonomous lane must not file into this tracker. `allowed` permits `--track` to file. Neither value ever makes a bare invocation file: filing always needs the explicit argument as well. Nearest-wins scalar merge. |

### `lanes[]` sub-keys

| Sub-key | Required | Type | Meaning |
|---|---|---|---|
| `name` | yes | string, kebab-case | The lane's identity — what `--lane <name>` selects, what the cursor records, and what the merge deduplicates on. Must be unique within the resolved set. |
| `globs` | yes | list of glob patterns | The files this lane hunts, relative to the repo root. A lane whose globs match no files is skipped and recorded as skipped, never as exhausted. |

A lane entry missing `name` or `globs` is malformed: report it, name its layer, and resolve as if that
one entry were absent — do not discard the whole layer.

## Consumer `.gitignore`

One recursive line covers the overlay here and every other cascade surface:

```gitignore
.claude/**/*.local.*
```

`/bug-report:setup` recommends this line; no plugin writes the consumer's `.gitignore`.
