# L1-derivability — `B-cc-config-ops`

130 files. `claude-config`, `claude-memory`, `claude-ops`, `context-budget`, `context-guard`,
`guardrails`, `rate-limit-guard`.

| Verdict | Count |
|---|---:|
| `keep-owns-facts` | 117 |
| `out-of-scope: functional artifact` | 12 |
| `convert-to-pointer` | 1 |

Roll-up for the 117 `keep-owns-facts`: skill bodies, `reference/` and `context/` sub-docs,
CHANGELOGs, and plugin READMEs. This group is the densest concentration of dated, externally-sourced
platform facts in the corpus (Claude Code version behavior, settings precedence, hook semantics,
auto-mode classifier behavior). Those are Factor 4 external facts by construction: the repository
does not contain the platform it describes, so no amount of exploration re-derives them. Twelve
files are functional artifacts (`**/evals/fixtures/**`, `**/templates/checklist.md`,
`plugins/context-budget/skills/audit/scripts/fixtures/context-sample.md`) and take no verdict.

## `plugins/claude-ops/skills/known-issues/context/issue-templates.md` — verdict: `convert-to-pointer` [audience: agent]

| Factor | Reading |
|--------|---------|
| Derivable? | not from this repo, but the document disclaims its own authority. Its truth lives in `anthropics/claude-code/.github/ISSUE_TEMPLATE/`, and the file itself prints the one command that fetches it |
| Re-derivation cost | cheap — a single `gh api` call the document already carries verbatim |
| Drift risk | high, self-declared — `issue-templates.md:3` "Templates may change without notice." The snapshot is dated 2026-03-29 |
| Fact ownership | none. It is explicitly not the source of truth, and its only consumer is instructed to bypass it |

Verdict rationale. This is the rubric's worked example of a cache that fails its drift-control gate:
a hand-kept restatement of an external source, with no regeneration script and no recorded recheck
trigger, so `keep-as-derivation-cache` demotes to `convert-to-pointer`.

Its own header, `plugins/claude-ops/skills/known-issues/context/issue-templates.md:3`:

> **Point-in-time snapshot for offline reference only.** `create` action MUST fetch live template
> from GitHub before drafting. Templates may change without notice.

And its consumer agrees. `plugins/claude-ops/skills/known-issues/context/action-create.md:38`:

> Template structure may change at any time — `context/issue-templates.md` is a reference snapshot,
> not source of truth.

`plugins/claude-ops/skills/known-issues/context/action-create.md:141`:

> Snapshot of template fields and body format (offline reference only — always fetch live):
> `context/issue-templates.md`

A 5.6 KB document that the only skill reading it is told never to trust is 5.6 KB of context tax
that can only mislead. It is agent-facing, where the deletion bar is lowest.

Pointer target, verified present by direct read: `context/action-create.md` (same directory), which
already carries both the live-fetch instruction and the failure rule ("If template can't be fetched
… STOP and inform user"). The live external source is
`anthropics/claude-code/.github/ISSUE_TEMPLATE/`, reachable by the command the file itself prints:

```bash
gh api repos/anthropics/claude-code/contents/.github/ISSUE_TEMPLATE/<template>.yml --jq '.content' | base64 -d
```

Replacement body: a one-line pointer naming that command and `action-create.md` as the owner of the
fetch protocol, with the 2026-03-29 snapshot content removed. Keeping the file as a pointer rather
than deleting it preserves the citation at `action-create.md:141` without a companion edit; a
`delete` would require rewriting that line too.

Spot-test: not run, and not required. This is a `convert-to-pointer`, not a deletion, and the
rubric's obligation for that verdict is target verification rather than a fresh-eyes reproduction.
Both targets were verified by direct read.

## Cross-lane observations

- L5-noise: `plugins/claude-ops/skills/known-issues/context/issue-templates.md` becomes a one-line
  file after this conversion; if L5 or L6 touches it first, the pointer conversion supersedes their
  edits (wave 3 runs L1 before both).
