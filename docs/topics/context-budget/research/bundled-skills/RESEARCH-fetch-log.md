---
topic: bundled-skills
section: fetch-log
abstract: Per-claim fetch log with artifact-ladder rungs and outcomes, plus conflicts, gaps, recency status and the outcome-gate result for the bundled-skills research run.
claims:
  - claim: "Recency gate satisfied: latest Claude Code release confirmed as 2.1.233 from the upstream CHANGELOG fetched this turn; the installed and inspected binary is 2.1.232, one patch behind, with no bundled-skill-relevant change between them."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md"
        tier: 1
        pool: "Anthropic (upstream changelog)"
      - url: "local Tier-0: claude --version → 2.1.232 (Claude Code)"
        tier: 0
        pool: "Anthropic (shipped binary)"
produced_by: all-phases
---

# Fetch log, conflicts, gaps, recency, gate result

All fetches performed **2026-08-17**. Environment: Claude Code v2.1.232 (linux-x64), remote
session. Rung numbers refer to the discipline's artifact ladder (1 = deepest technical artifact,
6 = third-party).

## Fetch log

| Claim | URL or command | Rung | Tool | Outcome |
|---|---|---|---|---|
| Bundled inventory | `grep registerBundledSkill` on `@anthropic-ai/claude-code-linux-x64/claude` v2.1.232 | 1 (source as spec) | Bash | carries the claim |
| Bundled inventory | <https://code.claude.com/docs/en/commands.md> | 2 | curl | carries the claim |
| Bundled inventory | <https://code.claude.com/docs/en/skills.md> | 3 | curl | carries the claim |
| Bundled inventory | <https://code.claude.com/docs/en/skills> | 3 | WebFetch | carries the claim |
| Bundled inventory | `claude --debug-file … -p hi` → `getSkills returning: … 42 bundled skills` | 1 | Bash (runtime) | carries the claim |
| Introducing version | <https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md> | 4 | curl | fetched and searched, does not carry the claim — no entry announces the mechanism |
| Introducing version | in-binary VCS history | 1 | — | does not exist for this claim class (closed-source binary; `anthropics/claude-code` publishes issues + changelog only) |
| What loads per skill | <https://code.claude.com/docs/en/skills.md> §"Skill descriptions are cut short" | 3 | curl | carries the claim |
| What loads per skill | binary `Yer()` / `entryLen` formula, v2.1.232 | 1 | Bash | carries the claim |
| What loads per skill | <https://code.claude.com/docs/en/skills> (frontmatter/context table) | 3 | WebFetch | carries the claim |
| Per-entry cap 1,536 | <https://code.claude.com/docs/en/skills.md> | 3 | curl | carries the claim |
| Per-entry cap 1,536 | <https://code.claude.com/docs/en/settings.md> (`skillListingMaxDescChars`) | 2 | curl | carries the claim |
| `disableBundledSkills` | <https://code.claude.com/docs/en/settings.md> | 2 | curl | carries the claim |
| `disableBundledSkills` | binary zod `.describe()` text, v2.1.232 | 1 | Bash | carries the claim |
| `disableBundledSkills` | CHANGELOG 2.1.169 | 4 | curl | carries the claim |
| `CLAUDE_CODE_DISABLE_BUNDLED_SKILLS` | <https://code.claude.com/docs/en/env-vars.md> | 2 | curl | carries the claim |
| `CLAUDE_CODE_DISABLE_BUNDLED_SKILLS` | binary resolver `O9()` | 1 | Bash | carries the claim |
| `CLAUDE_CODE_DISABLE_BUNDLED_SKILLS` | `CLAUDE_CODE_DISABLE_BUNDLED_SKILLS=1 claude … -p hi` → 1 bundled skill | 1 | Bash (runtime) | carries the claim |
| `skillOverrides` values | <https://code.claude.com/docs/en/skills.md> §"Override skill visibility" | 3 | curl | carries the claim |
| `skillOverrides` values | <https://code.claude.com/docs/en/settings.md> | 2 | curl | carries the claim |
| `skillOverrides` values | CHANGELOG 2.1.129 | 4 | curl | carries the claim |
| `skillOverrides` reaches bundled skills | binary resolver `rVe()` | 1 | Bash | carries the claim |
| `skillOverrides` reaches bundled skills | `--settings '{"skillOverrides":{…}}'` → listing 173→172 skills, 116,003→114,415 chars | 1 | Bash (runtime) | carries the claim |
| `/doctor` exemption | binary `survivesBundledKillSwitch:!0` (one occurrence) | 1 | Bash | carries the claim |
| `/doctor` exemption | <https://code.claude.com/docs/en/skills.md> | 3 | curl | carries the claim |
| `/doctor` exemption | <https://code.claude.com/docs/en/env-vars.md> (`DISABLE_DOCTOR_COMMAND`) | 2 | curl | carries the claim |
| Skill permission rules | <https://code.claude.com/docs/en/skills.md> §"Restrict Claude's skill access" | 3 | curl | carries the claim |
| Skill permission rules | binary `L1s()` skill-name extractor | 1 | Bash | carries the claim |
| Skill permission rules | <https://code.claude.com/docs/en/permissions.md> | 2 | curl | fetched and searched, does not carry the claim — no `Skill(` rule examples on this page |
| Deny rules shrink the listing | <https://www.aihero.dev/how-to-kill-the-bloat-in-claude-codes-system-prompt> | 6 | WebFetch | unreachable after escalation — EGRESS_BLOCKED by the network proxy; WebSearch snippet retained as the only trace |
| `/context` Skills row | <https://code.claude.com/docs/en/skills.md> | 3 | curl | carries the claim |
| `/context` Skills row | binary `/context` producer struct | 1 | Bash | carries the claim |
| `/context` Skills row | <https://code.claude.com/docs/en/commands.md> (`/context` row) | 2 | curl | fetched and searched, does not carry the claim — describes the grid, not the Skills row's accounting |
| `/context` Skills row | <https://code.claude.com/docs/en/context-window> | 3 | WebFetch | fetched and searched, does not carry the claim — simulation lists startup items, no Skills-row definition |
| Listing budget | <https://code.claude.com/docs/en/settings.md> (`skillListingBudgetFraction`) | 2 | curl | carries the claim |
| Listing budget | <https://code.claude.com/docs/en/env-vars.md> (`SLASH_COMMAND_TOOL_CHAR_BUDGET`) | 2 | curl | carries the claim |
| Listing budget | runtime `[WARN] Skill listing over budget: 173 skills, 116003 chars > 30000 budget` | 1 | Bash (runtime) | carries the claim |
| `--safe-mode` vs bundled | `claude --safe-mode --debug-file … -p hi` → 42 bundled skills | 1 | Bash (runtime) | carries the claim |
| `--safe-mode` vs bundled | <https://code.claude.com/docs/en/cli-reference.md> | 2 | curl | fetched and searched, does not carry the claim — says "skills … do not load" without distinguishing bundled |
| `--safe-mode` vs bundled | `claude --help` v2.1.232 | 1 | Bash | fetched and searched, does not carry the claim — same ambiguity |
| `CLAUDE_CONFIG_DIR` vs bundled | `CLAUDE_CONFIG_DIR=<empty> claude … -p hi` → 42 bundled skills | 1 | Bash (runtime) | carries the claim |
| `CLAUDE_CONFIG_DIR` vs bundled | <https://code.claude.com/docs/en/env-vars.md> | 2 | curl | carries the claim (scope: config dir only) |
| Doc-page enumeration | <https://code.claude.com/sitemap.xml> | — | curl | carries the claim (exhaustive surface for this host's pages) |
| **Recency** | <https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md> | 4 | curl | carries the claim — **2.1.233 (top entry, undated in file)** — **current** |

Note on the changelog rung: the file carries no per-release dates, so the confirmed-latest version
is cited without a release date. `gh` was not installed in this environment, so
`gh api repos/anthropics/claude-code/releases/latest` could not be run; the raw `CHANGELOG.md` on
`main` was used instead, which is the same publisher and was fetched this turn.

## Conflicts

1. **37 in-binary registrations vs 42 loaded vs 13 documented vs 14 listed.** All four numbers are
   real and measure different things. Static `registerBundledSkill` call sites = 37 (some are
   loop/template-driven, so they under-count). Runtime loaded = 42. Publicly documented for the
   terminal CLI = 13 (+1 workflow). Actually *listed to the model* in this session = ~14 (derived
   from the 173→159 drop under the kill switch). **Resolution: availability gating plus
   visibility state.** Primary (binary + runtime) wins over the doc count, and the doc count is not
   wrong — it is scoped to the terminal CLI. Recorded rather than collapsed.

2. **Docs say `--safe-mode` disables "skills"; runtime shows bundled skills surviving.** Primary
   (runtime observation) wins. Resolution: "skills" in that sentence means user/project/plugin
   skills. Flagged because a reader will get this wrong.

3. **A Tier-2 source claims bare-tool-name deny rules strip definitions from the payload while
   scoped rules do not.** Unresolved — the source is egress-blocked. Not accepted, not used.

## Gaps

- **Which version introduced the bundled-skill mechanism — NOT RESOLVED.** Checked: the full
  upstream `CHANGELOG.md` (365 version headings, down to 0.2.21), skills doc, commands reference.
  Unchecked: any pre-2.x release notes published off-changelog, and the binary's own history (no
  public VCS). Best-supported bracket: the *name* "bundled slash commands" first appears at
  **2.1.63**; "bundled skills" at **2.1.153**; individual members predate both (`/debug` at 2.1.30).
  No single introducing version is claimed.
- **Semantics of `CLAUDE_CODE_DISABLE_CLAUDE_API_SKILL`, `CLAUDE_CODE_DISABLE_CLAUDE_CODE_SKILL`,
  `CLAUDE_CODE_DISABLE_POLICY_SKILLS` — existence only.** Present in the binary's env table
  (Tier 0). Checked: env-vars.md, settings.md, skills.md — none document them. Unchecked: runtime
  behaviour (not tested). Names imply purpose; purpose is **unverified**.
- **Whether a `Skill(name)` deny rule removes the description from the listing.** Checked:
  skills.md, permissions.md, settings.md, the binary's budget path. Unchecked: the egress-blocked
  aihero.dev article, and a runtime A/B with a deny rule in place (not run). The binary's collapse
  set is keyed on `skillOverrides`, not on permission rules, which points to **no**, but this is
  **not** established.
- **Resolution of 3 of 37 registration call sites** (the artifact `doc`/`sheet`/`slides` kinds):
  whether they register as bare kinds or `artifact-`-prefixed. Unchecked: deeper de-minification.
- **`/config` as a disable surface.** Checked: commands.md, settings.md, skills.md — `/skills` is
  documented as the interactive surface, `/config` is not. Unchecked: the live interactive
  `/config` TUI, which could not be driven from this non-interactive session.
- **Generalisability of the character measurements.** 116,003 / 5,739 / 30,000 are from *this*
  session (208 plugin skills installed). Another machine will differ. The formulas generalise; the
  numbers do not.

## Recency status

| Subject | Primary age | Status |
|---|---|---|
| Claude Code binary behaviour | v2.1.232, inspected and executed this turn | current |
| Upstream changelog | v2.1.233 top entry, fetched this turn | current — one patch ahead of the inspected binary; its entries are unrelated to bundled-skill semantics except a `/checkup` alias fix |
| code.claude.com docs | all pages fetched this turn | current |

No major-version bump between the inspected binary and the confirmed-latest release, so no doc
invalidation applies.

## Outcome gate result

| # | Criterion | Owner | Result |
|---|---|---|---|
| 1 | Every claim has ≥1 Tier 0/1 source captured this turn | run | **PASS** |
| 2 | No claim is all-Tier-2 | run | **PASS** — the one Tier-2-only claim (per-skill token estimate) is explicitly rejected, not accepted |
| 3 | Every Phase 2/3 query traces to a numbered gap/conflict | run | **PASS** |
| 4 | ≥2 independent corroborators per claim | **verifier** | not self-graded — `sources[]` with `pool` supplied in every sidecar |
| 5 | Falsification query ran and is recorded | run | **PASS** — searched for "disable individual bundled skill not working"; it *falsified the anticipated framing* by surfacing that individual disable is supported, which was then confirmed against Tier 0/1 |
| 6 | Recency gate satisfied | run | **PASS** — 2.1.233 confirmed, verdict `current` |
| 7 | Every accepted claim HIGH confidence | **verifier** | not self-graded |
| 8 | Project fit | **parent** | not self-graded |
| 9 | Artifact-ladder rungs accounted per accepted claim | run | **PASS** — see fetch log; rung 1 reached for every accepted claim via the binary or runtime observation |
| 10 | Every reported absence names checked and unchecked sources | run | **PASS** — see Gaps |
| 11 | Coverage ledger fully marked | run, script | **PASS** — `check-coverage-complete.sh` exit 0 (cited in RESEARCH.md) |
