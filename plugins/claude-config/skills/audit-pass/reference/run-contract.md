# audit-pass — the run contract

Finding identity, where the report lives, run state, resumability, the report schema, and the three
finding tiers with their properties. Every rule here is stated as a condition a test can assert.

Terms: a **run** is one invocation against one **target**; a **lane** is **one delegated invocation
at the finest filter that skill's own interface accepts**, never finer — the pass dispatches skills
and never reaches inside one, so a lane it cannot invoke is a lane it cannot have; the **scan set**
is the set of files a run reads. A surface is **live** when the
harness actually loads it for that target — read from `InstructionsLoaded` for the memory layer and
`/context` for skills, subagents, and MCP tools, never inferred from a filesystem walk alone. The
**live surface set** is every live surface at the moment a run starts; it can change without the tree
changing, because startup scope depends on the launch directory and on settings the tree does not
contain.

## 1. Finding identity

Prose judgements are undiffable. Identity is three parts, emitted machine-readably, and the third is
a **set** — because a cross-surface finding is about a relation between sites, not about one site
with a footnote.

```text
identity = (check, claim, sites)
sites    = sorted([(surface, anchor), …])   # one entry, or two for a pairwise finding
```

- **`check`** — fully qualified, `<plugin>/<skill>/<check>`. A bare check id is ambiguous across
  catalogs.
- **`claim`** — the check's canonical claim id plus its bound parameters, never free prose. Prose is
  a rendering of the claim, never the claim itself. **The template set comes from the delegated
  invocation's own output, never from the owning plugin's files** — this pass dispatches skills and
  never reads inside one, so a template set it could learn only by opening another plugin's catalog
  is one it can never learn, and requiring one would make every finding unemittable. An invocation
  that declares its templates is validated against what it declared. An invocation that declares
  none — the state of every delegated catalog today — is **claim-unqualified**: the pass binds
  `claim` to the check's own id with no parameters, and names that catalog in the report's coverage
  notes as owing a declaration. The fallback is coarse deliberately. It merges the distinct claims
  one check can make at one site onto a single identity, which is a precision loss the coverage note
  states rather than hides — and it is stable across runs, which is the one thing identity cannot do
  without.
- **`sites`** — the set of `(surface, anchor)` pairs the finding is *about*, canonically sorted by
  the byte ordering of `surface \x1f anchor`. **Sorted, because an ordered pair hashes X-versus-Y
  differently from Y-versus-X** — the same conflict would then be reported twice and would not
  survive a re-run that happened to visit the surfaces in the other order.

**A cross-surface conflict is ONE finding with two sites, never two linked findings.** SARIF reserves
separate results for "distinct occurrences … which could be corrected independently"
([§3.27.12](https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html), verified 2026-07-24).
A contradiction between two instruction surfaces is retired by fixing *either* side, so the two sides
are not independently correctable and are not two results.

**`primary_site` and `related_site` are presentation and remediation fields, OUTSIDE the hash.**
Which side a report leads with, and which side a `--fix` proposes editing, is a routing judgement —
project scope is editable, user scope is routed, managed policy never — and routing must be free to
change without renaming the finding.

### `surface` — the physical file, never the loading entry point

The canonicalized **physical file** the content lives in. Project-scope surfaces are repo-relative
POSIX paths with no leading `./`; user-scope and managed-policy surfaces are scope-prefixed
(`user:.claude/CLAUDE.md`, `managed:CLAUDE.md`). A report is then comparable across machines whose
absolute paths differ.

A symlink resolves to its target. **A target resolving outside the target root takes the
scope-prefixed logical form**, not the resolved absolute path — otherwise one shared rules file
symlinked into several repositories yields a different surface in each, and a suppression recorded in
one is invisible to the rest.

The file that imported the content is a **load edge**, not identity. The harness already emits the
split: an `InstructionsLoaded` hook payload carries `file_path` (the surface) alongside
`parent_file_path` (the edge it was loaded through) — verified on Claude Code 2.1.220.

**`load_path`** — the ordered chain of entry points through which a surface loaded — is carried as a
**non-identity** field for diagnosis, capped at **5 entries** and truncated with an explicit marker
beyond that. Observed import depth is four hops, so the cap admits the real maximum with one to
spare. It is outside the hash because the same file reached through a second import path is the same
content and the same defect.

### `anchor` — content-derived, granularity-discriminated, versioned

**Content-derived, never line-derived.** A line number shifts whenever anything above it changes,
churning the whole report on an unrelated edit. The anchor field name carries its algorithm version:
findings emit **`anchor/v1`**, and two sides compare on the **greatest anchor version both carry**
(the versioned-fingerprint discipline of SARIF
[§3.27.17](https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html), verified 2026-07-24).
That is the escape hatch: a later algorithm ships as `anchor/v2` alongside `v1`, and a record written
under `v1` keeps matching until both sides have moved.

Two granularities, discriminated by prefix:

| Granularity | Form | Identity reduces to |
|---|---|---|
| Excerpt | `e:<sha256(normalized_excerpt) truncated to 12 hex>:<n>` | `(surface, anchor, check, claim)` |
| Whole surface | `s:` — bare, no digest | `(surface, check, claim)` |

`<n>` is the 1-based ordinal of this excerpt among identical normalized excerpts in the same surface,
so a rule repeated verbatim three times yields three distinct anchors rather than one collision.

**A whole-surface finding is content-FREE by construction**, and that is the point: a finding about a
file *as a whole* — it should not exist, it is unreachable, it duplicates another — must not be
retired by editing a line inside it. SARIF grounds the same decomposition: "If the region property is
absent, the `physicalLocation` object refers to the entire artifact"
([§3.29.4](https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html), verified 2026-07-24).
The consequence must be stated where an operator will meet it: **an `s:` suppression survives every
edit to the file and does not survive a rename.** A rename is a new surface, so the suppression goes
stale and is re-reported — correctly, because a renamed file is a decision worth re-judging.

**An `s:` anchor in a two-site finding is a hard error, not a warning.** A pairwise claim asserts a
relation between two pieces of text; with no excerpt on a side there is nothing to show the operator
and nothing to fix, and every contradiction between the same two files would collide on one id.

A human-readable heading path (`## Rules > ### Naming`) travels alongside each site for legibility
only — the anchor is what identity compares.

### Normalization, v1

Applied to the excerpt before hashing. Case is **preserved**, because these surfaces carry code and
identifiers.

1. Strip trailing whitespace; collapse internal whitespace runs to one space.
2. Strip surrounding markdown emphasis markers.
3. **Preserve backticks and the text they delimit.** Stripping them would normalize `` `@README` ``
   to `@README` — literal text quoted *as an example of an import* would then hash identically to a
   real import, and a check about imports would fire on prose describing one.
4. **Strip block-level HTML comments that fall outside a fenced code block.** They are removed before
   the content reaches the model, so hashing them churns anchors over text no check ever saw. Inside
   a fence they are content and are kept.

### Two deliberate divergences from GitHub's implementation

Both are stated here together because they share one premise and one dissent, and reading either
alone makes it look like an ad-hoc exception. **Shared premise:** SARIF's decomposition of a result
into logical location plus partial fingerprints is adopted wholesale — that is where `sites`, the
region/no-region granularity split, and versioned anchor names all come from. **Shared dissent:** the
*input to the hash* is chosen for this corpus, not inherited.

1. **Pairwise identity hashes both sides.** GitHub keys a result on `locations[0]` alone, treating
   any further location as context. For a cross-surface contradiction the second surface is not
   context — it is half of what makes the finding true, and dropping it merges every conflict a file
   has with anything into one identity.
2. **Whole-surface identity is content-free.** CodeQL's `fingerprints.ts` hashes the file's first
   line when no region is available. That gives a file-level finding a content dependency it does not
   have, so an unrelated edit to line 1 retires a suppression about the file's existence.

### `finding_id`

**`sha256` of `check`, `claim`, then each site's `surface` and `anchor` in sorted order, all joined
by `\x1f`, truncated to 16 hex characters.** A finding carries one `finding_id` per anchor version it
emits, named for that version. **A suppression entry's key is the `finding_id` computed over the
anchor versions that entry itself stores**, which is what gives assertion 4.5 a single referent;
1.9's greatest-common-version rule then selects which of a run's ids is compared against it.

| # | Assertion |
|---|---|
| 1.1 | For a fixed tree **and a fixed live surface set**, `finding_id` is stable across runs, working directories, operating systems, and path separators. Liveness is named because it can change with no tree change at all, and an identity claim that ignored it would be false the first time a run started from a different directory. |
| 1.2 | Inserting an unrelated paragraph above a finding does not change its `finding_id`. |
| 1.3 | Every emitted finding validates against the report schema. When the invocation that produced it declared a claim-template set, the finding's `claim` id exists in that set and one that does not is a **hard error**. When the invocation declared none, `claim` is the check's own id with no parameters and that catalog is named in the coverage notes. Free prose in `claim` is a hard error either way — that is what stops prose leaking back in. |
| 1.4 | A pairwise finding discovered as (A, B) and the same finding discovered as (B, A) produce one identical `finding_id`. Swapping `primary_site` and `related_site` does not change it either. |
| 1.5 | Reaching a surface through a different import chain changes `load_path` and does not change `finding_id`. A `load_path` longer than 5 entries is truncated with an explicit marker rather than dropped silently. |
| 1.6 | A finding emitted with an `s:` anchor and two sites is rejected as a **hard error**. |
| 1.7 | Editing any line of a surface leaves an `s:` finding's `finding_id` unchanged; renaming that surface changes it. |
| 1.8 | An excerpt reading `` `@README` `` and one reading `@README` produce different anchors. Adding, editing, or removing a block-level HTML comment outside a fenced code block changes no anchor; the same edit inside a fence does. |
| 1.9 | A record carrying only `anchor/v1` still matches a run emitting `anchor/v1` and `anchor/v2`; the comparison uses `v1`, the greatest version both carry. |
| 1.10 | Two identical normalized excerpts in one surface produce two distinct anchors, differing in `<n>`. |

## 2. Where the report lives

**A run never writes into its own scan set.** If run 1 writes a report into the tree, run 2's tree is
not unchanged and the idempotence property is unfalsifiable by construction.

- The report goes under `${CLAUDE_PLUGIN_DATA}`, which resolves outside any target repository and
  survives plugin updates, at `runs/<state-key>/<run-id>/findings.json`.
- `--report-to <path>` redirects it into the target tree. **The redirecting run records that path in
  its own exclusion set, before it writes** — not only for subsequent runs — and says so in its
  output. Deferring the record to run 2 would put the path in one run's derived-tier exclusion
  artifact and not the other's, and 2.2 requires those two derived sets to be equal. The path is
  recorded whether or not a file exists there yet: the exclusion is about the path this run is about
  to write, not about what it found there.

| # | Assertion |
|---|---|
| 2.1 | After a run against a clean git worktree with no redirect, `git status --porcelain` is empty. |
| 2.2 | With a redirect, a second run's scan set excludes the redirected path, and the two runs' derived identity sets are still equal. |
| 2.3 | The first run under `--report-to` records the redirected path in its own exclusion artifact before writing the report, whether or not that path already exists. |

## 3. Run state, keying, and concurrency

`${CLAUDE_PLUGIN_DATA}` is machine-global, not per-project, so state keyed by working directory would
collide or fragment depending on where the operator happened to stand.

**`<state-key>` = `<repo-identity>/<worktree-discriminator>`.**

- **`repo-identity`** — for a git repository, the first configured remote URL normalized to
  `host/owner/repo`, lowercased, `.git` suffix and credentials stripped. With no remote,
  `local/<sha256 of the canonicalized repo root>` truncated to 12.
- **`worktree-discriminator`** — `sha256` of the canonicalized worktree root, truncated to 8. Two
  worktrees of one repository on different branches legitimately hold different content and must not
  share a run report.

Suppressions are keyed differently on purpose (§4): they are a decision about the *repository*, not
about a checkout, so they are shared across worktrees and committed where the operator owns the
target.

**Concurrency.**

- A read-only run takes **no lock**; concurrent read-only runs are safe and are not serialized.
- An applying run takes an **exclusive advisory lock** at `runs/<state-key>/lock`, containing the
  process id and an ISO-8601 start timestamp.
- A second applying run for the same state key **refuses and exits non-zero**, naming the holder's
  pid and start time. It does not wait — a pass over a large tree runs long, and a silent queue looks
  like a hang.
- A lock whose recorded pid is not alive **and** whose timestamp is older than 30 minutes is stale
  and is reclaimed, with the reclamation reported in the run output.

| # | Assertion |
|---|---|
| 3.1 | Two applying runs launched concurrently against one target: exactly one proceeds, the other exits non-zero naming the holder. |
| 3.2 | Two read-only runs launched concurrently both complete, and their derived identity sets are equal. |
| 3.3 | A run launched from a subdirectory produces the same state key as one launched from the root. Working directory is never an input. |

## 4. Suppression, per target class

**The governing rule: suppression is always central. There is no inline marker, at any target.**

An inline form was specified and withdrawn, recorded here so it is not re-proposed. A marker would
have to carry the same constituents a central entry does — `check`, `claim`, every site, reason,
date — because the key is derived from them, so it duplicates the central record instead of
simplifying it. It cannot express a pairwise finding at all: a marker sits at one site, and a
two-site finding has no one site to sit at. And writing one into a clean worktree is the thing 2.1
forbids. A second format with strictly less capability, a second parser, and an unspecified
inline-versus-central merge rule is cost with no capability behind it.

**A central entry stores the finding's constituents, not a bare id.** `check`, `claim`, and **every**
`(surface, anchor)` site, alongside the required reason and date — with `finding_id` as the mapping
key derived from them. A bare id is a one-way hash: it can answer "is this exact finding still
present" and nothing else, so a record built on it cannot compute a tiered match and none of the four
dispositions below is implementable on top of it. The constituents also make the entry diagnosable by
a human reviewer — an operator auditing a year-old suppression can read what was accepted instead of
a hex string. They are required from the first published contract rather than retrofitted, because
this record is operator-authored and commonly committed: adding required keys later is a migration on
somebody else's tracked data, and the constituents cannot be recovered from the id they hash into.

| Target class | Disposition |
|---|---|
| A project-scope file the pass may edit | Central entry. Being *allowed* to edit a file is not a reason to edit it to silence a report about itself |
| A file the pass does not own | Central entry. Editing a file you do not own to silence a report is a boundary violation dressed as configuration |
| A user-scope file | Central entry, and **never** an edit to the file. User-scope surfaces are routed, never edited |
| A registered byte-identical cluster copy | **Refused**, naming the canonical source. The copy is excluded from the scan set, so an entry against it is stale by construction |

**The record and its layers.** `.claude/audit-pass.md` in the target repository, resolved across the
three config-cascade layers — user-global, team (tracked), and a gitignored local overlay. Layers
merge **per key**: a later layer's entry for one `finding_id` wins for that id alone, and every id it
does not mention keeps the earlier layer's entry. A list would be taken whole, so one personal entry
would silently discard the team's entire accepted set.

**A personal layer never enacts a suppression.** Two rules, and the first carries the weight:

1. **A personal entry for an id the team layer does not carry does not suppress.** It is reported as
   **`personal-only, not applied`**, naming promotion to the team layer as how to make it take
   effect. Absence from the team layer *is* the team's unsuppressed state, so applying such an entry
   would hide a finding the team never accepted. §3 already settles where the decision belongs: a
   suppression is a decision about the **repository**, not about a checkout — and a decision about
   the repository belongs in the layer the repository tracks.
2. **On a direct conflict for the same id the team layer wins**, inverting the usual precedence. This
   rule is narrower than it sounds, and saying so is the point: 4.5 forces an entry's constituents to
   hash to its own key, so two entries sharing a `finding_id` have identical `check`, `claim`, and
   `sites` by construction. The only fields that can differ are `reason` and `date` — so what the
   inversion protects is the team's recorded justification, not which findings are visible. Rule 1
   owns that.

A personal layer is therefore a **draft** surface: an entry there is read, reported, and attributed,
and takes effect only once promoted. Every reported entry names its contributing layer, which is what
makes both rules auditable rather than merely declared.

The cross-consumer key contract is published separately, as the **finding-suppression** convention in
this marketplace. This section states what the pass itself needs in order to run, so the skill
resolves nothing by reaching outside the plugin.

The record is **excluded from the scan set** — otherwise suppressing a finding changes the tree and
perturbs the next run.

### Matching an entry: the four dispositions

Storing constituents is what makes tiered matching computable at all — a bare id can only ever say
matched or gone — so the contract states the full table rather than a binary.

Tiered matching is prior art, not an invention. SARIF carries a whole **Appendix B (Normative), "Use
of fingerprints by result management systems"**, whose subject is that a fingerprint is expected to
be *stable enough* rather than absolutely stable. GitHub's documented behavior on a mismatch is
close-and-reopen: "If the filepaths differ for the same result, each time there is a new analysis a
new alert will be created, and the old one will be closed"
([SARIF support for code scanning](https://docs.github.com/en/code-security/code-scanning/integrating-with-code-scanning/sarif-support-for-code-scanning),
verified 2026-07-25).

| Condition | Disposition | Effect on the suppression |
|---|---|---|
| Both anchors match, `(check, claim)` match | **SAME, UNCHANGED** | Applies silently, as an exact match always has. |
| Exactly one anchor changed; the other anchor and `(check, claim, both surfaces)` all match | **SAME, CHANGED** | **Carries forward, marked `needs-reconfirmation`**, surfaced in `suppressed` with the changed side named. Never silent: the edit may have *been* the fix attempt, and silently re-suppressing hides precisely the case the operator most needs to see. |
| Both anchors changed, **or** `claim` changed, **or** a surface changed | **OLD CLOSED, NEW OPENED** | The old entry goes **stale** per 4.2, never silently dropped. The new finding is unsuppressed. |
| The finding is absent from the new run entirely | **CLOSED** | Must be **accounted for** as exactly one of: matched to an applied fix; matched to a successor by partial match; or reported as an **UNEXPLAINED DISAPPEARANCE**, which fails the run's self-check exactly as a P4a tolerance breach does. |

A single-site finding has no "other anchor", so row 2 cannot apply to one: a changed anchor on a
single-site finding falls to row 3.

**Row 4 is the detector P2 has been missing.** §6's P2 states that a finding vanishing without a fix
is a defect — a definition with nothing able to observe it. Requiring every disappearance to be
accounted for is what turns that definition into a check capable of failing.

| # | Assertion |
|---|---|
| 4.1 | A suppressed finding does not appear in the next run's findings, and appears in the `suppressed` section with its reason, its date, and its contributing cascade layer. |
| 4.1a | A personal-layer entry for a `finding_id` the team layer does not carry **does not suppress**: its finding still appears in the run's findings, and the entry appears in `suppressed` as **`personal-only, not applied`** naming its contributing layer. |
| 4.2 | Every entry resolves to exactly one of the four dispositions above. `SAME, CHANGED` carries the suppression forward and reports it as `needs-reconfirmation` naming the changed side; `OLD CLOSED, NEW OPENED` reports the old entry as **stale** and leaves the new finding unsuppressed. Neither is silent. |
| 4.3 | Adding a suppression does not change any other finding's `finding_id`. |
| 4.4 | No suppression mechanism writes to a path in the derived exclusion set. Attempting to suppress a finding in a registered cluster copy makes the run refuse and name the canonical source. |
| 4.5 | An entry whose stored constituents do not hash to its own key is reported as malformed and does not suppress. The constituents are authoritative; the key is derived from them. |
| 4.6 | Every finding present in the previous run and absent from this one is accounted for as exactly one of: matched to an applied fix, matched to a successor by partial match, or reported as an **UNEXPLAINED DISAPPEARANCE**. The third fails the run's self-check. |

## 5. Mid-run resumability

A pass over a large corpus plus three scopes can be interrupted by compaction, a rate limit, or a
crash. Restarting from zero wastes the run and tempts an operator to narrow the scan.

- Findings persist **incrementally, per lane**, as each lane completes — never buffered to the end.
- A run manifest records, per lane: the lane id, its **input digest**, and its completion state.
- **Input digest** = `sha256` over the lane's ordered file list paired with each file's content hash.
- **Resume** re-runs only lanes that are incomplete or whose input digest has changed. A lane whose
  digest is unchanged and whose state is complete is skipped and its findings carried forward.
- A re-attempted lane appends a **supersession record** and opens a new attempt, per §7. Attempt
  boundaries are what let an interrupted re-attempt be discarded deterministically.

| # | Assertion |
|---|---|
| 5.1 | Kill a run after lane *k* completes, resume, and the final report equals an uninterrupted run's over the same tree. |
| 5.2 | Modify one file belonging to a completed lane, then resume: that lane re-runs and no other completed lane does. |
| 5.3 | Invalidate a completed lane on resume, kill its re-attempt after it has appended findings but before its terminating record, then resume again: the abandoned attempt's rows appear in neither the assembled report nor any later attempt's carry-forward, and no finding is duplicated. |

## 6. The three tiers and their properties

The two-tier `mechanical` / `behavioral` split the delegated catalogs use cannot carry a determinism
property, for two independently sufficient reasons: no delegated check reaches the report without
model judgement (a catalog's own lane refinement and verify pass both re-judge, so even a
`mechanical`-tagged check is model-gated), and half the delegated catalog uses a different vocabulary
entirely. So the property is stated over the part of the run that genuinely is deterministic.

| Tier | Contents | Produced by | Property |
|---|---|---|---|
| **Derived** | three-scope surface inventory, exclusion set, shadowed-definition findings, raw script candidate rows | enumeration and scripts only — no model in the path | **exact equality** |
| **Judged** | every finding from a delegated catalog check, whatever that catalog calls it | a model | **stability tolerance** |
| **Delegated** | `/doctor`'s output | a prompt-based bundled skill | **none** — diffed by nobody |

The derived tier is not a consolation prize. It answers "did the pass look at the same things", which
is the question an operator asks first, and it is where a silent scope regression shows up.

Stated over two runs `R1` then `R2`; `D(R)` is the derived-tier identity set, `J(R)` the judged-tier
set.

### The precondition must be measured, not assumed

Every property below is conditioned on "tree unchanged". **A run cannot assume that precondition of
itself.** The state key is computed once at Phase 0, and nothing re-validates the tree at Phase 6, so
a checkout that moves *during a single run* — another session switching branches, pulling, or
committing underneath it — yields a comparison whose basis silently stopped holding. This is not
hypothetical: a pass over a shared checkout observed its target move mid-measurement, from one commit
on one branch to a different commit on another, with a rename landing in between. Several concurrent
sessions on one repository is the normal case for the operator who runs this first.

So the run **measures** its own precondition:

- At Phase 0 and again at Phase 6, capture the target's **HEAD commit** and its **worktree digest**.
- **Worktree digest** = `sha256` over every dirty path in sorted order, each paired with the content
  hash of its current bytes — the path set from `git status --porcelain`, the content hash per path
  from `git hash-object`, a deleted path paired with a fixed deletion sentinel. **A count is not
  enough and was the earlier mistake:** editing a dirty file's contents, or swapping one dirty path
  for another, leaves both HEAD and the count identical, so a count-based gate would evaluate P1–P3
  as though the tree held still while different lanes in fact read different states. Pairing each
  path with its content is what makes both of those movements visible.
- If either capture differs, the determinism gate is reported **`indeterminate`**, never `passed` and
  never `failed`, naming both captures and what moved.
- **Two endpoint captures detect a net change, not a transient one.** A file mutated and reverted
  inside the run is invisible to them. §5's per-lane input digests are the detector for that case and
  need no new machinery: two lanes whose inputs overlap record content hashes for the shared paths,
  and a disagreement between them means the tree moved mid-run. It reports `indeterminate` on the
  same grounds — the lanes demonstrably did not read one state.
- `indeterminate` is a distinct outcome, not a soft pass. It says the run could not establish the
  basis for the comparison — which is a true statement — where `passed` would assert a stability that
  was never tested.

An unfalsifiable `passed` is worse than an honest `indeterminate`: it manufactures confidence out of
a precondition nobody checked, and it is indistinguishable in the report from a gate that genuinely
held.

- **P1 — determinism.** Tree unchanged **and live surface set unchanged** ⇒ `D(R1) = D(R2)`, exactly.
  Not a subset, not a tolerance. The liveness clause is load-bearing rather than a hedge: startup
  scope depends on the launch directory and on settings the tree does not contain, so two runs over a
  byte-identical tree can legitimately see different surfaces. **A liveness change is reported as the
  cause and never silently absorbed** — a run that quietly attributed a liveness difference to the
  tree, or to nothing, would be the same silent scope regression P3a exists to catch.
- **P2 — convergence, measured against the findings the fixes targeted.** Accepted fixes applied
  between runs ⇒ every finding a fix targeted is absent from R2, and `D(R2) ⊆ D(R1)` still holds.
  **Strictness is conditional, not universal:** `D(R2) ⊊ D(R1)` is required only when at least one
  accepted fix targeted a derived-tier finding. A judged-tier fix need remove nothing from `D` —
  rewriting an over-prescriptive instruction leaves the surface inventory, the exclusion set, the
  shadowed definitions, and the raw script-candidate rows exactly as they were — so a blanket strict
  subset would declare a perfectly good fix non-convergent, which is the wrong verdict on the
  commonest fix there is. Conversely, a finding that vanishes without a fix is a defect in the check,
  not a success. **Its detector is §4's fourth disposition**: every disappearance is accounted for as
  a fix, a successor, or an UNEXPLAINED DISAPPEARANCE that fails the self-check. Without that
  accounting P2 is a definition nothing can observe.
- **P3 — no spontaneous growth.** Tree and catalog versions unchanged ⇒ `D(R2) ⊆ D(R1)`. The set may
  grow only on a catalog version bump or a change to the tree — and a skill authored between runs is
  a change to the tree.
- **P3a — the inventory is part of the gate.** A surface that silently drops out of scope between two
  runs **fails P1**. A silent scope regression is worse than a changed finding, because it looks like
  an improvement.
- **P4 — judged-tier stability, not identity.** Judged findings are reported in their own section,
  excluded from P1–P3, and held to
  `|J(R2) \ J(R1)| ≤ max(2, ceil(0.10 × |J(R1)|))` over an unchanged tree, measured across three
  consecutive runs with the worst pair taken; and to contradicting no accepted suppression.
- **P4a — a violation has a consequence.** Exceeding the tolerance **fails the run's self-check and
  is reported as an instability finding against `audit-pass` itself**, naming the checks whose output
  moved. It is never absorbed by recalibrating the constant. The tolerance may be revised only by an
  explicit, recorded decision citing the observed distribution.
- **P5 — the delegated tier is excluded from both properties.** A prompt-based delegate cannot
  contribute to a determinism gate.
- **P6 — an unestablished precondition yields `indeterminate`.** A run whose start and end captures
  of HEAD and worktree digest disagree — or whose per-lane input digests disagree on a shared path —
  reports the determinism gate as `indeterminate` and does not
  evaluate P1, P2, or P3 for that pair. Their precondition demonstrably did not hold, so a verdict on
  them would be an assertion about a comparison the run never actually made.

| # | Assertion |
|---|---|
| 6.1 | A run captures HEAD and the worktree digest at Phase 0 and again at Phase 6, and records both captures in the report. |
| 6.2 | When the two captures differ, the determinism gate reads `indeterminate` — never `passed`, never `failed` — and names both captures and what moved. |
| 6.2a | Changing a dirty file's contents during a run, or replacing one dirty path with another, changes the worktree digest and yields `indeterminate`, even though HEAD and the number of dirty files are unchanged. |
| 6.2b | Two lanes whose inputs overlap record the same content hash for every shared path; a disagreement yields `indeterminate`. |
| 6.3 | An `indeterminate` gate is visibly distinct from a passing one in the report, and P1–P3 are reported as not evaluated rather than as satisfied. |

The floor of 2 exists because with a small judged set a pure percentage rounds to zero, making P4
identity by the back door — which P4 exists to deny. With a large set the percentage dominates and
the floor is irrelevant. **10% is a starting calibration, not a discovered constant.**

## 7. Report schema

Two artifacts, because incremental persistence and a sectioned report want different shapes.

**During the run — `findings.partial.jsonl`.** One JSON object per line, appended as each lane
completes. Append-only is what makes §5 real: a single JSON document would be rewritten whole on
every append, which is exactly the operation an interrupted run leaves half-done. A lane's final
record is its terminating record, which is what marks the lane complete.

**Every record carries an attempt id, and an attempt is delimited at both ends.** A lane can be
attempted more than once — a completed lane is invalidated on resume when its input digest moved,
and an attempt can itself die before terminating — so an append-only file accumulates rows from
several attempts of one lane, interleaved with rows appended after them. Without a boundary, final
assembly cannot tell an abandoned partial attempt from the successful one, and would duplicate
findings or retain stale ones. So:

- `attempt` = `(lane id, ordinal)`, the ordinal starting at 1 and incremented on every re-attempt of
  that lane. Every record of that attempt carries it, findings included.
- An attempt opens with a **start record** and closes with its **terminating record**. Neither is a
  finding.
- **Assembly takes, per lane, the highest-ordinal attempt that has a terminating record, and
  discards every other attempt's rows outright** — including any complete-looking prefix. An attempt
  with a start record and no terminating record is abandoned by definition, whatever it managed to
  append.
- A resume that invalidates a completed lane appends a **supersession record** naming the lane and
  the ordinal it retires, so the retirement is in the artifact rather than inferred from ordering.
  Ordering alone cannot carry it: rows from a later attempt are appended after rows from an unrelated
  lane, and position is not provenance.

Each record separates the two field classes §1 distinguishes, because a reader who cannot tell them
apart cannot tell which fields a change would rename the finding through:

| Block | Fields | Rule |
|---|---|---|
| `identity` | `check`, `claim`, `sites` (each `surface` + versioned `anchor`, canonically sorted) | Hashed into `finding_id`. Nothing else is. |
| Presentation | `primary_site`, `related_site`, `load_path`, per-site heading path, rendered prose | Carried for reading and remediation. Changing any of them leaves `finding_id` untouched. |
| Run metadata | `lane`, `attempt`, `tier` | Where the record came from, and which attempt of that lane produced it. |

**At the end — `findings.json`.** One document assembled from the partial, carrying `schemaVersion`,
the run and target identity, the resolved version of every catalog consulted, and then the sections:

| Section | Contents |
|---|---|
| `inventory` | the three-scope surface list, derived tier |
| `mechanical` | derived-tier findings, including shadowed definitions |
| `behavioral` | judged-tier findings |
| `suppressed` | every entry with its reason, date, contributing cascade layer, and its disposition — including each `needs-reconfirmation` entry with the changed side named, each stale entry, each malformed entry, each **`personal-only, not applied`** entry, and every UNEXPLAINED DISAPPEARANCE |
| `delegated` | `/doctor`'s output, diffed by nobody |
| `skipped` | every surface excluded, **with its reason** — a silent exclusion reads as coverage, and this section is what stops it |

**Resume reads the partial, not the report**, so completion state is derivable from the artifact
rather than tracked beside it and able to disagree with it.
