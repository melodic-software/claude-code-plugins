---
name: check
description: "Skill-authoring QA for Claude Code skills. Use when: 'check this skill', 'skill quality', 'lint my skill', 'is this SKILL.md valid', 'validate skill frontmatter', 'check skill before publishing', 'validate evals.json', or before shipping a skill or plugin. Actions: `check [<skill-name>]` runs a twenty-one-check static contract gate (frontmatter, listing-budget cap, trigger-keyword preservation vs HEAD, line caps, broken internal refs, markdownlint, gotchas surface, evals presence, precompute opportunity, injection shell-declaration, fresh-eyes declaration conformance) and reports PASS/FAIL with warnings; `validate-evals [<skill-name>]` checks a skill's evals/evals.json against the bundled schema. Not for: writing new skills, or running model-graded evals."
argument-hint: "[check|validate-evals] [<skill-name>] — omit the action for check; omit the skill name to run over every skill"
user-invocable: true
disable-model-invocation: false
shell: bash
---

## Purpose

Static, deterministic quality gate for skill authoring. The `check` action runs the bundled
`check-skill.sh` — twenty-one checks with no model invocation, so results are reproducible in CI or a
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
     action-router without evals, orphan spokes, an injection with no `shell:` whose commands
     only *look* portable, an injected command carrying no `|| <fallback>`, and same-context
     judgment language with no fresh-eyes declaration or a stale exemption directive).
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
  to a WARN rather than failing, so a run on a machine without Node still gates on the other twenty.
- Trigger-keyword preservation compares the working tree against `HEAD` by default, so a brand-new skill
  (no committed version) skips check 3 — that is expected, not a silent pass. For a post-commit audit
  (where `HEAD` == the working tree hides an already-committed change), set `CHECK_SKILL_BASE_REF` to a
  ref before the change (e.g. `HEAD^` or a merge-base) and run on a clean tree; it reroutes checks 3/8/9.
- Trigger-drop protection tracks single-quoted `'phrase'` triggers. An unquoted `Use when:` list is not
  tracked by check 3; check 12 warns so those phrases get quoted and covered. A dropped phrase found
  verbatim in a sibling skill's description/when_to_use under the same skills root — where the
  sibling did NOT already carry it at the base ref — is a trigger MOVE: it WARNs instead of failing,
  because the listing still routes the phrase. Phrases absent everywhere, and phrases the sibling
  carried all along (coincidental overlap, not a move), still fail.
- Check 19 (injection shell-declaration) FAILs only when a `!` injection carries *detectable*
  bash-only syntax (`/dev/null`, `command -v`, a pipe into a Unix text tool) AND no `shell:` is
  declared; portable-looking commands downgrade to a WARN, since static analysis cannot prove
  portability. A `shell:` declaration is trusted wholesale — the check does not validate that the
  injected commands actually match the declared shell (so `shell: pwsh` with bash-only commands is
  out of scope). Both checks 19 and 20 scan the injected command text only — a bash-only token in a
  plain `` ```bash `` example or in prose never trips them.
- Check 21 (fresh-eyes declaration conformance) is WARN-only on its judgment-language heuristic;
  only a malformed or reason-less `fresh-eyes-exempt` directive FAILs. Its proximity window is
  per-file, so a declaration living in a referenced spoke file cannot satisfy it — the WARN says
  so; hand-verify before editing. Literal directive examples belong inside code fences (both
  detectors are fence- and inline-span-aware); a bare `<class>` placeholder in prose FAILs as an
  unknown class. Spec: `reference/fresh-eyes-declarations.md`.
- Check 18 (precompute opportunity) is an advisory heuristic, never a FAIL. It cannot tell an
  instruction-to-run shell block from an illustrative example, so a WARN is a candidate to judge, not a
  defect — like a check-5 ref, hand-verify the block before converting it. It reads only fenced shell
  blocks (not prose "run `git status` first") and stays silent whenever the skill already uses any `!`
  injection, so it under-reports by design; a clean run is not proof there is no precompute opportunity.
