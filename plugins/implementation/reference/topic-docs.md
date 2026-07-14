# Topic-docs placement — where this plugin's artifacts land

How `/implementation:implement`, `/implementation:implement-dispatch`, `/implementation:verify-changes`,
and `/implementation:verify-improvement` resolve where generated documents land in a consuming repo.
These skills read this one document; none bakes its own paths.

Implements the topic-docs convention:
<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/topic-docs/README.md>.
The contract owns every general rule — tiers, schema, resolution order, slug spec, runtime guards,
no-project-root fallback, non-interactive/forked mode, the prune-with-pointer lifecycle with its
redaction bar, deprecation grace. This document records only this plugin's deltas.

## What this plugin writes, per tier

| Artifact | Tier | Location (default) |
|---|---|---|
| `PLAN.md` Plan section + progress marks (phase tags, step boxes) | Contract | `docs/topics/<slug>/PLAN.md`, committed on the task branch |
| `DEVIATIONS.md` (autonomous-run deviation log, reviewed at PR time) | Contract | pinned beside `PLAN.md` in the topic's contract slice |
| Verification manifest (distilled, `verified_at_sha`-keyed; meets the contract's redaction bar) | Contract | `docs/topics/<slug>/verification/` |
| Baselines (machine-bound measurements) | Memory | `.work/<slug>/baselines/` — never committed |
| Raw verification captures | Memory | `.work/<slug>/scratch/` |
| Status summary | Memory | `.work/<slug>/` |
| Timestamped handoff notes | Memory | `.work/handoffs/` — `/session-flow:handoff` owns that surface; the fallback note (plugin absent) lands in the same home |

`contract_tier: local` moves the contract rows into the memory slice with an identical layout —
the contract's solo/offline mode. Roots are configurable via the concern file's `contract_dir` /
`memory_dir` keys.

**Phase-commit rule:** each implementation phase's plan updates ride the same commit as that
phase's source changes — one commit, one story; memory-tier files never enter the commit.

## Legacy grace — the contract's algorithm, this plugin's parameters

Slice axis: **topic slug**. Legacy root: `.claude/notes/` — or the directory a set `notes_dir`
names (read only the single `pluginConfigs["implementation@melodic-software"].options.notes_dir`
key, never a settings file wholesale). "Set" is the contract's decidable definition, and the
on-disk legacy-content probe runs inside the ladder's legacy rung with the contract's
short-circuits.

Guarded migration — the deprecation notice presents this command; run one topic slice at a time,
on explicit confirmation only, refusing to overwrite a populated target slice:

```bash
MEM=.work  # the resolved memory_dir; adjust when the concern file overrides it
mkdir -p "docs/topics/$SLUG" "$MEM/$SLUG"                     # create both target slices (use the configured roots)
[ -f "$MEM/.gitignore" ] || printf '*\n' > "$MEM/.gitignore"  # self-ignore heal on the resolved root
# contract kinds → contract slice (legacy content is untracked → mv + git add; git mv when tracked):
for f in PLAN.md DEVIATIONS.md verification; do
  [ -e ".claude/notes/$SLUG/$f" ] && mv ".claude/notes/$SLUG/$f" "docs/topics/$SLUG/"
done
git add "docs/topics/$SLUG"
mv ".claude/notes/$SLUG"/* "$MEM/$SLUG/" && rmdir ".claude/notes/$SLUG"  # remaining memory kinds (baselines, scratch, status)
jq 'del(.pluginConfigs["implementation@melodic-software"].options.notes_dir)' \
  .claude/settings.json > .claude/settings.json.tmp && mv .claude/settings.json.tmp .claude/settings.json
```

The `jq` removal repeats for **every** settings scope that sets the key — migration completes only
when the legacy knob is removed. Confirm: the slice reads back from the new homes; no scope still
sets `notes_dir`.
