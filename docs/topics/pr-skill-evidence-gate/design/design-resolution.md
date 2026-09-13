# Design resolution: pr-skill-evidence-gate

- outcome: light design (Tier B), resolved inline with a type sketch
- date: 2026-09-13 (revised the same day after the fresh-context plan review and stress test)
- reason: the change introduces two small contracts (a ledger row gains two fields; a PR body gains
  one fenced block) and one configuration key, all consumed by scripts that already exist or by one
  new script. No new module, no package topology change, no cross-plugin type sharing beyond a
  line-oriented text format. A full `/planning:design` pass would re-derive what the Brief already
  fixed.

## Type sketch

### Ledger row (`skill-usage.jsonl`, claude-ops second store)

Existing fields stay as they are. Two additive fields, both optional for readers:

| Field | Type | Present when | Source |
|---|---|---|---|
| `sha` | 40 hex | always inside a git work tree | `git rev-parse HEAD --abbrev-ref HEAD` (SHA first, then the branch, one spawn) |
| `pr` | decimal string | `branch.<name>.pr-number` is set in git config | written by the pull-request skill's create step; best-effort telemetry, no reader depends on it |

A row is stamped when the Skill tool call returns, which is when the skill is *invoked*, before
any edit the skill goes on to make. Every freshness rule below is written with that in mind.
Readers that filter on `event == "SkillUse"` keep working; the two fields are ignored by every
existing consumer (pre-flight in Phase 1 confirms).

### Evidence block (PR body, under `## Verification`)

A fenced code block whose info string is `skill-evidence`. Inside, one row per skill:

```text
<skill> <sha> <utc-timestamp>
```

- `<skill>` is the Skill-tool name as the ledger records it (`review:quality-gate`, `simplify`).
- `<sha>` is the 40-hex commit the skill was invoked at.
- `<utc-timestamp>` is `YYYY-MM-DDTHH:MM:SSZ`.
- One row per skill, the latest row wins. Rows are sorted by skill name. Blank lines are ignored.
  When a body carries two blocks, the first is read and the second is reported as a warning.
- The block is the machine surface; the prose around it is for humans.

### Freshness rule (one definition, three readers)

Two tiers, because rows are stamped at invocation and mutating skills (simplify, a fanout fix
pass) always precede the commit that carries their result:

- **The terminal skill** (the config marks it with a trailing `!`; here `verification:confirm!`)
  needs a row whose SHA **equals HEAD**. It is the seal the pre-PR order already places last, and it
  is non-mutating, so the sequence terminates.
- **Every other mandatory skill** needs a row whose SHA is HEAD or an **ancestor of HEAD** on
  the branch. Readers report `commits-since=<n>` (non-merge commits after the row) beside each row
  so a human sees how far back the evidence sits.

Consequences the plan states plainly: a base refresh by merge keeps every non-terminal row and
re-runs the terminal skill at the merge commit (the honest cost of refreshing); a rebase or
amend rewrites SHAs and invalidates every row, so once a PR exists the ready step merges, never
rebases; a conflict-resolution merge moves HEAD and so re-runs the terminal skill, which closes
the evil-merge hole a merge-only ancestry rule would have left.

In CI and in the babysit gate, ancestry is read over REST: `compare/{R}...{H}` reports
`identical` or `ahead` when `R` is on `H`'s history, `behind` or `diverged` otherwise. No
checkout with history is needed anywhere.

### Mandatory map (consumer config key `pr_skill_evidence`)

Resolved through the same three-layer ladder as every other `.claude/source-control.md` key.
The section body is a flat bullet list, one rule per bullet, three fields separated by ` | `:

```text
- <class> | <patterns> | <skills>
```

- `<class>` is a label used in messages.
- `<patterns>` is a space-separated list of gitignore-style patterns; `@file:<path>` reads
  patterns from a repo file; the single pseudo-pattern `@renamed` matches any path the diff
  reports as renamed.
- `<skills>` is a space-separated list of required skills; a token `a,b` means "any one of a or b";
  a trailing `!` marks the terminal skill (at most one per map, checked at HEAD exactly).
- Absent from every layer, or `none`: no rules, the mechanism is inert (lane-1 portable default).
  A local overlay declaring `none` disables drafting on that machine only; CI still reads the
  tracked layer, the same drafting-versus-enforcement split config-resolution.md already documents.

### Script surface (`plugins/source-control/scripts/skill-evidence.sh`)

| Subcommand | Reads | Writes | Used by |
|---|---|---|---|
| `classes --base <ref>` | git diff, config | class list to stdout | prep, ready, the hook |
| `check --head <sha> (--ledger <file> \| --body <file>) [--base <ref> \| --compare <json>]` | ledger or body, config, git or a REST compare result | `missing=`, `stale=`, `commits-since=` lines; exit 0 always | the hook (ledger), the validator (body), ready (ledger) |
| `render --ledger <file> --head <sha>` | ledger | the fenced block to stdout | create and ready |
| `report --repo <owner/repo>` | GitHub over REST (validator comment markers, merged PRs) | fired and fired-then-agreed counts per gate | promotion review |

Pattern matching runs `git -c core.excludesFile=<patterns file> check-ignore --no-index -v` and
keeps only matches whose source is that file, because `--no-index` still consults the repository's
own ignore rules. Exit codes: 0 on every audit path (advisory), 2 on usage error.

### Ledger location for the source-control readers

Plugin options are per plugin, so source-control cannot read claude-ops' `skill_usage_scope`.
The option `skill_evidence_store` takes `repo` (default: `.claude/observability/skill-usage.jsonl`
under the checkout the skill runs in, which in `create --pushed --worktree` mode is the target
worktree), `user` (the same subpath under `$HOME`), or an explicit path. claude-ops' `data-dir`
scope is documented as unsupported for evidence. A missing store is reported once per session and
then treated as "no rows".

## Design defaults walked

- Configurability: one consumer key, one plugin option.
- Extension points: new classes are new bullets; no code change.
- Observability: the validator's comment marker carries the head and the verdict, so both
  promotion counts (fired, fired-then-agreed) read from GitHub through one subcommand; the hook
  records nothing of its own, since a flip it flags is a head the validator flags too.
- Testability: the script is pure over a ledger file, a body file, a git fixture, or a compare
  JSON; every reader is black-box tested through the CLI, never by sourcing internals.
