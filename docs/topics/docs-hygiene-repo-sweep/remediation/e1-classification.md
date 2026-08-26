# E1 classification. All 89 L4 encapsulation violations, intra-plugin vs cross-plugin

Evidence pass for the E1 decision recorded in
`docs/topics/docs-hygiene-repo-sweep/remediation/escalations.md`. Every one of the 89 violations in
`docs/topics/docs-hygiene-repo-sweep/findings/L4-encapsulation/` is classified `INTRA` or `CROSS`,
each `INTRA` row is sub-classified by citation form, and every cited path was checked against the
file on disk.

This pass verifies, it does not confirm. Three of its results cut against the ruling as worded and
are stated in "What the evidence says against the ruling" below.

## Method and what was verified

1. All 89 violation ids were enumerated from the 25 per-plugin findings files. The count
   reconciles: 16 + 17 + 8 + 7 + 5 + 5 + 5 + 3 + 3 + 3 + 2 + 2 + (13 singletons) = 89.
2. Each violation's citing `path:line` was read from the source file on disk and compared against
   the verbatim quote in its findings file. All 89 match. No finding was taken on trust.
3. Each cited path was resolved and tested for existence, twice: once against the target the
   finding names, and once against the base the citation text actually implies.
4. Leaker shape was recomputed from the citing path rather than copied. The recomputed shape totals
   reproduce the roll-up's own table exactly (30 / 23 / 17 / 16 / 2 / 1), which is an independent
   check that the same 89 rows are in play.

### Definitions used in the tables

**`INTRA`.** The citing file sits under `plugins/<p>/` and the cited skill is
`plugins/<p>/skills/<s>/`, the same `<p>`. Plugin READMEs, plugin-level `context/`, `reference/` and
`agents/` docs, and sibling skill bodies all qualify.

**`CROSS`.** The citing file is in a different plugin, or outside `plugins/` entirely (`docs/**`,
`.claude/**`).

Citation form, the `ANCHOR-FORM` axis:

| Form | Written as | Resolved against |
|---|---|---|
| `anchored` | `${CLAUDE_PLUGIN_ROOT}/skills/<other>/<path>` | the plugin root, explicitly |
| `relative` | `../<other-skill>/<path>` or `../skills/<s>/<path>` | the citing file's own directory |
| `plugin-root` | `skills/<s>/<path>`, with no `../` prefix | the citing file's own directory |
| `repo-relative` | `plugins/<p>/skills/<s>/<path>` | the repository root |

"Resolves as written" means the path token, resolved against the base its own form implies, lands
on a file that exists. That is the test `docs/PLUGIN-PHILOSOPHY.md:341-342` actually describes.

## Summary. Counts by leaker shape

| Citing surface | INTRA anchored | INTRA bare, resolves | INTRA bare, does not resolve | CROSS | Total |
|---|---|---|---|---|---|
| Skill body reaching a sibling skill | 4 | 22 | 0 | 4 | 30 |
| Plugin-level doc (`context/`, `reference/`, `agents/`) | 4 | 11 | 8 | 0 | 23 |
| Plugin README | 0 | 16 | 0 | 0 | 16 |
| Repo convention doc (`docs/conventions/**`) | 0 | 0 | 0 | 17 | 17 |
| Repo doctrine doc (`docs/PLUGIN-PHILOSOPHY.md`) | 0 | 0 | 0 | 2 | 2 |
| Repo rule (`.claude/rules/**`) | 0 | 0 | 0 | 1 | 1 |
| **Total** | **8** | **49** | **8** | **24** | **89** |

Headline: **65 INTRA, 24 CROSS.** Of the 65 INTRA, only **8** use the anchored
`${CLAUDE_PLUGIN_ROOT}` form the philosophy doc prescribes. The other 57 do not.

The 8 anchored citations, for the record: `V-disc-01`, `V-disc-02`, `V-disc-03`, `V-disc-07`,
`V-mut-01`, `V-mut-02`, `V-mut-04`, `V-bugs-01`. Four of them (`V-mut-01`, `V-mut-02`, `V-mut-04`,
`V-bugs-01`) write the exact paired construction `PLUGIN-PHILOSOPHY.md:337-340` gives as its worked
example, an anchored code span wrapping a relative link target.

### The 24 CROSS violations

`V-review-01` through `V-review-14` (17 total counting the convention-doc rows), plus `V-slop-01`,
`V-slop-02`, `V-sq-01`, `V-sq-02`, `V-sc-15`, `V-ops-01`, `V-auto-01`, `V-ct-01`, `V-dhg-01`,
`V-sf-01`. Four of these are skill-body reaches across a plugin boundary and are therefore *not*
dissolved by the ruling even though the roll-up files them in the sibling-skill-reach class:
`V-sc-15` (`work-items` into `source-control`), `V-ops-01` (`claude-config` into `claude-ops`),
`V-auto-01` (`source-control` into `autonomy`), `V-ct-01` (`claude-config` into `code-tidying`).

## Already-broken citations

**No cited path in the corpus is missing from disk. All 89 targets exist, including both heading
anchors and the schema file.** The failure the contract predicts has not yet occurred anywhere in
this set. That negative result is reported first because it removes the strongest empirical argument
the sweep could have made, in either direction.

What *is* broken is narrower and real: **10 of the 89 citations do not resolve from the base their
own form implies.** The target file exists; the address written for it does not reach it. This is
precisely the defect `PLUGIN-PHILOSOPHY.md:341-342` names.

| # | Citing `path:line` | Path as written | Resolves to | Class |
|---|---|---|---|---|
| `V-sc-01` | `plugins/source-control/reference/config-resolution.md:179` | `skills/babysit-loop/reference/promotion-evidence-resolution.md` | `plugins/source-control/reference/skills/...`, absent | INTRA |
| `V-sc-02` | `plugins/source-control/reference/review-discipline.md:306` | `skills/babysit-loop/reference/pre-escalation-dispatch.md` | same shape, absent | INTRA |
| `V-sc-03` | `plugins/source-control/reference/review-discipline.md:171` | `skills/babysit-prs/reference/safety.md` | same shape, absent | INTRA |
| `V-sc-04` | `plugins/source-control/reference/review-discipline.md:271` | `skills/babysit-prs/reference/safety.md` | same shape, absent | INTRA |
| `V-sc-05` | `plugins/source-control/reference/review-discipline.md:303` | `skills/babysit-prs/reference/independent-resolution.md` | same shape, absent | INTRA |
| `V-disc-04` | `plugins/discovery/reference/topic-docs.md:88` | `skills/explore/reference/dispatch.md` | `plugins/discovery/reference/skills/...`, absent | INTRA |
| `V-disc-05` | `plugins/discovery/reference/topic-docs.md:88` | `skills/research/context/dispatch.md` | same shape, absent | INTRA |
| `V-disc-06` | `plugins/discovery/reference/topic-docs.md:89` | `skills/trace-intent/context/dispatch.md` | same shape, absent | INTRA |
| `V-sq-01` | `docs/PLUGIN-PHILOSOPHY.md:581` | `skills/check/reference/fresh-eyes-declarations.md` | no base at all; the plugin is named only in adjacent prose | CROSS |
| `V-sq-02` | `docs/PLUGIN-PHILOSOPHY.md:1056` | `skills/check/reference/fresh-eyes-declarations.md` | same, and ambiguous between two plugins shipping a `check` skill | CROSS |

All ten are bare code spans rather than markdown links, so none renders as a visibly broken link.
An agent instructed to open the path literally fails on all ten; a human clicking never gets the
chance to notice.

Two of the ten deserve separate attention because they sit in the doctrine document itself.
`docs/PLUGIN-PHILOSOPHY.md:581` and `:1056` write a path with no resolvable base, in the same file
whose lines 341-342 forbid exactly that. The registry row at `:581` reads:

```text
| Fresh-eyes declaration pattern contract | `skill-quality` plugin (`skills/check/reference/fresh-eyes-declarations.md`) |
```

The plugin name carries the base in prose. The path alone resolves against nothing, and this repo
ships two plugins with a `check` skill (`skill-quality` and `instruction-placement`), so the token
is genuinely ambiguous. `skill-quality.md` in the findings directory resolved it by file-existence
test; the file exists only under `skill-quality`.

### The `discovery` pair is the sharpest single piece of evidence in the set

`plugins/discovery` cites the **same three target files** twice, in two forms, in two plugin-level
docs, and one form works while the other does not.

`plugins/discovery/reference/parent-contract.md:15-17`:

```text
| `${CLAUDE_PLUGIN_ROOT}/skills/explore/reference/dispatch.md` | explore-only: the collision rule, the six-dimension cost of a re-dispatch, that family's ladder |
```

`plugins/discovery/reference/topic-docs.md:88-89`:

```text
`skills/explore/reference/dispatch.md`, `skills/research/context/dispatch.md` and
`skills/trace-intent/context/dispatch.md`.
```

Same plugin, same targets, one anchored and correct, one bare and unresolvable. This is direct
evidence that legalising the intra-plugin case without also mandating the anchored form produces
drift within a single plugin, and it is the concrete case for making the form requirement binding
rather than advisory.

## The two heading anchors and the one schema file

These need their own treatment because the ruling does not reach them.

| # | Citing `path:line` | Cited | Class | Anchor or file present? |
|---|---|---|---|---|
| `V-sc-17` | `plugins/source-control/reference/worktree-root-convention.md:66` | `plugins/source-control/skills/worktree/SKILL.md#the-nesting-invariant-verified` | **INTRA** | Yes. The heading `### The nesting invariant, verified` is at `plugins/source-control/skills/worktree/SKILL.md:58` |
| `V-dh-01` | `plugins/disk-hygiene/README.md:190` | `plugins/disk-hygiene/skills/clean/reference/safety-model.md#standalone-git-checkout-evidence` | **INTRA** | Yes. The heading `### Standalone Git checkout evidence` is at `plugins/disk-hygiene/skills/clean/reference/safety-model.md:126` |
| `V-auto-01` | `plugins/source-control/skills/babysit-loop/reference/promotion-evidence-resolution.md:8` | `plugins/autonomy/skills/setup/schemas/guardrails-security-binding.schema.json` | **CROSS** | Yes, the schema file exists |

Both heading anchors are INTRA. Both currently resolve. Under the ruling as stated they stay
violations anyway, because an anchor binds to body structure rather than to file layout and the
distribution-unit argument does not touch it: renaming a heading inside a skill breaks the citation
whether or not the two files ship together. `V-sc-17` has a further wrinkle worth naming. The cited
`SKILL.md:54` claims canonical ownership of that section for the whole plugin fleet and says "every
other surface in this plugin points here instead of restating it", so the skill has effectively
published the anchor as an interface. That is an argument for a narrow anchor carve-out, not for
leaving the citation as it stands.

The one schema violation, `V-auto-01`, is CROSS and is unaffected by the ruling. It remains for wave
3. The contract's treatment is unambiguous, at
`plugins/docs-hygiene/skills/audit-encapsulation/context/public-surface-contract.md:37`:

```text
Schema files (`*.schema.json`) stay private — route via `/skill-name <action>` or vendor the schema to a shared tooling location the consumer repo owns.
```

## What the ruling dissolves, and what remains

The answer depends on how strictly the form gate is read, so all three readings are given with their
counts. The orchestrator picks one; the classification underneath does not change.

| Reading | Form gate | Dissolves | Remains for wave 3 |
|---|---|---|---|
| **A. Ruling as literally worded** | Only the anchored `${CLAUDE_PLUGIN_ROOT}` form is legalised; every bare relative path stays a defect | **8** | **81** |
| **B. Form gate = the citation must resolve** | A citation is defective when it does not resolve from its own base, which is what `PLUGIN-PHILOSOPHY.md:341-342` actually says | **55** | **34** |
| **C. Intra-plugin legal, form handled separately** | The ruling legalises the intra-plugin case; form normalization becomes its own follow-up | **63** | **26** |

Reading B's 34 remainder is 24 CROSS + 8 non-resolving INTRA + 2 heading anchors. Reading C's 26 is
24 CROSS + 2 heading anchors, with 57 form-normalization edits (8 mandatory, the non-resolving ones,
and 49 optional) carried as a separate follow-up rather than as encapsulation remediation.

**Reading A is not supported by the file contents.** See the next section; its premise about what
`PLUGIN-PHILOSOPHY.md:341-342` says is wrong for 49 of the 57 bare INTRA citations.

**Reading B is the one this pass recommends**, on the grounds that it is the only reading whose form
gate corresponds to an observable defect. Under it, 55 of the 89 dissolve and 34 remain.

## What the evidence says against the ruling

Four findings qualify or contradict the ruling as it is currently framed. None of them defeats the
distribution-unit argument, which the repository layout supports: 71 plugins, 71
`plugins/<p>/.claude-plugin/plugin.json` manifests each carrying exactly one `version`, 71
`marketplace.json` entries each with `"source": "./plugins/<name>"`, and no per-skill manifest
anywhere. Skills in this repo do not ship or version independently. There is no `.claude/skills/`
directory in this repo at all.

### 1. The ruling's stated reason for rejecting bare relative paths is factually wrong

The brief says a bare relative cross-skill path "is what `PLUGIN-PHILOSOPHY.md:341-342` itself says
is broken". The doctrine text says something narrower:

```text
A bare `context/…`-style path is reserved for a skill's OWN supporting files; it resolves against
the citing skill's directory, so a cross-skill citation written that way points at a file that is
not there.
```

The shape it condemns is `context/x.md` with no `../` prefix, written from inside a skill. **Zero of
the 89 violations use that shape.** The 33 `relative` INTRA citations all use a correctly computed
`../` path and all 33 resolve on disk, verified individually. Applying the doctrine's breakage claim
to them is a category error, and Reading A's 81-item remainder is built on it.

The 8 INTRA citations that genuinely do not resolve are a different shape again: `plugin-root` form
(`skills/<s>/<path>`) written from a plugin-level `reference/` directory, where the implied base is
the plugin root but the actual base is the file's own directory. That failure is real and is listed
above.

### 2. The contract's licence to relax is weaker than E1 states

E1 says "The contract itself licenses this: it states 'A consuming repo may layer its own
conventions on top.'" The full sentence, at
`plugins/docs-hygiene/skills/audit-encapsulation/context/public-surface-contract.md:3`:

```text
A consuming repo may layer its own conventions on top, but the surfaces and carve-outs below are what the detector implements.
```

"On top" reads additive, and the second clause reasserts the detector's surfaces against whatever is
layered. The sentence is at least as easily read as "your conventions do not change what this
detects" as it is read as "you may carve exceptions". It permits the ruling; it does not obviously
authorize it, and quoting only the first clause overstates the case.

The stronger point against it is the guarantee the contract states at line 27:

```text
This guarantees skills are rip-and-paste portable: moving `.claude/skills/<name>/` into another repo carries every implementation detail with it; nothing outside the skill depends on internal layout.
```

That guarantee is stated at the **skill directory** level, not the plugin level. The ruling narrows
it deliberately. That is a defensible trade in a repo where skills never ship alone, but it should be
recorded as narrowing a stated guarantee rather than as reading the contract correctly.

One consequence to route explicitly: `audit-encapsulation` is a distributed plugin whose contract doc
claims applicability "to any repo with `.claude/skills/`". A repo-specific relaxation belongs in a
repo-level convention layered on top, not edited into
`plugins/docs-hygiene/skills/audit-encapsulation/context/public-surface-contract.md`, or this repo
exports its relaxation to every consumer of the plugin.

### 3. E1 understates the decision's blast radius by more than half

E1 says the decision "**Blocks:** 30 of that lane's 89 violations, the whole sibling-skill-reach
class", and that "The other 59 L4 violations are unaffected".

Both halves are wrong on the numbers:

- Only **26** of the 30 sibling-skill reaches are intra-plugin. The other 4 (`V-sc-15`, `V-ops-01`,
  `V-auto-01`, `V-ct-01`) cross a plugin boundary and are untouched by the ruling.
- The ruling reaches **65** violations, not 30, because `INTRA` as defined covers every plugin
  README and every plugin-level doc citing its own plugin's skills. That is 16 README citations plus
  23 plugin-level doc citations that E1 counts among the "unaffected 59".

The 16 plugin READMEs are the substantive change E1 never discusses. The contract names READMEs
explicitly as external consumers, and its reason is rip-and-paste of the skill directory, not
installability. Under the ruling, all 16 become legal in one move: `V-review-15`, `V-sc-16`,
`V-slop-03`, `V-slop-04`, `V-slop-05`, `V-over-03`, `V-sq-03`, `V-dh-01`, `V-dh-02`, `V-rfh-01`,
`V-rfh-02`, `V-cb-01`, `V-dom-01`, `V-imp-01`, `V-vis-01`, `V-x-01`. Whoever signs the ruling should
know they are signing that, and `V-dh-01` should be pulled out of the list because it is a heading
anchor.

The ruling also moots the data-file argument in `context-budget.md`. `V-cb-01` cites
`plugins/context-budget/skills/audit/reference/levers.json`, and the finding's careful reasoning
about why the skill-root data-file carve-out does not reach one level down stops mattering the moment
the citation is INTRA-legal.

### 4. The corpus contains no instance of the harm the contract predicts

Stated plainly because it cuts both ways. Across 89 adjudicated violations and 35 leaked skills,
zero cited paths are missing. No skill in this repo has yet renamed a private file out from under an
external citation. The contract's failure mode is real in principle and is not yet observed here,
which weakens the urgency of remediating the 34 that survive Reading B, and equally weakens any
argument that the 55 dissolved ones were doing damage.

The 10 unresolvable citations are the closest thing to observed harm, and 8 of the 10 are intra-plugin,
which is the case the ruling legalises. Intra-plugin proximity did not prevent them.

## Full per-violation table

89 rows. "Exists" is the cited target's presence on disk. "Resolves" is whether the path as written
reaches it from the base its own form implies.

| # | Citing `path:line` | Cited path | Citing plugin | Cited plugin | Class | Form | Exists | Resolves |
|---|---|---|---|---|---|---|---|---|
| V-review-01 | `docs/conventions/detector-findings/README.md:9` | `plugins/review/skills/fanout/context/default-mode.md` | (repo docs) | `review` | CROSS | repo-relative | yes | yes |
| V-review-02 | `docs/conventions/detector-findings/README.md:79` | `plugins/review/skills/fanout/context/fix-pass-mode.md` | (repo docs) | `review` | CROSS | repo-relative | yes | yes |
| V-review-03 | `docs/conventions/detector-findings/README.md:83` | `plugins/review/skills/fanout/context/findings-normalization.md` | (repo docs) | `review` | CROSS | repo-relative | yes | yes |
| V-review-04 | `docs/conventions/detector-findings/README.md:109` | `plugins/review/skills/fanout/context/findings-normalization.md` | (repo docs) | `review` | CROSS | repo-relative | yes | yes |
| V-review-05 | `docs/conventions/detector-findings/README.md:261` | `plugins/review/skills/fanout/context/fix-pass-mode.md` | (repo docs) | `review` | CROSS | repo-relative | yes | yes |
| V-review-06 | `docs/conventions/detector-findings/README.md:303` | `plugins/review/skills/fanout/context/fix-pass-mode.md` | (repo docs) | `review` | CROSS | repo-relative | yes | yes |
| V-review-07 | `docs/conventions/detector-findings/README.md:482` | `plugins/review/skills/fanout/context/fix-pass-mode.md` | (repo docs) | `review` | CROSS | repo-relative | yes | yes |
| V-review-08 | `docs/conventions/detector-findings/README.md:497` | `plugins/review/skills/fanout/context/fix-pass-mode.md` | (repo docs) | `review` | CROSS | repo-relative | yes | yes |
| V-review-09 | `docs/conventions/detector-findings/README.md:506` | `plugins/review/skills/fanout/context/fix-pass-mode.md` | (repo docs) | `review` | CROSS | repo-relative | yes | yes |
| V-review-10 | `docs/conventions/detector-findings/README.md:628` | `plugins/review/skills/fanout/context/default-mode.md` | (repo docs) | `review` | CROSS | repo-relative | yes | yes |
| V-review-11 | `docs/conventions/detector-findings/README.md:629` | `plugins/review/skills/fanout/context/fix-pass-mode.md` | (repo docs) | `review` | CROSS | repo-relative | yes | yes |
| V-review-12 | `docs/conventions/detector-findings/README.md:631` | `plugins/review/skills/fanout/context/findings-normalization.md` | (repo docs) | `review` | CROSS | repo-relative | yes | yes |
| V-review-13 | `docs/conventions/native-references/README.md:127` | `plugins/review/skills/quality-gate/context/pr.md` | (repo docs) | `review` | CROSS | repo-relative | yes | yes |
| V-review-14 | `docs/conventions/native-references/README.md:183` | `plugins/review/skills/quality-gate/context/pr.md` | (repo docs) | `review` | CROSS | repo-relative | yes | yes |
| V-review-15 | `plugins/review/README.md:83` | `plugins/review/skills/quality-gate/context/pr.md` | `review` | `review` | INTRA | plugin-root | yes | yes |
| V-review-16 | `plugins/review/skills/fanout/SKILL.md:112` | `plugins/review/skills/quality-gate/context/pr.md` | `review` | `review` | INTRA | relative | yes | yes |
| V-sc-01 | `plugins/source-control/reference/config-resolution.md:179` | `plugins/source-control/skills/babysit-loop/reference/promotion-evidence-resolution.md` | `source-control` | `source-control` | INTRA | plugin-root | yes | **NO** |
| V-sc-02 | `plugins/source-control/reference/review-discipline.md:306` | `plugins/source-control/skills/babysit-loop/reference/pre-escalation-dispatch.md` | `source-control` | `source-control` | INTRA | plugin-root | yes | **NO** |
| V-sc-03 | `plugins/source-control/reference/review-discipline.md:171` | `plugins/source-control/skills/babysit-prs/reference/safety.md` | `source-control` | `source-control` | INTRA | plugin-root | yes | **NO** |
| V-sc-04 | `plugins/source-control/reference/review-discipline.md:271` | `plugins/source-control/skills/babysit-prs/reference/safety.md` | `source-control` | `source-control` | INTRA | plugin-root | yes | **NO** |
| V-sc-05 | `plugins/source-control/reference/review-discipline.md:303` | `plugins/source-control/skills/babysit-prs/reference/independent-resolution.md` | `source-control` | `source-control` | INTRA | plugin-root | yes | **NO** |
| V-sc-06 | `plugins/source-control/skills/babysit-loop/SKILL.md:52` | `plugins/source-control/skills/babysit-prs/reference/loop.md` | `source-control` | `source-control` | INTRA | relative | yes | yes |
| V-sc-07 | `plugins/source-control/skills/babysit-loop/SKILL.md:54` | `plugins/source-control/skills/babysit-prs/reference/orchestration.md` | `source-control` | `source-control` | INTRA | relative | yes | yes |
| V-sc-08 | `plugins/source-control/skills/babysit-loop/SKILL.md:463` | `plugins/source-control/skills/babysit-prs/reference/loop.md` | `source-control` | `source-control` | INTRA | relative | yes | yes |
| V-sc-09 | `plugins/source-control/skills/babysit-prs/reference/loop.md:124` | `plugins/source-control/skills/pull-request/reference/monitor.md` | `source-control` | `source-control` | INTRA | relative | yes | yes |
| V-sc-10 | `plugins/source-control/skills/babysit-prs/reference/loop.md:127` | `plugins/source-control/skills/pull-request/reference/monitor.md` | `source-control` | `source-control` | INTRA | relative | yes | yes |
| V-sc-11 | `plugins/source-control/skills/babysit-prs/reference/loop.md:386` | `plugins/source-control/skills/pull-request/reference/readiness.md` | `source-control` | `source-control` | INTRA | relative | yes | yes |
| V-sc-12 | `plugins/source-control/skills/babysit-prs/reference/loop.md:395` | `plugins/source-control/skills/pull-request/reference/monitor.md` | `source-control` | `source-control` | INTRA | relative | yes | yes |
| V-sc-13 | `plugins/source-control/skills/babysit-prs/reference/loop.md:404` | `plugins/source-control/skills/pull-request/reference/monitor.md` | `source-control` | `source-control` | INTRA | relative | yes | yes |
| V-sc-14 | `plugins/source-control/skills/babysit-prs/reference/stuck-checks.md:19` | `plugins/source-control/skills/pull-request/reference/readiness.md` | `source-control` | `source-control` | INTRA | relative | yes | yes |
| V-sc-15 | `plugins/work-items/skills/setup/reference/overlay-ignore-probes.md:18` | `plugins/source-control/skills/setup/reference/apply-convention.md` | `work-items` | `source-control` | CROSS | repo-relative | yes | yes |
| V-sc-16 | `plugins/source-control/README.md:309` | `plugins/source-control/skills/worktree/fixtures/README.md` | `source-control` | `source-control` | INTRA | plugin-root | yes | yes |
| V-sc-17 | `plugins/source-control/reference/worktree-root-convention.md:66` | `plugins/source-control/skills/worktree/SKILL.md#the-nesting-invariant-verified` | `source-control` | `source-control` | INTRA | relative | yes (anchor present) | yes |
| V-wi-01 | `plugins/work-items/reference/dogfood-filing.md:32` | `plugins/work-items/skills/track/actions/add.md` | `work-items` | `work-items` | INTRA | relative | yes | yes |
| V-wi-02 | `plugins/work-items/reference/dogfood-filing.md:50` | `plugins/work-items/skills/track/actions/add.md` | `work-items` | `work-items` | INTRA | relative | yes | yes |
| V-wi-03 | `plugins/work-items/reference/dogfood-filing.md:60` | `plugins/work-items/skills/track/actions/add.md` | `work-items` | `work-items` | INTRA | relative | yes | yes |
| V-wi-04 | `plugins/work-items/reference/dogfood-filing.md:83` | `plugins/work-items/skills/track/actions/add.md` | `work-items` | `work-items` | INTRA | relative | yes | yes |
| V-wi-05 | `plugins/work-items/reference/issue-conventions.md:31` | `plugins/work-items/skills/track/actions/add.md` | `work-items` | `work-items` | INTRA | relative | yes | yes |
| V-wi-06 | `plugins/work-items/reference/issue-conventions.md:37` | `plugins/work-items/skills/track/actions/add.md` | `work-items` | `work-items` | INTRA | relative | yes | yes |
| V-wi-07 | `plugins/work-items/reference/issue-conventions.md:44` | `plugins/work-items/skills/track/actions/done.md` | `work-items` | `work-items` | INTRA | relative | yes | yes |
| V-wi-08 | `plugins/work-items/reference/label-taxonomy.md:90` | `plugins/work-items/skills/track/actions/due.md` | `work-items` | `work-items` | INTRA | relative | yes | yes |
| V-disc-01 | `plugins/discovery/reference/parent-contract.md:15` | `plugins/discovery/skills/explore/reference/dispatch.md` | `discovery` | `discovery` | INTRA | **anchored** | yes | yes |
| V-disc-02 | `plugins/discovery/reference/parent-contract.md:16` | `plugins/discovery/skills/research/context/dispatch.md` | `discovery` | `discovery` | INTRA | **anchored** | yes | yes |
| V-disc-03 | `plugins/discovery/reference/parent-contract.md:17` | `plugins/discovery/skills/trace-intent/context/dispatch.md` | `discovery` | `discovery` | INTRA | **anchored** | yes | yes |
| V-disc-04 | `plugins/discovery/reference/topic-docs.md:88` | `plugins/discovery/skills/explore/reference/dispatch.md` | `discovery` | `discovery` | INTRA | plugin-root | yes | **NO** |
| V-disc-05 | `plugins/discovery/reference/topic-docs.md:88` | `plugins/discovery/skills/research/context/dispatch.md` | `discovery` | `discovery` | INTRA | plugin-root | yes | **NO** |
| V-disc-06 | `plugins/discovery/reference/topic-docs.md:89` | `plugins/discovery/skills/trace-intent/context/dispatch.md` | `discovery` | `discovery` | INTRA | plugin-root | yes | **NO** |
| V-disc-07 | `plugins/discovery/agents/intent-tracer.md:191` | `plugins/discovery/skills/trace-intent/context/artifact-shape.md` | `discovery` | `discovery` | INTRA | **anchored** | yes | yes |
| V-slop-01 | `.claude/rules/vendor-docs-are-not-style.md:10` | `plugins/ai-slop/skills/audit/reference/rewrite-guide.md` | (repo rule) | `ai-slop` | CROSS | repo-relative | yes | yes |
| V-slop-02 | `docs/conventions/upstream-drift/README.md:342` | `plugins/ai-slop/skills/audit/reference/catalog.md` | (repo docs) | `ai-slop` | CROSS | repo-relative | yes | yes |
| V-slop-03 | `plugins/ai-slop/README.md:24` | `plugins/ai-slop/skills/audit/reference/catalog.md` | `ai-slop` | `ai-slop` | INTRA | plugin-root | yes | yes |
| V-slop-04 | `plugins/ai-slop/README.md:34` | `plugins/ai-slop/skills/audit/reference/rewrite-guide.md` | `ai-slop` | `ai-slop` | INTRA | plugin-root | yes | yes |
| V-slop-05 | `plugins/ai-slop/README.md:42` | `plugins/ai-slop/skills/audit/context/persist-findings.md` | `ai-slop` | `ai-slop` | INTRA | plugin-root | yes | yes |
| V-eval-01 | `plugins/evals/skills/design/SKILL.md:31` | `plugins/evals/skills/methodology/reference/success-criteria.md` | `evals` | `evals` | INTRA | relative | yes | yes |
| V-eval-02 | `plugins/evals/skills/design/SKILL.md:49` | `plugins/evals/skills/methodology/reference/grading.md` | `evals` | `evals` | INTRA | relative | yes | yes |
| V-eval-03 | `plugins/evals/skills/design/SKILL.md:49` | `plugins/evals/skills/methodology/reference/recipes.md` | `evals` | `evals` | INTRA | relative | yes | yes |
| V-eval-04 | `plugins/evals/skills/design/SKILL.md:53` | `plugins/evals/skills/methodology/reference/eval-design.md` | `evals` | `evals` | INTRA | relative | yes | yes |
| V-eval-05 | `plugins/evals/skills/design/SKILL.md:66` | `plugins/evals/skills/methodology/reference/grading.md` | `evals` | `evals` | INTRA | relative | yes | yes |
| V-mut-01 | `plugins/mutation-testing/skills/setup/SKILL.md:41` | `plugins/mutation-testing/skills/audit/context/suppression.md` | `mutation-testing` | `mutation-testing` | INTRA | **anchored** | yes | yes |
| V-mut-02 | `plugins/mutation-testing/skills/setup/SKILL.md:74` | `plugins/mutation-testing/skills/audit/context/suppression.md` | `mutation-testing` | `mutation-testing` | INTRA | **anchored** | yes | yes |
| V-mut-03 | `plugins/mutation-testing/skills/audit/SKILL.md:224` | `plugins/mutation-testing/skills/principles/reference/scaling-and-suppression.md` | `mutation-testing` | `mutation-testing` | INTRA | relative | yes | yes |
| V-mut-04 | `plugins/mutation-testing/skills/audit/SKILL.md:240` | `plugins/mutation-testing/skills/principles/reference/metrics.md` | `mutation-testing` | `mutation-testing` | INTRA | **anchored** | yes | yes |
| V-mut-05 | `plugins/mutation-testing/skills/audit/context/suppression.md:20` | `plugins/mutation-testing/skills/principles/reference/scaling-and-suppression.md` | `mutation-testing` | `mutation-testing` | INTRA | relative | yes | yes |
| V-ops-01 | `plugins/claude-config/skills/audit-pass/reference/run-state-and-resumability.md:70` | `plugins/claude-ops/skills/lanes/context/restart-consumer.md` | `claude-config` | `claude-ops` | CROSS | repo-relative | yes | yes |
| V-ops-02 | `plugins/claude-ops/skills/audit-skill-visibility/SKILL.md:103` | `plugins/claude-ops/skills/plugins/context/scope-semantics.md` | `claude-ops` | `claude-ops` | INTRA | relative | yes | yes |
| V-ops-03 | `plugins/claude-ops/skills/lanes/context/refresh.md:128` | `plugins/claude-ops/skills/plugins/context/sync.md` | `claude-ops` | `claude-ops` | INTRA | relative | yes | yes |
| V-over-01 | `plugins/overengineering/context/product-code-lane.md:38` | `plugins/overengineering/skills/audit/context/surface-walk.md` | `overengineering` | `overengineering` | INTRA | relative | yes | yes |
| V-over-02 | `plugins/overengineering/context/product-code-lane.md:189` | `plugins/overengineering/skills/audit/context/surface-walk.md` | `overengineering` | `overengineering` | INTRA | relative | yes | yes |
| V-over-03 | `plugins/overengineering/README.md:147` | `plugins/overengineering/skills/delta/context/recurring-wiring.md` | `overengineering` | `overengineering` | INTRA | plugin-root | yes | yes |
| V-sq-01 | `docs/PLUGIN-PHILOSOPHY.md:581` | `plugins/skill-quality/skills/check/reference/fresh-eyes-declarations.md` | (repo docs) | `skill-quality` | CROSS | plugin-root | yes | **NO** |
| V-sq-02 | `docs/PLUGIN-PHILOSOPHY.md:1056` | `plugins/skill-quality/skills/check/reference/fresh-eyes-declarations.md` | (repo docs) | `skill-quality` | CROSS | plugin-root | yes | **NO** |
| V-sq-03 | `plugins/skill-quality/README.md:44` | `plugins/skill-quality/skills/check/reference/fresh-eyes-declarations.md` | `skill-quality` | `skill-quality` | INTRA | plugin-root | yes | yes |
| V-dh-01 | `plugins/disk-hygiene/README.md:190` | `plugins/disk-hygiene/skills/clean/reference/safety-model.md#standalone-git-checkout-evidence` | `disk-hygiene` | `disk-hygiene` | INTRA | plugin-root | yes (anchor present) | yes |
| V-dh-02 | `plugins/disk-hygiene/README.md:280` | `plugins/disk-hygiene/skills/clean/reference/safety-model.md` | `disk-hygiene` | `disk-hygiene` | INTRA | plugin-root | yes | yes |
| V-rfh-01 | `plugins/repo-fleet-hygiene/README.md:180` | `plugins/repo-fleet-hygiene/skills/audit/reference/security-review.md` | `repo-fleet-hygiene` | `repo-fleet-hygiene` | INTRA | plugin-root | yes | yes |
| V-rfh-02 | `plugins/repo-fleet-hygiene/README.md:186` | `plugins/repo-fleet-hygiene/skills/audit/reference/official-sources.md` | `repo-fleet-hygiene` | `repo-fleet-hygiene` | INTRA | plugin-root | yes | yes |
| V-auto-01 | `plugins/source-control/skills/babysit-loop/reference/promotion-evidence-resolution.md:8` | `plugins/autonomy/skills/setup/schemas/guardrails-security-binding.schema.json` | `source-control` | `autonomy` | CROSS | relative | yes | yes |
| V-bugs-01 | `plugins/bugs/skills/scan/context/findings-report.md:29` | `plugins/bugs/skills/write/context/template.md` | `bugs` | `bugs` | INTRA | **anchored** | yes | yes |
| V-cc-01 | `plugins/claude-config/skills/audit/reference/audit-checklist.md:195` | `plugins/claude-config/skills/audit-instructions/reference/criteria.md` | `claude-config` | `claude-config` | INTRA | relative | yes | yes |
| V-cm-01 | `plugins/claude-memory/skills/audit/reference/criteria.md:95` | `plugins/claude-memory/skills/stateless/context/status.md` | `claude-memory` | `claude-memory` | INTRA | relative | yes | yes |
| V-ct-01 | `plugins/claude-config/skills/audit-instructions/reference/criteria.md:392` | `plugins/code-tidying/skills/tidy/reference/tidyings.md` | `claude-config` | `code-tidying` | CROSS | repo-relative | yes | yes |
| V-cu-01 | `plugins/computer-use/skills/setup/SKILL.md:22` | `plugins/computer-use/skills/diagnose/reference/failure-diagnostics.md` | `computer-use` | `computer-use` | INTRA | relative | yes | yes |
| V-cb-01 | `plugins/context-budget/README.md:53` | `plugins/context-budget/skills/audit/reference/levers.json` | `context-budget` | `context-budget` | INTRA | plugin-root | yes | yes |
| V-dhg-01 | `docs/conventions/upstream-drift/README.md:343` | `plugins/docs-hygiene/skills/write-for-humans/reference/sources.md` | (repo docs) | `docs-hygiene` | CROSS | repo-relative | yes | yes |
| V-dom-01 | `plugins/dometrain/README.md:132` | `plugins/dometrain/skills/sync/context/update.md` | `dometrain` | `dometrain` | INTRA | plugin-root | yes | yes |
| V-imp-01 | `plugins/improvement/README.md:68` | `plugins/improvement/skills/find/context/unattended.md` | `improvement` | `improvement` | INTRA | plugin-root | yes | yes |
| V-sf-01 | `docs/conventions/pre-pr-ordering/README.md:5` | `plugins/session-flow/skills/workflow/context/pre-pr.md` | (repo docs) | `session-flow` | CROSS | repo-relative | yes | yes |
| V-vis-01 | `plugins/visualization/README.md:26` | `plugins/visualization/skills/visualize/context/decision-matrix.md` | `visualization` | `visualization` | INTRA | plugin-root | yes | yes |
| V-x-01 | `plugins/x/README.md:73` | `plugins/x/skills/read/context/failure-modes.md` | `x` | `x` | INTRA | plugin-root | yes | yes |

## Wave 3 remainder under the recommended reading

Reading B leaves **34** violations for wave 3, in three groups.

**Group 1. Cross-plugin and out-of-plugin citations, 24.** Unchanged by the ruling; the existing
remediation specs in the findings files apply as written.

- Repo convention docs, 17: `V-review-01` through `V-review-14`, `V-slop-02`, `V-dhg-01`, `V-sf-01`.
- Repo doctrine doc, 2: `V-sq-01`, `V-sq-02`. Both also unresolvable as written.
- Repo rule, 1: `V-slop-01`. Tier 1, always loaded.
- Cross-plugin skill-body reaches, 4: `V-sc-15`, `V-ops-01`, `V-auto-01`, `V-ct-01`. `V-auto-01` is
  also the corpus's only schema-file citation.

**Group 2. Intra-plugin citations that do not resolve as written, 8.** Legal under the ruling as
citations, defective as paths. The fix is form, not routing: rewrite each to the anchored
`${CLAUDE_PLUGIN_ROOT}` form (which is what `parent-contract.md` already does for three of the same
targets) or add the `../` the plugin-root form is missing.

`V-sc-01`, `V-sc-02`, `V-sc-03`, `V-sc-04`, `V-sc-05`, `V-disc-04`, `V-disc-05`, `V-disc-06`.

**Group 3. Heading anchors, 2.** `V-sc-17` and `V-dh-01`. Both INTRA, both currently resolving, both
outside the ruling's reach because an anchor binds body structure. Decide these separately: either
remediate per the findings files, or open a narrow anchor carve-out, for which `V-sc-17` has a
genuine case (`plugins/source-control/skills/worktree/SKILL.md:54` publishes the anchor as the
plugin fleet's canonical address for that invariant).

**Dissolved: 55.** The 65 INTRA violations minus the 8 in group 2 and the 2 in group 3.

## Follow-ups this pass generated

1. **`escalations.md` E1 needs correcting on three counts** before it is used as the decision
   record: the "30 violations, the whole sibling-skill-reach class" scope (it is 26 of 30, and the
   ruling reaches 65), the "other 59 unaffected" claim, and the partial quotation of
   `public-surface-contract.md:3`.
2. **`docs/PLUGIN-PHILOSOPHY.md:581` and `:1056` violate the doctrine document's own line 341-342.**
   Whatever E1 decides, those two lines are defective, and one of them is a live registry row.
3. **If the ruling lands, the form requirement should be made binding**, not advisory. The
   `discovery` evidence shows the same three targets written correctly in one plugin-level doc and
   incorrectly in another, inside one plugin, today.
4. **Do not encode the relaxation in
   `plugins/docs-hygiene/skills/audit-encapsulation/context/public-surface-contract.md`.** That file
   ships to other repos and claims general applicability. A repo-level convention under
   `docs/conventions/` layered on top is the correct home, which is also what line 3 of the contract
   describes.
