---
topic: auto-mode-gates
section: permission-mode-inventory
abstract: Six modes, resolved against the three action classes the brief names — and the decisive structural fact is that ~/.claude/settings.json is BOTH a protected path and outside the working directory, so it is never covered by the working-directory edit auto-approval in any mode.
claims:
  - claim: "`.claude` is a protected directory, so any write under `~/.claude` or a project `.claude/` — settings.json included — is a protected-path write in every mode."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/permission-modes#protected-paths"
        tier: 1
        pool: "Anthropic — code.claude.com docs"
      - url: "https://code.claude.com/docs/en/permissions"
        tier: 1
        pool: "Anthropic — code.claude.com docs"
  - claim: "Protected-path writes resolve per mode as: default/acceptEdits prompt, plan prompts, auto routes to the classifier, dontAsk denies, bypassPermissions allows."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/permission-modes#protected-paths"
        tier: 1
        pool: "Anthropic — code.claude.com docs"
      - url: "https://code.claude.com/docs/en/permissions#permission-modes"
        tier: 1
        pool: "Anthropic — code.claude.com docs"
  - claim: "permissions.allow rules in settings files do not pre-approve protected-path writes, because the safety check runs before allow rules are evaluated."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/permission-modes#protected-paths"
        tier: 1
        pool: "Anthropic — code.claude.com docs"
      - url: "https://code.claude.com/docs/en/permission-modes#how-the-classifier-evaluates-actions"
        tier: 1
        pool: "Anthropic — code.claude.com docs"
  - claim: "acceptEdits auto-approval applies only to paths inside the working directory or additionalDirectories, so it never reaches ~/.claude on its own."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/permission-modes#auto-approve-file-edits-with-acceptedits-mode"
        tier: 1
        pool: "Anthropic — code.claude.com docs"
      - url: "https://code.claude.com/docs/en/permissions#working-directories"
        tier: 1
        pool: "Anthropic — code.claude.com docs"
produced_by: phase-1+2
---

# Q2 — Full permission-mode inventory against the three action classes

All rows sourced from [permission-modes](https://code.claude.com/docs/en/permission-modes) and
[permissions](https://code.claude.com/docs/en/permissions), both fetched 2026-08-17.

## The structural fact that governs the whole table

`~/.claude/settings.json` sits at the intersection of **two independent restrictions**, and
conflating them is the easiest way to design the wrong gate:

1. **It is a protected path.** `.claude` is on the protected-directory list (the only carve-out is
   `.claude/worktrees`). Protected-path writes are "never auto-approved except in
   `bypassPermissions` mode and in planning sessions with bypass permissions available."
2. **It is outside the working directory.** Every "file edits are auto-approved" clause in the docs
   is scoped to the working directory or `additionalDirectories`. `~/.claude` is neither unless the
   operator deliberately added it.

Either one alone keeps a `~/.claude/settings.json` write off the auto-approval fast path. Together
they mean the *only* modes where such a write executes with no review of any kind are
`bypassPermissions` and a planning session with bypass available.

## The inventory

| Mode | (a) Write/Edit inside the project | (b) Write/Edit under `~/.claude` | (c) Bash commands |
|---|---|---|---|
| `default` (Manual) | Prompts | **Prompts** (protected path) | Prompts, except the built-in read-only command set |
| `plan` | Blocked — Claude may not edit source; edits stay blocked until you approve the plan (except where bypass is available) | **Prompts.** With bypass available: allowed. With auto mode available during planning: routed to the classifier | Read-only exploration; with auto mode available and `useAutoModeDuringPlan` on (default), the classifier reviews commands instead of prompting. Otherwise commands outside the read-only set prompt |
| `acceptEdits` | Auto-approved, **working directory / `additionalDirectories` only** | **Prompts** — protected path, and out of scope besides | Auto-approves only `mkdir`, `touch`, `rm`, `rmdir`, `mv`, `cp`, `sed` (plus safe env prefixes and `timeout`/`nice`/`nohup` wrappers) on in-scope paths. All other Bash prompts |
| `auto` | Auto-approved (decision-order step 2), except protected paths | **Routed to the classifier.** Not prompted, not rule-approved — the classifier may approve or deny with no human involved | Goes to the classifier (step 3), unless a narrow allow rule matches. Broad allow rules are dropped on entry; `autoMode.classifyAllShell` suspends the narrow ones too |
| `dontAsk` | Allowed only if an allow rule matches; anything that would prompt is **auto-denied** | **Denied** | Only `permissions.allow` matches, the built-in read-only set, and PreToolUse-hook-approved calls run. Explicit ask rules are **denied rather than prompted**; `AskUserQuestion` is denied even if allowed |
| `bypassPermissions` | Executes immediately | **Allowed** — writes to protected paths execute | Executes immediately. Exceptions that still prompt: explicit ask rules, org-`ask` connector tools, `requiresUserInteraction` MCP tools, and the `rm -rf /` / `rm -rf ~` circuit breaker (including inside command/process substitution) |

## Three details worth carrying into the design

**`permissions.allow` cannot pre-approve a protected-path write.** Verbatim:

> `permissions.allow` rules in settings files do not pre-approve protected-path writes. The safety
> check runs before Claude Code evaluates allow rules from settings, so an entry such as
> `Edit(.claude/**)` in `~/.claude/settings.json` or `.claude/settings.json` does not change the
> per-mode outcome in the table above.

**But a prompt, once answered, can widen the whole session.** In modes that prompt:

> the prompt for a `.claude/` write offers **Yes, and allow Claude to edit its own settings for this
> session**, which approves later `.claude/` writes in that session without prompting again.

For a skill that intends one reviewed change, this is a real hazard: a user who reflexively picks
that option converts a single approval into a session-wide grant over their own configuration. The
skill should make its *one* write, and should not be structured so the user is nudged toward the
session-wide option.

**Rules that hold in every mode, `bypassPermissions` included** — the short list the whole gate
question reduces to:

> - deny rules and explicit ask rules, which apply to every tool but can't block `EndConversation`
>   while any other tool remains
> - the org `ask` setting on connector tools
> - the `requiresUserInteraction` marker

Note the asymmetry that breaks the "every mode" reading: **`dontAsk` denies rather than prompts.**
An ask rule in `dontAsk` mode does not produce a human gate; it produces a refusal. That is arguably
the correct outcome for this skill (no silent write), but it is not a confirmation.

## Precedence, stated once

Rules evaluate **deny → ask → allow**, first match wins, and "rule specificity doesn't change the
order" ([permissions](https://code.claude.com/docs/en/permissions#manage-permissions), fetched
2026-08-17). A matching ask rule therefore prompts even when a more specific allow rule also matches.
A bare tool name in `deny` removes the tool from Claude's context entirely; a scoped rule like
`Bash(rm *)` leaves the tool present and blocks matching calls.
