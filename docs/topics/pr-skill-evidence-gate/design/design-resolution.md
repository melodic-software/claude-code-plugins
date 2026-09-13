# Design resolution: pr-skill-evidence-gate

- outcome: light design (Tier B), resolved inline with a type sketch
- date: 2026-09-13
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
| `sha` | 40 hex | always inside a git work tree | `git rev-parse HEAD` at hook time |
| `pr` | decimal string | `branch.<name>.pr-number` is set in git config | written by the pull-request skill's create step |

Readers that filter on `event == "SkillUse"` keep working; the two fields are ignored by every
existing consumer (pre-flight in Phase 1 confirms).

### Evidence block (PR body, under `## Verification`)

A fenced code block whose info string is `skill-evidence`. Inside, one row per skill:

```text
<skill> <sha> <utc-timestamp>
```

- `<skill>` is the Skill-tool name as the ledger records it (`review:quality-gate`, `simplify`).
- `<sha>` is the 40-hex commit the skill ran against.
- `<utc-timestamp>` is `YYYY-MM-DDTHH:MM:SSZ`.
- One row per skill: the latest row wins. Rows are sorted by skill name. Blank lines are ignored.
- The block is the machine surface; the prose around it is for humans.

### Freshness rule (one definition, three readers)

A row with commit `R` is fresh for head `H` when `R == H`, or when `R` is an ancestor of `H` and
`git rev-list --no-merges R..H` is empty (only base merges happened since the evidence). This is
what lets "update branch" keep a PR green without re-running every skill, while any new
non-merge commit makes the evidence stale.

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
- `<skills>` is a space-separated list of required skills; a token `a,b` means "any one of a or b".
- Absent from every layer: no rules, the mechanism is inert (lane-1 portable default).

### Script surface (`plugins/source-control/scripts/skill-evidence.sh`)

| Subcommand | Reads | Writes | Used by |
|---|---|---|---|
| `classes --base <ref>` | git diff, config | class list to stdout | prep step, hook, validator |
| `check --head <sha> (--ledger <file> \| --body <file>) --base <ref>` | ledger or body, config | `missing=` and `stale=` lines; exit 0 always | hook (ledger), validator (body), ready step |
| `render --ledger <file> --head <sha>` | ledger | the fenced block to stdout | create and ready steps |
| `report --ledger <file>` | ledger | fired and fired-then-agreed counts | promotion review |

Exit codes: 0 on every audit path (advisory), 2 on usage error. The validator and the hook wrap the
check in their own reporting; neither turns anything red until promotion.

## Design defaults walked

- Configurability: one consumer key, one plugin option (`skill_evidence_store`, the ledger path
  the source-control hook reads, because plugin options are not shared across plugins).
- Extension points: new classes are new bullets; no code change.
- Observability: the hook appends a `SkillEvidenceGate` row to the same ledger when it fires, so
  the promotion count reads from one file.
- Testability: the script is pure over a ledger file, a body file, and a git fixture; every reader
  is black-box tested through the CLI, never by sourcing internals.
