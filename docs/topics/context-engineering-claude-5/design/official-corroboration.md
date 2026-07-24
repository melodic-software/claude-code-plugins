# Official corroboration — each source claim against current documentation

The source is one practitioner's post. Every rule it states is checked here against official
documentation fetched 2026-07-24. Where a doc confirms the rule, the doc is the authority and the
post is a restatement. Where no doc confirms it, the rule is `OPINION`-tier under the authority axis
already defined in `claude-config/skills/audit-instructions/reference/criteria.md`.

Pages fetched this session:

- <https://code.claude.com/docs/en/commands> — `/doctor`
- <https://code.claude.com/docs/en/best-practices> — CLAUDE.md include/exclude, verification,
  subagents, adversarial review
- <https://code.claude.com/docs/en/memory> — CLAUDE.md load order, `.claude/rules/`, auto memory
- <https://code.claude.com/docs/en/workflows> — dynamic workflows, verifier agents
- <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5>
  — model-era prompting and scaffolding changes

Pages fetched in the Phase 1 sweep (2026-07-24):

- <https://code.claude.com/docs/en/skills> — progressive disclosure, skill content lifecycle,
  `context: fork`, dynamic context injection, `skillOverrides`
- <https://code.claude.com/docs/en/plugins> — plugin layout, manifest fields, component directories
- <https://code.claude.com/docs/en/plugins-reference> — manifest schema, `${CLAUDE_PLUGIN_ROOT}` /
  `${CLAUDE_PLUGIN_DATA}`, `userConfig`
- <https://code.claude.com/docs/en/hooks> — the hook event list, including `InstructionsLoaded`
- <https://code.claude.com/docs/en/sub-agents> — what loads at a subagent's startup, subagent memory
- <https://code.claude.com/docs/en/tools-reference> — the `ToolSearch` entry and deferred tools
- <https://code.claude.com/docs/en/claude-directory> — surface enumeration
- <https://code.claude.com/docs/en/debug-your-config> — the native diagnostic path
- <https://code.claude.com/docs/en/large-codebases> — root and per-directory layout, `claudeMdExcludes`
- <https://code.claude.com/docs/en/settings> — settings scopes and precedence
- <https://code.claude.com/docs/en/context-window> — startup load order and what survives compaction

| § | Source rule | Official status |
|---|---|---|
| S2 | `/doctor` rightsizes skills and `CLAUDE.md` | **Confirmed, and broader than stated.** Commands doc: it deduplicates local `CLAUDE.md` against checked-in ones, "trims checked-in `CLAUDE.md` files by cutting content Claude could derive from the codebase, and migrates the always-loaded guidance that remains into skills and nested `CLAUDE.md` files that load on demand." Memory doc adds the trim requires v2.1.206+ and names what it cuts (directory layouts, dependency lists, architecture overviews) and keeps (pitfalls, rationale, conventions differing from tool defaults). |
| S2 | 80% of the system prompt removed with no eval loss | **Unconfirmed.** No official page states this. `OPINION`-tier; the directional claim it supports (capability improvements warrant re-auditing instructions) *is* official — Fable 5 guide: "Capability improvements at this level are also a good prompt to re-evaluate which instructions, tools, and guardrails are still needed." |
| S3 | Conflicting instructions across surfaces cost the model reasoning | **Confirmed.** Memory doc, "Consistency": "if two rules contradict each other, Claude may pick one arbitrarily. Review your CLAUDE.md files, nested CLAUDE.md files in subdirectories, and `.claude/rules/` periodically to remove outdated or conflicting instructions." Troubleshooting repeats it: "Look for conflicting instructions across CLAUDE.md files." **No tool performs this review** — the docs prescribe it as a manual periodic task. |
| S4 | Memory, artifacts, and skills are now destinations for content | **Partly confirmed.** Memory doc splits CLAUDE.md (you write instructions) from auto memory (Claude writes learnings), and routes multi-step procedures and part-of-codebase content to skills or path-scoped rules. Artifacts are not named as a context destination in any page fetched. |
| S5 | Absolute rules give way to judgement | **Confirmed.** Fable 5 guide: "Instruction-following is improved enough that you can steer most behaviors with a brief instruction rather than enumerating each behavior by name," and "Skills developed for prior models are often too prescriptive for Claude Fable 5 and can degrade output quality. Review and consider removing older instructions if default performance is better." |
| S6 | Examples constrain; design expressive interfaces instead | **Split.** No page says examples now harm. Prompting best practices still recommend examples for format, tone, and structure. The Fable 5 guide's *brevity-instruction-over-enumeration* pattern is the confirmed half. The post's interface-design half is `OPINION`-tier — plausible, unsupported. |
| S7 | Progressive disclosure — file trees, on-demand loading | **Confirmed.** Best practices: "CLAUDE.md is loaded every session, so only include things that apply broadly. For domain knowledge or workflows that are only relevant sometimes, use skills instead." Memory doc: target under 200 lines per `CLAUDE.md`; path-scoped rules load only on matching files; `@path` imports organize but do **not** reduce context because imported files load at launch. Skills doc: "a skill's body loads only when it's used, so long reference material costs almost nothing until you need it." |
| S8 | Instructions belong at the definition of the thing they govern | **Unconfirmed as stated.** No page states the placement rule. Adjacent official guidance: hooks for what must happen every time (best practices, memory doc), `--append-system-prompt` for system-prompt-level instructions. `OPINION`-tier. |
| S9 | Auto-memory replaces `#`-hotkey writes | **Confirmed with correction.** Memory doc: auto memory is on by default, stored at `~/.claude/projects/<project>/memory/`, `MEMORY.md` index loaded per session capped at 200 lines or 25KB, topic files read on demand. The post's framing understates the split: CLAUDE.md is still *yours* for instructions; auto memory is Claude's for learnings. Asking Claude to remember something writes to auto memory, not `CLAUDE.md`. |
| S10 | Rubrics driving verifier agents via dynamic workflows | **Confirmed as a mechanism.** Workflows doc: a workflow "can have independent agents adversarially review each other's findings before they're reported, or draft a plan from several angles and weigh them against each other." Bundled `/deep-research` votes on claims and filters those that fail cross-checking. Best practices: a fresh-context reviewer subagent "sees only the diff and the criteria you give it." The word "rubric" appears in no fetched page — the mechanism is official, the term is the post's. |
| S10 | HTML artifacts as references | **Unconfirmed.** No fetched page names artifacts as a reference format for plans or specs. `OPINION`-tier. |
| S11 | System prompt is product context; harness authors invest there | **Confirmed indirectly.** `--append-system-prompt` is documented as the system-prompt-level path and is noted as better suited to scripts and automation than interactive use. |
| S12 | CLAUDE.md lightweight, gotcha-dense, no obviousness | **Confirmed verbatim.** Best practices include/exclude table: include bash commands Claude can't guess, style rules differing from defaults, testing instructions, repo etiquette, architectural decisions, environment quirks, "common gotchas or non-obvious behaviors"; exclude anything Claude can figure out by reading code, standard conventions it knows, detailed API docs, frequently-changing information, long explanations, file-by-file descriptions, self-evident practices. Plus the line test: "Would removing this cause Claude to make mistakes? If not, cut it." |
| S13 | Skills are lightweight guides; stay constrained only in important areas | **Half confirmed.** The de-prescription half is the Fable 5 guide's. The "except in highly important areas" carve-out appears in no fetched page — `OPINION`-tier, and it is the load-bearing calibration knob. |
| S14 | Prefer code references; HTML mockup beats a screenshot | **Partly confirmed.** Best practices, "Provide rich content": reference files with `@`, paste images, give URLs, pipe data. It recommends screenshots for UI verification rather than ranking them below code. The ranking is the post's. |
| S15 | `claude doctor` automates simplification; the Fable field guide covers model-specific prompting | **Confirmed.** Both exist; the field guide is the Fable 5 prompting page cited above. |

## Official material the source omits, relevant to this work

- **`InstructionsLoaded` hook** — "log exactly which instruction files are loaded, when they load,
  and why." A deterministic enumeration of the live instruction surface, better than walking the
  filesystem and guessing. Candidate mechanism for the runbook's inventory phase.
- **`/context`** — confirms which memory files actually loaded in a session.
- **`claudeMdExcludes`** — glob-based exclusion of ancestor `CLAUDE.md` files, mergeable across
  settings layers. A remediation option no incumbent proposes.
- **Auto-memory index limits** — `MEMORY.md` is capped at 200 lines / 25KB on load; Claude Code
  errors and tells Claude to rewrite the index when it exceeds them. An auditable surface.
- **Reasoning-echo refusal risk** — show-your-thinking instructions can trigger the
  `reasoning_extraction` refusal on Fable 5. Already check I10.
- **Effort as a separate control** — the Fable 5 guide treats effort as the primary
  intelligence/latency/cost trade-off, orthogonal to instruction content.
- **`@path` imports do not save context.** Imported files load at launch. A "split it into imports"
  remediation is a progressive-disclosure *anti-fix* — only skills and path-scoped rules defer load.
  Any detector proposing a split must propose the right destination.

## Phase 1 sweep — what the eleven pages settled

### `/doctor` presence is configurable, exactly as assumed

Skills doc, "Bundled skills": `disableBundledSkills` "disables every bundled skill except `/doctor`",
and `/doctor` "stays typable when `disableBundledSkills` is on, in Claude Code v2.1.205 and later. To
hide it, set the `DISABLE_DOCTOR_COMMAND` environment variable or a `skillOverrides` entry of
`"doctor": "off"`. Before v2.1.205, `/doctor` was a built-in command rather than a bundled skill."
The prerequisite check is therefore three-part: version floor, environment variable, and
`skillOverrides`.

### `skillOverrides` does not reach plugin skills

Skills doc: "Plugin skills are not affected by `skillOverrides`. Manage those through `/plugin`
instead." This bounds any remediation that proposes hiding a noisy skill from the model: for the
surface this pass audits — plugin skills — the visibility lever is the plugin's own enablement, not a
settings key. The `disable-model-invocation: true` frontmatter field remains available to the skill
author.

### The compaction table is the authority for "which destination survives"

Context-window doc, "What survives compaction":

| Mechanism | After compaction |
|---|---|
| System prompt and output style | Unchanged; not part of message history |
| Project-root `CLAUDE.md` and unscoped rules | Re-injected from disk |
| Auto memory | Re-injected from disk |
| Rules with `paths:` frontmatter | Lost until a matching file is read again |
| Nested `CLAUDE.md` in subdirectories | Lost until a file in that subdirectory is read again |
| Invoked skill bodies | Re-injected, capped at 5,000 tokens per skill and 25,000 tokens total; oldest dropped first |
| Hooks | Not applicable; hooks run as code, not context |

This makes the progressive-disclosure recommendation directional rather than free: moving content out
of root `CLAUDE.md` into a path-scoped rule or a nested file trades always-loaded cost for
*post-compaction absence*. A detector that recommends the move without naming that trade is
recommending a silent behavior change in long sessions.

### Skill content persists for the session, and re-invocation is not a reload

Skills doc, "Skill content lifecycle": rendered `SKILL.md` "enters the conversation as a single
message and stays there for the rest of the session"; Claude Code "does not re-read the skill file on
later turns, so write guidance that should apply throughout a task as standing instructions rather
than one-time steps." Re-invocation with identical rendered content appends a short already-loaded
note instead of a second copy. Both facts constrain how a skill body should be written, and both are
checkable.

### Subagents inherit the full `CLAUDE.md` hierarchy; Explore and Plan do not

Sub-agents doc, "What loads at startup": a non-fork subagent's initial context contains "every level
of the `CLAUDE.md` hierarchy the main conversation loads, including `~/.claude/CLAUDE.md`, project
rules, `CLAUDE.local.md`, and managed policy files. The built-in Explore and Plan agents skip this."
And: "Explore and Plan are the only subagents that omit `CLAUDE.md` and git status. There is no
frontmatter field or per-agent setting to change which agents skip them." The main conversation's
auto memory is *not* loaded into a subagent; a subagent gets persistent memory only through the
`memory` field, which is itself gated on auto memory being enabled.

### The native diagnostic surface is larger than `/doctor`

Debug-your-config enumerates `/context`, `/memory`, `/skills`, `/hooks`, `/mcp`, `/permissions`,
`/doctor`, `/debug [issue]`, and `/status`, plus `claude doctor` for read-only terminal diagnostics,
`claude --safe-mode` to disable every customization, and `CLAUDE_CONFIG_DIR` pointed at an empty
directory for a clean-room comparison. It also states the failure this pass exists to catch:
"Adherence drops when an instruction is vague enough to interpret multiple ways, when two files give
conflicting direction, or when the file has grown long enough that individual rules get less
attention." The native-first inventory any detector must clear is this list, not `/doctor` alone.

### `claudeMdExcludes` has a hard floor and a merge rule

Large-codebases doc: "Managed policy CLAUDE.md files cannot be excluded, so organization-wide
instructions always apply." The setting is available at user, project, local, or managed scope, and
"Arrays merge across scopes, so a team can set project-level defaults while individuals add local
overrides." It is also "static, not a per-task switch" — the doc's own alternative for task-scoped
focus is starting Claude from the package directory.

### Startup scope depends on the launch directory

Large-codebases doc: starting from the repository root loads the root `CLAUDE.md` only, with
subdirectory files loading on demand; starting from a subdirectory loads "that directory's plus every
ancestor's". Project settings do not inherit the same way: "a `.claude/settings.json` at the
repository root applies only when you start from the root." Any inventory that walks the filesystem
and calls the result "the loaded surface" is wrong without knowing the launch directory —
`/context` is the only ground truth.

### Deferred tool loading is owned by the MCP page, not `tools-reference`

`tools-reference` carries only the `ToolSearch` row: "Searches for and loads deferred tools when tool
search is enabled." The mechanism lives at `mcp#scale-with-mcp-tool-search`: "Tool search is enabled
by default. MCP tools are deferred rather than loaded into context upfront... Only tool names and
server instructions load at session start." `ENABLE_TOOL_SEARCH=auto` loads schemas upfront "when
they fit within 10% of the context window and defer only the overflow." The §S7 progressive-
disclosure claim is therefore confirmed for tools as well as skills, and the citation must point at
`mcp`, not `tools-reference`.

### `userConfig` documents a `default` the substitution path does not honor

Plugins-reference documents `default` as the "Value used when the user provides nothing", values
substituted as `${user_config.KEY}` and exported to hook processes as `CLAUDE_PLUGIN_OPTION_<KEY>`,
and non-sensitive values stored under `pluginConfigs[<plugin-id>].options` in **user** settings only
as of v2.1.207. This repository already established empirically (commit `f40e9944`, issue #1019) that
an unset-but-defaulted `${user_config.*}` token drops the whole hook entry rather than resolving to
the declared default. Documentation and behavior diverge; the behavior is the constraint, and any
check that reads a plugin's declared defaults must not assume they are live.

### The plugin path variables are stable, and one of them is not

`${CLAUDE_PLUGIN_ROOT}` is the plugin's installation directory and "changes when the plugin updates";
`${CLAUDE_PLUGIN_DATA}` resolves to `~/.claude/plugins/data/{id}/` and "survives plugin updates,
created on first reference". A criteria catalog materialized under `${CLAUDE_PLUGIN_ROOT}/reference/`
is versioned with the plugin, which is what the shape-4 seam assumes.

## Pages the plan's list missed

The eleven-slug list was built from the source article's claims. Walking `llms.txt` surfaced five
more pages whose subject is an instruction or configuration surface, three of which are load-bearing
enough that a detector designed without them would be wrong.

- <https://code.claude.com/docs/en/features-overview> — **the most consequential omission.** Its
  "Compare similar features" section is the official routing guidance between `CLAUDE.md`,
  `.claude/rules/`, skills, hooks, subagents, agent teams, and MCP, including a three-way
  `CLAUDE.md` vs rules vs skills table and the rule "Keep CLAUDE.md under 200 lines. If it's growing,
  move reference content to skills or split into `.claude/rules/` files." It also states the
  enforcement boundary verbatim: "An instruction like 'never edit `.env`' in CLAUDE.md or a skill is a
  request, not a guarantee. A `PreToolUse` hook that blocks the edit is enforcement." D7's premise —
  that content should be routed to the right memory primitive — is *official policy on this page*,
  not a gap. Phase 2.5 must weigh whether D7 detects anything the page does not already prescribe.
- <https://code.claude.com/docs/en/output-styles> — an instruction surface the pass had not
  enumerated. Output styles "directly modify Claude Code's system prompt", are appended at the end of
  it, and by default *remove* Claude Code's built-in software-engineering instructions unless
  `keep-coding-instructions: true`. Plugins can ship them in an `output-styles/` directory, and
  `force-for-plugin` lets a plugin override the user's `outputStyle` selection. That is a plugin
  capable of silently replacing the operator's system prompt — a D1 conflict source, and one the
  filesystem-walk inventory would miss.
- <https://code.claude.com/docs/en/mcp> — owns tool search, per the section above.
- <https://code.claude.com/docs/en/plugins> — the component-directory table and the manifest field
  set; already in the list, recorded here because `output-styles/` is absent from it and appears only
  on the output-styles page.
- <https://code.claude.com/docs/en/features-overview#understand-how-features-layer> — the official
  precedence statement per surface: `CLAUDE.md` files are additive across levels, skills and
  subagents override by name, MCP servers override by name, hooks merge. D1 compares surfaces that
  layer by four different rules, and the doc's own answer to a `CLAUDE.md` conflict is that "Claude
  uses judgment to reconcile them, with more specific instructions typically taking precedence."

## `llms.txt` walk — falsifiability check

`https://code.claude.com/docs/llms.txt` lists 172 pages. Every page whose subject is an instruction,
memory, or configuration surface is accounted for below. Fetched means read in this topic's sessions.

**Fetched:** `memory`, `commands`, `best-practices`, `workflows`, `skills`, `plugins`,
`plugins-reference`, `hooks`, `sub-agents`, `tools-reference`, `claude-directory`,
`debug-your-config`, `large-codebases`, `settings`, `context-window`, `features-overview`,
`output-styles`, `mcp`.

**In scope, deferred with a trigger:**

- `env-vars` — owns `DISABLE_DOCTOR_COMMAND`, `CLAUDE_CODE_DISABLE_AUTO_MEMORY`,
  `ENABLE_TOOL_SEARCH`, `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD`. Each was read through the
  page that uses it. Fetch before D1 or D7 asserts an environment-variable default.
- `cli-reference` — owns `--append-system-prompt`, `--safe-mode`, `--add-dir`, `--plugin-dir`. Same
  trigger: fetch before a check asserts a flag's behavior.
- `hooks-guide` — the authoring companion to the `hooks` reference. Fetch when Phase 6 rules on a
  hook-based detector.
- `server-managed-settings` and `admin-setup` — the enterprise distribution path for the managed
  tier D1 carries read-only. Fetch before Phase 10 inventories the managed scope.
- `permissions` and `permission-modes` — enforcement, not instruction. In scope only because
  `debug-your-config` draws the boundary between them and `CLAUDE.md`; that boundary is already
  captured above.
- `how-claude-code-works` — owns the auto-compaction reference the skills page links to. Fetch if a
  detector asserts compaction thresholds beyond the table above.
- `agent-teams`, `agents`, `agent-view` — subagent surfaces beyond the single-session model. Fetch
  when Phase 6 rules on whether the sweep runs as a team.
- `prompt-caching` — owns what an output-style change costs. Fetch only if a remediation proposes
  changing `outputStyle`.
- `troubleshooting` and `glossary` — already quoted second-hand through `memory` and
  `debug-your-config`.
- `routines`, `scheduled-tasks`, `goal`, `channels`, `statusline` — configuration surfaces that carry
  prompt text. Out of the *instruction-conflict* scope as drafted, but they are places instruction
  text can live; record as a D1 scope question for Phase 2.5 rather than a silent exclusion.
- `agent-sdk/modifying-system-prompts`, `agent-sdk/skills`, `agent-sdk/subagents`,
  `agent-sdk/slash-commands`, `agent-sdk/tool-search` — the SDK mirrors of surfaces already fetched.
  In scope only if the pass ever targets SDK consumers; no trigger today.

**Out of scope, with reason:**

- Installation, platform, and deployment pages (`setup`, `troubleshoot-install`, `devcontainer`,
  `desktop*`, `vs-code`, `jetbrains`, `mobile`, `slack`, `terminal-config`, `network-config`,
  `corporate-launcher`, `claude-apps-gateway*`, `llm-gateway*`, `amazon-bedrock`,
  `google-vertex-ai`, `microsoft-foundry`, `claude-platform-on-aws`, `github-actions`,
  `github-enterprise-server`, `gitlab-ci-cd`, `headless`, `claude-code-on-the-web`,
  `web-quickstart`) — they configure where Claude Code runs, not what instructions it loads.
- Billing, telemetry, and policy pages (`costs`, `analytics`, `monitoring-usage`, `data-usage`,
  `legal-and-compliance`, `zero-data-retention`, `security`, `feature-availability`,
  `authentication`) — no instruction surface.
- Feature pages with no instruction surface (`checkpointing`, `chrome`, `computer-use`,
  `voice-dictation`, `fullscreen`, `keybindings`, `deep-links`, `remote-control`, `sessions`,
  `interactive-mode`, `fast-mode`, `sandboxing`, `sandbox-environments`, `worktrees`,
  `code-review`, `claude-security`, `security-guidance`, `ultraplan`, `ultrareview`, `artifacts`).
  `artifacts` is named here deliberately: §S10's HTML-artifact claim remains `OPINION`-tier because
  this page documents publishing session output, not a reference format for plans or specs.
- Onboarding and marketing pages (`overview`, `quickstart`, `champion-kit`, `communications-kit`,
  `prompt-library`, `accessibility`, `platforms`, `third-party-integrations`, `errors`,
  `changelog`, `whats-new/*`) — no normative instruction guidance.
- Plugin distribution pages (`discover-plugins`, `plugin-marketplaces`, `plugin-dependencies`,
  `plugin-hints`, `plugin-relevance`, `managed-mcp`, `mcp-quickstart`) — distribution and discovery,
  not instruction content. In scope for Phase 11's publish gate, not for the detectors.
- The remaining `agent-sdk/*` pages — SDK-only surfaces with no Claude Code instruction analogue.
