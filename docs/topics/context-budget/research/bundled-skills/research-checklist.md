# Coverage ledger — Claude Code bundled skills

Corpus verdict: **BOUNDED**. Three enumerable sets: (a) the bundled-skill registry inside the
shipped Claude Code binary, (b) the disable mechanisms named in the dispatch question, (c) the
first-party documentation pages that own each answer.

Enumeration surfaces (exhaustive by construction):

- (a) `registerBundledSkill` call sites in `@anthropic-ai/claude-code-linux-x64/claude` v2.1.232 —
  the registry itself, not a doc about it. 37 call sites.
- (b) the dispatch question's own named list, plus every `CLAUDE_CODE_*SKILL*` env var in the
  binary's env-accessor table.
- (c) `https://code.claude.com/sitemap.xml` — exhaustive for that host's pages.

Explicit narrowing: doc-page rows cover only pages that own one of the six questions. Pages about
unrelated subsystems are out of scope and were not enumerated as rows.

| # | Corpus item | Depth criterion | Done |
|---|-------------|-----------------|------|
| 1 | Bundled-skill registry: enumerate every `registerBundledSkill` call site | every call site's `name:` resolved to a literal or recorded as unresolved, with a count | [x] |
| 2 | `survivesBundledKillSwitch` registrations | every occurrence located and the surviving skill(s) named | [x] |
| 3 | Category boundary: bundled skill vs built-in prompt command vs builtin-plugin skill | the discriminating predicate read out of the binary for each of the three | [x] |
| 4 | `disableBundledSkills` settings key | exact spelling + its own schema `.describe()` text read verbatim | [x] |
| 5 | `CLAUDE_CODE_DISABLE_BUNDLED_SKILLS` env var | exact spelling + the resolver function that reads it, read verbatim | [x] |
| 6 | `skillOverrides` settings key | exact spelling + full enum of accepted values + `.describe()` text verbatim | [x] |
| 7 | Per-skill `CLAUDE_CODE_DISABLE_*_SKILL(S)` env vars | every one in the env table named, with the skill each governs | [x] |
| 8 | Always-loaded per-skill payload: what text, what length | the entry-length formula and the listed-text function read out of the binary | [x] |
| 9 | Skills listing char budget + its env override | budget env var named and the truncation branch read | [x] |
| 10 | `/context` Skills row: what it counts | the row's producer struct + the label mapping read out of the binary | [x] |
| 11 | `--safe-mode` behaviour toward skills | flag help text captured this turn from the shipped binary | [x] |
| 12 | `--disable-slash-commands` flag | flag help text captured this turn from the shipped binary | [x] |
| 13 | Official docs: Skills page | fetched this turn; its statement on what loads at startup read | [x] |
| 14 | Official docs: settings reference | fetched this turn; searched for `disableBundledSkills` / `skillOverrides` | [x] |
| 15 | Official docs: CLI reference | fetched this turn; `--safe-mode` entry read | [x] |
| 16 | Official docs: slash commands / `/context` | fetched this turn; searched for a Skills-row description | [x] |
| 17 | Official docs: permissions / Skill-tool deny rules | fetched this turn; verdict on whether Skill is a denyable tool | [x] |
| 18 | Upstream CHANGELOG — recency gate + which version introduced bundled skills | latest release confirmed this turn; changelog searched for the introducing entry | [x] |
| 19 | `CLAUDE_CONFIG_DIR` clean-room comparison | its documented scope read; verdict on whether it moves bundled skills | [x] |
| 20 | Falsification: does a supported per-bundled-skill disable actually exist? | one deliberate attempt to break the leading hypothesis, recorded | [x] |
