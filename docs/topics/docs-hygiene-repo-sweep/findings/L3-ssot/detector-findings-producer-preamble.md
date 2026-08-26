# Cluster: detector-findings-producer-preamble

**Concept.** The opening contract of a detector-findings producer slice: fetch the producer
contract before the first write, declare that the contract wins where the two disagree, and refuse
to write when the contract cannot be fetched.

**Bucket.** N>=3 (four instances).

**Owner (existing).** `docs/conventions/detector-findings/README.md`, published at
`https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/detector-findings/README.md`.
Relevant headings: `## Where the file goes` (line 32), `## Three emitters, one statement of each
mechanic` (line 522), `## Adopters` (line 602).

**Portability note.** Unlike most clusters in this lane, the citation target here IS reachable at
runtime: every slice already fetches the contract over HTTPS rather than by repository path. That
is why these four files are the strongest `trim-to-citation` candidates in the corpus. They are
also, already, the closest to correct.

## Instances (Tier 0)

| File | Preamble lines |
|---|---|
| `plugins/ai-slop/skills/audit/context/persist-findings.md` | 1 to 12 |
| `plugins/claude-config/skills/audit-instructions/context/persist-findings.md` | 1 to 12 |
| `plugins/docs-hygiene/skills/audit-noise/context/persist-findings.md` | 1 to 12 |
| `plugins/mutation-testing/skills/audit/context/persist-findings.md` | 1 to 14 |

Byte-identical spine, present in all four:

> It owns the shape's authority, where the file goes, the producer-computed fields, the coexistence
> obligations, the self-ignore guard, and what a minimal producer may omit. This file adds only what
> [SLOT] decides for itself and cites the contract for the rest. Where the two disagree, the
> contract wins and this file is the defect.

The `[SLOT]` is genuinely per-instance (`an ai-slop run`, `an \`audit-instructions\` run`,
`an \`audit-noise\` run`, `a mutation run`), so this is identify form (e), shared framing with
per-instance data.

## The four drift points

**1. Title noun disagrees.**

- `plugins/ai-slop/skills/audit/context/persist-findings.md:1`
  > `# Persisting findings: this plugin's read of the detector-findings contract`
- `plugins/claude-config/skills/audit-instructions/context/persist-findings.md:1`
  > `# Persisting findings: this skill's read of the detector-findings contract`
- `plugins/docs-hygiene/skills/audit-noise/context/persist-findings.md:1`
  > `# Persisting findings: this skill's read of the detector-findings contract`
- `plugins/mutation-testing/skills/audit/context/persist-findings.md:1`
  > `# Persisting survivors — this plugin's read of the detector-findings contract`

`plugin's` versus `skill's` is not cosmetic. The file sits under one skill's `context/`, and the
`ai-slop` and `mutation-testing` plugins each ship exactly one such file, so `plugin's` reads as a
plugin-wide claim that neither file is scoped to make. Two files say one thing, two say the other,
and nothing declares which is house form.

**2. Punctuation after the fetch directive.** Three files use `:` and a following line; the
mutation-testing file uses ` — ` (an em dash), which
`.claude/rules/vendor-docs-are-not-style.md` and the house style guide at
`plugins/ai-slop/skills/audit/reference/rewrite-guide.md` forbid in this repo's own instruction
surfaces.

**3. The refusal clause tail diverges.**

- Three files (`ai-slop:10`, `claude-config:10`, `docs-hygiene:10`):
  > Inventing a destination reports success while the consumer never scans that path.
- `plugins/mutation-testing/skills/audit/context/persist-findings.md:13`:
  > Inventing a destination is the one failure the contract's own resolution section exists to
  > prevent, and a plausible guess is worse than no file: the run

The mutation-testing tail is stronger and cites the contract's own resolution section. The other
three carry the weaker form.

**4. The script-ownership paragraph diverges beyond its slot.**

- `plugins/ai-slop/skills/audit/context/persist-findings.md:29`
  > A repo-scale run produces thousands of rows; composing them in prose is exactly the hand-transform
  > the fleet's scripting discipline forbids, and the script owns the mechanical half: cell assembly,
  > escaping, tier lookup (a mirror of the crosswalk — the crosswalk row is authoritative), rank
  > ordering, the non-overwrite suffix, and the `## Surfaces` counts.
- `plugins/docs-hygiene/skills/audit-noise/context/persist-findings.md:55`
  > The script owns the mechanical half: the fence recomputation, cell assembly and escaping, tier
  > lookup (a mirror of the crosswalk — the crosswalk row is authoritative), rank ordering, the
  > non-overwrite suffix, and the `## Surfaces` counts.

`the fence recomputation` is a real `audit-noise`-specific item, so the difference is partly signal.
`A repo-scale run produces thousands of rows; ...` is `ai-slop`-specific framing, also signal. What
is drift is that the shared list following `the mechanical half:` differs in order and connective
between the two.

## Verdict and remedy

**Not `trim-to-citation`.** The preamble is what makes each slice legible on its own, and the
contract's `## Three emitters, one statement of each mechanic` heading indicates the contract
itself expects adopters to carry a per-adopter statement. Deleting the preamble in favor of a bare
pointer would produce a file whose first line is a link, which is the blind-pointer shape L2 flags.

**`normalize-wording`.** Align all four preambles onto one spine, keeping each file's genuine
per-adopter slot. **No new artifact.** The concept already has an owner with a live URL.

### Canonical preamble

Replacement text for lines 1 through 12 of each of the four files. `<SLOT>` is the only variable;
`<NOUN>` is `findings` except in the mutation-testing file where `survivors` is its real subject.

```text
# Persisting <NOUN>: this skill's read of the detector-findings contract

**Read the producer contract before the first write**:
<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/detector-findings/README.md>.
It owns the shape's authority, where the file goes, the producer-computed fields, the coexistence
obligations, the self-ignore guard, and what a minimal producer may omit. This file adds only what
<SLOT> decides for itself and cites the contract for the rest. Where the two disagree, the
contract wins and this file is the defect.

**If the contract cannot be fetched, do not write.** Report that the destination and the guard
could not be resolved from their owner, and stop. Inventing a destination is the one failure the
contract's own resolution section exists to prevent: a plausible guess reports success while the
consumer never scans that path.
```

Per-site slot values:

| File | `<NOUN>` | `<SLOT>` |
|---|---|---|
| `plugins/ai-slop/skills/audit/context/persist-findings.md` | `findings` | `an ai-slop run` |
| `plugins/claude-config/skills/audit-instructions/context/persist-findings.md` | `findings` | ``an `audit-instructions` run`` |
| `plugins/docs-hygiene/skills/audit-noise/context/persist-findings.md` | `findings` | ``an `audit-noise` run`` |
| `plugins/mutation-testing/skills/audit/context/persist-findings.md` | `survivors` | `a mutation run` |

Changes this makes, per file:

- `ai-slop`: `this plugin's` becomes `this skill's`; refusal tail takes the merged stronger form.
- `claude-config`: refusal tail takes the merged stronger form. Title unchanged.
- `docs-hygiene`: refusal tail takes the merged stronger form. Title unchanged.
- `mutation-testing`: the em dash after `contract` becomes `:`; `this plugin's` becomes
  `this skill's`; `— this plugin's read` becomes `: this skill's read`. Its existing line 3
  (`The mechanics of \`--persist-findings\` (SKILL.md "Phase 6 — Persist (opt-in)").`) is a genuine
  per-file pointer and stays, moved below the canonical preamble.

### Second edit: the script-ownership sentence

Align the shared portion in the two files that carry it. Replace
`plugins/ai-slop/skills/audit/context/persist-findings.md:29-37` and
`plugins/docs-hygiene/skills/audit-noise/context/persist-findings.md:55-60` so both read, after
their own per-file lead-in sentence:

```text
The script owns the mechanical half: cell assembly and escaping, tier lookup (a mirror of the
crosswalk, where the crosswalk row is authoritative), rank ordering, the non-overwrite suffix, and
the `## Surfaces` counts.
```

`audit-noise` prepends `the fence recomputation, ` to that list, which is its real extra item.
`ai-slop` keeps its lead-in sentence about repo-scale row counts. Note the em dash inside the
parenthetical is replaced by `where`, per house style.

## ROI

MEDIUM. Four files, small edits, and it removes two em dashes from instruction surfaces plus a
scope claim (`this plugin's`) that two of the four files are not entitled to make.

## Cross-lane observations

- Both em-dash instances noted here are also L5/L6 findings. Flagging so the reconciliation does
  not apply the fix twice.
- No encapsulation violation. Every citation in this cluster targets a published convention URL.
