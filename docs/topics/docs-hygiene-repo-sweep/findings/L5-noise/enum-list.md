# L5-noise: `enum-list`

**4568 candidates in. 0 findings out. 4568 rejected.**

The shape targets a specific defect: a file hardcodes the list of *other* things that consume it,
so every add or remove of a consumer forces an edit to that file. The detector does not test for
that. It tests four structural cues, three of which fire on ordinary markdown.

## Form taxonomy

Every candidate was mechanically assigned to the sub-pattern that fired, by replaying
`audit_noise_line_has_enum_list` from
`plugins/docs-hygiene/skills/audit-noise/scripts/lib/noise-shapes.sh:285-300` against the real
source line. Assignment is complete over all 4568, not sampled.

| Form | Cue | Population | Decision | Basis |
|---|---|---:|---|---|
| F1 `following N <consumers>` | `following (N\|two..ten) (skills\|consumers\|agents\|modules\|plugins)` | 3 | Reject | full read of all 3 |
| F2 slash-command bullet roster | `- /slug — role` | 0 | n/a | population empty |
| F3 bold definition bullet | `- **Term** — text` | 1625 | Reject | 20-row read plus a census of all 1625 |
| F4 table row containing any `/token` | row starting `\|`, not a separator, containing `/[a-z]` | 2940 | Reject | 20-row read plus a per-file and per-cell census of all 2940 |

### F1, `following N <consumers>`, 3 candidates, rejected

All three read in full. None is a live roster.

- `plugins/docs-hygiene/skills/audit-noise/SKILL.md:56` is the shape's own definition row, quoting
  `"the following five skills…"` as the pattern it looks for. Self-match, covered by the skill's
  own dismissal ground for a shape definition matching its own pattern.
- `plugins/docs-hygiene/skills/audit-noise/evals/fixtures/noisy-rule-snippet.md:18` and
  `.../recall-paraphrases.md:15` are the detector's own test fixtures, authored to trip it. The
  skill's prescribed corpus for a repo-wide run excludes `**/evals/fixtures/**` for this reason.

The canonical form the shape is named for therefore occurs zero times in real corpus prose.

### F2, slash-command bullet roster, 0 candidates

The form the shape table leads with (`bulleted /skill — role` rosters) never fires. Recorded
because its absence is the finding: the defect the shape was written against is not present in this
corpus in its canonical form.

### F3, bold definition bullet, 1625 candidates, rejected

Cue: `^\s*[-*+]\s+\*\*[^*]+\s*—`, a bullet whose bolded lead is followed by an em dash. That is
this repo's standard glossary and criteria bullet, used everywhere a term is named and then
defined. Examples from the sample:

- `plugins/docs-hygiene/skills/rename-references/context/patterns.md:35` reads
  `- **Form name** — the syntactic shape it catches`
- `plugins/review/agents/security-reviewer.md:36` reads
  `- **SQL injection** — ORM parameterization, no raw SQL string concatenation`
- `plugins/event-storming/skills/methodology/reference/process-modeling.md:27` reads
  `- **User Happy** — involved users are aware of the process completion (they see the outcome somewhere)`

Discriminating census over the whole form, not a sample: **17 of 1625** contain a
`plugin:skill` slash-command token at all. The other 1608 name no consumer of any kind, so they
cannot be a consumer roster. A cue with a 1% chance of even mentioning the entity class it is
supposed to enumerate is matching typography, not a defect.

### F4, table row containing any `/token`, 2940 candidates, rejected

Cue: any GFM row that is not a separator and contains `/` followed by a lowercase letter. That
matches a filesystem path, a URL, an environment-variable path, `and/or`, a date, and a regex, not
only a slash command.

Census over the whole form:

| Sub-form | Population | Note |
|---|---:|---|
| F4b: no slash command anywhere in the row | 2039 | matched a path, URL, or `and/or` only |
| F4a: row contains a `plugin:skill` token | 754 | further split below |

The 754 F4a rows decompose by owning file into four kinds, none of which is the defect:

1. **Generated catalog, 161 rows.** All 161 rows from `docs/SKILL-CHEAT-SHEET.md` are machine
   output. `plugins/session-flow/skills/show-options/context/candidate-ladder.md:57` states it:
   "docs/SKILL-CHEAT-SHEET.md is generated from skill frontmatter by
   `scripts/generate-cheatsheet.mjs`", and `scripts/check-docs-only.test.sh:86` confirms a
   `--check` gate reads it. The prescribed treatment for this shape is "replace with a runtime
   derivation". That treatment is already applied.
2. **Plugin README own-skill table.** A plugin README listing the plugin's own skills is the
   plugin's only self-describing surface. L3-ssot established the repo's written doctrine that
   plugin contracts are carried inline at every adopting site because plugins ship without the
   marketplace repo (`docs/conventions/untrusted-content/README.md:34`). Replacing these with a
   grep command would leave a consumer with no marketplace checkout holding a pointer to nothing.
3. **Situation-to-skill routing table.** `plugins/songwriting/context/pat-pattison/research/action-routing.md`
   (60 rows), `plugins/planning/skills/wayfind/SKILL.md` (11 rows), `plugins/songwriting/skills/rhyme/SKILL.md`
   and siblings. The left column is a symptom or a situation and the right column is the skill to
   invoke. The content is a mapping authored by judgment. No runtime derivation can produce it,
   and the "hardcoded N consumers" framing does not apply because the rows are not consumers of
   the file they sit in.
4. **Incidental single-cell mention.** A table about something else that names a skill in one cell,
   for example `plugins/coupling/skills/reduce/SKILL.md:163`,
   `| Shipping a PR | /source-control:pull-request create when installed; else the repo's own PR convention |`.
   One mention is not a roster.

## Recall check

The detector's cues are structural, so a genuine hard-coupled roster written in prose would be
missed. A corpus-wide grep for the semantic form over all 1218 scanned files:

```
the following (skills|plugins|consumers|agents|files|rules)
consumed by (these|the following)
consumers of this (rule|file|skill)
call sites:
adopting sites
these ... (skills|plugins) (use|consume|adopt)
```

returns exactly one hit, `plugins/context-guard/skills/setup/SKILL.md:426`
("consumers of this file must parse it as"), which states a parsing requirement and enumerates
nothing. The defect is absent from the corpus, not merely unmatched by the cue.

## Detector defect worth reporting

F3 and F4 are the two cues the detector's own test suite added for recall
(`detect.test.sh:1487-1523`, "bold roster is enum-list", "table consumer row flags as enum-list").
They bought recall at a precision cost this corpus makes measurable: 4565 of 4568 candidates come
from those two cues and none survives review. F4's inner test is `/[a-z]`, which does not require
a slash command at all; requiring a leading word boundary and a `plugin:skill` shape would drop
2039 candidates with no loss. F3 has no consumer test of any kind.

## Cross-lane observations

- **L3-ssot.** `Do not set the CLAUDE_PLUGIN_OPTION_* variables yourself. They are how Claude Code
  hands a configured value to a hook process; the value comes from the routes above.` appears
  verbatim in at least `plugins/actionlint/README.md:139`, `plugins/ai-briefing/README.md:144`, and
  `plugins/powershell-format/README.md:175`. Cross-file duplication is L3's call, not this lane's.
- **L6-compress.** Nothing. The F3 definition bullet is compact already.
- **L1-derivability.** `docs/SKILL-CHEAT-SHEET.md` is generated, so its existence question belongs
  to whoever owns generated artifacts, not to a noise pass.
