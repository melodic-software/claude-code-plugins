# extract-ssot whole-repo sweep, 2026-08-28

The record of a whole-repo `/docs-hygiene:extract-ssot` run: what it applied, what it verified and
deliberately did not apply, and what it refused. Written so the unapplied half is resumable without
re-auditing, and so the refusals are not re-derived.

This run exists because the eight-lane `docs-hygiene` sweep in
[#3362](https://github.com/melodic-software/claude-code-plugins/pull/3362) recorded its remainder in
[`docs-hygiene-sweep-unapplied-remediations.md`](docs-hygiene-sweep-unapplied-remediations.md), and
[#3380](https://github.com/melodic-software/claude-code-plugins/pull/3380) then closed out lanes L2,
L4, L5, L6 and L7 while leaving **L3, the deduplication lane, untouched**. An adversarial verifier
re-tested that premise cluster by cluster before any edit landed: all 13 remediated clusters were
still open, no later commit had applied them, and no open pull request covered them.

## Decay rule

Point-in-time, stamped 2026-08-28. The same rule the predecessor record states applies here and for
the same reason: **the check is the text, never the status and never the line number.** If a
finding's quoted source text is still present at or near the cited path, the finding is open. A
quote that matches nothing has been applied, superseded, or moved.

Two independent confirmations that this rule is not ceremonial. The predecessor's L3 section recorded
`setup-never-writes-boundary` as "41, 34 edited"; re-measurement found the 41 exact and the
edit set down to **one**, because 33 of the 34 had landed three days before the audit that recorded
them. And the em dashes it located at `persist-findings.md:1` and `:5` were still present, the second
having moved to `:16` when #3380 inserted a `## Contents` index above it.

## Contents

- [What this run did differently](#what-this-run-did-differently)
- [Applied in this change set](#applied-in-this-change-set)
- [Verified, not applied](#verified-not-applied)
- [Contradictions found](#contradictions-found)
- [New refusals, recorded so nobody re-opens them](#new-refusals-recorded-so-nobody-re-opens-them)
- [Open remainder after the encapsulation close](#open-remainder-after-the-encapsulation-close)
- [The L4 roster is closed, all 34 rows, and Group 2 was never open](#the-l4-roster-is-closed-all-34-rows-and-group-2-was-never-open)
- [Recall limits this run declares](#recall-limits-this-run-declares)

## What this run did differently

The predecessor's L3 lane declared its own recall limit precisely: line-anchored matching over
8-word normalized lines, which "finds verbatim and near-verbatim reproduction and misses a paragraph
asserting the same rule in different words", with hard-wrapped prose defeating it entirely and
roughly 200 of 364 candidate blocks triaged by first line and never individually verified. It named
the single change that would most improve a re-run: a shingled n-gram pass over whitespace-normalized
text with line breaks removed.

This run built that pass and added the fan-out the predecessor could not use ("No lane had a
subagent-spawn tool").

| Lane | Method | Yield |
|---|---|---|
| Re-verification | Four workers re-deriving the 13 recorded clusters against the current tree | 6 confirmed open, 5 refused as already applied or already owned, 2 corrected in owner or scope |
| Pass A | 12-word shingle detector over 1,168 files, line breaks removed: 2,087 raw clusters, 639 at 25+ words, 542 after filtering populations already refused with cause | 8 triage workers, 38 survivors from 366 rows |
| Pass B | Four concept-axis workers reading for paraphrase clusters sharing no verbatim phrase | 12 survivors and 12 recorded contradictions, none of them reachable by grep |

Pass B is where the predecessor's declared hole actually was, and it is where the highest-value
findings came from. Four of its results are factual defects rather than style drift.

## Applied in this change set

Ordered as the predecessor's sequencing note requires: the owner doc first, then the call sites, one
editing pass per file.

### Owner edits, `docs/PLUGIN-PHILOSOPHY.md`

- **A `runtime-grounded` clause** in "Setup is explicit and repeatable". The recorded cluster
  `setup-probe-dont-recite` named this owner and recorded the clause as absent; it was, and
  `grep -n "recite" docs/PLUGIN-PHILOSOPHY.md` returned nothing. Twenty setup skills asserted the
  rule with no owner to point at.
- **Three missing Convention registry rows.** `hook-budget`, `tracker-reference-form` and
  `untrusted-content` each open by declaring themselves owner docs and each was absent from the
  registry that indexes them. The registry's own text makes the omission load-bearing: "Fleet audits
  check conformance per row." A convention with no row gets no conformance check, and
  `untrusted-content` is fleet-adopted and anchors a standing refusal.
- **A registry row for the dynamic-context precompute convention**, owned by the `playbooks` plugin.
  The recorded cluster proposed a new `docs/PLUGIN-PHILOSOPHY.md` section named "Inline-template
  conventions"; that heading already exists under "Delegation mechanics" and owns a different
  subject (what a dispatch prompt must contain), so a second one would have duplicated an anchor and
  merged two unrelated concerns.

### The inline floor that was not identical

State §6's scope precisely, because the earlier draft of this section overstated it and the
overstatement is the same defect class as everything else recorded here.
`docs/conventions/loop-lane/README.md` §6 requires that each of the **three consuming lane bodies**
inline the operable floor, and "records the inline-floor rule so **the values** stay byte-identical
**across lanes**". It binds three lanes, on the values, and names
`plugins/rate-limit-guard/reference/reader-contract.md` as their provenance rather than as a fourth
carrier. It says nothing about `extract-ssot`'s orchestrated-mode consumer, which is not a lane.

Under that literal scope the three lanes were already mutually identical, and the values never
drifted at all. What drifted was the surrounding prose, between the three lanes and the contract they
cite. Hashing the three lanes plus the contract plus the orchestrated-mode consumer showed **two**
distinct texts, not three: `git log -S` returns two commits, both per-plugin de-slop shards, and
both made the same two substitutions, so they produced one drifted form between them rather than
two. One of those substitutions replaced a clause-joining dash with a comma, producing a comma
splice in a sentence whose whole job is to state a causal link. The em-dash campaign did not know
the block was frozen.

All five now hash identically, on a form that is both em-dash-free and grammatical, so identity and
the house style are satisfiable together. The predecessor refused `rate-limit-guard-floor-inline`
on the ground that the convention requires identity; that ground was sound for the three lanes and
the fix extends it to the two files they cite, which is a choice this record makes rather than one
§6 compels.

Two further files carry the same floor as a blockquoted restatement inside a prompt:
`prompts/loops/loop-lane-prompts.md` and `prompts/loops/loop-lane-profile-claude-code-plugins.md`.
Both re-wrap the block to a narrower measure. Neither is under the identity contract, for the
reason §6 gives rather than for anything the prompts say: §6 binds the three consuming lane bodies,
and a prompt quoting the floor is not a lane. An earlier draft of this paragraph claimed both files
"say in their own text that the quotation sits outside the byte-audited block". They do not. The
only sentence in either naming that block reads "Two further reader-contract rules apply alongside
the floor (outside the byte-audited block)", whose subject is those two rules, not the quotation —
the same attach-the-quote-to-the-wrong-subject error this record was corrected for once already, in
the `detector-findings-tier-self-restatement` row. Neither prompt is counted in the five. Their wording was brought to the same text anyway, because a reader who diffs a quotation
against its source should find only the wrapping different.

### Call-site normalizations

Each of these keeps its operable text inline. Plugins ship without this repository, so a
`plugins/**` site cannot cite a `docs/**` owner at its own runtime; the return is drift elimination
and one greppable canonical string, never line reduction.

The unreachable-fallback fix landed at **25** sites, plus one more site with a different defect. The
25 all pipe the probe into a cap before `||`, which binds the fallback to the pipeline, whose exit
status is the cap's; `head` exits 0 on empty input, so the fallback can never run.
`plugins/verification/skills/confirm/SKILL.md` is the fleet's one uncapped site: its `||` already
bound to the probe, so its fallback was reachable and emitted an empty string, which under a label
reading `Working tree status:` is the same rendering as a clean tree. Twenty-five plus that one is
the 26 the first commit message counts; that message states all 26 as unreachable and over-counts by
one. The squash message merged to the default branch carries the corrected split.

Four sites with the identical unreachable shape were **not** normalized by this run, on purpose.
**They are closed now**, by the separate pass this section asked for, together with the fifth site
this run recorded under [Recall limits this run declares](#recall-limits-this-run-declares) rather
than in the table here. The deferral reasoning is kept below in the past tense, because it states
what that pass had to answer.

| Site | Probe as this run left it | Defect |
|---|---|---|
| `plugins/docs-hygiene/skills/audit-noise/SKILL.md` | `git status --porcelain \| grep -E '\.md"?$' \| head -10 \|\| echo "none"` | fallback unreachable |
| `plugins/docs-hygiene/skills/audit-progressive-disclosure/SKILL.md` | same shape, `grep '\.md$'` | fallback unreachable |
| `plugins/code-tidying/skills/dissolve-comments/SKILL.md` | same shape, `awk` plus an extension `grep` | fallback unreachable |
| `plugins/code-tidying/skills/audit-comment-residue/SKILL.md` | same shape, `-z` parse plus an extension `grep` | fallback unreachable |
| `plugins/docs-hygiene/skills/compress/SKILL.md` | `{ git status --porcelain \| grep '\.md$' \|\| echo "none"; } \| head -10` | fallback reachable, both meanings collapse |

The fifth row is not a site this run normalized and then got wrong. Its brace group predates the
sweep, from `docs-hygiene` 0.15.0 in
[#2814](https://github.com/melodic-software/claude-code-plugins/pull/2814), and it puts the filter
*inside* the group, so the group's exit status is `grep`'s: 1 when git failed and 1 when nothing
matched. Its fallback did run, and printed `none` for both meanings.

These are filtered probes, not status probes, and the difference is not cosmetic. Their fallback
read `none`, which for a filtered list is the *correct* answer when the filter matches nothing, so
an empty render was not a misreading the way an empty working-tree status is. Making the fallback
reachable without more would have made `none` fire on probe failure too, collapsing "no matching
files" and "git did not run" into one string and creating the ambiguity the 25-site fix exists to
remove. Fixing them properly meant giving each a distinct failure token and re-deciding what its
label asserts, per skill, which is why this run recorded them open rather than doing it badly.

This section proposed one candidate form, from
`plugins/docs-hygiene/skills/audit-derivability/SKILL.md`:
`s=$(git status --porcelain 2>/dev/null) && printf '%s\n' "$s" | … | head -20 || echo "(status
unavailable)"`. Capturing first makes the probe's own exit status the head of an `&&` list, so a
failed probe short-circuits and the `||` fires; a successful probe with no matches runs the pipeline
and renders empty under a label that says `empty = none`. Both meanings survive, separately.
Verified by execution outside a repository: this form prints `(status unavailable)`, and the four
filtered probes print nothing.

**The pass did not take that candidate.** Capturing into `s` needs a `$` expansion, and
`plugins/playbooks/skills/skill-authoring/reference/precompute-context.md` requires a pre-compute
block to carry no `$` expansion other than a bare `$HOME`: an expansion leaves the composed block
unverifiable to the worktree-isolation guard, and the skill then fails to load from an isolated
agent (`session-flow` 0.17.16). `audit-derivability` demonstrates the binding, not a form to copy.
All five sites first took an equivalent that adds no `$` at all and heads the same `&&` list with a
status-only run of the site's own probe. **That form was itself wrong, and is no longer what
ships.** It is correct only without `set -o pipefail`; under pipefail the `&&` list inherits the
pipeline's status, which both `grep` matching nothing and `git` taking SIGPIPE at the cap make
non-zero, firing the failure token on a healthy probe. `docs-hygiene` 0.21.24 and `code-tidying`
0.14.13 replaced it with the pipeline inside a brace group closed by `:`, a command that cannot
fail, which is correct under both settings:

```text
git status --porcelain >/dev/null 2>&1 && { git status --porcelain 2>/dev/null | … | head -N; :; } || echo "(git status unavailable)"
```

The probe runs twice, which is the price of not capturing it. No line holds a `$` expansion after
the change: the `$` characters that remain are end-of-line anchors in single-quoted `grep` patterns
and field references in single-quoted `awk` programs, all pre-existing and none of them expanded by
the shell. Each site kept its own filter, its own cap and its own label noun; each label gained
`empty = none`; the failure token is the `(git status unavailable)` string the normalized status
probes already use. Verified by execution in three states per site, **without pipefail**: outside a
repository each prints the token, inside a repository whose dirty files do not match the filter each
prints nothing, and above the cap the cap holds with no spurious fallback. That qualifier is the
whole lesson: the same three states under pipefail print the token in two of them, which is what
0.21.24 and 0.14.13 had to correct. A verification that fixes the shell's options and does not say
so proves less than it appears to. Landed in `docs-hygiene` 0.21.23 and `code-tidying` 0.14.12,
which also carry the two `detect.test.sh` extractors that read these lines out of `SKILL.md` and
were anchored on the old labels.

One filtered probe with the unreachable shape remains open, and is out of this section's scope
because its probe is not `git status`:
`plugins/docs-hygiene/skills/rename-references/SKILL.md` renders rename pairs as
`{ git diff --name-status -M HEAD; git diff --cached --name-status -M; } | grep '^R' | head -15 || echo "none"`.
Same binding defect, different probe, and `grep '^R'` matching nothing is the ordinary case there.
Recorded, not fixed.

The per-cluster detail for the sites that were normalized is in the pull request that carries this
file.

## Verified, not applied

Every entry below carries a Tier 0 site roster and a proposed remedy. None proposes a new artifact:
this sweep created none and none of these needs one. They are ordered by the harm of leaving them.

### Factual defects

Four of the factual defects this survey found were applied in the same change set and so are not
rostered here: `auto-mode-dropped-class-roster`, `songwriting-title-type-attribution`,
`songwriting-section2-load-list-gate`, and `check-skill-trigger-fence-line-reference`. Their
per-site detail is in the affected plugins' changelogs — `claude-config`, `songwriting`, and
`docs-hygiene` respectively — and in the pull request that carried them. An earlier draft said they
were "listed under Applied above"; that section covers the owner edits, the inline floor, and the
call-site normalizations, and names none of these four, so a resumer following the pointer found
nothing.

The last of those is worth recording as a worked example of this file's own decay rule. It was
written here as an open cluster of four *prose* surfaces, and the count was short: a fifth carrier
sat in a script header, `plugins/docs-hygiene/skills/audit-noise/scripts/emit-findings.sh`, which a
`*.md`-only grep could not see. All five are closed, but only four were recorded as such at the
time. The cluster was four prose surfaces citing
`plugins/skill-quality/scripts/check-skill.sh:414` as the hard FAIL for a dropped trigger phrase.
Line 414 is inside a comment stating that a trigger **move** WARNs and never blocks; the `err` is at
462, so each citation asserted the reverse of the line it named. Between this file being written and
being merged, `main` fixed one of the four in `detector-findings` 2.7.1, independently and by the
same reasoning, which left the roster at four wrong within hours. The remaining three were fixed
here, on `main`'s remedy: name the check, never the line. A line number in a citation is the decay
rule's clearest case — it is wrong the moment anything above it moves, and nothing tells you.

What remains:

| Cluster | Sites | Defect |
|---|---|---|
| `overengineering-branch-identity-mechanism` | 6 files in `overengineering` | `delta`'s copy omits the normalize-then-validate step its siblings require, so an environment supplying `refs/heads/<name>` makes `delta` key a different home than the audit it composes, and the lane reports no delta forever, silently |
| `bugs-scan-git-clean-mechanism` | 1 file | "a fresh clone or a `git clean` erases" the memory tier. The tier is self-ignoring by contract, and plain `git clean` does not remove ignored files. The conclusion is right, the mechanism named is not |
| `babysit-prs-isolation-account` | 1 file | `plugins/source-control/skills/babysit-prs/SKILL.md` asserts the form-based account of the worktree-isolation refusal ("a git-bearing compound command") that `session-flow` 0.17.16 refutes in favour of a `$`-expansion trigger. Pre-existing on `main`; this sweep neither created nor worsened it |
| `detector-findings-tier-self-restatement` | 1 file | `docs/conventions/detector-findings/README.md` declares the severity vocabulary "is not this doc's to define", routing it to `plugins/review/context/severity.md`, then restates CRITICAL's tier test in eight crosswalk rows. (An earlier draft of this row attached the quote "This doc never restates it" to severity; that sentence is about the findings-file shape, a different subject in the same file. The observation stands, the quote did not.) |

Two encapsulation defects the earlier L4 lane's roster of 34 did not carry, both in `docs/**` citing
a plugin skill by filesystem path, which ADR 0018 rules out because an installed plugin may not be
on disk. One is fixed in this change set; the second, a table cell in the same file linking
`babysit-prs`, is recorded here and needs its own pass.

### Unowned contracts

| Cluster | Sites | Proposed owner |
|---|---|---|
| `read-only-artifact-write-reconciliation` | 7 audit skills | `docs/PLUGIN-PHILOSOPHY.md` "Naming". Seven skills reason from one unowned premise to two opposite bare-invocation defaults, and the repo has already shipped a detector that "quietly violated its own skill's stated hard rule" on it |
| `destructive-consent-floor` | 5 skills | `docs/PLUGIN-PHILOSOPHY.md` "Naming", which already uses "explicit user override" and "never under a blanket approval" without defining either. The fleet holds two live rules on whether a flag is consent, for the same operation |
| `worker-return-is-synthesis` | 13 files, 8 plugins | `docs/PLUGIN-PHILOSOPHY.md` "Delegation mechanics". The re-verification scope has already forked: four sites require every finding re-verified, one requires only load-bearing claims |
| `dispatch-prompt-part-contract` | 6 files | The same section, which carries a four-part list that matches no consumer's. Four, five and six-part contracts are all in force |
| `fanout-concurrency-cap` | 9 numeric sites | The same section, which has no concurrency content at all. Nine caps from 1 to a dozen with five grounds and no owner, while a fleet audit already treats "a numeric concurrency cap" as satisfying a required posture |
| `config-cascade-unreadable-layer` | 5 setup skills | `docs/conventions/config-cascade/`, whose resolution algorithm covers a malformed layer and not an unreadable one. Five skills invented a variant; one file states it twice, differently |
| `settings-scope-write-posture` | 3 audit skills | `docs/PLUGIN-PHILOSOPHY.md` "Configuration ownership and scope". Two owner docs exist and each is scoped so it binds none of the three sites |

### In-plugin consolidations

`discovery` (six clusters, including a dispatch spoke pair sharing 26 sentences whose own preambles
both say "This file does not restate it"), `session-flow` (a self-ignore guard restated five times
inside one plugin whose sibling already cites it correctly), `review` (a diff-base ladder stated four
times in three incompatible shapes, and a hardened git incantation byte-identical in three agents
that no drift check can see), `work-items` (a role-label rule whose loud-warning mandate a prior PR
set out to drop and dropped in only two of six files), `knowledge`, `claude-ops`, `code-tidying`,
`toolchain`, `github`, `prototype`, `context-guard`, `ai-briefing`, `repo-hygiene`, `adhd`,
`codebase-health`, `implementation`, `testing`, `verification`, `playwright`, `firecrawl`,
`playbooks`, `context7`, `dometrain`, `miro`, `actionlint`, `guardrails`.

## Contradictions found

Pass B's most valuable output, and the part no grep could have produced. Each is two statements of
one truth that have drifted into saying materially different things. Recorded whether or not the
surrounding cluster was rostered.

1. **A flag is consent, and a flag is never consent, for the same operation.** `repo-hygiene:clean`
   and `disk-hygiene:clean` both say a flag is never confirmation; `repo-fleet-hygiene:apply` treats
   `--yes` as non-interactive consent. The operation is identical: deleting a merged local branch.
   The divergence was seen at plugin level and recorded there, but nothing reconciles the two rules
   and neither skill's body mentions the other's.
2. **A byte-identical-by-contract block was not byte-identical.** Fixed in this change set.
3. **Are unscoped `.claude/rules/` visible inside a subagent?** One plugin says no and marks the cell
   `(measured)`; the measurement's own fixture contained no unscoped rule, and the same file's README
   generalizes correctly to deferred surfaces only. Another plugin quotes the official docs saying
   yes. The cell is load-bearing for the first plugin's central design argument.
4. **Do skill bodies come back after `/compact`?** Two files say yes with a specific per-skill and
   combined token budget sourced to the skills docs; two say no. Four copies of one table.
5. **The freshness window is "this session" in a declared home and "this turn" in five of its own
   consumers**, inside one skill. A grep run 150 turns ago satisfies one and fails the other.
6. **Fork inheritance is asserted as settled in two places and recorded as contested in a third**,
   with the third naming a specific tracked refutation of the runtime behavior.
7. **Whether a bare `audit` may write a file, answered both ways from one premise**, by skills that
   do not acknowledge each other exists.
8. **User-scope settings are never written in place, except by the skill whose job is to write
   them.** Two audits state the prohibition as a general rule about dotfile-managed trees; a
   model-invocable third skill writes user scope and recommends it, with its own mitigation.
9. **"GATE" means ask in two skills and means prove-then-act-without-asking in a third**, all about
   branch deletion.
10. **"Tier 0" names four mutually incompatible ladders**, three of them using the identical
    `Tier 0..3` surface form on different axes. The fix is naming, not extraction.
11. **The nesting-depth version history stops at v2.1.219 in five of six surfaces**, none of which
    carries an as-of date or a recheck trigger, which the upstream-drift convention's required parts
    forbid. Only one records the cap change that landed after.
12. **Who owns "is the skill listing overflowing?"** Three files name three different answers, two of
    which compute the same thing from the same settings and reference each other nowhere.

## New refusals, recorded so nobody re-opens them

Beyond the predecessor's 13. Each was resolved against the real files and refused with cause.

- **Distilled book corpus**, 155 rows. `plugins/songwriting/context/pat-pattison/research/**` is
  printed Pat Pattison text blockquoted across digest files, each carrying its own citation.
  Out of survey scope by the skill's own rule, and refused independently by the primary-source gate.
- **Measurement-record specimens**, 27 rows. Every cited line in
  `docs/specs/d1-model-already-knows-measurement.md` falls inside a 185-row table of verbatim
  sentences quoted from across the fleet, each row naming its own source path. Editing the specimens
  falsifies the number the record exists to publish.
- **ADR bodies**, 4 clusters. Treated as immutable throughout. In every case the ADR is the quoting
  party and already carries exact attribution, so citation was the existing state.
- **Generator-owned twins**, 6 rows, emitted from an adapter README template.
- **The `discipline` family's shared method pointer**, 15 skill bodies citing one plugin-level file
  (`git grep -l re-anchor-audit-correct -- 'plugins/discipline/skills/*/SKILL.md'`), the wording
  varying between them rather than one reproduced sentence. An earlier draft said 14, which matched
  neither the family total nor the identical-sentence subset.
  Shared voice is not duplication; only a reproduced rule counts.
- **CI-registered clusters**: the contract-clause registry, the standards contract mirror, the
  plugin artifact protocol, the zone-combination inline floor, the discovery agents' tool-honesty
  block. Each has a live gate that deduplication would break.
- Plus roughly 120 further per-cluster refusals across the eight triage batches, each recorded with
  its form and ground in the pull request that carries this file.

## Open remainder after the encapsulation close

Recorded, not fixed. A later pass adjudicates these; this section exists so it does not have to
re-find them. Stamped 2026-08-28 and subject to the decay rule at the top of this file.

### Twelve citations the encapsulation close created and never rostered

The pass that closed the encapsulation floor wrote a convention CHANGELOG entry for each fix, and
every entry quotes the path it removed. Those quotes are themselves `docs/**` citations of the exact
shape the pass was sweeping, created by the sweep, counted by nobody. **Verified against
`origin/main`, twelve of them:**

| File | Lines |
|---|---|
| `docs/conventions/config-cascade/CHANGELOG.md` | 12, 13, 14 |
| `docs/conventions/detector-findings/CHANGELOG.md` | 44, 57 |
| `docs/conventions/loop-lane/CHANGELOG.md` | 69 |
| `docs/conventions/native-references/CHANGELOG.md` | 16, 17, 18 |
| `docs/conventions/permission-rule-hygiene/CHANGELOG.md` | 14 |
| `docs/conventions/topic-docs/CHANGELOG.md` | 11, 12 |

One correction to the roster this was handed as: the `loop-lane` row was reported at `:14`, which is
where it sat when the pass wrote it. Release `9.1.0` landed above it, and the citation is at `:69`
today, inside the `9.0.2` entry. That is the decay rule firing on a record less than a day old, and
it is why a later pass must **re-derive by the text and never by these numbers.**

**The twelve are disjoint from the three this file already counts, confirmed by differencing the
tree at the fix commit's parent.** Before that commit, exactly three lines in
`docs/conventions/*/CHANGELOG.md` cited a plugin skill by path: two in `detector-findings` and one in
`loop-lane`. Those are the "three dated changelog entries that quote a citation as it stood" in the
kept set. Every one of the twelve above was written by the fix commit itself, so **the arithmetic is
16 fixed and 35 kept, not 16 and 23**, and the changelog-evidence class is fifteen rather than three.

**All twelve are keep-correct** under the test now written into
[ADR 0018](../adr/0018-treat-the-plugin-as-the-encapsulation-boundary-for-skill-citation.md)'s
amendment: each is a dated changelog entry whose whole claim is what a named file contained on that
date. Nothing here needs an edit. What is missing is the judgment, and a pass that re-derives this
shape finds twelve rows nobody ruled on and has to adjudicate them from scratch to learn they were
fine. The general lesson is worth more than the twelve rows: **a sweep that documents each fix by
quoting the citation it removed manufactures new instances of the shape it is sweeping,** so its own
output has to be swept before the count is closed.

**The pass writing this section did the same thing, deliberately, three more times.**
`docs/conventions/plugin-data-report-keying/CHANGELOG.md` 1.0.1 quotes the three pins it dropped, so
the class stands at eighteen. They are keep-correct on the same ground as the twelve, and they are
declared here rather than left for the next re-derivation to find. That is the only discipline
available: the alternative is a changelog entry that does not say what it changed.

### Three trees the sweep excluded by fiat

The sweep's encapsulation floor scoped itself to `docs/**` and then dropped five subtrees. Two of the
exclusions are defensible and stated as such: `docs/SKILL-CHEAT-SHEET.md` (162 citations, generated
and CI drift-checked, so an edit is reverted by its generator) and `docs/upstream/` (vendored, not
this repo's prose to style). **The other three rest on nothing.** `docs/specs/` (roughly 265 sites),
`docs/topics/` (roughly 43) and `docs/adr/` (25) were excluded on the assertion that "the dated
records under `docs/specs/`, `docs/adr/` and `docs/topics/` are out of scope by the same test", and
no carve-out in ADR 0018 authorizes any of it.

The assertion is *probably* right and is *not* established. Under the amendment's test most of that
population is evidence: dated records, and ADR bodies that quote what they cite. But "most of a
265-site population is evidence" is a hypothesis about 265 sites, argued from the tree a citation
lives in rather than from what the citation does, which is the form-over-function reasoning the
amendment rejects. A tree-shaped exclusion is a carve-out; ADR 0018 grants none. Either the pass that
resumes this samples the three trees and records the ruling, or the ADR gains the carve-out
explicitly. It should not stay a habit.

Counts re-derived for this record and rounded deliberately: the exact figure moves with the search
expression, and per this file's own recall-limits discipline none of these numbers is a total.

### A stale record found in passing, not an ADR matter

`docs/MIGRATION-PLAYBOOK.md:943` carries the `dometrain` security-review record: "Reviewed at
`0.1.0`; a version bump adding a new trust surface re-triggers this review." **The plugin's manifest
reads `0.2.7` today** (`plugins/dometrain/.claude-plugin/plugin.json`, confirmed against
`origin/main`). The trigger has had every opportunity to fire across those bumps and the review was
never re-run, so the record asserts a currency it does not have.

This is not a citation defect and does not belong to the encapsulation lane. It is logged here
because the encapsulation pass kept that record's five file-and-frontmatter citations *on the
strength of* its re-trigger clause, which means the clause was read and its own condition was not
checked. Whoever re-runs the review owns the record; the citations are fine either way.

## The L4 roster is closed, all 34 rows, and Group 2 was never open

A pass dispatched to fix the predecessor roster's eight Group 2 rows found **nothing to fix**. All
eight were closed on 2026-08-26 by
[#3380](https://github.com/melodic-software/claude-code-plugins/pull/3380) (`6c7a1032`) — the same
commit that wrote the roster. Its own message says so in a clause nobody carried forward: "eight
citations written with an implied base of the plugin root while the real base was `reference/` —
none of them resolved for any reader". It fixed them and left the roster's summary line asserting
that all 34 still resolved to the citing text the audit quoted.

**That one stale sentence has now caused four passes to re-derive the same roster**, this one
included. It is the most expensive line in the sweep record, and it is expensive precisely because
it sits above an inventory whose own decay rule says the status column is its weakest part. The
lesson is not about these eight rows: **a record that fixes findings and updates its own summary in
the same commit must update the summary, or the summary outranks the fix for every later reader.**

### The eight, verified against the live tree

Anchored on text, never on the rostered line numbers, which are stale in all three files. Each was
rewritten from the bare `skills/<s>/<path>` form to the anchored
`${CLAUDE_PLUGIN_ROOT}/skills/<s>/<path>` form clause 3 requires:

| # | Citing file | Cited surface | Now at |
|---|---|---|---|
| `V-sc-01` | `plugins/source-control/reference/config-resolution.md` | `babysit-loop` `promotion-evidence-resolution.md` | `:189` |
| `V-sc-02` | `plugins/source-control/reference/review-discipline.md` | `babysit-loop` `pre-escalation-dispatch.md` | `:314` |
| `V-sc-03` | `plugins/source-control/reference/review-discipline.md` | `babysit-prs` `safety.md` | `:178` |
| `V-sc-04` | `plugins/source-control/reference/review-discipline.md` | `babysit-prs` `safety.md` | `:278` |
| `V-sc-05` | `plugins/source-control/reference/review-discipline.md` | `babysit-prs` `independent-resolution.md` | `:311` |
| `V-disc-04` | `plugins/discovery/reference/topic-docs.md` | `explore` `reference/dispatch.md` | `:88` |
| `V-disc-05` | `plugins/discovery/reference/topic-docs.md` | `research` `context/dispatch.md` | `:89` |
| `V-disc-06` | `plugins/discovery/reference/topic-docs.md` | `trace-intent` `context/dispatch.md` | `:90` |

All seven distinct targets exist on disk. Group 3's two heading anchors are closed by the same
commit, dropped to file-level links, so **the 34-row roster stands at 34 closed, 0 open**: 22 of
Group 1 plus all of Groups 2 and 3 by #3380, and `V-review-13` and `V-review-14` by
[#3475](https://github.com/melodic-software/claude-code-plugins/pull/3475).

Derived twice with unrelated expressions, per this file's own discipline. First by matching the
roster's quoted bare-form text at each citing path: zero matches remain, and a regex for any
`skills/<s>/(reference|context|actions|evals|templates)/` token not prefixed by
`${CLAUDE_PLUGIN_ROOT}` returns zero across both plugins' `reference/` trees. Second, without
reference to the roster at all, by resolving **every** citation token in every plugin-level
`reference/`, `context/` and `agents/` tree and every plugin README against the base its own form
implies: **52 tokens, 0 clause 3 failures.** That population strictly contains the eight, so the
second derivation confirms the first without sharing its search expression.

### Judgment: ADR 0018 barely reaches this class, and its encapsulation half does not

Recorded because the dispatch asked for it explicitly and because tidying these rows under the wrong
clause would have been easy.

**Group 2 was never an encapsulation defect.** The roster says so itself: "Legal as citations under
ADR 0018, defective as paths." Clause 1 names this exact citing surface — it covers "plugin-level
`context/`, `reference/` and `agents/` docs" reaching a sibling skill's private files — and
legalises it. Clause 2 cannot reach them: both files ship inside one plugin, so the runtime absence
that motivates clause 2, and the fetched-contract problem the amendment builds on it, cannot occur.
A consumer enabling `source-control` gets `reference/review-discipline.md` and
`skills/babysit-prs/reference/safety.md` or gets neither.

So **only clause 3 reaches Group 2**, and clause 3 is a resolvability rule, not an encapsulation
rule. The amendment's fix-an-address / keep-evidence test does not apply either: that test divides
clause 2 applications, and these are not clause 2 matters. Had the eight still been open, the remedy
would have been the path form and nothing else — no routing to a slash invocation, no promotion of
content to a shared location. **Intra-plugin genuinely is a different case, and the file that says
so is the ADR's own correction 1**, which withdrew the bare-relative breakage claim as a category
error and named this narrower shape as the real defect: an implied base of the plugin root against a
real base of the citing file's directory.

The one clause that earned its keep here is the ADR's warning that "proximity did not prevent
them" — eight of the ten non-resolving citations in the corpus were intra-plugin, inside the case
the decision legalises. Legalising a citation class and requiring it to resolve are separate
obligations, and only the second one had teeth in this set.

### What was deliberately not done

No `plugins/**` file was edited, so **no plugin version bump and no plugin CHANGELOG entry belong to
this pass**. A bump describing a diff that does not exist would be a worse record than none.

The predecessor roster's tables were left verbatim. Its inventory is the part its decay rule says
cannot be re-derived without re-running the audit, and two earlier passes (#3474, #3475) closed rows
without touching that file. This pass follows them: the only edit there is an additive closure stamp
above the tables, correcting the false summary sentence in place rather than rewriting any row.

## Recall limits this run declares

A finding count read as a defect count is worse than no count. An adversarial verifier audited the
Pass A detector itself; the measurements below are its, not the detector author's.

**Every number in this section is unreproducible from this repository.** The Pass A detector was a
session tool — a shingling script, a triage driver and a batch runner, written in a scratch
directory and deliberately not committed, because a one-run measurement instrument is not a
marketplace artifact and shipping it would create a surface nobody maintains. So these figures
cannot be re-derived by running anything in the change set; they are a record of what one run
measured, not a claim any later reader can check. Treat them the way the decay rule at the top of
this file treats everything else: as a pointer to re-do the work, never as a fact to cite. A pass
that needs these numbers should rebuild the instrument and re-measure, and should expect its own
figures to differ.

- **The hard-wrap claim is real and is most of the yield.** Against a control paragraph re-wrapped
  at 62, 72 and 120 columns, the predecessor's line-anchored method shares **zero** lines at every
  width and the shingle pass recovers **100%**. 58% of the clean roster (316 of 542 rows) has no
  cross-file shared 8-word normalized line at all, so those rows were unreachable before. Both
  positive controls were recovered with one site *more* than the predecessor found.
- **K=12 was audited and held.** The actionable count is nearly K-invariant (655 / 639 / 598 at
  K=8/12/16) but linkage is not: K=8 produces 4.3 times the file-pairs for the same cluster count,
  which is chaining rather than new duplicates. K=12's pair set strictly contains K=16's.
- **Precision is bimodal.** On a uniform sample of the roster, roughly 65% false positive. On the
  in-scope remainder, after removing quoted external material, distilled teaching material and
  measurement-record specimens, roughly 12%. The dominant false-positive class is quoted external
  material, which the scope rules exclude and the detector did not.
- **Three detector defects, all found by audit rather than by use.** A prose *mention* of
  `BEGIN GENERATED` opened a region that never closed, making 72% of the predecessor sweep record
  invisible to the pass. The known-refused pre-filter's regexes were broader than the refusals they
  cite and suppressed four recorded-open remediations; all four were separately owned by the
  re-verification lane, so nothing was lost, but the filter cannot be trusted in either direction.
  And union-find chains blocks transitively, so one site row in eight is labelled by a longer
  span than it actually shares. The triage contract absorbed all three by requiring every row be
  resolved against the real files before judgment, which is why the roster survived them.
- **Pass A's floor is 12 words and 25 words of block length.** Below that the detector is silent by
  construction. The `orchestrator-owns-the-loop` cluster was found only by Pass B because its shared
  span is six words.
- **Pass A excludes `evals/` wholesale**, which drops eval data and also seven authoring surfaces in
  the `evals` plugin. It excludes `vendor/`, `fixtures/`, `CHANGELOG.md`, `docs/upstream/`, YAML
  frontmatter (and so every skill `description:`), and `BEGIN GENERATED` regions. It does **not**
  exclude the `<!-- native-surfaces:start -->` marker family, so one generated view reached triage.
- **Pass B is reading-bounded and candidate discovery still began with keyword greps.** A paragraph
  asserting one of its truths in vocabulary none of the greps used is outside every count.
  Two of the four axis workers had no subagent tool and read serially; one covered 55 of roughly
  1,335 candidate files, the other 41.
- **Trees Pass B did not open**: `prompts/loops/` (the largest body of restart-and-resume prose in
  the repo, squarely on one axis), most of `plugins/work-items/`, `plugins/autonomy/reference/
  runner/`, `plugins/machine-health/`, `plugins/event-storming/`, `plugins/mcp-tools/`, and every
  plugin's `agents/` directory except three.
- **Three counts are floors, not totals.** The `worker-return-is-synthesis` roster at 13 files and
  the `read-only-artifact-write-reconciliation` roster at 7 both come from partial reads; neither
  could shrink, both could grow. The encapsulation roster is the third, and it grew: it recorded
  **two** `docs/**` surfaces citing a plugin skill by filesystem path, which is what the survey
  found, and a later pass found three more of the identical shape that were on no roster. **They
  are closed now**, by a pass that re-derived the shape across all of `docs/**` rather than
  trusting the roster. That pass resolved **16 citations at 12 sites in 8 files**, every one
  rewritten to the `/plugin:skill` public invocation on the
  [`loop-lane` 9.0.1](../conventions/loop-lane/CHANGELOG.md) form. Beyond the five named above it
  reached `docs/PLUGIN-PHILOSOPHY.md`'s Convention registry (the dynamic-context precompute row
  this very change set added, written in the bare plugin-relative form ADR 0018 names as its real
  defect class), two conformance rows in `docs/conventions/config-cascade/README.md`, one in
  `docs/conventions/pre-pr-ordering/README.md`, three in
  `docs/conventions/native-references/README.md` (two of them `V-review-13` and `V-review-14`, the
  last two rows of the predecessor's 34-item L4 roster still open by that roster's own text test:
  re-derivation found 22 of its other 32 rows already closed, twelve of them by #3380 itself, so
  what remains of the 34 is its eight Group 2 intra-plugin path-form defects, untouched here — a
  claim a later pass refuted: those eight were closed by #3380 too, see
  [the L4 roster's closure](#the-l4-roster-is-closed-all-34-rows-and-group-2-was-never-open)), and
  one adopter-row detail
  in `docs/conventions/detector-findings/README.md`. **What remains is a judgment set, not a
  backlog**: 23 further in-shape citations were kept with reasons, because each is evidence about
  this checkout rather than an address for an obligation. They are the three worked examples in
  `docs/conventions/plugin-data-report-keying/README.md`, the four location cites in
  `docs/conventions/shell-test-helpers/README.md` (whose subject *is* where the duplicate copies
  sit), the four `scripts/` entry-surface pointers in `docs/NATIVE-SURFACES.md` and
  `docs/CLOUD-SESSIONS.md` that the public-surface contract's own carve-out permits, two observation
  rows in the `NATIVE-SURFACES` generated region (authored in
  `docs/native-surfaces/records.json`, so a hand-edit of the rendered view would be overwritten and
  the store's copy is the same citation, not a second one), that store's own note on where the
  overlap seed file lives, the boris-baseline evidence row in `docs/PLUGIN-PHILOSOPHY.md`, the five
  file-and-frontmatter cites inside `docs/MIGRATION-PLAYBOOK.md`'s dated `dometrain` security-review
  record (each asserting what a named file contains, under a record that re-triggers on a version
  bump), and three dated changelog entries that quote a citation as it stood.
  `docs/SKILL-CHEAT-SHEET.md` is
  generated too, and the dated records under `docs/specs/`, `docs/adr/` and `docs/topics/` are out
  of scope by the same test.
- **A fifth filtered probe exists and is not in the four-site table above.**
  `plugins/docs-hygiene/skills/compress/SKILL.md` already binds its fallback inside the brace group,
  so unlike the four it *is* reachable — but its fallback is `none`, which collapses "no matching
  files" and "git did not run" into one string. Same ambiguity, arrived at from the other direction.
  A pass that fixes the four should fix this one too. **It did**: the follow-up pass recorded under
  [Call-site normalizations](#call-site-normalizations) took all five, and the table there now
  carries this site as its fifth row.
- **The `1,536`-character listing cap appeared in 14 tracked files when this was measured**; the
  batch that surfaced it saw three. A later count during this change set's own review found 16, and
  the population keeps moving. That is the point of the paragraph rather than an exception to it:
  any pass acting on that cluster must re-derive against the full population, never cite this
  number.
