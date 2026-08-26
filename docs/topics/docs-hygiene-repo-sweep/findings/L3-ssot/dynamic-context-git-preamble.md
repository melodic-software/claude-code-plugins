# Cluster: dynamic-context-git-preamble

**Concept.** The `!`-injection preamble a skill puts near the top of its `SKILL.md` to precompute
repository context: current branch, working-tree status, and recent commits.

**Bucket.** N>=3. 44 files carry the branch line; 37 carry a tree-status or recent-commits line.

**Owner.** None. No file in `docs/`, `docs/conventions/`, or `.claude/rules/` states a canonical
form for this preamble.

## Multiplicity evidence (Tier 0)

The branch line is byte-identical across all 44 files:

```text
- Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
```

Files: `plugins/ai-slop/skills/audit`, `plugins/architecture/skills/improve`,
`plugins/bugs/skills/scan`, `plugins/bugs/skills/write`, `plugins/claude-ops/skills/observability`,
`plugins/code-tidying/skills/audit-comment-residue`,
`plugins/code-tidying/skills/batch-simplify`, `plugins/code-tidying/skills/dissolve-comments`,
`plugins/code-tidying/skills/tidy`, `plugins/codebase-health/skills/audit`,
`plugins/coupling/skills/reduce`, `plugins/debugging/skills/debug`,
`plugins/discovery/skills/blindspot`, `plugins/discovery/skills/explore`,
`plugins/discovery/skills/research`, `plugins/discovery/skills/research-deep`,
`plugins/discovery/skills/trace-intent`, `plugins/docs-hygiene/skills/audit-derivability`,
`plugins/docs-hygiene/skills/audit-noise`,
`plugins/docs-hygiene/skills/audit-progressive-disclosure`,
`plugins/docs-hygiene/skills/compress`, `plugins/docs-hygiene/skills/rename-references`,
`plugins/implementation/skills/implement`, `plugins/improvement/skills/find`,
`plugins/mutation-testing/skills/audit`, `plugins/planning/skills/audit-answers`,
`plugins/planning/skills/design`, `plugins/planning/skills/design-handoff`,
`plugins/planning/skills/devils-advocate`, `plugins/planning/skills/interview`,
`plugins/planning/skills/plan`, `plugins/planning/skills/prd`,
`plugins/prototype/skills/explore-directions`, `plugins/prototype/skills/pressure-test`,
`plugins/repo-hygiene/skills/clean`, `plugins/review/skills/fanout`,
`plugins/review/skills/quality-gate`, `plugins/testing/skills/diagnose`,
`plugins/testing/skills/plan`, `plugins/testing/skills/run-e2e`, `plugins/testing/skills/write`,
`plugins/toolchain/skills/check`, `plugins/toolchain/skills/lint`,
`plugins/verification/skills/confirm` (all `SKILL.md`).

## The defect: the companion lines have not stayed identical

`Working tree status`, ten variants across 26 files:

| Variant | Count | Example site |
|---|---|---|
| `git status --porcelain 2>/dev/null \| head -20 \|\| echo "clean"` | 8 | `plugins/testing/skills/write/SKILL.md:15` |
| `git status --porcelain 2>/dev/null \| head -10 \|\| echo "clean"` | 7 | `plugins/planning/skills/plan/SKILL.md:16` |
| `... \| head -20 \|\| echo "unavailable"` | 2 | `plugins/review/skills/fanout/SKILL.md:15` |
| `... \| head -20 \|\| echo "(unavailable)"` | 2 | `plugins/codebase-health/skills/audit/SKILL.md:15` |
| `... \| head -10 \|\| echo "(unavailable)"` | 1 | `plugins/improvement/skills/find/SKILL.md:16` |
| `... \| head -20 \|\| echo "not a git repository"` | 1 | `plugins/toolchain/skills/lint/SKILL.md:14` |
| `... \| head -20 \|\| echo ""` | 1 | `plugins/toolchain/skills/check/SKILL.md:14` |
| `git status --porcelain 2>/dev/null \|\| echo ""` | 1 | `plugins/verification/skills/confirm/SKILL.md:14` |

`Recent commits`, five variants across 13 files:

| Variant | Count | Example site |
|---|---|---|
| `git log --oneline -5 2>/dev/null \|\| echo "no commits"` | 8 | `plugins/planning/skills/plan/SKILL.md:15` |
| `git log --oneline -10 2>/dev/null \|\| echo "no commits"` | 2 | `plugins/coupling/skills/reduce/SKILL.md:15` |
| `git log --oneline -15 2>/dev/null \|\| echo "no commits"` | 1 | `plugins/improvement/skills/find/SKILL.md:15` |
| `git log --oneline -20 2>/dev/null \|\| echo "no commits"` | 1 | `plugins/architecture/skills/improve/SKILL.md:15` |
| `git log --oneline -10 2>/dev/null \|\| echo "no history (shallow or fresh clone)"` | 1 | `plugins/bugs/skills/scan/SKILL.md:16` |

Six further single-instance spellings of the same intent exist outside this family
(`- Branch: !\`git symbolic-ref --quiet --short HEAD ...\`` x3, `- Tree: !\`git status --short\`` and
three more), which is the same drift one step further along.

## Which differences are signal and which are drift

**Signal, keep.** The `head -N` and `log -N` depths. `architecture:improve` documents that its scan
uses recent-commit hot spots and deliberately widened its window to 20 commits
(`docs/upstream/mattpocock-skills.md:33`). Depth is a per-skill choice about how much context the
skill's own method needs.

**Drift, normalize.** The fallback strings. `"clean"`, `"unavailable"`, `"(unavailable)"`,
`"not a git repository"`, and `""` are five different answers to the same question, and two of them
are wrong: `git status --porcelain` failing does not mean the tree is clean, and an empty string
renders as a blank line the model must guess about. `"no commits"` versus
`"no history (shallow or fresh clone)"` is the same problem on the log line.

**Stability test: passes.** Correcting the `"clean"` mislabel alone forces 15 lockstep edits.
**Reader-burden test: passes.** No file names an owner, and a skill author copying any one of them
has no way to tell which fallback is house form.

## Remedy

`normalize-wording`. **No new artifact.** Two reasons the Rule of Three does not license one here:

1. **File class.** These are shell snippets, not prose. The skill's own code and config escape
   hatch routes repeated command snippets to the language-idiomatic mechanism, and there is none
   for a `!`-injection: Claude Code substitutes the literal text at skill load, so there is no
   include to extract to. `config-extract-advisory` is the honest classification of the mechanical
   half.
2. **Portability.** Even a prose rule stating the canonical form would live in `docs/conventions/`,
   which an installed plugin cannot read. The text stays inline at all 44 sites either way, so a new
   artifact buys a name and nothing else.

An `edit-existing-rule` addition is worth proposing alongside the normalization, so the canonical
form has a stated home for future authors working inside this repository.

### Canonical form

```text
- Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
- Working tree status: !`git status --porcelain 2>/dev/null | head -<N> || echo "unavailable"`
- Recent commits: !`git log --oneline -<N> 2>/dev/null || echo "no commits"`
```

`<N>` is the per-skill slot and is not normalized. The fallback strings are not slots.

### Replacement text per call site

**Rule 1.** In each of the 26 files carrying a `Working tree status` line, replace the fallback
string with `"unavailable"`, keeping the file's existing `head -N` value. Concretely, the 15 files
whose fallback is `"clean"` change from

```text
- Working tree status: !`git status --porcelain 2>/dev/null | head -20 || echo "clean"`
```

to

```text
- Working tree status: !`git status --porcelain 2>/dev/null | head -20 || echo "unavailable"`
```

and likewise for `head -10`. Sites: `plugins/architecture/skills/improve/SKILL.md:16`,
`plugins/code-tidying/skills/tidy/SKILL.md:17`, `plugins/coupling/skills/reduce/SKILL.md:16`,
`plugins/debugging/skills/debug/SKILL.md:16`, `plugins/discovery/skills/explore/SKILL.md:15`,
`plugins/docs-hygiene/skills/rename-references/SKILL.md:14`,
`plugins/implementation/skills/implement/SKILL.md:15`,
`plugins/planning/skills/interview/SKILL.md:16`, `plugins/planning/skills/plan/SKILL.md:16`,
`plugins/planning/skills/prd/SKILL.md:16`,
`plugins/prototype/skills/explore-directions/SKILL.md:16`,
`plugins/prototype/skills/pressure-test/SKILL.md:16`,
`plugins/testing/skills/diagnose/SKILL.md:15`, `plugins/testing/skills/plan/SKILL.md:15`,
`plugins/testing/skills/run-e2e/SKILL.md:15`, `plugins/testing/skills/write/SKILL.md:15`.

The parenthesized and empty-string variants change the same way:
`plugins/codebase-health/skills/audit/SKILL.md:15`,
`plugins/mutation-testing/skills/audit/SKILL.md:15`,
`plugins/improvement/skills/find/SKILL.md:16`, `plugins/toolchain/skills/check/SKILL.md:14`,
`plugins/toolchain/skills/lint/SKILL.md:14`, `plugins/verification/skills/confirm/SKILL.md:14`.
`plugins/review/skills/fanout/SKILL.md:15` and
`plugins/review/skills/quality-gate/SKILL.md:16` already use `"unavailable"` and need no change.

`plugins/verification/skills/confirm/SKILL.md:14` additionally gains the missing `| head -20`,
since an unbounded `--porcelain` in a precomputed injection has no size ceiling.

**Rule 2.** `plugins/bugs/skills/scan/SKILL.md:16` changes its log fallback from
`"no history (shallow or fresh clone)"` to `"no commits"`. Its shallow-clone concern is real and is
already served by its own separate line, `- Shallow clone: !\`git rev-parse --is-shallow-repository ...\``,
so the information is not lost.

**Rule 3.** No change to any `head -N` or `log -N` depth.

### Proposed owner addition

Add to `docs/PLUGIN-PHILOSOPHY.md` under `### Inline-template conventions` (line 788):

```text
A skill precomputing repository context with `!` injections uses one canonical spelling of the
three standard lines, varying only the depth argument:

- `- Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"``
- `- Working tree status: !`git status --porcelain 2>/dev/null | head -<N> || echo "unavailable"``
- `- Recent commits: !`git log --oneline -<N> 2>/dev/null || echo "no commits"``

The depth is the skill's own choice about how much context its method needs. The fallback strings
are not: a failed `git status` is unavailable, never clean, and an empty fallback renders as a blank
line the reader has to guess about.
```

## ROI

MEDIUM-HIGH. 26 one-line edits, no semantic risk, and it removes a live mislabel (`"clean"` on
failure) that could mislead a skill into acting as though the tree were clean.

## Cross-lane observations

- `plugins/skill-quality/skills/check/SKILL.md:200` documents check 19, injection
  shell-declaration, and check 18, precompute opportunity. Neither checks the fallback string, so
  this drift is invisible to the existing gate. Candidate for a 26th check; out of scope here.
- No encapsulation violations in this cluster.
