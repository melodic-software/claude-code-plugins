# Changelog

All notable changes to the `mcp-tools` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.6.3] - 2026-10-04

### Changed

- **Shared `prerequisites` checker copies synced ([#6225](https://github.com/melodic-software/claude-code-plugins/issues/6225)); no change to this plugin's behavior.**

## [0.6.2] - 2026-10-03

### Changed

- **Shared `prerequisites.mjs` synced ([#6084](https://github.com/melodic-software/claude-code-plugins/issues/6084)); no change to this plugin's lib.**
  The prerequisite check now counts a Windows App Execution Alias (a Store or winget install on PATH) as found,
  except App Installer's Python install stub. A `cli` or `runtime` entry can set `reject_store_alias` to skip aliases instead; no entry in this plugin does.

## [0.6.1] - 2026-10-03

### Changed

- Shared `prerequisites.sh`, `prerequisites.ps1` synced ([#5843](https://github.com/melodic-software/claude-code-plugins/issues/5843)); no change to this plugin's own behavior.

## [0.6.0] - 2026-10-02

### Added

- `prerequisites.json`, declaring the external tools this plugin runs and what stops working
  without each, and the generated `lib/prerequisites.mjs` checker with its `.sh` and `.ps1`
  stubs that read it ([#5842](https://github.com/melodic-software/claude-code-plugins/issues/5842)).

## [0.5.8] - 2026-10-02

### Fixed

- `plugin.json` no longer sets `$schema`. claude.ai's marketplace sync stripped it with a warning, and Claude Code ignores it at load time.

## [0.5.7] - 2026-10-01

### Changed

- **The `audit-posture` and `audit` checklists keep source records as decisions plus pointers.** The
  sandbox scope, the MCP review responsibility and the registry-listing records state what the
  audit decides and point at the documentation section with an as-of date and a recheck trigger,
  and carry none of the page's wording.
- **The tool-design source now points at the Define tools best-practices section.** The `audit`
  skill and README cite that section as the pointer and keep the engineering post as a correlate.

## [0.5.6] - 2026-10-01

### Changed

- References to the `claude-config`, `claude-memory` and `claude-ops` plugins now use their new
  names, `harness-config`, `harness-memory` and `harness-ops`.

## [0.5.5] - 2026-09-29

### Changed

- **`audit-posture` marks `provided_by` as informational.** Phase 1 now says the column only lets
  the operator tell organization-provided servers (which `claude mcp remove` refuses) from
  user-configured ones; no P1-P5 criterion reads it. The Phase 3 inventory table gains a
  `Provided by` column so the saved report keeps it.

### Fixed

- In-place correction of the released 0.5.2 entry: its `### Added` bullet repeated the 0.5.1
  `provided_by` entry although 0.5.2 made no consumer-visible or implementation change. The body
  now says so.

## [0.5.4] - 2026-09-28

### Changed

- **Argument hints** on `audit`, `audit-posture` stay inside the 100-character house style
  ([#3542](https://github.com/melodic-software/claude-code-plugins/issues/3542)).
  Examples, defaults, and flag catalogs that exceeded the budget now live in the skill body.

## [0.5.3] - 2026-09-28

### Changed

- **`audit` runs as a blocking fork** (`context: fork`, `background: false`) (#3545). The body
  is an isolated subagent prompt with no parent history; the optional path argument and the
  working tree are the whole input. The caller waits for the scorecard in the same turn.
  `audit-posture` stays inline. Rubric: `docs/conventions/invocation-context/`.

## [0.5.2] - 2026-09-28

### Changed

- No consumer-visible change. The version was bumped by the
  [#4027](https://github.com/melodic-software/claude-code-plugins/issues/4027) close-out chore;
  the `provided_by` attribution shipped in 0.5.1.

## [0.5.1] - 2026-09-28

### Added

- **`audit-posture` attributes `managedMcpServers`** ([#4027](https://github.com/melodic-software/claude-code-plugins/issues/4027)). The inventory TSV gains `provided_by`: `organization` for a `managedMcpServers` row, `managed-mcp.json` for a server from that file, and `-` otherwise. Those organization servers are the ones `claude mcp remove` refuses.

## [0.5.0] - 2026-09-26

### Added

- `audit-posture` skill: a consumer-side supply-chain audit of the MCP servers configured in Claude
  Code. Its `scripts/inventory.sh` reads user, local, project, managed, and passed-in config
  statically and emits a dated, sorted TSV inventory (scope, effective, transport, launcher,
  package, pin, publisher, sandboxed) with a coverage footer naming the sources it cannot read. It
  never prints `env` or `headers` values or any argument other than the package spec, and never
  runs, installs, or connects to a server.
- `skills/audit-posture/reference/checklist.md`: criteria P1-P5 (floating version, local stdio
  where the vendor offers a remote endpoint, publisher provenance, OCI image available but unused,
  inventory) with severities and a four-part source record for each factual claim.
- Evals for `audit-posture`: floating-version detection, routing a tool-design question to
  `/mcp-tools:audit`, refusal to print secrets or start a server, and no invented FAIL on a
  remote-only configuration.

### Changed

- `audit`'s description routes "is it safe to run" questions to `/mcp-tools:audit-posture` instead
  of disclaiming MCP server configuration, and its "What this skill does NOT do" list points there.
- The README and manifest description present the plugin as two audits: author-side design quality
  and consumer-side supply-chain posture.

## [0.4.1] - 2026-09-25

### Changed

- Comment-only pass with /code-tidying:dissolve-comments: restating comments, history narration and ticket back-references removed from scripts and tests, over-budget rationale shortened. Every edit is certified comment-only by a token-level proof, so behavior is unchanged; the removed text is recorded in the commit bodies.

## [0.4.0] - 2026-09-23

### Changed

- `audit` checks each Phase 2 subagent's evidence before accepting its verdicts and consolidates
  them into the one Phase 3 report.

## [0.3.6]

### Changed

- The markdown-format hook uses the shared hook-utils git-tree and dirname helpers instead of local copies, its suite and the powershell-format suite route repeated invocations through shared runners, and the mcp-tools discover, mutation-testing suppression-lint, and playwright update scripts fold duplicated blocks into helpers, with identical output.

## [0.3.5]

### Changed

- **Manifest description drops its em dashes.** Wording only; the plugin's behavior, options, and defaults are unchanged. The description renders into `docs/CATALOG.md`, which the repository's em-dash gate reads.
- **The plugin's prose drops its em dashes.** Nine surfaces were rewritten: this changelog, the README, `skills/audit/SKILL.md`, two `skills/audit/reference/` documents, and the four eval fixtures. Wording only, with no change to any criterion, code, severity, or budget. Every criterion keeps its code, and `evals.json` refers to criteria by code rather than by name, so no expectation moved. In each fixture the dash sat in the descriptive header, never in the fenced tool source the audit is graded on, which is byte-identical. The report-output template inside `SKILL.md`'s fenced block was rewritten with the prose it belongs to, so a run still prints what the body describes. No heading changed, so no anchor moved. The released sections corrected in place are 0.3.0, 0.2.4, 0.2.3, and 0.2.1: their wording changed, their facts did not.
- **The 0.2.4 entry names the duplication instead of calling it a drift seam.** It now reads "and so a source of drift".
- **The plugin's markdown is declared in `scripts/em-dash-purged-paths.txt`.** The gate now defends `CHANGELOG.md`, every `skills/*/SKILL.md`, the `skills/audit/reference/` tree, and the audit eval fixtures.

## [0.3.4]

### Changed

- Date the C17 and C18 client-behavior values, and drop the undocumented 2KB description-truncation claim so C4 states its own budget (prompt-audit follow-up F6)

## [0.3.3]

### Changed

- audit: dropped the two Claude Code version floors from the C18 and C19 checklist rows; removed the orientation-section annotation sentence whose spec-provenance claim was wrong for C17 to C19 (the scoped rule at C12 to C14 and in SKILL.md stays); Phase 1 discovery is one command with its `--path` scoping clause instead of two steps saying the same thing; the Python server-constructor note names both spellings without the module-rename history.
- Applied from the 2026-09 prompt-audit against Claude Fable 5.1 (docs/specs/prompt-audit-skills-2026-09.md).

## [0.3.2]

### Changed

- **Instruction-surface de-slop (#2891, mcp-tools cluster).** Rewrote this plugin's `README.md` and every
  `SKILL.md` to drop em dashes under the repo's zero-tolerance house policy, using
  `/ai-slop:audit fix` semantics: periods or commas, or a restructured sentence, never
  parentheses, en dashes, or a spaced hyphen as a stand-in. Meaning stays; only the mark
  and the sentence break change. Official page titles in the three authority links keep
  their em dashes so the cited titles stay verbatim.

## [0.3.1]

### Changed

- **Fixture-building tests clear inherited git environment (#2872).** Suites
  that build a git fixture now unset `GIT_DIR`, `GIT_WORK_TREE`, and
  `GIT_CONFIG` so an inherited environment cannot write the fixture identity
  into the caller's repository. Test-only; no plugin behavior change.

## [0.3.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command, which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.2.4]

### Changed

- The Phase 3 aggregate surfaces now account for the whole result vocabulary
  instead of three buckets. The `Overall` line and the summary-by-server table
  gain an `Info` column, and the reporting guidance states that those counts
  cover a server's server-level criterion rows as well as its tools' rows.
  Previously the per-server score aggregated "across all tools", structurally
  excluding the server-level C4 outcome the report had just rendered. `n/a` and
  `undetermined` are named as non-severities that appear only in the
  server-level criterion table, closing the gap where the text referred to a
  summary table with no column for them.
- C4's size budget is stated in the unit its cited source uses: the Claude Code
  MCP page says descriptions and server instructions truncate at 2KB each, so
  the evaluation reads "over 2KB" in bytes rather than "~2000 characters", and
  notes that non-ASCII UTF-8 characters spend more than one byte. The two
  diverge on any multibyte text.
- `reference/server-discovery.md` describes the server `instructions` field by
  how the protocol delivers it rather than by a single emission site: via
  `InitializeResult` on `initialize` for protocol revision 2025-11-25 and
  earlier, and via `DiscoverResult` on `server/discover` for 2026-07-28 and
  later.
- The same file records C4's no-`instructions` outcome as `n/a`, the literal
  token SKILL.md defines, instead of the prose "not applicable".

### Removed

- `skills/audit/templates/checklist.md`, an unreferenced second copy of the
  result vocabulary, and so a source of drift. The skill's "Track progress" section
  already asks for an in-response checklist and never pointed at the file.

## [0.2.3]

### Added

- Checklist section 7 (C17-C19): the Claude-Code-specific `_meta` annotations
  documented on the Claude Code MCP page. They are `anthropic/maxResultSizeChars`
  (per-tool result-size ceiling, hard-capped at 500,000 characters),
  `anthropic/requiresUserInteraction` (per-call consent prompt; JSON boolean
  `true` only; Claude Code v2.1.199+), and `anthropic/alwaysLoad` (per-tool
  tool-search deferral exemption). Missing is at most an info advisory. The
  defect splits two ways: declared-but-ineffective (C17 over the ceiling or on
  an image-returning tool, C18 set to anything but JSON `true`) and
  declared-honored-but-unwarranted (C19 over-declared, spending session-start
  context deferral would have saved).
- A `meta-extraction` rule per SDK in `reference/server-discovery.md`, so
  C17-C19 have an extraction contract following the same shape as the existing
  tool-marker / name / description rules:
  Python's `meta=` argument on `@mcp.tool`, the `_meta` field of the config
  object passed to TypeScript's `server.registerTool`, and .NET's repeatable
  `[McpMeta]` attribute. Each entry names how that language spells the JSON
  boolean `true` versus a string or a number, which is what C18's FAIL turns on.
- Three result values the criteria already needed but the skill had no words
  for: `info` (the severity the checklist assigns to C8, C11, C14 and by
  default to C17-C19), and `n/a` / `undetermined` for C4's per-server clause.
  The Phase 3 report gains a server-level criterion block under each
  `### Server:` heading, so a server-scoped outcome has somewhere to land
  instead of being evaluated and dropped.
- An eval and fixture for C18's JSON-type rule: paired TypeScript and .NET
  tools declaring `anthropic/requiresUserInteraction` correctly and as a JSON
  string, so the eval discriminates rather than only detecting.

### Changed

- C4's size budget now also covers the server `instructions` field. Claude
  Code truncates tool descriptions and server instructions at 2KB each.
  `discover.sh` emits per-tool records only, so Phase 2 gains a once-per-server
  step that resolves `instructions` from the server's construction site; without
  it the new clause would have had no input to audit. That construction site is
  usually not one of the discovered tool files, so the step searches the
  server's subtree and names the per-language spelling (`instructions=`,
  `ServerOptions.instructions`, `McpServerOptions.ServerInstructions`). A server
  declaring no `instructions` is recorded not applicable rather than passing;
  one whose construction site is out of scan scope is recorded undetermined.
  That step carries an untrusted-content caution matching the one already on
  discovered file paths: the protocol defines `instructions` as text aimed at
  steering a connecting LLM, so it is read only to measure its length.
- The Python SDK is named by its package (`mcp`) rather than by `FastMCP`,
  which [v2.0.0](https://github.com/modelcontextprotocol/python-sdk/releases/tag/v2.0.0)
  renamed to `MCPServer` with no back-compat alias. The `@mcp.tool` marker
  survives the rename, so discovery is unaffected, and the package name is
  correct for both the 1.x and 2.x lines, matching how the TypeScript and .NET entries
  already name theirs.
- The OPINION authority row now states that C4 and C17-C19 draw their
  client-behavior facts from the Claude Code page. The tag stays OPINION
  because that page documents Claude Code's behavior rather than mandating the
  criterion, but the Source column no longer reads as if the facts were
  ungrounded.

## [0.2.2]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.2.1]

### Changed

- README gains a Requirements section declaring the audit's Bash + coreutils
  and `jq` mechanics with their Windows path (Git Bash; `jq` is a separate
  install there). Part of the cross-platform declaration wave.

## [0.2.0]

First versioned release covered by this changelog; see the git history of
`plugins/mcp-tools/` for earlier changes.
