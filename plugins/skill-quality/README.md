# skill-quality

A Claude Code plugin for **skill-authoring QA**: it runs a static, deterministic contract gate over a
skill directory and validates a skill's `evals.json` against a bundled schema. No model invocation in
the gate — the same seventeen checks run identically in a session, a pre-commit hook, or CI.

The one failure static analysis catches best is a rewrite silently dropping a `description` trigger
phrase, which quietly degrades a skill's auto-invocation. Check 3 compares the trigger phrases against
`HEAD` and fails on a regression.

| Skill | What it does |
|---|---|
| `/skill-quality:check` | Runs the contract gate (`check`) or schema-validates evals (`validate-evals`), for one skill or every skill. |
| `/skill-quality:setup` | `check` (default) resolves and verifies the skills directory; `apply` routes a non-default `skills_root` change through Claude Code. |

## Checks

`check` runs `check-skill.sh` — seventeen checks, reported as `FAIL:` (blocking) or `WARN:` (advisory):

- Frontmatter parses; `name` + `description` present.
- `description` + `when_to_use` within the 1536-char listing budget (overflow truncates the listing).
- Trigger-keyword preservation vs `HEAD` (skipped for a new, uncommitted skill).
- `SKILL.md` under 500 lines (hard) / 200 lines (soft, advisory).
- Backtick- and link-cited skill-internal supporting files resolve.
- `markdownlint-cli2` clean (advisory-skips when `npx` is absent).
- `scripts/*.test.sh` pass where present.
- Vendored `vendor/` byte-identical vs `HEAD`; stale-tracking metadata keys preserved; sync age.
- Gotchas surface present; `description` carries `Use when` phrasing; no committed cache artifacts;
  action-router skills ship `evals/evals.json`; companion spoke dirs are referenced.

```shell
/skill-quality:check my-skill          # gate one skill
/skill-quality:check                   # gate every skill under the resolved root
/skill-quality:check validate-evals my-skill # schema-check evals.json
```

## Skills directory — never baked in

The checker resolves the skills root through the convention-resolution ladder, first hit wins:

1. `${user_config.skills_root}` — set only when your skills live outside `.claude/skills`.
2. `${CLAUDE_PROJECT_DIR}/.claude/skills` — the conventional default.

`CHECK_SKILL_SKILLS_ROOT` is honored as a one-run environment override the checker reads directly;
the setup skill neither writes nor persists it. When your skills live at the default location, no
configuration is needed:

```shell
/skill-quality:setup         # check (default): resolve + verify the skills directory (re-runnable)
/skill-quality:setup apply   # route a non-default skills_root change through Claude Code
```

## Evals schema

`validate-evals` checks a skill's `evals/evals.json` against the bundled
`reference/evals.schema.json`. The schema accepts both the minimal form (`id` + `prompt` per case) and
the rich form (adding `name`, `expected_output`, `files`, and one of `assertions` / `expectations`).
Evals are warranted, not mandatory — a skill shipping none is not a failure.

## Requirements

- A git repository — several checks read `git show HEAD:` / `git ls-files`; outside a repo the script
  exits 2.
- `npx` (Node) is optional; without it the markdownlint check downgrades to a warning and the other
  sixteen still gate.
