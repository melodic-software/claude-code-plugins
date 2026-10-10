# Friction classes

The classify agent assigns every event key in `friction.json` one class. `class_hint` is the
script's guess from the event kind alone; the agent reads the evidence session before it agrees.

| Class | Meaning | Typical event keys | Usual cause | Route |
|---|---|---|---|---|
| A | The person wanted to be in the loop, and the agent acted without them | `interrupt`, `correction`, `agent-ask/correction` | An instruction that let the agent decide a design or policy point | An instruction change: `/session-flow:retro codify` |
| B | The work was meant to be autonomous, and the agent stalled, asked, handed the person a step, or stopped | `handoff/*`, `user-command`, a `rule` denial with no prompt host | A gate the lane cannot pass, or agent behavior that treats the person as the message bus | Remove the gate, script the step once, or add a standing instruction to proceed |
| C | The agent asked a question with an obvious recommended answer | `agent-ask/approve`, `approve-reply`, an `AskUserQuestion` answered with its recommended options | Instructions that ask before acting on reversible, authorized work | An instruction to proceed on the recommendation for reversible, authorized work, and to batch the rest |
| D | A tool, permission or classifier block the person had to work around | `denied/*`, `prompt-approved` | A missing allow rule, an ask rule, a command shape that defeats prefix rules, a hook, or a classifier category | `friction.py cause` hint: allowlist (`/fewer-permission-prompts`), classifier entry (`/harness-config:draft-auto-mode-rules`), command shape, hook alternative, or keep |
| E | Anything else: pace, scope drift, no clear close-out | perf signals, `agent-ask/other` | Serial work, deferred scope pulled forward, no stated stop | A process change in the plan |

## Keep or remove

Not every block is friction to remove. Keep a block that protects the person from something they
did not decide: credential exploration, creating unsafe agents, an unreviewed production apply,
self-modification the person has not approved. For those, lower the cost instead: one batched
approval and one reviewed script per change set. Recommend removal only for a block whose every
occurrence the person approved or worked around.

## Event keys

A key is `kind[/cause][/hook][/reason][/reply]`:

- `denied/classifier/<category>`: the auto-mode classifier's bracketed category, or `unexplained`.
- `denied/hook/<plugin or label>/<first line>`: a PreToolUse hook block.
- `denied/rule/<reason type>`: a permission rule denial; with no prompt host it is often an ask rule.
- `denied/user-rejected`: the person declined at a prompt.
- `prompt-approved`: the person approved a permission prompt.
- `agent-ask/<reply>`, `handoff/<reply>`: what the person replied: `approve`, `correction`,
  `rejected` or `other`.
- `user-command`, `correction`, `approve-reply`, `interrupt`.

Every event carries `side` (`main` or `sub`), `agent` (the subagent type), `no_prompt_host` (a
headless session), `shape` and `flags` (for a shell call: `cd-prefix`, `env-prefix`, `compound`,
`redirect`, `heredoc`, `substitution`, `multiline`; for a file: `claude-config`, `outside-cwd`).
