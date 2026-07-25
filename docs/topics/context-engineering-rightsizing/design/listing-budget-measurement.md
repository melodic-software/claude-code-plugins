# Skill-listing budget measurement for issue #1271

Measurement of this repository's skill listing against Claude Code **v2.1.219**, produced for
[#1271](https://github.com/melodic-software/claude-code-plugins/issues/1271).

Two passes stand behind it: an original read-only measurement that recovered the listing algorithm
from the shipped CLI rather than inferring it, and an independent re-verification that re-ran every
load-bearing count against the tree before this file was committed. §9 records what reproduced,
what was corrected, and what is carried without independent reproduction.

**Baseline for every figure below:** commit `39880e3bb7`, 130 model-invocable skills.

---

## 1. Harness behavior, verified

### 1.1 What the documentation says

From <https://code.claude.com/docs/en/skills.md> (§ *Skill descriptions are cut short*):

> Claude Code loads a listing of skill names and descriptions into context so Claude knows what's
> available. The listing always contains every skill name, but if you have many skills, Claude Code
> shortens descriptions to fit the listing's character budget, which can strip the keywords Claude
> needs to match your request. The budget scales at 1% of the model's context window. When the
> listing overflows, Claude Code drops descriptions starting with the skills you invoke least, so
> the skills you use most keep their full text.

Frontmatter reference, same page:

> `description` … Put the key use case first: the combined `description` and `when_to_use` text is
> truncated at 1,536 characters in the skill listing to reduce context usage.
>
> `when_to_use` … Additional context for when Claude should invoke the skill, such as trigger
> phrases or example requests. **Appended to `description` in the skill listing** and counts toward
> the 1,536-character cap.

Invocation-control table, same page:

> `disable-model-invocation: true` … Description **not in context**, full skill loads when you
> invoke.

From <https://code.claude.com/docs/en/settings.md>:

> `skillListingBudgetFraction` — **Default**: `0.01`. Fraction of the model's context window
> reserved for the skill listing Claude sees each turn, so the default reserves 1%. When the listing
> exceeds the budget, descriptions for the least-used skills are dropped and only their names are
> listed, so Claude can still invoke them but can't see what they do.
>
> `skillListingMaxDescChars` — **Default**: `1536`. Per-skill character cap on the combined
> `description` and `when_to_use` text in the skill listing Claude sees each turn. Text longer than
> this is truncated.
>
> `skillOverrides` — … **Does not apply to plugin skills**, which are managed through `/plugin`.

Every passage above was re-fetched from the live pages and matched character-for-character during
re-verification.

> **Third-party divergence, recorded.** The community-maintained SchemaStore schema
> (`json.schemastore.org/claude-code-settings.json`) gives `skillListingMaxDescChars` a default of
> `8000` and describes it as "Maximum characters in skill description text shown to Claude". Both
> the official documentation and the shipped binary say **1536**. SchemaStore is not authoritative
> here; it is noted so a reader who consults it is not misled.

### 1.2 What the installed binary actually does

The doc leaves "1% of the context window" ambiguous between tokens and characters, and says
descriptions are "shortened". Both were resolved against the shipped implementation. Reproduce by
grepping the installed `claude` binary for the constant block
`totalChars:p,rawTotalChars:c,budget:i,budgetFromEnv:s,bytesPerToken:o}}`.

Constants: fraction `0.01`, bytes-per-token `4`, fallback context window `200000`, per-entry cap
`1536`.

```js
// budget, in CHARACTERS
budget(ctxTokens, bytesPerToken = 4) {
  if (process.env.SLASH_COMMAND_TOOL_CHAR_BUDGET) return that;
  return Math.floor((ctxTokens ?? 200000) * bytesPerToken * fraction);   // 0.01 default
}

// the text a listing entry carries
entryText(e) { return e.whenToUse ? `${e.description} - ${e.whenToUse}` : e.description }

// rendered entry
`- ${name}: ${entryText(cmd).slice(0, 1536)}`   // kept
`- ${name}`                                      // dropped or name-only
```

Seven facts follow, and three of them change how this issue should be scoped:

1. **The budget is characters, and it is `contextTokens × 4 × 0.01`.** The binary's own schema text
   says "Fraction of the context window **(in characters)**" — a phrasing the published settings
   documentation does not carry. That is **8,000 characters** at a 200k context window and
   **40,000** at 1M. No override is in force: `skillListingBudgetFraction`,
   `skillListingMaxDescChars`, `skillOverrides`, and `SLASH_COMMAND_TOOL_CHAR_BUDGET` were all
   checked across user settings, project settings, and the environment, and none is set.

2. **`when_to_use` is appended with a literal `" - "` separator.** Moving a trigger block out of
   `description` into `when_to_use` therefore **costs +3 characters**. The split is a
   maintainability and authoring-discipline change, not a saving — the issue already says this, and
   the implementation confirms it exactly.

3. **Overflow is all-or-nothing per skill, not "shortening".** The doc's wording is loose. Each
   entry either carries its full (1,536-capped) text or collapses to `- name`. There is no partial
   truncation to fit.

4. **Per-entry accounting** is `len(listedName) + 4 + min(len(entryText), 1536)`, name-only is
   `len(listedName) + 2`, and the whole listing adds `n - 1` separators. The `+4` is the rendered
   `-` bullet and `:` separator with their trailing spaces; the `+2` is the bullet alone. Listed
   names are the prefixed form (`re-anchor:do-your-research`), not the bare frontmatter `name`.

5. **There is a floor.** In the overflow path every entry still costs `len(name) + 2` even when its
   description is dropped, and bundled prompt skills keep their *full* entry length inside that
   floor. Headroom for descriptions is `budget − floor`, not `budget`.

6. **Priority is local, decayed usage** — a skill's priority is
   `usageCount × max(0.5^(daysSinceLastUse / 7), 0.1)`, and `0` for a skill never used. A skill with
   no usage history is dropped **first**. This is per-machine state, so *which* descriptions survive
   differs between machines and between users of the same plugin. A newly published skill is
   invisible-by-description on every machine until someone invokes it — which is hard to do if they
   cannot see what it does.

7. **The drop loop does not break on first failure.** It walks the droppable set in descending
   priority and skips any entry whose description does not fit, continuing to consider cheaper
   entries. So a small low-priority description can survive while a large higher-priority one is
   dropped.

Two population rules: skills with `disable-model-invocation` are filtered out of the listing
entirely, confirming the docs; and the population is **builtin commands + skills + MCP prompt
commands, deduped by name** — not plugin skills alone.

---

## 2. Reconciling the measurements

Neither headline figure is the listing denominator. They measure different populations, and both are
raw subtotals of a quantity the harness calls `rawTotalChars` — distinct from the `totalChars` the
model actually receives.

| Figure | Population | Verified here |
|---|---|---|
| Issue #1271: **80,026** chars / **135** skills | `description` only, model-invocable only, repo tree | **79,653** chars / **130** skills |
| Effort handoff: **111,784** chars / **195** skills | `name` + `description`, *all* invocability, installed+enabled plugins across *all* marketplaces | **111,578** chars / **192** entries |

**The file-count step.** A naive `find plugins -name SKILL.md` returns **188**, but **7** of those
are nested inside a skill directory rather than being skills themselves — six `vendor/`
materializations and one `references/` fixture:

- `plugins/context7/skills/lookup/vendor/cli/SKILL.md`
- `plugins/context7/skills/lookup/vendor/find-docs/SKILL.md`
- `plugins/dometrain/skills/sync/vendor/SKILL.md`
- `plugins/playbooks/skills/boris/vendor/SKILL.md`
- `plugins/playbooks/skills/skill-authoring/vendor/SKILL.md`
- `plugins/playwright/skills/playwright/vendor/SKILL.md`
- `plugins/plugin-quality/skills/audit/references/component-types/SKILL.md`

Discovery is `plugins/<plugin>/skills/<name>/SKILL.md`, so those are not skills. **181 skills** in
the repo: **130 model-invocable**, **51 `disable-model-invocation`**.

The issue's 135 / 80,026 is 5 skills and 373 characters above today's tree — ordinary drift since
filing, and the issue explicitly calls its figures point-in-time.

**The 181 → 192 step.** Decomposed against `enabledPlugins` and the installed-plugin cache, and each
term re-verified:

| Source | Skills |
|---|---:|
| melodic-software plugins in the repo | 181 |
| less `miro` (`enabledPlugins` sets it `false`) | −1 |
| `caveman@caveman` | +7 |
| `codex@openai-codex` | +3 |
| `claude-security@claude-plugins-official` | +1 |
| `security-guidance@claude-plugins-official` (no `skills/` directory) | +0 |
| personal skill under the user skills directory | +1 |
| **resolved total** | **192** |

The residual against the handoff's 195 — 3 entries, 206 characters, 0.2% — is not attributable from
the files on disk. `dometrain@inline` is enabled but has no installed-plugin cache entry, and
bundled/builtin commands are in the listing but not in any plugin cache. The installed
melodic-software cache is byte-identical in this respect to the working tree, so cache-vs-tree drift
is *not* a contributor.

**The right denominator.** For what the model receives:

```text
totalChars = Σ over included entries [ len(pluginName:skillName) + 4 + min(len(desc + " - " + wtu), 1536) ]
           + (n − 1)
```

over the *included* population — non-DMI skills, builtin commands, and MCP prompts, deduped by name.

For a PR against this repo the actionable denominator is the melodic model-invocable subset:
**130 skills**, whose entry costs sum to **83,270 characters**; adding the `n − 1` inter-entry
separators the formula specifies gives **83,399**. Both numbers appear below on their stated basis —
the per-plugin table in §4 sums entry costs only, so its total is 83,270. `name`+`description`
alone is 82,533.

**No entry in this repo is near the 1,536 cap.** Longest is `docs-hygiene:audit-derivability` at
1,161; the median entry text is 600 characters; count at or over 1,536 is **zero**. Every raw
character saved here is a real listing character saved — the cap is not currently binding, and does
not distort any figure below.

---

## 3. What the model was actually receiving

The observation session ran on a 1M-context model, so the budget was **40,000 characters** — the
most generous configuration the defaults produce. The live skill listing in that session's system
prompt was recorded and diffed against the 130-skill inventory.

**Provenance — this is the one figure not produced by a command.** The listing lives in the system
prompt, which no script can read, so the set of skills carrying a description was transcribed by
hand and then diffed against the measured 130-skill inventory. The diff catches any name that does
not exist, and the per-plugin counts reconcile exactly against all 130; it cannot catch a skill that
*did* carry a description and was omitted from the transcription. Any such error inflates the drop
count, so **73% is an upper bound on the drop and the true figure is at or below it.** The budget
arithmetic below is an independent consistency check, not a proof of the transcription.

- **35 of 130** melodic model-invocable skills kept their description.
- **95 of 130 (73%) were name-only.**
- **59,824 characters of description were being withheld from the model in that session.**

Consistency check on the model of the algorithm: melodic's name-only floor is 3,140, the granted
descriptions add 20,306, for 23,446 of the 40,000 budget — leaving 16,554 for caveman, codex,
claude-security, the bundled skills (several of which, like `dataviz` and `claude-api`, carry
1,000-character descriptions and are *protected from dropping*), the builtin commands, and
separators. That is the right order of magnitude, so the reimplementation is behaving as the binary
does.

Whole plugins were dark. All 9 `songwriting` skills, all 6 `docs-hygiene`, all 4 `claude-config`,
all 4 `claude-ops`, all 4 `testing`, all 3 `code-tidying`, all 3 `knowledge`, both `github`, both
`prototype`, both `education`, both `event-storming`, both `verification`, both `toolchain`, both
`claude-memory`, both `adhd` — name-only. `session-flow` kept 2 of 11.

**On a 200k-context model the budget is 8,000 characters and the melodic name-only floor alone is
3,140** — before builtin and bundled entries, which are protected and take their full length out of
the same 8,000. Essentially every melodic description is dropped there. This is the mechanism behind
the issue's originating symptom: a capability that appeared not to exist.

Which descriptions survive is **per-machine usage state**, not a property of the repo. Another
machine sees a different 35.

---

## 4. Per-plugin table

Model-invocable skills only — the listing population. `name` is the listed form (`plugin:skill`).
The "kept description" columns are the observation session's listing at a 40,000-character budget;
they are per-machine usage state. The `listing entry cost` column sums entry costs only; see §2 for
the separator-inclusive figure.

| plugin | model-invocable skills | `name`+`description` chars | share | listing entry cost | kept description | dropped to name-only | uses `when_to_use` |
|---|---:|---:|---:|---:|---:|---:|---:|
| `re-anchor` | 15 | 9,895 | 12.0% | 9,955 | 11 | 4 | 0 |
| `session-flow` | 11 | 7,405 | 9.0% | 7,449 | 2 | 9 | 0 |
| `planning` | 10 | 6,713 | 8.1% | 6,753 | 5 | 5 | 0 |
| `work-items` | 7 | 5,681 | 6.9% | 5,709 | 3 | 4 | 0 |
| `songwriting` | 9 | 5,501 | 6.7% | 5,537 | 0 | 9 | 0 |
| `docs-hygiene` | 6 | 4,218 | 5.1% | 4,242 | 0 | 6 | 0 |
| `source-control` | 6 | 3,403 | 4.1% | 3,427 | 4 | 2 | 0 |
| `claude-config` | 4 | 2,334 | 2.8% | 2,350 | 0 | 4 | 0 |
| `knowledge` | 3 | 2,133 | 2.6% | 2,145 | 0 | 3 | 0 |
| `adhd` | 2 | 2,040 | 2.5% | 2,048 | 0 | 2 | 0 |
| `code-tidying` | 3 | 1,992 | 2.4% | 2,004 | 0 | 3 | 0 |
| `discovery` | 5 | 1,982 | 2.4% | 2,002 | 3 | 2 | 0 |
| `education` | 2 | 1,802 | 2.2% | 1,810 | 0 | 2 | 0 |
| `claude-ops` | 4 | 1,794 | 2.2% | 1,810 | 0 | 4 | 0 |
| `testing` | 4 | 1,530 | 1.9% | 1,546 | 0 | 4 | 0 |
| `playbooks` | 3 | 1,486 | 1.8% | 1,586 | 1 | 2 | 1 |
| `github` | 2 | 1,421 | 1.7% | 1,429 | 0 | 2 | 0 |
| `prototype` | 2 | 1,397 | 1.7% | 1,405 | 0 | 2 | 0 |
| `event-storming` | 2 | 1,286 | 1.6% | 1,294 | 0 | 2 | 0 |
| `verification` | 2 | 1,078 | 1.3% | 1,086 | 0 | 2 | 0 |
| `architecture` | 1 | 1,077 | 1.3% | 1,081 | 0 | 1 | 0 |
| `claude-memory` | 2 | 1,068 | 1.3% | 1,076 | 0 | 2 | 0 |
| `kindle-dedrm` | 1 | 999 | 1.2% | 1,003 | 0 | 1 | 0 |
| `visualization` | 1 | 971 | 1.2% | 975 | 0 | 1 | 0 |
| `plugin-quality` | 1 | 902 | 1.1% | 906 | 0 | 1 | 0 |
| `implementation` | 2 | 866 | 1.0% | 874 | 1 | 1 | 0 |
| `repo-hygiene` | 1 | 856 | 1.0% | 860 | 0 | 1 | 0 |
| `review` | 2 | 854 | 1.0% | 862 | 1 | 1 | 0 |
| `toolchain` | 2 | 830 | 1.0% | 838 | 0 | 2 | 0 |
| `debugging` | 1 | 820 | 1.0% | 824 | 0 | 1 | 0 |
| `bug-report` | 1 | 753 | 0.9% | 757 | 0 | 1 | 0 |
| `skill-quality` | 1 | 744 | 0.9% | 748 | 1 | 0 | 0 |
| `naming` | 1 | 664 | 0.8% | 668 | 1 | 0 | 0 |
| `firecrawl` | 1 | 662 | 0.8% | 666 | 1 | 0 | 0 |
| `tdd` | 1 | 627 | 0.8% | 631 | 0 | 1 | 0 |
| `domain-driven-design` | 1 | 623 | 0.8% | 627 | 0 | 1 | 0 |
| `mcp-tools` | 1 | 618 | 0.7% | 622 | 0 | 1 | 0 |
| `machine-health` | 1 | 606 | 0.7% | 610 | 0 | 1 | 0 |
| `repo-fleet-hygiene` | 1 | 592 | 0.7% | 596 | 0 | 1 | 0 |
| `codebase-health` | 1 | 583 | 0.7% | 587 | 0 | 1 | 0 |
| `playwright` | 1 | 530 | 0.6% | 663 | 1 | 0 | 1 |
| `context7` | 1 | 469 | 0.6% | 473 | 0 | 1 | 0 |
| `dometrain` | 1 | 398 | 0.5% | 402 | 0 | 1 | 0 |
| `ai-briefing` | 1 | 330 | 0.4% | 334 | 0 | 1 | 0 |
| **total** | **130** | **82,533** | **100%** | **83,270** | **35** | **95** | **2** |

For completeness, all 181 skills including the 51 DMI ones total **108,460** `name`+`description`
characters and **109,581** listing cost including separators — but DMI skills never enter the
listing, so that figure is context only. `re-anchor` leads on both bases; the 1,536 cap and the name
component do not reorder the top of the table.

`when_to_use` is used by **2 of 130** model-invocable skills — `playbooks:boris` and
`playwright:playwright` — carrying 211 characters between them, exactly as the issue reports.

---

## 5. The reduction available without losing discovery

Three spans were extracted per description: the leading fragment that reproduces the plugin or skill
name; the trigger block from the first `Use when` / `Use for` / `Triggers on` marker; and the
trailing exclusion clause from the first `Not for` / `NOT for` / `Skip when` marker. Exclusion
clauses are classified **sibling-routing** when they name another capability (a slash token, a
`plugin:skill` token, "sibling", "that is the … skill", "routes to", "owns that") and **pure**
otherwise.

| source | chars | skills | share of 79,653 desc chars | is it available? |
|---|---:|---:|---:|---|
| Name-restating opener | 236 | 28 | 0.3% | **yes** |
| Pure exclusion clauses (no sibling named) | 1,670 | 11 | 2.1% | **mostly not** — see §7 |
| Sibling-routing exclusion clauses | 2,639 | 16 | 3.3% | **no** — load-bearing |
| Trigger blocks (`Use when: …`) | 38,509 | 125 | 48.3% | **no** — relocation, **+3 chars each** |

> **Span-extraction is heuristic.** These four rows depend on the exact span-detection rules above.
> An independently written detector over the same tree produced 169 / 42,224 / 2,222 / 1,820 — the
> individual spans move by up to 10%, the ordering and the conclusion do not. Treat the row values
> as approximate and the **totals and shares** as the load-bearing result: both detectors put the
> two genuinely-available sources at **2.4–2.5%** of description mass.

### The finding that matters

**The three named sources yield almost nothing.** Name-restating openers plus pure exclusions total
**1,906 characters — 2.4%** of description mass (independent detector: 1,989 — 2.5%), and once the
exclusion clauses carrying output or scope contracts are set aside (§7), what is genuinely available
is **807 characters — 1.0%**. The trigger blocks are roughly half the mass but are the discovery
surface itself, and relocating them to `when_to_use` *adds* 3 characters per skill.

Concretely: **zeroing every character the three named sources can offer still leaves the listing
above 81,000 characters** (both detectors agree; the independent one lands at 81,410), against a
40,000 budget at 1M context and 8,000 at 200k. The 73% drop rate observed in §3 would not move.

Name restatement is also narrower than the issue implies. The detector finds 236 characters across
28 skills, and 120 of those are `re-anchor`'s twelve `"Re-anchor "` prefixes. Outside `re-anchor`
the pattern is a bare imperative verb that happens to match the skill name
(`docs-hygiene:compress` → "Compress …", `debugging:debug` → "Debug …"), 6–13 characters each, where
the verb is doing real semantic work. The issue's cited example — `do-your-research` opening
"Re-anchor research and…" — is real, but it is one plugin's house style, not a fleet-wide tax.

### Where the mass actually is, and what it means

The characters outside trigger blocks are the "what it does" prose, roughly 316 characters per
skill. That is the only large compressible pool, and compressing it is exactly the tradeoff the
issue rules out for trigger keywords: prose carries matchable vocabulary too. §6 shows what a
careful, keyword-preserving pass actually recovers: **9.2%** on the worst plugin.

A structural redundancy worth naming: within `re-anchor`, fifteen descriptions each re-state the
same corrector shape ("restores discipline X, then audits the work in flight and corrects"),
~100–200 characters apiece. There is no plugin-level description field in the listing — the entry
text reads only `description` and `when_to_use` — so this cannot be factored out at the metadata
layer. It is a cost of one-skill-per-discipline decomposition, not an authoring defect.

---

## 6. Worked before/after — `re-anchor`

`re-anchor` is the worst plugin on every basis: 15 model-invocable skills, 9,895 `name`+`description`
characters, **12.0%** of the model-invocable listing, 9,955 characters of listing entry cost.

**This is a proposal, not an applied edit. No skill file was modified.**

**Blocked by an in-flight rename.** PR
[#1276](https://github.com/melodic-software/claude-code-plugins/pull/1276) renames the `re-anchor`
plugin to `discipline` across 45 files and is open and unmerged. Names below are pre-rename. When
the rename lands, every listed name gains one character (`re-anchor:` → `discipline:`, +1 × 15 =
+15) and the `sweep-all-disciplines` and `do-your-research` texts that say "re-anchor" need review
as trigger phrases. **Apply this to the renamed paths, not to `plugins/re-anchor/`.** Issue #1271
names the same blocker.

Method, applied to all 15 model-invocable skills (`setup` is DMI and never enters the listing, so it
is untouched):

- `description` states what the skill does. No `Use when:` block, no name-restating opener.
- `when_to_use` carries every trigger phrase verbatim, plus sibling routing.
- Prose tightened without dropping matchable vocabulary.

| skill | before | after | delta |
|---|---:|---:|---:|
| `do-your-research` | 584 | 543 | −41 |
| `do-your-research-deep` | 829 | 745 | −84 |
| `follow-our-standards` | 428 | 441 | **+13** |
| `mind-your-maxims` | 586 | 545 | −41 |
| `pick-for-the-problem` | 639 | 632 | −7 |
| `point-dont-copy` | 470 | 463 | −7 |
| `reason-dont-recite` | 530 | 523 | −7 |
| `recheck-against-upstream` | 592 | 586 | −6 |
| `recheck-against-upstream-deep` | 648 | 606 | −42 |
| `reuse-or-replace` | 1,052 | 749 | −303 |
| `script-the-deterministic-work` | 1,097 | 972 | −125 |
| `scrutinize-dont-coast` | 560 | 552 | −8 |
| `sweep-all-disciplines` | 770 | 638 | −132 |
| `tighten-your-output` | 473 | 466 | −7 |
| `use-your-skills` | 697 | 574 | −123 |
| **total (listing entry cost)** | **9,955** | **9,035** | **−920 (−9.2%)** |

`follow-our-standards` goes **up** by 13 characters. That is the `" - "` joiner plus a slightly
clearer opener, and it is the honest shape of this change on a short description: the structural
split costs characters, and only prose compression pays them back.

Extrapolated at the same rate, a fleet-wide pass would recover roughly 7,700 characters of the
83,270 — the listing would still be ~75,600 against a 40,000 budget. **Treat 9.2% as an upper bound,
not a central rate.** `re-anchor` is the most compressible plugin in the tree: it owns 120 of the
236 name-restating characters fleet-wide, and its fifteen descriptions repeat one corrector frame
that no other plugin repeats. Plugins without that redundancy will recover less, so the true
fleet-wide figure is below 7,700.

### Gate results against the proposal

The proposed frontmatter was run through the repository's own gate rather than a reimplementation
(§8 has the detail):

- **Trigger-phrase preservation** — `plugins/skill-quality/scripts/skill-frontmatter.sh:102`'s
  `extract_triggers`, applied to before/after pairs for all 15 skills: **122 of 122 base-ref trigger
  phrases preserved, 0 lost.**
- **Per-skill 1,536 cap** — 15 of 15 pass; largest after-entry is 972.
- **`Use when:` phrasing (check 12)** — 15 of 15 **WARN**. See §8; this is the one place the
  proposal collides with the incumbent gate.

### Rewritten frontmatter

Only `description` and `when_to_use` are shown; every other frontmatter field is unchanged.
`displayName` is untouched, per the issue's scope. Paths are pre-rename — see the blocker above.

```yaml
# plugins/re-anchor/skills/do-your-research/SKILL.md
description: Restores research and no-assumptions discipline mid-session, then self-audits and corrects the work in flight.
when_to_use: "'do your research', 'you're guessing', 'cite that', 'stop assuming', 'evidence, not vibes', 'you skipped verification', 'that's training-data recall', 'research this properly', 'fact-check', 'fact check this', 'make sure that's right', or at conversation start to set the posture. For a heavy verification fan-out over a typed inventory of the session's claims, use the sibling do-your-research-deep."

# plugins/re-anchor/skills/do-your-research-deep/SKILL.md
description: Heavy verification fan-out over a typed full inventory of the session's claims — assumptions, asserted facts, concrete specifics (paths, defaults, flags, signatures), load-bearing premises — each verified against a primary source at a configurable depth, reported as a per-item ledger with verdict, source tier, consensus count, and recency.
when_to_use: "'deep research pass', 'verify every claim', 'audit all our claims', 'fact-check everything', 'fact-check all these claims', 'go make sure those are all right', 'we've made a lot of load-bearing claims', or when your own judgement is the suspected bias across many claims. For a single or small inline fact-check ('fact-check that'), use the sibling do-your-research."

# plugins/re-anchor/skills/follow-our-standards/SKILL.md
description: Restores your organization's engineering standards as the working posture, then audits the work in flight against them and corrects violations with doc citations.
when_to_use: "'follow our standards', 'follow the standards', 're-anchor to standards', 'does this match our conventions', 'audit against standards', 'you're drifting from our conventions', or at conversation start on a repo governed by shared conventions."

# plugins/re-anchor/skills/mind-your-maxims/SKILL.md
description: Restores cooperative-communication discipline — Grice's conversational maxims plus the AI-augmented transparency maxim — then audits recent responses and agent-authored artifacts for completeness in both directions, relevance, clarity, and disclosed boundaries.
when_to_use: "'mind your maxims', 'communication quality', 'answer what I asked', 'you buried the answer', 'you didn't answer the question', 'too vague', 'stay on topic', 'is this clear', 'grice', 'maxims', or at conversation start to set the communication posture."

# plugins/re-anchor/skills/pick-for-the-problem/SKILL.md
description: Restores the discipline that a tool, library, framework, language, or approach is chosen to fit the actual problem — not reached for out of habit, availability, incumbency, or preconception — then audits the selection in flight and re-derives it from the problem.
when_to_use: "'pick for the problem', 'right tool for the job', 'which library should we use', 'what framework', 'should we build this or use X', 'is this the right approach', 'you defaulted to X', 'we always reach for X', 'evaluate the options', 'choose a dependency', or at conversation start on a build-vs-buy or technology-selection decision."

# plugins/re-anchor/skills/point-dont-copy/SKILL.md
description: Restores pointer-over-copy discipline, then audits the work in flight for copied content, internal-name coupling, and closed capability lists, and corrects by pointing at the living source.
when_to_use: "'point don't copy', 'you copied that', 'don't duplicate the docs', 'cite instead of paste', 'link don't restate', 'you enumerated the tools', 'that couples to internal names', 'this will drift', or at conversation start on documentation work."

# plugins/re-anchor/skills/reason-dont-recite/SKILL.md
description: Restores the discipline that inherited content is evidence of what is, never self-justifying authority — then audits the work in flight for decisions coasting on precedent and re-derives them from first principles.
when_to_use: "'reason don't recite', 'why is it this way', 'challenge that convention', 'you're deferring to precedent', \"that's just how it's done\", 'question the inherited design', 'stop reciting the docs', 'is this actually right', or at conversation start on legacy or inherited code."

# plugins/re-anchor/skills/recheck-against-upstream/SKILL.md
description: Restores the discipline that existing state — config, code, docs, infra — is not evidence of its own correctness, then audits the surface in flight against CURRENT official upstream docs and classifies each divergence.
when_to_use: "'recheck against upstream', 'check this against the docs', 'is our config still current', 'did upstream change', 'are we still doing this right', 'verify against the official docs', 'this may have drifted from upstream', 'audit our setup against the vendor docs', or at conversation start on config, infra, or integration work."

# plugins/re-anchor/skills/recheck-against-upstream-deep/SKILL.md
description: "Heavy upstream-conformance fan-out: fresh-context subagents doc-by-doc over a whole subsystem, framework, or repo, comparing each surface against its CURRENT official upstream docs, reported as an inline divergence ledger."
when_to_use: "'recheck the whole subsystem against upstream', 'audit every surface against the docs', 'deep upstream conformance pass', 'check the entire framework config against upstream', 'we depend on a lot of upstream surfaces and they may have drifted'. For a single inline recheck of the surface in play, use the sibling recheck-against-upstream."

# plugins/re-anchor/skills/reuse-or-replace/SKILL.md
description: Restores the anti-fragmentation discipline that new work REUSES an established way — code idiom, structure, error handling, naming shape, doc format, process — or openly REPLACES it (migrate the old uses, record the decision). The sin is the SILENT second parallel way, not divergence itself; then audits the work in flight for an invented approach diverging with no stated reason.
when_to_use: "'reuse or replace', 'we already have a way of doing this', 'don't invent a second way', 'keep it one way', 'follow the existing pattern or replace it', 'be consistent', 'you added a parallel way', 'this diverges from how we do it elsewhere', or at conversation start on work that extends an established codebase, structure, or process."

# plugins/re-anchor/skills/script-the-deterministic-work/SKILL.md
description: Restores the discipline that deterministic sub-work — counting, diffing, sorting, transforming, matching, sweeping, arithmetic — gets a script that runs and returns real output, with the model reasoning only afterward over that output. Then audits the work in flight for transforms executed by hand. Fires on drift, mid-flight or retrospective, or as posture on transform-heavy work.
when_to_use: "'script the deterministic work', 'you should have scripted that', 'don't eyeball that', 'you counted that by hand', 'compute that, don't estimate', 'diff it with a tool', 'stop hand-tallying', 'run it instead of guessing', or at conversation start on count-, diff-, or transform-heavy work. Not for authoring a requested script or migration ('script it' as a work order), nor for a first-turn count/diff/transform work order ('diff these files', 'count the routes', 'convert all of these') — doing that task with a tool is just doing the task."

# plugins/re-anchor/skills/scrutinize-dont-coast/SKILL.md
description: Restores adversarial self-scrutiny — stop coasting on your own recent output, re-examine whether it is actually sound (not merely confidently produced) through a fresh-context pass blind to the reasoning that made it, and remediate with the user. Takes an optional focus to scope the re-examination.
when_to_use: "'scrutinize don't coast', 'wait, stop', 'are you sure about this', 'second-guess this', 'poke holes in what you just did', \"you're steamrolling\", 'push back on yourself', or at conversation start to set the posture."

# plugins/re-anchor/skills/sweep-all-disciplines/SKILL.md
description: "Composes the plugin's discipline correctors into ONE batched pass — a router, not a corrector: fans out an audit-only subagent per in-scope corrector, then applies their corrections on the main thread in a fixed order. At conversation start it reports a cheap posture digest instead. For a single discipline, invoke that corrector directly."
when_to_use: "'sweep all disciplines', 'ground ourselves', 're-anchor everything', 'run the whole re-anchor bundle', 'posture batch', 'set our posture before we start', 'batch the correctors', or at conversation start to set posture across every standing discipline at once."

# plugins/re-anchor/skills/tighten-your-output/SKILL.md
description: Restores terseness discipline — say markdown in fewer words without semantic loss, write code in fewer lines when readability holds — then audits the work in flight for avoidable verbosity and tightens it.
when_to_use: "'tighten your output', 'tighten this', 'too verbose', 'say it in fewer words', 'this is bloated', 'trim the code', 'simpler form', 'cut the wordiness', 'be more concise', or at conversation start on prose- or code-heavy work."

# plugins/re-anchor/skills/use-your-skills/SKILL.md
description: Restores the discipline of actually using the skills available to you — scan the in-context listing, map the task to the skills that fit, and invoke them instead of reinventing their procedure. Then audits the work in flight for a skill that should have fired and did not, and routes forward.
when_to_use: "'use your skills', 'you have a skill for that', 'did you check your skills', 'there's a skill for this', 'you reinvented that', 'you skipped the skill', 'invoke your skills', or at conversation start to set the posture that available skills get used."
```

Two deliberate content changes beyond compression: `sweep-all-disciplines` drops "Membership is each
corrector's own tier metadata" (an implementation detail that belongs in the skill body) and
`use-your-skills` drops "naming the relevant skills when delegating to a subagent" (a procedure
step, not a selection signal). Both are body content, not listing content.

---

## 7. Must-not-flag list

Content that reads like bloat and is load-bearing. A future sweep — automated or otherwise — must
leave these alone.

1. **Exclusion clauses that name a sibling.** ~2,600 characters across 16 skills. In a fleet with
   130 model-invocable entries in one repo, negative routing is what stops the wrong skill firing,
   and it is cheaper than the wrong skill loading its whole body. Examples in this tree:
   - `work-items:track` — "Not for new bug reports — use `/bug-report:write` first … Sibling skills
     own the other verbs: `/work-items:work`, `/work-items:triage`, `/work-items:decompose`,
     `/work-items:scan-todos`"
   - `naming:name-it-better` — "Not for an already-decided rename ('rename X to Y', 'I renamed X')
     — that routes to the rename-references sweep"
   - `session-flow:reanchor` — "Not for resuming work (use `/session-flow:keep-going`) …"
   - `prototype:pressure-test` ↔ `prototype:explore-directions` — a mutually-disambiguating pair
     whose two names alone do not distinguish them
   - `planning:design-handoff`, `planning:audit-answers`, `code-tidying:batch-simplify`,
     `knowledge:youtube-digest`, `event-storming:methodology`

2. **Exclusion clauses that disambiguate a sibling in prose rather than by slash path.** These
   classify as sibling-routing above and are the reason that bucket is ~2,600 rather than ~1,200 —
   they are the same load-bearing kind, just written without a `/path`:
   - `github:audit` / `github:advise` — several hundred characters that exist *only* to separate two
     skills in the same plugin whose names are both about GitHub ("that is the advise skill" / "that
     is the audit skill"). Delete either and the pair becomes ambiguous.
   - `docs-hygiene:compress` — names `/compact`, `/audit-noise`, `/extract-ssot`
   - `plugin-quality:audit` — names `skill-quality:check`, `review`, `mcp-tools:audit`
   - `code-tidying:tidy` — names `/simplify` and `batch-simplify`
   - `visualization:visualize` — cedes chart craft to a dataviz capability

   The "pure" bucket that remains is 11 clauses, and most are still load-bearing for a different
   reason: they carry output or scope contracts rather than routing. `bug-report:write` states its
   output mode; `debugging:debug` enumerates its outputs; `architecture:improve` fences module-level
   from diff-level work; `re-anchor:script-the-deterministic-work` separates a corrector from a work
   order, which is the single distinction the skill exists to make. Those four account for about
   two-thirds of the bucket. The genuinely trimmable remainder is **571 characters across 7
   skills** — `adhd:shape`, `claude-config:audit-instructions`,
   `domain-driven-design:curate-language`, `knowledge:book-distill`, `mcp-tools:audit`,
   `planning:devils-advocate`, `skill-quality:check` — or **0.7% of description mass.**

3. **Trigger phrases that restate the skill's own name.** `re-anchor:do-your-research`'s first
   trigger is `'do your research'`; the listed name is `re-anchor:do-your-research`. This looks like
   pure duplication and is measurable — but the listed name is hyphenated and plugin-prefixed while
   the trigger is the spaced natural-language form a user actually types. Matching is lexical.
   **Recommendation: keep.** The saving is ~20 characters per skill and the downside is losing the
   exact phrase the skill is invoked by.

4. **Skills already at or near a floor.** `ai-briefing:generate` (330 `name`+`description` chars),
   `dometrain:grounding` (398), `context7:lookup` (469, and the only model-invocable skill with no
   trigger block at all). There is nothing to take.

5. **`Actions:` enumerations on multi-verb skills.** `work-items:track`, `skill-quality:check`,
   `re-anchor:setup`. These tell the model which verb to pass, which is selection information, not
   documentation. Cutting them turns a correct invocation into a body read.

6. **Domain vocabulary in the prose half.** `docs-hygiene:audit-noise`'s "historical citations,
   ghost refs to ephemeral working-directories", `code-tidying:audit-comment-residue`'s four residue
   shapes, `songwriting`'s craft terms. These read as elaboration but are the only vocabulary a
   user's phrasing can match against — nothing in `songwriting:meter-prosody`'s *name* matches "does
   this line scan".

7. **The 1,536 cap is not a place to save.** No entry in this repo exceeds it (max 1,161), so
   nothing is currently being truncated. But if a future entry crosses 1,536, characters trimmed
   above the cap save exactly zero — and the cheapest thing to lose is whatever sits last in the
   text. That is an argument for putting trigger phrases *early*, which is precisely what the docs
   advise and what moving them into `when_to_use` works against, since `when_to_use` is always
   appended last.

8. **`skillOverrides` is not an escape hatch here.** The docs offer `"name-only"` as a way to free
   budget, but the setting explicitly "does not apply to plugin skills". Every skill in this repo is
   a plugin skill. A reader planning around that lever should know it is unavailable.

---

## 8. The incumbent gate — what `skill-quality:check` already enforces

Run before proposing anything new, per the incumbent-first rule. All line references are to
`plugins/skill-quality/scripts/check-skill.sh` at commit `39880e3bb7`.

| Check | Location | What it actually does |
|---|---|---|
| 2 — per-skill cap | `check-skill.sh:219-234` | `DESC_CHAR_CAP=1536` (`:132`) against `len(description) + len(when_to_use)` |
| 3 — trigger preservation | `check-skill.sh:236-304` | Extracts single-quoted trigger phrases from `description` **and** `when_to_use` combined at `CHECK_SKILL_BASE_REF` (default `HEAD`, `:93`) and in the working tree, and `err`s on any phrase lost. A phrase that reappears in a sibling skill that did not already carry it at the base ref is treated as a deliberate **move** and only `warn`s |
| 12 — trigger phrasing | `check-skill.sh:440-448` | `warn`s when a case-insensitive search for `use when` finds nothing in `description` concatenated with `when_to_use`, then `warn`s if the triggers are not single-quoted |

Four findings follow.

**The lever already exists — check 3 is the gate.** Because check 3 reads `description` and
`when_to_use` *combined* on both sides of the diff, the exact migration #1271 proposes — moving a
trigger phrase from one field to the other in the same skill — passes it unchanged, while genuinely
dropping a phrase fails it. This is the "no discovery was lost" gate, already built and already
wired. Verified against the §6 proposal using the repo's own extractor
(`plugins/skill-quality/scripts/skill-frontmatter.sh:102`): **122 of 122 phrases preserved.**
Nothing new needs building; the acceptance criterion should cite this check.

**Check 2 is a per-skill cap, not a listing-budget cap.** The skill's own description advertises a
"listing-budget cap". What check 2 enforces is the per-skill 1,536-character truncation cap — a
different thing from the shared 40,000/8,000 listing budget of §1.2. **There is no incumbent check
on the shared budget at all.** That is a real gap, and also the reason the shared budget could
overflow 10× without any gate noticing.

**Check 2 omits the 3-character joiner.** It computes `DESC_LEN + WTU_LEN` (`check-skill.sh:227`),
but the binary's entry text is `description + " - " + when_to_use`. The check therefore under-counts
by exactly 3 characters whenever `when_to_use` is populated. Not currently binding — the longest
entry in the tree is 1,161 — but wrong at the root, and wrong in precisely the direction this issue
is about.

**Check 12 collides with the proposal, and this is the one blocker.** Check 12 warns unless the text
`use when` appears somewhere in `description` + `when_to_use`. The §6 rewrite puts bare quoted
trigger phrases in `when_to_use` with no `Use when:` marker anywhere, so **all 15 proposed rewrites
WARN**. Evaluated directly against check 12's own predicate; the result is 0 of 15 passing. Two
honest fixes, and the choice is #1271's to make:

- Keep a literal `Use when:` prefix inside `when_to_use`. No code change, but it costs ~10
  characters per skill **on top of** the joiner's +3. Across 130 model-invocable skills that is
  roughly **+1,700 characters** — which would consume most of the 1,906 the named reduction sources
  can offer (§5) and push a fleet-wide migration net-negative on characters. The "close to
  character-neutral" framing therefore depends on which fix is chosen; this option is not neutral.
- Amend check 12 to treat a populated, single-quoted `when_to_use` as satisfying the trigger-spec
  requirement. This is the better fix — check 12's warning text ("a description is a trigger spec,
  not a summary") encodes the pre-`when_to_use` authoring model that #1271 is deliberately changing.
  It edits `check-skill.sh`, so it **sequences behind PR
  [#1096](https://github.com/melodic-software/claude-code-plugins/pull/1096)**, which is already
  editing that file.

---

## 9. Re-verification record

Every load-bearing figure was re-derived by script against the tree at `39880e3bb7` before this file
was committed, rather than transcribed. The documentation quotations in §1.1 were re-fetched from
the live pages and compared character-for-character.

| Figure | Original | Reproduced | Verdict |
|---|---|---|---|
| `find plugins -name SKILL.md` | 187 | **188** | corrected |
| Nested non-skill `SKILL.md` files | 6, all `vendor/` | **7 — six `vendor/`, one `references/`** | corrected |
| Skills in the repo | 181 | 181 | exact |
| Model-invocable / DMI | 130 / 51 | 130 / 51 | exact |
| Model-invocable `description` chars | 79,653 | 79,653 | exact |
| Model-invocable `name`+`description` | 82,533 | 82,533 | exact |
| Listing entry cost (130) | 83,270 | 83,270 entry-cost sum; **83,399** with `n − 1` separators | basis clarified |
| All 181 `name`+`description` | 108,460 | 108,460 | exact |
| All 181 listing cost | 109,581 | 109,581 (separator-inclusive) | exact |
| Entries at or over 1,536 | 0 | 0 | exact |
| Longest entry | 1,161, `docs-hygiene:audit-derivability` | 1,161, same skill | exact |
| Median entry text | 556 | **594** (`description`) / **600** (entry text) | corrected |
| Skills using `when_to_use` | 2, 211 chars | 2, 211 chars | exact |
| Model-invocable name-only floor | 3,140 | 3,140 | exact |
| Budget at 1M / 200k | 40,000 / 8,000 | 40,000 / 8,000 | exact |
| 192-entry decomposition | 181 − 1 + 7 + 3 + 1 + 0 + 1 | every term re-counted | exact |
| §5 span totals | 1,906 chars, 2.4% | 1,989 chars, 2.5% (independent detector) | consistent, heuristic-dependent |
| Residual after zeroing named sources | "above 81,000" | 81,410 | consistent |
| §6 trigger preservation | 103 / 103 | **122 / 122** (repo's own extractor) | consistent verdict, different denominator |

Three items are **carried without independent reproduction** and should be read accordingly:

- **The 111,578-character total** for the 192-entry installed population. The entry *count*
  decomposition was re-verified term by term; the character total was not re-derived, because it
  depends on resolving which cached plugin version the harness loads and how it dedupes across
  marketplaces.
- **The §3 live-listing figures** (35 kept / 95 name-only / 59,824 withheld). These come from a
  hand transcription of a system prompt no script can read, are per-machine usage state, and are an
  **upper bound on the drop** — see the provenance note in §3. They have not been upgraded to a
  measurement.
- **The §5 per-source spans.** Heuristic and detector-dependent; see the note in §5. The totals
  agree across two independent detectors, the individual rows do not.

The median-entry correction (556 → 594) and the file-count correction (187 → 188) change no
conclusion. Neither figure is load-bearing for anything in §§1–8.
