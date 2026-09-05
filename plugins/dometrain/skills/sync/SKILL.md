---
description: "Maintainer-only drift check for the grounding skill's vendored upstream content. Never model-invocable — only a human explicitly running /dometrain:sync. Use when: 'check dometrain sync drift', 'has the dometrain-grounding skill changed upstream', before a version bump, or at a scheduled fleet-conformance recheck."
argument-hint: "check"
user-invocable: true
disable-model-invocation: true
shell: bash
---

## Purpose

Report-only drift check between this plugin's vendored `dometrain-grounding` baseline
(`vendor/SKILL.md`) and Dometrain's current upstream skill content
(`github.com/Dometrain/mcp`, `skills/dometrain-grounding/SKILL.md`). There is one upstream
dependency and no CLI to upgrade, only vendored prose to diff.

**Consumer vs maintainer role split:** this skill is `disable-model-invocation: true`, so it is
reachable only by a human's explicit `/dometrain:sync` invocation, never by the model on its own
initiative. `check` (the only action) is report-only. The `--refresh-baseline` flag is not
skill-exposed; `context/update.md` documents it for a maintainer to type as a raw bash command in a
working clone.

## `check` (report-only, the only action)

Run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/sync/scripts/update.sh"
```

The script:

1. Fetches Dometrain's current `skills/dometrain-grounding/SKILL.md` from `raw.githubusercontent.com`.
2. Diffs it against `vendor/SKILL.md` (stripping the vendored file's own attribution comment
   first, since upstream never carries it).
3. Reports "No drift detected" or shows the diff for manual review.

Never writes to `vendor/SKILL.md` or `grounding/SKILL.md`. Direct the user to
[context/update.md](context/update.md) for the maintainer-only integration protocol.

## Output

Report the script's exit code and its stdout verbatim (or a short summary if long): drift
present or absent, and when present, point to `context/update.md` for the next step.

## Boundaries

- Never model-invocable. This skill exists so a maintainer can check drift explicitly, not so
  the model can decide on its own that a check is warranted.
- Never runs `--refresh-baseline`. That overwrites the vendor snapshot and is restricted to a
  maintainer typing the raw command directly in a working clone.
- Never edits `grounding/SKILL.md`. Integration is a human decision, documented in
  `context/update.md`.
