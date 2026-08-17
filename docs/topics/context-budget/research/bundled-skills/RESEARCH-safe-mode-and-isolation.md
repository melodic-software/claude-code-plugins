---
topic: bundled-skills
section: safe-mode-and-isolation
abstract: Empirically, neither --safe-mode nor a clean CLAUDE_CONFIG_DIR removes bundled skills — both strip user/project/plugin skills while all 42 bundled skills still load — so neither gives a bundled-free clean-room baseline.
claims:
  - claim: "--safe-mode does NOT disable bundled skills: all 42 still load, while skill-dir commands, plugin skills and builtin-plugin skills all drop to 0."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "local Tier-0 experiment 2026-08-17: claude --safe-mode --debug-file … -p hi → 'getSkills returning: 0 skill dir commands, 0 plugin skills, 42 bundled skills, 0 builtin plugin skills'"
        tier: 0
        pool: "Anthropic (shipped binary, observed runtime)"
      - url: "https://code.claude.com/docs/en/cli-reference.md — --safe-mode entry"
        tier: 1
        pool: "Anthropic (docs)"
      - url: "local Tier-0: claude --help v2.1.232 --safe-mode text"
        tier: 0
        pool: "Anthropic (shipped binary)"
  - claim: "CLAUDE_CONFIG_DIR relocates the config dir and so strips user/plugin skills, but bundled skills are unaffected — all 42 still load."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "local Tier-0 experiment 2026-08-17: CLAUDE_CONFIG_DIR=<empty dir> claude --debug-file … -p hi → '0 skill dir commands, 0 plugin skills, 42 bundled skills'"
        tier: 0
        pool: "Anthropic (shipped binary, observed runtime)"
      - url: "https://code.claude.com/docs/en/env-vars.md — CLAUDE_CONFIG_DIR"
        tier: 1
        pool: "Anthropic (docs)"
      - url: "local Tier-0: debug log line 'Loading skills from: … user=<CLAUDE_CONFIG_DIR>/skills'"
        tier: 0
        pool: "Anthropic (shipped binary, observed runtime)"
  - claim: "The kill switch removes 14 skills and 5,739 characters from the model-visible skill listing in this environment, leaving exactly 1 bundled skill loaded (/doctor)."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "local Tier-0 experiment 2026-08-17: baseline '173 skills, 116003 chars' vs CLAUDE_CODE_DISABLE_BUNDLED_SKILLS=1 '159 skills, 110264 chars'"
        tier: 0
        pool: "Anthropic (shipped binary, observed runtime)"
      - url: "local Tier-0: 'getSkills returning: … 1 bundled skills' under the kill switch"
        tier: 0
        pool: "Anthropic (shipped binary, observed runtime)"
      - url: "https://code.claude.com/docs/en/skills.md — 'disables every bundled skill except /doctor'"
        tier: 1
        pool: "Anthropic (docs)"
produced_by: phase-2+phase-4
---

# Q6 — safe-mode and CLAUDE_CONFIG_DIR clean-room comparison

**Headline: neither one gives you a bundled-skill-free baseline.** Both are commonly assumed to,
and both do not. This was verified by running the shipped binary, not by reading about it.

## Method — a reproducible measurement the caller's tool can reuse

Claude Code's debug log emits two lines that make the whole question directly observable:

```
[DEBUG] getSkills returning: <n> skill dir commands, <n> plugin skills, <n> bundled skills, <n> builtin plugin skills
[WARN]  Skill listing over budget: <n> skills, <n> chars > <n> budget — descriptions will be truncated.
```

Capture them with `--debug-file` on a throwaway prompt:

```bash
claude --debug-file /tmp/x.log -p "hi" >/dev/null 2>&1
grep -oE 'getSkills returning:.*|Skill listing over budget:.*' /tmp/x.log
```

The first line counts what **loaded**; the second counts what the **model actually sees**. They are
different stages and the distinction matters (see "A trap" below).

## Results, v2.1.232, measured 2026-08-17

| Configuration | skill dir | plugin | **bundled** | builtin plugin | Listing |
|---|---|---|---|---|---|
| Baseline (no flags) | 7 | 208 | **42** | 0 | 173 skills, 116,003 chars |
| `--safe-mode` | 0 | 0 | **42** | 0 | (under budget — no warning) |
| `CLAUDE_CONFIG_DIR=<empty>` | 0 | 0 | **42** | 0 | (under budget — no warning) |
| `CLAUDE_CODE_DISABLE_BUNDLED_SKILLS=1` | 7 | 208 | **1** | 0 | 159 skills, 110,264 chars |
| `skillOverrides {dataviz:off, code-review:name-only}` | 7 | 208 | 42 | 0 | 172 skills, 114,415 chars |

### `--safe-mode`

The docs say safe mode disables "skills":

> "Start with all customizations disabled to troubleshoot a broken configuration: CLAUDE.md,
> skills, plugins, hooks, MCP servers, custom commands and agents, output styles, workflows, custom
> themes, custom keybindings, status line and file-suggestion commands, LSP servers, and auto memory
> do not load."
> — <https://code.claude.com/docs/en/cli-reference.md>, fetched 2026-08-17

**Read that as "customizations", because that is what it measures.** Empirically, "skills" there
means *your* skills. All 42 bundled skills still load under `--safe-mode`; the debug log shows
`[reduced mode] Skipping skill dir discovery` while the bundled count is unchanged. Safe mode also
sets `CLAUDE_CODE_SAFE_MODE=1` and the binary's safe-mode predicate is
`id(){return $n(process.env.CLAUDE_CODE_SAFE_MODE)||nfs("--safe-mode")}` (Tier 0) — it gates
customization discovery, not the in-binary registry.

**Consequence:** `--safe-mode` is a good baseline for "what do MY customizations cost" and a
**wrong** baseline for "what does Claude Code cost before I add anything", because the bundled
payload is still fully present.

### `CLAUDE_CONFIG_DIR`

> "Override the configuration directory (default: `~/.claude`). All settings, session history, and
> plugins are stored under this path, as are credentials on Linux and Windows; on macOS,
> credentials are in the system Keychain. Useful for running multiple accounts side by side"
> — <https://code.claude.com/docs/en/env-vars.md>, fetched 2026-08-17

Pointing it at an empty directory produced `user=<that dir>/skills` in the debug log and zeroed
skill-dir and plugin skills — **and left all 42 bundled skills loaded**. Bundled skills ship inside
the binary (the loader has a `getBundledSkillExtractDir` / `skill_bundled_extract` path that
materialises files on demand), so no config-directory relocation can reach them.

Note one thing a clean `CLAUDE_CONFIG_DIR` does **not** isolate: `managed=/etc/claude-code/.claude/skills`
stayed in the search path in both runs. A true clean room has to account for the managed/policy
path too, and policy settings survive `--safe-mode` by design ("Admin-managed (policy) settings
still apply" — `claude --help`, v2.1.232).

### Correct clean-room recipe

To measure the *irreducible* startup payload, combine them — isolation for customizations, the kill
switch for bundled skills:

```bash
CLAUDE_CONFIG_DIR=$(mktemp -d) CLAUDE_CODE_DISABLE_BUNDLED_SKILLS=1 \
  claude --debug-file /tmp/floor.log -p "hi"
```

That is the only configuration observed to drive bundled skills to their floor of 1 (`/doctor`).
Even then `/doctor` remains; add `DISABLE_DOCTOR_COMMAND=1` to reach zero.

## A trap: "loaded" and "listed" are different numbers

The kill switch dropped the **loaded** bundled count 42 → 1, but the **listing** only shrank by
**14 skills / 5,739 chars**. Both are correct: of 42 loaded bundled skills, only ~14 were listed to
the model in this environment — the rest are availability-gated or hidden
(`user-invocable-only` / `disable-model-invocation`) and were never costing context.

**So the real context saving from disabling bundled skills here is ~5,700 characters, not 42
skills' worth.** A trimming tool that reports the loaded count will overstate the win by roughly
3×. Measure the `Skill listing over budget` line — or `/context`'s Skills row — never `getSkills`.

Similarly, `skillOverrides` did **not** change the loaded count (still 42) because it is a
visibility filter applied downstream of loading. It changed the listing: 173 → 172 skills and
116,003 → 114,415 chars. That is the stage that costs tokens.
