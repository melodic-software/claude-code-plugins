# RESEARCH — Claude Code bundled (built-in) skills

## Task restatement

Establish, for the author of a marketplace skill that inventories and trims a session's fixed
startup context payload: the current inventory of bundled skills shipped with Claude Code and the
version that introduced the mechanism; exactly what loads into every request per skill and its
documented always-loaded cost; every supported way to disable bundled skills individually or
wholesale, with exact key spellings verified against current docs; whether individual bundled
skills can be disabled or it is all-or-nothing; what `/context`'s Skills row actually counts; and
how bundled skills interact with `claude --safe-mode` and a `CLAUDE_CONFIG_DIR` clean-room
comparison. Every claim carries its source URL and fetch date, and anything unverified is marked
as such rather than filled in from recall.

Environment for all Tier-0 evidence: Claude Code **v2.1.232** (linux-x64), inspected **and
executed** on **2026-08-17**. All documentation fetched 2026-08-17.

## Headline answers

1. **Inventory** — 42 bundled skills load at runtime; 37 static registration call sites; **13**
   are publicly documented for the terminal CLI (plus one bundled workflow, `/deep-research`); only
   ~14 are actually listed to the model. The differences are availability gating and visibility
   state, not a docs error. **No single version introduced the mechanism** — that is an unresolved
   gap, bracketed at 2.1.63–2.1.153.
2. **What loads** — only **name + description** (plus `whenToUse` when present), never the SKILL.md
   body. Official statement quoted in the sidecar. Cost per skill =
   `name.length + 4 + min(text, 1536)` characters; a `name-only` entry costs `name.length + 2`.
3. **Disable mechanisms** — five supported ones exist, all with exact spellings verified:
   `disableBundledSkills`, `CLAUDE_CODE_DISABLE_BUNDLED_SKILLS`, `skillOverrides`, `Skill(...)`
   permission rules, and name shadowing. Plus `DISABLE_DOCTOR_COMMAND` for the one exempt skill.
4. **Individual disable** — **YES, supported.** Not all-or-nothing. `skillOverrides` reaches
   bundled skills, confirmed in the binary's resolver, prescribed by the docs, and demonstrated
   empirically (listing 173 → 172 skills).
5. **`/context` Skills row** — the **post-budget** size of the skill *listing*, not SKILL.md
   bodies. Bundled skills appear in its breakdown labelled **"built-in"**. Over-reports on
   v2.1.195 and earlier.
6. **safe-mode / CLAUDE_CONFIG_DIR** — **neither removes bundled skills.** Both zero out
   user/project/plugin skills while all 42 bundled skills still load. Verified by running the
   binary.

## Sidecars

| Section | Abstract | File |
|---|---|---|
| Inventory | Claude Code v2.1.232 registers 37 bundled skills in-binary while the public commands reference documents 13, because most are availability-gated; "bundled skill" is one of three distinct categories and no single version "introduced" the mechanism. | [RESEARCH-inventory.md](RESEARCH-inventory.md) |
| Context cost | Only name + description (plus whenToUse) load per skill each turn, capped per-entry at 1,536 chars and in aggregate at 1% of the context window; /context's Skills row reports the post-budget listing size, which since v2.1.196 matches what the model actually receives. | [RESEARCH-context-cost.md](RESEARCH-context-cost.md) |
| Disable mechanisms | Five supported mechanisms exist — disableBundledSkills, CLAUDE_CODE_DISABLE_BUNDLED_SKILLS, per-skill skillOverrides, Skill-tool permission deny rules, and name-shadowing — and individual bundled skills CAN be disabled, so it is not all-or-nothing. | [RESEARCH-disable-mechanisms.md](RESEARCH-disable-mechanisms.md) |
| Safe mode and isolation | Empirically, neither --safe-mode nor a clean CLAUDE_CONFIG_DIR removes bundled skills — both strip user/project/plugin skills while all 42 bundled skills still load — so neither gives a bundled-free clean-room baseline. | [RESEARCH-safe-mode-and-isolation.md](RESEARCH-safe-mode-and-isolation.md) |
| Fetch log | Per-claim fetch log with artifact-ladder rungs and outcomes, plus conflicts, gaps, recency status and the outcome-gate result for the bundled-skills research run. | [RESEARCH-fetch-log.md](RESEARCH-fetch-log.md) |

Coverage ledger: [research-checklist.md](research-checklist.md) — graded by
`plugins/discovery/scripts/check-coverage-complete.sh`, **exit 0**.

## Section → anchor map

| Question | Sidecar | Anchor |
|---|---|---|
| Q1 inventory + introducing version | RESEARCH-inventory.md | `#the-documented-inventory--13-bundled-skills`, `#which-version-introduced-the-mechanism--not-resolved` |
| Q2 what loads / per-skill cost | RESEARCH-context-cost.md | `#q2--name--description-only-official-statement-verbatim`, `#the-exact-cost-formula--tier-0-from-the-shipped-binary` |
| Q3 disable mechanisms | RESEARCH-disable-mechanisms.md | `#answer-to-q3--the-mechanisms-that-exist` |
| Q4 individual vs wholesale | RESEARCH-disable-mechanisms.md | `#answer-to-q4--individual-disable-is-supported-not-all-or-nothing` |
| Q5 /context Skills row | RESEARCH-context-cost.md | `#q5--what-contexts-skills-row-counts` |
| Q6 safe-mode / CLAUDE_CONFIG_DIR | RESEARCH-safe-mode-and-isolation.md | `#q6--safe-mode-and-claude_config_dir-clean-room-comparison` |
| Conflicts, gaps, recency, gate | RESEARCH-fetch-log.md | `#conflicts`, `#gaps`, `#recency-status`, `#outcome-gate-result` |

## Next-stage handoff

### Settled — safe to build on

- Bundled skills contribute **listing text only** (name + description + optional `whenToUse`),
  never SKILL.md bodies, to every request.
- Per-skill character cost formula and the 1,536-char per-entry cap are exact and first-party.
- Three levers with distinct effects, all first-party: `disableBundledSkills` (wholesale, spares
  `/doctor`), `skillOverrides` (per-skill: `on` / `name-only` / `user-invocable-only` / `off`),
  `DISABLE_DOCTOR_COMMAND` (the exempt one).
- `skillOverrides` **does** apply to bundled skills and **does not** apply to plugin skills.
- The measurement surface a trimming tool should use is the **listing**, observable three ways:
  `/context`'s Skills row, `/doctor`'s estimate, or the `[WARN] Skill listing over budget` debug
  line via `--debug-file`.
- Neither `--safe-mode` nor `CLAUDE_CONFIG_DIR` yields a bundled-free baseline; only
  `CLAUDE_CODE_DISABLE_BUNDLED_SKILLS=1` (plus `DISABLE_DOCTOR_COMMAND=1`) does.

### Design implications the author should weigh

- **Report listed cost, not loaded count.** In the measured session, disabling all bundled skills
  removed 14 skills / 5,739 chars from the listing while the loaded count fell 42 → 1. Reporting
  the loaded count would overstate the win ~3×.
- **Bundled skills are protected inside the budget.** When the listing overflows, the binary keeps
  bundled entries at full length and collapses user/project entries first. So bundled skills are a
  *floor* on the payload, which is precisely why they are a legitimate named trim target — the
  budget will not reclaim them for you.
- **`name-only` is the low-risk default trim.** It preserves `/name` invocability and menu
  presence while removing the description, which is where nearly all the cost is.
- Prefer `skillOverrides` over permission deny rules for size: deny rules are documented to govern
  *invocation*, and their effect on listing size is **unverified** (see Gaps).

### Open decisions for the author / user

1. Whether the tool should write `skillOverrides` into `.claude/settings.local.json` — the same
   file the built-in `/skills` menu writes — and how to avoid clobbering entries a user set there.
2. Whether to surface the three undocumented `CLAUDE_CODE_DISABLE_*_SKILL(S)` env vars at all,
   given their behaviour is unverified.
3. Whether to depend on the `--debug-file` WARN line, which is a debug diagnostic with no
   stability guarantee, versus the structured `/context` twin the binary exposes.

## Unverified / explicitly not established

- The version that introduced the bundled-skill mechanism.
- Semantics of `CLAUDE_CODE_DISABLE_CLAUDE_API_SKILL`, `CLAUDE_CODE_DISABLE_CLAUDE_CODE_SKILL`,
  `CLAUDE_CODE_DISABLE_POLICY_SKILLS` (existence is Tier-0; purpose is inferred from names only).
- Whether a `Skill(name)` deny rule shrinks the listing.
- Any per-skill **token** figure (docs give characters only; a circulating "~75–150 tokens" figure
  is Tier-2 and was rejected).
- Naming of 3 of the 37 registration call sites (artifact `doc`/`sheet`/`slides` kinds).
- Whether `/config` exposes any of these keys.
