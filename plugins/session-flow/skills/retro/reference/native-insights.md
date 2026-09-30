# The built-in `/insights` command: verification record

Detail behind the `## Boundary` section in [SKILL.md](../SKILL.md). Each row is a four-part
record: the claim, the basis it rests on, the date it was checked, and the event that makes it
worth checking again.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `insights` is a built-in command described as "Generate a report analyzing your Claude Code sessions", with no argument hint | The `/claude-ops:inventory` extraction of the installed 2.1.284 binary (`builtin_commands.insights`) | 2026-09-29 | A release renames or removes `insights`, or changes its description |
| It is user-invocable and not model-invocable (model invocation disabled), and it is not gated behind a setting | Same extraction: `user_invocable: true`, `model_invocable: false`, `disable_model_invocation: true`, `gated: false` | 2026-09-29 | A release changes its invocability or adds a gate |
| It generates an HTML report on recent sessions on this machine (projects, how you use Claude Code, where things go wrong, features to try) and is not available in cloud sessions | The `/insights` row on <https://code.claude.com/docs/en/commands> | 2026-09-29 | The commands page row changes or disappears |
| It includes an auto mode recommendation estimating how many permission prompts auto mode could have handled | Claude Code changelog, 2.1.281 | 2026-09-29 | A release note changes what the report covers |

## Why the verdict is complementary

`/insights` is cross-session usage analytics: a report over many sessions, with no scoring
dimensions and no path into the repo's rules or memory. This skill scores one session or handoff
chain against fixed quality dimensions, checks feedback-memory regressions, and codifies learnings
behind approval. `trends` mode is the nearest overlap, and it still reads this plugin's own score
history rather than usage telemetry, so the skill offers `/insights` beside it rather than
replacing either.
