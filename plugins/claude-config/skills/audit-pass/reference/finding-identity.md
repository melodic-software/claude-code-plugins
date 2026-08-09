# audit-pass — finding identity

This file owns §1: what identifies a finding — the `(check, claim, sites)` tuple, `surface`, `anchor`,
normalization, and the derived `finding_id`.

Terms: [terms.md](terms.md). Full index: [run-contract.md](run-contract.md).

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
