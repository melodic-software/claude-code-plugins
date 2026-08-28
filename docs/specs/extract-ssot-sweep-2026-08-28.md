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
`setup-never-writes-boundary` as "41 instances, 34 edited"; re-measurement found the 41 exact and the
edit set down to **one**, because 33 of the 34 had landed three days before the audit that recorded
them. And the em dashes it located at `persist-findings.md:1` and `:5` were still present, the second
having moved to `:16` when #3380 inserted a `## Contents` index above it.

## Contents

- [What this run did differently](#what-this-run-did-differently)
- [Applied in this change set](#applied-in-this-change-set)
- [Verified, not applied](#verified-not-applied)
- [Contradictions found](#contradictions-found)
- [New refusals, recorded so nobody re-opens them](#new-refusals-recorded-so-nobody-re-opens-them)
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
| Pass B | Four concept-axis workers reading for paraphrase clusters sharing no verbatim phrase | 12 survivors and 15 recorded contradictions, none of them reachable by grep |

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

`docs/conventions/loop-lane/README.md` §6 requires the rate-limit-guard floor to be **byte-identical**
across its carriers, and the predecessor refused `rate-limit-guard-floor-inline` on exactly that
ground. Hashing the five carriers showed three distinct texts.

The drift was one-directional and traceable: `git log -S` returns two commits, both per-plugin
de-slop shards, which edited the three lane bodies away from the anchor. One of the two edits
replaced a clause-joining dash with a comma, producing a comma splice in a sentence whose whole job
is to state a causal link. The em-dash campaign did not know the block was frozen.

All five carriers now hash identically, on a form that is both em-dash-free and grammatical, so the
byte-identity contract and the house style are satisfiable together. The predecessor's refusal rested
on a premise that was false at the time it was written: the convention requires identity, so any
difference is the bug, which makes this the opposite of a refusal.

### Call-site normalizations

Each of these keeps its operable text inline. Plugins ship without this repository, so a
`plugins/**` site cannot cite a `docs/**` owner at its own runtime; the return is drift elimination
and one greppable canonical string, never line reduction.

The per-cluster detail, including which sites were deliberately skipped and why, is in the pull
request that carries this file.

## Verified, not applied

Every entry below carries a Tier 0 site roster and a proposed remedy. None proposes a new artifact:
this sweep created none and none of these needs one. They are ordered by the harm of leaving them.

### Factual defects

| Cluster | Sites | Defect |
|---|---|---|
| `auto-mode-dropped-class-roster` | `claude-config` audit-permission-state | A recap of upstream's dropped-allow-rule classes elides `Monitor` and then counts "four documented classes" from the elision. Upstream added the category in v2.1.236. A `Monitor` allow rule is dropped on auto-mode entry and reported under none of the audit's classes |
| `overengineering-branch-identity-mechanism` | 6 files in `overengineering` | `delta`'s copy omits the normalize-then-validate step its siblings require, so an environment supplying `refs/heads/<name>` makes `delta` key a different home than the audit it composes, and the lane reports no delta forever, silently |
| `check-skill-trigger-fence-line-reference` | 4 prose files | Four surfaces cite `check-skill.sh:414` as the hard FAIL for a dropped trigger phrase. Line 414 is a comment saying trigger moves WARN; the FAIL is at 462. The citation asserts the opposite of what the cited line says |
| `songwriting-title-type-attribution` | 4 files | Four sites attribute a seven-title-type taxonomy to Pat Pattison. The owner file's own heading says the taxonomy is unaudited and that "the count 'seven' is ours, not Pat's". One site carries that warning and contradicts it five lines later; a shipped prompt template asserts it with no caveat |
| `songwriting-section2-load-list-gate` | 3 skills | Three skills state a filter's mandatory load list as two files. The filter's own Reference line names seven. Five required files are silently dropped at the gate a prior release added to fix a production failure |
| `bugs-scan-git-clean-mechanism` | 1 file | "a fresh clone or a `git clean` erases" the memory tier. The tier is self-ignoring by contract, and plain `git clean` does not remove ignored files. The conclusion is right, the mechanism named is not |
| `detector-findings-tier-self-restatement` | 1 file | `docs/conventions/detector-findings/README.md` declares "This doc never restates it" about the severity vocabulary and routes tier decisions to `review`'s owner, then restates CRITICAL's tier test inside its own crosswalk table |

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
- **The `discipline` family's shared method pointer**, 14 sites, all citing one plugin-level file.
  Shared voice is not duplication; only a reproduced rule counts.
- **CI-registered clusters**: the contract-clause registry, the standards contract mirror, the
  plugin artifact protocol, the zone-combination inline floor, the discovery agents' tool-honesty
  block. Each has a live gate that deduplication would break.
- Plus roughly 120 further per-cluster refusals across the eight triage batches, each recorded with
  its form and ground in the pull request that carries this file.

## Recall limits this run declares

A finding count read as a defect count is worse than no count. An adversarial verifier audited the
Pass A detector itself; the measurements below are its, not the detector author's.

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
- **Two counts are floors, not totals.** The `worker-return-is-synthesis` roster at 13 files and the
  `read-only-artifact-write-reconciliation` roster at 7 both come from partial reads; neither could
  shrink, both could grow.
- **The `1,536`-character listing cap appears in 14 tracked files**; the batch that surfaced it saw
  three. Any pass acting on that cluster should re-derive against the full population.
