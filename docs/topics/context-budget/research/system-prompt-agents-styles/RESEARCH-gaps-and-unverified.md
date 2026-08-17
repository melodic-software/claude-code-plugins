---
topic: system-prompt-agents-styles
section: gaps-and-unverified
abstract: The fetch log, the recency verdict, and every claim this run could not raise to HIGH — including the unreachable 80% blog post and the unrecovered git commit count.
claims:
  - claim: "The claude.com blog post carrying the 80% statement was unreachable after the full escalation ladder, so the figure itself rests on Tier-2 synthesis; the underlying change is independently sourced first-party from the changelog."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "Tier 0: curl 403 with and without browser UA, and WebFetch EGRESS_BLOCKED for claude.com, 2026-08-17"
        tier: 0
        pool: "local tool output"
      - url: "https://code.claude.com/docs/en/changelog"
        tier: 1
        pool: "Anthropic changelog (generated from anthropics/claude-code CHANGELOG.md)"
  - claim: "Claims are current as of Claude Code v2.1.233 (August 14, 2026), the latest release; the probed binary was v2.1.232 and nothing in 2.1.233 touches system prompt, agent, or output-style behavior."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "https://code.claude.com/docs/en/changelog"
        tier: 1
        pool: "Anthropic changelog (generated from anthropics/claude-code CHANGELOG.md)"
      - url: "Tier 0: `claude --version` → 2.1.232 (Claude Code), 2026-08-17"
        tier: 0
        pool: "local tool output"
produced_by: phase-4
---

# Gaps, unverified claims, and the fetch log

## Recency verdict

- **Latest upstream release: v2.1.233, August 14, 2026** (changelog fetched 2026-08-17).
- **Probed binary: v2.1.232** (`claude --version`, Tier 0) — one patch behind, three days old.
- Every 2.1.233 entry was read. None touches the system prompt, output styles, or agent loading.
- **Verdict: `current`.** No major version bump since any cited doc.
- `github.com/anthropics/claude-code` releases API returned HTTP 403 to unauthenticated `curl`; the
  first-party changelog page, which that repo's `CHANGELOG.md` generates, was used instead and is
  the same artifact one rung up.

## Gaps — claims NOT raised to HIGH

**G1. The "80%+" figure itself — Tier 2 only.**
`https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models`
could not be retrieved. Escalation walked in full: direct `curl` → **HTTP 403**; `curl` with a
browser User-Agent and Accept header → **HTTP 403**; WebFetch → **EGRESS_BLOCKED** (`claude.com` is
blocked by this session's egress proxy). No headless-browser reader or managed scraping tool is
connected. The final rung — a synthesis tool domain-filtered to `claude.com` — returned text
attributed to the post ("removed over 80% of Claude Code's system prompt for more advanced models …
with no measurable loss on their coding evaluations"), but **that is synthesis over a page this run
never read.**
*Sources checked:* claude.com direct (two fetchers), WebFetch, domain-filtered search,
`platform.claude.com/.../prompting-claude-opus-5`, `code.claude.com` full doc corpus grep for "80%".
*Sources left unchecked:* an archive mirror, the post's PDF/print variant if one exists, Anthropic
social accounts, any Anthropic engineering talk.
**Mitigation:** the substantive claim does not depend on the figure. The changelog entry at v2.1.154
("The lean system prompt is now the default for all models except Haiku, Sonnet, and Opus 4.7 and
earlier") is first-party, was fetched this turn, and is corroborated by the `env-vars` entry and by
direct measurement. The *number* 80% is reported as Tier 2 and should be attributed, not asserted.

**G2. The recent-commit count `N` in `git log --oneline -n <N>` — unverified.**
Recovered the argv shape from the shipped binary but `N` is a compiled integer constant, not a
string, so `strings` could not reach it. **That the count is fixed rather than repo-dependent is
HIGH; the specific value is unverified.** A skill should not print a number here.
*Checked:* binary strings around the git-command region, `settings`, `context-window`, `sub-agents`,
changelog. *Unchecked:* a disassembler pass, and an in-repo empirical count (would require reading
the assembled prompt, which no supported surface exposes).

**G3. Which surface uses the second `# Environment` template — unverified.**
The binary carries two environment-block templates: the `<env>` form (matches interactive sessions)
and a `# Environment` / "You have been invoked in the following environment:" form carrying
`Primary working directory`, a git-worktree warning, and availability/fast-mode sentences. Which one
serves subagents vs. the Agent SDK vs. cloud sessions was not established. Does not affect any
accepted claim.

**G4. `--safe-mode` raises `System tools` 18.1k → 26.2k — unexplained.**
Measured and reproducible in this environment, but no first-party source accounts for it, and it
runs opposite to the intuition that safe mode removes things. Recorded as an observation. **Do not
build advice on this number.**
*Checked:* `cli-reference`, `env-vars`, `prompt-caching`, changelog search for safe-mode entries.
*Unchecked:* a per-tool `/context` diff between the two runs, which would localize it.

**G5. `force-for-plugin` output styles — not measured.**
Documented behavior is Tier 1 and clear. Whether such a style is itemized in `/context`, and the
exact resolution order behind "the first one loaded", could not be measured: no plugin in this
environment sets the flag.

**G6. `--disallowedTools "Agent(<name>)"` — not measured.**
Expected to behave as `permissions.deny` (same rule surface, and `cli-reference` presents them as
equivalents), so expected NOT to unload the payload. Reasoned, not measured.

**G7. Absolute token numbers are environment-specific.**
`Skills` 9.9k and `Custom agents` 1.5k reflect 65 installed plugins on this machine. Deltas are the
portable finding; absolutes are not. `/context` also rounds to 0.1k, so sub-100-token effects are
invisible to this method.

## Conflicts

**C1. The brief's premise vs. the evidence.** The dispatch stated these three contributors have "no
operator lever yet identified" and asked to distinguish "you can change this" from "vendor weight".
All three have documented levers. The brief also framed `CLAUDE_CODE_SIMPLE=1` as undocumented; it
has its own row in the official env-var reference plus a documented CLI equivalent, `--bare`.
Reported rather than quietly corrected, because the skill's framing depends on it.

**C2. Docs say `includeGitInstructions` removes the git status snapshot from *the system prompt*;
measurement showed the saving in the `System tools` row.** Both are true and not in conflict once
separated: the setting removes two things — the commit/PR workflow instructions (which live in the
Bash tool description, hence `System tools`) and the status snapshot (too small for the 0.1k
rounding on this repo). Changelog v2.1.78 records a fix specifically for the setting *"not
suppressing the git status section in the system prompt"*, confirming both halves are in scope.

## Falsification query (mandatory, Phase 2)

**Target hypothesis:** "Custom agents contribute name + description only, so the payload is small
and description length is the lever."
**Attempt:** searched for evidence that full agent definitions load at startup, or that agent
context cost is larger than advertised — query: *Claude Code subagents full agent definition loaded
startup context cost not just description criticism*.
**Result: failed to falsify.** Practitioner sources agree the markdown body becomes the subagent's
own system prompt *at invocation, in its own context window*, and describe the resulting main-session
saving as the mechanism. The Tier-0 arithmetic (122 tokens charged against a 5,139-token file) is
independently decisive.
**A second falsification landed elsewhere and succeeded:** the attempt to confirm that
`permissions.deny: ["Agent(<name>)"]` trims the payload **broke that hypothesis** — the payload did
not move, against a verified control. That negative is carried into the classification.

## Fetch log

| Claim | URL or command | Ladder rung | Tool | Outcome |
|---|---|---|---|---|
| env block contents | `strings`/`dd` on `bin/claude.exe` v2.1.232 | 1 (source as spec) | Bash | carries the claim |
| env block contents | https://code.claude.com/docs/en/context-window | 3 product docs | curl/WebFetch | fetched and searched, corroborates |
| env block contents | https://code.claude.com/docs/en/changelog | 4 changelog | curl | fetched and searched — v2.1.233 (2026-08-14) — current |
| git block contents | `grep -abo`/`dd` on `bin/claude.exe` | 1 | Bash | carries the claim |
| git block bounded (2k trunc.) | `bin/claude.exe` truncation literal | 1 | Bash | carries the claim |
| git commit count `N` | `bin/claude.exe` argv region | 1 | Bash | fetched and searched, does not carry the claim (compiled constant) — **Gap G2** |
| git lever | https://code.claude.com/docs/en/settings (`includeGitInstructions`) | 2 reference | curl | carries the claim |
| git lever | https://code.claude.com/docs/en/changelog (v2.1.69, v2.1.78) | 4 changelog | curl | carries the claim — v2.1.233 — current |
| system-prompt flags | `claude --help` v2.1.232 | 0 direct tool output | Bash | carries the claim |
| system-prompt flags | https://code.claude.com/docs/en/cli-reference | 2 reference | curl | carries the claim |
| system-prompt flags | https://code.claude.com/docs/en/headless | 3 product docs | curl | fetched and searched, corroborates |
| `CLAUDE_CODE_SIMPLE*` | https://code.claude.com/docs/en/env-vars | 2 reference | curl | carries the claim |
| lean-prompt default | https://code.claude.com/docs/en/changelog (v2.1.154) | 4 changelog | curl | carries the claim — v2.1.233 — current |
| 80% figure | https://claude.com/blog/the-new-rules-… | 5 announcement | curl (403), curl+UA (403), WebFetch (egress-blocked) | **unreachable after escalation — Gap G1** |
| 80% figure | domain-filtered search on claude.com | 6 third-party synthesis | WebSearch | carries the claim at Tier 2 only |
| 80% figure | https://platform.claude.com/…/prompting-claude-opus-5 | 2 reference | curl | fetched and searched, does not carry the claim |
| removal shipped & felt | https://github.com/anthropics/claude-code/issues/81331 | 6 third-party | WebFetch | fetched and searched, corroborates |
| agents: name+description | https://code.claude.com/docs/en/sub-agents (`#what-loads-at-startup`) | 3 product docs | curl | carries the claim |
| agents: per-agent cost | `claude -p "/context"` v2.1.232 | 0 direct tool output | Bash | carries the claim |
| agents: deny does not unload | paired `claude --settings … -p "/context"` + control | 0 direct tool output | Bash | carries the claim |
| agents: no per-agent key | https://code.claude.com/docs/en/settings (full table) | 2 reference | curl | fetched and searched, does not carry the claim (absence, enumerated) |
| agents: falsification | *…full agent definition loaded startup…* | 6 third-party | WebSearch | fetched and searched, failed to falsify |
| output style: modifies prompt | https://code.claude.com/docs/en/output-styles | 3 product docs | curl/WebFetch | carries the claim |
| output style: conditional coding block | section-assembly branch in `bin/claude.exe` | 1 source as spec | Bash | carries the claim |
| output style: net negative | three paired `/context` runs | 0 direct tool output | Bash | carries the claim |
| output style: `/output-style` removed | https://code.claude.com/docs/en/changelog + output-styles note | 4 changelog | curl | carries the claim — v2.1.233 — current |
| plugin output styles | https://code.claude.com/docs/en/plugins-reference | 2 reference | curl | carries the claim |
| plugin components not relevance-gated | https://code.claude.com/docs/en/plugin-relevance | 3 product docs | curl | fetched and searched, does not carry the claim (it governs suggestions, not loading) |
| CLAUDE.md is not system prompt | https://code.claude.com/docs/en/memory | 3 product docs | curl | carries the claim |
| corpus enumeration | https://code.claude.com/docs/sitemap.xml | exhaustive surface | curl | carries the claim (187 en pages) |

**Tool diversity:** Bash/`curl` direct fetch, Bash/`strings`+`dd` on the shipped binary, Bash/`claude`
CLI probes, WebFetch, WebSearch, GitHub MCP (`search_issues`), Read/Grep on local files — **7
distinct tool types**, against a broad-topic floor of 5.
