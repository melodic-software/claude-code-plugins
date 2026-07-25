---
outcome: contract-defined
tier: A
date: 2026-07-24
---

# Phase 4 — the re-run contract

Task #35. Idempotence is the Brief's headline acceptance criterion, and after the proportionality
gate it carries more weight than it did: the argument for the sweep existing at all is that *the
checks are delegated but the run semantics are not*. If this document lands as prose intent, that
argument has nothing behind it. So every property below is written as a condition a test could
assert, with the assertion named.

Terms used throughout: a **run** is one invocation of the sweep against one **target**; a **lane** is
one check applied to one surface class; the **scan set** is the set of files a run reads.

## 1. Finding identity

"The same finding set" is undiffable while findings are prose judgements. Identity is a three-part
tuple, and the run emits it machine-readably.

```text
identity = (check, claim, sites)
```

**Revised 2026-07-24: the tuple was `(surface, check, anchor, claim)` and could not express D1.**
It carried exactly one surface and one anchor, which fits I1–I11 — single-location findings. D1/I12
is inherently **pairwise across two surfaces**; the headline example is a skill body against
`CLAUDE.md`. The old tuple never said which side represented the finding, whether both sides got
ids, or how a suppression keyed to one id suppresses a *relation*. Two repairs were rejected first:

- **An ordered `(primary, related)` pair fails on symmetry.** X-contradicts-Y and Y-contradicts-X
  hash differently, so one conflict yields two ids and no stable re-run.
- **Two linked findings fails on SARIF's own rule.** §3.27.12 reserves separate results for
  "distinct occurrences … which can be corrected independently". A contradiction is not that:
  fixing *either* side retires it.

The fields:

- **`check`** — a fully-qualified check id, `<plugin>/<skill>/<check>`, e.g.
  `claude-config/audit-instructions/I12`. Bare `I12` is ambiguous across catalogs.
- **`claim`** — the check's canonical claim id plus its bound parameters, **not** free prose. Every
  check declares a closed set of claim templates in its criteria entry; a finding names one and
  supplies its parameters. Prose is a rendering of the claim, never the claim itself.
- **`sites`** — a **canonically-sorted set** of `(surface, anchor)` pairs, sorted as byte strings.
  The sort is what makes identity symmetric. A single-location finding is the one-element case, so
  I1–I11 are unaffected in substance. `primary_site` and `related_site` survive as **presentation
  and remediation fields carried outside the hash** — a report still has to say which side to edit,
  and that is advice, not identity.

### `surface` — the physical file, never the loading entry point

- **Logical, never machine-absolute.** Repo-scope surfaces are repo-relative POSIX paths with no
  leading `./`. User-scope surfaces are scope-prefixed (`user:.claude/CLAUDE.md`), managed-policy
  likewise (`managed:CLAUDE.md`), so a report is comparable across machines whose absolute paths
  differ.
- **The canonicalized physical file, not the entry point that loaded it.** An `@path` import is
  expanded into context at launch, so a finding's excerpt can originate in an imported file while
  the loading surface is `CLAUDE.md`. Keying on the entry point would collide two distinct findings
  on one id. **`load_path` is carried as a non-identity ordered field, bounded at 5 entries** —
  import depth is four hops, verified, and stated in none of PLAN.md,
  [checks-and-sweep.md](checks-and-sweep.md), or this document before now.
- **A symlink target that escapes the target root takes the scope-prefixed logical form.**
  Otherwise one shared rules file yields a different surface per consuming repository. This falls
  out of the scope-prefix rule above and was simply never applied to symlink targets.
- **An escaped target is also read-only, and that is a separate rule from how it is named.** Raised
  by the cross-vendor review. Naming it makes it a surface, and the apply posture permits editing any
  surface the pass may write, protecting only managed-policy and user-scope paths by name — so an
  applying run pointed at one repository could rewrite a sibling repository's file through the
  symlink, and the target's own `git status --porcelain` check would stay empty and report nothing,
  because the write landed outside the tree that command inspects. Every surface whose canonicalized
  path resolves outside the target root is therefore classified **read-only and routed as a
  recommendation** — the posture user scope already has — whatever scope prefix it carries. Testable
  by fixture: an apply against a finding on an escaped target refuses and routes.

### `anchor` — content-derived, versioned, and granularity-tagged

A line number shifts when anything above it changes, which would churn the whole report and destroy
the property this contract exists to protect. So the anchor is content-derived, carried alongside a
human-readable heading path (`## Rules > ### Naming`) for legibility only — the hash is what
identity compares.

- **Versioned name, `anchor/v1`.** SARIF §3.27.17 requires versioned hierarchical property names,
  and says a result management system "SHOULD use the latest version of the partial fingerprint
  available in both results". Matching is on the greatest common version. **This is the highest-value
  adoption here**: every queued improvement to the anchor algorithm changes its output, and without
  versioning the *first* such change silently discards the operator's entire suppression record.

  **Matching on the greatest common version presupposes there is one, and one tagged anchor per site
  does not supply it.** Raised by the cross-vendor review. Once the algorithm advances, a producer
  emitting only `v2` against a stored result carrying only `v1` has an empty intersection: the
  `finding_id` changes, the suppression cannot be carried forward, and the record-loss versioning was
  adopted to prevent happens on the first bump anyway. So **a site carries every anchor version the
  run's algorithm can still compute, not only the newest**, for a stated migration window, and
  matching runs on the greatest version present in both results. How long the window is and when a
  version retires are Phase 6's; that more than one version is emitted at once is not.
- **Granularity discriminator.** `e:` for an excerpt, `s:` for a whole surface. A whole-surface
  finding's identity reduces to `(surface, check, claim)` and is **content-free** — SARIF §3.29.4
  backs it: "If the region property is absent, the physicalLocation object refers to the entire
  artifact." A dead-surface or unreachable-file finding is about the file's existence, not its text,
  so hashing its content would churn the id on every unrelated edit.
- **Excerpt anchor** = `sha256(normalized_excerpt)` truncated to 12 hex characters.

**Normalization**: strip trailing whitespace; collapse internal whitespace runs to one space; strip
surrounding markdown emphasis markers. Case is preserved, because these surfaces contain code and
identifiers. Two rules added 2026-07-24, each with a verified reason:

- **Backticks are preserved, explicitly.** If emphasis-stripping ever extended to them,
  `` `@README` `` would normalize to `@README` — turning literal text into an apparent import, and
  making a literal mention hash identically to a real one.
- **Block-level HTML comments outside code blocks are stripped.** They are removed before content is
  injected into Claude's context, so hashing them churns anchors over text the model never saw.

### Excerpt extraction, per surface class

The normalization above is markdown-shaped and was undefined for the other surfaces in scope. Same
logical-path discipline the contract already applies to scope prefixes, one level further down:

| Surface class | Excerpt is |
|---|---|
| Markdown body | heading path + normalized block text |
| Prompt-type hooks embedded in JSON | JSON Pointer ([RFC 6901](https://www.rfc-editor.org/rfc/rfc6901)) + the **decoded** string value |
| Frontmatter | YAML key path + normalized scalar |

**The JSON row's decode step is load-bearing:** unescape before whitespace normalization, or `\n`
and a literal newline diverge for what is the same live prompt.

### Registered cluster copies canonicalize before identity

A conflict touching a registered byte-identical cluster copy would otherwise emit up to 13 findings
for one defect, because the derived exclusion set guards the **write** side only and was never
applied to detection. A registered cluster member canonicalizes to its canonical source *before*
identity is computed; the copies are recorded in a non-identity `also_present_in` field. This is not
a new rule — §4 already states "at the **canonical source**, never the copy" for suppression. It was
simply never carried across to detection.

### `finding_id`, and why the truncations are what they are

**`finding_id` = `sha256` over `check`, `claim`, and the sorted `sites`, joined by `\x1f`, truncated
to 16 hex characters.**

The widths were asserted without argument, which is what made them look arbitrary. The load-bearing
move is that **the anchor's collision domain is not corpus-wide**: `surface` and `check` are already
in the tuple, so two anchors collide destructively only within one `(surface, check)`.

- **Threat model, stated explicitly: non-adversarial.** Truncated SHA-256 is chosen for report
  legibility, not for collision resistance against an attacker who controls file content.
- **And that disclaimer must be read against
  [checks-and-sweep.md](checks-and-sweep.md), "Threat model — prompt injection against the sweep",
  which posits exactly such an attacker.** The two do not contradict, and the reconciliation is the
  point: identity truncation is not a security control and is not asked to be one. An attacker who
  can craft a colliding excerpt must already be able to write the file, and a T2 suppression is
  bounded to one `(check, claim, sites)` tuple regardless. The controls that carry the adversarial
  case are the ones named there — suppression unreachable from apply, VCS-diffable records, least
  privilege — never the hash width.
- **Collision arithmetic is deferred rather than asserted.** Birthday-bound figures computed on
  *assumed* corpus sizes indicated both widths are comfortable, but assumed numbers must not ship as
  measured ones. **Phase 10's dogfood run supplies the real counts**, and they replace this
  paragraph before the widths are stated as fact.

### Assertions

- **Assertion 1.1** — for a fixed tree, `finding_id` is stable across runs, working directories,
  operating systems, and path separators. Test: run twice from two different absolute paths on two
  path-separator conventions; the id sets are equal.

  **Scoped 2026-07-24 to excerpt-granularity findings, because it is false as originally written
  for liveness-dependent ones.** See §6, "Liveness is not a function of the tree". A
  whole-surface liveness finding cannot satisfy this assertion, and a second machine falsifies it
  through correct behavior rather than through a defect.
- **Assertion 1.2** — inserting an unrelated paragraph above a finding does not change its
  `finding_id`. Test: fixture with a known finding, insert 20 lines above it, re-run, id unchanged.
- **Assertion 1.3** — every emitted finding validates against the report schema, and its `claim` id
  exists in the cited check's declared template set. A finding whose claim id is not declared is a
  hard error, not a warning — that is what stops prose leaking back in.
- **Assertion 1.4** — a pairwise finding's `finding_id` is invariant under which side the detecting
  lane encountered first. Test: a fixture with two conflicting surfaces, run with the inventory order
  reversed; the id is unchanged.

### Borrowed vocabulary, and two deliberate divergences

**SARIF mapping, with its caveat.** Our `anchor` is a `partialFingerprints` entry; our `finding_id`
is a `fingerprints` value. §3.27.16 says "A direct SARIF producer SHOULD NOT populate this
property", because a producer emits partials and a separate result management system combines them —
and our sweep is both in one process. That is legitimate, and it is stated in one sentence so the
borrowed vocabulary is never read as a claim of SARIF conformance.

**Two divergences from GitHub's implementation, stated together because the pattern is one pattern.**
Both adopt SARIF's decomposition and diverge only on the hash input:

- **Pairwise identity hashes both sides**, where GitHub keys on `locations[0]` only. Primary-only is
  correct for an ordered taint flow, where one end is the defect; it is wrong for a symmetric
  contradiction, where neither side is.
- **Whole-surface identity is content-free**, where CodeQL hashes the first line of the file. A
  finding about a file's *existence* must not churn when its text changes.

Stated apart, these read as two ad-hoc exceptions. Stated together, they are one principle: the hash
input is whatever the finding is actually *about*.

**One correction carried so the contract does not repeat it.** SARIF's relation kinds were initially
reported as "containment only, no contradiction kind". That is right for the pairwise case and wrong
as a general statement: for the **import** case containment is exactly right, and the spec's own
example is a `#include` chain with `isIncludedBy` — structurally identical to `@path`.

### Matching across runs — the tiered table

The contract had no equivalent, and chasing a churn-proof hash is the wrong goal. **SARIF's
"Appendix B. (Normative) Use of fingerprints by result management systems" establishes a tolerance
standard rather than a stability requirement** — its subject is precisely how a result management
system should use fingerprints that are not perfectly stable. So the tiers are specified, and with
them what suppression does in each.

**The appendix is Normative, and an earlier draft had this backwards.** It read that SARIF "concedes
the problem rather than solving it", which understated our own support: a *normative* appendix
establishing the tolerance is stronger backing for tiered matching than a concession being leaned on
charitably. **The sentence that framing rested on is deliberately not quoted here** — the OASIS
single-page HTML truncates before Appendix B on repeated fetch attempts, so nobody has confirmed it
verbatim. The appendix is cited by its verified title and status and its subject is stated rather
than quoted. Unverified text does not ship inside quotation marks.

| R1 → R2 | Verdict | Suppression |
|---|---|---|
| Both anchors match, `(check, claim)` match | SAME, unchanged | applies silently |
| Exactly one anchor changed; the other anchor and `(check, claim, both surfaces)` all match | SAME, changed | carries forward, marked `needs-reconfirmation`, surfaced with the changed side named |
| Both anchors changed, or `claim` changed, or a `surface` changed | old CLOSED, new OPENED | old entry goes stale per Assertion 4.2, never silently dropped |
| Absent from R2 entirely | CLOSED | accounted for — see below |

**The rows are phrased pairwise, and the one-site case is stated beside them rather than by rewording
them.** Raised by the cross-vendor review: every one of I1–I11 is a single-location finding, so its
`sites` set has one element and "both anchors", "the other anchor", and "both anchors changed" name
nothing. An ordinary edit to such a finding's excerpt would fall through all four rows and leave it
with no disposition at all — dropping its suppression or failing Assertion 1.5. The rows are **not**
reworded, because they are the cross-lane contract described immediately below and re-phrasing them
here is the drift that paragraph exists to prevent. So, additively, for a one-element `sites` set:
its single anchor matching is row 1; **row 2 is unreachable**, because a partial match needs a second
anchor to hold still; a changed anchor, a changed `claim`, or a changed `surface` is row 3, old
CLOSED and new OPENED with the old entry stale per Assertion 4.2 and never silently dropped; absence
is row 4. A single-site finding has no partial-match tier — which is the concrete thing row 2 buys
the pairwise case, and the reason it was worth a tier of its own.

**These four rows are a cross-lane contract, not this document's private vocabulary.** The shipped
`docs/conventions/finding-suppression/` obligation and the `audit-pass` skill's suppression section
carry the same four, in the same words. A contract and an implementation that disagree from day one
is worse than either shape alone, and the second row is where they would most plausibly drift —
partial match is the row an implementation is tempted to collapse into "no match".

**Row 3 has documented prior art, and it is worth naming because it is the *expensive* row.**
GitHub's code-scanning behavior on a changed location is close-and-reopen: "If the filepaths differ
for the same result, each time there is a new analysis a new alert will be created, and the old one
will be closed." That is exactly row 3, and it is why row 2 exists — without a partial-match tier,
*every* nearby edit takes row 3's path, and the operator's suppression record erodes one edit at a
time.

**The "changed" row is never silent, and that is the whole point of it:** the edit may itself have
*been* the fix attempt, so an operator has to see it rather than have a stale suppression quietly
absorb it.

**The last row is the missing enforcement for P2.** P2 says "a finding that vanishes without a fix
is a defect in the check" — a definition with no detector. Now every closure is accounted for as
exactly one of: matched to an applied fix; matched to a successor by partial match; or reported as
an **unexplained disappearance that fails the run's self-check**, the way a P4a tolerance breach
does.

- **Assertion 1.5** — every finding present in `R1` and absent from `R2` carries one of the three
  accounted dispositions. An unaccounted **derived** closure fails the run's self-check; an
  unaccounted **judged** closure is counted in P4's instability metric.

  **The two-tier split in this assertion is new, and the unscoped form was inconsistent with P4.**
  Raised by the cross-vendor review. A judged finding can disappear over an unchanged tree purely
  because the model judged differently, which P4 explicitly tolerates — yet an unscoped 1.5 fails the
  run for exactly that. That made judged *removals* deterministic while judged *additions* got a
  tolerance, which is one detection asked to be two different things. Routing the removal into P4
  keeps every closure accounted for, which is what this assertion is for, without asserting
  determinism where §6 has already established there is none. P4's metric is the symmetric difference
  for this reason.

## 2. Where the report lives

**A run never writes into its own scan set.** If run 1 writes a report into the tree, run 2's tree is
not unchanged and the idempotence property is unfalsifiable by construction.

- The report is written under `${CLAUDE_PLUGIN_DATA}`, which resolves outside any target repository
  and survives plugin updates, at `runs/<state-key>/<run-id>/findings.json` — `<state-key>` per §3.
- The operator may redirect the report into the target tree with an explicit argument. When they do,
  the run **must** add that path to the exclusion set for subsequent runs and say so in its output.
  Silently scanning your own previous report is the failure this rule exists to prevent.
- **A redirect destination is a path the run may create, never one it would audit.** Raised by the
  cross-vendor review. Excluding the path governs the *next* run, and by then the write has already
  happened: a redirect naming an existing audited file — a `CLAUDE.md`, a skill body — overwrites it,
  and the exclusion then hides the corrupted path from the run that would have noticed. That turns an
  otherwise read-only invocation into a destructive one, which is the single worst outcome available
  to a read-only default. So a run **refuses** a destination that already exists, and refuses one its
  own inventory enumerated as a surface, rather than writing and excluding.
- **Assertion 2.1** — after a run against a clean git worktree with no redirect argument,
  `git status --porcelain` is empty. This is the whole property in one command.
- **Assertion 2.2** — with the redirect argument, a second run's scan set excludes the redirected
  path, and the two runs' derived-tier identity sets are still equal.
- **Assertion 2.3** — a redirect naming an existing file, or naming a path in the run's own scan set,
  exits non-zero and writes nothing. Test: point the redirect at the target's own `CLAUDE.md`; the
  file is byte-identical afterward.

## 3. Run state, keying, and concurrency

`${CLAUDE_PLUGIN_DATA}` is machine-global, not per-project. This machine alone carries multiple
worktrees of this repository plus a large ghq checkout root, so state keyed by working directory
would collide or fragment depending on where the operator happened to stand.

**State key.** `<state-key>` = `<repo-identity>/<worktree-discriminator>`.

- **`repo-identity`** — for a git repository, the first configured remote URL normalized to
  `host/owner/repo`, lowercased, with any `.git` suffix and credentials stripped. With no remote,
  `local/<sha256 of the canonicalized repo root>` truncated to 12.
- **`worktree-discriminator`** — `sha256` of the canonicalized worktree root, truncated to 8. Two
  worktrees of one repository on different branches legitimately hold different content and must not
  share a run report.

**Only the discriminator is load-bearing.** `repo-identity` buys a legible state directory and the
ability to enumerate every run against one repository; it carries no property. The discriminator
alone separates every report that must be separated, and Assertion 3.3 is satisfied by canonicalizing
the worktree root rather than by the remote URL. So if remote-URL normalization proves fiddly —
several remotes, rewritten URLs, no remote at all — **keying on the worktree hash alone loses nothing
this contract asserts.** Derived in [proportionality-gate.md](proportionality-gate.md), "The run
contract's own machinery, proportionality-tested per mechanism".

**Suppressions are keyed differently on purpose** — see §4. They are a decision about the
*repository*, not about a checkout, so they are shared across worktrees and, where the target is a
repository the operator owns, committed to it.

**Concurrency.**

- A read-only run takes **no lock against another read-only run**. Concurrent read-only runs are safe
  and are not serialized.
- **A read-only run is serialized against an applying one**, by a shared/exclusive form of the same
  lock or by reading from a stable snapshot. Raised by the cross-vendor review: the exclusive lock
  below excludes a second *applying* run and nothing else, so an unlocked reader overlapping an
  applier reads some surfaces before mutation and others after, and reports a finding set
  corresponding to no tree state — the same failure the report-location rule exists to prevent, with
  nothing in the output to reveal it. Which of the two mechanisms ships is Phase 6's; both satisfy
  Assertion 3.5, and taking neither does not.
- An applying run takes an **exclusive advisory lock** at `runs/<state-key>/lock`, containing the
  process id and an ISO-8601 start timestamp.
- A second applying run for the same `<state-key>` **refuses and exits non-zero** with the holder's
  pid and start time. It does not wait, because a sweep over a large tree can run for a long time and
  a silent queue looks like a hang.
- A lock whose recorded holder is not alive **and** whose timestamp is older than 30 minutes is stale
  and is reclaimed, with the reclamation reported in the run output.
- **"Not alive" is not decidable from a process id alone, and a stale lock must always have a
  recovery path.** Raised by the cross-vendor review. Operating systems reuse process ids, so after
  an applying run crashes its recorded id can name an unrelated long-lived process: the lock is far
  older than 30 minutes and its id still answers "alive", the conjunction above never fires, and
  every later applying run for that target is blocked permanently with no documented way out. The
  lock therefore records a **start identity** beside the process id — a value that differs when the
  id has been reused, such as the holder's start time — and liveness means both match.

  **The no-start-identity fallback was reclaiming live holders, and the cross-vendor review caught
  it.** Falling back to the age test alone means an applying run that legitimately exceeds 30 minutes
  — a large target, a slow filesystem, a long human gate — has its lock taken while it is still
  mutating, a second applier proceeds, and Assertion 3.1 is violated by the very mechanism written to
  uphold it. Reclaiming a *dead* holder and reclaiming a *slow* one are indistinguishable by age, so
  age cannot be the sole discriminator on any platform.

  The holder therefore **refreshes a heartbeat in the lock on a fixed interval**, and staleness is a
  heartbeat that has stopped advancing, not a lock that is old. A run that holds its lock for hours
  keeps it; a crashed run stops refreshing and is reclaimed within a small multiple of the interval,
  on every platform, with or without a start identity. Where a start identity is available it still
  short-circuits the wait, since a reused id is provable rather than inferred. And because a
  heartbeat can itself be defeated — a suspended process, a clock jump — an **explicit operator
  override** remains, reported when used. Three rungs, and what is binding is the pair of properties
  they exist to hold simultaneously: no lock is unreclaimable, and no live holder is reclaimed.
  Interval, multiple, and override spelling are Phase 6's.
- **Assertion 3.1** — two applying runs launched concurrently against one target: exactly one
  proceeds, the other exits non-zero naming the holder.
- **Assertion 3.2** — two read-only runs launched concurrently both complete, and their derived-tier
  identity sets are equal.
- **Assertion 3.3** — a run launched from a subdirectory of the target produces the same
  `<state-key>` as one launched from the root. Working directory must not be an input.

**The tree can move under a run, and the self-check must be able to say so.** Found by running the
pass (Phase 10): the target's `HEAD` and branch both moved mid-measurement, with a plugin rename
landing in between. The state key is computed once at the start and nothing re-validates it, so
*"any inequality over an unchanged tree is a defect"* is **unfalsifiable on a shared checkout** — an
inequality could mean a defect or could mean the tree moved, and the run cannot tell which.

- **Assertion 3.4** — a run records the target's revision **at start and at end**. When they differ,
  the run's determinism verdict is **`indeterminate`**, never `pass` and never `fail`, and the run
  reports both revisions. A determinism claim over a tree that changed underneath it is not a weaker
  claim; it is not a claim at all, and reporting it as either outcome is the error.

  **Strengthened by the cross-vendor review, not replaced: the revision is necessary and not
  sufficient.** An editor, a hook, or a sibling session can rewrite working-tree files without moving
  `HEAD`, and then both recorded revisions are equal while the lanes read different trees — 3.4
  reports a determinism `pass` for a report corresponding to no snapshot, which is the failure the
  assertion was added to close, arriving through the uncommitted door instead of the committed one.
  So the run records a **working-tree content digest** beside each revision, over the same
  enumeration the scan set uses, and `indeterminate` follows when *either* pair differs. The revision
  is what makes a mismatch legible to an operator; the digest is what makes it detectable at all.
- **Assertion 3.5** — a read-only run overlapping an applying run against one target never reports a
  finding set mixing pre-apply and post-apply content. Test: an apply that rewrites a fixture surface
  while a reader is mid-run; the reader's report matches exactly one of the two tree states.

## 4. Suppression, per target class

A deliberately-kept finding must not resurface. But "its site" differs by class, and one mechanism
does not fit all four. **The governing rule: an inline marker is permitted only where the pass may
write; everywhere else suppression is central and keyed by `finding_id`.**

| Target class | Suppression site | Why |
|---|---|---|
| A file in the target repo the pass may edit | inline marker at the finding's site | Local, reviewable in the same diff as the content it governs, and it travels with the content — the idiom `docs-hygiene:audit-noise` already uses |
| A `SKILL.md` or file this pass does not own | central suppression file in the target repo, keyed by `finding_id` | Editing a file you do not own to silence a report is a boundary violation dressed as configuration |
| A chezmoi-managed `~/.claude/**` file | central, in the user-scope suppression record; **never** an edit to the file | The Brief settles that user-scope surfaces are routed, never edited. An inline marker would be an in-place edit by another name |
| A registered byte-identical cluster copy | at the **canonical source**, never the copy | An inline marker in a copy makes it differ from its siblings and breaks the sync path — the same failure the exclusion set exists to prevent |

**The inline-marker row is conditioned on the surface being commentable, and one class in scope is
not.** Raised by the cross-vendor review. A prompt-type hook embedded in JSON has no comment syntax,
and both available placements fail: a marker in the JSON is not representable, and a marker inside
the decoded string changes the instruction Claude is actually shown *and* changes the excerpt the
suppression is keyed to — so the suppression perturbs the very finding it suppresses, and §1's
decode-then-normalize rule is what makes that unavoidable rather than an implementation slip. So **a
surface class with no representation for a comment outside the audited value routes to the central
record**, keyed by `finding_id`, exactly as a file the pass does not own does. This is derived from
§1's per-class excerpt table rather than observed: this repository has no prompt-type instruction
hook, so the class is in scope with no local instance.

**The central suppression record** lives at a documented path in the target repository, carries one
entry per suppressed finding with a required free-text reason and the date, and is **excluded
from the scan set** — otherwise suppressing a finding changes the tree and perturbs the next run.

**An entry stores the identity's constituents, not only the `finding_id`.** This read "one entry per
suppressed `finding_id`", and a bare truncated composite hash cannot satisfy two commitments §1
already makes:

- **Versioned-anchor matching has nothing to recompute from.** §1 adopts `anchor/v1` and SARIF
  §3.27.17's rule that matching happens on the greatest common version available in both results.
  An entry holding only a hash computed under `v1` cannot be re-evaluated under `v2` — so the first
  anchor-algorithm change discards the operator's entire suppression record, which is the exact
  failure versioning was adopted to prevent. Versioning the anchor and storing only its hash cancel
  each other out.
- **The tiered matching table cannot classify a suppressed finding.** Every row turns on *which*
  component moved — one anchor, both anchors, the `claim`, a `surface`. A stored hash answers only
  "same or different", so a suppressed finding could never be carried forward as
  `needs-reconfirmation`; it would go stale on any change.

So each entry carries `check`, `claim` with its bound parameters, the ordered `sites` carrying **every
anchor version the producing run emitted** for each site, and the `finding_id` as a **derived
convenience field for lookup**, not as the stored identity. The reason and date requirements are
unchanged.

**"Every version" rather than "its version tag" is the cross-vendor review's correction, and it is
the half that makes the rest work.** An entry storing one tagged anchor per site has no version in
common with a result produced under the next algorithm, so greatest-common-version matching has
nothing to compare and the entry goes stale on the bump — the same record-loss as storing a bare
hash, reached one step later. §1's migration rule and this storage shape are one mechanism in two
places; either alone leaves it undischarged.

**Writing a suppression is never an apply.** The inline-marker row above says *where* a suppression
lives when the pass may edit that file; it does not license the apply step to author one. No fix,
from any surface, may add or amend a suppression by either mechanism — inline marker or central
entry. Suppression is a deliberate operator action in its own step, and it is the one decision in
this contract that stays per-decision rather than per-run, because its effect is durable and silent.
Rationale, including the injection path this closes:
[checks-and-sweep.md](checks-and-sweep.md), "T2 — the suppression record as an attack surface".

- **Assertion 4.1** — a suppressed finding does not appear in the next run's report, and appears in a
  `suppressed` section with its reason, so suppression is visible rather than silent.
- **Assertion 4.2** — a suppression entry is resolved against the current finding set into **exactly
  one of three states**, and each has a distinct disposition:
  - **EXACT** — every stored constituent matches a current finding. The suppression applies
    silently, per the tiered table's first row.
  - **PARTIAL** — exactly one anchor differs and the other anchor and `(check, claim, both
    surfaces)` all match. The suppression **carries forward, marked `needs-reconfirmation`**, and is
    surfaced with the changed side named. It is **not** stale and must not be dropped.
  - **NONE** — no current finding matches on the constituents. Reported as **stale** rather than
    silently ignored. A suppression that has outlived its finding is how a corpus quietly loses a
    check.

  **This assertion was binary until now, and the binary form is what storing constituents breaks.**
  It read "a suppression entry whose `finding_id` no longer matches any finding is reported as
  stale" — a rule with only match and no-match in it. Under that rule the PARTIAL state resolves to
  `stale`, which **contradicts the tiered table's second row directly**: the table says carry the
  suppression forward for reconfirmation, and the binary assertion says report it as outlived. An
  operator editing a line near a suppressed finding would lose the suppression and be told it had
  expired. Found by the lane implementing the constituent-keyed record, which is the right place to
  find it: constituent keys shipped beside a binary stale rule are keys with no consumer.
- **Assertion 4.3** — adding a suppression does not change any other finding's `finding_id`.
- **Assertion 4.4** — no suppression mechanism writes to a path in the derived exclusion set. Test:
  attempt to suppress a finding in a registered cluster copy; the run refuses and names the canonical
  source instead.

## 5. Mid-run resumability

A run over 181 skills plus three scopes can be interrupted by compaction, a rate limit, or a crash.
Restarting from zero wastes the whole run and, worse, tempts an operator to narrow the scan.

- Findings persist **incrementally, per lane**, as each lane completes — not buffered to the end.
- A run manifest records, per lane: the lane id, its **input digest**, and its completion state.
- **Input digest** = `sha256` over the lane's ordered file list paired with each file's content hash,
  **and over the run basis** — the liveness basis (launch directory, effective merged
  `claudeMdExcludes`, external-import approval state, setting sources), the harness version, and the
  lane's detection version triple.
- **The non-file half is not optional, and the digest was file-only until the cross-vendor review.**
  §6 establishes every one of those values as an input the derived tier depends on. A file-only
  digest is unmoved when any of them changes, so a resume skips the completed lanes and assembles
  their stale findings beside freshly executed ones — a report corresponding to no single run basis,
  which is precisely what Assertion 5.1 claims cannot happen, failing silently while appearing to
  hold. Either the digest covers the run basis or the resume refuses; proceeding quietly is the one
  option this rules out.
- **Resume** re-runs only lanes that are incomplete or whose input digest has changed. A lane whose
  digest is unchanged and whose state is complete is skipped and its findings are carried forward.
- **Assertion 5.1** — kill a run after lane *k* completes, resume, and the final report equals the
  report of an uninterrupted run over the same tree. This is the property; everything else in §5 is
  mechanism.
- **Assertion 5.2** — modify one file belonging to a completed lane, then resume: that lane re-runs
  and no other completed lane does. **Conditional on the per-lane form — see below.**

**Per-lane digests are the richer of two forms, and which one ships is not settled here.** The
property at risk is that a run resumed across a tree change produces a report corresponding to no
single tree state, silently violating P1 while appearing to satisfy it. **A single tree-wide digest
that refuses to resume a moved tree closes that hole completely**, at a fraction of the manifest
cost. Per-lane digests buy *partial* resume on top — re-run only the lanes whose inputs moved — which
is an ergonomic gain of unmeasured size. Phase 10 measures lane cost and interruption frequency
against the real corpus and picks; **Assertion 5.2 is owed only under the per-lane form**, and
Assertion 5.1 holds under both. Derived in [proportionality-gate.md](proportionality-gate.md), "The
run contract's own machinery, proportionality-tested per mechanism".

## 6. The idempotence properties

### The tiers had to be re-derived first — the two-tier split did not survive contact

The original two tiers came from the `audit-instructions` catalog: `mechanical` (pattern-detectable
by static reading) and `behavioral` (ground truth is observed model behavior). The determinism
property was defined over the mechanical tier. **Verified against the implementations, that split
cannot carry it**, for two independently sufficient reasons.

- **No dispatched check reaches the report without model judgment.** `audit-instructions`' own
  `SKILL.md` says the deterministic pre-scan "is advisory and a grep cannot judge whether a
  rationale is genuinely present, so the lane refines every candidate rather than reporting it
  verbatim" — and Phase C then re-judges *every* removal or rewrite proposal, not only behavioral
  ones, where "a proposal the verifier defends is demoted to `info` or dropped." So a check the
  catalog labels `mechanical` passes through two model stages before it is a finding. Two runs can
  differ on a borderline case from ordinary sampling variance.
- **Half the dispatched catalog has no tier at all.** `claude-memory`'s `reference/criteria.md`
  carries **17 checks and zero occurrences** of `mechanical` or `behavioral`; it labels
  `FAIL`/`WARN`/`INFO`. A property defined over a vocabulary that half the catalog does not use is
  undefined for that half.

**Three tiers, replacing two.** The fix is not to weaken the guarantee everywhere — it is to state
it over the part of the run that genuinely is deterministic, which turns out to be substantial and
was previously unnamed.

| Tier | What it contains | Produced by | Property |
|---|---|---|---|
| **Derived** | the three-scope surface inventory, the exclusion set, shadowed-definition findings, and raw script candidate rows | scripts and enumeration only — no model in the path | **exact equality** |
| **Judged** | every finding from a dispatched catalog check, whatever that catalog calls it | a model, through lane refinement and the Phase C verifier | **stability tolerance** |
| **Delegated** | `/doctor`'s output | a prompt-based bundled skill | **no property**, diffed by nobody |

The derived tier is not a consolation prize. It is the answer to "did the sweep look at the same
things", which is the question an operator actually asks first — and it is where a silent scope
regression would show up. A surface that vanished from the inventory between runs is a defect the
old two-tier split could not have caught, because the inventory was never a reported artifact.

### Two inputs to the derived tier that are not the tree

Both surfaced 2026-07-24. They are separate problems with fixes an order of magnitude apart, and
both arise the same way: a **dead-surface finding** — "this instruction file is reachable from no
loaded entry point" — is derived-tier by construction (filesystem enumeration plus graph
reachability, no model in the path), so it inherits every promise P1 makes.

#### The harness version is an undeclared input

Such a finding's truth depends on what Claude Code *reads*, which is a property of the **harness
version**, not of the tree. Task #56's verification was version-pinned to v2.1.219 for exactly this
reason. If Claude Code ships `AGENTS.md` support, every dead-surface finding about an `AGENTS.md`
vanishes with no tree change and no catalog bump — and **P2 reads that as "a finding that vanished
without a fix", which it calls a defect, when it is correct behavior.** P3 breaks in the other
direction if a new dead-surface class appears. P1 breaks outright.

**Fix, and it is cheap:** the run manifest records the **harness version** beside the catalog
versions, and P3's clause becomes *tree unchanged, detection version unchanged, **and harness
version unchanged***.

**One consequence for this section's own claim.** The derived tier was described as "file
enumeration, registry parsing, `git worktree list`, and name comparison across a fixed precedence
order". That is now incomplete: it **also depends on a registry of harness behavior** — what this
version of Claude Code loads — which needs its own version pin and its own recheck trigger, exactly
as the criteria catalogs do.

#### Liveness is not a function of the tree

This one **falsifies Assertion 1.1 as originally written**. Verified inputs to liveness that live
outside the tree:

- **Launch directory.** Running in `foo/bar/` loads `foo/bar/CLAUDE.md` *and* `foo/CLAUDE.md`.
  [checks-and-sweep.md](checks-and-sweep.md) already flags this for `/context`; it applies to
  liveness generally.
- **`claudeMdExcludes`.** Patterns match absolute paths, configurable at user, project, local, or
  managed-policy layer, and **arrays merge across layers**. A file excluded on one machine is live on
  another — and the excluded file is then dead, so the finding is caused by a machine-local setting.
- **Declined external imports.** The approval dialog appears once; "If you decline, the imports stay
  disabled and the dialog doesn't appear again." Machine-local, persistent, and invisible in the
  tree.
- **`--setting-sources`** excluding `project` skips project rules;
  `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD` plus `--add-dir` adds more.

Assertion 1.1 requires ids stable "across runs, working directories, operating systems, and path
separators". A liveness-dependent finding cannot satisfy that, because liveness is not a function of
the tree — **run the sweep on a second machine and P1 is falsifiable by correct behavior, not by a
defect.**

**Fix, three parts:**

1. **Assertion 1.1 is scoped** to excerpt-granularity findings, and explicitly excludes
   liveness-dependent ones. Applied in §1.
2. **A liveness-dependent finding records its liveness basis as evidence** — the launch directory,
   the effective merged `claudeMdExcludes`, the setting-sources in play, and whether external
   imports were approved.
3. **P1's exact equality is scoped** to *same tree **and** same liveness basis*.

**Why this matters past the property.** Without it the sweep reports a machine-local configuration
as a repository defect, and tells a teammate to add an import that already exists and that *they*
declined. That is worse than missing the finding.

#### Liveness is three-valued, because a run observes the launch set only

The fix above makes liveness an *observed* input rather than a modelled one, which is what keeps a
dead-surface finding in the derived tier at all. But observation has a horizon, and it is narrower
than "the tree", so a two-valued live/dead classification is unsound over what a run can actually
see.

**Measured, not assumed** (task #54, Claude Code 2.1.220): the `InstructionsLoaded` hook payload
carries `{file_path, memory_type, load_reason, parent_file_path}` — the harness emits the load edge
natively, so reachability is observable rather than parsed. But a nested `sub/CLAUDE.md` produced
**no event at session start**, and the model did not know its codeword. What was *not* established
is whether a genuine nested load later in the session fires an event at all: no `nested_traversal`,
`path_glob_match`, or compaction-triggered `load_reason` value was ever observed.

**So a one-shot unattended run observes the launch set, and nothing licenses reading absence from
that set as death.** A nested `CLAUDE.md` that loads only when the model touches its subdirectory is
neither live at launch nor dead — it is **conditionally live**, and the sweep must carry that as its
own state:

- **A surface absent from the observed load set is classified `dead` only when no load edge could
  reach it** — it is outside every ancestor chain of the launch directory, **is not a descendant of
  it**, matches no path scope, and is the target of no import. Otherwise it is `conditionally-live`,
  recorded with the condition.

  **The descendant clause is the cross-vendor review's, and without it this rule contradicted the
  paragraph above it.** Ancestor chains are what a launch directory walks *up* through; an ordinary
  nested `sub/CLAUDE.md` under a root-launched run is a *descendant*, so the unamended test found no
  reaching edge and classified it `dead` — the exact surface the preceding paragraph establishes as
  conditionally live, and a false finding in the derived tier, where a false finding reproduces
  perfectly on every re-run. A descendant memory file is conditionally live unless its traversal is
  definitively impossible, which nothing a one-shot run observes can establish.
- **A `conditionally-live` surface is never reported as a dead-surface finding.** It is enumerated in
  the inventory, and its state is part of the liveness basis.
- **The failure this prevents is the worst shape available to a derived-tier check:** classifying a
  conditionally-live surface as dead yields a finding that is perfectly deterministic — it reproduces
  exactly, run after run, satisfying P1 — and perfectly wrong. Determinism is not correctness, and
  this is the one place in the contract where the two most plausibly get confused.

**Ground truth is two sources, not one, and that is a design constraint rather than an
implementation detail.** `InstructionsLoaded` fires for `CLAUDE.md` and `.claude/rules/*.md` **only**
— it does not see skill bodies, agent definitions, prompt-type hooks, or output styles, which are
most of D1's comparison set. `/context` covers more classes (Skills, Custom Agents, MCP Tools, each
with a Source column) but is markdown with no load edges. A single-source liveness design therefore
**silently under-covers D1's surface set**, which is the specific way this would fail without
looking like a failure. Neither source observes the managed-settings `claudeMd` key; that remains
untested, and is flagged rather than guessed.

**Consequence for the deliverable, stated plainly.** D1 is a judged finding, so the deliverable's
primary check does not contribute to the diff-clean gate. That was already conceded; what is new is
that *no* catalog check contributes, so the concession is not specific to D1 and is not evidence
against it.

### The properties

Stated as assertions over two runs, `R1` then `R2`. `D(R)` is the derived-tier identity set; `J(R)`
is the judged-tier set.

**Every property below is conditioned on one shared precondition, stated here once rather than
per-property.** The cross-vendor review found P1 and P4a missing a clause P3 already carried, and
stating it three times is what allowed two of the three to drift — so the **comparable-runs**
precondition is defined in one place and the properties cite it:

> `R1` and `R2` are **comparable** when their **target tree**, **liveness basis** (launch directory,
> effective merged `claudeMdExcludes`, import approvals, setting sources), **detection version
> triple** of every check consulted, and **harness version** are all equal.

A property asserts nothing about a non-comparable pair. This is not a weakening — it is what makes
the assertions falsifiable at all. Each of those inputs changes what a correct run finds: a harness
update legitimately moves the versioned registry of harness behavior that dead-surface
classification and raw script candidates are read against, and a catalog or prompt change
legitimately moves what the judged tier reports. Comparing across them makes correct behavior
indistinguishable from a defect, in the direction that raises a false alarm — the failure mode this
whole contract exists to avoid. The run already records all four, because all four affect detection;
the only thing that was missing was applying them uniformly. A non-comparable pair is **reported as
non-comparable, naming which input moved**, never as a pass and never as a failure: an unfalsifiable
claim is not a weaker claim, it is not a claim.

- **P1 — determinism, over the derived tier.** `R1` and `R2` **comparable** ⇒ `D(R1) = D(R2)`,
  exactly. Not a subset, not a tolerance: equal. This is assertable because nothing in `D` passes
  through a model — it is file enumeration, registry parsing, `git worktree list`, name comparison
  across a fixed precedence order, and a versioned registry of harness behavior. That last clause is
  precisely why the comparability precondition has to cover the harness and detection versions and
  not only the tree and the liveness basis: a versioned registry of harness behavior *is* a function
  of the harness version, so the paragraph above this one already conceded that a harness update
  breaks the unqualified form. P1 carried the liveness half and not the version half until the
  cross-vendor review found the asymmetry.
- **P2 — convergence, measured in the tier the fix acted on.** Accepted fixes applied between `R1`
  and `R2` ⇒ every accepted finding is absent from `R2`, in whichever tier it was reported, and every
  member of `D(R1) \ D(R2)` corresponds to a fix that was actually applied. A finding that vanishes
  without a fix is a defect in the check, not a success.

  **The tier clause replaces a strict subset over `D`, and the strict subset was wrong.** Raised by
  the cross-vendor review. D1 — the deliverable's only new check — is a judged finding and
  contributes nothing to the derived tier, so fixing one leaves the inventory, the exclusion set,
  shadowed definitions, and the raw script candidate rows all legitimately identical. `D(R2) ⊊ D(R1)`
  then *fails* the successful remediation of the primary detector, making the headline convergence
  gate unsatisfiable for the normal case. Strictness belongs in "every accepted finding is gone",
  which is the claim convergence is actually making; the containment half over `D` is P3's job and
  P3 already states it.
- **P3 — no spontaneous growth.** `R1` and `R2` **comparable** ⇒ `D(R2) ⊆ D(R1)`. The set may grow
  only on a detection-version bump, a harness-version bump, a change to the liveness basis, or a
  change to the tree — and a skill authored between runs is a change to the tree. That enumeration is
  exactly the negation of comparability, which is why the precondition is shared rather than restated
  here: P3 spelled all four out inline, P1 and P4a spelled out fewer, and the divergence was the
  defect.

  **The liveness clause was added to P1 and left out here, which made P3 read correct behavior as a
  defect.** Raised by the cross-vendor review. A changed launch directory, a changed effective
  `claudeMdExcludes`, a newly declined import, or different `--setting-sources` legitimately produces
  new derived dead-surface findings over an unmoved tree at an unmoved harness version — the exact
  case "Liveness is not a function of the tree" above was written for. P3 inherits that amendment for
  the same reason P1 took it, and omitting it from one of the two was an oversight rather than a
  distinction.
- **P3b — "catalog version" was the wrong version, and it left a hole.** Raised by the cross-vendor
  review. P3 originally keyed on `criteria.md`'s version, which covers only the criteria file. **The
  detection behavior for checks I6 and I10 does not live there.** It lives in
  `audit-instructions`' `SKILL.md`: Phase B names the pre-scan script that emits the I6 and I10
  candidate rows and instructs the lane that the script "is advisory and a grep cannot judge whether
  a rationale is genuinely present, so the lane refines every candidate rather than reporting it
  verbatim"; Phase C prompts the verifier to refute with a specific question and demotes or drops
  what it defends. Both are prompt text, and **`SKILL.md` carries no version at all.** Rewording
  either — tightening the refutation prompt, changing what "refines" means — moves the finding set
  with `criteria.md`'s version untouched, so P3 would report no growth was licensed while growth
  occurred. The same hole exists for the script itself, which is also unversioned.

  **Fix: P3 keys on a composite detection version, not on a catalog version.** For each dispatched
  check the run records a `detectionVersion` triple:

  ```text
  detectionVersion = (catalog_version, host_plugin_version, prompt_digest)
  ```

  - **`catalog_version`** — the criteria file's own version, as today.
  - **`host_plugin_version`** — the semver in the owning plugin's `.claude-plugin/plugin.json`. This
    is the seam that already exists and already moves: the repo requires a manifest bump plus a
    matching changelog heading for a content change, so editing `SKILL.md` prompt text is *already*
    a version event. P3 simply has to read that version instead of ignoring it.
  - **`prompt_digest`** — `sha256` over the check's own detection-behavior inputs, truncated to 12:
    the host `SKILL.md` and any script it names for that check. It exists because the manifest bump
    is a **convention** enforced by review, not a mechanism enforced by the file's own bytes; a
    prompt edit that skips the bump is exactly the silent case P3 must catch. The digest fails
    closed where the convention fails open.

  A growth in `D` is licensed when any component of the triple changed, and is a **P3 violation
  reported against the sweep** when none did. The composite is recorded per check in the report's
  existing per-catalog version block, so a diff of two reports shows which component moved.

  **Two consequences, stated rather than left implicit.** The digest makes an unrelated `SKILL.md`
  edit — a typo in a Gotchas line — read as a licensed-growth event, which is a false *permission*
  rather than a false alarm: it lets a real spontaneous growth pass unreported that run. That is the
  correct direction to fail, because the alternative silently blesses prompt rewrites. And the
  triple is the reason task **#43** (machine-readable versioning for the catalog) is necessary but
  not sufficient — versioning `criteria.md` alone does not close this; the plan item should carry
  both halves.
- **P3a — the inventory is part of the gate, not scaffolding for it.** The derived tier includes the
  three-scope surface inventory and the exclusion set, so a surface that silently drops out of scope
  between two runs **fails P1**. This is the property the old two-tier split could not express,
  because the inventory was never a reported artifact — and a silent scope regression is worse than a
  changed finding, since it looks like an improvement.
- **P4 — judged-tier stability, not identity.** Judged detection is a model judgement and cannot be
  made deterministic; an identity function normalizes how a finding is *reported* and cannot make the
  *detection* reproducible. So judged findings are reported in a separate section, excluded from
  P1–P3, and held instead to:
  - `|J(R1) △ J(R2)| ≤ max(2, ceil(0.10 × |J(R1)|))` over a **comparable** pair — **the stated
    tolerance**, measured across three consecutive runs, with the worst pair taken. The tolerance
    read "over an unchanged tree" until the cross-vendor review, and an unchanged tree is the weakest
    of the four comparability inputs: a changed catalog or prompt is precisely a change to what the
    judged tier is asked to find, so the judged set can move far past 10% while every run is correct,
    and P4a would then fail the sweep for model instability that is not instability at all. This is
    the same drift as P1's, in the tier where it is most likely, since a catalog revision is the
    ordinary way this deliverable evolves. **The metric is the symmetric difference, and it was
    one-directional growth until the cross-vendor review.**
    Assertion 1.5 routes an unaccounted judged closure here, so removals need somewhere to land; and
    a metric counting only additions lets a check that silently stops firing pass unremarked, which
    is the more damaging of the two directions. The constant is unchanged and is still the
    calibration Phase 10 tests;
  - no member of `J(R2)` contradicts an accepted suppression.
- **P4a — a violation has a consequence, or the property is decoration.** Exceeding the tolerance
  **fails the run's self-check and is reported as an instability finding against the sweep itself**,
  naming the checks whose output moved. It is not silently absorbed by recalibrating the constant.
  The tolerance may be revised only by an explicit, recorded decision citing the observed
  distribution — never as an implicit response to a failure. Without that clause the metric absorbs
  its own counterevidence, which is what a placeholder does.
- **P5 — `/doctor` is the delegated tier and is excluded from both properties.** It is prompt-based
  rather than fixed logic, so it cannot contribute to a determinism gate, and its output is reported
  in its own section and diffed
  by nobody.

**Why the tolerance is a floor of 2 rather than a pure percentage.** With a small judged set, a
percentage rounds to zero and the property becomes identity by the back door — which P4 exists to
deny. With a large set, the percentage dominates and the floor is irrelevant. The number is a
starting calibration, not a discovered constant: Phase 10's dogfood run is what tests whether 10% is
the right figure, and the figure is expected to move once there is evidence.

## Sanity check

The Phase 4 sanity check asks that this document state the identity tuple, the report location rule,
the state key, the concurrency posture, the per-class suppression surface, the checkpoint property,
and each idempotence property **as a condition a test could assert — not as prose intent**. Each is
above under a numbered assertion. The count is 13 identity/report/state assertions, 4 suppression
assertions, 2 resumability assertions, and 8 idempotence properties — P1, P2, P3, P3a, P3b, P4, P4a,
P5. Counted by grep over the assertion labels, not transcribed; the previous figure of 8 predated
Assertions 1.5 and 3.4 and was already stale before this round added 2.3 and 3.5.

**Two properties are now explicitly scoped rather than universal**, and the scoping is the honest
form: Assertion 1.1 holds for excerpt-granularity findings, and P1's exact equality holds for a
fixed tree *and* a fixed liveness basis. Both were falsifiable as originally written — not by a
defect in the sweep, but by correct behavior on a second machine.

**What this document deliberately does not decide.** The report's concrete schema, the suppression
file's path and format, and the lane decomposition are Phase 6 design, because they depend on the
sweep's dispatch structure. This document constrains them; it does not specify them.
