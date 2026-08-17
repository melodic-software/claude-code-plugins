# Empirical measurements — this session, CLI v2.1.232

Method: `claude -p "/context"` differencing. Free (zero API tokens), exit 0, repeatable.
Each row is a full headless run; the `System tools` cell is read from the category table.
Baseline re-measured before the series and identical both times (18.1k), so drift is not a factor.

## Per-tool attribution by bare-name deny

| Run | `System tools` | Delta vs baseline |
|---|---|---|
| baseline | 18.1k | — |
| `--disallowedTools "Workflow"` | 10.2k | **−7.9k** |
| `--disallowedTools "Artifact"` | 13.7k | **−4.4k** |
| `--disallowedTools "Workflow" "Artifact"` | 5.8k | **−12.3k** |
| `--disallowedTools "Bash(rm *)"` | 18.1k | **0** |

**Four results, each load-bearing.**

1. **Bare-name deny removes the schema.** Confirms the tool-definitions run's central claim
   independently, on this machine, at this version.
2. **Scoped deny removes nothing.** `Bash(rm *)` left the bucket byte-identical. Rule *shape* is the
   determining factor, not which setting carries the rule. A scoped rule is a runtime guard whose
   schema still ships and is still billed every turn.
3. **Deltas are additive.** 7.9k + 4.4k = 12.3k, and 18.1k − 12.3k = 5.8k exactly. Per-tool
   attribution by differencing is therefore compositional, not just directional — the skill can
   price a whole basket by measuring members individually.
4. **Two tools are 68% of the entire non-deferred tool pool.** `Workflow` (7.9k) and `Artifact`
   (4.4k) together are 12.3k of 18.1k. Both were named as trim candidates before any measurement.

`System tools (deferred)` held at 17.8k across the Workflow run, as expected — `Workflow` is a
prefix tool, so denying it cannot touch the deferred bucket.

## What this explains about the source material

The course's unexplained drop — `System tools` 17.9k → 3.5k from restoring `settings.json`, a 14.4k
saving it never accounts for — is now substantially explained. `Workflow` + `Artifact` alone are
12.3k of it at this version. The remaining ~2k is plausibly a handful of further bare-name denies.

The source treats this as a settings-file mystery. It is not a mystery; it is two tool schemas.

## What this overturns

The tool-definitions run establishes, and this series is consistent with, the fact that **deferral
does not shrink the request**. `defer_loading` "controls what enters the context window, not what
you send in the request" — the full schema goes out in the `tools` array every turn so the cached
prefix stays stable. So Q13 resolves against the intuition the course builds on: a deferred tool is
**not** free. It is out of the context window but still in the request.

Consequence for the report: the `System tools (deferred)` bucket must be presented as *real,
recurring request weight*, not as "already handled". And the honest lever for it is the same
bare-name deny, not deferral itself.

## The skills listing is budget-capped — disabling skills saves nothing

`skillOverrides` genuinely works: `--settings '{"skillOverrides":{"dataviz":"off",…}}'` removed
`dataviz`, `claude-api` and `code-review` from the listing (3 rows present → 0). Confirms the
bundled-skills run's central claim, and it reaches bundled skills, not just plugin ones.

**But the `Skills` token row did not move — 9.9k in every run**, despite removing ~890 tokens of
descriptions.

| Run | `Skills` | skill rows | rows collapsed to `< 20` |
|---|---|---|---|
| baseline | 9.9k | 185 | 131 |
| 3 skills overridden `off` | 9.9k | 182 | — |
| `--safe-mode` | 1.9k | 14 | 0 |

The mechanism is a **listing budget**. At baseline 131 of 185 skills are already collapsed to
`< 20`; freeing three skills' worth of budget simply lets three collapsed skills expand into it. The
total is pinned at the cap. Under `--safe-mode`, with only 14 bundled skills present, nothing is
collapsed and the row falls to its true uncapped size.

**Consequence, and it contradicts the source material.** Disabling individual skills yields **zero**
token saving while the listing is over budget — you change *which* skills get full descriptions, not
what you pay. A saving appears only once the surviving set drops below the cap. The course's "rename
your skills directory" works because it removes *everything at once*, not because per-skill trimming
pays. Any wizard that offers "disable this skill to save N tokens" while over budget is giving false
advice, and this is the clearest instance of the report's required third category: **the lever works,
the saving is zero.**

This also corroborates the bundled-skills run from the other direction: bundled skills are protected
from truncation while user/plugin skills collapse first, so they are a floor the budget never
reclaims.

## Disabling 45 of 65 plugins saved zero skill-listing tokens — but agents scale

Settings override setting 45 plugins to `false`, nothing else changed:

| Run | `Skills` | `Custom agents` |
|---|---|---|
| baseline (65 plugins) | 9.9k | 1.5k |
| 45 plugins disabled | **10k** (unchanged, still 1.0%) | **861** |

**The skills listing is hard-capped and the cap is absolute.** Removing 69% of the plugins moved the
row by nothing — the surviving 20 plugins' skills simply expanded into the freed budget. This is the
fifth independent confirmation of the budget effect and by far the strongest, because the input was
enormous and the output was zero.

**Custom agents are NOT capped.** The same run cut agents 1.5k → 861, roughly proportional. Agent
definitions are a genuine additive saving; skill listings are not.

So the three operator-facing categories separate cleanly, and the skill's report must keep them
apart:

| Surface | Capped? | Does disabling save tokens? |
|---|---|---|
| Tool schemas (`System tools`) | no | **yes** — large and additive (bare-name deny) |
| Custom agents | no | **yes** — proportional |
| Skill listing | **yes (~1%)** | **no** — while over the cap |

The conventional advice "disable unused plugins to reclaim context" is therefore **false for the
skills listing** in any configuration over the cap. What it actually buys is **routing accuracy** —
fewer candidates competing for selection — which is a real benefit and should be presented as the
honest reason, rather than a token saving that does not occur.

## `--safe-mode` is not a clean-room baseline — it makes the prefix worse

| Run | System prompt | System tools | System tools (deferred) |
|---|---|---|---|
| baseline | 5.1k | 18.1k | 17.8k |
| `--safe-mode` | 5.1k | **26.2k** | **row absent** |

**CORRECTED.** The first reading of this table — "safe mode loads previously-deferred tools into the
prefix" — was wrong, and the `/context`-contract run supplied the reason: **`System tools` has listed
skill-frontmatter tokens *subtracted* from it.** So removing skills makes `System tools` go *up*
without any tool changing state. The arithmetic confirms it: safe mode moved `Skills` −8.0k
(9.9k → 1.9k) and `System tools` +8.1k. Those are the same tokens, counted on the other side.

Control run that isolates it: disabling 45 plugins left `Skills` capped (9.9k → 10k) and
`System tools` **byte-identical at 18.1k** — no skill tokens freed, so no artifact. Safe mode
differs only because it actually drops the listing below the cap.

**Therefore `System tools` is not independently meaningful across configurations that change the
skill listing.** Only compare it between runs whose skill listing is identical. Every per-tool
deny measurement above satisfies that (denying a tool changes no skills), so those numbers stand.

Safe mode is still not a clean room — the bundled-skills run measured 42 bundled skills still
loaded while user and plugin skills go to zero, and a clean `CLAUDE_CONFIG_DIR` does not unload
them either. But the deferred-row absence is unremarkable (rows are gated `tokens > 0`), not
evidence of a loading-regime change.

**This falsifies a claim this marketplace already relies on.** `docs/topics/context-engineering-claude-5/design/checks-and-sweep.md:291`
adopts `claude --safe-mode` and `CLAUDE_CONFIG_DIR` as the clean-room comparison route. Neither
gives a clean room: safe mode changes the tool-loading regime rather than neutralising it, and a
clean `CLAUDE_CONFIG_DIR` does not unload bundled skills either. That line needs correcting
independently of this skill.

## Method notes for the skill

- `claude -p "/context"` is verified working and free at 2.1.232, but is **undocumented** on the
  headless page's list of `-p`-capable built-in commands. Treat as load-bearing-but-unsanctioned:
  the skill must degrade gracefully if it stops working, and must say so rather than assume.
- Each run costs ~30-60s wall clock. A full per-tool sweep over ~70 tools is one run per tool and is
  too slow for an interactive wizard — the skill should measure a curated candidate set, or offer
  the sweep as an explicit long-running action.
- `alwaysLoad` and `ENABLE_TOOL_SEARCH` exist but are **not** settings.json keys, so a wizard that
  emits persistent config cannot reach them that way.
- Two upstream issues that appear to contradict the deny-removes-schema finding actually concern
  `disabledTools`, a key Anthropic never documented. Do not cite them as counter-evidence.
