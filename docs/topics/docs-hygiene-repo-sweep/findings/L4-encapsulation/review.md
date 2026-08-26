# L4 encapsulation. Leaked skills in `plugins/review`

16 violations. `review/fanout` is the most-leaked skill in the repo (12 inbound cites from a single
repo-level convention doc); `review/quality-gate` adds 4.

## V-review-01 through V-review-12. `docs/conventions/detector-findings/README.md` depends on `review/fanout`'s private `context/`

**Owning skill:** `review:fanout` (`plugins/review/skills/fanout/`).
**Private surface reached:** `context/default-mode.md`, `context/fix-pass-mode.md`,
`context/findings-normalization.md`. All three are private subdirectory files.
**Leak kind:** private subdir.

This is the highest-severity finding in the lane, and the only one where the citing file states the
dependency as a contract. `docs/conventions/detector-findings/README.md` is a repo-level convention
doc that other plugins are told to implement. Its "External authority" section names three files
inside one skill's private body as the authority its own rules defer to, and its opening paragraph
says the shape "is owned by" one of them and that "This doc never restates it". Every producer that
implements this convention therefore transitively depends on `review:fanout`'s internal file layout.

`review:fanout` cannot rename, split, or merge `context/default-mode.md`,
`context/fix-pass-mode.md`, or `context/findings-normalization.md` without breaking a convention doc
that at least one other plugin implements, and nothing in the build would notice.

**Public surface element it should cite instead:** none exists that carries the content. The
findings-file shape, the severity/confidence rank order, and the consumer algorithm are cross-plugin
shared vocabulary by the convention doc's own framing, so this is a **Path A. promote out**, not a
Path B route. The shape belongs in the convention doc's own owner directory (or a sibling under
`docs/conventions/`), with `review:fanout` citing it from the inside.

### Remediation spec

1. Promote the three cited sections out of `review:fanout` into
   `docs/conventions/detector-findings/findings-file-shape.md` (new spoke of the existing owner
   directory, which already has a `CHANGELOG.md` and a README). Carry the findings-file shape, the
   merge-set and consumption-marking algorithm, and the normalization rank order.
2. Rewrite `plugins/review/skills/fanout/context/default-mode.md`,
   `context/fix-pass-mode.md`, and `context/findings-normalization.md` to cite the promoted doc
   rather than own the text, so the body is not dual-maintained.
3. Rewrite the twelve call sites below.

| # | `path:line` | Verbatim | Replacement text |
|---|---|---|---|
| V-review-01 | `docs/conventions/detector-findings/README.md:9` | ``[`plugins/review/skills/fanout/context/default-mode.md`](../../../plugins/review/skills/fanout/context/default-mode.md)`` | ``[`findings-file-shape.md`](findings-file-shape.md)`` |
| V-review-02 | `docs/conventions/detector-findings/README.md:79` | ``  [`plugins/review/skills/fanout/context/fix-pass-mode.md`](../../../plugins/review/skills/fanout/context/fix-pass-mode.md)`` | ``  [`findings-file-shape.md`](findings-file-shape.md) "Consumer algorithm"`` |
| V-review-03 | `docs/conventions/detector-findings/README.md:83` | ``  [`findings-normalization.md`](../../../plugins/review/skills/fanout/context/findings-normalization.md)`` | ``  [`findings-file-shape.md`](findings-file-shape.md) "Rank order"`` |
| V-review-04 | `docs/conventions/detector-findings/README.md:109` | ``   ([`findings-normalization.md:72`](../../../plugins/review/skills/fanout/context/findings-normalization.md)),`` | ``   ([`findings-file-shape.md`](findings-file-shape.md) "Rank order"),`` |
| V-review-05 | `docs/conventions/detector-findings/README.md:261` | ``([`fix-pass-mode.md`](../../../plugins/review/skills/fanout/context/fix-pass-mode.md) "Step 2"), so`` | ``([`findings-file-shape.md`](findings-file-shape.md) "Consumer algorithm, step 2"), so`` |
| V-review-06 | `docs/conventions/detector-findings/README.md:303` | ``  ([`fix-pass-mode.md`](../../../plugins/review/skills/fanout/context/fix-pass-mode.md) "Step 2") has`` | ``  ([`findings-file-shape.md`](findings-file-shape.md) "Consumer algorithm, step 2") has`` |
| V-review-07 | `docs/conventions/detector-findings/README.md:482` | ``[`fix-pass-mode.md`](../../../plugins/review/skills/fanout/context/fix-pass-mode.md) "Step 1: Build`` | ``[`findings-file-shape.md`](findings-file-shape.md) "Consumer algorithm, step 1: Build`` |
| V-review-08 | `docs/conventions/detector-findings/README.md:497` | ``[`fix-pass-mode.md`](../../../plugins/review/skills/fanout/context/fix-pass-mode.md) "Step 5" owns`` | ``[`findings-file-shape.md`](findings-file-shape.md) "Consumer algorithm, step 5" owns`` |
| V-review-09 | `docs/conventions/detector-findings/README.md:506` | ``[`fix-pass-mode.md`](../../../plugins/review/skills/fanout/context/fix-pass-mode.md) "Step 1" — meet`` | ``[`findings-file-shape.md`](findings-file-shape.md) "Consumer algorithm, step 1", meet`` |
| V-review-10 | `docs/conventions/detector-findings/README.md:628` | ``- [`plugins/review/skills/fanout/context/default-mode.md`](../../../plugins/review/skills/fanout/context/default-mode.md) — the findings-file shape this contract points at and never copies.`` | ``- [`findings-file-shape.md`](findings-file-shape.md), the findings-file shape this contract points at and never copies. `/review:fanout` consumes it.`` |
| V-review-11 | `docs/conventions/detector-findings/README.md:629` | ``- [`plugins/review/skills/fanout/context/fix-pass-mode.md`](../../../plugins/review/skills/fanout/context/fix-pass-mode.md) — the consumer algorithm, including merge-set construction and consumption marking.`` | ``- [`findings-file-shape.md`](findings-file-shape.md) "Consumer algorithm", the merge-set construction and consumption marking `/review:fanout fix` performs.`` |
| V-review-12 | `docs/conventions/detector-findings/README.md:631` | ``- [`plugins/review/skills/fanout/context/findings-normalization.md`](../../../plugins/review/skills/fanout/context/findings-normalization.md) — the rank order that makes `low` worse than omission.`` | ``- [`findings-file-shape.md`](findings-file-shape.md) "Rank order", the ordering that makes `low` worse than omission.`` |

Line 630 of the same file cites `plugins/review/context/severity.md` and line 632 cites
`plugins/review/reference/topic-docs.md`. Both are plugin-level, outside every `skills/<X>/`
directory, so both are legal and are left alone. That contrast is the argument for the fix: the
convention doc already cites plugin-shared docs correctly; only the three skill-private ones leak.

## V-review-13. `docs/conventions/native-references/README.md:127` names a private file as the pattern exemplar

**Owning skill:** `review:quality-gate`. **Private surface reached:** `context/pr.md`.
**Leak kind:** private subdir. **Confidence:** medium. The cite is illustrative rather than
load-bearing, but a reader is expected to open it, and the path is the only address given.

Verbatim:

```text
(`plugins/review/skills/quality-gate/context/pr.md`, `plugins/review/skills/fanout/SKILL.md`):
```

**Public surface element:** the `pr` mode of `/review:quality-gate` (its documented action router
lists `pr` among the modes), plus `plugins/review/skills/fanout/SKILL.md` which is already a legal
bare-`SKILL.md` cite.

**Replacement text:**

```text
(`/review:quality-gate pr` and `plugins/review/skills/fanout/SKILL.md`):
```

## V-review-14. `docs/conventions/native-references/README.md:183` adopter registry row

**Owning skill:** `review:quality-gate`. **Private surface reached:** `context/pr.md`.
**Leak kind:** private subdir. **Confidence:** medium, this is a tracking registry rather than a
content dependency, but the row goes stale silently when the skill refactors.

Verbatim:

```text
| `plugins/review/skills/quality-gate/context/pr.md`, `plugins/review/skills/fanout/SKILL.md` | The organic Boundary pattern this doc generalizes; adopts the phrasing rules on next touch |
```

**Public surface element:** the skill identity, not a file inside it.

**Replacement text:**

```text
| `/review:quality-gate` (`pr` mode), `plugins/review/skills/fanout/SKILL.md` | The organic Boundary pattern this doc generalizes; adopts the phrasing rules on next touch |
```

## V-review-15. `plugins/review/README.md:83` reaches into its own plugin's skill

**Owning skill:** `review:quality-gate`. **Private surface reached:** `context/pr.md`.
**Leak kind:** private subdir. A plugin README is an external consumer under the contract: it is not
carried when the skill directory is ripped and pasted, and it is one of the surfaces the contract
names explicitly.

Verbatim:

```text
  [`skills/quality-gate/context/pr.md`](skills/quality-gate/context/pr.md) and
```

**Public surface element:** `/review:quality-gate pr`.

**Replacement text:**

```text
  `/review:quality-gate pr` and
```

## V-review-16. `plugins/review/skills/fanout/SKILL.md:112` sibling-skill reach

**Owning skill:** `review:quality-gate`. **Private surface reached:** `context/pr.md`.
**Leak kind:** private subdir. The contract's `scripts/` carve-out is explicit that skill-to-skill
citation stays slash-only; this is the plain-prose form of the same reach.

Verbatim (the cite within the line):

```text
[`quality-gate/context/pr.md`](../quality-gate/context/pr.md)'s "Boundary" section describes all three surfaces and what each one mutates; that description is not repeated here.
```

**Public surface element:** `/review:quality-gate pr`.

**Replacement text:**

```text
`/review:quality-gate pr` describes all three surfaces and what each one mutates; that description is not repeated here.
```

## Cross-lane observations

- L3 (SSOT): `docs/conventions/detector-findings/README.md` states outright that it "never restates"
  the shape it points at. If L3 mints an SSOT for the findings-file shape, that artifact is the same
  artifact V-review-01..12 needs. The two lanes should land one file, not two.
- L1 (derivability): none of the three `review/fanout` context files is a deletion candidate. They
  are the facts; only their address is wrong.
