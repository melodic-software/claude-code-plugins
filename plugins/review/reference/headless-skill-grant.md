# Headless Skill grant for the CI review lanes

Record behind the fail-closed rule in `/review:code-review` and
`/review:security-review`. The lane procedure (stop, do not review the diff
yourself, marker line, exit 3) is this repo's contract. The rows below are the
upstream specifics that contract rests on.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `allowed-tools` grants the listed tools for the invoking turn and does not restrict which other tools are available. The grant clears on the next user message. | [Pre-approve tools for a skill](https://code.claude.com/docs/en/skills#pre-approve-tools-for-a-skill), fetched 2026-09-28 | 2026-09-28 | That section stops saying the field grants without restricting, or stops applying the grant in a `-p` run |
| When the model invokes a skill that declares `allowed-tools` under headless `claude -p`, the Skill tool result is only `Execute skill: <name>` with `is_error` true, the body never loads, and the process can still exit 0. The same skill loads when the prompt is the user-typed slash command, or when the session pre-allows `Skill()`. Removing `allowed-tools` also loads it. Interactive sessions load it. | [anthropics/claude-code#77363](https://github.com/anthropics/claude-code/issues/77363), bcherny comment on 2026-08-17, reproduced on Claude Code 2.1.233. The issue was closed stale on 2026-09-14, not fixed | 2026-09-28 | The issue is reopened with a different tool result, the skills page documents this denial, or a release note changes Skill-tool permission for `allowed-tools` under `-p` |
| These two lanes keep `allowed-tools` and rely on the wrapper pre-allow. ci-workflows `claude-review.yml` at `0d3e6a6` (v0.29.1) appends `--allowedTools "Skill(<plugin-command>)"` after the caller's args. That is the `Skill()` workaround, scoped to the configured command. A result that is still only `Execute skill:` is a failed lane, not a green review | The reusable workflow pin in `.github/workflows/claude-review.yml` and the sibling security caller; the workaround spelling is the same issue comment | 2026-09-28 | The pin drops the `Skill(` grant, or the compose step stops appending it after caller args |

Workarounds that load the body, from that issue comment: `claude --allowedTools "Skill()"` or `claude -p "/<skill> ..."`. The lane prompt is model invocation (`Invoke /review:code-review now`), so it needs the pre-allow. The pre-allow does not excuse a missing body.
