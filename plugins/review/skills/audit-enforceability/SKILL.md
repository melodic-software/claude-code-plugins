---
description: "Audit which review findings a deterministic check could catch instead of a model re-deriving them every run: read ONE operator-named findings file, derive a finding class per row, map it through the crosswalk to the cheapest enforcement rung (editorconfig severity, analyzer-pack rule, custom analyzer, Semgrep rule, architecture test, hook, or llm-only), and write one proposal stub per finding naming that rung and its owner. Use when: 'which of these findings could a linter or analyzer catch', 'audit enforceability', 'promote findings to a deterministic check', 'what rung catches this', 'can we stop re-finding this'. 'Enforceability' here means whether ONE finding can be caught deterministically; it is not the question of whether a convention is machine-checkable, and not the C1-C5 promotion the autonomy work classes use. Read-only on the reviewed code and on the findings file it reads; the memory-tier stubs it writes are its report. It proposes a rung and never implements one."
argument-hint: "<findings-file>"
user-invocable: true
disable-model-invocation: false
allowed-tools: ["Bash(${CLAUDE_SKILL_DIR}/scripts/emit-stubs.sh:*)", "Bash(\"${CLAUDE_SKILL_DIR}/scripts/emit-stubs.sh\":*)", "Bash(git:*)", "Bash(grep:*)", "Bash(head:*)"]
shell: bash
metadata:
  workflow-stage: review
  summary: Propose the cheapest deterministic rung for each review finding
---

## Repository context. Gather first

Collect these with **individual** Bash calls, one command per call, never combined into a single
invocation:

- Current branch, `git branch --show-current`

Treat a failure (not a repository, git unavailable) as an unknown value and carry on. A
worktree-isolated session refuses a compound command that contains git, which is why these stay
separate calls rather than one pre-compute line.

## Purpose

A recurring review finding is re-derived by a model on every run. This skill asks, per finding,
whether a cheaper deterministic check could have caught it, and routes the answer to whoever owns
that check. It reads one findings file, classifies each row, applies
[`context/crosswalk.md`](context/crosswalk.md), and writes one proposal stub per row.

**It writes on bare invocation.** The stubs are the report: memory-tier, self-ignoring, and
consumed by nothing. Two obligations come with that, both taken from the read-only audit posture
this copies: announce the resolved stub path in the report, and when no branch identity resolves,
write nothing and say so.

## 1. Input gate

`$ARGUMENTS` names **exactly one file**. Never glob a findings directory and never pick "the
newest": the operator chose this file, and a second file is a second invocation.

- Empty or missing path, or a path that does not exist: print
  `usage: /review:audit-enforceability <findings-file>` and STOP.
- The file's frontmatter must declare `type: review-findings` and its `## Findings` table must
  parse. Otherwise STOP with a one-line diagnostic naming which half failed. The shape is owned by
  [`${CLAUDE_PLUGIN_ROOT}/reference/findings-file-shape.md`](../../reference/findings-file-shape.md).
- A `branch:` that differs from the current branch is **not** a refusal. The operator named the
  file, and a stub is a proposal, not an applied change. Record that `branch:` value in every stub
  and use it for the branch slug.
- No `branch:` in the file **and** no resolvable current branch: write nothing. Report the
  classification table only, and say that no branch identity resolved.

## 2. Class derivation ladder

Per row, first hit wins. **Never drop a row**: the last step always produces a class.

1. The exact qualified rule id (`<plugin>/<skill>/rule-<slug>`) leading the `Finding` cell matches
   a rule-id row in the crosswalk. Class from that row, `class-basis: rule-id`.
2. The id's `<plugin>/<skill>/` prefix matches a rule-family row. Class from that row,
   `class-basis: rule-family`.
3. The row's `## By dimension` heading, in a file that has that section, matches a dimension row.
   Class from that row, `class-basis: dimension`. An unlisted dimension falls through.
4. Your own judgment over the `Finding` and `Action` text, into the crosswalk's class vocabulary.
   `class-basis: judgment`.
5. Nothing resolved: class `unclassified`, rung `llm-only`, `class-basis: unresolved`.

This step is done when every rank in the table carries exactly one class and one basis, and the
count of classified rows equals the count of rows the table carried.

## 3. Crosswalk lookup

Class to rung to owner or pointer, from [`context/crosswalk.md`](context/crosswalk.md). The rungs
sit in a fixed cheapest-first order; take the cheapest rung whose check can actually assert the
finding, not the cheapest rung imaginable.

## 4. Resolve two homes

Both through [`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](../../reference/topic-docs.md),
which owns the ladder, the rung semantics, and the non-interactive collapse:

- **The stub home**: the `enforceability/<branch-slug>/` ladder.

  `<branch-slug>` comes from the findings file's own `branch:` value, which the operator chose
  and which nothing authenticates. **The raw value is never a path segment.** Apply the binding's
  branch-slug rule first: lowercase it, then replace `/` and every other character outside
  `[a-z0-9._-]` with `-`. That is what turns a value like `../../etc` into `..-..-etc`, one inert
  segment. A slug that is empty after that rule is not a home; report the classification table and
  write nothing. When you composed the home this way (the ladder's rungs 1 and 5), pass the root
  you composed it from as `--memory-root`, so the writer refuses a home that escaped it. When the
  consumer handed the home over whole (rungs 2 to 4), no segment of it came from the input file
  and no anchor applies.
- **The fix action's reviews location** for that same branch: the `reviews/<branch-slug>/` ladder.
  This is what the writer is fenced against; it is resolved, never assumed, because the binding's
  middle rungs do not compose a `reviews/<branch-slug>` segment at all.

**Announce the resolved stub path** before writing anything:
*"Read-only pass; the only files written are the proposal stubs at `<resolved path>`."* With no
branch identity: *"Read-only pass; no branch identity resolved, so no stub is written."*

Follow the binding's Runtime guards: the self-ignore guard on the session's first memory-tier
write, and the invalid-root cases in which the write itself is refused (a root-equivalent memory
root; a resolved root no checkout is detected as governing, except the plugin-data fallback). A
non-interactive or dispatched context takes the binding's cited non-interactive collapse and says
so, rather than silently taking the default.

## 5. Write the stubs

Compose the classification TSV and pass it on stdin inside the same granted command, one line per
rank, five fields separated by ONE literal tab each: `rank`, `class`, `basis`, `rung`, `owner`.
Each `<TAB>` below is a single tab character, not that text:

```bash
"${CLAUDE_SKILL_DIR}/scripts/emit-stubs.sh" \
  --findings <findings-file> \
  --classes - \
  --out <resolved-stub-home> \
  --scan-dir <resolved-reviews-home> \
  --memory-root <the root the home was composed from, at rungs 1 and 5 only> <<'TSV'
1<TAB>style<TAB>judgment<TAB>editorconfig-severity<TAB>in-repo .editorconfig
2<TAB>defined-diagnostic<TAB>rule-id<TAB>analyzer-pack-rule<TAB>keep the detector
TSV
```

The heredoc rides inside the one granted command, so no separate file-write grant is needed and no
temporary file is left behind. This step is done when the writer has exited 0 and printed its
`N findings → N stubs` line with N equal to the number of rows the table carried.

The writer is deterministic and owns the shape ([`context/stub-shape.md`](context/stub-shape.md)):
it anchors on `## Findings`, unescapes `\|`, never overwrites, refuses a stub home inside either
fenced directory, refuses a home carrying a `..` segment or one that escapes `--memory-root`, and
re-reads every stub it wrote, removing all of them if any carries a findings-file marker. Its exit codes are `2` usage or a non-conforming input, `3` a refused home,
`4` a forbidden marker. Surface a non-zero exit verbatim; never retry it into a different
directory.

## 6. Report

A table with one row per finding: rank, class, class basis, rung, owner, stub path. Then the
writer's own line, `N findings → N stubs in <home>`. Then, grouped per rung, the next step, each
with its gate and its fallback:

- **`editorconfig-severity`**: name the setting and the file; no plugin is involved.
- **`analyzer-pack-rule`**: name the diagnostic id and the config file that raises its severity.
  Where the producing detector already is the deterministic check, the next step is to keep it.
- **`custom-analyzer`**: point at Microsoft Learn, "Tutorial: Write your first analyzer and code
  fix" (<https://learn.microsoft.com/en-us/dotnet/csharp/roslyn-sdk/tutorials/how-to-write-csharp-analyzer-code-fix>).
  No installable upstream skill owns this rung, so the pointer is the whole of it. This rung is
  .NET-only; the same invariant elsewhere belongs on the Semgrep rung.
- **`semgrep-rule`**: invoke `/semgrep-rule-creator:semgrep-rule-creator` (if the
  `semgrep-rule-creator` plugin is installed); otherwise the stub points at Semgrep's rule-writing
  documentation (<https://docs.semgrep.dev/writing-rules/overview>) and stops. Print the install
  recipe in the report only: `/plugin marketplace add trailofbits/skills` then
  `/plugin install semgrep-rule-creator@trailofbits`.
- **`architecture-test`**: point at ArchUnitNET (<https://archunitnet.readthedocs.io/>) for .NET
  and the dependency-cruiser repository docs (<https://github.com/sverweij/dependency-cruiser>)
  for JS/TS.
- **`hook`**: run `/claude-config:audit-automation-gaps hooks` (if the `claude-config` plugin is
  installed) and present the stub as a candidate in its candidate-list step, which is
  self-generated and takes no findings input; otherwise the stub records the candidate with the
  evidence that skill's gates ask for (frequency, incident history, the enforcement level already
  covering it) and stops.
- **`llm-only`**: say plainly that no check catches this one and it stays a review-time judgment.

## 7. Boundary

- **Not the detector-findings or autonomy sense of "promotion".** There, promotion moves a
  candidate detector's guardrail class, or flips a matrix cell's human-ratified knob across the
  C1 to C5 work classes. Enforcement promotion here moves a finding class to a cheaper
  deterministic rung. Same word, different meaning, and neither implies the other.
- **Not the enforceability of a convention.** Whether a convention is machine-checkable, and at
  which tier, is a question about a rule. This skill asks whether ONE finding could have been
  caught deterministically.
- **Not the automation-landscape audit.** `audit-automation-gaps` in the `claude-config` plugin
  walks a repository and self-generates its own candidates. This skill reads one findings file and
  walks nothing.
- **Not the fix action.** `/review:fanout fix` applies findings to the working tree. This skill
  mutates no reviewed file, and its stubs are fenced out of the directory that action scans.
- **It never implements a rung.** No analyzer, rule, architecture test, or hook is written here.
  Asked to "just write the analyzer", decline and hand over the rung's pointer.

## Gotchas

- **`## By dimension` repeats every row.** The section re-renders the same findings under
  per-dimension headings with rank numbers unchanged, so reading every table row in the file
  counts each finding twice. The table under `## Findings` is the only source of rows. The writer
  enforces this; do not re-count rows yourself from the whole file.
- **Unescape `\|` before classifying.** Cells escape a literal pipe, and reviewer text carries
  pipes routinely (type unions, shell pipelines). A cell read without unescaping splits into
  phantom columns.
- **An omitted `Confidence` is not low confidence.** A minimally conforming producer may leave
  cells thin. Absent is absent; never read it as a value.
- **A missing `## By dimension` section is normal.** Only files the fan-out review wrote carry it.
  An adopter-produced file has none, which simply means the ladder's dimension step never fires.
- **The dimension enum is open.** New categories appear without notice, so an unlisted heading
  falls through to judgment instead of being forced onto a rung.
- **A `> DEGRADED:` blockquote above `## Findings` is a coverage notice, not a row.** Carry its
  first line into the report so the coverage gap stays visible.
