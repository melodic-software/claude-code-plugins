# L2 progressive disclosure: `B-cc-config-ops`

130 files, 29 `T2`. Plugins: `claude-config`, `claude-memory`, `claude-ops`, `context-guard`,
`context-budget`, `guardrails`, `rate-limit-guard`.

Totals: T1=9, T2=9, T3=2.

## Split lane

### `oversize` + `tier-mismatch`: `plugins/context-guard/skills/setup/SKILL.md` (Tier 2)

462 lines, 4,715 words, **zero spokes**. Highest-value split in this group: an invocation-loaded
body at 92% of the 500-line ceiling with no hierarchy layer at all.

`##`check`(read-only)` spans **lines 37 to 371, 335 lines, 72% of the file**. Within it, numbered
step 7 alone spans **lines 186 to 365, 180 lines**.

`plugins/context-guard/skills/setup/SKILL.md:186`:

> `7. **Print the operator edit**. Print the applicable statusline edit for the settings file`

Step 7 is an unwrap-then-compose algorithm: peel rules 1 and 2 with sub-branches A/B/C, the
`sh -c` ambiguity carve-out, the shell-syntax guard, the layer-count invariant, the JSON edit
blocks, and the Windows/Git Bash note. None of it is read unless the run reaches the point of
printing an edit, and none of it co-executes with steps 1 to 6.

**Split spec.**

New spoke: `plugins/context-guard/skills/setup/reference/statusline-edit.md`

Moves: lines 186 to 365 verbatim, dedented one list level, retitled. Section order inside the new
file: `# Composing the statusline edit` / `## Unwrap before you compose` (peel rules 1 and 2, the
A/B/C branches, the ambiguity carve-out) / `## The shell-syntax guard` / `## The edit blocks`
(both JSON forms) / `## Windows note`. Open the file with a `## Contents` anchor list.

Replaces lines 186 to 365 in `SKILL.md` with:

```markdown
7. **Print the operator edit**, except when step 3 took the terminal-less exception, found the
   status line disabled by policy or trust, or found the effective command owned by managed
   settings. Those branches already forbade printing wiring the operator cannot make run. When
   this step does print, the wiring target is the SHIM's fixed path, never
   `${CLAUDE_PLUGIN_ROOT}`. Read
   [`reference/statusline-edit.md`](reference/statusline-edit.md) now, before composing: it owns
   the peel rules, the shell-syntax guard, both JSON edit blocks, and the Windows note, and
   composing without it is what produced `context -> rate -> rate -> renderer` and the
   compounding `sh -c` wrap.
```

Resulting `SKILL.md`: 462 - 180 + 10 = **292 lines**.

### `oversize`: `plugins/claude-config/skills/audit-pass/SKILL.md` (Tier 2)

495 lines, 5,476 words, 9 existing `reference/` spokes. At 99% of the line ceiling and above the
recommended 5k-token body size.

Densest inline sections: `## Phase 0  Resolve, key, lock` (lines 130 to 192, 63 lines),
`## Phase 1  Three-scope inventory, before any check` (193 to 247, 55 lines), `## Arguments`
(52 to 129, 78 lines).

`plugins/claude-config/skills/audit-pass/SKILL.md:52`:

> `## Arguments`

**Split spec.** New spoke: `plugins/claude-config/skills/audit-pass/reference/arguments.md`
holding lines 53 to 129 (every flag's semantics, precedence, and the `--fix`/`--resume`
interaction). Leave in the hub a table of flag names and one-line meanings only.

Replacement pointer at line 52, after the trimmed table:

```markdown
Flag semantics, precedence between them, and what `--fix` and `--resume` change about the phases
below are in [reference/arguments.md](reference/arguments.md). Read it when a run is invoked with
more than one flag, or with any flag whose effect on a later phase you are about to assume.
```

### `oversize`: `plugins/claude-config/skills/audit-instructions/SKILL.md` (Tier 2)

487 lines, 5,154 words. `## Phase A  Inventory` spans **lines 150 to 307, 158 lines, 32% of the
file**, and is the largest single block.

`plugins/claude-config/skills/audit-instructions/SKILL.md:150`:

> `## Phase A: Inventory`

**Split spec.** New spoke: `plugins/claude-config/skills/audit-instructions/context/phase-a-inventory.md`
holding lines 151 to 307. The skill already uses `context/` for procedure detail
(`context/persist-findings.md`, `context/report-keying.md`), so the destination matches the
existing convention.

Replaces lines 150 to 307 with:

```markdown
## Phase A: Inventory

Enumerate every locally-owned instruction surface, then hand the per-surface list to Phase B.
Read [context/phase-a-inventory.md](context/phase-a-inventory.md) before starting Phase A: it
owns the surface discovery order, the per-surface record fields Phase B and Phase B2 both key
off, and the exclusions. Phase B cannot run against a record set built any other way.
```

Resulting `SKILL.md`: 487 - 158 + 8 = **337 lines**.

### `oversize`: remaining `T2` bodies over the word ceiling (Tier 2)

| Path | Lines | Words | Note |
|---|---|---|---|
| `plugins/claude-ops/skills/lanes/SKILL.md` | 323 | 2,884 | under both ceilings on words; line-count only, no treatment |
| `plugins/claude-config/skills/audit-permission-state/SKILL.md` | 302 | 2,660 | same |

Neither fires. Recorded so the roll-up's counts are reproducible.

## Structure lane

### `missing-toc` (Tier 1)

| Path | Lines |
|---|---|
| `plugins/claude-config/skills/audit-instructions/reference/criteria.md` | 1,742 |
| `plugins/claude-config/skills/audit-instructions/reference/conflict-criteria.md` | 618 |
| `plugins/context-guard/reference/reader-contract.md` | 526 |
| `plugins/claude-ops/skills/plugins/context/sync.md` | 495 |
| `plugins/claude-memory/skills/audit/reference/criteria.md` | 449 |
| `plugins/guardrails/README.md` | 449 |
| `plugins/claude-ops/README.md` | 362 |
| `plugins/claude-config/skills/audit-permission-state/reference/criteria.md` | 332 |
| `plugins/claude-config/skills/audit-pass/reference/run-state-and-resumability.md` | 310 |

Worst case, `plugins/claude-config/skills/audit-instructions/reference/criteria.md:6`:

> `# Instruction-Audit Criteria`

1,742 lines, one row per check, opened by a reader looking for one check. No `## Contents`.

Remediation, all nine: insert a `## Contents` anchor list directly under the H1 (after the
frontmatter where present), matching
`plugins/docs-hygiene/skills/audit-progressive-disclosure/context/tier-model.md:3-9`. For
`criteria.md` and `conflict-criteria.md`, add one line above the list giving the grep recipe for
finding a check by id, since both are consulted per check rather than read.

### `deep-nesting` (Tier 2)

**`plugins/claude-config/skills/audit-pass/reference/run-contract.md:9`**

> `| [terms.md](terms.md) | preamble | The shared vocabulary: run, target, lane, scan set, live surface, live surface set. |`

`SKILL.md:19` points only at `reference/run-contract.md`, which is itself a routing index into
seven leaves. Five of those leaves are also cited directly from `SKILL.md` (lines 348, 406, 419
and others), but **`terms.md` and `finding-identity.md` are reachable only through the index**,
two hops from the hub. Every other leaf opens with `Terms: [terms.md](terms.md).`
(`determinism-tiers.md:6`, `suppression.md:6`, `finding-identity.md:6`,
`run-state-and-resumability.md:6`), so the vocabulary every leaf assumes is the file furthest from
the hub. That is the documented partial-read failure: an agent that reads a leaf directly from
`SKILL.md` never sees the index row that would have told it to read `terms.md` first.

Remediation: add both leaves to the hub's own pointer list so they are one level deep, keeping
`run-contract.md` as the section-number map. At `plugins/claude-config/skills/audit-pass/SKILL.md:19`,
after the existing sentence:

```markdown
Read [reference/terms.md](reference/terms.md) first: every other contract file opens by assuming
its vocabulary. [reference/finding-identity.md](reference/finding-identity.md) owns the
`(check, claim, sites)` tuple and the derived `finding_id`; read it before emitting or comparing
any finding. [reference/run-contract.md](reference/run-contract.md) remains the `§1`-`§7` map.
```

### `blind-pointer`: index sections with no load condition (Tier 2)

| Path:line | Verbatim heading |
|---|---|
| `plugins/claude-ops/skills/changelog/SKILL.md:173` | `## Cross-references` |
| `plugins/claude-ops/skills/lanes/SKILL.md:311` | `## Cross-references` |
| `plugins/claude-ops/skills/morning-brief/SKILL.md:70` | `## Cross-references` |
| `plugins/claude-ops/skills/observability/SKILL.md:129` | `## Cross-references` |
| `plugins/claude-ops/skills/plugins/SKILL.md:284` | `## Cross-references` |

Sample rows, `plugins/claude-ops/skills/changelog/SKILL.md:175-176`:

```text
- `context/repo-surfaces.md`. Surface categories to check per changelog item
- `context/classification-rubric.md`. P1/P2/P3 classification criteria
```

Each row states what the spoke holds and not when to open it. The same plugin already carries the
correct shape at `plugins/claude-ops/skills/observability/SKILL.md:36`
(`## Context ladder (read on demand)`), so this is an inconsistency inside one plugin, not a
missing convention.

Remediation, all five: rename the heading to `## Reference index. Load on demand` and append a
when-clause to each row. For the sampled rows:

```markdown
- `context/repo-surfaces.md`. Read before the surface sweep: the surface categories to check per
  changelog item.
- `context/classification-rubric.md`. Read when an item's priority is not obvious from its
  changelog line: the P1/P2/P3 criteria.
```

### `deep-nesting` (Tier 3, awareness only)

`plugins/claude-ops/skills/known-issues/context/issue-templates.md` and
`context/output-templates.md` are reached only from `context/action-create.md:141` and
`context/action-search.md`. Both are explicitly conditional snapshots
(`action-create.md:141`: `Snapshot of template fields and body format (offline reference only —
always fetch live)`), so the chain is an alternate, not a required reading path. No treatment.

### `missing-toc`, 100 to 300 lines (Tier 3, awareness only)

38 files. No treatment; the two official sources disagree at this length.

## Cross-lane observations

- `plugins/claude-ops/skills/audit-performance/SKILL.md`, `audit-install-state`, and
  `audit-native-overlap` each restate the "reports, never mutates" contract in their own words.
  Cross-file duplication is L3.
- `plugins/context-guard/skills/setup/SKILL.md:31-36` says the consumer-facing constants are owned
  by `${CLAUDE_PLUGIN_ROOT}/reference/reader-contract.md`, and step 5 (line 156) reports
  `zones.json` state with the default bands restated inline. L3.
