---
name: audit-permission-grants
description: "Audit Claude Code permission GRANTS for portability and auto-mode durability — scans skill/command/agent frontmatter allowed-tools and settings.json/settings.local.json permissions.allow for interpreter-wildcard rules dropped in auto mode, hardcoded machine/user paths, and inert plugin self-grants. Use when: 'check permission rules', 'why was my allowed-tools grant ignored', 'audit allow rules', 'is this permission portable', after authoring a code-execution grant, or when a guarded helper is denied despite an allow rule. Report-only."
argument-hint: "[scope] — scope: frontmatter|settings|plugins|all (default: all)"
user-invocable: true
disable-model-invocation: false
metadata:
  cheatsheet-stage: anytime
  cheatsheet-summary: Audit permission grants for portability and auto-mode durability
---

## Purpose

Audit whether a repo's permission **grants** actually take effect. Answers a question the sibling
`audit` skill does not: "Are our allow-rules and `allowed-tools` grants portable across
machines and durable when the session enters auto mode — and is the operative rule in a place that can
work?"

The principle, the three anti-patterns, and the correct pattern (with official-doc citations) live in
the marketplace's **permission-rule-hygiene** convention, published at
<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/permission-rule-hygiene/README.md>.
The mechanical check definitions (P1/P2/P3, severities, detector invocation) are in
[reference/criteria.md](reference/criteria.md), which carries every recommendation this skill needs at
run time — the convention is the doctrine's owner, not a runtime dependency.

## Scope boundary (route out)

This skill owns grant portability + auto-mode durability + who adds the operative rule. It does **not**
own config-file correctness — baseline deny/ask presence, deprecated `:*` syntax, overly broad
patterns, or live plugin drift belong to the sibling `audit` skill. When a request is about
those, route it there rather than answering here. The `audit` skill in the `claude-memory` plugin
owns the instruction layer (CLAUDE.md / rules / auto-memory).

## Arguments

Parse `$ARGUMENTS` for an optional scope filter:

- `frontmatter` — skill/command/agent `allowed-tools` only
- `settings` — `.claude/settings.json` + `.claude/settings.local.json` `permissions.allow` only
- `plugins` — plugin `settings.json` self-grant (P3) only
- `all` — everything (default)

This skill is report-only. There is no `--fix`: the correct P3 remediation is inherently
operator-manual (the bare-name rule must land in user-global `~/.claude/settings.json`, which a skill
or plugin cannot write), and P1/P2 rewrites are judgment calls the operator confirms.

## Phase 1: Detect

Run the deterministic spine:

```shell
bash "${CLAUDE_PLUGIN_ROOT}/skills/audit-permission-grants/scripts/permission-rule-check.sh"
```

It scans frontmatter `allowed-tools` and settings `permissions.allow` across the consuming repo and
prints one finding per fragile grant (`<severity> [<check>] <source>: <detail>`). `--count` prints the
count. It requires `jq`; a missing `jq` exits 2 (report the environment gap rather than a clean bill).
`settings.local.json` is parsed for its `permissions.allow` array only — never echoed wholesale.

If a scope filter was given, run the full detector and present only the matching checks (P1/P2 map to
`frontmatter`/`settings` sources; P3 to `plugins`).

## Phase 2: Report

Present findings as the severity-rated table in
[reference/criteria.md](reference/criteria.md) "Output format". For each finding, give the concrete
recommendation from its check: replace the fragile grant with the bare-name-on-PATH pattern from the
convention, and add an **Operator setup** note where a user-global `~/.claude/settings.json` rule is
required.

### Severity guide

| Severity | Criteria |
| --- | --- |
| error | Non-portable grant that leaks a username / breaks on other machines (P2) |
| warning | Interpreter/runner-led grant whose broad forms auto mode drops, or an inert self-grant (P1, P3) |

A clean scan ("No fragile permission grants found.") is a valid outcome — report it as such.

## Consumer conventions

A consuming repo may declare, in its own `CLAUDE.md` / `.claude/rules/`, additional interpreter tokens
or path shapes it treats as fragile, or a documented exemption (e.g. a deliberately broad grant behind
a PreToolUse hook). Read those when present; this skill does not assume them.
