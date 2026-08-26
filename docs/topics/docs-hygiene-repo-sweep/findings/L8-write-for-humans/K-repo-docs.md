# K-repo-docs

Lane `L8-write-for-humans`, wave 1, read-only. Audience slice: all 89 rows in this group are
`HUMAN`. Composition: 17 ADRs, 29 convention docs, 8 specs, 5 upstream ledgers, 17 `docs/` root
files, and the rest under `docs/native-surfaces/`.

This is the largest group in the lane and the one where the audience classification is most often
wrong. **Two thirds of the group's `L1` volume sits in files this lane recommends reclassifying or
routing elsewhere**, so the actionable set is much smaller than the raw scan suggests.

## Reclassifications first

Before findings, because they change what is in scope.

### K-R1. Nine convention docs are agent-loaded, not human-facing

These nine `docs/conventions/*/README.md` files declare in their own text that they are synced
verbatim into plugin binding copies that an agent loads:

```text
docs/conventions/detector-findings/README.md
docs/conventions/finding-suppression/README.md
docs/conventions/loop-lane/README.md
docs/conventions/plugin-data-report-keying/README.md
docs/conventions/shell-test-helpers/README.md
docs/conventions/standards/README.md
docs/conventions/untrusted-content/README.md
docs/conventions/upstream-drift/README.md
docs/conventions/windows-path-emit/README.md
```

`docs/conventions/standards/README.md:14` states the mechanism, verbatim:

```text
Consuming plugins carry a synced, byte-identical binding copy at
`reference/standards-contract.md`; the `standards-contract` frontmatter key above names the
contract version a copy or a consumer index conforms to.
```

Their primary reader is an agent loading the binding copy. **Reclassify to `AGENT`, routing to
`L7-write-for-agents`.** Two consequences the orchestrator must weigh:

1. Byte-identical sync means an edit to the owner doc without a matching edit to every binding copy
   breaks a CI drift check. Any wave 3 edit to these nine must go through the sync script, not
   through a direct file edit. `scripts/check-cross-plugin-source-drift.sh` is the relevant gate.
2. The nine carry 25 of this group's 225 `L1` hits. Those move to `L7` with the files.

The other 20 convention docs make no sync claim and stay `HUMAN`.

### K-R2. Two generated files are out of scope

```text
docs/CATALOG.md
docs/SKILL-CHEAT-SHEET.md
```

Both carry an explicit generation marker. `docs/CATALOG.md:3`, verbatim:

```text
The generated per-category plugin catalog: the block between the markers below is generated from the
plugin manifests and kept in sync by CI — never hand-edit it
```

`docs/SKILL-CHEAT-SHEET.md:3` says the same for `scripts/generate-cheatsheet.mjs` and SKILL.md
frontmatter.

The resolved guide's legitimate-hit class 3 rules on this: fix the generator or its source, never
the output. **`docs/CATALOG.md` alone holds 21 of this group's 225 `L1` hits, and every one of them
is a plugin manifest `description` string**, which lives in `plugins/*/.claude-plugin/plugin.json`.
That is not markdown and is not in this sweep's corpus at all.

Recorded as a routing finding: if the orchestrator wants those 21 sentences fixed, the edit is to
the manifests, and it is outside the sweep's declared scope. The hand-written preamble above each
generation marker stays in scope and is clean.

### K-R3. Five upstream ledgers are drift-tracking records

```text
docs/upstream/aihero-course.md
docs/upstream/aihero-shipping-course.md
docs/upstream/cursor-pstack.md
docs/upstream/mattpocock-skills.md
docs/upstream/mattpocock-skills-v12-map.md
```

These are recheck ledgers under the `upstream-drift` convention: what was taken from an upstream
source, what was rejected, when it was last checked, and what triggers the next check. Their rows
are dated records, not prose a reader consumes for understanding.

They carry 43 of this group's 225 `L1` hits, nearly all inside table cells summarising an upstream
document.

**This lane does not recommend reclassifying them out of `HUMAN`** (a person does read them when
deciding whether to re-audit), but it files no conformance findings against their table rows. A
ledger row is a record of what a source said, and rewriting it for readability changes the record.
Same principle as the CHANGELOG class judgment in `README.md`.

## Findings

After the three reclassifications, the actionable set for this group is small.

| # | Path | Predicate | Severity |
|---|---|---|---|
| K1 | `docs/MIGRATION-PLAYBOOK.md:1728` | `Am3` | S3 |
| K2 | `docs/conventions/standards/README.md:80` | `Am3` | S3 |
| K3 | `docs/upstream/mattpocock-skills.md:14` | `Am2` | S3 |
| K4 | `docs/PLUGIN-PHILOSOPHY.md` | `M1` | S2 |

### K1

`docs/MIGRATION-PLAYBOOK.md:1728`, verbatim:

```text
agents do **not** hold — a distinct human-only GitHub account and/or a signing key kept off the agent
runners, with branch protection requiring that identity's review on `docs/conventions/**`.
```

Predicate `Am3`. `and/or` is the case Global English names explicitly, and here it matters: the
sentence is about what makes cryptographic separation real, so whether both are required or either
suffices is the substance.

Replacement:

```text
agents do **not** hold: a distinct human-only GitHub account, a signing key kept off the agent
runners, or both, with branch protection requiring that identity's review on `docs/conventions/**`.
```

**This resolves an ambiguity rather than preserving one**, so wave 3 must confirm the intended
reading before applying. If the author meant "both are required", the replacement is wrong and the
right text is `a distinct human-only GitHub account and a signing key`. Per the resolved guide's
negative-parallelism rule, keep the original and raise it with the author if the surrounding
context does not settle it.

### K2

`docs/conventions/standards/README.md:80`, a table cell. Verbatim:

```text
| Applies when | free-form context clues | File globs and/or task keywords; the model matches task context against them |
```

Predicate `Am3`, same shape, lower stakes because the cell is descriptive.

Replacement for the cell:

```text
| Applies when | free-form context clues | File globs, task keywords, or both. The model matches task context against them |
```

### K3

`docs/upstream/mattpocock-skills.md:14`, verbatim:

```text
**Recheck trigger:** a mattpocock/skills release whose changeset names any skill in the
attribution table below — re-audit the affected row(s). Release notes name skills explicitly
```

Predicate `Am2`: `row(s)` in prose. This is the only prose instance of the shape in the whole human
slice; the other eight are table column headers, which are labels rather than sentences and are not
findings.

Replacement:

```text
**Recheck trigger:** a mattpocock/skills release whose changeset names any skill in the
attribution table below. Re-audit every affected row. Release notes name skills explicitly
```

The em dash also goes, but that is `ai-slop:audit`'s call and `docs/**` is outside the em-dash
rule's declared scope. The replacement above happens to remove it; wave 3 may keep the dash and
apply only the `row(s)` fix if it prefers to stay inside this lane's remit.

### K4. `docs/PLUGIN-PHILOSOPHY.md` is four documents

1096 lines, 15 top-level sections. Predicate `M1`. The document's own lead states its mode:

```text
This is the durable design policy for plugins in this marketplace.
```

Policy is **reference**: facts, rules, and limits for lookup. Most of the document holds that. Three
kinds of content in it do not:

- **Argument.** Sections that reason toward a rule rather than stating it. That is explanation, and
  it is the mode the skill says permits a view. It is good writing in the wrong container.
- **Procedure.** Prescriptive sequences a reader follows. That is how-to, and the document itself
  points at `MIGRATION-PLAYBOOK.md` as the place procedures live.
- **Measured findings.** Numbers with dates and conditions attached.

**No edit is proposed.** Splitting a 1096-line policy document is a structural decision that belongs
to `L2-progressive-disclosure`, which owns splits and is the lane whose findings wave 3 applies
second. This is filed so `L2` has the mode reasoning available when it decides where the split lines
go: the seams are between the three modes above, not at arbitrary length.

24 of this group's `L1` hits are in this file. Most are inside its argument sections, where the
resolved guide's register gate protects the author's voice, so they should be judged after the split
rather than before it.

### The doctrine conflict `L4-encapsulation` raised

`L4-encapsulation` reports that `docs/PLUGIN-PHILOSOPHY.md:337-342` prescribes a pattern that
contradicts the public-surface contract. This lane read those lines. Verbatim:

```text
Apply the same anchoring rule to bundled assets: one skill citing another skill's supporting file
writes the full `${CLAUDE_PLUGIN_ROOT}/skills/<other-skill>/<path>` form, optionally paired with a
relative markdown link target for browsing on GitHub
```

**This lane takes no position on which doctrine is right.** It is an encapsulation question, not a
prose question, and `L4` owns it. Recorded here only to confirm that the passage is in this lane's
group and that no `L8` finding touches those lines, so the two lanes will not collide in wave 3.

## Document mode

The group's document genres and their modes:

| Genre | Files | Mode | Verdict |
|---|---|---|---|
| ADR (`docs/adr/*`) | 17 | Explanation | Correct. The Status / Date / Context / Decision / Consequences shape is a settled genre and it maps cleanly onto explanation, which is the one mode that permits a view. No findings |
| Convention owner doc | 29 | Reference | Correct. Each states a contract and describes its shape |
| Spec / measurement record | 8 | Explanation with a reference core | Correct. `docs/specs/d1-model-already-knows-measurement.md` is the model: verdict first, then method, then the numbers |
| Upstream ledger | 5 | Reference | Correct, and treated as a record per K-R3 |
| `docs/` root | 17 | Mixed | One finding, K4. The rest hold one mode |

Two root files were checked closely and cleared:

- `docs/GLOSSARY.md` is pure reference and describes without instructing, including the entry at
  line 88 that declines to define a term:

  ```text
  | sycophancy | nothing — a generic LLM-behavior term with no distinct project meaning. Free-prose use is unaffected; it is simply not project vocabulary |
  ```

  Declining to define is still describing. Correct. The `simply` in that row is the "merely" sense,
  not a procedure, so predicate `A2` does not reach it.
- `docs/specs/d1-model-already-knows-measurement.md` leads with `## Verdict` before `## Method`,
  which is the address layer's "put the common case first" applied to a research record. It is the
  best-structured document in the group.

## Predicates with no findings in this group

`M2`, `M3`, `A1`, `A2`, `Am1`, `Am4`, `N1`, `C1`.

On `Am1`: zero broken parentheticals in 89 files, against eighteen in 71 plugin READMEs. See
`standard-resolution.md` for why the two populations differ.

On `A1` and `A2`: the mechanical proxies fired 34 and 21 times respectively in this group and
adjudicated to zero. Every `should be <verb>ed` hit is a constraint statement in reference register;
every `simply` hit is the "merely" sense in explanation prose.

## Cross-lane observations

- **`ai-slop:audit`**: 130 of this group's 133 non-CHANGELOG files carry em dashes, `docs/MIGRATION-PLAYBOOK.md`
  alone carrying 353. Note for the orchestrator before anyone treats that as a backlog:
  `.claude/rules/vendor-docs-are-not-style.md` scopes the em-dash prohibition to `SKILL.md`, plugin
  READMEs, `AGENTS.md`, `CLAUDE.md`, and `.claude/rules/**`. `docs/**` is outside that list, so
  these are in policy. `ai-slop:audit` owns whether that scope should widen.
- **`source-control`**: nothing in this group.
