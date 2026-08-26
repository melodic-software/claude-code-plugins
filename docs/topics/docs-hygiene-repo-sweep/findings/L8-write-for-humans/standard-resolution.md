# Standard resolution

Lane `L8-write-for-humans`, wave 1, read-only. Written before any file was audited, because
`docs-hygiene:write-for-humans` makes standard resolution its first step and its own failure mode
its first gotcha.

## The resolved standard

**This repository declares its own prose style guide, so the bundled default set does not apply as
a whole.**

The authority chain:

1. `.claude/rules/vendor-docs-are-not-style.md` (a `T1` always-loaded rule) ends with this
   declaration:

   ```text
   Write this repo's prose to
   `plugins/ai-slop/skills/audit/reference/rewrite-guide.md`.
   ```

2. `PLAN.md` restates it as a standing rule for every agent in this sweep:

   ```text
   **This repo's prose style** is `plugins/ai-slop/skills/audit/reference/rewrite-guide.md`. No em
   dashes in this repo's own instruction surfaces.
   ```

So the resolved standard is **`plugins/ai-slop/skills/audit/reference/rewrite-guide.md`**, with four
supporting repo surfaces that carry parts of the same contract:

| Surface | What it owns |
|---|---|
| `plugins/ai-slop/skills/audit/reference/rewrite-guide.md` | Prose style: plain speech, substitution guardrails, voice, the legitimate-hit taxonomy |
| `.markdownlint-cli2.jsonc` | Markdown mechanics, and which mechanical rules this repo has switched off |
| `docs/conventions/**/README.md` | Document-shape contracts (`topic-docs`, `standards`, `seam-phrasing`, `tracker-reference-form`) |
| `scripts/check-skill-count-claims.sh`, `scripts/check-changelog-parity.sh` | Two prose invariants this repo enforces in CI rather than by proofreading |

The bundled default set (Diátaxis, Google developer style, ASD-STE100, Global English) is reached
only where the resolved standard is silent. It is silent on exactly two things: **document mode**
and **sentence-level ambiguity**. Those two are where this lane does its work.

## The skill's three rules that survive a declared guide

The skill names three rules as outliving any project guide. All three hold here, and two of them
turn out to be already enforced by this repo rather than by prose review:

| Rule | Status in this repo |
|---|---|
| Cut every word that does no work | Held by the resolved guide's own "Filler" and "Plain speech" sections. Owned by `ai-slop:audit`, not by this lane |
| Use the short, everyday word | Held by the guide's "Prefer the plain word" and "Metaphor jargon" entries. Owned by `ai-slop:audit` |
| Write the real name, and the real number | Held, and **enforced in CI** by `scripts/check-skill-count-claims.sh`. This lane verified it independently and found zero live violations |

## Where the repo guide overrode a named default

Eleven points. Each one is a place where applying the bundled default would have damaged the
corpus, so each is recorded rather than silently absorbed.

### 1. Em dashes: the repo tightens, it does not disable

Global English offers its em-dash rule as one a project is likely to overrule
(`reference/sentence-rules.md`, "Two punctuation rules that a project may well disable"). This repo
went the other way. The resolved guide's "Substitution guardrails" make it zero-tolerance and add a
guardrail the bundled rule lacks: *"Never parentheses, never en dashes, never a spaced hyphen: each
of those is the same interruption wearing a different mark. If the thought needs separation, end the
sentence."*

`ai-slop:audit` owns the em-dash axis and this lane does not duplicate it. This lane owns the
**consequence**: twelve places in the corpus where a sentence has been ended *inside* a
parenthetical, leaving a fragment on one side of the period and text that does not parse. That is
the exact shape the guardrail produces when "end the sentence" is applied between parentheses, which
is the one case the guardrail does not cover. Predicate `Am1` covers it, and it is this lane's
highest-confidence finding class.

Two limits on that reading, both stated because the causal story is suggestive rather than proven.
This lane did not check the sites against git history, so it cannot say which commit produced them.
And the substitution has not been applied uniformly: 427 em dashes remain in plugin READMEs outside
the generated marker blocks, so a straightforward "the de-slop did this everywhere" account does not
hold. The findings stand on the text as it is; the mechanism is offered as the likely explanation,
not as a claim.

Note also that the rule's own scope is narrower than the corpus. `.claude/rules/vendor-docs-are-not-style.md`
names the surfaces it governs:

```text
Do not copy their formatting, including em dashes, into this repo's own
instruction surfaces (`SKILL.md`, plugin READMEs, `AGENTS.md`, `CLAUDE.md`,
`.claude/rules/**`).
```

`docs/**` is not in that list. So the 130 files under `docs/` that carry em dashes are in policy,
not in violation, and this lane treats them as such. Every one of the twelve `Am1` findings is in a
plugin README, which is inside the rule's declared scope.

### 2. Semicolons: not adopted

Global English prefers periods to semicolons. The resolved guide says nothing about semicolons, and
the corpus uses them heavily and deliberately. **Not adopted. This lane does not flag a semicolon.**

### 3. Latin abbreviations: not adopted

Global English says to skip Latin abbreviations. `e.g.` and `i.e.` appear at 104 sites across the
human slice, consistently, including in files the repo owner clearly proofreads. That is house
usage, not drift. **Not adopted. This lane does not flag `e.g.`, `i.e.`, or `etc.`**

Flagging 104 sites of a consistent house convention would have been the single most damaging thing
this lane could do, which is the exact failure the skill's first step exists to prevent.

### 4. Voice and rhythm: register-gated, narrower than the bundled rule

The skill body's "Vary the rhythm" tells you to have a view and to mix sentence lengths. The
resolved guide's "Adding voice" section is explicitly **register-gated**: it *"applies where the
document has an author's voice (a README's narrative sections, a design doc's tradeoffs, a
changelog's rationale) and stays out of API reference tables, operative skill instructions, and
generated content."* It then adds a docs-register constraint the bundled rule does not have:
*"in reference prose vary structure less and lead with the point instead."*

So in `## Requirements`, `## Configuration`, `### Options reference`, and the convention contract
docs, the rhythm rule is **off**. This lane filed no rhythm findings anywhere.

### 5. Bold as a pseudo-heading: not adopted

Google's heading guidance would push a bolded lead-in to a real heading. `.markdownlint-cli2.jsonc`
disables `MD036` with the comment *"Allow bold text used as a pseudo-heading"*. That is a deliberate
configuration decision. **Not adopted.**

### 6. Line length and one-h1-per-page: not adopted

`.markdownlint-cli2.jsonc` disables `MD013` (no hard line-length limit) and `MD025` (multiple h1
sections allowed). The bundled address layer's heading rules assume otherwise. **Not adopted.**

### 7. Heading case: no repo rule, so no finding

Google style asks for sentence case. The repo declares nothing, `SECURITY.md` uses Title Case per
GitHub's community-health-file convention, and plugin READMEs use sentence case. With no declared
rule, imposing one would be inventing a standard. **Not applied.**

### 8. Tracker references: house form, not a defect

`docs/conventions/tracker-reference-form/README.md` blesses the bare parenthesised `(#N)` form and
scopes its own enforcement to a code-extension allowlist, stating outright that *"Markdown and YAML
are not scanned"*. This lane therefore never flags `(#1416)` as a citation-form defect. It flags
only the surrounding **release-history narrative** when a README carries it (predicate `M2`), which
is a mode question, not a citation-form question.

### 9. Generated blocks: out of scope by the guide's own taxonomy

The resolved guide's legitimate-hit taxonomy, class 3: *"**Generated files** whose prose is owned by
a generator. Fix the generator or its source, never the output."*

That rules out four surfaces this lane would otherwise have findings in:

- `docs/CATALOG.md` (generated from plugin manifests; 21 backtrack-risk sentences in it are
  manifest `description` strings, owned by `plugins/*/.claude-plugin/plugin.json`)
- `docs/SKILL-CHEAT-SHEET.md` (generated from SKILL.md frontmatter by
  `scripts/generate-cheatsheet.mjs`)
- every `### Options reference` table (generated by `scripts/sync-plugin-options-docs.py` from
  `plugin.json`)
- the `<!-- BEGIN GENERATED -->` block in each plugin README

The **placement** of a generated block is authored, not generated, so predicate `M3` still reaches
it. The prose inside it does not.

### 10. Negative parallelism and triads: the guide restrains the rewriter

The bundled set has no rule here. The resolved guide adds two, both of which restrain this lane
rather than arming it. On negative parallelism: *"when the context does not settle it, keep the
original and flag the ambiguity to the author instead of guessing."* On triads: keep the strongest
item *"ONLY when the surviving text still entails every deleted item."*

Adopted. Where a construction in the corpus was genuinely two-way readable, this lane recorded it as
an ambiguity to raise rather than proposing a rewrite that picks a reading.

### 11. The improve-it-anyway gate

The resolved guide opens with a posture the bundled set has no equivalent for: *"would this edit
improve the prose if AI detection did not exist? An edit that only launders provenance fails the
test and is not applied."*

Every finding in this lane was filed against that gate. It is the reason the yield is small: most of
what a bundled-set audit would surface here fails it.

## What this leaves the lane

After the eleven overrides, this lane owns four things nothing else in the sweep covers:

1. **Document mode** (Diátaxis). The resolved guide is silent on it, and no sibling lane rules on it.
2. **Sentence-level ambiguity** (Global English). The resolved guide has no ambiguity layer at all.
3. **Backtracking sentences**, which the resolved guide does name ("One idea per sentence. If the
   reader must backtrack to parse it, break it in two or drop clauses") but which no scanner checks.
4. **Audience reclassification** of rows the manifest calls `HUMAN` that are not.

Everything else routes: filler and vocabulary and em dashes to `ai-slop:audit`, historical citations
to `L5-noise`, word-level trimming to `L6-compress`, generated-block content to whoever owns the
generator's source.
