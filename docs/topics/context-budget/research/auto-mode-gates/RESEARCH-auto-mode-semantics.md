---
topic: auto-mode-gates
section: auto-mode-semantics
abstract: Auto mode is the built-in starting mode on Pro/Max/Team from v2.1.228 (v2.1.233 native Windows); a classifier reviews actions instead of the user, and on entry it drops four named classes of broad allow rule.
claims:
  - claim: "Auto mode replaces the human permission prompt with a second classifier model that reviews actions before they run; it does not merely widen an allowlist."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/permission-modes"
        tier: 1
        pool: "Anthropic — code.claude.com docs"
      - url: "https://code.claude.com/docs/en/permissions"
        tier: 1
        pool: "Anthropic — code.claude.com docs"
      - url: "https://code.claude.com/docs/en/auto-mode-config"
        tier: 1
        pool: "Anthropic — code.claude.com docs"
  - claim: "Auto mode is the built-in starting mode on Pro, Max, and Team plans in a terminal or the VS Code extension, and the built-in auto default requires v2.1.228+ on macOS/Linux/WSL and v2.1.233+ on native Windows."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/permission-modes#which-mode-a-session-starts-in"
        tier: 1
        pool: "Anthropic — code.claude.com docs"
      - url: "https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md"
        tier: 1
        pool: "anthropics/claude-code repository"
  - claim: "On entering auto mode Claude Code drops exactly four classes of broad allow rule — blanket Bash(*)/PowerShell(*), wildcarded interpreters, package-manager run commands, and Agent allow rules — restoring them on leaving; narrow rules carry over."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/permission-modes#how-the-classifier-evaluates-actions"
        tier: 1
        pool: "Anthropic — code.claude.com docs"
      - url: "https://code.claude.com/docs/en/auto-mode-config#route-all-shell-commands-through-the-classifier"
        tier: 1
        pool: "Anthropic — code.claude.com docs"
  - claim: "Only allow rules change on entry to auto mode; deny and ask rules are evaluated before the classifier in every mode."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/permission-modes"
        tier: 1
        pool: "Anthropic — code.claude.com docs"
      - url: "https://code.claude.com/docs/en/auto-mode-config#common-boundaries"
        tier: 1
        pool: "Anthropic — code.claude.com docs"
produced_by: phase-1+2
---

# Auto mode: what it is, when it became default, what it decides

## Q1 — What auto mode is, and whether it is the default

**What it is.** Auto mode substitutes machine review for human review. Per
[permission-modes](https://code.claude.com/docs/en/permission-modes) (fetched 2026-08-17):

> In [auto mode], a second model, the classifier, reviews actions instead of you.

and

> Auto mode lets Claude execute without routine permission prompts. A separate classifier model
> reviews actions before they run, blocking anything that escalates beyond your request, targets
> unrecognized infrastructure, or appears driven by hostile content Claude read. Explicit ask rules
> still force a prompt.

That last sentence is the hinge for the whole brief and is developed in
[`RESEARCH-forcing-a-human-gate.md`](./RESEARCH-forcing-a-human-gate.md).

**Is it the default?** Yes, conditionally — and the condition matters for the skill's threat model.
The same page states: "On Pro, Max, and Team plans, the built-in starting mode is auto mode." The
built-in default is selected by a first-match table:

| How you run Claude Code | Built-in starting mode |
|---|---|
| Any settings file sets `disableAutoMode` to `"disable"` | `default` |
| Feature-flag fetching is off, or first session after install/upgrade | `default` |
| `claude -p` or the Agent SDK | `default` |
| Bedrock, Google Cloud Agent Platform, Microsoft Foundry, Claude Platform on AWS, signed-in apps gateway | `default` |
| **A Pro, Max, or Team plan, in a terminal or the VS Code extension** | **`auto`** |
| An Enterprise plan or a Claude Console API key | `default` |

**Since which version.** The docs are explicit and this supersedes the date-based framing in the
repo's own convention:

> The built-in `auto` default requires Claude Code v2.1.228 or later on macOS, Linux, and WSL, and
> v2.1.233 or later on native Windows. On earlier versions, the built-in default is Manual.

Note the ordering hazard: the starting-mode resolution runs `--permission-mode` flag → `defaultMode`
in a settings file → built-in default. **An `"auto"` value in `.claude/settings.json` or
`.claude/settings.local.json` does not take effect**, and when one is present Claude Code "then uses
the built-in default rather than a `defaultMode` from `~/.claude/settings.json`" — a project file
attempting to self-grant auto mode also suppresses the user's own setting.

## What auto mode auto-approves vs. still prompts for

The decision order is fixed, first match wins
([permission-modes, "How the classifier evaluates actions"](https://code.claude.com/docs/en/permission-modes#how-the-classifier-evaluates-actions),
fetched 2026-08-17):

1. Actions matching allow, ask, or deny rules resolve immediately. **Writes to protected paths route
   to the classifier even when an allow rule matches.** Org-`ask` connector tools and MCP tools
   marked `requiresUserInteraction` prompt directly even when an allow rule matches. **Content-scoped
   ask rules fall back to a permission prompt.**
2. Read-only actions and file edits in your working directory are auto-approved, **except writes to
   protected paths**.
3. Everything else goes to the classifier. Org-`ask` connector tools and `requiresUserInteraction`
   MCP tools skip the classifier and prompt directly, "so an org-required approval is never
   auto-approved" and "a consent step is never auto-approved on the tool author's behalf" (v2.1.199+).
4. If the classifier blocks, Claude receives the reason and tries an alternative.

**Still prompts in auto mode:** explicit ask rules (content-scoped), org-`ask` connector tools,
`requiresUserInteraction` MCP tools, and a PreToolUse hook returning `"ask"` (v2.1.211+). **Falls
back to prompting** after repeated classifier blocks — 3 consecutive or 20 total, thresholds not
configurable.

**Auto-approved without any human:** reads, working-directory file edits outside protected paths,
and anything the classifier approves — which includes a large default allow list (dependency installs
from lockfiles, reading `.env` and sending credentials to their matching API, read-only HTTP, pushing
to any branch of the current repo).

**A caution the operator should carry:** auto mode "also nudges Claude to keep working without
stopping for clarifying questions, though Claude still asks when your prompt or a skill explicitly
relies on it." A skill that depends on Claude *choosing* to ask is working against the mode's own
bias, which is a design argument for a mechanical gate over an instructed one.

## Q3 — The repo's "auto mode drops some rules" claim: the official basis

**The claim is correct and precisely sourced.** The `claude-config:audit-permission-state` skill
(read at `plugins/claude-config/skills/audit-permission-state/SKILL.md`, Tier 0) says auto mode "on
entry **silently drops** broad allow rules" and classifies them as `blanket`,
`interpreter-wildcard`, `package-manager-run`, or `agent`. The official basis is the
"How the classifier evaluates actions" accordion on
[permission-modes](https://code.claude.com/docs/en/permission-modes#how-the-classifier-evaluates-actions)
(fetched 2026-08-17), verbatim:

> On entering auto mode, broad allow rules that grant arbitrary code execution are dropped:
>
> - Blanket `Bash(*)` or `PowerShell(*)`
> - Wildcarded interpreters like `Bash(python*)`
> - Package-manager run commands
> - `Agent` allow rules
>
> Narrow rules like `Bash(npm test)` carry over. Dropped rules are restored when you leave auto mode.

The skill's four-class vocabulary maps one-to-one onto that list. Independently corroborated by
[auto-mode-config](https://code.claude.com/docs/en/auto-mode-config#route-all-shell-commands-through-the-classifier)
(fetched 2026-08-17): "Auto mode suspends only the broad rules that grant arbitrary code execution,
such as `Bash(*)` or wildcarded interpreters", plus `autoMode.classifyAllShell: true`, which
"suspend[s] every Bash and PowerShell allow rule while auto mode is active" (v2.1.193+).

The skill's companion statement — "**Only allow rules change on entry.** Deny and ask are evaluated
before the classifier in every mode, so they are not part of this diff — do not report them as
'surviving'" — is also correct, and is the single most useful sentence in this repo for the skill
being designed. It is corroborated by the decision order above (step 1 precedes the classifier) and
by [auto-mode-config](https://code.claude.com/docs/en/auto-mode-config#common-boundaries): ask rules
are "evaluated before the classifier and always force a permission prompt, even in auto mode".

**One word deserves scrutiny: "silently".** The docs do not say the drop is silent, and this repo's
own `--oracle` path exists because the harness apparently *does* narrate drops in some form. Treat
"silently" as this repo's field observation (Tier 0 from its own tooling) rather than as a
documented property — the load-bearing part, that the drop happens, is fully documented.

## Recency

Latest release confirmed this turn: **2.1.233**
(`https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md`, fetched 2026-08-17).
Neither 2.1.233 nor 2.1.232 changes the classifier decision order, the drop classes, the protected
path list, or hook decision semantics. 2.1.233 contains one auto-mode entry — a Windows fix for auto
mode "repeatedly stopping for manual approval on ordinary `cd <dir> && <command> > file` Bash
commands (a 2.1.232 regression)" — which touches classifier behavior on Windows shell commands only
and does not bear on any claim here. Verdict: **current**.
