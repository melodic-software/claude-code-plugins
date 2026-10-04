# Persisting findings: this skill's read of the detector-findings contract

**Read the producer contract before the first write**:
<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/detector-findings/README.md>.
It owns the shape's authority, where the file goes, the producer-computed fields, the coexistence
obligations, the self-ignore guard, and what a minimal producer may omit. This file adds only what
an `audit-instructions` run decides for itself and cites the contract for the rest. Where the two
disagree, the contract wins and this file is the defect.

**If the contract cannot be fetched, do not write.** Report that the destination and the guard
could not be resolved from their owner, and stop. Inventing a destination reports success while
the consumer never scans that path.

## This does not loosen the read-only contract

The skill body's "Read-only contract" still holds: this skill proposes, the human applies. A
findings file is a **proposal artifact**, not an applied edit. It reaches `review:fanout`'s `fix`
action, which is itself human-gated. Persisting is therefore opt-in behind `--persist-findings`;
a bare invocation reports and stops. Never describe the findings file to an
operator as a change that has been made.

## Where the file goes

Resolve per the contract "Where the file goes": the current branch's findings directory in the
memory slice (`<memory_dir>/reviews/<branch-slug>/`, `.work/` unless the project's instructions
declare another root), honor the self-ignore guard, and prove the destination is outside tracked
space before writing (a destination that cannot be proven is reported and not written to).

File name: `${TS}-audit-instructions.md`, `TS="$(date -u +%Y%m%dT%H%M%SZ)"` (colon-free,
Windows-safe). Never overwrite: when the path exists, take `-2`, `-3`, the smallest free integer.
`emit-findings.sh` does this itself.

## The body-scope fence is not optional and not the caller's alone

A `description`, a `when_to_use`, and a quoted `'trigger phrase'` are routing text: dropping one
regresses auto-invocation, and where the `skill-quality` plugin's `check-skill.sh` gate runs, its
trigger-phrase drop check warns on a dropped trigger phrase against the base ref. A remediation that
edits any of them is therefore a regression, not a debatable suggestion. Two consequences bind every
run:

- Scan with `instruction-scan.sh --body-only` (I28) and `restatement-scan.py` (I29, body-scoped
  by construction). Concatenate both onto the `--from` stream. Lane findings for I30 to I33 go on
  their own `--from-lane` stream, and the same fence binds them.
- Do **not** rely on that alone. `emit-findings.sh` recomputes the fence over its input and
  additionally declines any body row quoting a trigger phrase that appears in the file's own
  `description`. A fence that lives only in the caller is one caller away from being bypassed.

A coercive phrase inside a `description` is a real observation and still belongs in the **human
report**. It is routed there, never to the relay.

## Compose by script, not by hand

Once the destination is resolved and the contract fetch succeeded, run
`${CLAUDE_SKILL_DIR}/scripts/emit-findings.sh --from <scan output file> --from-lane <lane rows file> --out <resolved path>`,
omitting whichever input the run has nothing for. The script owns the mechanical half: the fence
recomputation, cell assembly and escaping, tier lookup (a mirror of the crosswalk, and the
crosswalk row is authoritative), each row's finding identity (through `scripts/finding-ids.sh`,
per [reference/finding-identity.md](../reference/finding-identity.md)), rank ordering, the
non-overwrite suffix, and the `## Surfaces` counts. What stays with the model is everything before
the script (destination resolution, the fetch-and-refuse gate, the self-ignore guard) and everything
after it (reading the written file's head to confirm shape, and severity-vocabulary mapping when
the consuming project defines its own). For that mapping, edit the written file's `Tier` cells per
the contract's consumer-precedence rule.

## Which findings enter the file

**The I28 and I29 families from the scan, and I30 to I33 from the lanes.** `instruction-scan.sh`
marks twelve check families and `restatement-scan.py` marks two more; the other ten scanned
families (I6, I8-a/b/c/f, I10, I23, I25, I27, I38) and every other lane check have no
severity-crosswalk row, and the contract admits no row whose tier cannot be looked up from one.
They stay in the human report and are counted in `## Surfaces` as
`reason=no-severity-crosswalk-row`. They are declined, never silently dropped.

| Family | Intake | Rule id | Tier |
|---|---|---|---|
| `I28-a` | `--from` | `harness-config/audit-instructions/rule-coercive-emphasis` | IMPORTANT |
| `I28-b` | `--from` | `harness-config/audit-instructions/rule-blanket-tool-default` | IMPORTANT |
| `I29-a` | `--from` | `harness-config/audit-instructions/rule-description-restatement` | IMPORTANT |
| `I29-b` | `--from` | `harness-config/audit-instructions/rule-sibling-restatement` | IMPORTANT |
| `I30` | `--from-lane` | `harness-config/audit-instructions/rule-trigger-less-stamp` | IMPORTANT |
| `I31` | `--from-lane` | `harness-config/audit-instructions/rule-migration-relative-phrasing` | IMPORTANT |
| `I32` | `--from-lane` | `harness-config/audit-instructions/rule-route-to-absent-skill` | CRITICAL |
| `I33` | `--from-lane` | `harness-config/audit-instructions/rule-spoke-self-description` | SUGGESTION |

**A lane row is a Phase C-surviving finding, written as `<path>:<line>:<check-id>`** with the line
of the flagged sentence's first physical line (for I33, the opener). A row on the wrong intake is
declined naming the intake it belongs to (`reason=scanner-fed-rule` or `reason=lane-fed-rule`).
I31 and I33 are admitted for any file inside a skill directory (`skills/<name>/`, including
`SKILL.md` for I31 but not for I33) and for any file in a `context/`, `reference/`, or `references/`
directory, where a file a memory surface points at lives; a row elsewhere is declined as
`reason=outside-rule-surfaces`. I32 is `CRITICAL` on a path under `plugins/` (the marketplace arm)
and `IMPORTANT` anywhere else (the user and project arm). **I32 is the one lane rule whose catalog surfaces reach
frontmatter**: a description or `when_to_use` routing clause naming an absent skill is a real
finding, but the relay is body-scoped, so the writer declines the row as `reason=frontmatter` and
counts it, and the human report carries it.

**These rules are selected by judgment, so an unresolved call falls toward emitting.** Each I30 to
I33 exemption in [reference/criteria.md](../reference/criteria.md) is a withholding boundary that
needs its evidence present: a one-line scope note is one line that bounds the subject, a named
owner record is named at the site, a CHANGELOG is a CHANGELOG. A candidate the lane cannot place
inside an exemption on that evidence goes on the `--from-lane` stream.

The model lane's criteria carve-outs still apply **before** persistence: emphasis guarding a
destructive, security, or permission gate, a stated hard precondition, and a document *about* the
pattern are not findings (reference/criteria.md, I28). The scanner over-produces by design; drop
those candidates from the scan output handed to `--from` rather than emitting and retracting.

**Count what you drop.** Removing those rows before the writer sees them would make the exclusion
invisible in `## Surfaces`, which is precisely the silent decline this contract forbids. The
section would report fewer candidates examined than were actually looked at. Pass the number
through: `--declined-carveout <n>`, which records it as its own counted line. Zero dropped → omit
the flag.

A candidate the report holds as `RESIDENCY-UNRESOLVED` proposes no applicable edit, so it is held
out of `--from` the same way and counted through its own flag, `--declined-residency <n>`, never
folded into the carve-out count, whose reason names a different ground. Zero held → omit the flag.

The same rule binds the writer's own intake. A `--from` line that is not a scan row, whether a
well-formed `path:line:I<n>` whose suffix sits outside `[a-c]`, a prose line, or a blank, still
increments `Scan rows read` and is counted as `reason=unparsable-row`. It is never omitted from
both the row count and every decline line. Intake strips a trailing CR before the pattern match
(the same strip `descr()` and `source_line()` already do), so a mixed CRLF file is parsed rather
than silently dropping the CR-terminated rows.

**Surfaces outside the repository never reach the relay.** Phase A inventories user-level surfaces
under `${CLAUDE_CONFIG_DIR:-~/.claude}` as well as repo-owned ones, but `Location` is contractually
repo-relative and the fix action fences each remediation to it. An absolute path would have the
fix pass either edit a file outside the working tree or consume the finding without applying it.
`emit-findings.sh` declines any row whose path is not under the repo root and counts it as
`reason=outside-repo-root`. Those findings still belong in the **human report**; route them there,
and where the surface is upstream-owned, to its owning repository per the skill body's routing
rule.

A row whose path is not absolute is not one of them. `instruction-scan.sh` echoes the path it was
handed, so naming a repo-owned file relatively is the ordinary invocation; such a path is resolved
against the directory the scan is run from, which is the directory the writer reads the file from,
and then meets the same fence. A path holding a `..` segment is refused whatever its form
(`/` or `\`; Git Bash spells a parent with a backslash): the fence test is lexical, so a
traversing path can prefix-match the root while resolving outside it. `Location` is
pipe-escaped the same way Finding and Action are.

## What each cell says

- **`branch:`** is `git branch --show-current` verbatim.
- **`Location`** is `<repo-relative path>:<line>`; never the file alone.
- **`Surface(s)`** is `harness-config:audit-instructions`.
- **`Finding`** leads with the qualified rule id and the fired marker in the run's own values
  (`marker="CRITICAL:"`, `phrase="if in doubt, use"`, `target="/fleet:reachx"`), then
  `finding_id=<16 hex>`, then the excerpt. No rubric reasoning. A row whose identity
  `finding-ids.sh` refuses is declined as `reason=identity-unresolved`, never emitted without one.
- **`Action`** states the **downgrade**: normal conditional phrasing for `rule-coercive-emphasis`,
  the targeted condition for `rule-blanket-tool-default`. **The remediation is never a deletion.**
  A finding that removes the instruction rather than its shouting is wrong, so no `Action` cell
  may instruct removal. The directive survives verbatim and only its volume changes. The single
  legitimate exception is **sentence-initial capitalization forced by dropping a leading wrapper**
  (`…MUST resolve` → `Resolve`), which the official source's own worked example also makes
  (`use` → `Use`). Any other wording change means the remediation overreached.
- **`Action`** for a lane rule keeps the flagged content and changes its framing: I30 adds the
  recheck trigger and keeps the stamp, I31 restates the current rule and names the owning
  `CHANGELOG.md` as the target for any history kept, I32 repoints the route and keeps the routing
  sentence, and I33 deletes the opener and names the hub as the target for a loading condition its
  index row lacks. I31 and I33 are therefore off-site rows in the contract's sense.
- **`Tier`** is LOOKED UP from the rule's crosswalk row, then mapped to the consuming project's
  severity vocabulary when it defines one. **`Confidence`** is `high` on every scanner-fed row: a
  deterministic detector fired. It is omitted on every lane-fed row: a judgment selected it, and
  the contract gives a producer no grade below `high`, so the row ranks as `unscored`.

## Surfaces, and when the file is written at all

`## Surfaces` names `harness-config:audit-instructions` once, states what was scanned, and carries
the declined counts per family and reason. Rows sharing a `finding_id` (identical sentences under
one heading path) are emitted once, and an `Identity collisions: finding_id=<id> count=<n>` line
names each such id. Omit `tier:`, `## By dimension`, and `## Unparsed`.

- Findings to emit → write.
- Files scanned, zero emittable findings → write anyway with the empty `## Findings` header:
  coverage is the payload.
- Nothing scanned (empty target set, everything excluded) → write nothing; say so in the report.

## Re-running

A re-run writes what it currently finds and never replays: never re-emit a previous file, never
copy rows forward. After the relay's `fix` applies a remediation, re-run the scan and emit a fresh
file so no stale findings file survives its own remediation.
