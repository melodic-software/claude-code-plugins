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

## Core quality

| Row | Tag |
|---|---|
| Description is specific: concrete nouns a user would type, key use case first | judgment |
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
| A gotchas surface exists (`## Gotchas` inline or a gotchas spoke) | mechanical (check 11) |
| `## Next` is present and names the successor in mention-only form | judgment |
| No date-conditional guidance; history lives in CHANGELOG, commit, or ADR; a restated number carries the four-part record | judgment |
| One term per concept throughout | judgment |
| Examples are concrete, not abstract | judgment |
| File references are one level deep | judgment |
| Each spoke pointer says what the file holds and when to read it | judgment |
| Freedom level chosen per section and matched to fragility | judgment |

## Code and scripts

| Row | Tag |
|---|---|
| Scripts solve the problem rather than defer to the model | judgment |
| Error handling in scripts is explicit and prints what it did | judgment |
| Every constant carries its justification | judgment |
| Execute-versus-read intent is stated per script pointer ("Run" or "See") | judgment |
| Script pointers use `${CLAUDE_SKILL_DIR}` or `${CLAUDE_PLUGIN_ROOT}` | judgment |
| Dependencies are listed with their install command and checked before use | judgment |
| MCP tools are named in the harness form (`mcp__<server>__<tool>`) | judgment |
| Validation steps, loop-backs, and a gate exist for critical operations | judgment |
| `scripts/*.test.sh` pass | mechanical (check 7) |
| No committed cache or build artifacts | mechanical (check 13) |
| Injected `!` commands are portable and carry a fallback | mechanical (checks 19 and 20) |

## Testing

| Row | Tag |
|---|---|
| `evals/evals.json` is present | mechanical (check 14) |
| `evals/evals.json` validates against the schema and passes the eval-quality lint | mechanical (`/skill-quality:check validate-evals <skill>`) |
| Three or more eval cases | mechanical (advisory) |
| Where the bundled skill-creator plugin is installed, its eval modes ran the cases with a subagent per case; otherwise the fresh-session loop below stands in | attestation |
| Fresh-session baseline captured with the skill disabled, then enabled | attestation |
| Tested on real tasks, not contrived scenarios | attestation |
| Models exercised: which of `haiku`, `sonnet`, `opus`, `fable` | attestation |
| Team feedback incorporated, where applicable | attestation |

Close with `/skill-quality:check <skill>`: its output answers the mechanical rows, and its WARN
lines are the reviewer's reading list for the rest.
