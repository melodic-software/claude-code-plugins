---
description: "Audit Claude Code permission GRANTS for portability and auto-mode durability. Scans skill/command/agent frontmatter allowed-tools and settings.json/settings.local.json/user-global permissions.allow for interpreter-wildcard rules dropped in auto mode, hardcoded machine/user paths, and inert plugin self-grants. Use when: 'check permission rules', 'why was my allowed-tools grant ignored', 'audit allow rules', 'is this permission portable', after authoring a code-execution grant, or when a guarded helper is denied despite an allow rule. Report-only."
argument-hint: "[scope]: frontmatter|settings|plugins|all (default: all)"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Audit permission grants for portability and auto-mode durability
---

## Purpose

Audit whether a repo's permission **grants** actually take effect. Answers a question the sibling
`audit` skill does not: "Are our allow-rules and `allowed-tools` grants portable across
machines and durable when the session enters auto mode, and is the operative rule in a place that can
work?"

The principle, the three anti-patterns, and the correct pattern (with official-doc citations) live in
the marketplace's **permission-rule-hygiene** convention, published at
<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/permission-rule-hygiene/README.md>.
The mechanical check definitions (P1/P2/P3, severities, detector invocation) are in
[reference/criteria.md](reference/criteria.md), which carries every recommendation this skill needs at
run time. The convention is the doctrine's owner, not a runtime dependency.

## Scope boundary (route out)

This skill owns grant portability + auto-mode durability + who adds the operative rule. It does **not**
own config-file correctness. Baseline deny/ask presence, overly broad patterns, and live plugin
drift belong to the sibling `audit` skill. When a request is about
those, route it there rather than answering here. The `audit` skill in the `claude-memory` plugin
owns the instruction layer (CLAUDE.md / rules / auto-memory).

## Arguments

Parse `$ARGUMENTS` for an optional scope filter. **It narrows which checks may produce findings,
never what the detector scans.** One full detector run happens either way, and the filter is
applied to its output:

- `frontmatter`: skill/command/agent `allowed-tools` only
- `settings`: project, local, and user-global `permissions.allow` only
- `plugins`: plugin `settings.json` self-grant (P3) only
- `all`: everything (default)

Saying so is the fix, not a workaround. The filter reads like a scan-scope, and the cost argument
for making it one no longer holds: since #2249 the root is a git toplevel, `$CLAUDE_PROJECT_DIR`, or
an explicitly named directory, never an unbounded sweep, and over this repository the two `find`
walks measure **0.49 s** and **0.41 s** (2026-08-12). Detector flags to skip half a second of walk
would buy nothing and add a second place for scope to be defined. The coverage block still reports
the whole denominator on a filtered run, so a narrowed report never implies a narrowed scan.

This skill is report-only. There is no `--fix`: the correct P3 remediation is inherently
operator-manual (the bare-name rule must land in user-global `~/.claude/settings.json`, which a skill
or plugin cannot write), and P1/P2 rewrites are judgment calls the operator confirms.

## Phase 1: Detect

Run the deterministic spine:

```shell
bash "${CLAUDE_PLUGIN_ROOT}/skills/audit-permission-grants/scripts/permission-rule-check.sh"
```

It scans frontmatter `allowed-tools` and settings `permissions.allow` across the consuming repo and
the user-global settings file (`${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json`), and prints one
finding per fragile grant (`<severity> [<check>] <source>: <detail>`). `--count` prints the count.
**Exit 2 is the environment-gap channel: report the gap rather than a clean bill.** Three things
raise it: a missing `jq`, a scan root that resolves to neither a git toplevel nor
`$CLAUDE_PROJECT_DIR`, and an unresolvable user scope when the user-global scan cannot locate
`${CLAUDE_CONFIG_DIR:-$HOME/.claude}`. On an unresolvable project root, say the scan did not run and
give the fix: run from inside the repository you mean to scan, or set
`$PERMISSION_HYGIENE_SCAN_ROOT` explicitly. That variable is a supported operator lever, not a
test-only seam; `$PERMISSION_HYGIENE_FIXTURE_DIR` still works as a back-compatible alias and the new
name wins when both are set. Never report "no fragile permission grants found" on an exit 2.
`settings.local.json` is parsed for its `permissions.allow` array only, never echoed wholesale.

### Report the denominator, always

Every run ends with a **coverage block**, and it is not optional garnish. It is what makes a clean
result readable. Carry its numbers into the report:

- **A clean bill needs a non-zero denominator.** `No fragile permission grants found.` is printed
  only when the run actually parsed at least one `allowed-tools` block or allow rule. When it parsed
  none the detector prints `NOTHING TO AUDIT` instead. **Relay that as the outcome; never soften it
  into a clean bill.** A scan of nothing is not evidence about grants.
- **Say what was not read.** The block counts paths the walk could not open, settings files present
  but not valid JSON (whose rules were skipped entirely), and files an exclusion rule removed. Each
  of those is a hole in the denominator, and each belongs in the report next to the finding count.
- **Name the scopes this detector never opens**: managed-policy and enterprise settings, a
  `--settings` flag file, the pre-v2.1.211 start-directory copy. `audit-permission-state` owns the
  question of which scopes exist; this skill's silence about them is a boundary, not a result.

A user-global finding is reported the same as any other, but its remediation is the operator's: a
skill cannot write that file. Expect this scope to carry the most findings on a long-lived machine.
"Always allow" writes there, and nothing prunes it.

If a scope filter was given, run the full detector and present only the matching checks (P1/P2 map to
`frontmatter`/`settings` sources; P3 to `plugins`).

## Phase 2: Report

Present findings as the severity-rated table in
[reference/criteria.md](reference/criteria.md) "Output format". For each finding, give the concrete
recommendation from its check. For P1, match the platform reality the convention records: where
plugin `bin/` is not reliably on the Bash tool's PATH (see the convention's **Known gap** section),
prescribe the bundled-path grant that works today and an operator-setup note for the bare-name rule.
Do not unconditionally tell the operator to expose a bare command on PATH when that end state is not
yet reachable on the measured platform. Add an **Operator setup** note wherever a user-global
`~/.claude/settings.json` rule is required.

### Severity guide

| Severity | Criteria |
| --- | --- |
| error | Non-portable grant that leaks a username / breaks on other machines (P2) |
| warning | Interpreter/runner-led grant whose broad forms auto mode drops, or an inert self-grant (P1, P3) |

A clean scan ("No fragile permission grants found.") is a valid outcome. Report it as such, with
the denominator beside it. `NOTHING TO AUDIT` is **not** that outcome; see "Report the denominator".

## Consumer conventions

A consuming repo may declare, in its own `CLAUDE.md` / `.claude/rules/`, additional interpreter tokens
or path shapes it treats as fragile, or a documented exemption (e.g. a deliberately broad grant behind
a PreToolUse hook). Read those when present; this skill does not assume them.

**Three constraints on those declarations, because the repo being audited is the repo that writes
them.** The docs name this threat model directly, in "Review project skills before trusting a
repository, since a skill can grant itself broad tool access"
(<https://code.claude.com/docs/en/skills>, fetched 2026-08-12), and an exemption read out of the
audited tree is input from the subject of the audit:

1. **Disclosure.** Every declaration the run read is named in the report, with the file it came from
   and what it changed, whether or not it altered a single finding. A declaration that was read and
   left no trace in the report is indistinguishable from one that was never read.
2. **Narrowing only in the report, never in the finding set.** A declaration may ADD fragile tokens
   or path shapes. It may never delete a finding. An exemption downgrades a finding's severity and
   annotates it `exempt — <declaration source>: <stated reason>`; the row stays in the table and
   stays in the counts.
3. **A suppressed report must not read like a clean one.** If every finding in a run is exempted,
   the report says so explicitly, "N finding(s), all exempted by consumer declaration", and does
   not print a clean bill. Combined with the denominator, that closes the two ways this report could
   claim health it never established: an empty scan, and a silenced one.
