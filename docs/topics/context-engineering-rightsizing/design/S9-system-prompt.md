# S9 — Applying this to your context → System Prompt

Scope: the one-line framing that opens "Applying this to your context", plus the **System Prompt**
block. All doc citations were fetched this session (2026-07-24) from `code.claude.com/docs`.

## Claims

1. **Framing.** > "Pulling this all together, what does this look like when you assemble your
   context?"
   The section asserts that context is *assembled* from a definite set of surfaces, and that the
   four blocks that follow (System Prompt, CLAUDE.md, Skills, References) are that set.

2. **System prompt is product-bound.** > "A system prompt is heavily tied to the product context."

3. **System prompt content = product identity + current activity.** > "It tells Claude what product
   it's operating in and what it's doing."

4. **Claude Code users won't modify it.** > "For Claude Code, you will likely never modify this"

5. **Harness authors should invest heavily in it.** > "but if you are building your own agent
   harness, this is where you should spend a lot of time."

## Evidence status

**Claim 1 — PARTIAL.**
`https://code.claude.com/docs/en/context-window` enumerates startup context and it is *broader* than
the article's four blocks: "System prompt" (`desc: 'Core instructions for behavior, tool use, and
response formatting. Always loaded first. You never see it.'`), "Auto memory (MEMORY.md)",
"Environment info", "MCP tools (deferred)", "Skill descriptions", `~/.claude/CLAUDE.md`, "Project
CLAUDE.md", then the user prompt; rules (`Rule: api-conventions.md`) and hooks fire mid-session. The
same page: "Before you type anything: CLAUDE.md, auto memory, MCP tool names, and skill descriptions
all load into context. Your own setup may add more here, like an [output style] or text from
[`--append-system-prompt`], which both go into the system prompt the same way." The article's
four-block enumeration omits auto memory, environment info, tool schemas, rules, and hooks. It is a
useful authoring taxonomy, not the documented load model.

**Claim 2 — CONFIRMED.**
`https://code.claude.com/docs/en/agent-sdk/modifying-system-prompts`: "Start from the `claude_code`
preset for CLI or IDE-like coding tools where a human watches and steers the work. Write your own
prompt for agents with a different surface, identity, or permission model." And: "The deciding
factor is how closely your agent resembles Claude Code: a coding agent operating in a repository,
with a human watching streaming output and steering the work. The further your product is from that,
the more you'll want to write your own prompt." The page then names the four product-context axes
verbatim — "Different surface", "Different identity", "Different permission model", "Non-coding
tasks". This is the article's claim stated as official design guidance.

**Claim 3 — CONFIRMED.**
Same page, on what the preset contains: "the full system prompt that the Claude Code CLI uses, with
tool usage instructions, code style and formatting guidelines, response tone and verbosity rules,
security and safety instructions, and context about the working directory and environment."
`context-window` adds that environment info ("Working directory, platform, shell, OS version, and
whether this is a git repo") and the git block live *in* the system prompt. "What product it's
operating in and what it's doing" maps cleanly onto both halves.

**Claim 4 — SPLIT: CONTRADICTED as a capability statement, UNBACKED as a frequency statement.**
Contradicted: `https://code.claude.com/docs/en/output-styles` — "Output styles directly modify
Claude Code's system prompt"; "Custom output styles leave out Claude Code's built-in software
engineering instructions, such as how to scope changes, write comments, and verify work, unless
`keep-coding-instructions` is set to `true`"; `force-for-plugin` — "Plugin output styles only: apply
this style automatically whenever the plugin is enabled, without requiring users to select it.
Overrides the user's `outputStyle` setting." Also `--append-system-prompt` (`memory`:
"For instructions you want at the system prompt level, use `--append-system-prompt`") and, for
subagents, `--append-subagent-system-prompt`, which "appends the text you provide to the end of every
subagent's system prompt, including nested subagents" (`sub-agents`, requires v2.1.205+).
So a Claude Code user can append to, extend, or *remove* built-in system-prompt content today, and a
plugin can do it to them without their selecting it.
Unbacked: no fetched page says how often users actually do this. `context-window` says only "You
never see it" — never *see*, not never *modify*. I looked at `output-styles`, `memory`,
`context-window`, `settings`-linked material, and `agent-sdk/modifying-system-prompts`.

**Claim 5 — CONFIRMED.**
`agent-sdk/modifying-system-prompts` is entirely a harness-author page and its decision table assigns
escalating ownership: preset → preset + `append` ("Nothing is removed, so this is the lowest-risk
customization") → custom string ("Only what you write. You take responsibility for replacing the tool
guidance and safety instructions your agent still needs"). "Built-in safety: Must be added",
"Environment context: Must be provided", "Default tools: Lost (unless included)" in the comparison
table. That is the documented form of "spend a lot of time".

## Local analogues — what functions as a system prompt in this repo

Verified surface-by-surface. Counts are from commands run in
`D:/repos/.worktrees/context-engineering-rightsizing`.

| Surface | Present here | Loading semantics (doc-verified) |
| :--- | :--- | :--- |
| Plugin agent definitions `plugins/*/agents/*.md` | **7** | Body **is** the whole system prompt on the delegation path |
| Same files, agent-teams path | same 7 | Body is **appended** to the teammate's system prompt |
| Output styles (`output-styles/`) | **0** | Would modify the main system prompt directly |
| Prompt-injecting hooks (`UserPromptSubmit`) | **0** | — |
| `SessionStart` hooks | **1**, injects nothing | Context-only event; this one emits no stdout |
| Slash commands (`commands/*.md`) | **0** | — |
| Skills with `context: fork` | **1** | Fork inherits the parent's **full** system prompt |
| `initialPrompt` (main-session agent) | **0** | Only field that makes a definition a product-level prompt |

**1. Plugin agent definitions — the primary analogue.**
`find plugins -path '*/agents/*' -name '*.md' | wc -l` → **7**, in two plugins:

- `plugins/plugin-quality/agents/auditor.md` (586 body words)
- `plugins/review/agents/architecture-guardian.md` (588)
- `plugins/review/agents/ci-log-auditor.md` (778)
- `plugins/review/agents/code-reviewer.md` (850)
- `plugins/review/agents/doc-drift-detector.md` (628)
- `plugins/review/agents/ecosystem-specialist.md` (696)
- `plugins/review/agents/security-reviewer.md` (1000)

`sub-agents`: "The frontmatter defines the subagent's metadata and configuration. The body becomes
the system prompt that guides the subagent's behavior. Subagents receive only this system prompt plus
basic environment details like the working directory, not the full Claude Code system prompt." And
under *What loads at startup*: "**System prompt**: the agent's own prompt plus environment details
that Claude Code appends, not the full Claude Code system prompt."

So the article's harness-author advice ("spend a lot of time there") applies to exactly these seven
files and nothing else in the repo. Each is the complete standing instruction set for a scoped
execution.

**2. What else reaches those seven agents — the part the bodies must not duplicate.**
`sub-agents` *What loads at startup* also lists, for a non-fork subagent: "**CLAUDE.md files**: every
level of the CLAUDE.md hierarchy the main conversation loads, including `~/.claude/CLAUDE.md`,
project rules, `CLAUDE.local.md`, and managed policy files. The built-in Explore and Plan agents skip
this." Plus git status, preloaded `skills`, the delegation task message, and (v2.1.206+) a sibling
roster. Never reaching them: output style, the main conversation's auto memory, conversation history.

**3. The same seven files load differently as agent-team teammates.**
`agent-teams`: "The teammate honors that definition's `tools` allowlist and `model`, and the
definition's body is **appended to the teammate's system prompt as additional instructions rather
than replacing it**." Also: "The `skills` and `mcpServers` frontmatter fields in a subagent
definition are not applied when that definition runs as a teammate." A teammate "loads the same
project context as a regular session: CLAUDE.md, MCP servers, and skills." One artifact, two loading
semantics — this is the sharpest technical fact in the section, and no repo file records it.

**4. Absences, stated with where I looked.**

- Output styles: `find . -type d -name 'output-styles' -not -path './node_modules/*'` → no results;
  `find . -iname '*output*style*'` → no results. Zero shipped. `.claude/settings.json` contains only
  `{"worktree":{"baseRef":"head"}}` — no `outputStyle`. The repo therefore does not use
  `force-for-plugin`, which is the one documented way a plugin can rewrite a consumer's system prompt
  without their consent.
- Prompt-injecting hooks: enumerated every event across all 15 `plugins/*/hooks/hooks.json`. Events
  present: `PostToolUse` (11), `PreToolUse` (2), `PreCompact`, `Notification`, `StopFailure`,
  `SessionStart` (1). **No `UserPromptSubmit`.**
- The single `SessionStart` hook — `plugins/session-flow/hooks/hooks.json` → `observer-arm.sh` — is
  not a context-injection surface. It reads stdin, arms a detached observer, redirects all output to
  `/dev/null`, and `exit 0`s; it emits no `additionalContext` and no `systemMessage`, and it no-ops
  unless `CLAUDE_PLUGIN_OPTION_OBSERVER_ENABLED=true`. Treat it as a side-effect hook, not a
  standing-instruction surface.
- Slash commands: `find plugins -path '*/commands/*' -name '*.md' | wc -l` → **0**. All 181 skills,
  no commands. A command body is prompt-shaped (injected on invocation) rather than
  standing-instruction-shaped, so I exclude it from S9 by definition as well as by absence.
- `initialPrompt`: `grep -rn "initialPrompt" plugins/` → no matches. No definition here is intended
  to run as the main session agent, so nothing in this repo occupies the product-level system-prompt
  slot the article's claims 2–4 are about.
- `skills:` preload frontmatter: not set on any of the 7.
- `hooks` / `mcpServers` / `permissionMode` frontmatter: not set on any of the 7 — correct, since
  `sub-agents` states these "are ignored when loading agents from a plugin".

**5. The fork exception.**
`plugins/discovery/skills/explore-deep/SKILL.md:7` sets `context: fork`. Per `sub-agents` and
`output-styles`, a fork "inherits the parent's full system prompt" and skips both subagent tool
filters. This is the only execution context originating in this repo that runs under the *main*
system prompt rather than a scoped one. Every criterion below must exempt it.

## Organization-deployed instruction surfaces — the bound on remediation

The brief asked whether a managed-policy surface exists and where it sits. It does, on **three**
independent axes, and all three outrank anything this repo ships.

1. **Managed subagents.** `sub-agents` scope table, verbatim priority order: Managed settings —
   "1 (highest)"; `--agents` CLI flag — 2; `.claude/agents/` — 3; `~/.claude/agents/` — 4;
   **"Plugin's `agents/` directory | Where plugin is enabled | 5 (lowest)"**. And: "Managed
   subagents are deployed by organization administrators. Place markdown files in `.claude/agents/`
   inside the managed settings directory… Managed definitions take precedence over project and user
   subagents with the same name." An org admin can shadow every one of this repo's seven agents by
   `name` and the plugin copy never loads.
2. **Managed CLAUDE.md.** `memory`: managed policy at `/Library/Application Support/ClaudeCode/CLAUDE.md`
   (macOS), `/etc/claude-code/CLAUDE.md` (Linux/WSL), `C:\Program Files\ClaudeCode\CLAUDE.md`
   (Windows); or inline via the `claudeMd` key, "honored" in "managed and policy settings only" —
   "Setting `claudeMd` in user, project, or local settings has no effect." Precedence: "Loads before
   user and project CLAUDE.md." And: "Managed policy CLAUDE.md files cannot be excluded. This ensures
   organization-wide instructions always apply regardless of individual settings." Since CLAUDE.md
   loads into every custom subagent's context, managed policy text reaches all seven agents here.
3. **Managed output styles** at `.claude/output-styles` inside the managed settings directory, and
   the operator-side `--append-subagent-system-prompt`, which appends to every subagent prompt
   including nested ones.

**Bound:** no remediation this repo emits may assume a plugin agent definition is authoritative. A
definition here is (a) shadowable by `name` at priority 1, (b) preceded in context by managed
CLAUDE.md that cannot be excluded, and (c) suffixable by an operator flag. Remediations must be
written to remain correct under all three, and must never instruct an agent to override
organization-level guidance.

## Criteria

Each rule names its surface, the pass/fail observable, and at least one case it must not flag.
`AGENT-BODY` = the markdown body of a `plugins/*/agents/*.md` file.

**S9-R1 — Agent body must not re-fetch what already loaded.** *(highest leverage)*
Surface: AGENT-BODY.
Observable: the body instructs the agent to go read `CLAUDE.md`, `CLAUDE.local.md`, `.claude/rules/`,
`~/.claude/rules/`, or "project rules". These are already in the subagent's startup context per
`sub-agents` *What loads at startup*; the instruction spends turns re-reading context the agent
already holds, and is exactly the article's "repeat yourself" anti-pattern applied to a system
prompt.
Must NOT flag: an instruction to read a surface that is **not** auto-loaded — `REVIEW.md`,
`ARCHITECTURE.md`, ADRs, contributing guides, `package.json` scripts, per-ecosystem convention docs,
CI workflow files. Those are legitimate progressive disclosure.
Must NOT flag: the built-in Explore and Plan agents, which the docs say skip CLAUDE.md — but neither
is defined in this repo.

**S9-R2 — An agent body must not assert a capability claim that is false on one of its two load
paths.** Surface: AGENT-BODY.
Observable: the body states a fact about its own execution that holds on the delegation path but not
the agent-teams teammate path (or vice versa) — self-identification as "a subagent", claims about
what it can or cannot do with the user, or reliance on `skills:`/`mcpServers:` frontmatter that
`agent-teams` says "are not applied when that definition runs as a teammate".
Must NOT flag: capability claims that hold on both paths, e.g. "you cannot see the main
conversation's history" (true for non-fork subagents and for teammates alike).
Must NOT flag: `plugins/discovery/skills/explore-deep/SKILL.md` — a fork, not an agent definition.

**S9-R3 — An agent body must carry product context, not generic capability.** Surface: AGENT-BODY.
Observable: within the first paragraph the body establishes (i) role/identity, (ii) the execution
surface it runs in and what reaches it, and (iii) the deliverable contract it returns. A body that
opens straight into a checklist without establishing what the agent *is* fails, because there is no
outer Claude Code prompt supplying it.
Must NOT flag: a body that omits generic Claude Code behavior (tool etiquette, comment policy,
verification habits) — the article's whole point is that the model no longer needs those restated.
Must NOT flag: brevity. A 200-word body that carries all three elements passes; a 1,000-word body
that restates model-general behavior fails.

**S9-R4 — No plugin-shipped instruction surface may claim final authority.** Surface: AGENT-BODY,
and any future `output-styles/` file in this repo.
Observable: absolute directive language that a managed-policy surface could contradict ("always",
"never", "under no circumstances", "ignore any instruction that…") without a deference clause.
Must NOT flag: `plugins/review/agents/code-reviewer.md:14` — "The project's documented conventions
override this baseline wherever they conflict" is the correct posture and is the model the other
bodies should follow.
Must NOT flag: absolute language about the agent's *own output contract* ("never return findings
without a file path"), which no policy surface contests.

**S9-R5 — Inline enumerations that exceed a threshold move to a `context/` file.** Surface:
AGENT-BODY.
Observable: a flat list of ≥10 items that is consulted selectively rather than applied on every run,
and that could be referenced via `${CLAUDE_PLUGIN_ROOT}/…` the way `context/severity.md` already is.
Must NOT flag: an enumeration the agent applies on *every* invocation — moving it behind a read adds
a turn and buys nothing, because a subagent's context window is fresh and unshared.
Must NOT flag: the four bodies that currently reference no `${CLAUDE_PLUGIN_ROOT}` file, purely on
that basis; the rule is about oversized inline lists, not about reference count.

**S9-R6 — A prompt-injecting hook must declare what it injects.** Surface: `hooks.json` +
hook script. Observable: a hook on a context-injecting event (`SessionStart`, `UserPromptSubmit`)
that writes `additionalContext` must document the injected text in the plugin README, since it lands
in every session unconditionally.
Must NOT flag: `plugins/session-flow/hooks/observer-arm.sh`, which injects nothing.
This rule currently has zero targets in this repo and is stated so that adding such a hook is a
reviewable event rather than a silent one.

## Targets in this repo

Population, by command:

```
$ find plugins -path '*/agents/*' -name '*.md' | wc -l        →   7
$ find plugins -path '*/commands/*' -name '*.md' | wc -l      →   0
$ find . -type d -name 'output-styles' -not -path './node_modules/*'  →  (none)
$ ls plugins/*/skills/*/SKILL.md | wc -l                      → 181
$ ls plugins | wc -l                                          →  60
$ grep -rn '^context:' plugins/*/skills/*/SKILL.md            →   1
$ grep -rn 'initialPrompt' plugins/                           →   0
```

**S9-R1 — 5 of 7 bodies name an auto-loaded surface; 4 are true hits, 1 is the designed exception:**

- `plugins/review/agents/architecture-guardian.md:14` — "Read the project's own architecture
  reference first — architecture docs, ADRs, layer rules, module conventions (`CLAUDE.md`,
  `REVIEW.md`, project rules, …)". `CLAUDE.md` and "project rules" are already loaded; ADRs,
  `REVIEW.md`, `ARCHITECTURE.md` are not. Fix is surgical: drop the two auto-loaded names.
- `plugins/review/agents/code-reviewer.md:14` — "Check for a `CLAUDE.md`, project rules, a
  `REVIEW.md` or review-criteria docs, and contributing guides." Same split.
- `plugins/review/agents/doc-drift-detector.md:16` — "Cross-reference the project's instruction
  surfaces (`CLAUDE.md`, project rules, `AGENTS.md`, contributing guides, per-directory READMEs)".
  **Does not flag**: this agent's job is auditing those files *as artifacts*, so it must read them
  from disk even though their content is in context. This is the rule's designed exception and shows
  R1 needs the "as subject matter vs. as instruction" distinction written into it.
- `plugins/review/agents/ecosystem-specialist.md:23` — "Read `CLAUDE.md`, project rules, contributing
  docs, `package.json` scripts, `Makefile`/`justfile` targets, and CI workflow files".
- `plugins/review/agents/security-reviewer.md:14` — "a security review guide, threat-model doc,
  `REVIEW.md`, or security section of the project rules". Only "project rules" is auto-loaded.

**S9-R2 hits — 5 of 7**, each carrying the sentence "You are a subagent and cannot ask the user
questions":
`plugins/review/agents/architecture-guardian.md:54`,
`plugins/review/agents/code-reviewer.md:66`,
`plugins/review/agents/doc-drift-detector.md:99`,
`plugins/review/agents/ecosystem-specialist.md:52`,
`plugins/review/agents/security-reviewer.md:108`.
It is doc-correct on the
delegation path (`sub-agents` lists `AskUserQuestion` among the tools removed from every subagent)
and doc-wrong on the teammate path, where `agent-teams` says "Each teammate is a full, independent
Claude Code session. You can message any teammate directly". Not present in `ci-log-auditor.md` or
`plugin-quality/agents/auditor.md`.

**S9-R3:** all 7 pass the opener test — every body begins "You are a …" and states role plus scope.
`plugin-quality/agents/auditor.md` additionally states its dispatch contract. No current failures;
the rule is a floor for new definitions.

**S9-R4:** `code-reviewer.md:14` and `security-reviewer.md:14` carry explicit deference clauses.
No body currently asserts authority over organization-level guidance. No hits.

**S9-R5 candidate — 1:** `plugins/review/agents/code-reviewer.md:43-57`, a 12-item Fowler
design-smell catalog inlined in the body. It is described as "advisory heuristics" consulted against
a diff, i.e. selective. `code-reviewer.md:62` already demonstrates the pattern for moving it out
(`${CLAUDE_PLUGIN_ROOT}/context/severity.md`). Contested — see Conflicts.

**S9-R6:** zero targets. `plugins/session-flow/hooks/hooks.json` is the only `SessionStart` hook and
injects nothing.

## Conflicts and ambiguity

**A. The article's own advice does not reach this repo's main lever, and reaches a lever the repo
does not pull.** Claims 2–4 are about a *product-level* system prompt. This repo ships zero surfaces
in that slot: no output styles, no `initialPrompt`, no `force-for-plugin`, no prompt hooks. What it
does ship — seven scoped subagent prompts — is governed by claim 5's harness-author advice, not by
claim 4's "you'll never modify this". Applying S9 here means applying only claim 5, and saying so.

**B. Claim 4 is wrong on capability and the repo could exploit exactly the mechanism that makes it
wrong.** `force-for-plugin` lets a plugin apply an output style "automatically whenever the plugin is
enabled, without requiring users to select it. Overrides the user's `outputStyle` setting." A
60-plugin marketplace shipping one such style would silently rewrite the system prompt of every
consumer who enables that plugin — including stripping their built-in coding instructions if
`keep-coding-instructions` is left at its documented `false` default. This repo does not do it. That restraint is currently accidental (no output styles exist at
all) rather than a documented position, and it is the highest-consequence unwritten decision S9
found.

**C. Progressive disclosure is weaker advice for a subagent prompt than the article implies.** The
article's rationale for progressive disclosure is standing context cost across many requests. A
subagent gets a fresh, isolated context window per invocation and does not share it with the main
conversation, so an inlined list costs one agent's window once. Moving it behind a file read adds a
guaranteed turn. S9-R5 is therefore genuinely contested for `code-reviewer.md:43-57` and I have kept
the rule narrow (selective-consultation lists only) rather than applying the article's advice
mechanically.

**D. Overlap with `claude-config:audit-instructions` — real, but not the overlap it looks like.**
`plugins/claude-config/skills/audit-instructions/SKILL.md:3` names "agent definitions, prompt-type
hooks, output styles" among the surfaces it audits, and offers an `agents` scope
(`SKILL.md:66`). But its Phase A inventory (`SKILL.md:76-88`) enumerates the **invoking consumer's**
tree — `${CLAUDE_CONFIG_DIR:-~/.claude}/agents/` and `.claude/agents/` — and explicitly excludes
"installed plugin-cache content" as upstream-owned (`SKILL.md:52-57`). This repo's own seven agent
definitions live at `plugins/*/agents/*.md`, which is neither. **A marketplace that ships an
instruction-surface auditor does not point it at the instruction surfaces it ships.** That is a gap,
not a duplication — S9's criteria should feed the existing skill's criteria catalog rather than
spawn a parallel mechanism, and the skill's inventory needs a plugin-source-tree mode.

**E. R1 has a genuine exception that a naive implementation will get wrong.**
`doc-drift-detector.md:16` must read `CLAUDE.md` from disk because auditing it *is* the job. Any
automated form of S9-R1 that matches on the filename alone produces a false positive there. The rule
must test intent (instruction retrieval vs. artifact inspection), which is not a grep.

**F. The teammate-path conflict (S9-R2) is unresolvable inside a single file.** One body cannot be
simultaneously "the whole system prompt" and "an appendix to a full session prompt" without either
hedging every self-description or dropping self-description entirely. Dropping it weakens the
delegation path, which is the dominant one. There is no documented way to branch on load path from
inside the definition.

**G. The article says nothing about precedence, and precedence is the fact that most constrains this
repo.** A plugin agent definition is priority 5 of 5. The article's framing ("this is where you
should spend a lot of time") is written for a harness author who owns their prompt outright. A
marketplace author owns the lowest-priority copy of a shadowable name. Nothing in this repo's docs
records that.

## Open questions for the operator

1. Should S9-R1 remediation be applied to the 4 confirmed hits now, or bundled into a
   `claude-config:audit-instructions` inventory extension so it runs repeatably?
   **RECOMMENDED: bundle.** The gap in D is worth more than four one-off edits, and the four edits
   fall out of it.
2. Does the repo want a written position that it will never ship a `force-for-plugin` output style
   (Conflict B)? **RECOMMENDED: yes**, as a one-line marketplace-level constraint. It costs nothing
   and converts an accidental restraint into a reviewable one.
3. For S9-R2, do we resolve the teammate/subagent conflict by removing the "You are a subagent and
   cannot ask the user questions" sentence from all 5 bodies, or by rewording it to a path-neutral
   form? **RECOMMENDED: reword** to "You cannot pause for user input mid-task; review under the most
   reasonable assumption and flag the ambiguity" — path-neutral, keeps the behavior, drops the false
   capability claim.
4. Is S9-R5 in or out? It is the one criterion where I think the article's advice does not clearly
   transfer (Conflict C). **RECOMMENDED: keep it, scoped to selective-consultation lists only**, and
   treat `code-reviewer.md:43-57` as a proposal requiring a measured before/after, not an auto-fix.
5. Should the two load-path semantics (delegation vs. agent-teams append) be documented in
   `plugins/review/README.md`, or is that duplication of upstream docs?
   **RECOMMENDED: a pointer, not a copy** — one line naming the agent-teams section URL, per the
   repo's pointer-not-copy posture.

## Fence events

None. I did not read, list, grep, or reference any path under `docs/topics/context-engineering-claude-5/**`,
`docs/topics/fable-field-guide-audit/**`, `.work/fable-field-guide-audit/**`, any other worktree, or
any sibling file under `sections/` (the directory did not exist until I created it for this file).

## Sources fetched this session

- <https://code.claude.com/docs/llms.txt>
- <https://code.claude.com/docs/en/sub-agents.md>
- <https://code.claude.com/docs/en/output-styles.md>
- <https://code.claude.com/docs/en/memory.md>
- <https://code.claude.com/docs/en/agent-teams.md>
- <https://code.claude.com/docs/en/agent-sdk/modifying-system-prompts.md>
- <https://code.claude.com/docs/en/context-window.md>
