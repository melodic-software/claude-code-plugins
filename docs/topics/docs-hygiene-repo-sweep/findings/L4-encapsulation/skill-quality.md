# L4 encapsulation. Leaked skills in `plugins/skill-quality`

3 violations, all into `skill-quality:check`, all naming the same private file. Two of the three are
in `docs/PLUGIN-PHILOSOPHY.md`, the repo's own doctrine document, and one of those is a row in its
**Convention registry**, which is a live routing table other plugins are told to consult.

**Owning skill:** `skill-quality:check` (`plugins/skill-quality/skills/check/`).
**Private surface reached:** `reference/fresh-eyes-declarations.md`.
**Leak kind:** private subdir (3 of 3).

A detection note worth recording: this path is written in its short plugin-relative form
(`skills/check/reference/fresh-eyes-declarations.md`) with the owning plugin named only in
surrounding prose. Two plugins in this repo ship a `check` skill (`skill-quality` and
`instruction-placement`), so a purely mechanical resolver has to guess. Confirmed by file existence:
`plugins/skill-quality/skills/check/reference/fresh-eyes-declarations.md` is present,
`plugins/instruction-placement/skills/check/reference/fresh-eyes-declarations.md` is not.

## V-sq-01. `docs/PLUGIN-PHILOSOPHY.md:581`, convention registry row

Verbatim:

```text
| Fresh-eyes declaration pattern contract | `skill-quality` plugin (`skills/check/reference/fresh-eyes-declarations.md`) |
```

Every other row in that table points at a `docs/conventions/<topic>/` directory. This is the one row
that points inside a skill, and the asymmetry is the finding: the registry's own rule is that a
cross-plugin convention lands in an owner doc, and this convention did not.

**Public surface element:** none carries the content. The fresh-eyes declaration grammar, its closed
class set, and its exemption directive are consumed by third-party skill authors, which is
cross-plugin shared vocabulary by definition. This is **Path A. promote out**, and the target is the
one the registry itself prescribes.

**Remediation spec:**

1. Create `docs/conventions/fresh-eyes-declarations/README.md` carrying the grammar, the canonical
   wording, the closed class set, and the exemption-directive syntax.
2. Rewrite `plugins/skill-quality/skills/check/reference/fresh-eyes-declarations.md` to cite the
   convention doc rather than own the text.
3. Rewrite the three call sites.

**Replacement text:**

```text
| Fresh-eyes declaration pattern contract | [`docs/conventions/fresh-eyes-declarations/`](conventions/fresh-eyes-declarations/README.md) |
```

## V-sq-02. `docs/PLUGIN-PHILOSOPHY.md:1056`

Verbatim:

```text
(`skills/check/reference/fresh-eyes-declarations.md`), where the conformance check points third-party
```

**Replacement text (post-promotion):**

```text
([`docs/conventions/fresh-eyes-declarations/`](conventions/fresh-eyes-declarations/README.md)), where the conformance check points third-party
```

**Route-only alternative, if the promotion is deferred:**

```text
(`/skill-quality:check`), where the conformance check points third-party
```

## V-sq-03. `plugins/skill-quality/README.md:44`

A plugin README is an external consumer under the contract.

Verbatim:

```text
  reason-less directives fail. Contract: `skills/check/reference/fresh-eyes-declarations.md`.
```

**Replacement text (post-promotion):**

```text
  reason-less directives fail. Contract: `docs/conventions/fresh-eyes-declarations/`.
```

**Route-only alternative:**

```text
  reason-less directives fail. Contract: `/skill-quality:check`.
```

## Legal hits noted for the record, not counted as violations

`docs/topics/context-engineering-claude-5/design/checks-and-sweep.md:523` cites the same private path
inside a design record ("are cited by heading, not..."). Classified KIND-1 meta-prose: a design
record narrating what it inspected. It goes stale rather than breaking, and it is not a live routing
surface. If the promotion in V-sq-01 lands, updating it is optional courtesy, not remediation.

## Cross-lane observations

- L3 (SSOT): the fresh-eyes contract has at least three live consumers (PLUGIN-PHILOSOPHY twice, the
  plugin README, plus third-party authors the doc addresses), so it clears L3's Rule of Three. The
  artifact L3 would mint is the same `docs/conventions/fresh-eyes-declarations/README.md` this lane
  needs. Land one, not two.
