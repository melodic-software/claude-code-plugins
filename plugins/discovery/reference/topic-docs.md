# Topic-docs placement — where discovery artifacts land

How `/discovery:explore`, `/discovery:explore-deep`, `/discovery:research`, and
`/discovery:research-deep` resolve where generated documents land in a consuming repo. These skills
read this one document; none bakes its own paths.

Implements the topic-docs convention:
<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/topic-docs/README.md>.
The contract owns every general rule — tiers, schema, resolution order, slug spec, runtime guards,
no-project-root fallback, non-interactive/forked mode, deprecation grace. This document records
only this plugin's deltas.

## What this plugin writes

Discovery writes **memory tier only** — working documents nothing downstream enforces against:

| Artifact | Location |
|---|---|
| `EXPLORE.md` (+ `EXPLORE-<scope>.md` sidecars and overflow) | `<memory_dir>/<slug>/` (default `.work/<slug>/`) — never committed |
| `RESEARCH.md` (+ `RESEARCH-<topic>.md` sidecars and overflow) | `<memory_dir>/<slug>/` — never committed |

Discovery never writes the contract tier; the `contract_tier` setting does not change where its
artifacts land. `/discovery:explore-deep` and a Tier-2 research subagent operate under the
contract's **non-interactive / forked mode** rule.

## Legacy grace — the contract's algorithm, this plugin's parameters

Slice axis: **topic slug**. Legacy root: `.claude/notes/` — or the directory a set `notes_dir`
names (read only the single `pluginConfigs["discovery@melodic-software"].options.notes_dir` key,
never a settings file wholesale). "Set" is the contract's decidable definition, and the on-disk
legacy-content probe runs inside the ladder's legacy rung with the contract's short-circuits.

Guarded migration — run by `/discovery:setup`, one topic slice at a time, on explicit confirmation
only, refusing to overwrite a populated target slice:

```bash
mkdir -p "$MEMORY_DIR"                                        # create the target root
[ -f "$MEMORY_DIR/.gitignore" ] || printf '*\n' > "$MEMORY_DIR/.gitignore"  # self-ignore heal
mv ".claude/notes/$SLUG" "$MEMORY_DIR/$SLUG"                  # legacy memory slices are untracked → mv, not git mv
jq 'del(.pluginConfigs["discovery@melodic-software"].options.notes_dir)' \
  .claude/settings.json > .claude/settings.json.tmp && mv .claude/settings.json.tmp .claude/settings.json
```

The `jq` removal repeats for **every** settings scope that sets the key — migration completes only
when the legacy knob is removed. Confirm: the slice reads back from the new home; no scope still
sets `notes_dir`.
