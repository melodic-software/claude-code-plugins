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

`<n>` **discriminates identical excerpts within a surface, and it is not a positional ordinal.** A
rule repeated verbatim three times must yield three distinct anchors rather than one collision — but
a 1-based position among the duplicates is the wrong discriminator, because deleting the first
occurrence renumbers the second from `:2` to `:1`, where it **inherits the deleted occurrence's
`finding_id` and any suppression attached to it**. The operator's decision about the text they
removed silently transfers to text they never judged, and the stale entry is never reported stale
because something still matches its key. Insertion has the same shape in the other direction.

So `<n>` is a **stable occurrence discriminator**, derived in full here rather than deferred — an
underspecified derivation is not a weaker contract, it is a different anchor per implementation and
therefore a different `finding_id` for the same text:

```text
<n> = sha256(heading_path) truncated to 8 hex
```

where `heading_path` is the surface's ordered enclosing headings joined by `\x1f`, normalized by the
same v1 rules as the excerpt — the same path already carried alongside each site for legibility, now
load-bearing. A surface with no heading structure above the excerpt, or no heading concept at all (a
prompt-type hook in JSON), uses the fixed sentinel `\x00`.

**Why the enclosing heading path and not the neighbouring text.** A digest over adjacent blocks would
satisfy this thread and violate assertion 1.2 in the same stroke: inserting an unrelated paragraph
directly above a finding would change its neighbours, hence its anchor, hence its `finding_id` —
churning suppressions on edits that touch nothing relevant, which is the failure content-derived
anchoring exists to avoid. The heading path is invariant under insertion, deletion, and reordering of
*content*, and changes only when the document's structure around the excerpt changes, which is a
re-judging event on its own terms. It is also invariant under deleting a duplicate elsewhere in the
surface, which is the defect this replaces.

**Two duplicates under one heading path are genuinely indistinguishable, and the contract fails
closed rather than guessing.** No positional scheme can separate them without reintroducing the
transfer bug, so their anchors collide: the finding is reported **once**, the collision is named with
its occurrence count, and **no suppression carries forward across it** — an operator suppressing one
of two identical sentences in one section is making a decision the record cannot faithfully attach to
one of them. Splitting the heading, or making the sentences differ, resolves it in the document where
the ambiguity actually lives.

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

The heading path is **also** an identity input, via the duplicate discriminator above; its rendered
form (`## Rules > ### Naming`) travels alongside each site for legibility
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
| 1.10 | Two identical normalized excerpts under **different** heading paths in one surface produce two distinct anchors, differing in `<n>`. |
| 1.10a | Two identical normalized excerpts under the **same** heading path produce the **same** anchor: the finding is reported once, the collision is named with its occurrence count, and no suppression carries forward across it. Deleting one of them leaves the anchor unchanged. |
| 1.10b | Deleting an identical excerpt under a *different* heading path does not change the surviving one's anchor or `finding_id`, and a suppression keyed to the deleted one is reported stale rather than applied to the survivor. |

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
- **A redirect destination is accepted only if it is new, or is already an `audit-pass`-owned
  report.** Recording the path unconditionally was right for the *exclusion* and wrong as a licence
  to *write*: `--report-to CLAUDE.md` would overwrite an audited instruction surface with a JSON
  report, with no `--fix` and no confirmation — a read-only invocation destroying target content —
  and then exclude the corrupted path from every later run, so the damage hides itself. Anything else
  at that path is refused, non-zero, naming the file; the run does not offer to overwrite, because
  the only surfaces this pass may write are its own. Ownership is decided by the artifact's own
  identifying header, never by filename or location, so a hand-placed file cannot claim it.

| # | Assertion |
|---|---|
| 2.1 | After a run against a clean git worktree with no redirect, `git status --porcelain` is empty. |
| 2.5 | `--report-to <existing-non-report-path>` exits non-zero naming the file, writes nothing, and leaves the file byte-identical — including when the path is an audited instruction surface. |
| 2.2 | With a redirect, a second run's scan set excludes the redirected path, and the two runs' derived identity sets are still equal. |
| 2.3 | The first run under `--report-to` records the redirected path in its own exclusion artifact before writing the report, whether or not that path already exists. |
| 2.4 | A run under `--report-to <path-inside-target>` against an otherwise-unchanging tree reports the determinism gate as satisfied, not `indeterminate` — writing its own report does not move its own state digest. |

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

### The lease — how `--resume` tells a live run from an abandoned one

Every run writes a lease; only an applying run also takes the lock above. The two are separate
mechanisms and the lease grants no exclusivity: it exists solely so `--resume` can classify an
incomplete run, which the no-lock read-only policy otherwise makes undecidable.

- **Path** — `runs/<state-key>/<run-id>/lease`, beside that run's own partial artifact, so one lease
  describes exactly one run and concurrent read-only runs never contend for it.
- **Contents** — the run id, the process id, an ISO-8601 start timestamp, a **`heartbeat_at`**
  timestamp the run rewrites in place, and an **`owner_epoch`** integer starting at 1.
- **Refresh** — the holder rewrites `heartbeat_at` every **60 seconds**, and additionally at each
  lane boundary, so a long single lane cannot look abandoned.
- **Liveness** — the lease is **live** when `now - heartbeat_at < 5 minutes` — five refresh intervals,
  chosen so ordinary scheduling delay, a slow filesystem, or a paused VM does not read as a crash.
  Otherwise it is **stale**.
- **`--resume` against a live lease exits non-zero**, naming the run id and its `heartbeat_at`, and
  does not attach. Against a stale lease it takes over the artifact and begins refreshing that lease
  itself.
- **Adoption fences the previous holder; a stale lease is not assumed abandoned.** A suspended
  process can wake at any time, so "it stopped refreshing" is evidence, never proof. The lease
  therefore carries an **`owner_epoch`**, a monotonically increasing integer. Adopting a stale lease
  increments it in a single atomic write conditioned on the observed value — the compare-and-set is
  what makes two simultaneous adopters resolve to one — and the adopter then owns that epoch.
  **Every heartbeat refresh and every artifact append re-reads `owner_epoch` first and aborts the run
  if it is no longer the writer's own.** A woken holder therefore fails on its next refresh or
  append, before it can write, rather than resuming alongside the adopter.
- Without fencing, both processes could reach a not-yet-started lane and assign it the **same attempt
  ordinal** — and §7's delimiters distinguish attempts, not writers, so two interleaved streams under
  one ordinal are indistinguishable at assembly. That is the one failure the attempt machinery cannot
  absorb, which is why the check is on every append rather than only at adoption.
- **A stale lease is therefore never fatal, and never a silent double-write**: the worst case is that
  a merely-slow run is fenced out and must be re-run, which is visible and recoverable, rather than
  two runs quietly interleaving records into one artifact.
- **`heartbeat_at` must not move backwards, and must not run away forwards.** A clock adjustment that
  rewinds it would make a live run read stale, so a refresh writes `max(now, previous)`. But
  `max(now, previous)` alone preserves a timestamp written during a *forward* jump that is later
  corrected — and since liveness only tests `now - heartbeat_at < 5 minutes`, a future timestamp
  keeps the lease live for the whole skew interval **even if the process has since crashed**, so
  every `--resume` refuses an abandoned run indefinitely. That is the worse failure of the two,
  because the backwards case costs a re-run and this one costs the artifact.
- So liveness is **two-sided**: the lease is live when
  `-60s ≤ now - heartbeat_at < 5 minutes`. A heartbeat more than one refresh interval in the future
  is not evidence of life — it is a clock artifact — and the lease is classified **stale**, with the
  skew reported so the operator sees why. Both bounds are needed: the lower one keeps a corrected
  clock from pinning a dead run live, the upper one is the ordinary staleness test.

Interval and threshold are stated here rather than left to the implementation because "live or abandoned" is a
classification two implementations must reach identically or `--resume` is nondeterministic.

| # | Assertion |
|---|---|
| 3.1 | Two applying runs launched concurrently against one target: exactly one proceeds, the other exits non-zero naming the holder. |
| 3.6 | `--resume` against a run whose lease was refreshed within the threshold exits non-zero naming the run id, and the live run's partial artifact is byte-identical afterwards. |
| 3.7 | `--resume` against a run whose lease has not been refreshed past the threshold adopts the artifact, increments `owner_epoch`, and refreshes the lease itself. |
| 3.8 | A holder whose lease was adopted while it was suspended aborts on its next heartbeat refresh or artifact append, writing nothing: the partial artifact contains records from exactly one writer per attempt ordinal. |
| 3.9 | A lease whose `heartbeat_at` is further in the future than one refresh interval is classified stale and is adoptable, with the skew reported — a forward clock jump cannot make an abandoned run permanently unresumable. |
| 5.4 | A lane whose delegate reported no catalog version or prompt digest re-runs on every `--resume` rather than being carried forward, and the delegate is named in the report's coverage notes as owing a detection declaration. |
| 6.1d | The scan baseline is computable on a worktree containing an untracked directory: paths come from `git status --porcelain --untracked-files=all`, so no `git hash-object` is attempted on a directory. |
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
| **Every** site's anchor matches, `(check, claim)` match | **SAME, UNCHANGED** | Applies silently, as an exact match always has. Phrased over the whole `sites` set rather than "both anchors", because the set holds one entry for an ordinary single-site finding and two for a pairwise one — the two-site phrasing left an unchanged single-site entry matching **no** row, so the commonest case in the table had no disposition at all. |
| Exactly one anchor changed; the other anchor and `(check, claim, both surfaces)` all match | **SAME, CHANGED** | **Carries forward, marked `needs-reconfirmation`**, surfaced in `suppressed` with the changed side named. Never silent: the edit may have *been* the fix attempt, and silently re-suppressing hides precisely the case the operator most needs to see. |
| Both anchors changed, **or** `claim` changed, **or** a surface changed | **OLD CLOSED, NEW OPENED** | The old entry goes **stale** per 4.2, never silently dropped. The new finding is unsuppressed. |
| The finding is absent from the new run entirely | **CLOSED** | Must be **accounted for** as exactly one of: matched to an applied fix; matched to a successor by partial match; **retired with its check**, when the check that raised it is absent or renamed in the new run's detection configuration; or reported as an **UNEXPLAINED DISAPPEARANCE**, which fails the run's self-check exactly as a P4a tolerance breach does. |

A single-site finding has no "other anchor", so row 2 cannot apply to one: a changed anchor on a
single-site finding falls to row 3.

**`retired with its check` is a disposition rather than an exemption, and the difference matters.** A
delegated catalog that removes or renames a check legitimately makes its findings disappear with no
fix and no successor, and the unconditional rule called that an UNEXPLAINED DISAPPEARANCE and failed
the run — the comparability contract already treats a detection-version change as non-comparable, so
the two disagreed. But suppressing the accounting entirely would be worse: findings would vanish
silently on any catalog edit, which is the exact shape row 4 exists to detect. So the disappearance
is still accounted for, still reported, and named as retirement with the retiring check and the
version transition cited. Any suppression entry keyed to a retired check goes **stale** rather than
being deleted, because a check that returns under its old name must not silently re-apply a
suppression the operator has not seen since.

**Row 2 requires a unique successor, and without that requirement it is not a function.** Two current
pairwise findings can share the unchanged anchor, both surfaces, `check`, and `claim` while differing
only in the changed-side anchor — and then *both* satisfy row 2's condition for one old entry. The
**claim-unqualified fallback makes this ordinary rather than exotic**: with `claim` bound to the bare
check id, every claim that check can make at one site pair collapses onto one identity, so the
collision is the expected case for any catalog that has not declared its templates. Carrying the
entry to both suppresses a newly opened conflict the operator never accepted; picking one is
nondeterministic and would break P1 by construction, since the choice depends on iteration order.

So: **row 2 applies only when exactly one candidate satisfies it.** With two or more, the old entry
goes **stale** per 4.2 and *every* candidate is left unsuppressed and reported, with the ambiguity
named and the candidates listed. That is the fail-closed direction — it re-surfaces a finding the
operator may re-suppress in one action, where the alternative silently hides one they never saw. It
also gives the claim-unqualified fallback a visible cost at exactly the point that costs something,
which is where the coverage note says the imprecision would be felt.

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
| 4.6 | Every finding present in the previous run and absent from this one is accounted for as exactly one of: matched to an applied fix; matched to a successor by partial match; **retired with its check**, when the check that raised it is absent or renamed in the new run's detection configuration; or reported as an **UNEXPLAINED DISAPPEARANCE**. Only the last fails the run's self-check. |

## 5. Mid-run resumability

A pass over a large corpus plus three scopes can be interrupted by compaction, a rate limit, or a
crash. Restarting from zero wastes the run and tempts an operator to narrow the scan.

- Findings persist **incrementally, per lane**, as each lane completes — never buffered to the end.
- A run manifest records, per lane: the lane id, its **input digest**, and its completion state.
- **Input digest** = `sha256` over the lane's ordered file list paired with each file's content hash,
  **plus its detection configuration** — the lane's detection version (catalog version and the
  check's prompt digest), the harness version, and every behavior-affecting argument the resumed
  invocation carries, `--opinion` among them.
- **A file-only digest is what makes a resume mix configurations.** Update a delegated plugin or
  catalog between the interruption and the `--resume`, or resume with a different `--opinion`, and the
  audited files stay byte-identical — so completed lanes are carried forward from the old detection
  configuration while unfinished lanes run under the new one, and the assembled report presents one
  resolved version over findings produced under two. That is worse than restarting, because the
  report looks coherent. Including the configuration means such a resume re-runs the affected lanes
  instead of blending them.
- **What the pass may hash is bounded by what the delegate reports, and the gap is closed by
  re-running rather than by reaching in.** This pass dispatches skills and never reads inside one, so
  a delegate's catalog version and prompt digest are available only if that delegate *emits* them —
  and today none does: `claude-memory:audit` takes an action verb and returns findings and counts.
  Requiring metadata no interface supplies would make the rule unimplementable, and hashing it by
  reading another plugin's files would break the boundary the whole design rests on. So each lane is
  classified by what its own delegate returned:
  - **Detection-qualified** — the invocation reported its catalog version and prompt digest. Both go
    into the input digest, and the lane resumes normally when they are unchanged.
  - **Detection-unqualified** — the invocation reported neither, the state of every delegated catalog
    today. The lane is **not resumable**: it re-runs on every `--resume`, and the report's coverage
    notes name that delegate as owing a detection declaration.

  Fail-closed, and deliberately the expensive direction: re-running a lane costs tokens, while
  carrying one forward across an unobservable catalog change produces a report mixing two rule sets
  and presenting them as one. The observable half — the plugin's own semver from the marketplace
  manifest, and the harness version, which are the pass's own to read — is still recorded, so the
  report can say *what changed* even where it could not have prevented the mix. The upgrade path is a
  change to the delegated interfaces, not to this pass, and it is the same declaration `claim`
  templates already ask of them.
- **Resume** re-runs only lanes that are incomplete, detection-unqualified, or whose input digest has
  changed. A lane whose digest is unchanged, whose state is complete, and which is
  detection-qualified is skipped and its findings carried forward.
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

- At the **scan baseline** — Phase 1's inventory frozen, before any lane reads — and again at the
  **audit endpoint** — the moment the last lane completes, *before* any Phase 5 mutation — capture the
  target's **HEAD commit** and the run's **state digest**.
- **State digest** = `sha256` over the inventoried surfaces in sorted order, each paired with the
  content hash of its current bytes, plus every dirty path in the target worktree on the same terms —
  path set from **`git status --porcelain --untracked-files=all`**, content hash from
  `git hash-object`, a deleted path paired with a fixed deletion sentinel.
- **`--untracked-files=all` is required, not a preference.** Bare `git status --porcelain` collapses
  an untracked directory to a single `?? dir/` entry rather than listing its files, and
  `git hash-object` on a directory fails — so on the ordinary worktree state of having one untracked
  directory, the baseline digest cannot be computed at all and the determinism gate does not merely
  degrade, it fails to run. `all` yields file paths, which is what the digest hashes. Parse the
  porcelain **paths**, not the status letters: a rename entry carries `orig -> new` and a path with
  unusual bytes is emitted quoted, so both need decoding before hashing. Prefer `-z` where available,
  which sidesteps the quoting entirely.
- **Its scope is every inventoried scope, not the target repository alone.** Restricting it to the
  target worktree leaves the user-global and managed-policy surfaces outside the measurement, and
  those are read by the lanes exactly like project files: editing `~/.claude/CLAUDE.md` between runs
  can move derived script candidates and dead-surface classifications while HEAD and the target's
  dirty set both hold still. The gate would then report a legitimate external-state change as a
  determinism **defect** rather than `indeterminate` — an accusation instead of an abstention, which
  is the worse of the two errors. If Phase 1 inventoried a surface, the digest covers it.
- **A count is not enough and was the earlier mistake:** editing a dirty file's contents, or swapping
  one dirty path for another, leaves both HEAD and the count identical, so a count-based gate would
  evaluate P1–P3 as though the tree held still while different lanes in fact read different states.
  Pairing each path with its content is what makes both movements visible.
- **The run's own artifacts are excluded from the digest, on the same list that excludes them from
  the scan.** A `--report-to` path inside the target appears in `git status --porcelain` the moment
  the report is written, which is between the scan-baseline and audit-endpoint captures — so a digest over *every*
  dirty path makes the redirected run fail its own determinism gate as `indeterminate`, every time,
  purely because it did what it was asked to do. Recording the path in the scan exclusion set does
  not reach the digest; the exclusion has to apply to both, and it is one list precisely so the two
  cannot diverge. What is excluded is the pass's own class-4 artifact set and nothing else: a
  *different* file appearing or changing is still a moved tree and still `indeterminate`.
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

Every property below is conditioned on the runs being **comparable**, stated here once rather than
per-property so the clause cannot drift between them:

> `R1` and `R2` are **comparable** when their **scan-baseline state digest**, **live surface set**,
> **detection version** of every check consulted (its catalog version and a digest over the check's
> own detection-behavior inputs — the host `SKILL.md`, the criteria catalog and its imports, and any
> script named for that check), and **harness version** are all equal.

**The first input is the state digest, not the target tree, and the difference is the whole point of
widening the digest.** "Target tree" covers only the repository, so a changed `~/.claude/CLAUDE.md`
or managed-policy file left two runs classified as comparable while their derived sets legitimately
differed — reported as a determinism **defect**, the accusation-instead-of-abstention failure the
widened digest was introduced to close, surviving in the cross-run definition after being fixed in
the within-run one. Since the state digest already spans every inventoried scope and the target's
dirty set, and the baseline is taken with the inventory frozen, comparing baselines compares exactly
what the lanes were about to read. This is what makes eval 22's `indeterminate` the contract's answer
rather than an assertion against it.

A property asserts nothing about a non-comparable pair, which is reported as **non-comparable naming
the input that moved** — never as a pass and never as a failure. This is not a hedge: each input
changes what a *correct* run finds, so comparing across one makes correct behavior indistinguishable
from a defect, in the false-alarm direction. The live surface set earns its place the same way —
startup scope depends on the launch directory, the additional-directory set, and settings the tree
does not contain, so two runs over a byte-identical tree can legitimately see different surfaces. A
detection-behavior input not covered by the digest is a defect in the digest.

- **P1 — determinism.** `R1` and `R2` comparable ⇒ `D(R1) = D(R2)`, exactly. Not a subset, not a
  tolerance. **A comparability change is reported as the cause and never silently absorbed** — a run
  that quietly attributed a liveness or version difference to the tree, or to nothing, would be the
  same silent scope regression P3a exists to catch.
- **P2 — convergence, measured against the findings the fixes targeted.** P2 is the one property
  whose whole subject is a *changed* tree, so it takes the comparability relation **modulo the
  accepted mutation set**: `R1` and `R2` are **fix-comparable** when every comparability input is
  equal *except* for the differences **attributable to the edits accepted in `R1`** — no more.
  Stated separately because the unqualified relation excludes precisely the pair P2 exists to judge,
  which would leave the convergence property unevaluable in the normal case; and *"no more"* is what
  keeps it a real constraint rather than a hole, since any difference not attributable to the
  accepted set means something else moved and P2 abstains exactly as P1 would. The applied-set
  comparison the mutation-integrity capture already performs is what makes the delta checkable.

  **The exemption covers the live surface set too, not the state digest alone.** Exempting only the
  tree would have re-broken P2 on the fix the delegated catalogs most often recommend: moving
  always-loaded material into a skill changes what is loaded at startup, so the accepted remediation
  moves the live surface set as a *consequence*, and P2 would abstain on exactly the remediation it
  is supposed to verify. Attribution is what bounds this — a surface entering or leaving the live set
  because an accepted edit created, deleted, or moved it is attributable; one that moved because the
  launch directory or `claudeMdExcludes` changed is not, and P2 abstains.

  Fix-comparable ⇒ every finding a fix targeted is absent from R2, and `D(R2) ⊆ D(R1)` still holds.
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
  of HEAD and state digest disagree — or whose per-lane input digests disagree on a shared path —
  reports the determinism gate as `indeterminate` and does not
  evaluate P1, P2, or P3 for that pair. Their precondition demonstrably did not hold, so a verdict on
  them would be an assertion about a comparison the run never actually made.

| # | Assertion |
|---|---|
| 6.1 | A run captures HEAD and the state digest at the **scan baseline** (Phase 1 inventory frozen, before any lane reads) and again at the **audit endpoint** (last lane complete, before any Phase 5 mutation), and records both captures in the report. |
| 6.1c | The scan baseline covers every surface the Phase 1 inventory produced, including user-scope and managed-policy surfaces — it is not computable before that inventory exists. |
| 6.1a | A `--fix` run that applies at least one accepted edit against an otherwise-unchanging tree reports the determinism gate as satisfied, not `indeterminate` — its own accepted mutations fall outside the measured read window. |
| 6.1b | Editing an inventoried user-scope surface (`~/.claude/CLAUDE.md`) mid-run yields `indeterminate`, even though the target's HEAD and dirty set are both unchanged. |
| 6.2 | When the two captures differ, the determinism gate reads `indeterminate` — never `passed`, never `failed` — and names both captures and what moved. |
| 6.2a | Changing a dirty file's contents during a run, or replacing one dirty path with another, changes the state digest and yields `indeterminate`, even though HEAD and the number of dirty files are unchanged. |
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
| Presentation | `primary_site`, `related_site`, `load_path`, the *rendered* heading path, rendered prose | Carried for reading and remediation. Changing any of them leaves `finding_id` untouched. **The rendered path only** — the normalized heading path is hashed into the excerpt anchor's duplicate discriminator per §1, so restructuring the headings around an excerpt does rename the finding. |
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
