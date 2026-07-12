---
name: skill-quality
description: "Skill-authoring QA for Claude Code skills. Use when: 'check this skill', 'skill quality', 'lint my skill', 'is this SKILL.md valid', 'validate skill frontmatter', 'check skill before publishing', 'validate evals.json', or before shipping a skill or plugin. Actions: `check [<skill-name>]` runs a seventeen-check static contract gate (frontmatter, listing-budget cap, trigger-keyword preservation vs HEAD, line caps, broken internal refs, markdownlint, gotchas surface, evals presence) and reports PASS/FAIL with warnings; `validate-evals [<skill-name>]` checks a skill's evals/evals.json against the bundled schema. Not for: writing new skills, or running model-graded evals."
argument-hint: "[check|validate-evals] [<skill-name>] — omit the action for check; omit the skill name to run over every skill"
user-invocable: true
disable-model-invocation: false
---

## Purpose

Static, deterministic quality gate for skill authoring. The `check` action runs the bundled
`check-skill.sh` — seventeen checks with no model invocation, so results are reproducible in CI or a
pre-commit hook. The `validate-evals` action checks a skill's `<skill>/evals/evals.json` against the bundled
JSON schema. Catches the failure that static analysis catches best: a rewrite silently dropping a
`description` trigger phrase, which degrades auto-invocation.

## Skills-directory resolution

The checker never assumes a repo layout (convention-resolution ladder). It resolves the skills root in
this order — first hit wins:

1. `${user_config.skills_root}` — set it when your skills live outside `.claude/skills` (run
   `/skill-quality:setup` to configure).
2. `${CLAUDE_PROJECT_DIR}/.claude/skills` — the conventional default.

The skill passes the resolved root to the script via the `CHECK_SKILL_SKILLS_ROOT` environment
variable. When `skills_root` is configured, export it before invoking the script:

```shell
CHECK_SKILL_SKILLS_ROOT="${user_config.skills_root}" \
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-skill.sh" <skill-name>
```

When it is unset, invoke the script plain — it falls back to `${CLAUDE_PROJECT_DIR}/.claude/skills`.

## Arguments

Parse `$ARGUMENTS`:

- **`check <skill-name>`** (default action) — run the static contract gate over one skill.
- **`check`** *(no name)* — run the gate over every skill under the resolved root.
- **`validate-evals <skill-name>`** — validate one skill's `<skill>/evals/evals.json` against the schema.
- **`validate-evals`** *(no name)* — validate every skill's `<skill>/evals/evals.json` that exists.

## Action: check

1. Resolve the skills root (above). If the directory does not exist, report it and offer
   `/skill-quality:setup`.
2. For a named skill, run:

   ```shell
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-skill.sh" <skill-name>
   ```

   For no name, enumerate each immediate subdirectory of the skills root that contains a `SKILL.md`
   and run the script once per skill, collecting results.
3. Report per skill:
   - **PASS / FAIL** from the script's exit code (0 = pass, 1 = one or more `FAIL:` lines).
   - The `FAIL:` lines verbatim (each is an actionable defect).
   - `WARN:` lines grouped after failures (advisory — soft line target, missing gotchas surface,
     action-router without evals, orphan spokes).
4. For a multi-skill run, end with a one-line rollup: `N passed, M failed`.

The `FAIL:` messages are self-describing. Do not re-derive their meaning; surface them and, when the
user asks, fix the cited skill. A broken-internal-ref FAIL points at a `SKILL.md:<line>` — hand-verify
that line before editing, since it may be an illustrative example path rather than a real broken ref.

## Action: validate-evals

1. Locate `<skills-root>/<skill-name>/evals/evals.json`. If absent, report that the skill ships no
   evals (not a failure — evals are warranted, not mandatory).
2. Read the bundled schema at
   [`${CLAUDE_PLUGIN_ROOT}/reference/evals.schema.json`](../../reference/evals.schema.json) and the
   skill's `evals.json`.
3. If a JSON-schema validator is available (`check-jsonschema`, `ajv`, or `python -m jsonschema`),
   run it and report conformance. Otherwise validate structurally against the schema: `skill_name`
   and a non-empty `evals` array are required; each case requires `id` and `prompt`; a rich-form case
   may add `name` (kebab-case), `expected_output`, `files`, and one of `assertions` / `expectations`.
4. Report each violation with its JSON path, or confirm the file conforms.

## Gotchas

- The script needs a git repository — several checks (trigger-keyword preservation, vendor
  byte-identity, committed-artifact scan) read `git show HEAD:` / `git ls-files`. Outside a repo it
  exits 2 (env error).
- `check-skill.sh` runs `npx markdownlint-cli2` for check 6; when `npx` is absent that check downgrades
  to a WARN rather than failing, so a run on a machine without Node still gates on the other sixteen.
- Trigger-keyword preservation compares against `HEAD`, so a brand-new skill (no committed version)
  skips check 3 — that is expected, not a silent pass.
