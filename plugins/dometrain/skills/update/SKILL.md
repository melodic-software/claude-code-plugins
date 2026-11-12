---
description: "Maintainer-facing drift check and baseline refresh for the grounding skill's vendored upstream content. Actions: --check (default, read-only drift report) and --apply (refresh the vendored baseline, working-tree checkout only). Use when: 'check dometrain drift', 'has the dometrain-grounding skill changed upstream', before a version bump, or at a scheduled recheck."
argument-hint: "[--check|--apply]"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Drift check between this plugin's vendored `dometrain-grounding` baseline (`vendor/SKILL.md`) and
Dometrain's current upstream skill content (`github.com/Dometrain/mcp`,
`skills/dometrain-grounding/SKILL.md`). There is one upstream dependency and no CLI to upgrade,
only vendored prose to diff.

This skill runs only when a person types `/dometrain:update`, so its frontmatter sets
`disable-model-invocation` (what the flag does:
<https://code.claude.com/docs/en/skills#control-who-invokes-a-skill>).

## Invocation

| Invocation | Action |
|---|---|
| `/dometrain:update` (or `--check`) | Default. Read-only drift report. Modifies no files. |
| `/dometrain:update --apply` | Overwrite `vendor/SKILL.md` with current upstream and stamp `synced:` in `grounding/SKILL.md`. Working-tree checkout only. |

## `--check` (default, report-only)

Run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/update/scripts/update.sh" --check
```

The script:

1. Fetches Dometrain's current `skills/dometrain-grounding/SKILL.md` from `raw.githubusercontent.com`.
2. Diffs it against `vendor/SKILL.md` (stripping the vendored file's own attribution comment
   first, since upstream never carries it).
3. Reports "No drift detected" or shows the diff for manual review.

Writes nothing.

## `--apply` (maintainer, working-tree checkout only)

1. Confirm this plugin is loaded from a **working-tree checkout** (a clone of the marketplace
   repository, or a directory loaded via `--plugin-dir`), never the installed plugin cache: the
   script writes next to itself. If you cannot verify that, stop and say so.
2. Run the script with `--apply` from that checkout:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/update/scripts/update.sh" --apply
   ```

3. Remind the maintainer of the follow-up steps in [context/update.md](context/update.md): re-add
   the attribution comment, port what is worth keeping into `grounding/SKILL.md` by hand, and add
   the release record.

`--apply` refreshes the baseline only. It never rewrites the body of `grounding/SKILL.md`.

## Output

Report the script's exit code (0 no drift or `--apply` completed, 1 drift, 2 unverifiable) and its
stdout verbatim (or a short summary if long): drift present or absent, and when present, point to
`context/update.md` for the next step.

## Spoke paths

The `context/` files write this skill's directory as `<skill-dir>`, which is `${CLAUDE_SKILL_DIR}`.
Put that path in place of the placeholder before running a command. Those files arrive through the
Read tool as plain bytes, so a `${…}` token in them would reach the Bash tool unsubstituted, and the
Bash tool's environment has no `CLAUDE_SKILL_DIR` to expand it from. Basis: the plugins reference,
<https://code.claude.com/docs/en/plugins/manifest-reference#where-each-variable-resolves>.

## Boundaries

- Never model-invocable. This skill exists so a maintainer can check drift explicitly, not so
  the model can decide on its own that a check is warranted.
- Runs `--apply` only when the invocation names `--apply`, and only from a working-tree checkout.
  A request to "update the copy" without `--apply` gets the `--check` report and a pointer to
  `--apply`.
- Never edits the body of `grounding/SKILL.md`. Integration is a human decision, documented in
  `context/update.md`.
