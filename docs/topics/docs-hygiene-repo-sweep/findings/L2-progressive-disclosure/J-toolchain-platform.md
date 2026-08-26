# L2 progressive disclosure: `J-toolchain-platform`

137 files, 31 `T2`. Plugins: `actionlint`, `bash-format`, `biome-format`, `computer-use`,
`desktop-notification`, `eol-normalizer`, `go-format`, `instruction-placement`, `kindle-dedrm`,
`machine-health`, `mcp-tools`, `playwright`, `plugin-quality`, `powershell-format`, `ruff-format`,
`skill-quality`, `toolchain`, `wizard`.

Totals: T1=1, T2=2, T3=1.

## Split lane

### `oversize` + `tier-mismatch`: `plugins/plugin-quality/skills/audit/SKILL.md` (Tier 2)

499 lines, **5,579 words**, 6 `references/` spokes. At the 500-line ceiling and 49% over the
recommended body size. The largest `T2` body in this group by both measures.

`plugins/plugin-quality/skills/audit/SKILL.md:120`:

> `## Evidence packet (one per resolved target, created in step 1, survives compaction)`

The packet block spans **lines 120 to 298, 179 lines, 36% of the file**, in three parts:

| Section | Lines | Span |
|---|---|---|
| `## Evidence packet (one per resolved target, ...)` | 120 to 220 | 101 |
| `### Report-file write guardrail (packet filenames)` | 221 to 253 | 33 |
| `### Packet files are write-once evidence (sibling hooks rewrite them in place)` | 254 to 298 | 45 |

All three are specification, not workflow: a directory layout, a filename constraint with its
`PostToolUse` rationale, and a write-once discipline with hook mechanics and upstream doc
citations. The workflow that uses them is `## Workflow` at line 299, which is where the run
actually starts. This is `tier-mismatch` as the rubric defines it, reference detail inline in a
hub, and the file already carries the right destination convention.

**Split spec.**

New spoke: `plugins/plugin-quality/skills/audit/references/evidence-packet.md`

Moves: lines 121 to 298 verbatim, promoted to H1 `# The evidence packet`, with the two H3s raised
to H2 and a `## Contents` list on top. Naming matches the plugin's existing `references/`
directory (note the plural, which this skill uses).

Replaces lines 120 to 298 with:

```markdown
## Evidence packet (one per resolved target, created in step 1, survives compaction)

Every resolved target gets one packet under
`${CLAUDE_PLUGIN_DATA}/evidence/<session_id>/<target-slug>/<run-nonce>/`, written in step 1 and
read by every later step. Read
[`references/evidence-packet.md`](references/evidence-packet.md) before step 1 writes anything:
it owns the directory layout, the `audit-notes.md` filename constraint and why `findings.md` is
forbidden, and the write-once discipline that keeps a sibling `PostToolUse` hook from rewriting
evidence underneath the run. Getting any of the three wrong silently corrupts the audit rather
than failing it.
```

Resulting `SKILL.md`: 499 - 178 + 11 = **332 lines**, and the remaining body is routing, the
context gate, the six workflow steps, and the reference index.

Add the new spoke to the existing index at line 485 (`## Reference index. Load on demand`), which
already carries a `Load when` column:

```markdown
| `references/evidence-packet.md` | Before step 1 writes the packet, and before any step reads it. |
```

### Not findings

`plugins/toolchain/skills/check/SKILL.md` is 185 lines / 3,494 words, inside both ceilings but
dense (18.9 words per line) and carrying 6 `context/` ecosystem spokes. It fires on neither
trigger; recorded because one more ecosystem crosses the recommended body size without moving the
line count much.

`plugins/skill-quality/skills/check/SKILL.md` (263 / 2,670), `plugins/toolchain/skills/lint/SKILL.md`
(219 / 2,679), and `plugins/plugin-quality/agents/auditor.md` (180 / 2,270) are all inside both
ceilings.

## Structure lane

### `missing-toc` (Tier 1)

| Path | Lines |
|---|---|
| `plugins/machine-health/skills/audit/references/windows/check-catalog.md` | 352 |

The lowest `missing-toc` count of any group. The file is a per-check catalog, so a reader arrives
looking for one check.

Remediation: insert a `## Contents` anchor list under the H1 enumerating the checks by name,
matching `plugins/docs-hygiene/skills/audit-progressive-disclosure/context/tier-model.md:3-9`.

### `blind-pointer` (Tier 2)

**`plugins/kindle-dedrm/skills/manage/SKILL.md:154`**

```text
## Cross-references

- `references/workflow.md`: procedural detail (the long-form version of `setup`)
- `references/sources.md`: URL inventory + drift baselines + page hashes
- `references/versions.md`: version pins, SHA256 baselines, supported Kindle/tool matrix
- `references/troubleshooting.md`: common errors and recovery paths
```

Five rows naming what each target holds, none naming when to open it. The repo's own best version
of this section is two plugins away in the same group, at
`plugins/plugin-quality/skills/audit/SKILL.md:485`, which uses a two-column table with a literal
`Load when` header.

Remediation: replace lines 154 to 160 with that shape:

```markdown
## Reference index. Load on demand

| File | Load when |
|------|-----------|
| `references/workflow.md` | Running `setup` end to end, or recovering a partially completed setup. |
| `references/sources.md` | A download URL fails, or a drift baseline needs re-checking against a page hash. |
| `references/versions.md` | Pinning or bumping a tool version, or checking whether a Kindle build is supported. |
| `references/troubleshooting.md` | Any command in this skill errors and the error is not one the step names. |
| `scripts/` | Executable helpers cited above; run, do not read. |
```

The last row also fixes an unmarked execute-versus-read intent: the current row lists `scripts/`
alongside four files that are read.

### Not a finding

`plugins/playwright/skills/playwright/SKILL.md:48` (`## Progressive disclosure map`) pairs each
target with the situation that calls for it, for example line 54:

> `| Command reference, raw output, element targeting | [reference/commands.md](reference/commands.md) |`

That is a load condition in table form. No treatment.

`plugins/machine-health/skills/audit/SKILL.md:50` routes the OS reference tree with a glob inside
its detection fence:

> `Read references/<os>/*.md`

The depth-2 through depth-4 readings my reachability pass produced for
`references/windows/elevation-matrix.md`, `references/shared/correlation-rules.md`,
`references/shared/testing.md`, and `references/windows/remediation-policy.md` are artifacts of
the `<os>` placeholder and the fenced glob, not real chains. Every one of those files is one level
from the hub. No treatment.

### `missing-toc`, 100 to 300 lines (Tier 3, awareness only)

29 files. No treatment.

## Cross-lane observations

- The seven single-purpose formatter plugins (`bash-format`, `biome-format`, `eol-normalizer`,
  `go-format`, `powershell-format`, `ruff-format`, and `actionlint`) each ship a `setup` skill
  under 130 lines with a near-identical shape. Disclosure has nothing to say about that; the
  duplication is L3's.
- `plugins/machine-health/skills/audit/references/linux/NOT_IMPLEMENTED.md` and
  `references/macos/NOT_IMPLEMENTED.md` are placeholder stubs. Whether a stub file earns its
  existence over a line in the routing table is L1.
