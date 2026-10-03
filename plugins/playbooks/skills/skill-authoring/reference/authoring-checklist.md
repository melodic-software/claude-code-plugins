# Pre-share checklist

Locally-owned Melodic Software guidance (not part of the upstream playbook). Run it once per skill
before publication, after the eval loop in [`authoring-guidance.md`](authoring-guidance.md) has
converged. Each row carries a tag:

- **mechanical (check N)**: `skill-quality:check` decides it; N is the check number in that
  skill's contract, and its FAIL or WARN line is the row's answer.
- **mechanical (advisory)**: a count or script settles it, but no check gates on it.
- **judgment**: a reviewer decides it by reading; no script can.
- **attestation**: the author states it was done; nothing verifies it.

The checker covers the first group. The rest belongs to the reviewer, and a gate that claims to
have checked a judgment row is misreporting.

## Frontmatter and body

| Row | Tag |
|---|---|
| Description names the concrete nouns a user would type, key use case first | judgment |
| Description says what the skill does and when to use it, with "Use when" phrasing in single quotes | mechanical (check 12) |
| Description prose carries no first or second person; quoted trigger phrases may | judgment |
| `description` alone is at most 1,024 codepoints | mechanical (check 2b) |
| `description` plus `when_to_use` is at most 1,536 characters | mechanical (check 2) |
| SKILL.md is under 500 lines, whole file | mechanical (check 4) |
| SKILL.md is at or under 200 lines; detail lives in spokes | mechanical (check 10) |
| Every backtick-cited or linked skill-internal path resolves | mechanical (check 5) |
| Every skill-internal path in SKILL.md and in every spoke uses forward slashes | mechanical (check 5) |
| Every `reference/`, `references/`, `context/` directory is referenced from the hub | mechanical (check 15) |
| A reference file over 300 lines opens with a `## Contents` block | mechanical (check 26) |
| `disable-model-invocation` is written explicitly | mechanical (check 24) |
| `context: fork` only when the invocation-context rubric says it pays; anti-candidate classes stay inline | judgment |
| A forked skill writes `background: false` unless a skill-specific confirmation chooses async | judgment |
| A gotchas surface exists (`## Gotchas` inline or a gotchas spoke) | mechanical (check 11) |
| `## Next` is present and names the successor in mention-only form | judgment |
| Arguments follow the skill argument shape: one action first, earned `--flag` modifiers, at most one subject last, `argument-hint` in the same order ([`authoring-guidance.md`](authoring-guidance.md#argument-surface)) | judgment |
| No date-conditional guidance; history lives in CHANGELOG, commit, or ADR, apart from a names-only "Old patterns" table ([`authoring-guidance.md`](authoring-guidance.md#time-sensitive-content)); no upstream text is restated, and a volatile specific the body depends on is our decision plus a pointer to the exact section, an as-of date, and a recheck trigger | judgment |
| Every item of the upstream checklist (Pointer below) that this file does not sharpen holds | judgment |
| Each spoke pointer says what the file holds and when to read it | judgment |
| Freedom level chosen per section and matched to fragility | judgment |

## Scripts

| Row | Tag |
|---|---|
| Script output names what the script did, including on failure | judgment |
| Execute-versus-read intent is stated per script pointer ("Run" or "See") | judgment |
| Script pointers use `${CLAUDE_SKILL_DIR}` or `${CLAUDE_PLUGIN_ROOT}` | judgment |
| Each dependency's install command sits beside it, and the script checks for it before use | judgment |
| MCP tools are named in the harness form (`mcp__<server>__<tool>`) | judgment |
| Validation steps, loop-backs, and a gate exist for critical operations | judgment |
| `scripts/*.test.sh` pass | mechanical (check 7) |
| No committed cache or build artifacts | mechanical (check 13) |
| Injected `!` commands are portable and carry a fallback | mechanical (checks 19 and 20) |

## Evals and testing

| Row | Tag |
|---|---|
| `evals/evals.json` is present | mechanical (check 14) |
| `evals/evals.json` validates against the schema and passes the eval-quality lint | mechanical (`/skill-quality:check validate-evals <skill>`) |
| Eval-case count meets the upstream checklist's floor (Pointer below) | mechanical (advisory) |
| Where the bundled skill-creator plugin is installed, its eval modes ran the cases with a subagent per case; otherwise the fresh-session loop below stands in | attestation |
| Fresh-session baseline captured with the skill disabled, then enabled | attestation |
| Models exercised: which of `haiku`, `sonnet`, `opus`, `fable` | attestation |

Close with `/skill-quality:check <skill>`: its output answers the mechanical rows, and its WARN
lines are the reviewer's reading list for the rest.

- **Pointer**: [Checklist for effective Skills](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#checklist-for-effective-skills)
- **As of**: 2026-10-01
- **Recheck trigger**: that section adds, drops or renames an item.
