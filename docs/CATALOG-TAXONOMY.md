# Plugin catalog taxonomy

This document is the single owner of the marketplace's category vocabulary. Each plugin entry in
`.claude-plugin/marketplace.json` carries one `category` value drawn from the controlled set below, and
the generated catalog groups plugins by it. Consumers of this vocabulary — the marketplace file, the
catalog generator, `docs/CATALOG.md` — conform to this document and cite it; they never restate its definitions.

Category is display-and-grouping metadata only. It never appears in an install identifier
(`plugin-name@marketplace`) or a skill invocation (`/plugin-name:skill`). Physical layout stays flat
(`plugins/<name>`); grouping lives here, not in directories or names.

## Form rule

Every category value is a lowercase noun or gerund-noun naming a domain of activity or subject matter —
never a bare-verb imperative (`development`, not `build`; `deployment`, not `deploy`; `maintenance`, not
`support`). This matches the controlled-vocabulary convention (ANSI/NISO Z39.19 §6.4.1), every value in
the official Claude Code marketplace, and the VS Code and Chrome category enumerations.

## Assignment principle

The taxonomy is **lifecycle-primary with a subject catch-all**. A plugin that serves the general software
lifecycle is filed by its lifecycle **activity**. A plugin whose defining trait is a special **subject** —
Claude Code itself, the workstation, music, personal life — is filed by that subject.

When a plugin is an activity applied to a special subject, **subject wins if the subject is the salient
reason the plugin exists**. `skill-quality` audits (activity) Claude Code skills (subject) and is filed
under `claude-code`; `mcp-tools` audits MCP-server source, a general development artifact, and is filed
under `quality`; `codebase-health` audits the general codebase and is filed under `quality`.

## Vocabulary

Lifecycle tier — the SDLC spine:

| Category | Scope |
|---|---|
| `discovery` | Explore code, research, ingest external sources. |
| `design` | Plan, model, architect, prototype before building. |
| `development` | Implement, format, lint, commit — the construction inner loop. |
| `testing` | Design, author, run, and diagnose tests. |
| `verification` | Prove a change achieved its intended outcome against baseline and intent. |
| `quality` | Reviews and audits of artifacts (SWEBOK software-quality reviews-and-audits). |
| `maintenance` | Fix, tidy, and keep an existing codebase healthy (SWEBOK maintenance). |
| `deployment` | CI/CD, environments, releases. Not yet populated — see triggers. |

Domain-and-cross-cutting tier — filed by subject:

| Category | Scope |
|---|---|
| `claude-code` | Operating Claude Code itself: its config, memory, telemetry, session plumbing, usage playbooks. Membership requires the subject to *be* Claude Code, not merely to run on it. |
| `autonomy` | Governed autonomous agent operation: adoption discovery, guardrail and sandbox contracts, standing routines, autonomy telemetry and return-accounting conventions. |
| `security` | Secret, path, and bypass guarding. |
| `workflow` | Conducting the development session and process: staging, handoff, retrospective, orchestration priming. |
| `project-management` | Tracking, triaging, and decomposing the work backlog. |
| `operations` | Workstation day-2 operations — monitoring and remediation. |
| `learning` | Coaching the human through a subject. |
| `music` | Songwriting and music craft. |
| `personal` | The owner's personal-life tooling, outside the software-delivery lifecycle. |

Current per-plugin assignments are owned by `marketplace.json`, not restated here; the generated catalog
renders them.

## Singleton governance

A category with one member is legitimate when its label positively predicts its member (Nielsen Norman
Group: a category name must predict its contents). A value earns its place by naming a genuinely distinct
discipline — not by balancing bucket sizes. Do not merge a singleton into a broader category if the merge
would force a vague or junk label onto the combined set; the distinct, honest label is preferred. Revisit
a singleton only if it would otherwise need a misleading label to survive.

## Trigger register

Conditions that change this taxonomy, recorded so they are acted on when met, not forgotten. Category-level
triggers are owned here; plugin-scoped revisit conditions are owned by each plugin's own README and listed
here only as pointers.

Category-level:

| Trigger | Action |
|---|---|
| First deployment plugin lands | Populate the `deployment` category (already reserved above). |
| A non-music creative plugin lands | Broaden `music` — rename to `creative` or add a sibling creative category — rather than filing the newcomer under `music`. |
| A broader automation plugin lands (automation that is not governed-autonomy-scoped) | Broaden `autonomy` or add a sibling category rather than filing the newcomer under `autonomy`. |

Plugin-scoped (owned by the named plugin's README):

| Plugin | Possible future change |
|---|---|
| `firecrawl` | Split into a dedicated document-`parse` skill. |
| `knowledge` | Extraction of a standalone `youtube` plugin. |
| `kindle-dedrm` | Relocation out of `personal`. |
| `work-items` | Further decomposition of the `track` skill. |
| `playbooks` | Regeneration of the `fable-5` pack (model-version-triggered). |

## Generation contract

The human-browsable catalog is generated, not hand-maintained. `marketplace.json` is the single source of
truth for each plugin's `category` and the ordering key; `plugin.json` owns each description. The generator
emits the grouped catalog section between markers in `docs/CATALOG.md`, and a CI check fails when the committed
section drifts from what the manifests would produce. This retires hand-maintained catalog duplication and
keeps the grouped view and the manifests from diverging.
