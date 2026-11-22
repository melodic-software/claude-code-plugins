# Replace the official Codex plugin with one external-agents plugin and a skill per CLI

- Status: accepted
- Date: 2026-11-21
- Refs: [#17954](https://github.com/melodic-software/claude-code-plugins/pull/17954) (the plugin and
  the council switch-over), [#17967](https://github.com/melodic-software/claude-code-plugins/pull/17967)
  (the Antigravity skill); owner interview of 2026-11-20 and 2026-11-21 (Q4, Q13, Q14, Q16, Q21,
  Q28); [ADR 0118](0118-ship-the-external-agents-command-in-bin-and-exempt-it-from-the-no-bin-gate.md),
  [ADR 0119](0119-run-every-external-cli-through-one-runner-over-provider-records-with-per-use-sandbox-ceilings.md)

## Context

OpenAI's `codex@openai-codex` plugin ([openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc))
was how sessions and the council review lanes reached Codex. It ships legacy `commands/`, a
proactive forwarding agent and hooks that run in every session. It drives `codex app-server`,
which OpenAI documents as experimental, and its prompting guidance names retired models. Upstream's
last push was 2026-07-08, and it had 546 open issues and pull requests when this was recorded. Council
reached into the plugin's private script by install path. The owner also wants the same pattern for
other vendors' CLIs: Gemini/Antigravity now, then Cursor, and maybe Grok's.

## Decision

1. **Replace, do not wrap.** The marketplace ships its own plugin, `external-agents`, and dotfiles
   turn the official plugin off after it releases. The official plugin is cited as the upstream
   source and none of its text or code is copied.
2. **One plugin, one skill per CLI.** `/external-agents:codex` is the first skill and
   `/external-agents:antigravity` the second. Every skill shares the plugin's runner, job store,
   CLI-facts cache and breaker. Another vendor's CLI is added as a provider record and a skill.
3. **No agent, no hooks, no `commands/`.** Delegation happens only when asked: a skill invocation,
   or a council run that names the member. When the plugin is unused, nothing runs.
4. **The name and boundary is non-Anthropic coding-agent CLIs.** Only official vendor CLIs are in
   scope: no third-party Claude Code plugin and no Claude provider. `multi-agent` stays Claude-only
   and unchanged.
5. **Each skill learns its CLI from the CLI.** Facts come from the CLI's own help, cached per CLI
   version, and each skill cites the vendor's docs index without copying from it.

## Considered options

- **Keep the official plugin and fix around it.** Rejected (Q4): the hooks cost every session,
  the run surface is experimental, and upstream is not taking changes.
- **One plugin per vendor CLI.** Rejected (Q13): each plugin would duplicate the runner, job
  store and breaker, so the copies would drift.
- **A forwarding agent, as upstream ships.** Rejected (Q14): a model hop that adds a turn and makes
  the output shape depend on the model. Skills and the command reach the CLI directly.
- **Session hooks (a stop-time review gate, session transfer).** Rejected (Q16): they run whether
  or not Codex is used, and the owner dropped both features.
- **Drive `codex app-server` or the Codex SDK.** Rejected: OpenAI documents `codex exec` as the
  headless surface and calls the app server experimental
  ([non-interactive mode](https://learn.chatgpt.com/docs/non-interactive-mode.md)).

## Consequences

- Council's Codex member and `/external-agents:codex` move to the new plugin. Council no longer
  looks up another plugin's install path.
- A new CLI costs one provider record, one skill and its tests. Each CLI's permission limits
  differ, and ADR 0119 records them.
- Until dotfiles turn the official plugin off, both plugins are installed. Its hooks keep running
  until then.

## Revisit triggers

- OpenAI resumes maintaining the official plugin and it reaches parity with current Claude Code
  plugin guidance.
- A vendor CLI's headless surface cannot be described by a provider record and needs its own code
  path.
