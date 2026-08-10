# Arid-node suppression — this plugin's read of the finding-suppression contract

The record at `.claude/mutation-testing-arid.md` is a **finding-suppression** surface. That
convention owns the keys, the merge form, the precedence rule, and the obligations on a consuming
skill; this file owns only what the convention leaves to each consumer — **how a mutation finding
derives its `finding_id` and constituents** — plus the reporting shape that satisfies the
obligations.

Read the convention itself for anything not stated here. Where the two appear to disagree, the
convention wins and this file is the defect.

## The five required keys, mapped to a mutation finding

Every entry carries all five. **An entry missing any required key is malformed and does not
suppress** — it is reported as malformed, never silently partially parsed.

| Key | For a mutation finding |
|---|---|
| `check` | The operator that produced the mutant, qualified by this plugin: `mutation-testing/operator/SBR`, `.../ROR`, `.../AOR`, `.../LCR`, `.../UOI`. Never the tool's own internal mutator name — those differ per ecosystem and the record must survive a tool swap. |
| `claim` | The canonical claim id plus bound parameters, **never free prose**: `arid(kind=<node-kind>)`. The `<node-kind>` vocabulary is enumerated in full in the `principles` skill's [`scaling-and-suppression.md`](../../principles/reference/scaling-and-suppression.md) ("The node-kind vocabulary") — that table is the whole list, and a survivor fitting none of it **is not arid** and must not be suppressed. Validation is membership in that table, not "looks like an identifier". |
| `sites` | One `{surface, anchor/v1}` for an ordinary mutation finding. `surface` is the repo-relative source path. Anchor derivation below. |
| `reason` | Why killing this mutant would not improve the suite. Non-empty, and a sentence a reviewer a year from now can judge — not "arid" restated. |
| `date` | ISO-8601, when it was accepted. |

`reason` and `date` alone are **not** a valid entry. An early draft of this plugin described the
record as carrying only those two; that was wrong, and an entry shaped that way is malformed.

## Anchor and id derivation — this consumer's contract

The convention's anchor discriminator is `sha256(heading_path)` truncated to 8 hex, where
`heading_path` is the ordered enclosing headings of the excerpt. Source code has no headings, so
this plugin binds `heading_path` to the **ordered enclosing scope path** of the mutated node —
outermost first, each element as written in the source:

```text
["<file basename>", "<class or module>", "<function or method>"]
```

A node at file scope has a one-element path. The path is what the *language* nests, not what the
formatter indents: a nested closure contributes an element only if the language names it.

Both derivations are the convention's, unchanged, with `US = "\x1f"`:

```python
import hashlib
US = "\x1f"

def discriminator(heading_path):          # ordered enclosing scope path, above
    return hashlib.sha256(US.join(heading_path).encode("utf-8")).hexdigest()[:8]

def finding_id(check, claim, sites):      # sites: [(surface, anchor), …]
    parts = [check, claim]
    for surface, anchor in sorted(sites, key=lambda p: (p[0].encode(), p[1].encode())):
        parts += [surface, anchor]
    return hashlib.sha256(US.join(parts).encode("utf-8")).hexdigest()[:16]
```

**The constituents are authoritative and the key is derived from them.** An entry whose stored
constituents do not hash to its own key is malformed and does not suppress — the same disposition a
missing `reason` gets. Never hand-write a key; always re-derive it after editing any constituent.

The anchor key carries its algorithm version (`anchor/v1`) so a site may hold several versions at
once; comparison uses the greatest version both sides carry.

## Layering — a personal entry is a draft, not a suppression

This surface sits in the cascade's **policy-floor precedence-inversion** class. Two consequences,
and the second is the one most easily got wrong:

1. On a direct conflict for the same `finding_id`, **the team layer wins** — the reverse of the
   cascade default. What that protects is narrow and worth stating: two entries sharing an id have
   identical `check`, `claim`, and `sites` by construction, so the only fields that can differ are
   `reason` and `date`. The inversion protects the team's recorded *justification*.
2. **A personal-layer entry for a `finding_id` the team layer does not carry does not suppress.** It
   is reported as `personal-only, not applied`, naming promotion to the team layer as what makes it
   take effect. Absence from the team layer *is* the team's unsuppressed state; honoring a
   personal-only entry would let one developer hide a finding the team never accepted.

So `.claude/mutation-testing-arid.local.md` is a **draft** surface. Describing it as "layered like
the config" is wrong in exactly the direction that matters — the config's later layers do take
effect, and this record's do not.

## Obligations this skill must meet

1. **Resolve layers per the cascade** — anchor at the repo root, read every layer that exists, merge
   **per key** (never as a list; a list taken whole would let one personal entry discard the team's
   entire accepted set), report the contributing layer, degrade soft on a malformed layer.
2. **Emit a `suppressed` section listing every suppressed finding** with its `reason`, `date`, and
   contributing layer, **and every entry that did not suppress** — each `personal-only, not applied`
   entry and each malformed one, with what makes it malformed. Suppression is visible, never silent,
   and so is a suppression the operator wrote that the contract declined to enact.
3. **Resolve every IN-SCOPE entry to one of four dispositions**, reporting all but the first.

   **Scope first, and this qualification is load-bearing.** The convention's obligation is written
   for a consumer that examines its whole corpus each run. This skill is diff-scoped by design, and
   narrows further by dropping uncovered lines — so on any ordinary run most entries sit outside what
   was examined. Every other entry is **not-examined**, left untouched, and reported under a separate
   count. It is never run through the dispositions below.

   **In scope means the entry's own anchored node, not its file.** An entry is in scope when the node
   its `anchor/v1` identifies is one this run actually generated a mutant for — that is, inside
   Phase 1's changed-line set *after* the coverage drop. File-level scoping is not sufficient and
   fails the same way: a file with a suppressed survivor at line 100 and an unrelated edit at line 10
   has its `sites[].surface` examined, yet no mutant is ever generated at line 100, so there is no
   observation to classify the entry — and it would fall through to CLOSED on every such run. The
   granularity of the scope test must match the granularity of mutant generation, which is the line.

   Without that qualification the contract inverts: an out-of-scope entry is "absent from this run"
   for a reason none of CLOSED's accounted outcomes covers — not fixed, not retired, not missing —
   so it would land on UNEXPLAINED DISAPPEARANCE and fail this skill's own self-check on essentially
   every run. A self-check that fails routinely is a self-check nobody reads. `--full` does not close
   the gap either, because the coverage-based drop still removes lines from its mutant set for
   reasons unrelated to fix or retirement.

   The staleness the convention protects is therefore reached incrementally: an entry is judged when
   its own node is next examined, which is also when someone is looking at that code.
   - **SAME, UNCHANGED** — every site's anchor matches and `(check, claim)` match. Applies silently.
   - **SAME, CHANGED** — pairwise findings only. Mutation findings are single-site, so this
     disposition is unreachable here; a single-site anchor change is the row below.
   - **OLD CLOSED, NEW OPENED** — the anchor changed, or `claim` changed, or the surface changed. The
     old entry goes **stale**, never silently dropped; the new survivor is reported unsuppressed.
     This is the common case after a refactor, and reporting it is the point: the edit may have *been*
     the fix.
   - **CLOSED** — the finding is absent although **its own anchored node was examined** — this run
     generated a mutant there and no survivor matched the entry. Account for it as
     exactly one of: matched to an applied fix; **retired with its check**, when its operator is
     absent from this run's configured set (name the operator and the transition); or reported as an
     **UNEXPLAINED DISAPPEARANCE**, which fails this skill's own self-check. An entry keyed to a
     retired operator goes stale rather than being deleted, so an operator returning under its old
     name cannot silently re-apply a decision nobody has seen since. An entry whose anchored node
     this run did not generate a mutant for never reaches this row — it is not-examined, per the
     scope rule above.
4. **Refuse a suppression written into a path the audit excludes** — a vendored tree, a synced copy,
   a worktree — and name the canonical source instead.
5. **Never edit a user-scope file.** A `~/.claude/**` finding is routed as a recommendation; that
   tree is commonly owned by a dotfiles manager that will fight an in-place edit.

## Proposing an entry

This skill **proposes** and never writes a suppression unprompted. A proposal is complete only when
it carries all five keys with the id derived from them, so the user is accepting a reviewable record
rather than a hex string:

````markdown
```yaml
suppressions:
  <derived finding_id>:
    check: mutation-testing/operator/SBR
    claim: arid(kind=log-call)
    sites:
      - surface: src/pricing.ts
        anchor/v1: "e:<excerpt-hash>:<discriminator>"
    reason: "Structured-logging call; killing this mutant would assert on log emission, which no consumer depends on."
    date: 2026-08-10
```
````

**An equivalent mutant is never suppressed.** The convention is explicit that its record is not for
"a finding that is simply wrong (fix the check)" — filing equivalence as a suppression hides a
defective check behind an accepted finding. Route it as a check-configuration change instead.
