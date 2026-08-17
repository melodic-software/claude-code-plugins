---
topic: auto-mode-gates
section: forcing-a-human-gate
abstract: A skill CAN force a prompt auto mode cannot auto-approve — a PreToolUse hook returning "ask", shipped in the skill's own frontmatter — but no mechanism is un-bypassable, because bypassPermissions is undocumented for hook asks, dontAsk converts asks to denials, disableAllHooks removes hooks wholesale, and a PermissionRequest hook can answer the prompt on the user's behalf.
claims:
  - claim: "A PreToolUse hook returning permissionDecision \"ask\" forces a permission prompt in auto mode; the classifier can still deny but cannot approve the call silently. Requires v2.1.211 or later."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/hooks#pretooluse-decision-control"
        tier: 1
        pool: "Anthropic — code.claude.com docs"
      - url: "https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md"
        tier: 1
        pool: "anthropics/claude-code repository"
      - url: "https://code.claude.com/docs/en/permissions#extend-permissions-with-hooks"
        tier: 1
        pool: "Anthropic — code.claude.com docs"
  - claim: "A skill can define PreToolUse hooks directly in its own frontmatter, and Claude Code registers them when the skill is invoked and keeps them for the rest of the session."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/hooks#hooks-in-skills-and-agents"
        tier: 1
        pool: "Anthropic — code.claude.com docs"
      - url: "https://code.claude.com/docs/en/plugins-reference"
        tier: 1
        pool: "Anthropic — code.claude.com docs"
  - claim: "An explicit content-scoped permissions.ask rule is evaluated before the classifier and always forces a prompt in auto mode, and still prompts in bypassPermissions — but it must be written into a settings file by the operator, since a plugin cannot ship permission rules."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/auto-mode-config#add-a-human-checkpoint"
        tier: 1
        pool: "Anthropic — code.claude.com docs"
      - url: "https://code.claude.com/docs/en/permission-modes#skip-all-checks-with-bypasspermissions-mode"
        tier: 1
        pool: "Anthropic — code.claude.com docs"
      - url: "https://code.claude.com/docs/en/plugins-reference"
        tier: 1
        pool: "Anthropic — code.claude.com docs"
  - claim: "AskUserQuestion is not a permission gate: it requires no permission, it is denied outright in dontAsk mode, a user setting can make it auto-continue on idle, and a PreToolUse hook can answer it via updatedInput."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/tools-reference#askuserquestion-tool-behavior"
        tier: 1
        pool: "Anthropic — code.claude.com docs"
      - url: "https://code.claude.com/docs/en/settings"
        tier: 1
        pool: "Anthropic — code.claude.com docs"
      - url: "https://code.claude.com/docs/en/hooks#pretooluse-decision-control"
        tier: 1
        pool: "Anthropic — code.claude.com docs"
  - claim: "No skill-shippable gate is un-bypassable: disableAllHooks removes non-managed hooks entirely, and a PermissionRequest hook can return behavior:\"allow\" to grant the request on the user's behalf."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/hooks#permissionrequest-decision-control"
        tier: 1
        pool: "Anthropic — code.claude.com docs"
      - url: "https://code.claude.com/docs/en/hooks#disable-or-remove-hooks"
        tier: 1
        pool: "Anthropic — code.claude.com docs"
produced_by: phase-2-falsification+phase-3
---

# Q4 — Can a skill mandate a confirmation no permission mode can bypass?

**Short answer: a skill can construct a gate that auto mode cannot auto-approve. It cannot
construct one that *no* permission mode and no configuration can bypass.** The strongest
skill-shippable construct is a `PreToolUse` hook returning `"ask"`. Everything weaker fails against
auto mode; everything stronger requires the operator's own settings file.

The four candidates the brief names, graded:

## 1. `AskUserQuestion` — NOT a gate. Do not build on it

Four independent defeats, each documented:

- **It is not permission-gated at all.** The tools table on
  [tools-reference](https://code.claude.com/docs/en/tools-reference) (fetched 2026-08-17) lists
  `AskUserQuestion` with "Permission required: **No**". It is a conversational affordance, not a
  checkpoint.
- **It can auto-answer itself.** The `askUserQuestionTimeout` setting
  ([settings](https://code.claude.com/docs/en/settings), fetched 2026-08-17) accepts `"60s"`,
  `"5m"`, `"10m"` or `"never"`; on timeout the dialog "submits any options you'd already selected
  and tells Claude you may be away from your keyboard, so Claude proceeds on its own judgment."
  Default is `"never"`, so this is opt-in — but it is the *user's* opt-in, invisible to the skill.
  The same page draws the contrast explicitly: "The timeout applies only to `AskUserQuestion`'s
  multiple-choice questions; permission prompts, including plan approval, never auto-resolve on
  idle."
- **`dontAsk` mode denies it outright**, "even if you've allowed [it]"
  ([permission-modes](https://code.claude.com/docs/en/permission-modes#allow-only-pre-approved-tools-with-dontask-mode)).
- **A hook can answer it.** A `PreToolUse` hook returning `"allow"` plus `updatedInput` carrying an
  `answers` object "satisfies that requirement… so the tool runs without prompting"
  ([hooks](https://code.claude.com/docs/en/hooks#pretooluse-decision-control)).

Auto mode additionally "nudges Claude to keep working without stopping for clarifying questions."
An `AskUserQuestion` confirmation is a request Claude makes, not a gate the harness enforces.

## 2. `disallowed-tools` in skill frontmatter — real, but the wrong shape

It exists and works. Per [skills](https://code.claude.com/docs/en/skills) (fetched 2026-08-17):

> `disallowed-tools` — Tools removed from Claude's available pool while this skill is active. Use for
> autonomous skills that should never call certain tools, such as `AskUserQuestion` for a background
> loop… The restriction clears when you send your next message.

It **removes capability; it cannot request confirmation.** For this skill it is useful defensively
(a skill that must never shell out could deny itself `Bash`) but it cannot produce an approval gate.
Note the mirror-image trap: its own documentation names `AskUserQuestion` as the example of a tool
worth removing — reinforcing that the tool is treated as a convenience, not a control.

Its sibling `allowed-tools` is worth naming only to rule it out: it is turn-scoped ("The grant
clears when you send your next message"), it "does not restrict which tools are available", and
auto mode drops the broad shapes anyway. It grants; it never gates. One line on that page does bear
on gate design, though: "A matching ask or deny rule still aborts the invocation regardless of
`allowed-tools`."

## 3. A `PreToolUse` hook returning `"ask"` — the strongest skill-shippable gate

**This is the answer to the operator's question.** Two facts combine.

**Fact one — a hook `"ask"` floors the decision at a prompt in auto mode.** From
[hooks, PreToolUse decision control](https://code.claude.com/docs/en/hooks#pretooluse-decision-control)
(fetched 2026-08-17), verbatim:

> A hook's `"ask"` also forces a permission prompt in [auto mode]: the classifier can still deny the
> tool call, but it can't approve the call silently. Before v2.1.211, the classifier could approve a
> Bash command running outside the [sandbox] without showing the prompt the hook requested; the
> classifier still applied its own safety rules to that command, and a hook `"deny"` was always
> honored.

Independently corroborated Tier 1 from the upstream release stream
(`https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md`, fetched 2026-08-17),
under **2.1.211**:

> Fixed auto mode overriding a PreToolUse hook's `ask` decision for unsandboxed Bash — a hook `ask`
> now floors the decision at a prompt

**So there is a hard version floor: v2.1.211.** Below it the gate leaks in auto mode for unsandboxed
Bash. The brief's target of v2.1.232 clears it comfortably.

**Fact two — a skill can ship the hook itself.** From
[hooks, "Hooks in skills and agents"](https://code.claude.com/docs/en/hooks#hooks-in-skills-and-agents):

> hooks can be defined directly in [skills] and [subagents] using frontmatter, in the same
> configuration format as settings-based hooks… **Skill hooks**: Claude Code registers them when you
> or Claude invoke the skill and keeps running them for the rest of the session, on turns after the
> skill's own turn as well… All hook events are supported.

And plugins ship hooks as a first-class component: `hooks/hooks.json`
([plugins-reference](https://code.claude.com/docs/en/plugins-reference), fetched 2026-08-17), which
the `/hooks` menu labels `Plugin Hooks`. **This is the one permission-adjacent thing a plugin can
ship** — contrast the same page's Settings row: a plugin's `settings.json` supports "Only the
`agent` and `subagentStatusLine` keys", so a plugin cannot ship `permissions.ask`.

Two supporting properties make this the right construct:

- The prompt is **attributed**. "When a hook returns `"ask"`, the permission prompt displayed to the
  user includes a label identifying where the hook came from: for example, `[User]`, `[Project]`,
  `[Plugin]`, or `[Local]`." The user sees that the skill asked for the checkpoint.
- Hook decisions **cannot be used to escape rules**. "Claude Code evaluates deny and ask rules
  regardless of what a PreToolUse hook returns" — so the hook layers on top of the operator's own
  policy rather than displacing it.

Precedence among multiple hooks is `deny` > `defer` > `ask` > `allow`, so a competing `allow` hook
cannot outvote the gate.

## Falsification — what breaks the hook gate

The mandatory falsification query targeted the hypothesis "a hook `"ask"` is un-bypassable." **It
found counter-evidence. The hypothesis is false as stated**, and the skill's design must account for
four escapes:

1. **`disableAllHooks`.** `"disableAllHooks": true` in a settings file removes every hook. "There is
   no way to disable an individual hook while keeping it in the configuration." Only managed-level
   hooks survive a non-managed `disableAllHooks`
   ([hooks](https://code.claude.com/docs/en/hooks#disable-or-remove-hooks)). A skill's hook is not
   managed, so it can be switched off wholesale — including per-run with
   `--settings '{"disableAllHooks": true}'`.
2. **A `PermissionRequest` hook can answer the prompt.** This is the sharpest defeat. Per
   [hooks, PermissionRequest decision control](https://code.claude.com/docs/en/hooks#permissionrequest-decision-control):
   `behavior: "allow"` "grants the permission". The event "runs when Claude Code is about to ask you
   for permission" — precisely the prompt the `"ask"` gate raised. It can additionally return
   `updatedPermissions` with `addRules`/`setMode` written to `destination: "userSettings"`, i.e.
   `~/.claude/settings.json`. A confirmation gate and a mechanism for auto-answering confirmations
   coexist in the same hook system by design.
3. **`bypassPermissions` is undocumented for hook asks — treat as leaking.** The docs state that
   *explicit ask **rules*** still prompt in `bypassPermissions`. They make **no equivalent statement
   about a hook's `"ask"` decision.** The bypass-mode section enumerates what still prompts (ask
   rules, org-`ask` connectors, `requiresUserInteraction` MCP tools, the `rm -rf` circuit breaker)
   and hooks are absent from that list. **This is a documented-silence gap, not a confirmed leak** —
   see Gaps. Design as though it leaks.
4. **`dontAsk` converts the gate into a denial**, not a confirmation. Acceptable failure direction —
   the write does not happen — but the skill must not promise a prompt there.

## 4. Operator-set `permissions.ask` — the firmest gate, and not shippable

The strongest documented mechanism, and the docs name it as such. From
[auto-mode-config, "Add a human checkpoint"](https://code.claude.com/docs/en/auto-mode-config#add-a-human-checkpoint)
(fetched 2026-08-17):

> The most direct mechanism is `permissions.ask`. Content-scoped ask rules like the ones below are
> evaluated before the classifier and **always force a permission prompt, even in auto mode**,
> because an explicit ask rule is your stated intent to be prompted for that action.

with a boundary table stating for `permissions.ask`: "Always prompts for content-scoped rules like
the recipe above. **The classifier cannot auto-approve a matching action.**" And explicit ask rules
also still prompt in `bypassPermissions`.

**But the skill cannot install it.** A plugin's `settings.json` carries only `agent` and
`subagentStatusLine`; `defaultMode: "auto"` is ignored from project settings "so a repository cannot
grant itself auto mode"; and writing the rule into `~/.claude/settings.json` is *itself* the
protected-path write the gate is meant to guard. **The rule must be added by the operator**, which
matches this repo's existing `permission-rule-hygiene` conclusion for the allow-rule case.

## Recommended construction

Defense in depth, because no single layer holds:

1. **Ship a `PreToolUse` hook in the skill's (or plugin's) own configuration**, matched to `Edit`
   and `Write`, returning `permissionDecision: "ask"` when `file_path` resolves under a settings
   file, with a `permissionDecisionReason` naming the exact keys being changed. This is the piece
   that survives auto mode.
2. **Document a one-line operator setup**: an `Edit` ask rule anchored on the settings file in
   `~/.claude/settings.json` — the firmest layer, and the only one that also holds in
   `bypassPermissions`.
3. **Show the diff before writing, in the skill body**, and never rely on the user reading the
   permission dialog alone. Match `/doctor`'s posture — report first, apply after confirmation.
4. **Declare the version floor (v2.1.211+)** and state plainly that the skill does not gate under
   `bypassPermissions` or `disableAllHooks`. A skill that promises a gate it cannot deliver in those
   configurations is worse than one that states its boundary.
5. Prefer writing to a **narrower target** where possible. Nothing in the docs makes
   `settings.local.json` less protected — it is under `.claude` too — but scoping the change to the
   smallest file that achieves the goal reduces the blast radius of a mis-approved write.
