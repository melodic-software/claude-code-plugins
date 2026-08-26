# L7 findings: `I-songwriting`

Slice audited: 104 `AGENT` rows (12 `T2`). Predicates emitted here: P3, filed as one batch.

Verbatim source quotes and proposed replacements are in fenced `text` blocks so wave 3 can match
them against the real files.

## I-1 · batch · `See <link> for <payload>` opens on the routing verb (T3, S3)

31 pointers across 16 files under `plugins/songwriting/context/pat-pattison/` and
`plugins/songwriting/skills/suno/context/` open on `See`. Every `T2` file in this group is clean;
every hit is `T3`.

This is one house pattern applied consistently, not 31 independent defects. Three representative
citations, verbatim.

`plugins/songwriting/context/pat-pattison/research/prosody.md:1055`:

```text
See [meter](meter.md) "Structural Pentad" for the paradigm-by-paradigm
```

`plugins/songwriting/context/pat-pattison/research/five-compositional-elements.md:118`:

```text
See [rhyme strategy](rhyme-strategy.md) for scheme as a control of
```

`plugins/songwriting/context/pat-pattison/research/workflows.md:266`:

```text
See [stable / unstable](stable-unstable-meta.md).
```

The transform is mechanical: move the payload in front of the verb. The first one becomes:

```text
Paradigm-by-paradigm treatment: see [meter](meter.md) "Structural Pentad"
```

**Recommended disposition: do not apply.** Severity is S3 on all 31, the corpus is internally
consistent, and this sub-tree is cross-referenced densely enough that a partial rewrite would leave
two competing pointer styles in one reading path. The finding is recorded so the reconciliation pass
can see it and decide; if the orchestrator wants it applied, apply all 31 in one edit or none.

The three pointers with no payload at all (`workflows.md:266`, `workflows.md:122`, `form.md:1317`)
additionally fail P4, which is `L2-progressive-disclosure`'s blind-pointer shape. If L2 files those
three, take L2's rewrite for them.
