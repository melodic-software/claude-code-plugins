# The native `security-review` command: verification record

Detail behind the `## Boundary` section in [SKILL.md](../SKILL.md). Each row is a four-part
record: the claim, the basis it rests on, the date it was checked, and the event that makes it
worth checking again.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| The commands table lists `/security-review [low\|medium\|high\|xhigh\|max] [--fix] [pr#\|branch\|path]` as a Skill: "Review the current diff, or a PR number, branch, or path you pass, for security vulnerabilities. Pass `--fix` to apply findings" | <https://code.claude.com/docs/en/commands>, the row and its Type label | 2026-09-11 | The row changes its label, flags, or targets |
| The installed binary still registers it as plugin-backed, not as a bundled skill: `pluginName:"security-review", pluginCommand:"security-review"`, description "Complete a security review of the pending changes on the current branch", and the prompt refuses to run outside a git repository | String search of the installed 2.1.263 binary | 2026-09-11 | An extraction reports the name under bundled skills, or the docs page the row links (`/docs/en/security-review`, which returned 404 on 2026-09-11) resolves and states the class |
| `--fix` applies findings to the working tree; the bare command reports | The commands row | 2026-09-11 | The flag changes |
| It is the single-pass, on-demand layer of a stack: the security guidance plugin reviews code as Claude writes it; the Claude Security plugin runs a multi-agent deep scan with reviewed patches; Code Review reviews pull requests on Team and Enterprise plans; the managed Claude Security product monitors repositories on Enterprise | The "How the plugin fits with other security tools" table on <https://code.claude.com/docs/en/claude-security> | 2026-09-11 | The table adds, removes, or re-tiers a layer |
| It is unusable in CI because it diffs against `origin/HEAD`, which the Actions checkout does not create | The body's opening paragraph carries that record with its own basis and recheck trigger; not repeated here | 2026-09-06 | See the body |

The docs label and the binary disagree on the command's class. The registry row keeps
`plugin-backed-builtin`, the class the binary reports, and this record carries the docs label
beside it; the disagreement itself is the recheck event the row names, half fired.

## Why the verdict is complementary

This skill is the security logic the `claude-security-review` reusable workflow runs in CI, with
the wrapper owning posting and this skill owning what to hunt for. The native command is a local
single pass a developer runs on a branch before pushing, and it cannot run under the Actions
checkout at all. Neither wraps the other. The Claude Security plugin and the managed products are
further surfaces this lane does not wrap either: a request for a deep scan or repository
monitoring routes to them, not here.

## Presence

The native command is gated by its backing plugin's availability, `skillOverrides`, the host
surface, and the environment. Nothing in this lane depends on it: the CI wrapper never invokes it.

## Extraction record

The registry row's observation is a 2026-08-23 extraction of the 2.1.232 binary, whose
`plugin_backed` map reports `{"security-review": "security-review"}` with the name in neither the
built-in commands nor the bundled skills. This record re-verifies the plugin-backed registration
on the installed 2.1.263 binary by string search and reads the two pages named above, all on
2026-09-11.
