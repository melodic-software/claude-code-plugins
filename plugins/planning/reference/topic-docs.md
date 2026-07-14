# Topic-docs resolution — where planning artifacts land

How every planning skill resolves the destination for its per-topic artifacts. All pipeline
skills read this one document; none bakes its own placement rules.

Implements the topic-docs convention:
<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/topic-docs/README.md>.
The contract owns every general rule — tiers, schema, resolution order, slug spec, runtime guards,
no-project-root fallback, non-interactive/forked mode, the contract-slice lifecycle with its
redaction bar, deprecation grace. This document records only this plugin's deltas.

## What this plugin writes, per tier

| Artifact (writer) | Tier | Location (default) |
|---|---|---|
| `PRD.md` (`/planning:prd`) | Contract | `docs/topics/<topic-slug>/`, committed on the task branch |
| `PLAN.md` — Brief (`/planning:interview`), Plan (`/planning:architect`) | Contract | same slice |
| `design/` — ALL design artifacts, including the `design-threads.md` / `design-resolution.md` gate files (`/planning:design`, gated by `/planning:design-handoff`; gate files must travel with the branch) | Contract | `docs/topics/<topic-slug>/design/` |
| `interview-checklist.md`, `architect-checklist.md` | Memory | `.work/<topic-slug>/` — never committed |
| `baselines/` — machine-bound captures from the architect's baseline step | Memory | `.work/<topic-slug>/baselines/` |
| Opt-in `brainstorm.md` (`/planning:brainstorm` — never a default write) | Memory | `.work/<topic-slug>/` |

`contract_tier: local` moves the contract rows into the memory slice with an identical layout —
the contract's solo/offline mode. Roots are configurable via the concern file's `contract_dir` /
`memory_dir` keys.

## Close-out — the vault seam

`/planning:architect` owns describing the contract-slice close-out. Its promotion step resolves
the concern file's `vault_backend`: `docs` (default) → a guarded, history-preserving `git mv`
into `docs/adr/` / `docs/specs/`; any other value → the backend the consuming repo documents,
degrading to `docs` when that backend's tools are absent.

## Legacy grace — the contract's algorithm, this plugin's parameters

Slice axis: **topic slug**. Legacy root: `.claude/notes/` — or the directory a set `notes_dir`
names (read only the single `pluginConfigs["planning@melodic-software"].options.notes_dir` key,
never a settings file wholesale: the local overlay is secret-bearing). "Set" is the contract's
decidable definition, and the on-disk legacy-content probe runs inside the ladder's legacy rung
with the contract's short-circuits.

Guarded migration — run by `/planning:setup`, one topic slice at a time, on explicit confirmation
only, refusing to overwrite a populated target slice:

```bash
LEGACY=.claude/notes  # the resolved legacy root: the notes_dir value when set, else this default
MEM=.work             # the resolved memory_dir; adjust when the concern file overrides it
CONTRACT=docs/topics  # the resolved contract_dir; adjust when the concern file overrides it
                      # (contract_tier: local routes contract kinds to "$MEM/$SLUG" instead — skip the git add)
mkdir -p "$CONTRACT/$SLUG" "$MEM/$SLUG"                       # create both target slices
[ -f "$MEM/.gitignore" ] || printf '*\n' > "$MEM/.gitignore"  # self-ignore heal on the resolved root
# contract kinds → contract slice (legacy content is untracked → mv + git add; git mv when tracked):
for f in PRD.md PLAN.md design; do
  [ -e "$LEGACY/$SLUG/$f" ] && mv "$LEGACY/$SLUG/$f" "$CONTRACT/$SLUG/"
done
git add "$CONTRACT/$SLUG"
mv "$LEGACY/$SLUG"/* "$MEM/$SLUG/" && rmdir "$LEGACY/$SLUG"  # remaining memory kinds (checklists, baselines, scratch)
jq 'del(.pluginConfigs["planning@melodic-software"].options.notes_dir)' \
  .claude/settings.json > .claude/settings.json.tmp && mv .claude/settings.json.tmp .claude/settings.json
```

The `jq` removal repeats for **every** settings scope that sets the key — migration completes only
when the legacy knob is removed. Confirm: the slice reads back from the new homes; no scope still
sets `notes_dir`.
