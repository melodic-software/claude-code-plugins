---
topic: auto-mode-gates
section: settings-mutation-safety
abstract: The bundled /doctor is the documented model — it reports findings first and applies fixes only after confirmation — while /config writes directly with no confirmation; and ~/.claude/settings.json is treated differently from project writes by two independent mechanisms plus an explicit self-escalation warning.
claims:
  - claim: "The bundled /doctor skill mutates configuration only after explicit user confirmation — it reports findings first and proposes fixes it applies only after you confirm."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/commands"
        tier: 1
        pool: "Anthropic — code.claude.com docs"
      - url: "https://code.claude.com/docs/en/debug-your-config"
        tier: 1
        pool: "Anthropic — code.claude.com docs"
  - claim: "/config key=value writes a setting directly without opening the interface and without a documented confirmation step, including in non-interactive -p mode and from the mobile app."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/commands"
        tier: 1
        pool: "Anthropic — code.claude.com docs"
      - url: "https://code.claude.com/docs/en/settings"
        tier: 1
        pool: "Anthropic — code.claude.com docs"
  - claim: "Writes to ~/.claude/settings.json are treated differently from project writes by two independent mechanisms: protected-path status, and being outside the working directory that scopes edit auto-approval."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/permission-modes#protected-paths"
        tier: 1
        pool: "Anthropic — code.claude.com docs"
      - url: "https://code.claude.com/docs/en/permissions#working-directories"
        tier: 1
        pool: "Anthropic — code.claude.com docs"
  - claim: "Claude Code's own docs name writing ~/.claude/settings.json as a self-escalation vector, in the sandbox filesystem-isolation warning."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/sandboxing"
        tier: 1
        pool: "Anthropic — code.claude.com docs"
      - url: "https://code.claude.com/docs/en/permission-modes#eliminate-prompts-with-auto-mode"
        tier: 1
        pool: "Anthropic — code.claude.com docs"
produced_by: phase-2+phase-3
---

# Q5 — Official guidance on tools/skills that modify the user's own settings.json

There is **no single normative "skills that edit settings must confirm" page.** That is a reported
absence with its enumeration: checked and not carrying such a rule —
[security](https://code.claude.com/docs/en/security),
[security-guidance](https://code.claude.com/docs/en/security-guidance),
[skills](https://code.claude.com/docs/en/skills),
[settings](https://code.claude.com/docs/en/settings),
[plugins-reference](https://code.claude.com/docs/en/plugins-reference) (all fetched 2026-08-17).
Left unchecked: the Agent SDK permission/hook pages, and the two maintainer long-form writeups that
were unreachable (see Gaps).

What exists instead is **mechanism plus one strong worked example**, which together are the
guidance.

## `/doctor` — the documented model, and it confirms

`/doctor` is a **bundled Skill** that changes configuration, which makes it the closest official
analogue to what the operator is building. Two doc pages state its posture independently.

[commands](https://code.claude.com/docs/en/commands) (fetched 2026-08-17):

> **[Skill].** Run a setup checkup that diagnoses issues and can fix them… Also offers to make
> [auto mode] your default and to [pre-approve] frequently denied read-only commands. **Reports
> findings first and asks for confirmation before changing anything.**

[debug-your-config](https://code.claude.com/docs/en/debug-your-config) (fetched 2026-08-17):

> It reports what it finds… **then proposes fixes it applies only after you confirm.**

Note what `/doctor` actually proposes: making auto mode your default, and adding permission
pre-approvals. Anthropic's own settings-mutating skill changes the same class of setting the
operator's skill will, and it gates on confirmation. **Report-then-confirm is the documented house
style, and it is carried by the skill body, not by the permission system.**

Also note `claude doctor` from the terminal "prints read-only installation diagnostics without
starting a session" — a read-only entry point is offered alongside the mutating one. This repo's own
`audit-permission-state` skill takes the same shape ("Report-only — never writes any settings
file"), which is good precedent to follow: **split the reporting skill from the mutating skill.**

## `/config` — the counter-example, and it does not confirm

From [commands](https://code.claude.com/docs/en/commands):

> From v2.1.181, pass one or more `key=value` pairs to **set a setting directly without opening the
> interface**, for example `/config thinking=false`… The `key=value` form also works in
> non-interactive mode (`-p`) and from the Claude mobile app via Remote Control.

No confirmation is documented for that form. The distinction is coherent: `/config` is a *user-typed
imperative* (the human already decided), whereas `/doctor` is *Claude proposing changes* (the human
has not). **The operator's skill is in the `/doctor` category, not the `/config` category** — it
offers to disable connectors, plugins, and bundled skills, i.e. Claude proposes and the human
ratifies. It should confirm.

## Q6 — Are `~/.claude/settings.json` writes treated differently from project writes?

**Yes, by two independent mechanisms, plus an explicit warning.** These are separate and it is worth
keeping them separate, because they fail differently.

**Mechanism 1 — protected-path status.** `.claude` is on the protected-directory list
([permission-modes](https://code.claude.com/docs/en/permission-modes#protected-paths), fetched
2026-08-17), with `.claude/worktrees` the only carve-out. This applies to a project `.claude/` too,
so it is **not** what distinguishes home from project. `.mcp.json` and `.claude.json` are separately
listed as protected files. The stated rationale names Claude's own configuration explicitly: "This
prevents accidental corruption of repository state **and Claude's own configuration**."

**Mechanism 2 — working-directory scope. This is the actual home-vs-project difference.** Every
edit auto-approval in the system is scoped to the working directory or `additionalDirectories`
([permissions](https://code.claude.com/docs/en/permissions#working-directories)). A project's
`.claude/settings.json` is inside the working directory; `~/.claude/settings.json` normally is not.
So the home file is out of scope for auto mode's step-2 auto-approval and for `acceptEdits` on two
grounds rather than one.

A third, narrower asymmetry sits in rule *authoring* rather than enforcement: a `/path` pattern
anchors to its settings source, so `Edit(/settings.json)` written in `~/.claude/settings.json`
resolves to `~/.claude/settings.json`, whereas the same rule in project settings resolves to
`<project root>/settings.json`. An operator-facing ask rule should use a `~/` or `//` anchor to
avoid this.

**The explicit warning.** [sandboxing](https://code.claude.com/docs/en/sandboxing) (fetched
2026-08-17) names this exact file as an escalation vector:

> With filesystem isolation off and commands auto-allowed, a sandboxed command can write files that
> later commands run or read, such as shell startup files, executables on `$PATH`, or
> `~/.claude/settings.json`, and use them to widen its own access on the next run.

Auto mode's own default block list carries the same theme: writes to `~/.claude/projects/`
transcripts are blocked outright as "session state that Claude Code writes, not a working file"
(v2.1.205+), and driving Claude Code's own tmux pane is blocked because the classifier "treats
[it] as Claude changing its own permissions or oversight" (v2.1.198+).

**The implication for this skill is uncomfortable and should be stated in its docs.** A skill that
disables connectors, plugins, and bundled skills by editing `~/.claude/settings.json` is performing
a configuration change of the class the classifier is trained to view as oversight-reducing. Two
consequences: (a) the classifier may well **deny** it in auto mode, so the skill must handle denial
as an ordinary outcome and not a bug — this is why `permission-rule-hygiene`'s "never document a
prompt the operator will wait for" caution applies; and (b) precisely because the change reduces the
user's own safety surface, a confirmation is warranted on the merits, independent of what any
permission mode enforces.

## Bearing on the skill's specific mutations

Disabling **plugins** has a documented non-settings path worth preferring: per
[security-guidance](https://code.claude.com/docs/en/security-guidance), disabling a plugin from
`/plugin` "writes an override to your `.claude/settings.local.json` rather than editing the
checked-in file", and the dialog separately offers removal for everyone. Where a built-in UI already
performs the mutation with its own confirmation, routing the user there beats writing the file — and
is a legitimate design option for at least part of the skill's scope.
