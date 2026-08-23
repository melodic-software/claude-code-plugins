# Self-review (default mode)

Design judgment and completeness check after implementation, before verification or PR. **Not a build check.**

**Dispatch policy:** the producing main thread MUST NOT run the checklist inline — the thread that wrote the code rubber-stamps its own recap. Orchestrate a fresh-context read-only subagent; the main thread gathers inputs, dispatches, verifies findings, and presents the verdict. Where the verdict is high-stakes and correlated blind spots are the risk, prefer a cross-vendor advisor **when one is installed and set up** — e.g. the OpenAI Codex plugin, when its documented surface can take this artifact, invoked per its own docs — with the fresh-context same-vendor subagent as the stated fallback, never a route to a command that may not resolve (per `docs/PLUGIN-PHILOSOPHY.md` "Fresh-eyes checkpoints" in the marketplace repository).

## Orchestrator sequence (main thread)

1. **Gather inputs** — the pre-computed git facts; the approved plan or task brief when one exists — in the conversation, else the topic's contract slice `<contract_dir>/<slug>/PLAN.md` (default `docs/topics/`), falling back to the memory tier `<memory_dir>/<slug>/` (default `.work/`) under `contract_tier: local`; resolve both roots from `.claude/topic-docs.yaml` per the binding ([`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md))
2. **Choose the worker** — prefer this plugin's `code-reviewer` agent; else a general read-only subagent
3. **Dispatch** with the prompt template below
4. **Verify each finding** (diff read, grep, file assert) before presenting — worker output is synthesis, not evidence
5. **Write the findings artifact** to the findings location (SKILL.md "Shared inputs"), even on a clean pass — a missing artifact must mean "review never ran," not "review found nothing"
6. **Present** findings table + strengths + verdict; suggest escalation when warranted
7. **Do not fix during review** — fixes happen after review completes

For large diffs, dispatch two parallel read-only workers with the same template and one **lens** each — standards conformance vs spec conformance. Verify both sets as usual, then **present them separately, under their own headings**: the two lenses answer different questions, so a combined list lets a clean standards pass mask a failing spec pass (and the reverse). "Lens" is the deliberate word here — in this plugin **`axis` means severity/confidence** ([`${CLAUDE_PLUGIN_ROOT}/context/severity.md`](${CLAUDE_PLUGIN_ROOT}/context/severity.md) "Vocabulary"), and merging and ranking across those two is exactly what `fanout` exists to do.

## Subagent prompt template

```text
You are a fresh-context reviewer. You did NOT author this work.

Read in order:
1. The project's own review criteria and conventions when present (REVIEW.md,
   review guides, CLAUDE.md, project rules for the changed file types).
2. The change set: git diff <review-diff-base> (the dispatcher substitutes the
   resolved review diff base from SKILL.md "Shared inputs" — the PR's real base
   when one exists, else the origin/HEAD -> remote default branch -> origin/main -> HEAD fallback)
   plus untracked files from git ls-files --others --exclude-standard.

Run the checklist below. Do not edit files. Return the findings table only.

## Worker checklist

### Completeness
- Every planned item has a corresponding change (when a plan/brief exists)
- No TODO/FIXME representing unfinished work
- No deferred edge cases that should have been handled
- No partial validation chains or incomplete error handling

### Consistency
- New files match neighboring naming conventions
- New types match patterns in the same module
- Code style and import organization match surrounding code

### Convention compliance
- Apply the project's documented rules for the changed ecosystems

### No debugging artifacts
- No stray print/log/debug statements left behind
- No commented-out code blocks
- No hardcoded test values that should be configuration

### No loose ends
- New public APIs have tests
- New dependencies declared in the project's dependency manifest
- Error messages are user-safe

### Spec conformance (when a plan/brief exists — surface check only)
- Flag anywhere the change diverges from the plan/brief, quoting the line diverged from. Do not
  classify or grade the divergence; a dedicated lens owns that taxonomy and the dispatcher routes
  to it.

Report format:

## Review: self — <branch>

### Findings
| # | Severity | Category | Finding | File:Line | Action |

### Summary
CRITICAL / IMPORTANT / SUGGESTION counts

If zero findings: "No self-review issues found in changed files."
```

## When to suggest escalation

- Spec fidelity — the change judged against what was actually asked for → `spec` mode
  ([spec.md](spec.md)), which owns the finding-class enum and the spec-source
  discovery ladder. The checklist above only surfaces divergence; this is where it gets classified
  and graded
- Dependency direction / module boundaries → `architecture` mode
- Auth, input handling, secrets → `security` mode
- Widespread code-quality concerns → `code` mode
- Design fundamentally flawed → revisit the plan/design before more code lands
