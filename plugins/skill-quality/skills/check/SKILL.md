---
name: check
description: "Skill-authoring QA for Claude Code skills. Use when: 'check this skill', 'skill quality', 'lint my skill', 'is this SKILL.md valid', 'validate skill frontmatter', 'check skill before publishing', 'validate evals.json', 'shared listing budget', 'is the skill listing overflowing', or before shipping a skill or plugin. Actions: `check [<skill-name>]` runs a twenty-two-check static contract gate (frontmatter, per-skill listing-entry cap, trigger-keyword preservation vs HEAD, line caps, broken internal refs, markdownlint, gotchas surface, evals presence, precompute opportunity, injection shell-declaration, fresh-eyes declaration conformance) and reports PASS/FAIL with warnings; `validate-evals [<skill-name>]` checks a skill's evals/evals.json against the bundled schema; `listing-budget [<root> ...]` reports the SHARED aggregate listing-budget estimate across every listing-eligible skill under the resolved root(s) — advisory only, never blocks. Not for: writing new skills, or running model-graded evals."
argument-hint: "[check|validate-evals|listing-budget] [<skill-name-or-root> ...] — omit the action for check; omit the name/root to run over every skill under the resolved root"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  cheatsheet-stage: review
  cheatsheet-summary: Static QA gate for skill frontmatter, caps, and evals
---

## Purpose

Static, deterministic quality gate for skill authoring. The `check` action runs the bundled
`check-skill.sh` — twenty-two checks with no model invocation, so results are reproducible in CI or a
pre-commit hook. The `validate-evals` action checks a skill's `<skill>/evals/evals.json` against the bundled
JSON schema. The `listing-budget` action runs `check-listing-budget.sh` — a separate, always-advisory
report on the SHARED listing budget every loaded skill draws from together (a different, cross-skill
limit from `check`'s per-skill entry cap). Catches the failure that static analysis catches best: a
rewrite silently dropping a `description` trigger phrase, which degrades auto-invocation.

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

**Gating a marketplace-installed skill.** A `plugin:skill` name (e.g. `source-control:setup`) is
NOT auto-resolved: the checker resolves a bare skill name under one root and deliberately does not
reverse-engineer Claude Code's plugin-cache layout to locate an install. That layout is internal —
only the cache's existence is documented, the `<marketplace>/<plugin>/<version>` nesting is not, and
the version dir changes on every update
([plugins-reference](https://code.claude.com/docs/en/plugins-reference)). To gate an installed skill,
point the root at its installed skills dir explicitly:

```shell
CHECK_SKILL_SKILLS_ROOT=~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/skills \
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-skill.sh" <skill-leaf-name>
```

The cache is a **copy, not a git checkout**, so the git-backed checks (3 trigger-preservation, 8
vendor byte-identity, 9 stale-metadata) no-op against it — a "new skill / skipped" result is
expected there, not a defect. Passing a `plugin:skill` name unresolved prints this exact guidance.

## Arguments

Parse `$ARGUMENTS`:

- **`check <skill-name>`** (default action) — run the static contract gate over one skill.
- **`check`** *(no name)* — run the gate over every skill under the resolved root.
- **`validate-evals <skill-name>`** — validate one skill's `<skill>/evals/evals.json` against the schema.
- **`validate-evals`** *(no name)* — validate every skill's `<skill>/evals/evals.json` that exists.
- **`listing-budget`** *(no root)* — report the shared listing-budget estimate over every
  listing-eligible skill under the resolved root.
- **`listing-budget <root> [<root> ...]`** — pool every listing-eligible skill under each given root
  into ONE shared aggregate (e.g. every plugin's skills dir in a marketplace repo). Every root given
  must exist.

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

## Action: listing-budget

1. Resolve the root(s): explicit `<root> ...` arguments if given; otherwise the same
   skills-root resolution as `check` (above).
2. Run:

   ```shell
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-listing-budget.sh" [<root> ...]
   ```

3. Report the printed aggregate, the budget it was compared against (and whether that budget is the
   documented default, a fixed override, or a reconstructed one — the script labels which), and the
   biggest contributors when it overflows.

This is a **different, cross-skill limit** from `check`'s per-skill entry cap (`description` +
`when_to_use` <= 1536 chars): the shared budget every loaded skill draws from together
(`skillListingBudgetFraction`, default 1% of the model's context window). It is always advisory —
exit 0 regardless of overflow — because the live budget depends on the model's context window and a
consumer's own settings, neither of which this static check can observe. Point `/doctor` at the live
session for the authoritative resolved cost.

**Only listing-eligible skills count.** A skill with `disable-model-invocation: true` has its
description kept out of the model-visible listing entirely, so it spends none of the shared budget
and the report skips it — counting those would overstate the aggregate. A consumer's
`skillOverrides` can free further descriptions by collapsing entries to `"name-only"`, which
repository content cannot reveal, so the reported figure is an upper bound for anyone who sets it.
A missing explicit root and a nonnumeric override are both environment errors (exit 2), never a
silent skip or a coerced-to-zero budget.

## Gotchas

- The script needs a git repository — several checks (trigger-keyword preservation, vendor
  byte-identity, committed-artifact scan) read `git show HEAD:` / `git ls-files`. Outside a repo it
  exits 2 (env error).
- `check-skill.sh` runs `npx markdownlint-cli2` for check 6; when `npx` is absent that check downgrades
  to a WARN rather than failing, so a run on a machine without Node still gates on the other twenty.
- **Check 6 defers to the repo's markdownlint config — run it from inside that repo.** `markdownlint-cli2`
  discovers the nearest `.markdownlint-cli2.jsonc` from its working directory. Run the checker from
  *outside* the target repo (or against a marketplace-installed skill in the plugin cache, which has no
  config) and markdownlint applies its DEFAULTS — so rules a repo deliberately disables (commonly
  `MD013` line-length for injection blocks and tables, `MD041` first-line-heading for a frontmatter/H2
  start, `MD060` table-pipe style) fire as spurious failures on a skill that passes in-repo. This is the
  usual cause of a "shipped marketplace skill fails the marketplace's own gate" report: it is a
  wrong-config artifact, not a real regression. **Injection blocks are not special-cased** — a declared
  `shell:` block with long lines is MD013-subject like any other content; whether it fails is entirely the
  consumer's markdownlint config's call (disable `MD013`, or wrap the lines), never something this gate
  overrides. In this marketplace's own CI the division of labor is explicit: the skill-quality gate skips
  markdownlint (`CHECK_SKILL_SKIP_MARKDOWNLINT=1` in the repo's `check-changed-skills.sh` gate) and the
  hygiene lane lints all repo markdown, SKILL.md included, under the repo config.
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
- `listing-budget` never asserts a resolved live value (context window and `skillListingBudgetFraction`
  are both consumer settings this static check cannot observe) — it reports against a documented,
  overridable default and always exits 0. A clean report is a signal to investigate against `/doctor`
  in a live session, not a guarantee nothing is dropped there. In this marketplace's own repo, each
  plugin owns its own `plugins/<plugin>/skills/` root, so gating the whole marketplace means pooling
  every plugin's root into one call (`check-listing-budget.sh plugins/*/skills`) rather than running it
  once per plugin in isolation — the repo's `check-changed-skills.sh` CI gate does this on every run.
