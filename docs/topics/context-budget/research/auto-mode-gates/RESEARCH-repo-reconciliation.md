---
topic: auto-mode-gates
section: repo-reconciliation
abstract: The permission-rule-hygiene convention holds on every claim checked, with one correction (the auto-mode default is version-gated at v2.1.228/v2.1.233, not dated 2026-08-14) and one gap it does not yet cover (it reasons only about allow rules, never about forcing a prompt).
claims:
  - claim: "The convention's auto-mode default framing is date-based (2026-08-14) where the current docs are version-based (v2.1.228 macOS/Linux/WSL, v2.1.233 native Windows); the quoted August-14 passage is no longer present on the cited page."
    confidence: HIGH
    tiers: [1, 0]
    sources:
      - url: "https://code.claude.com/docs/en/permission-modes#which-mode-a-session-starts-in"
        tier: 1
        pool: "Anthropic — code.claude.com docs"
      - url: "https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md"
        tier: 1
        pool: "anthropics/claude-code repository"
  - claim: "The convention's core anti-pattern-1 claim, its plugin-cannot-self-grant claim, and its allowed-tools turn-scoping claim are all confirmed verbatim against the current docs."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/permission-modes#how-the-classifier-evaluates-actions"
        tier: 1
        pool: "Anthropic — code.claude.com docs"
      - url: "https://code.claude.com/docs/en/plugins-reference"
        tier: 1
        pool: "Anthropic — code.claude.com docs"
      - url: "https://code.claude.com/docs/en/skills"
        tier: 1
        pool: "Anthropic — code.claude.com docs"
produced_by: phase-3
---

# Reconciliation with `docs/conventions/permission-rule-hygiene/README.md`

Read end to end (Tier 0, local). Verdict: **the convention is sound and nothing in this research
contradicts its operative guidance.** Three refinements and one genuine gap.

## Confirmed verbatim

- **Anti-pattern 1** (interpreter-wildcard / blanket allow rules dropped in auto mode) — the
  convention quotes the decision-order passage exactly as it still reads today. Confirmed.
- **Anti-pattern 3** (a skill or plugin cannot self-grant) — all three cited constraints hold:
  `allowed-tools` is turn-scoped and "clears when you send your next message"; a plugin's
  `settings.json` supports "Only the `agent` and `subagentStatusLine` keys"; and project-settings
  `defaultMode: "auto"` is ignored. Confirmed.
- **The "design for both" caution** — "never document a prompt the operator will wait for in a
  session that will never issue one" — is not merely still correct, it is the single most relevant
  sentence in this repo for the skill being designed. Auto mode routes an uncovered protected-path
  write to the classifier, which "may approve or deny without prompting."

## Correction 1 — the default is version-gated, not dated

The convention's section heading reads "**Auto mode is the default from 2026-08-14**" and block-quotes
a passage beginning "Starting August 14, 2026, auto mode becomes the default permission mode for new
sessions on Pro, Max, and Team plans."

**That passage is not present on
[permission-modes](https://code.claude.com/docs/en/permission-modes) as fetched 2026-08-17.** The
page now expresses the same fact as a version floor plus a first-match table: "The built-in `auto`
default requires Claude Code v2.1.228 or later on macOS, Linux, and WSL, and v2.1.233 or later on
native Windows. On earlier versions, the built-in default is Manual."

This is very likely the announcement text having been replaced by the shipped-behavior text rather
than a factual reversal — the substance (auto is the built-in default on Pro/Max/Team in terminal
and VS Code) is unchanged. But the convention now quotes text that cannot be verified at its own
cited URL, which will fail the next audit that checks it. **Recommend re-quoting to the version
sentence.** The practical difference is real: a user on v2.1.220 is not in auto mode by default
regardless of the date.

Two sub-points also drifted and are worth refreshing while editing:

- The convention says a self-set `defaultMode` "stays in place unless you accept the one-time switch
  prompt." Still true and still documented, but the current page adds that the one-time ask fires
  only when `~/.claude/settings.json` sets a different `defaultMode` **and no other settings file
  sets one**.
- The convention's plan-scoping paragraph on Bedrock/Foundry/etc. is confirmed and if anything
  strengthened — those providers are now their own row in the built-in-default table, landing on
  `default`. Worth adding: **`claude -p` and the Agent SDK are also `default`**, which the convention
  does not currently mention and which matters for any CI-invoked skill.

## Correction 2 — a plugin *can* ship hooks, and the convention's framing may be read as denying it

Anti-pattern 3 correctly says a plugin cannot ship *permission rules*. But a reader could over-generalize
that to "a plugin cannot influence permission decisions", which is false and is the crux of this
research: **`hooks/hooks.json` is a documented plugin component**, and a `PreToolUse` hook returning
`"ask"` forces a prompt the auto-mode classifier cannot silently approve (v2.1.211+). Skill
frontmatter can carry hooks too.

**Recommend a sentence in anti-pattern 3** distinguishing the two: a plugin cannot ship rules, but it
can ship hooks — and hooks are the supported route to *tightening* a decision, while rules are the
only route to *loosening* one and must come from the operator.

One boundary to state alongside it: **plugin subagents** do not get this. Per
[sub-agents](https://code.claude.com/docs/en/sub-agents) (fetched 2026-08-17), "For security reasons,
plugin subagents don't support the `hooks`, `mcpServers`, or `permissionMode` frontmatter fields."
Whether the same exclusion reaches *plugin skill* frontmatter hooks is **not stated** — see Gaps.
The `hooks/hooks.json` route is documented and unambiguous, so prefer it over skill frontmatter in a
plugin.

## Correction 3 — "silently" is field observation, not documentation

The convention repeatedly calls the auto-mode drop silent, and `audit-permission-state` says
"**silently** drops". The docs describe the drop but never characterize it as unannounced. Given
that skill ships an `--oracle` mode that reads "the harness's own drop narration", the harness
evidently narrates something. Low stakes, but the word is doing evidential work it is not sourced
for; consider marking it as observed behavior.

## The gap the convention does not yet cover

The convention reasons **entirely about allow rules** — how to write a grant that survives auto mode.
It has no guidance for the opposite direction: **how to make an action stop for a human when auto
mode would otherwise proceed.** That is exactly what the new skill needs, and it is a distinct
problem with a distinct answer (hooks and `permissions.ask`, not rule shape).

**Recommend a companion section or sibling convention** covering the tightening direction, anchored
on: `permissions.ask` is operator-installed and holds in auto *and* bypassPermissions; a PreToolUse
hook `"ask"` is skill-shippable and holds in auto only, with a v2.1.211 floor; and neither survives
`disableAllHooks` or a `PermissionRequest` hook that answers on the user's behalf. The full analysis
is in [`RESEARCH-forcing-a-human-gate.md`](./RESEARCH-forcing-a-human-gate.md).

## Project fit

The proposed design fits this repo's existing conventions well:

- **`audit-permission-state` is report-only and says so in its own description.** The new skill should
  state its write boundary with the same prominence, and ideally split reporting from mutation the
  way that skill and `/doctor`'s read-only `claude doctor` entry point both do.
- **The operator-setup boundary is already this repo's established pattern** (`permission-rule-hygiene`
  step 3: "The skill/plugin documents an 'Operator setup' note telling the operator to add the
  bare-name rule once to `~/.claude/settings.json`"). The `permissions.ask` recommendation reuses that
  pattern exactly, just with `ask` instead of `allow` — no new concept for this repo's operators.
- **Do not invoke the helper through an interpreter.** If the skill ships a script to compute or apply
  the settings diff, anti-pattern 1 and the known `bin/`-on-PATH gap both apply unchanged; invoke it
  by its bundled path and do not assume it can be pre-approved.
