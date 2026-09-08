# claude-config audit skill improvements

## Brief

### TLDR

- A script engine decides every deterministic audit row and emits JSON; the model does only judgment rows and the report.
- Findings persist as audit-pass-shaped rows so `audit-pass` consumes them and a re-run can diff.
- Session posture is declared in a concern file, never sniffed; allow-list completeness rows drop to info.
- Hook coverage for the third baseline narrowing comes from a manifest the hook plugin declares (separate slice, touches guardrails).
- Mechanical fixes ship first as their own issue: doc pointers to `settings-reference`, directory-source drift, cache-versus-loaded hook inventory, debug-log read for Category G, last-verified dates, a `## Next` section.

### Goal

Running `/claude-config:audit` costs a handful of tool calls instead of dozens, reports only rows a
consumer can act on in the session posture it declared, leaves a findings artifact that
`audit-pass` and a later re-run can read, and degrades visibly rather than silently when GitHub,
an optional sibling plugin, or a debug log is unavailable. The skill's purpose is unchanged:
config-file correctness against upstream truth.

### Constraints

- Only rows decidable by `jq`, a file-exists test, a regex, or a grep of a page fetched in the run
  move into the engine. Every row that needs a reading stays with the model: the Category B
  narrowings, Category C disable reasons, "timeouts reasonable", "justified custom var", the
  Category G levers, and all of Phase 3.
- Findings rows use audit-pass's identity tuple (`check`, `claim`, `sites` of `surface` plus
  `anchor/v1`) with `lane`, `attempt`, `tier` as run metadata. No second row schema in the plugin.
- Session posture is declared by the consuming repo in a concern file layered per the
  config-cascade convention. The skill never reads `CLAUDE_CODE_REMOTE`, auto-mode state, or any
  environment signal to decide it.
- Every composition is presence-gated with a hard degrade: the guardrails coverage manifest,
  `claude-ops:known-issues`, and `audit-pass` may each be absent in a consumer repo and the audit
  still completes with the same categories.
- The bootstrap script and the fleet plugin list are out of scope. Environment-side state is
  reported only where it changes what the audit can claim.
- The coverage manifest is a cross-plugin contract and ships as its own slice against guardrails.
- Upstream doc citations follow the repo's upstream-drift convention: fetch verbatim, grep the file,
  a truncated read supports no finding.

### Acceptance criteria

- One engine script run emits a JSON document covering every Category A row, the Category D rows
  for path resolution, readability, millisecond-shaped timeouts, matcher classification,
  placeholder quoting and duplicates, the Category E static and drift rows, the Category F secret
  scan and forward-slash check, and the Category H and I value checks; a full audit on this
  repository issues no more than ten Bash calls before Phase 4.
- The audit writes `findings.json` rows in audit-pass's identity shape to the topic's memory tier,
  and `audit-pass` appends those rows through its own `partial append` without transformation.
- With a concern file declaring an exempted baseline family, the report omits that family's finding
  and names the declaration; with no concern file, the finding stands at its unnarrowed severity.
- The B.5 allow-list rows (`git commit`, `git fetch`, `git stash`) report at `info`.
- When a hook plugin ships a coverage manifest, the third narrowing cites the manifest and names its
  opt-out levers; when none ships, the finding is stated conditionally as today.
- Phase 3.2 tries the REST endpoint, then `claude-ops:known-issues` when installed, and otherwise
  reports each known issue as unverified with the date from its last-verified column.
- Category G reads an existing debug log first and, when the over-budget warning is present,
  reports skill count, character count and budget from it without prompting for a relaunch.
- `check-plugin-drift.sh` diffs `enabledPlugins` against a directory-source marketplace's on-disk
  `marketplace.json` instead of reporting SKIP.
- `check-hook-coverage.sh` resolves a directory-source plugin's hooks from the marketplace
  directory the session loads, and reports cache-versus-loaded divergence as info.
- Every key the checklist cites resolves on the page it names, and a fetch-and-grep test fails when
  a cited page stops carrying a cited key.
- `known-issues.md` rows carry a last-verified date, and the skill body carries a `## Next`
  section.
- IF the engine cannot read a scope, THEN it reports that scope as not inspectable rather than
  clean.
- WHILE a fetched page is truncated, no Phase 3 finding is reported from it.

### Captured assumptions

- audit-pass's anchor grammar fits JSON config files through its no-heading-concept path; revisit
  if implementing the row emitter shows the excerpt discriminator collides on repeated JSON keys.
- The documented debug-log locations are stable enough to search; revisit if the CLI reference
  moves them or a cloud session stops writing one.
- Consumer repos will adopt a concern file for posture; revisit if the first two consumers instead
  ask for a settings key.

### Out-of-scope

- Auditing the cloud bootstrap or the fleet plugin list (environment component, own repo).
- Sniffing session mode from environment variables.
- A full environment audit (`claude-ops:audit-install-state` owns it).
- Retiring Phase 3.2 entirely in favour of claude-ops.

### Deferred questions

- None.

## Plan
