# Native surfaces registry

Generated view over the native-overlap store. The block between the markers below is rendered from
`docs/native-surfaces/records.json` by
`plugins/claude-ops/skills/audit-native-overlap/scripts/overlap.py generate` and kept in sync by CI.
**Never hand-edit it.** Verdicts, evidence, and recheck triggers are edited in the store; this
file is output.

Every verdict here is a human's. Rows are recorded per overlap between a native Claude Code surface
and a component in this repository, and each one carries the observable event that obliges
re-deriving it. Availability is never asserted: an observation record says what was seen, where,
and when. See [`docs/conventions/native-references/`](conventions/native-references/README.md).

<!-- native-surfaces:start -->

## Summary

| Lane | Rows | Baked | Integration | Verdicts |
|---|---|---|---|---|
| Built-in CLI commands | 24 | 23 | route 4, suggest 20 | complementary 23, defer 1 |
| Bundled skills | 29 | 22 | route 18, suggest 9, wrap 2 | complementary 23, defer 6 |
| Bundled workflows | 1 | 1 | suggest 1 | complementary 1 |
| Plugin-backed built-ins | 2 | 1 | route 2 | complementary 2 |
| Built-in subagents | 3 | 2 | route 3 | complementary 3 |
| Built-in tools | 2 | 2 | route 2 | complementary 2 |
| Session-provided skills (observation-only) | 1 | 0 | route 1 | defer 1 |
| First-party marketplace plugins | 2 | 2 | route 2 | complementary 2 |

## Built-in CLI commands

### `auto-mode-setup` → `claude-config:draft-auto-mode-rules`

- **Verdict:** `complementary`: The native command drafts and saves autoMode.environment entries (plus optional rule tweaks); ours interviews for full allow/deny classifier rules and prints only, never writing settings. Reserved for the person to run, so ours suggests it. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation.
- **Integration:** `suggest`
- **Native surface:** `auto-mode-setup` (built-in command; markers: hidden, gated, model-invocation-disabled)
- **Our component:** `claude-config:draft-auto-mode-rules` (skill)
- **Evidence:**
  - `auto-mode-setup` present in the extraction as builtin-command
  - markers: hidden, gated, model-invocation-disabled
  - native description: Teach auto mode about your environment, plus optional rule tweaks
  - argument hint: [--request-id <uuid>] (--wizard posture=… scope=… depth=… --propose | --expect-sha256 <64-hex> --apply-file <path>)
  - invocation mode (2026-09-29, Claude Code 2.1.284): user-invocable only, model invocation disabled (command type `local`)
  - detect: origin discovered, score 0.6585, invocable_by user-only, recommended integration suggest
  - docs cross-check (commands reference, 2026-09-29): documented
- **Observation:** extraction: extracted from binary v2.1.284 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, counts are totals) (2026-09-29)
- **Recheck trigger:** a Claude Code release renames or removes `/auto-mode-setup`, changes its argument contract or what it writes, un-hides it, or makes it model-invocable (verified 2026-09-29)
- **Baked:** description phrase no · Boundary section yes · Native step no · suggest sentence no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `autofix-pr` → `source-control:babysit-prs`

- **Verdict:** `complementary`: `/autofix-pr` spawns a cloud session that watches the current branch's PR and pushes fixes for CI failures and review comments; ours advances the user's open PRs as a fleet from a local session under tiered autonomy, and never resolves threads or merges at the safe tier. User-only, so ours offers `/autofix-pr` for one PR the person wants watched after the session ends. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation.
- **Integration:** `suggest`
- **Native surface:** `autofix-pr` (built-in command; markers: hidden, gated, model-invocation-disabled)
- **Our component:** `source-control:babysit-prs` (skill)
- **Evidence:**
  - `autofix-pr` present in the extraction as builtin-command
  - markers: hidden, gated, model-invocation-disabled
  - native description: Monitor and autofix any issues with the current PR
  - invocation mode (2026-09-29, Claude Code 2.1.284): user-invocable only, model invocation disabled (command type `local-jsx`)
  - detect: origin discovered, score 0.3934, invocable_by user-only, recommended integration suggest
  - docs cross-check (commands reference, 2026-09-29): documented
- **Observation:** extraction: extracted from binary v2.1.284 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, counts are totals) (2026-09-29)
- **Recheck trigger:** a Claude Code release renames or removes `/autofix-pr`, un-hides it, changes its gating, or makes it model-invocable (verified 2026-09-29)
- **Baked:** description phrase no · Boundary section yes · Native step no · suggest sentence no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `autofix-pr` → `source-control:pull-request`

- **Verdict:** `complementary`: The native command runs a cloud session that monitors the current PR and autofixes it; ours monitors locally. Reserved for the person to run, so ours suggests it during monitor as an alternative or addition. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation.
- **Integration:** `suggest`
- **Native surface:** `autofix-pr` (built-in command; markers: hidden, gated, model-invocation-disabled)
- **Our component:** `source-control:pull-request` (skill)
- **Evidence:**
  - `autofix-pr` present in the extraction as builtin-command
  - markers: hidden, gated, model-invocation-disabled
  - native description: Monitor and autofix any issues with the current PR
  - invocation mode (2026-09-29, Claude Code 2.1.284): user-invocable only, model invocation disabled (command type `local-jsx`)
  - detect: origin discovered, score 0.4125, invocable_by user-only, recommended integration suggest
  - docs cross-check (commands reference, 2026-09-29): documented
- **Observation:** extraction: extracted from binary v2.1.284 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, counts are totals) (2026-09-29)
- **Recheck trigger:** a Claude Code release renames or removes `/autofix-pr`, un-hides it, changes its gating, or makes it model-invocable (verified 2026-09-29)
- **Baked:** description phrase no · Boundary section yes · Native step no · suggest sentence no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `background` → `session-flow:continue-in-background`

- **Verdict:** `complementary`: The built-in command sends this session itself to the background and frees the terminal; ours starts a fresh detached session from a save-point. User-only, so ours suggests it. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation.
- **Integration:** `suggest`
- **Native surface:** `background` (built-in command; markers: gated, model-invocation-disabled)
- **Our component:** `session-flow:continue-in-background` (skill)
- **Evidence:**
  - `background` present in the extraction as builtin-command
  - markers: gated, model-invocation-disabled
  - aliases: bg
  - native description: Send this session to the background and free the terminal
  - argument hint: [prompt]
  - invocation mode (2026-09-29, Claude Code 2.1.284): user-invocable only, model invocation disabled (command type `local-jsx`)
  - detect: origin discovered, score 0.7755, invocable_by user-only, recommended integration suggest
  - docs cross-check (commands reference, 2026-09-29): documented
- **Observation:** extraction: extracted from binary v2.1.284 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, counts are totals) (2026-09-29)
- **Recheck trigger:** a Claude Code release renames or removes `/background` or its `bg` alias, changes its gating, or makes it model-invocable (verified 2026-09-29)
- **Baked:** description phrase no · Boundary section yes · Native step no · suggest sentence no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `bug` → `bugs:write`

- **Verdict:** `complementary`: `/bug` sends a report about Claude Code itself, with the conversation, to Anthropic; ours writes a structured report for a defect in the user's own code and files nothing by default. When the defect is in Claude Code, ours offers `/bug`. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation.
- **Integration:** `suggest`
- **Native surface:** `bug` (built-in command; markers: model-invocation-disabled)
- **Our component:** `bugs:write` (skill)
- **Evidence:**
  - `bug` present in the extraction as builtin-command
  - markers: model-invocation-disabled
  - aliases: share
  - native description: Report a bug or share your conversation
  - argument hint: [report]
  - invocation mode (2026-09-29, Claude Code 2.1.284): user-invocable only, model invocation disabled (command type `local-jsx`)
  - detect: origin discovered, score 0.4082, invocable_by user-only, recommended integration suggest
  - docs cross-check (commands reference, 2026-09-29): documented
- **Observation:** extraction: extracted from binary v2.1.284 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, counts are totals) (2026-09-29)
- **Recheck trigger:** a Claude Code release renames or removes `/bug` or its `share` alias, changes what it sends, or makes it model-invocable (verified 2026-09-29)
- **Baked:** description phrase no · Boundary section yes · Native step no · suggest sentence no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `commit-push-pr` → `source-control:commit`

- **Verdict:** `complementary`: `/commit-push-pr` commits, pushes, and opens a PR in one step; ours creates one commit under the repository's subject convention with surgical staging and never pushes. A request to commit only stays with ours. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation.
- **Integration:** `route`
- **Native surface:** `commit-push-pr` (built-in command; markers: none)
- **Our component:** `source-control:commit` (skill)
- **Evidence:**
  - `commit-push-pr` present in the extraction as builtin-command
  - native description: Commit, push, and open a PR
  - invocation mode (2026-09-29, Claude Code 2.1.284): model-invocable and user-invocable (command type `prompt`)
  - detect: origin discovered, score 0.4361, invocable_by model+user, recommended integration route
  - docs cross-check (commands reference, 2026-09-29): undocumented
- **Observation:** extraction: extracted from binary v2.1.284 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, counts are totals) (2026-09-29)
- **Recheck trigger:** a Claude Code release renames or removes `/commit-push-pr`, changes its invocability, or the commands reference documents it (verified 2026-09-29)
- **Baked:** description phrase yes · Boundary section yes · Native step no · suggest sentence no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `commit-push-pr` → `source-control:pull-request`

- **Verdict:** `complementary`: The built-in command commits, pushes, and opens a PR in one prompt; ours owns the whole lifecycle and this repo's PR contract. Different scope, same object. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation.
- **Integration:** `route`
- **Native surface:** `commit-push-pr` (built-in command; markers: none)
- **Our component:** `source-control:pull-request` (skill)
- **Evidence:**
  - `commit-push-pr` present in the extraction as builtin-command
  - native description: Commit, push, and open a PR
  - invocation mode (2026-09-29, Claude Code 2.1.284): model-invocable and user-invocable (command type `prompt`)
  - detect: origin discovered, score 0.4092, invocable_by model+user, recommended integration route
  - docs cross-check (commands reference, 2026-09-29): undocumented
- **Observation:** extraction: extracted from binary v2.1.284 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, counts are totals) (2026-09-29)
- **Recheck trigger:** a Claude Code release renames or removes `/commit-push-pr`, changes its command type or invocability, or the commands reference starts documenting it (verified 2026-09-29)
- **Baked:** description phrase yes · Boundary section yes · Native step no · suggest sentence no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `context` → `context-budget:audit`

- **Verdict:** `complementary`: The built-in command visualizes the current session's context usage as a colored grid with optimization suggestions; ours measures a fresh headless session's startup payload per item, splitting the built-in tool pools /context reports as lump sums, and ledgers before/after deltas. User-only, so ours offers it to the person for a live look at the current window. Ruled 2026-09-30 by operator direction on the orchestrator's recommendation.
- **Integration:** `suggest`
- **Native surface:** `context` (built-in command; markers: gated, model-invocation-disabled)
- **Our component:** `context-budget:audit` (skill)
- **Evidence:**
  - `context` present in the 2.1.285 extraction as builtin-command
  - markers: gated
  - native description: Visualize current context usage as a colored grid; argument hint `[all]`
  - invocation mode (2026-09-30, Claude Code 2.1.285): user-invocable only, model invocation disabled (command type `local-jsx`)
  - detect: origin discovered, score 0.3859 from shared tokens context, usage
  - docs cross-check (commands reference, 2026-09-30): the `/context [all]` row documents the grid, optimization suggestions for context-heavy tools, memory bloat and capacity warnings, and `all` to expand the per-item breakdown
  - our Boundary: 'If /context is available in your session (gate basis: the verification record below), you can run `/context` to see what fills the current window'; the description carries no /context clause
- **Observation:** extraction: extracted from binary v2.1.285 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; builtin_commands lane integrity ok) (2026-09-29)
- **Recheck trigger:** a Claude Code release renames or removes `/context`, makes it model-invocable, or widens it to a fresh session's startup payload or a before/after comparison (verified 2026-09-30)
- **Baked:** description phrase no · Boundary section yes · Native step no · suggest sentence yes

### `export` → `session-flow:clean-stop`

- **Verdict:** `complementary`: No component duplicates /export and none may invoke it: /export is a non-prompt command type the Skill tool never lists, and the command is confirmed unavailable headless. clean-stop, handoff (prompt-only path), and retro instead suggest that the user run it at session-end moments, because transcripts are retention-swept and the conversation otherwise has no durable artifact. The native surface does the exporting; the skills only name the moment and a destination convention (<memory_dir>/exports/). Verdict recorded per the user-approved export-session-flow Brief (PR #3355).
- **Integration:** `suggest`
- **Native surface:** `export` (built-in command; markers: model-invocation-disabled)
- **Our component:** `session-flow:clean-stop` (skill)
- **Evidence:**
  - probed on the live v2.1.241 binary 2026-08-24: `claude --bare -p "/export <path>"` returned `/export isn't available in this environment.` and wrote no file, so the command is an interactive-terminal surface
  - documented at code.claude.com/docs/en/commands.md: /export renders the current conversation as plain text to clipboard or a file (optional filename argument), no format or redaction flags
  - output written to user paths sits outside the cleanupPeriodDays retention sweep (path-scoped to ~/.claude), which is the durability property the suggestions exist for
  - suggestion sites: plugins/session-flow/skills/clean-stop/SKILL.md (durability sweep), handoff/SKILL.md (prompt-only close), retro/SKILL.md (post-chain-coverage offer); all body text, presence-gated with the canonical token, none baked into a description or Boundary section
  - invocation mode (2026-09-11, Claude Code 2.1.263): local-jsx command type, not a prompt, so the Skill tool never lists /export
- **Observation:** live-roster: probed on the live v2.1.241 binary in a Linux container (headless form unavailable; interactive form documented but not observed here); one environment, one day (2026-08-24)
- **Recheck trigger:** a Claude Code release note or docs change adds an /export format/redaction flag, a headless or programmatic form, or an official conversation-sharing surface; any of these reopens whether suggestion-only is still the right integration shape (verified 2026-08-24)
- **Baked:** description phrase no · Boundary section no · Native step no · suggest sentence yes

### `export` → `session-flow:handoff`

- **Verdict:** `complementary`: No component duplicates /export and none may invoke it: /export is a non-prompt command type the Skill tool never lists, and the command is confirmed unavailable headless. clean-stop, handoff (prompt-only path), and retro instead suggest that the user run it at session-end moments, because transcripts are retention-swept and the conversation otherwise has no durable artifact. The native surface does the exporting; the skills only name the moment and a destination convention (<memory_dir>/exports/). Verdict recorded per the user-approved export-session-flow Brief (PR #3355).
- **Integration:** `suggest`
- **Native surface:** `export` (built-in command; markers: model-invocation-disabled)
- **Our component:** `session-flow:handoff` (skill)
- **Evidence:**
  - probed on the live v2.1.241 binary 2026-08-24: `claude --bare -p "/export <path>"` returned `/export isn't available in this environment.` and wrote no file, so the command is an interactive-terminal surface
  - documented at code.claude.com/docs/en/commands.md: /export renders the current conversation as plain text to clipboard or a file (optional filename argument), no format or redaction flags
  - output written to user paths sits outside the cleanupPeriodDays retention sweep (path-scoped to ~/.claude), which is the durability property the suggestions exist for
  - suggestion sites: plugins/session-flow/skills/clean-stop/SKILL.md (durability sweep), handoff/SKILL.md (prompt-only close), retro/SKILL.md (post-chain-coverage offer); all body text, presence-gated with the canonical token, none baked into a description or Boundary section
  - suggest site: plugins/session-flow/skills/handoff/SKILL.md
  - invocation mode (2026-09-11, Claude Code 2.1.263): local-jsx command type, not a prompt, so the Skill tool never lists /export
- **Observation:** live-roster: probed on the live v2.1.241 binary in a Linux container (headless form unavailable; interactive form documented but not observed here); one environment, one day (2026-08-24)
- **Recheck trigger:** a Claude Code release note or docs change adds an /export format/redaction flag, a headless or programmatic form, or an official conversation-sharing surface; any of these reopens whether suggestion-only is still the right integration shape (verified 2026-08-24)
- **Baked:** description phrase no · Boundary section no · Native step no · suggest sentence yes

### `export` → `session-flow:retro`

- **Verdict:** `complementary`: No component duplicates /export and none may invoke it: /export is a non-prompt command type the Skill tool never lists, and the command is confirmed unavailable headless. clean-stop, handoff (prompt-only path), and retro instead suggest that the user run it at session-end moments, because transcripts are retention-swept and the conversation otherwise has no durable artifact. The native surface does the exporting; the skills only name the moment and a destination convention (<memory_dir>/exports/). Verdict recorded per the user-approved export-session-flow Brief (PR #3355).
- **Integration:** `suggest`
- **Native surface:** `export` (built-in command; markers: model-invocation-disabled)
- **Our component:** `session-flow:retro` (skill)
- **Evidence:**
  - probed on the live v2.1.241 binary 2026-08-24: `claude --bare -p "/export <path>"` returned `/export isn't available in this environment.` and wrote no file, so the command is an interactive-terminal surface
  - documented at code.claude.com/docs/en/commands.md: /export renders the current conversation as plain text to clipboard or a file (optional filename argument), no format or redaction flags
  - output written to user paths sits outside the cleanupPeriodDays retention sweep (path-scoped to ~/.claude), which is the durability property the suggestions exist for
  - suggestion sites: plugins/session-flow/skills/clean-stop/SKILL.md (durability sweep), handoff/SKILL.md (prompt-only close), retro/SKILL.md (post-chain-coverage offer); all body text, presence-gated with the canonical token, none baked into a description or Boundary section
  - suggest site: plugins/session-flow/skills/retro/SKILL.md
  - invocation mode (2026-09-11, Claude Code 2.1.263): local-jsx command type, not a prompt, so the Skill tool never lists /export
- **Observation:** live-roster: probed on the live v2.1.241 binary in a Linux container (headless form unavailable; interactive form documented but not observed here); one environment, one day (2026-08-24)
- **Recheck trigger:** a Claude Code release note or docs change adds an /export format/redaction flag, a headless or programmatic form, or an official conversation-sharing surface; any of these reopens whether suggestion-only is still the right integration shape (verified 2026-08-24)
- **Baked:** description phrase no · Boundary section no · Native step no · suggest sentence yes

### `fork` → `session-flow:continue-in-background`

- **Verdict:** `complementary`: The built-in command spawns a background agent that inherits the full conversation; ours hands off through a durable save-point and a detached session. User-only, so ours suggests it. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation.
- **Integration:** `suggest`
- **Native surface:** `fork` (built-in command; markers: gated, model-invocation-disabled)
- **Our component:** `session-flow:continue-in-background` (skill)
- **Evidence:**
  - `fork` present in the extraction as builtin-command
  - markers: gated, model-invocation-disabled
  - native description: Spawn a background agent that inherits the full conversation
  - argument hint: <directive>
  - invocation mode (2026-09-29, Claude Code 2.1.284): user-invocable only, model invocation disabled (command type `local-jsx`)
  - detect: origin seeded, score 0.0611, invocable_by user-only, recommended integration suggest
  - docs cross-check (commands reference, 2026-09-29): documented
- **Observation:** extraction: extracted from binary v2.1.284 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, counts are totals) (2026-09-29)
- **Recheck trigger:** a Claude Code release renames or removes `/fork` (the changelog records a 2.1.77 rename to `/branch` that the 2.1.284 registration does not show), changes its gating, or makes it model-invocable (verified 2026-09-29)
- **Baked:** description phrase no · Boundary section yes · Native step no · suggest sentence no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `goal` → `planning:draft-goal-condition`

- **Verdict:** `complementary`: Ours drafts the completion condition the native command runs; the person sets it with `/goal`. User-only, so ours suggests it. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation.
- **Integration:** `suggest`
- **Native surface:** `goal` (built-in command; markers: model-invocation-disabled)
- **Our component:** `planning:draft-goal-condition` (skill)
- **Evidence:**
  - `goal` present in the extraction as builtin-command
  - markers: model-invocation-disabled
  - native description: Set a goal Claude checks before stopping
  - argument hint: [<condition> | clear]
  - invocation mode (2026-09-29, Claude Code 2.1.284): user-invocable only, model invocation disabled (command type `local-jsx`)
  - detect: origin discovered, score 0.8063, invocable_by user-only, recommended integration suggest
  - docs cross-check (commands reference, 2026-09-29): documented
- **Observation:** extraction: extracted from binary v2.1.284 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, counts are totals) (2026-09-29)
- **Recheck trigger:** a Claude Code release renames or removes `/goal`, changes its condition contract or length limit, or makes it model-invocable (verified 2026-09-29)
- **Baked:** description phrase no · Boundary section yes · Native step no · suggest sentence no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `insights` → `session-flow:retro`

- **Verdict:** `complementary`: The built-in command generates a report analyzing the person's Claude Code sessions; ours runs a structured retrospective of one session and codifies learnings durably. User-only, so ours suggests it. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation.
- **Integration:** `suggest`
- **Native surface:** `insights` (built-in command; markers: model-invocation-disabled)
- **Our component:** `session-flow:retro` (skill)
- **Evidence:**
  - `insights` present in the extraction as builtin-command
  - markers: model-invocation-disabled
  - native description: Generate a report analyzing your Claude Code sessions
  - invocation mode (2026-09-29, Claude Code 2.1.284): user-invocable only, model invocation disabled (command type `prompt`)
  - detect: human-added pair, not emitted at threshold 0.30 / top-k 3 (discovery score 0.0105)
  - docs cross-check (commands reference, 2026-09-29): documented
- **Observation:** extraction: extracted from binary v2.1.284 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, counts are totals) (2026-09-29)
- **Recheck trigger:** a Claude Code release renames or removes `/insights`, changes its report scope, or makes it model-invocable (verified 2026-09-29)
- **Baked:** description phrase no · Boundary section yes · Native step no · suggest sentence no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `install-github-app` → `github:advise`

- **Verdict:** `complementary`: `/install-github-app` installs the Claude GitHub App for one repository and optionally sets up its Actions workflow and secrets; ours is read-only guidance across the GitHub settings plane. When the ask is setting up Claude in GitHub Actions, ours offers `/install-github-app`. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation.
- **Integration:** `suggest`
- **Native surface:** `install-github-app` (built-in command; markers: gated, model-invocation-disabled)
- **Our component:** `github:advise` (skill)
- **Evidence:**
  - `install-github-app` present in the extraction as builtin-command
  - markers: gated, model-invocation-disabled
  - native description: Set up Claude GitHub Actions for a repository
  - invocation mode (2026-09-29, Claude Code 2.1.284): user-invocable only, model invocation disabled (command type `local-jsx`)
  - detect: origin discovered, score 0.3046, invocable_by user-only, recommended integration suggest
  - docs cross-check (commands reference, 2026-09-29): documented
- **Observation:** extraction: extracted from binary v2.1.284 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, counts are totals) (2026-09-29)
- **Recheck trigger:** a Claude Code release renames or removes `/install-github-app`, ungates it, or makes it model-invocable (verified 2026-09-29)
- **Baked:** description phrase no · Boundary section yes · Native step no · suggest sentence no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `memory` → `claude-memory:stateless`

- **Verdict:** `complementary`: `/memory` is the interactive dialog to edit CLAUDE.md files, turn auto memory on or off, and view its entries; ours reports auto-memory state across every scope and disables or purges it persistently through settings. Ours offers `/memory` for an interactive toggle or a look at the entries. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation.
- **Integration:** `suggest`
- **Native surface:** `memory` (built-in command; markers: model-invocation-disabled)
- **Our component:** `claude-memory:stateless` (skill)
- **Evidence:**
  - `memory` present in the extraction as builtin-command
  - markers: model-invocation-disabled
  - native description: Edit CLAUDE.md files and memory settings
  - invocation mode (2026-09-29, Claude Code 2.1.284): user-invocable only, model invocation disabled (command type `local-jsx`)
  - detect: origin discovered, score 0.5276, invocable_by user-only, recommended integration suggest
  - docs cross-check (commands reference, 2026-09-29): documented
- **Observation:** extraction: extracted from binary v2.1.284 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, counts are totals) (2026-09-29)
- **Recheck trigger:** a Claude Code release renames or removes `/memory`, drops its auto-memory toggle, or makes it model-invocable (verified 2026-09-29)
- **Baked:** description phrase no · Boundary section yes · Native step no · suggest sentence no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `pause-memory` → `claude-memory:stateless`

- **Verdict:** `defer`: Deferred: a hidden, gated command that pauses auto memory for one session; ours inspects and disables auto memory persistently. Hidden and undocumented, so not ruled on. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation.
- **Integration:** `route`
- **Native surface:** `pause-memory` (built-in command; markers: hidden, gated, model-invocation-disabled)
- **Our component:** `claude-memory:stateless` (skill)
- **Evidence:**
  - `pause-memory` present in the extraction as builtin-command
  - markers: hidden, gated, model-invocation-disabled
  - aliases: memory-pause, toggle-memory
  - native description: Pause automemory for this session
  - invocation mode (2026-09-29, Claude Code 2.1.284): user-invocable only, model invocation disabled (command type `local`)
  - detect: human-added pair, not emitted at threshold 0.30 / top-k 3 (discovery score 0.1724)
  - docs cross-check (commands reference, 2026-09-29): undocumented
- **Observation:** extraction: extracted from binary v2.1.284 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, counts are totals) (2026-09-29)
- **Recheck trigger:** a Claude Code release un-hides or ungates `/pause-memory` (aliases `memory-pause`, `toggle-memory`), or the commands reference documents it (verified 2026-09-29)
- **Baked:** description phrase no · Boundary section no · Native step no · suggest sentence no

### `permissions` → `claude-config:audit-permission-grants`

- **Verdict:** `complementary`: `/permissions` views and edits allow, ask, and deny rules interactively; ours audits grants for portability and auto mode durability and writes nothing. When a finding calls for changing a rule, ours offers `/permissions`. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation.
- **Integration:** `suggest`
- **Native surface:** `permissions` (built-in command; markers: model-invocation-disabled)
- **Our component:** `claude-config:audit-permission-grants` (skill)
- **Evidence:**
  - `permissions` present in the extraction as builtin-command
  - markers: model-invocation-disabled
  - aliases: allowed-tools
  - native description: Manage allow and deny tool permission rules
  - invocation mode (2026-09-29, Claude Code 2.1.284): user-invocable only, model invocation disabled (command type `local-jsx`)
  - detect: origin discovered, score 0.8541, invocable_by user-only, recommended integration suggest
  - docs cross-check (commands reference, 2026-09-29): documented
- **Observation:** extraction: extracted from binary v2.1.284 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, counts are totals) (2026-09-29)
- **Recheck trigger:** a Claude Code release renames `/permissions`, changes its `allowed-tools` alias, or makes it model-invocable (verified 2026-09-29)
- **Baked:** description phrase no · Boundary section yes · Native step no · suggest sentence no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `permissions` → `claude-config:audit-permission-state`

- **Verdict:** `complementary`: The built-in command is the interactive viewer and editor for allow and deny rules (with recent denials and an auto mode tab); ours merges every settings scope into the effective set with sources, report-only. User-only, so ours suggests it. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation.
- **Integration:** `suggest`
- **Native surface:** `permissions` (built-in command; markers: model-invocation-disabled)
- **Our component:** `claude-config:audit-permission-state` (skill)
- **Evidence:**
  - `permissions` present in the extraction as builtin-command
  - markers: model-invocation-disabled
  - aliases: allowed-tools
  - native description: Manage allow and deny tool permission rules
  - invocation mode (2026-09-29, Claude Code 2.1.284): user-invocable only, model invocation disabled (command type `local-jsx`)
  - detect: origin discovered, score 0.8253, invocable_by user-only, recommended integration suggest
  - docs cross-check (commands reference, 2026-09-29): documented
- **Observation:** extraction: extracted from binary v2.1.284 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, counts are totals) (2026-09-29)
- **Recheck trigger:** a Claude Code release renames or removes `/permissions` or its `allowed-tools` alias, changes its tabs, or makes it model-invocable (verified 2026-09-29)
- **Baked:** description phrase no · Boundary section yes · Native step no · suggest sentence no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `plan` → `planning:plan`

- **Verdict:** `complementary`: The built-in command enters plan mode or shows the session plan; ours produces a persisted plan with test strategy, blast radius, and an approval gate. User-only, so ours suggests it. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation.
- **Integration:** `suggest`
- **Native surface:** `plan` (built-in command; markers: model-invocation-disabled)
- **Our component:** `planning:plan` (skill)
- **Evidence:**
  - `plan` present in the extraction as builtin-command
  - markers: model-invocation-disabled
  - native description: Enable plan mode or view the current session plan
  - argument hint: [open|<description>]
  - invocation mode (2026-09-29, Claude Code 2.1.284): user-invocable only, model invocation disabled (command type `local-jsx`)
  - detect: origin discovered, score 0.6733, invocable_by user-only, recommended integration suggest
  - docs cross-check (commands reference, 2026-09-29): documented
- **Observation:** extraction: extracted from binary v2.1.284 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, counts are totals) (2026-09-29)
- **Recheck trigger:** a Claude Code release renames or removes `/plan`, changes what it persists, or makes it model-invocable (verified 2026-09-29)
- **Baked:** description phrase no · Boundary section yes · Native step no · suggest sentence no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `plugin eval` → `evals:plugin-eval`

- **Verdict:** `complementary`: The CLI runs and scores: `claude plugin eval <target>` loads the plugin, runs every case in a with-plugin arm and a no-plugin baseline arm, grades each run, and reports WITH, W/OUT, and the delta. evals:plugin-eval is the guided practice around that command, which the CLI does not ship: a preflight that reports the CLI version against the floor, whether a sandbox backend exists on this machine, and the target type (plugin, wrapped skill, wrapped agent, hooks as advisory; CLAUDE.md and rules refused because the run strips them by design); static validation of the case files with no model call; a cost estimate from cases x runs x arms and a ceiling from plugin user config passed as --max-cost-usd; and a delta-first reading with the iteration loop. Neither replaces the other: the skill never grades, and the command never preflights, prices, or reads. The skill's Boundary section names the command; no listing phrase is baked, because the native-references gate token is a condition on the model's skill listing, and a CLI subcommand never enters that listing, so the skill gates on the CLI itself (preflight's version floor) instead. The gated marker rests on two switches: below the floor the binary prints an early-access refusal, and a server-side switch prints an unavailable refusal that nothing local restores.
- **Integration:** `route`
- **Native surface:** `plugin eval` (built-in command; markers: gated)
- **Our component:** `evals:plugin-eval` (skill)
- **Evidence:**
  - `claude plugin eval --help` at 2.1.269 (read 2026-09-11): 'Run eval cases (<eval dir>/**/case.yaml or prompt.md + graders/*.md; the eval dir is evals/ unless --eval-dir or the manifest says otherwise) against a plugin and report scored results. Target is a path, a plugin name, or a plugin@marketplace id: installed and skills-dir plugins both resolve (and add a no-plugin baseline arm)'; `--ablation` defaults to with-without whenever a plugin resolves and reports the score delta, and under it graders marked with-only, including `tool_used: Skill`, are a plugin-fired indicator rather than part of the score
  - the same help text: `--max-cost-usd` is an optional hard ceiling checked before each run launches (exit 2 with partial results when hit; paid graders skipped on the breaching run while free graders still score it); `--trust-plugin` answers the first-run trust prompt for CI; `--threshold` defaults to 1.0; `--allow-tools` is the operator grant for Bash, Write, Edit, WebFetch, and mcp__*; `init` takes only --bare, --eval-dir, and -i
  - https://code.claude.com/docs/en/plugin-evals.md (the raw variant; read 2026-09-11) documents the same flag set, the case layout, the exit codes 0/1/2/130/143, and the aggregate-result.json fields; the raw page matched `--help` exactly where a summarizer over the rendered page had fabricated a flag table
  - gate basis: the command shipped in Claude Code 2.1.269 (anthropics/claude-code, 2026-09-11); below that floor the binary prints `plugin eval is currently in early access`, and a server-side switch prints `plugin eval is currently unavailable`, which no local setting restores
  - the docs page: the run strips user settings, hooks, CLAUDE.md, MCP servers, other plugins, memory, and skills, so a rules or CLAUDE.md target has nothing to measure; native Windows has no sandbox backend, so a case granting Bash, Write, or Edit is refused rather than run unconfined, with WSL2 named for Windows and bubblewrap plus socat for Linux
  - the docs page: the case format (`prompt.md` plus `graders/*.md`, or `case.yaml` with `schema_version: "1.1"`) is not the skill-creator `evals/evals.json` format this marketplace's skills carry, so the two coexist and `skill-quality:check validate-evals` keeps the other one
  - our planned description: preflight, validate without spending, price, and read the delta for a `claude plugin eval` run; the CLI runs and scores, this skill guides the practice around it (shipped as `plugins/evals/skills/plugin-eval` in melodic-software/claude-code-plugins#4154)
  - `plugin eval` is absent from the 2.1.232 and 2.1.251 extractions the sibling rows rest on; absence from an extraction is a statement about the extraction, and the command postdates both
- **Observation:** extraction: `claude plugin eval --help` from the installed CLI at 2.1.269 (`claude --version` prints `2.1.269 (Claude Code)`), read live in the session on 2026-09-11; a targeted observation of one subcommand's help text, not a re-extraction of the binary's roster (2026-09-11)
- **Recheck trigger:** a Claude Code release after 2.1.269 changes the plugin eval flag set, the case schema version, the exit codes, the ablation exclusion rule for with-only and `tool_used: Skill` graders, the early-access or unavailable gate strings, or the sandbox backend list; or the command or its docs page gains a preflight, validate-only, dry-run, or cost-estimate mode that makes any part of evals:plugin-eval redundant (verified 2026-09-11)
- **Baked:** description phrase no · Boundary section yes · Native step no · suggest sentence no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `recap` → `session-flow:orient`

- **Verdict:** `complementary`: The built-in command generates a one-line recap of the current session; ours orients from durable state (ledgers, handoffs, PRs, work items, git) the recap never sees. User-only, so ours suggests it. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation.
- **Integration:** `suggest`
- **Native surface:** `recap` (built-in command; markers: model-invocation-disabled)
- **Our component:** `session-flow:orient` (skill)
- **Evidence:**
  - `recap` present in the extraction as builtin-command
  - markers: model-invocation-disabled
  - native description: Generate a one-line session recap now
  - invocation mode (2026-09-29, Claude Code 2.1.284): user-invocable only, model invocation disabled (command type `local`)
  - detect: origin seeded, score 0.1948, invocable_by user-only, recommended integration suggest
  - docs cross-check (commands reference, 2026-09-29): documented
- **Observation:** extraction: extracted from binary v2.1.284 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, counts are totals) (2026-09-29)
- **Recheck trigger:** a Claude Code release renames or removes `/recap`, widens it beyond the current session, or makes it model-invocable (verified 2026-09-29)
- **Baked:** description phrase no · Boundary section yes · Native step no · suggest sentence no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `skill-doctor` → `claude-ops:audit-skill-visibility`

- **Verdict:** `complementary`: The sibling doctor row's split, narrowed to the surface that now owns the question. Built-in /skill-doctor is a one-shot report of what each loaded skill costs in context and how often it is used, so unused ones can be turned off. audit-skill-visibility answers why a skill is unseen: it reconciles three usage sources (native ~/.claude.json counters, its own JSONL store, OTEL) under a max-across-sources rule, computes an observed horizon and withholds every verdict the span cannot support, diagnoses reachability causes, and analyses listing-budget starvation. It disables nothing by contract. This row is separate from the doctor row rather than folded into it because the two surfaces carry different gates: /doctor answers to DISABLE_DOCTOR_COMMAND, /skill-doctor to a minimum version and to feature-flag fetching, so a session can resolve either, both, or neither, and each routing line needs its own presence gate.
- **Integration:** `suggest`
- **Native surface:** `skill-doctor` (built-in command; markers: gated, model-invocation-disabled)
- **Our component:** `claude-ops:audit-skill-visibility` (skill)
- **Evidence:**
  - upstream commit d7dbd9a09f59775726ed14bbea8fc9dfdff62f7b in anthropics/claude-code (2026-09-04) added the `## 2.1.261` CHANGELOG heading and, under it, `Added /skill-doctor to show which loaded skills go unused and what they cost in context, so you can prune them`; read from the commit diff, not from the rendered changelog page
  - https://code.claude.com/docs/en/commands.md carries a /skill-doctor row in the all-commands table, and that row does NOT carry the bold `[Skill](/docs/en/skills#bundled-skills).` prefix the same table puts on /doctor, /run, /run-skill-generator and /simplify; that prefix is how the table marks a bundled skill, so this row is classed builtin-command rather than bundled-skill (read 2026-09-07)
  - the same table row and https://code.claude.com/docs/en/skills.md ('Find unused skills') both state that /skill-doctor requires Claude Code v2.1.252 or later and is unavailable in sessions that skip feature-flag fetching, and the skills page adds that it answers `Skill usage reports are not available on this connection.` over Remote Control; that is the gate this row records, and it is not doctor's
  - the version the surface was announced in and the version it is documented to require disagree upstream: the CHANGELOG lands it at 2.1.261 while commands.md and skills.md say v2.1.252 or later, so no shipped routing line in this repository states a version for it (read 2026-09-07)
  - our description: audit whether each installed skill is actually VISIBLE to the model; reconciles native counters, a JSONL store, and OTEL; withholds every verdict the data cannot support; read-only, never disables, deletes, or edits a skill
  - our description's front-loaded routing clause, the Purpose section, and the SKILL.md Scope boundary table each name /skill-doctor behind its own `resolves in this session` gate, separate from the /doctor gate beside it
  - invocation mode (2026-09-11, Claude Code 2.1.263): local-jsx command type, not a prompt, so the Skill tool never lists it; the native report excludes bundled skills
- **Observation:** upstream-source: d7dbd9a09f59775726ed14bbea8fc9dfdff62f7b, the anthropics/claude-code commit that added the 2.1.261 CHANGELOG entry naming /skill-doctor, plus the commands.md and skills.md pages read the same day. Not an extraction and not a live roster: this container runs 2.1.258, below the release that announced the surface, so nothing here observed the command itself. (2026-09-07)
- **Recheck trigger:** a Claude Code release note or docs change removes /skill-doctor, folds its report back into /doctor, gives its all-commands row the bundled-skill marker (which moves this row to the bundled-skill lane and changes which switch disables it), changes its version or feature-flag gate, or gives it a multi-source reconciliation or observation-horizon discipline of its own (verified 2026-09-07)
- **Baked:** description phrase yes · Boundary section yes · Native step no · suggest sentence yes
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `subtask` → `session-flow:continue-in-background`

- **Verdict:** `complementary`: The built-in command sends a subagent off with the full context and returns its result here; ours writes a save-point and launches a detached background session seeded with a resume prompt. User-only, so ours suggests it. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation.
- **Integration:** `suggest`
- **Native surface:** `subtask` (built-in command; markers: gated, model-invocation-disabled)
- **Our component:** `session-flow:continue-in-background` (skill)
- **Evidence:**
  - `subtask` present in the extraction as builtin-command
  - markers: gated, model-invocation-disabled
  - native description: Send a subagent off with your full context; its result comes back here
  - argument hint: <task>
  - invocation mode (2026-09-29, Claude Code 2.1.284): user-invocable only, model invocation disabled (command type `local-jsx`)
  - detect: origin seeded, score 0.0771, invocable_by user-only, recommended integration suggest
  - docs cross-check (commands reference, 2026-09-29): documented
- **Observation:** extraction: extracted from binary v2.1.284 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, counts are totals) (2026-09-29)
- **Recheck trigger:** a Claude Code release renames or removes `/subtask`, changes its gating, or makes it model-invocable (verified 2026-09-29)
- **Baked:** description phrase no · Boundary section yes · Native step no · suggest sentence no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

## Bundled skills

### `artifact-explainer` → `education:explain`

- **Verdict:** `defer`: Deferred: the bundled skill is gated on Artifact availability, so its presence is not determinable from this session's evidence. It publishes a step-by-step concept walkthrough as an Artifact; ours drops a concept to plain prose in the reply. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation.
- **Integration:** `route`
- **Native surface:** `artifact-explainer` (bundled skill; markers: gated)
- **Our component:** `education:explain` (skill)
- **Evidence:**
  - `artifact-explainer` present in the extraction as bundled-skill
  - markers: gated
  - native description: Create an explainer artifact - a step-by-step conceptual walkthrough that teaches how something works. Use when the user asks to explain a concept, walk through a process, show how X works, make a tutorial, or produce a teaching-oriented page with a clear progression. Keywords - explainer, how it works, walkthrough, tutorial, step by step, concept. Only for CREATING a new artifact; edits to an existing artifact modify its HTML directly.
  - invocation mode (2026-09-29, Claude Code 2.1.284): model-invocable and user-invocable
  - detect: origin discovered, score 0.3873, invocable_by model+user, recommended integration route-or-wrap
  - docs cross-check (commands reference, 2026-09-29): undocumented
- **Observation:** extraction: extracted from binary v2.1.284 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, counts are totals) (2026-09-29)
- **Recheck trigger:** a Claude Code release ungates the bundled `artifact-explainer` skill, the commands reference documents it, or a live roster capture protocol exists for Artifact-gated skills (verified 2026-09-29)
- **Baked:** description phrase no · Boundary section no · Native step no · suggest sentence no

### `artifact-pr-review` → `review:pr-explainer`

- **Verdict:** `defer`: Deferred: the bundled skill is gated on Artifact availability, so its presence is not determinable from this session's evidence. It publishes a PR review briefing as an Artifact; ours offers a self-contained local HTML explainer beside the markdown record. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation.
- **Integration:** `route`
- **Native surface:** `artifact-pr-review` (bundled skill; markers: gated)
- **Our component:** `review:pr-explainer` (skill)
- **Evidence:**
  - `artifact-pr-review` present in the extraction as bundled-skill
  - markers: gated
  - native description: Create a PR review artifact - a structured review briefing for a GitHub pull request (synthesis title and bottom line, a recommendation, reviewer judgment calls, a visual explainer, signals, and blind spots), published as a shareable page. Use when the user asks to review a PR as an artifact, publish a PR review page, or share a review briefing. NOT a narrative walkthrough. Only for CREATING a new artifact; edits to an existing artifact modify its HTML directly.
  - argument hint: [pr number or url]
  - invocation mode (2026-09-29, Claude Code 2.1.284): model-invocable and user-invocable
  - detect: origin discovered, score 0.5363, invocable_by model+user, recommended integration route-or-wrap
  - docs cross-check (commands reference, 2026-09-29): undocumented
- **Observation:** extraction: extracted from binary v2.1.284 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, counts are totals) (2026-09-29)
- **Recheck trigger:** a Claude Code release ungates the bundled `artifact-pr-review` skill, the commands reference documents it, or a live roster capture protocol exists for Artifact-gated skills (verified 2026-09-29)
- **Baked:** description phrase no · Boundary section no · Native step no · suggest sentence no

### `batch` → `implementation:implement-dispatch`

- **Verdict:** `complementary`: The bundled skill researches and plans a large change, then runs it across 5 to 30 isolated worktree agents that each open a PR; ours dispatches an approved plan's phases to scope-fenced workers with verification at each boundary. User-only, so ours suggests it. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation.
- **Integration:** `suggest`
- **Native surface:** `batch` (bundled skill; markers: model-invocation-disabled)
- **Our component:** `implementation:implement-dispatch` (skill)
- **Evidence:**
  - `batch` present in the extraction as bundled-skill
  - markers: model-invocation-disabled
  - native description: Research and plan a large-scale change, then execute it in parallel across 5–30 isolated worktree agents that each open a PR.
  - argument hint: <instruction>
  - invocation mode (2026-09-29, Claude Code 2.1.284): user-invocable only, model invocation disabled
  - detect: origin seeded, score 0.0782, invocable_by user-only, recommended integration suggest
  - docs cross-check (commands reference, 2026-09-29): documented
- **Observation:** extraction: extracted from binary v2.1.284 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, counts are totals) (2026-09-29)
- **Recheck trigger:** a Claude Code release renames or removes the bundled `batch` skill, changes its worker range or PR behavior, or makes it model-invocable (verified 2026-09-29)
- **Baked:** description phrase no · Boundary section yes · Native step no · suggest sentence no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `claude-api` → `claude-config:audit-instructions`

- **Verdict:** `complementary`: Composite posture, decided at the ClaudeDevs cost-performance adoption interview: wrap or point to the bundled subcommand where it fits the use case, and run our own processes where they fit, rather than routing one way on paper. The bundled skill's prompt-audit subcommand is the vendor's apply-sweep over the working directory's whole prompt surface, application code included; audit-instructions is a standing report-only audit of locally-owned Claude Code instruction surfaces with the versioned I-catalog, target-model scoping, and deterministic pre-scans. ADR-0028 already composes both: run the vendor procedure per model change, feed recurring gap shapes back into the catalog. The app-code surface stays with the bundled skill (scope widening rejected at the same interview).
- **Integration:** `route`
- **Native surface:** `claude-api` (bundled skill; markers: gated)
- **Our component:** `claude-config:audit-instructions` (skill)
- **Evidence:**
  - binary extraction 2026-09-09 (claude.exe 2.1.263): registerClaudeApiSkill present; subcommand array cost-optimize, migrate, managed-agents-onboard, prompt-audit, upgrade, build-eval, hillclimb
  - platform docs claude-api-skill page (fetched 2026-09-09): 'The skill comes bundled with Claude Code and is also available in the open-source Anthropic skills repository'
  - hillclimb and build-eval are bundled-only: absent from anthropics/skills HEAD 41bbe19 (2026-09-03) and from the skill's docs page
  - executed composition precedent: docs/specs/prompt-audit-skills-2026-09.md (fleet-wide prompt-audit run, 805 findings applied) + ADR-0028 (repeats per model change; findings are edits, not criteria)
  - verdict recorded from the owner's interview answers in docs/upstream/claudedevs-cost-performance.md Lane M and Lane T2, 2026-09-10
- **Observation:** extraction: extracted from binary 2.1.263 at node_modules/@anthropic-ai/claude-code/bin/claude.exe (registerClaudeApiSkill string plus subcommand array; bundled shared/evals/eval-hillclimb.md extracted and read); bulk registrar enumeration was broken at this build, so this row's evidence is the targeted extraction, not the inventory JSON (2026-09-09)
- **Recheck trigger:** a Claude Code release changes the bundled claude-api skill's subcommand set, or the anthropics/skills repo or the platform claude-api-skill docs page gains hillclimb/build-eval (which also fires the docs/upstream/claudedevs-cost-performance.md hillclimb row) (verified 2026-09-10)
- **Baked:** description phrase yes · Boundary section yes · Native step no · suggest sentence no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `claude-api` → `evals:methodology`

- **Verdict:** `complementary`: Different jobs on the same object. The bundled skill's hillclimb subcommand consumes an eval suite and searches model and effort for the cheapest configuration that holds the target (train/test split, one change per round, held-out scoring), and build-eval scaffolds the suite it needs; both run evals and change configuration. evals:methodology is knowledge about designing the suite (criteria, anatomy, grading, effort as an axis) and runs nothing. The two chain: design the suite here, hand it to the search. Recorded when the effort-axis note citing hillclimb landed in the methodology reference.
- **Integration:** `route`
- **Native surface:** `claude-api` (bundled skill; markers: gated)
- **Our component:** `evals:methodology` (skill)
- **Evidence:**
  - binary extraction 2026-09-09 (claude.exe 2.1.263): subcommand array includes build-eval and hillclimb; bundled shared/evals/eval-hillclimb.md read end to end (train/test split, one proposal per round, held-out scoring)
  - hillclimb and build-eval absent from anthropics/skills HEAD 41bbe19 (2026-09-03) and from the platform claude-api-skill docs page
  - our description: 'Knowledge (WHY/WHAT of eval design), not a runner; ... for running and scoring a plugin's suite against a no-plugin baseline use /evals:plugin-eval'
  - reference/eval-design.md 'Effort as an eval axis' cites the subcommand behind the presence gate
- **Observation:** extraction: extracted from binary 2.1.263 at node_modules/@anthropic-ai/claude-code/bin/claude.exe (subcommand array; bundled shared/evals/eval-hillclimb.md extracted and read); bulk registrar enumeration was broken at this build, so this row's evidence is the targeted extraction, not the inventory JSON (2026-09-09)
- **Recheck trigger:** a Claude Code release changes the bundled claude-api skill's subcommand set, or the public anthropics/skills repo or the docs page gains hillclimb/build-eval (verified 2026-09-11)
- **Baked:** description phrase yes · Boundary section yes · Native step no · suggest sentence no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `claude-api` → `playbooks:fable-5`

- **Verdict:** `complementary`: The playbook's chapters defer every current fact (model ID, price, beta boundary, parameter shape) to the bundled claude-api skill by standing rule, and its API prompt-caching chapter names cost-optimize as the automation for the cost levers it describes. The bundled skill resolves live facts and acts (prompt-audit, cost-optimize, hillclimb edit prompts and configuration when asked); the playbook is operating doctrine and mechanisms that outlive any one price, and performs no work. Neither replaces the other.
- **Integration:** `route`
- **Native surface:** `claude-api` (bundled skill; markers: gated)
- **Our component:** `playbooks:fable-5` (skill)
- **Evidence:**
  - binary extraction 2026-09-09 (claude.exe 2.1.263): registerClaudeApiSkill present; subcommand array cost-optimize, migrate, managed-agents-onboard, prompt-audit, upgrade, build-eval, hillclimb
  - platform docs claude-api-skill page (fetched 2026-09-09): bundled with Claude Code and published in the open-source skills repository
  - reference/model-adaptation/fable-5-1.md standing rule: 'this chapter carries no model ID, price, or limit. Resolve the current details through the claude-api skill at the moment of use'
  - reference/prompt-caching.md 'Automation' bullet cites cost-optimize behind the presence gate
- **Observation:** extraction: extracted from binary 2.1.263 at node_modules/@anthropic-ai/claude-code/bin/claude.exe (registerClaudeApiSkill string plus subcommand array); bulk registrar enumeration was broken at this build, so this row's evidence is the targeted extraction, not the inventory JSON (2026-09-09)
- **Recheck trigger:** a Claude Code release changes the bundled claude-api skill's subcommand set or moves it between bundled and marketplace distribution (verified 2026-09-11)
- **Baked:** description phrase yes · Boundary section yes · Native step no · suggest sentence no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `code-review` → `review:code-review`

- **Verdict:** `complementary`: Same object, different invocation surface. The bundled skill is a session-driven review of the current diff or a named PR, with mutating flags (--fix writes the working tree, --comment posts to the PR). review:code-review is a non-interactive CI lane a reusable workflow invokes for one pull request, deliberately scoped out of security when a security lane exists. Neither replaces the other: a CI lane cannot be typed into a session, and the session surface has no workflow contract. The route is cost and shape: the native surface fans out its own agents, and a CI lane cannot be typed into a session. Skill-tool reach is not the reason.
- **Integration:** `route`
- **Native surface:** `code-review` (bundled skill; markers: none)
- **Our component:** `review:code-review` (skill)
- **Evidence:**
  - `code-review` present in the extraction as bundled-skill
  - aliases: review
  - native description: Review the current diff or a PR for bugs and cleanups
  - our description: CI code-review lane for a GitHub pull request. High-signal correctness and maintainability findings only, scoped out of security when a security lane exists
  - the review plugin already documents this overlap organically in plugins/review/skills/quality-gate/context/pr.md's Boundary section, naming the bundled command, the marketplace plugin, and the managed service as three distinct surfaces
- **Observation:** extraction: extracted from binary v2.1.284 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, counts are totals) (2026-09-29)
- **Recheck trigger:** a Claude Code release changes the bundled `code-review` skill's roster entry, its `review` alias, or its invocation mode. The alias was re-pointed at 2.1.220 and the alias-under-shadowing fix landed at 2.1.233, so this pair has moved twice in one quarter (verified 2026-09-11)
- **Baked:** description phrase yes · Boundary section yes · Native step no · suggest sentence no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `code-review` → `review:code-reviewer`

- **Verdict:** `complementary`: The bundled skill reviews the current diff or a named PR for correctness bugs at a chosen effort; the agent is a dispatched reviewer for convention adherence and design judgment in a finished change set. Agents are registry rows only: the routing line belongs at the dispatching skill. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation.
- **Integration:** `route`
- **Native surface:** `code-review` (bundled skill; markers: none)
- **Our component:** `review:code-reviewer` (agent)
- **Evidence:**
  - `code-review` present in the extraction as bundled-skill
  - aliases: review
  - native description: Review the current diff, or a PR number/branch/path target, for correctness bugs (plus reuse/simplification/efficiency cleanups where the model's review recipe covers them) at the given effort level (low/medium: fewer, high-confidence findings; high→max: broader coverage, may include uncertain findings…); with no level given, it reuses the level you typed last. Pass --comment to post findings as inline PR comments, or --fix to apply the findings to the working tree after the review.…
  - argument hint: […] [--fix] [--comment] [<pr#>|<branch>|<path>]
  - invocation mode (2026-09-29, Claude Code 2.1.284): model-invocable and user-invocable
  - detect: origin discovered, score 0.5822, invocable_by model+user, recommended integration route-or-wrap
  - docs cross-check (commands reference, 2026-09-29): documented
- **Observation:** extraction: extracted from binary v2.1.284 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, counts are totals) (2026-09-29)
- **Recheck trigger:** a Claude Code release changes the bundled `code-review` skill's roster entry, its `review` alias, or its invocation mode (verified 2026-09-29)
- **Baked:** description phrase no · Boundary section no · Native step no · suggest sentence no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `commit` → `source-control:commit`

- **Verdict:** `complementary`: Ours resolves the repo's commit convention (layered source-control config, project convention, Conventional Commits default) and stages surgically, never `git add -A`; the bundled skill is a generic commit workflow the model is told to use whenever it is about to commit. Both create commits, so the Boundary names which one a session takes. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation.
- **Integration:** `route`
- **Native surface:** `commit` (bundled skill; markers: gated)
- **Our component:** `source-control:commit` (skill)
- **Evidence:**
  - `commit` present in the extraction as bundled-skill
  - markers: gated
  - native description: Create a git commit. Use whenever you are about to create a commit, whether the user asked for one or it is a step in your current task - it gathers git context and applies the required commit workflow (message style, staging rules, attribution).
  - argument hint: [guidance]
  - invocation mode (2026-09-29, Claude Code 2.1.284): model-invocable and user-invocable
  - detect: origin discovered, score 0.734, invocable_by model+user, recommended integration route-or-wrap
  - docs cross-check (commands reference, 2026-09-29): undocumented
- **Observation:** extraction: extracted from binary v2.1.284 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, counts are totals) (2026-09-29)
- **Recheck trigger:** a Claude Code release renames or removes the bundled `commit` skill, changes its invocability or gating, or the commands reference starts documenting it (verified 2026-09-29)
- **Baked:** description phrase yes · Boundary section yes · Native step no · suggest sentence no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `debug` → `debugging:debug`

- **Verdict:** `complementary`: The bundled skill debugs Claude Code itself (it turns on session debug logging and reads that log) and is user-invocable only; ours debugs the user's application through a reproduction loop. Ours offers `/debug` to the person when the problem is Claude Code, not their app. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation.
- **Integration:** `suggest`
- **Native surface:** `debug` (bundled skill; markers: model-invocation-disabled)
- **Our component:** `debugging:debug` (skill)
- **Evidence:**
  - `debug` present in the extraction as bundled-skill
  - markers: model-invocation-disabled
  - native description: Enable debug logging for this session and help diagnose issues
  - argument hint: [issue description]
  - invocation mode (2026-09-29, Claude Code 2.1.284): user-invocable only, model invocation disabled
  - detect: origin discovered, score 0.6786, invocable_by user-only, recommended integration suggest
  - docs cross-check (commands reference, 2026-09-29): documented
- **Observation:** extraction: extracted from binary v2.1.284 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, counts are totals) (2026-09-29)
- **Recheck trigger:** a Claude Code release renames or removes the bundled `debug` skill, widens it beyond Claude Code's own session log, or makes it model-invocable (verified 2026-09-29)
- **Baked:** description phrase no · Boundary section yes · Native step no · suggest sentence no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `design` → `prototype:explore-directions`

- **Verdict:** `complementary`: The bundled design skill is model-invocation-disabled, so explore-directions does not route the model to it. When the intent selector lands on the HTML mockup substrate, it builds the mockup by default and tells the person they can run /design instead of or alongside it. The canvas persists under the user's account; the mockup is thrown away once the winning-variant key is captured. Same surface as the visualize row, sibling component; the Boundary section carries the suggest sentence, the split, and the mutation gate. Switched from route to suggest by operator ruling at the 2026-09-29 interview.
- **Integration:** `suggest`
- **Native surface:** `design` (bundled skill; markers: gated, model-invocation-disabled)
- **Our component:** `prototype:explore-directions` (skill)
- **Evidence:**
  - binary extraction of Claude Code 2.1.285 (2026-09-29): one bundled registration named `design`, model_invocable false (disable_model_invocation true, so the model invocation mode is user-only), user_invocable true, gated true, description unresolved; a targeted string search of the same 2.1.285 binary (2026-09-30) resolves its identity: the `design` config carries description 'Make a new Design artifact from a brief' and argument hint '[what to design]', its prompt has the model create a new Artifact from the published Artifact type titled 'Design', its `slides` sibling registers with disableModelInvocation true, the 2.1.263 canvas strings ('Draft a design on a canvas', 'Create a design canvas') no longer occur, and the claude.ai/design hub text now belongs to a separate ClaudeDesign tool, so the name answers to a user-only design-Artifact creator, not the hub
  - our Boundary: 'If /design is available in your session (gate basis: the verification record below), you can run `/design <scope>` instead of or alongside this skill for a hand-editable design canvas'; the description no longer carries a design clause
  - string search of the installed binary v2.1.263 (2026-09-11): the canvas skill registers model-invocable and user-invocable with no disableModelInvocation, enabled by a first-party-context check, a rollout flag that defaults on, and an Artifact tool whose schema carries capabilities; a second same-named Claude Design hub registration carries disableModelInvocation true behind an allow_design_sync setting (detail in the sibling visualize row and plugins/prototype/skills/explore-directions/reference/bundled-design.md)
  - commands page (2026-09-11) carries a /design row labeled Skill describing the canvas and its gates (artifacts availability, v2.1.234+); the changelog names no design-family surface through v2.1.268
  - prior: binary extraction v2.1.251 (2026-08-31) registered the canvas skill research-preview gated with no model-invocation gate; the 2.1.263 registration matches except that the rollout flag now defaults on
  - name collision (2026-09-11, Claude Code 2.1.263): the canvas registration (`registerDesignCanvasSkill`, model-invocable, no invocation-control field) is the surface this row describes; the claude.ai/design hub is a separate model-invocation-disabled registration this row does not describe; a `local` access command shares the name
- **Observation:** extraction: extracted from binary v2.1.285 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; bundled_skills lane integrity ok), refreshing the v2.1.263 targeted string search (2026-09-29)
- **Recheck trigger:** a Claude Code release makes the `design` registration model-invocable, changes its description (the identity string both Boundary offers quote), changes its gating or enablement, splits or merges its registrations, or the commands-page row stops describing the canvas (verified 2026-09-30)
- **Baked:** description phrase no · Boundary section yes · Native step no · suggest sentence yes

### `design` → `visualization:visualize`

- **Verdict:** `complementary`: The bundled design skill is model-invocation-disabled, so visualize does not route the model to it. For a hand-tweakable visual layout (UI mockup, poster, one-pager) it renders its own rich page and, where the medium permits publishing, tells the person they can run /design instead of or alongside it. The canvas is a persistent, shareable Artifact whose edits save automatically; this skill's page paths are throwaway or plain-static. The Boundary section carries the suggest sentence, the split, and the mutation gate; the catalog spoke carries the surface facts. Switched from route to suggest by operator ruling at the 2026-09-29 interview.
- **Integration:** `suggest`
- **Native surface:** `design` (bundled skill; markers: gated, model-invocation-disabled)
- **Our component:** `visualization:visualize` (skill)
- **Evidence:**
  - binary extraction of Claude Code 2.1.285 (2026-09-29): one bundled registration named `design`, model_invocable false (disable_model_invocation true, so the model invocation mode is user-only), user_invocable true, gated true, description unresolved; a targeted string search of the same 2.1.285 binary (2026-09-30) resolves its identity: the `design` config carries description 'Make a new Design artifact from a brief' and argument hint '[what to design]', its prompt has the model create a new Artifact from the published Artifact type titled 'Design', its `slides` sibling registers with disableModelInvocation true, the 2.1.263 canvas strings ('Draft a design on a canvas', 'Create a design canvas') no longer occur, and the claude.ai/design hub text now belongs to a separate ClaudeDesign tool, so the name answers to a user-only design-Artifact creator, not the hub
  - our SKILL.md Boundary: 'If /design is available in your session (gate basis: the verification record below), you can run it instead of or alongside this skill for a hand-editable design canvas'; the description and plugin.json no longer carry a design clause
  - catalog spoke plugins/visualization/skills/visualize/context/decision-matrix.md carries the canvas surface facts with their own verified-on line
  - string search of the installed binary v2.1.263 (2026-09-11): the canvas skill registers model-invocable and user-invocable (menu line 'Draft a design on a canvas Artifact, editable where saving is enabled (Claude Design preview)'; description 'Create a design canvas...'; argument hint '[what to design]'; no disableModelInvocation; enabled by a first-party-context check, a rollout flag that defaults on, and an Artifact tool whose schema carries capabilities); it is listed to the model with the canvas description in a first-party session on that build
  - string search of the same binary: a second bundled registration named design is a Claude Design hub (menu line 'Work with Claude Design (claude.ai/design): create, import, export, sync, login') with disableModelInvocation true, enabled only behind an allow_design_sync setting, a policy gate, and a feature flag; a local design consent|revoke command beside it; so the listed description is the presence check
  - commands page (2026-09-11) carries a /design row labeled Skill describing the canvas (artboards on one canvas published as an artifact running a research preview of Claude Design's editor; requires artifacts availability and v2.1.234+); the artifacts page's 'Draft a design canvas' shows /design <brief>; the changelog names no design-family surface through v2.1.268
  - prior: binary extraction v2.1.251 (2026-08-31) registered the canvas skill with a /design dispatch table and no model-invocation gate, and the rollout flag defaulted off at v2.1.234; the 2.1.263 registration matches except that the flag now defaults on
  - name collision (2026-09-11, Claude Code 2.1.263): the canvas registration (`registerDesignCanvasSkill`, model-invocable, no invocation-control field) is the surface this row describes; the claude.ai/design hub is a separate model-invocation-disabled registration this row does not describe; a `local` access command shares the name
- **Observation:** extraction: extracted from binary v2.1.285 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; bundled_skills lane integrity ok), refreshing the v2.1.263 targeted string search (2026-09-29)
- **Recheck trigger:** a Claude Code release makes the `design` registration model-invocable, changes its description (the identity string both Boundary offers quote), changes its gating or enablement, splits or merges its registrations, or the commands-page row stops describing the canvas (verified 2026-09-30)
- **Baked:** description phrase no · Boundary section yes · Native step no · suggest sentence yes

### `design-sync` → `visualization:visualize`

- **Verdict:** `defer`: Deliberately undetermined. The design-sync family (design-sync skill with disableModelInvocation, hidden design-consent/design-revoke commands managing a durable agent-access grant, design-login credential flow, DesignSync tool) is registered in the binary but documented nowhere through v2.1.251, and no operator of this marketplace uses claude.ai/design design-system projects. Real enough to record next to the canvas integration it ships beside; too thin to rule on, and design-system sync is publishing, not visualization, so no integration text ships anywhere.
- **Integration:** `route`
- **Native surface:** `design-sync` (bundled skill; markers: gated, model-invocation-disabled)
- **Our component:** `visualization:visualize` (skill)
- **Evidence:**
  - binary extraction v2.1.251 (2026-08-31): design-sync registered with disableModelInvocation true; design-consent/design-revoke registered as hidden commands ('Grant/Revoke Claude agent access to your Design projects'); design-login flow strings present
  - docs and changelog through v2.1.251 carry none of the four names (checked 2026-08-31)
  - no claude.ai/design usage among this marketplace's operators (user-confirmed 2026-09-01)
- **Observation:** extraction: extracted from binary v2.1.251 at node_modules/@anthropic-ai/claude-code/bin/claude.exe (design-family registrations read from the bundle strings) (2026-08-31)
- **Recheck trigger:** a Claude Code release documents any of design-sync/design-consent/design-revoke/design-login, or an operator of this marketplace adopts claude.ai/design design-system projects (verified 2026-09-01)
- **Baked:** description phrase no · Boundary section no · Native step no · suggest sentence no

### `doc` → `docs-hygiene:write-for-humans`

- **Verdict:** `defer`: Deferred: the bundled skill is gated on Artifact availability and undocumented. It publishes an editable team document artifact (memo, proposal, spec); ours writes human-facing prose files in the repository under the project style guide. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation.
- **Integration:** `route`
- **Native surface:** `doc` (bundled skill; markers: gated)
- **Our component:** `docs-hygiene:write-for-humans` (skill)
- **Evidence:**
  - `doc` present in the extraction as bundled-skill
  - markers: gated
  - native description: Create a document artifact - a working document that looks and edits like a word processor page, published for the team to read and edit in place - a memo, proposal, plan, spec, or meeting notes. Use when the user wants a document others will read or weigh in on, rather than a chat reply, a local file, or a finished report meant to be read top-to-bottom. - Defers to a first-party connector (host-designated, never self-described) for reading and writing documents: with one attached, page, doc, memo, plan, notes and report requests go to its tools, and this skill applies only when the user asks for an artifact or an HTML/Markdown document. Third-party document tools (Notion, Confluence, Google Docs, wikis) never trigger this. Only for CREATING a new artifact; edits to an existing artifact modify its HTML directly.
  - invocation mode (2026-09-29, Claude Code 2.1.284): model-invocable and user-invocable
  - detect: origin discovered, score 0.3196, invocable_by model+user, recommended integration route-or-wrap
  - docs cross-check (commands reference, 2026-09-29): undocumented
- **Observation:** extraction: extracted from binary v2.1.284 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, counts are totals) (2026-09-29)
- **Recheck trigger:** a Claude Code release ungates the bundled `doc` skill, the commands reference documents it, or a live roster capture protocol exists for Artifact-gated skills (verified 2026-09-29)
- **Baked:** description phrase no · Boundary section no · Native step no · suggest sentence no

### `doctor` → `claude-config:audit-instructions`

- **Verdict:** `complementary`: `/doctor prompt-audit` (added 2.1.283) audits CLAUDE.md files, skills, agents and commands for prompting patterns; ours audits standing instructions for over-prescription, misstated Claude Code behavior, and cross-surface drift, report-only. Model invocation is disabled on the native side, so ours suggests it. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation.
- **Integration:** `suggest`
- **Native surface:** `doctor` (bundled skill; markers: gated, model-invocation-disabled)
- **Our component:** `claude-config:audit-instructions` (skill)
- **Evidence:**
  - `doctor` present in the extraction as bundled-skill
  - markers: gated, model-invocation-disabled
  - aliases: checkup
  - native description: Health-check the user's Claude Code setup and fix issues: diagnose installation health - what the `claude doctor` terminal diagnostics cover - from local data (duplicate or leftover installs, PATH, unparsable settings files, broken or colliding agent definitions, skills whose frontmatter fails to parse); find unused skills, MCP servers, and plugins versus their context cost and disable dead weight; deduplicate local CLAUDE.md files against checked-in ones; trim checked-in CLAUDE.md files by cutting content a session could derive from the codebase (directory layouts, tech-stack lists, architecture overviews) while keeping gotchas, rationale, and non-standard conventions; migrate always-loaded CLAUDE.md guidance into lazy skills and nested CLAUDE.md files; flag slow hooks and context-heavy extensions; check the installed version is current; make auto mode the default permission mode; and pre-approve frequently denied read-only commands. Use when the user asks for a doctor run, checkup, audit, tune-up, or cleanup of their Claude Code setup or configuration.
  - argument hint: [prompt-audit [<path>]]
  - invocation mode (2026-09-29, Claude Code 2.1.284): user-invocable only, model invocation disabled
  - detect: human-added pair, not emitted at threshold 0.30 / top-k 3 (discovery score 0.0565)
  - docs cross-check (commands reference, 2026-09-29): documented
- **Observation:** extraction: extracted from binary v2.1.284 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, counts are totals) (2026-09-29)
- **Recheck trigger:** a Claude Code release changes the `prompt-audit` subcommand of `/doctor`, the skill's alias or gating, or lets the model invoke it (verified 2026-09-29)
- **Baked:** description phrase no · Boundary section yes · Native step no · suggest sentence no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `doctor` → `claude-ops:audit-install-state`

- **Verdict:** `complementary`: Bundled `doctor` is the quick native health-and-fix pass over an installation, and it offers to fix, which puts it outside the read-only contract audit-install-state holds. audit-install-state is the deep read-only inventory of the install tree: every file classified, product-managed retention separated from genuinely unmanaged state, filename schemes resolved before any liveness check, and a deliberate-or-experimental state detected before anything is called stale. Prefer the native pass for a fast check; ours when the question is what is actually in the tree and what nothing manages.
- **Integration:** `suggest`
- **Native surface:** `doctor` (bundled skill; markers: gated, model-invocation-disabled)
- **Our component:** `claude-ops:audit-install-state` (skill)
- **Evidence:**
  - `doctor` present in the extraction as bundled-skill
  - markers: gated
  - aliases: checkup
  - native description: Health-check your setup and fix issues: installation, unused extensions, duplicated or bloated memory files, slow hooks, updates, permissions
  - the native surface offers to fix; audit-install-state is report-only by contract and never writes to the target tree
  - invocation mode (2026-09-11, Claude Code 2.1.263): model-invocation-disabled (`disableModelInvocation`, survives `disableBundledSkills`); the Skill tool does not list it
- **Observation:** extraction: extracted from binary v2.1.284 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, counts are totals) (2026-09-29)
- **Recheck trigger:** a Claude Code release changes `/doctor`'s status as a bundled skill or its gating switch. It became a bundled skill at 2.1.205, which retargeted DISABLE_DOCTOR_COMMAND, and it is the one bundled skill `disableBundledSkills` does not remove (verified 2026-09-29)
- **Baked:** description phrase no · Boundary section yes · Native step no · suggest sentence yes

### `doctor` → `claude-ops:audit-performance`

- **Verdict:** `complementary`: Same native surface, a different one of our lanes. audit-performance is a timed diagnostic capture taken at the moment something feels slow: CLI version, retention-sweep health, a timed stat-walk standing in for the product's own sweep cost, session and plugin-fleet counts, and a process census, all interpreted against a bundled known-issues reference. Bundled `doctor` reports health and offers fixes; it does not capture a timed slowness profile. Complementary by construction: this skill never reads transcripts, and `/doctor` does. Body-level compose row only (capture first, `/doctor` second); the routing sentence for the shared surface lives in audit-install-state.
- **Integration:** `suggest`
- **Native surface:** `doctor` (bundled skill; markers: gated, model-invocation-disabled)
- **Our component:** `claude-ops:audit-performance` (skill)
- **Evidence:**
  - `doctor` present in the extraction as bundled-skill
  - markers: gated
  - native description: Health-check your setup and fix issues: installation, unused extensions, duplicated or bloated memory files, slow hooks, updates, permissions
  - our description: read-only slowness-diagnostic capture run AT THE MOMENT the machine or a session feels slow, before restarting or deleting anything
  - invocation mode (2026-09-11, Claude Code 2.1.263): model-invocation-disabled (`disableModelInvocation`, survives `disableBundledSkills`); the Skill tool does not list it
- **Observation:** extraction: extracted from binary v2.1.284 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, counts are totals) (2026-09-29)
- **Recheck trigger:** a Claude Code release gives `/doctor` a timed or profiling mode, or changes its status as a bundled skill, or this skill's Never-read rule stops covering transcripts (the engine gains a transcript read) (verified 2026-09-29)
- **Baked:** description phrase no · Boundary section yes · Native step no · suggest sentence yes

### `doctor` → `claude-ops:audit-skill-visibility`

- **Verdict:** `complementary`: Same native surface as the two sibling rows, a third of our lanes. Bundled `doctor` ships a one-shot check (its Check 1) that groups unused skills, MCP servers, and plugins against their context cost, labels each group with a token-savings estimate, and offers to disable the selected groups. audit-skill-visibility answers a different question, why a skill is unseen: it reconciles three usage sources (native ~/.claude.json counters, its own JSONL store, OTEL) under a max-across-sources rule, computes an observed horizon and withholds every verdict the span cannot support, diagnoses reachability causes, and analyses listing-budget starvation. It disables nothing by contract. The skill's own description and Scope boundary already route the one-shot unused-versus-context-cost question to the native surface; this row records that routing in the store rather than replacing it.
- **Integration:** `suggest`
- **Native surface:** `doctor` (bundled skill; markers: gated, model-invocation-disabled)
- **Our component:** `claude-ops:audit-skill-visibility` (skill)
- **Evidence:**
  - `doctor` present in the 2026-08-23 extraction as bundled-skill (markers: gated; aliases: checkup), per the two sibling rows
  - the shipped doctor skill carries a check titled 'Check 1: unused skills, MCP servers, and plugins' whose prompt groups unused components, labels each group with a benefit estimate ('37 unused skills, saves ~2.2k est. tokens/session'), and applies only the groups the user selects; confirmed by string search of the installed v2.1.252 binary on 2026-08-31
  - string search of the installed v2.1.284 binary (2026-09-29): the strings are present, spelled with an em dash where the v2.1.252 quotes above use a colon and a comma: the heading 'Check 1 (em dash) unused skills, MCP servers, and plugins', and a 'Let me pick' follow-up whose option labels are 'a short name plus the benefit' (example '37 unused skills (em dash) saves ~2.2k est. tokens/session'), after which only the selected groups are applied. A per-item remove verdict and the disable mechanics are present too, so Check 1's grouping, disable offer, and benefit estimate are confirmed at this build
  - our description: audit whether each installed skill is actually VISIBLE to the model; reconciles native counters, a JSONL store, and OTEL; withholds every verdict the data cannot support; read-only, never disables, deletes, or edits a skill
  - our description's Not-for clause and the SKILL.md Scope boundary table both already name the native surface ('Claude Code ships that in /doctor and the Stats tab') with no store row behind them until this one; a prose disclaimer without a store row is the drift this registry exists to catch
  - recheck trigger fired 2026-09-04 and is discharged as of 2026-09-07: /skill-doctor now has its own row in this store, pinned to the upstream commit that added it, so this row is scoped back to /doctor alone and no longer stands in for two surfaces
  - this row's routing survives the split: the /doctor row of https://code.claude.com/docs/en/commands.md still credits the bundled doctor skill with finding 'unused skills, MCP servers, and plugins versus their context cost' inside its setup checkup, so the deferral recorded here is to a surface that still does the job (read 2026-09-07)
  - invocation mode (2026-09-11, Claude Code 2.1.263): model-invocation-disabled (`disableModelInvocation`, survives `disableBundledSkills`); the Skill tool does not list it
- **Observation:** extraction: extracted from binary v2.1.284 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, counts are totals) (2026-09-29)
- **Recheck trigger:** a Claude Code release changes doctor's unused-components check (Check 1's grouping, its disable offer, or its benefit estimate), gives it a multi-source reconciliation or observation-horizon discipline, or changes /doctor's status as a bundled skill or its gating switch (verified 2026-09-29)
- **Baked:** description phrase no · Boundary section yes · Native step no · suggest sentence yes

### `explain-usage` → `claude-ops:observability`

- **Verdict:** `complementary`: The bundled skill explains where the current session's tokens went in one chart; ours reads locally captured telemetry for cross-session trends, hook latency, and cost. Session snapshot versus captured history. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation.
- **Integration:** `route`
- **Native surface:** `explain-usage` (bundled skill; markers: gated)
- **Our component:** `claude-ops:observability` (skill)
- **Evidence:**
  - `explain-usage` present in the extraction as bundled-skill
  - markers: gated
  - native description: Explain where this session's tokens went, with one simple chart in plain language. Use when: explain usage, explain my usage, where did my tokens go, token usage breakdown, what used the most tokens.
  - invocation mode (2026-09-29, Claude Code 2.1.284): model-invocable and user-invocable
  - detect: origin seeded, score 0.0951, invocable_by model+user, recommended integration route-or-wrap
  - docs cross-check (commands reference, 2026-09-29): undocumented
- **Observation:** extraction: extracted from binary v2.1.284 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, counts are totals) (2026-09-29)
- **Recheck trigger:** a Claude Code release renames or removes the bundled `explain-usage` skill, widens it beyond the current session, or changes its gating (verified 2026-09-29)
- **Baked:** description phrase yes · Boundary section yes · Native step no · suggest sentence no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `explain-usage` → `context-budget:audit`

- **Verdict:** `complementary`: The bundled skill explains after the fact where the current session's tokens went; ours measures startup context per item with a before/after ledger. Where the session spent versus what loads before it starts. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation.
- **Integration:** `route`
- **Native surface:** `explain-usage` (bundled skill; markers: gated)
- **Our component:** `context-budget:audit` (skill)
- **Evidence:**
  - `explain-usage` present in the extraction as bundled-skill
  - markers: gated
  - native description: Explain where this session's tokens went, with one simple chart in plain language. Use when: explain usage, explain my usage, where did my tokens go, token usage breakdown, what used the most tokens.
  - invocation mode (2026-09-29, Claude Code 2.1.284): model-invocable and user-invocable
  - detect: origin seeded, score 0.0698, invocable_by model+user, recommended integration route-or-wrap
  - docs cross-check (commands reference, 2026-09-29): undocumented
- **Observation:** extraction: extracted from binary v2.1.284 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, counts are totals) (2026-09-29)
- **Recheck trigger:** a Claude Code release renames or removes the bundled `explain-usage` skill, adds startup or per-tool attribution to it, or changes its gating (verified 2026-09-29)
- **Baked:** description phrase yes · Boundary section yes · Native step no · suggest sentence no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `fewer-permission-prompts` → `claude-config:audit-permission-state`

- **Verdict:** `complementary`: The bundled skill writes a prioritized allowlist into project .claude/settings.json from transcript evidence; ours reports the effective permission state, read-only. One writes rules, the other reports what is in effect. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation.
- **Integration:** `route`
- **Native surface:** `fewer-permission-prompts` (bundled skill; markers: none)
- **Our component:** `claude-config:audit-permission-state` (skill)
- **Evidence:**
  - `fewer-permission-prompts` present in the extraction as bundled-skill
  - native description: Scan your transcripts for common read-only Bash and MCP tool calls, then add a prioritized allowlist to project .claude/settings.json to reduce permission prompts.
  - invocation mode (2026-09-29, Claude Code 2.1.284): model-invocable and user-invocable
  - detect: origin seeded, score 0.2718, invocable_by model+user, recommended integration route-or-wrap
  - docs cross-check (commands reference, 2026-09-29): documented
- **Observation:** extraction: extracted from binary v2.1.284 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, counts are totals) (2026-09-29)
- **Recheck trigger:** a Claude Code release renames or removes the bundled `fewer-permission-prompts` skill, changes what it writes, or changes its invocability (verified 2026-09-29)
- **Baked:** description phrase yes · Boundary section yes · Native step no · suggest sentence no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `pr` → `source-control:pull-request`

- **Verdict:** `complementary`: Ours runs the full pull-request lifecycle (prep, draft, ready, monitor, merge, CI logs) under the repo's PR contract; the bundled skill creates one PR generically. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation.
- **Integration:** `route`
- **Native surface:** `pr` (bundled skill; markers: gated)
- **Our component:** `source-control:pull-request` (skill)
- **Evidence:**
  - `pr` present in the extraction as bundled-skill
  - markers: gated
  - native description: Create a GitHub pull request. Use whenever you are about to open a PR, whether the user asked for one or it is a step in your current task - it gathers branch context and applies the required PR workflow (gh CLI, title/body format, attribution).
  - argument hint: [guidance]
  - invocation mode (2026-09-29, Claude Code 2.1.284): model-invocable and user-invocable
  - detect: origin discovered, score 0.5095, invocable_by model+user, recommended integration route-or-wrap
  - docs cross-check (commands reference, 2026-09-29): undocumented
- **Observation:** extraction: extracted from binary v2.1.284 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, counts are totals) (2026-09-29)
- **Recheck trigger:** a Claude Code release renames or removes the bundled `pr` skill, changes its invocability or gating, or the commands reference starts documenting it (verified 2026-09-29)
- **Baked:** description phrase yes · Boundary section yes · Native step no · suggest sentence no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `prototype` → `prototype:explore-directions`

- **Verdict:** `defer`: Deferred: the bundled skill is gated, so its presence is not determinable from this session's evidence. It publishes a single proof-of-concept Artifact; ours builds switchable throwaway layout variants on the real stack. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation.
- **Integration:** `route`
- **Native surface:** `prototype` (bundled skill; markers: gated)
- **Our component:** `prototype:explore-directions` (skill)
- **Evidence:**
  - `prototype` present in the extraction as bundled-skill
  - markers: gated
  - native description: Turn an idea into a working proof of concept and publish it as an Artifact - a single self-contained page the user can open, click through, and react to. Run a short intake, state your assumptions, build, then iterate on feedback in the same artifact. Use when the user asks to prototype an idea, mock up a concept, build a proof of concept, or wants to see something working before committing to a real build - including, on an explicit ask, a new feature shown in place on an app they already have.
  - invocation mode (2026-09-29, Claude Code 2.1.284): model-invocable and user-invocable
  - detect: origin discovered, score 0.3625, invocable_by model+user, recommended integration route-or-wrap
  - docs cross-check (commands reference, 2026-09-29): undocumented
- **Observation:** extraction: extracted from binary v2.1.284 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, counts are totals) (2026-09-29)
- **Recheck trigger:** a Claude Code release ungates the bundled `prototype` skill, the commands reference documents it, or a live roster capture protocol exists for gated skills (verified 2026-09-29)
- **Baked:** description phrase no · Boundary section no · Native step no · suggest sentence no

### `prototype` → `prototype:pressure-test`

- **Verdict:** `defer`: Deferred: the bundled skill is gated, so its presence is not determinable from this session's evidence. It publishes a clickable proof-of-concept Artifact; ours builds a throwaway terminal app or HTML demo to pressure-test logic and state. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation.
- **Integration:** `route`
- **Native surface:** `prototype` (bundled skill; markers: gated)
- **Our component:** `prototype:pressure-test` (skill)
- **Evidence:**
  - `prototype` present in the extraction as bundled-skill
  - markers: gated
  - native description: Turn an idea into a working proof of concept and publish it as an Artifact - a single self-contained page the user can open, click through, and react to. Run a short intake, state your assumptions, build, then iterate on feedback in the same artifact. Use when the user asks to prototype an idea, mock up a concept, build a proof of concept, or wants to see something working before committing to a real build - including, on an explicit ask, a new feature shown in place on an app they already have.
  - invocation mode (2026-09-29, Claude Code 2.1.284): model-invocable and user-invocable
  - detect: origin discovered, score 0.3661, invocable_by model+user, recommended integration route-or-wrap
  - docs cross-check (commands reference, 2026-09-29): undocumented
- **Observation:** extraction: extracted from binary v2.1.284 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, counts are totals) (2026-09-29)
- **Recheck trigger:** a Claude Code release ungates the bundled `prototype` skill, the commands reference documents it, or a live roster capture protocol exists for gated skills (verified 2026-09-29)
- **Baked:** description phrase no · Boundary section no · Native step no · suggest sentence no

### `run` → `testing:run-e2e`

- **Verdict:** `complementary`: The bundled skill answers 'did this change work when I ran the app'; run-e2e drives named UI and API flows, captures evidence (screenshots, responses, logs), and carries a non-UI smoke playbook for libraries, MCP servers, hooks, and scripts, none of which have an app to launch. Prefer the native surface for the quick look; ours where the verification has to be reproducible or the target is not an app.
- **Integration:** `wrap`
- **Native surface:** `run` (bundled skill; markers: none)
- **Our component:** `testing:run-e2e` (skill)
- **Evidence:**
  - `run` present in the extraction as bundled-skill
  - native description: Launch this project's app to see your change working
  - our description: End-to-end live app verification. Check prerequisites, start the app, drive UI/API flows, and capture evidence; includes a non-UI smoke-test playbook
  - the non-UI smoke lane has no native counterpart in this extraction
  - invocation mode (2026-09-11, Claude Code 2.1.263): model-invocable (no invocation-control field); a project skill named run is a legitimate target the bundled skill itself defers to
- **Observation:** extraction: extracted from binary v2.1.284 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, counts are totals) (2026-09-29)
- **Recheck trigger:** a Claude Code release changes the bundled `run` skill's roster entry or invocation mode, or gives it an evidence-capture or non-app target mode (verified 2026-09-11)
- **Baked:** description phrase yes · Boundary section yes · Native step yes · suggest sentence no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `simplify` → `code-tidying:batch-simplify`

- **Verdict:** `complementary`: Scale is the whole difference. The bundled skill handles the change in front of it; batch-simplify fans the same job across a time- or branch-scoped window of changed files, grouped by ecosystem and dependency order, for the catch-up case after a multi-session sprint. Its description already sends single-file cleanup to the native surface.
- **Integration:** `wrap`
- **Native surface:** `simplify` (bundled skill; markers: none)
- **Our component:** `code-tidying:batch-simplify` (skill)
- **Evidence:**
  - `simplify` present in the extraction as bundled-skill
  - native description: Clean up the changed code without changing behavior
  - our description already carries `Skip for single-file cleanup. Use /simplify instead`
  - seeded rationale: same cleanup job at batch scale across many files
  - invocation mode (2026-09-11, Claude Code 2.1.263): model-invocable (no invocation-control field); takes a [<target>] argument so a wrap scopes it per file set
- **Observation:** extraction: extracted from binary v2.1.284 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, counts are totals) (2026-09-29)
- **Recheck trigger:** a Claude Code release gives the bundled `simplify` skill a time-window argument form, a repository mode, or ecosystem grouping (the multi-file half of this trigger fired by 2026-09-11: the skill accepts a path or PR reference target, so the remaining distinction is the sweep discipline, recorded in the skill's context/bundled-simplify.md) (verified 2026-09-11)
- **Baked:** description phrase yes · Boundary section yes · Native step yes · suggest sentence no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `simplify` → `code-tidying:tidy`

- **Verdict:** `complementary`: Different trigger, not a different job. The bundled skill refines the code a change already touched; tidy proactively hunts unfiled structural drift across a rotated, glob-scoped lane and ships one structure-only PR per invocation. tidy's own description already routes current-diff work away to the native surface, which is the routing this row records rather than replaces.
- **Integration:** `route`
- **Native surface:** `simplify` (bundled skill; markers: none)
- **Our component:** `code-tidying:tidy` (skill)
- **Evidence:**
  - `simplify` present in the extraction as bundled-skill
  - native description: Clean up the changed code without changing behavior
  - our description already carries `Skip when: /simplify refines the current diff`
  - seeded rationale: both clean up code without changing behavior
- **Observation:** extraction: extracted from binary v2.1.284 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, counts are totals) (2026-09-29)
- **Recheck trigger:** a Claude Code release adds, removes, or changes the invocation mode of the bundled `simplify` skill, or the skill gains a lane-scoped mode that overlaps tidy's proactive hunt (verified 2026-09-11)
- **Baked:** description phrase yes · Boundary section yes · Native step no · suggest sentence no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `update-config` → `claude-config:audit`

- **Verdict:** `complementary`: The bundled skill writes settings.json on request (hooks, permissions, env vars); ours audits configuration for correctness, security, and drift, report-only unless --fix. Make a change versus audit what exists. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation.
- **Integration:** `route`
- **Native surface:** `update-config` (bundled skill; markers: none)
- **Our component:** `claude-config:audit` (skill)
- **Evidence:**
  - `update-config` present in the extraction as bundled-skill
  - native description: Use this skill to configure the Claude Code harness via settings.json. Automated behaviors ("from now on when X", "each time X", "whenever X", "before/after X") require hooks configured in settings.json - the harness executes these, not Claude, so memory/preferences cannot fulfill them. Also use for: permissions ("allow X", "add permission", "move permission to"), env vars ("set X=Y"), hook troubleshooting, or any changes to settings.json/settings.local.json files. Examples: "allow npm commands", "add bq permission to global settings", "move permission to user settings", "set DEBUG=true", "when claude stops show X". For simple settings like theme/model, suggest the /config command.
  - invocation mode (2026-09-29, Claude Code 2.1.284): model-invocable and user-invocable
  - detect: human-added pair, not emitted at threshold 0.30 / top-k 3 (discovery score 0.2957)
  - docs cross-check (commands reference, 2026-09-29): documented
- **Observation:** extraction: extracted from binary v2.1.284 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, counts are totals) (2026-09-29)
- **Recheck trigger:** a Claude Code release renames or removes the bundled `update-config` skill, changes what it writes, or changes its invocability (verified 2026-09-29)
- **Baked:** description phrase yes · Boundary section yes · Native step no · suggest sentence no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `verify` → `verification:confirm`

- **Verdict:** `complementary`: The bundled skill exercises a change end to end and observes behavior, bootstrapping a project verify skill when none exists; ours runs the mechanical prerequisite and then outcome verification against the plan or intent by change type. Its registration disables model invocation, so ours suggests it. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation.
- **Integration:** `suggest`
- **Native surface:** `verify` (bundled skill; markers: model-invocation-disabled)
- **Our component:** `verification:confirm` (skill)
- **Evidence:**
  - `verify` present in the extraction as bundled-skill
  - markers: model-invocation-disabled
  - native description: Verify that a code change actually does what it's supposed to by exercising it end-to-end and observing behavior - drive the affected flow, not just tests or typecheck. Run before committing nontrivial changes; bootstraps this repo's project verify skill if none exists yet. Don't invoke it on a diff that only touches tests, docs, or other code with no runtime surface to drive (a change to product source always has one) - there's nothing to observe.
  - invocation mode (2026-09-29, Claude Code 2.1.284): user-invocable only, model invocation disabled (`model_invocable` undetermined at this build, `disable_model_invocation: true` read instead)
  - detect: origin discovered, score 0.3204, invocable_by user-only, recommended integration suggest
  - docs cross-check (commands reference, 2026-09-29): documented
- **Observation:** extraction: extracted from binary v2.1.284 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, counts are totals) (2026-09-29)
- **Recheck trigger:** a Claude Code release renames or removes the bundled `verify` skill, changes what it bootstraps, or makes it model-invocable (verified 2026-09-29)
- **Baked:** description phrase no · Boundary section yes · Native step no · suggest sentence no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

## Bundled workflows

### `deep-research` → `discovery:research-deep`

- **Verdict:** `complementary`: The bundled workflow is a fan-out web research harness (scope, search, fetch, verify, synthesize) producing a cited report; ours dispatches multi-topic research to the heaviest isolated tier with source tiers and a coverage ledger. Its registration disables model invocation, so ours suggests it. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation.
- **Integration:** `suggest`
- **Native surface:** `deep-research` (bundled workflow; markers: model-invocation-disabled)
- **Our component:** `discovery:research-deep` (skill)
- **Evidence:**
  - `deep-research` present in the extraction as bundled-workflow
  - markers: model-invocation-disabled
  - native description: Deep research harness - fan-out web searches, fetch sources, adversarially verify claims, synthesize a cited report.
  - invocation mode (2026-09-29, Claude Code 2.1.284): user-invocable only, model invocation disabled (`model_invocable` undetermined at this build, `disable_model_invocation: true` read instead)
  - detect: origin discovered, score 0.7023, invocable_by user-only, recommended integration suggest
  - docs cross-check (commands reference, 2026-09-29): documented
- **Observation:** extraction: extracted from binary v2.1.284 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, counts are totals) (2026-09-29)
- **Recheck trigger:** a Claude Code release renames or removes the bundled `deep-research` workflow, changes its phases, or makes it model-invocable (verified 2026-09-29)
- **Baked:** description phrase no · Boundary section yes · Native step no · suggest sentence no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

## Plugin-backed built-ins

### `security-review` → `review:security-review`

- **Verdict:** `complementary`: The native side is not a bundled skill at all. The extraction reports it under `plugin_backed`, backed by the `security-review` plugin, and it runs in-session over the change at hand. review:security-review is the CI lane a reusable workflow invokes for a pull request, targeting logic, trust-boundary, and Actions findings static analysis misses. Reading the wrong extraction key is the failure this row exists to prevent: under `builtin_commands` the surface looks absent. The row stays route because the CI lane runs a pinned workflow in another repository whose tool roster this repository does not control, and the native command diffs against `origin/HEAD`, which that checkout does not provide. `allowed-tools` does not decide reach.
- **Integration:** `route`
- **Native surface:** `security-review` (plugin-backed built-in; markers: none)
- **Our component:** `review:security-review` (skill)
- **Evidence:**
  - `security-review` present in the extraction as plugin-backed-builtin
  - the extraction's `plugin_backed` map reports {"security-review": "security-review"}; the name appears in neither `builtin_commands` nor `bundled_skills`
  - our description: CI security-review lane for a GitHub pull request. Logic, trust-boundary, and Actions security findings static analysis misses
- **Observation:** extraction: extracted from binary v2.1.284 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, counts are totals; `security-review` read in the plugin_backed lane) (2026-09-29)
- **Recheck trigger:** an extraction stops reporting `security-review` under `plugin_backed`: it moves into the bundled-skill or built-in-command lane, or its backing plugin name changes (re-verified 2026-09-11: the installed 2.1.263 binary registers it plugin-backed and the commands page gives the row no Skill label; the skill's reference/bundled-security-review.md carries the record) (verified 2026-09-11)
- **Baked:** description phrase yes · Boundary section yes · Native step no · suggest sentence no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `security-review` → `review:security-reviewer`

- **Verdict:** `complementary`: The plugin-backed built-in analyzes the current branch's changes for security vulnerabilities in a session; the agent is a dispatched cross-ecosystem security reviewer for logic flaws and architectural gaps. Agents are registry rows only: the routing line belongs at the dispatching skill. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation.
- **Integration:** `route`
- **Native surface:** `security-review` (plugin-backed built-in; markers: none)
- **Our component:** `review:security-reviewer` (agent)
- **Evidence:**
  - `security-review` present in the extraction as plugin-backed-builtin
  - invocation mode (2026-09-29, Claude Code 2.1.284): not recorded by the extraction for this lane
  - detect: origin discovered, score 0.8379, invocable_by unknown, recommended integration None
  - docs cross-check (commands reference, 2026-09-29): documented
- **Observation:** extraction: extracted from binary v2.1.284 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, counts are totals) (2026-09-29)
- **Recheck trigger:** a Claude Code release moves `security-review` out of the plugin-backed lane, renames it, or changes what it reviews (verified 2026-09-29)
- **Baked:** description phrase no · Boundary section no · Native step no · suggest sentence no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

## Built-in subagents

### `Explore` → `discovery:explore`

- **Verdict:** `complementary`: The built-in agent locates code and returns excerpts, one-shot and convention-blind; ours runs a persisted, resumable exploration that writes EXPLORE.md, and uses the built-in agent as its locate-tier scout. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation.
- **Integration:** `route`
- **Native surface:** `Explore` (built-in subagent; markers: gated)
- **Our component:** `discovery:explore` (skill)
- **Evidence:**
  - `Explore` present in the extraction as builtin-agent
  - markers: gated
  - native description: Fast read-only search agent for locating code. Use it to find files by pattern (eg. "src/components/**/*.tsx"), grep for symbols or keywords (eg. "API endpoints"), or answer "where is X defined / which files reference Y." Do NOT use it for code review, design-doc auditing, cross-file consistency checks, or open-ended analysis — it reads excerpts rather than whole files and will miss content past its read window. When calling, specify search breadth: "quick" for a single targeted lookup, "medium" for moderate exploration, or "very thorough" to search across multiple locations and naming conventions. <!-- ai-slop-ignore: verbatim native text -->
  - disallowed tools: Agent, Artifact, ArtifactComments, ArtifactData, ArtifactCheck, ExitPlanMode, Edit, Write, NotebookEdit; omits CLAUDE.md
  - invocation mode (2026-09-29, Claude Code 2.1.285): model-invocable and user-invocable; roster conditional
  - detect: origin discovered, score 0.5706, invocable_by model+user, recommended integration route
  - docs cross-check (sub-agents page, 2026-09-29): documented as a built-in subagent; removable with CLAUDE_CODE_DISABLE_EXPLORE_PLAN_AGENTS
- **Observation:** extraction: extracted from binary v2.1.285 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, degraded overall only because 2.1.285 is past the extractor's last validated build 2.1.284, so counts are floors) (2026-09-29)
- **Recheck trigger:** a Claude Code release renames or removes the built-in `Explore` agent, lets it write files or read CLAUDE.md, or changes its gating (verified 2026-09-29)
- **Baked:** description phrase no · Boundary section yes · Native step no · suggest sentence no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `Explore` → `discovery:explorer`

- **Verdict:** `complementary`: The built-in agent locates code and returns excerpts; this agent runs the full /discovery:explore workflow and persists EXPLORE.md. Agents are registry rows only: the routing line belongs at the dispatching skill, /discovery:explore. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation.
- **Integration:** `route`
- **Native surface:** `Explore` (built-in subagent; markers: gated)
- **Our component:** `discovery:explorer` (agent)
- **Evidence:**
  - `Explore` present in the extraction as builtin-agent
  - markers: gated
  - native description: Fast read-only search agent for locating code. Use it to find files by pattern (eg. "src/components/**/*.tsx"), grep for symbols or keywords (eg. "API endpoints"), or answer "where is X defined / which files reference Y." Do NOT use it for code review, design-doc auditing, cross-file consistency checks, or open-ended analysis — it reads excerpts rather than whole files and will miss content past its read window. When calling, specify search breadth: "quick" for a single targeted lookup, "medium" for moderate exploration, or "very thorough" to search across multiple locations and naming conventions. <!-- ai-slop-ignore: verbatim native text -->
  - invocation mode (2026-09-29, Claude Code 2.1.285): model-invocable and user-invocable; roster conditional
  - detect: origin discovered, score 0.6029, invocable_by model+user, recommended integration route
  - docs cross-check (sub-agents page, 2026-09-29): documented as a built-in subagent
- **Observation:** extraction: extracted from binary v2.1.285 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, degraded overall only because 2.1.285 is past the extractor's last validated build 2.1.284, so counts are floors) (2026-09-29)
- **Recheck trigger:** a Claude Code release renames or removes the built-in `Explore` agent, lets it write files, or changes its gating (verified 2026-09-29)
- **Baked:** description phrase no · Boundary section no · Native step no · suggest sentence no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `Plan` → `planning:plan`

- **Verdict:** `complementary`: The built-in agent returns a read-only implementation approach to its caller and cannot write files; ours produces a stress-tested, approval-gated plan persisted as PLAN.md for a cleared session. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation.
- **Integration:** `route`
- **Native surface:** `Plan` (built-in subagent; markers: gated)
- **Our component:** `planning:plan` (skill)
- **Evidence:**
  - `Plan` present in the extraction as builtin-agent
  - markers: gated
  - native description: Software architect agent for designing implementation plans. Use this when you need to plan the implementation strategy for a task. Returns step-by-step plans, identifies critical files, and considers architectural trade-offs.
  - disallowed tools: Agent, Artifact, ArtifactComments, ArtifactData, ArtifactCheck, ExitPlanMode, Edit, Write, NotebookEdit; omits CLAUDE.md
  - invocation mode (2026-09-29, Claude Code 2.1.285): model-invocable and user-invocable; roster conditional
  - detect: origin discovered, score 0.6849, invocable_by model+user, recommended integration route
  - docs cross-check (sub-agents page, 2026-09-29): documented as a built-in subagent used during plan mode to gather context before presenting a plan
- **Observation:** extraction: extracted from binary v2.1.285 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, degraded overall only because 2.1.285 is past the extractor's last validated build 2.1.284, so counts are floors) (2026-09-29)
- **Recheck trigger:** a Claude Code release renames or removes the built-in `Plan` agent, lets it write files, or changes its gating (verified 2026-09-29)
- **Baked:** description phrase no · Boundary section yes · Native step no · suggest sentence no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

## Built-in tools

### `WebFetch` → `firecrawl:firecrawl`

- **Verdict:** `complementary`: The built-in tool fetches one unprotected page and returns a small model's extraction inline; ours scrapes, crawls, or renders pages WebFetch cannot reach (anti-bot, JS) and writes the full content to disk. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation.
- **Integration:** `route`
- **Native surface:** `WebFetch` (built-in tool; markers: gated)
- **Our component:** `firecrawl:firecrawl` (skill)
- **Evidence:**
  - `WebFetch` present in the extraction as builtin-tool
  - markers: gated
  - search hint: fetch and extract content from a URL
  - invocation mode (2026-09-29, Claude Code 2.1.285): model-invocable, not user-invocable; deferred (loads through tool search)
  - detect: human-added pair, not emitted at threshold 0.30 / top-k 3 (discovery score 0.1829)
  - docs cross-check (tools reference, 2026-09-29): documented
- **Observation:** extraction: extracted from binary v2.1.285 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, degraded overall only because 2.1.285 is past the extractor's last validated build 2.1.284, so counts are floors) (2026-09-29)
- **Recheck trigger:** a Claude Code release renames or removes the built-in `WebFetch` tool, stops returning a model extraction in place of the page, or gains JS rendering (verified 2026-09-29)
- **Baked:** description phrase no · Boundary section yes · Native step no · suggest sentence no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `WebSearch` → `firecrawl:firecrawl`

- **Verdict:** `complementary`: The built-in tool returns result titles and URLs inline for a quick lookup; ours searches with page content scraped and written to disk, for results worth keeping or reading in full. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation.
- **Integration:** `route`
- **Native surface:** `WebSearch` (built-in tool; markers: gated)
- **Our component:** `firecrawl:firecrawl` (skill)
- **Evidence:**
  - `WebSearch` present in the extraction as builtin-tool
  - markers: gated
  - search hint: search the web for current information
  - invocation mode (2026-09-29, Claude Code 2.1.285): model-invocable, not user-invocable; deferred (loads through tool search)
  - detect: human-added pair, not emitted at threshold 0.30 / top-k 3 (discovery score 0.1443)
  - docs cross-check (tools reference, 2026-09-29): documented
- **Observation:** extraction: extracted from binary v2.1.285 on 2026-09-29 (the /claude-ops:inventory extraction of the installed native build; integrity ok on every lane, degraded overall only because 2.1.285 is past the extractor's last validated build 2.1.284, so counts are floors) (2026-09-29)
- **Recheck trigger:** a Claude Code release renames or removes the built-in `WebSearch` tool or makes it fetch result pages (verified 2026-09-29)
- **Baked:** description phrase no · Boundary section yes · Native step no · suggest sentence no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

## Session-provided skills (observation-only)

### `morning` → `claude-ops:morning-brief`

- **Verdict:** `defer`: Undetermined, and deliberately so. `morning` was observed in a session roster, not in any binary extraction, so the only evidence available is two session rosters on two days, not a basis for a routing line shipped to every consumer. The overlap is real enough to record and too thin to rule on: nothing is known about what the session-provided skill reads, whether it is gh-based, or whether it exists outside the surface it was seen on. Observation-only, never baked, until an in-session capture protocol exists.
- **Integration:** `route`
- **Native surface:** `morning` (session-provided skill; markers: none)
- **Our component:** `claude-ops:morning-brief` (skill)
- **Evidence:**
  - `morning` is absent from this extraction. Absence from the extraction is a statement about the extraction, not the product
  - observed in this repository's cloud session roster on 2026-08-23, alongside other session-provided skills (docx, pdf, pptx, xlsx, design, artifact-*) that the local-CLI bundled roster does not carry
  - second observation (2026-09-29, Claude Code 2.1.284, a local session's own skill roster): listed as `anthropic-skills:morning`, namespaced with the other `anthropic-skills:` entries (docs, docx, pdf, pptx, xlsx, google-workspace, skill-creator, import-memory); `morning` is still absent from the v2.1.284 binary extraction's bundled-skill set, which is a floor
  - our description: prints the operator's read-only morning view for the current GitHub repo in one pass: queue-label counts, merge-ready PRs, parked decisions, loop-lane telemetry freshness
- **Observation:** live-roster: observed in a Claude Code cloud session's own skill roster (2026-08-23) and again in a local session's roster as `anthropic-skills:morning` (2026-09-29); two sessions, no repeatable capture protocol (2026-09-29)
- **Recheck trigger:** an in-session roster capture protocol lands and can observe this surface repeatably, or `morning` appears in a binary extraction's bundled-skill set (verified 2026-09-29)
- **Baked:** description phrase no · Boundary section no · Native step no · suggest sentence no

## First-party marketplace plugins

### `playground` → `prototype:explore-directions`

- **Verdict:** `complementary`: Both produce a browser page with switchable controls, which is why the pair needs a recorded boundary: explore-directions varies YOUR PROJECT'S own UI (real header, real data, real routes) so you can pick a direction and throw the rest away, while a playground explores an arbitrary parameter space and hands back a prompt. Its description now routes the explorer shape to the playground skill via the playgrounds wrapper.
- **Integration:** `route`
- **Native surface:** `playground` (first-party marketplace plugin; markers: none)
- **Our component:** `prototype:explore-directions` (skill)
- **Evidence:**
  - upstream SKILL.md read at commit ed404106fcd80ba98ecb7c851e531dcb626d13b7: 'especially when the input space is large, visual, or structural and hard to express as plain text'
  - our description: builds throwaway UI variations, several radically different visual layouts on one route, switchable from a floating control bar
  - the baked routing clause carries the marketplace parity token so fleet parity traces it to this row
  - corpus slice: 27-resource verified map (2026-08-31)
- **Observation:** upstream-source: anthropics/claude-plugins-official at commit ed404106fcd80ba98ecb7c851e531dcb626d13b7 (HEAD of main, re-verified by fetch 2026-09-01) (2026-09-01)
- **Recheck trigger:** the upstream repository's default branch moves past the pinned commit with changes under plugins/playground, or the playground plugin is renamed, removed, or absorbed into the CLI as a bundled skill (verified 2026-09-01)
- **Baked:** description phrase yes · Boundary section yes · Native step no · suggest sentence no
- **Budget caveat:** the baked phrase may be dropped from the skill listing under budget pressure. It is the best available routing surface, not a guaranteed one

### `playground` → `visualization:visualize`

- **Verdict:** `complementary`: visualize decides the best visual FORM for conversation content and renders it; the first-party playground skill builds an interactive parameter explorer whose output returns as a prompt. The shapes meet only at 'show me this visually', so visualize's Boundary section routes explorer-shaped requests out (to the playground skill, or the playgrounds wrapper which owns install uplift and cloud delivery) and keeps every static form for itself.
- **Integration:** `route`
- **Native surface:** `playground` (first-party marketplace plugin; markers: none)
- **Our component:** `visualization:visualize` (skill)
- **Evidence:**
  - upstream SKILL.md (plugins/playground/skills/playground/SKILL.md) read at commit ed404106fcd80ba98ecb7c851e531dcb626d13b7: 'interactive controls on one side, a live preview on the other, and a prompt output at the bottom with a copy button'
  - our description: decide the best visual FORM and MEDIUM for what is in the conversation right now, then render it
  - the wrapper plugin `playgrounds` declares the cross-marketplace dependency and carries the install uplift, so the Boundary route has a landing surface in this marketplace
  - corpus slice: 27-resource verified map of the announcement article, plugin source, and implicated docs (2026-08-31)
- **Observation:** upstream-source: anthropics/claude-plugins-official at commit ed404106fcd80ba98ecb7c851e531dcb626d13b7 (HEAD of main, re-verified by fetch 2026-09-01) (2026-09-01)
- **Recheck trigger:** the upstream repository's default branch moves past the pinned commit with changes under plugins/playground, or the playground plugin is renamed, removed, or absorbed into the CLI as a bundled skill (verified 2026-09-01)
- **Baked:** description phrase no · Boundary section yes · Native step no · suggest sentence no

## Dismissed

Pairs a human ruled are not an overlap. `detect` suppresses each one until either side's fingerprint changes, then lists it again flagged "resurfaced: description changed".

| Native surface | Class | Component | Reason | As of | Date |
|---|---|---|---|---|---|
| `Agent` | builtin-tool | `docs-hygiene:write-for-agents` | The Agent tool launches a subagent; ours writes agent-consumed markdown. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.285 | 2026-09-29 |
| `Bash` | builtin-tool | `bash-format:check` | Name overlap only: bash-format:check is a read-only check that the shfmt and shellcheck binaries resolve for the bash-format hook; the built-in Bash tool executes shell commands. Different jobs, no routing. | 2.1.285 | 2026-09-30 |
| `Bash` | builtin-tool | `bash-format:setup` | The Bash tool runs shell commands; ours sets up the shell-script formatter hook. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.285 | 2026-09-29 |
| `Explore` | builtin-agent | `prototype:explore-directions` | The Explore agent locates code; ours builds throwaway UI variations. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.285 | 2026-09-29 |
| `Plan` | builtin-agent | `planning:plan-reviewer (agent)` | The Plan agent drafts an implementation approach; this agent stress-tests a written plan for /planning:plan. The Plan pair is recorded against planning:plan. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.285 | 2026-09-29 |
| `Plan` | builtin-agent | `testing:plan` | The Plan agent drafts an implementation approach; ours plans tests for a change by regression risk. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.285 | 2026-09-29 |
| `PowerShell` | builtin-tool | `powershell-format:check` | Name overlap only: powershell-format:check is a read-only check that pwsh, PSScriptAnalyzer, jq and node resolve for the powershell-format hook; the built-in PowerShell tool executes PowerShell commands. Different jobs, no routing. | 2.1.285 | 2026-09-30 |
| `PowerShell` | builtin-tool | `powershell-format:setup` | The PowerShell tool runs PowerShell commands; ours sets up the PowerShell formatter hook. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.285 | 2026-09-29 |
| `Read` | builtin-tool | `x:read` | The Read tool reads a local file; ours reads an X post through third-party converters. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.285 | 2026-09-29 |
| `SendUserMessage` | builtin-tool | `claude-ops:morning-brief` | SendUserMessage (alias Brief) sends the user a message; ours prints a repo's morning ops view. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.285 | 2026-09-29 |
| `Workflow` | builtin-tool | `session-flow:workflow` | The Workflow tool runs a workflow script; ours routes the next stage of a staged workflow. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.285 | 2026-09-29 |
| `Workflow` | builtin-tool | `songwriting:workflow` | The Workflow tool runs a workflow script; ours routes a songwriting session. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.285 | 2026-09-29 |
| `Write` | builtin-tool | `bugs:write` | The Write tool writes a file; ours drafts a structured bug report. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.285 | 2026-09-29 |
| `Write` | builtin-tool | `docs-hygiene:write-for-agents` | The Write tool writes a file; ours authors agent-consumed markdown. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.285 | 2026-09-29 |
| `Write` | builtin-tool | `docs-hygiene:write-for-humans` | The Write tool writes a file; ours authors human-facing prose. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.285 | 2026-09-29 |
| `agents` | builtin-command | `docs-hygiene:write-for-agents` | /agents manages subagents (its registration now reads "(removed)"); ours writes agent-consumed markdown. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `artifact-design` | bundled-skill | `planning:design` | Design guidance for Artifact pages versus resolving code design decisions (types, contracts, module boundaries). Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `artifact-explainer` | bundled-skill | `review:pr-explainer` | The bundled skill publishes a concept walkthrough artifact; ours explains one pull request's diff as a local HTML page. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `artifact-pr-review` | bundled-skill | `source-control:babysit-prs` | A PR review briefing artifact versus a loop that advances the user's open PRs. Shared PR vocabulary only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `artifact-pr-review` | bundled-skill | `source-control:pull-request` | A PR review briefing artifact versus the PR lifecycle (prep, draft, ready, monitor, merge); the review-artifact pair is recorded against review:pr-explainer. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `autofix-pr` | builtin-command | `review:pr-explainer` | A cloud session that pushes fixes to a PR versus a local HTML explainer of a PR's diff. Shared PR vocabulary only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `batch` | bundled-skill | `code-tidying:batch-simplify` | Parallel worktree agents executing one large change, each opening a PR, versus a simplification sweep over changed files. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `brief` | builtin-command | `ai-briefing:generate` | /brief toggles brief-only output mode; ours builds a sourced AI industry briefing. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `brief` | builtin-command | `ai-briefing:setup` | /brief toggles brief-only output mode; ours configures an AI industry briefing profile. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `brief` | builtin-command | `claude-ops:morning-brief` | /brief toggles brief-only output mode; ours prints a repository's morning operator view. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `bug` | builtin-command | `bugs:setup` | /bug reports a Claude Code bug to Anthropic; ours configures the bugs plugin for a repository. The reporting overlap is recorded against bugs:write. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `claude-code-docs` | bundled-skill | `review:doc-drift-detector (agent)` | Answers questions about Claude Code features versus an agent that finds stale documentation in a repository. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `code-review` | bundled-skill | `review:security-review` | The bundled skill reviews for correctness bugs; ours is the CI security lane. The security pair is recorded as security-review -\> review:security-review. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `commit-push-pr` | builtin-command | `review:pr-explainer` | Commits, pushes, and opens a PR versus explaining an existing PR's diff. Shared PR vocabulary only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `config` | builtin-command | `claude-config:audit` | /config opens the preferences UI (theme, model, output style); ours audits settings files for correctness and drift. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `config` | builtin-command | `claude-config:audit-permission-state` | /config opens the preferences UI; ours reports the effective permission rules across scopes. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `config` | builtin-command | `claude-config:draft-auto-mode-rules` | /config opens the preferences UI; ours drafts autoMode classifier rules. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `context` | builtin-command | `architecture:map-context` | /context shows context-window usage; ours charts a C4 system context from configuration. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `copy` | builtin-command | `discipline:point-dont-copy` | /copy puts the last response on the clipboard; ours is a pointer-over-copy writing discipline. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `deep-research` | bundled-workflow | `discipline:do-your-research-deep` | The workflow researches a new question on the web; ours verifies the session's own claims against primary sources. The research pair is recorded against discovery:research-deep. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `deep-research` | bundled-workflow | `discovery:research-verifier (agent)` | An agent that grades one research artifact's outcome rows for the discovery skills that dispatch it. The research pair is recorded against discovery:research-deep. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `design` | bundled-skill | `evals:design` | The bundled skill drafts UI mockups on a Claude Design canvas; ours designs an LLM evaluation suite. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `design` | bundled-skill | `planning:design` | The bundled skill drafts UI mockups on a Claude Design canvas; ours resolves types, contracts, and module boundaries. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `design` | bundled-skill | `planning:design-handoff` | The bundled skill drafts UI mockups on a Claude Design canvas; ours gates a finished code design for planning. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `design-sync` | bundled-skill | `repo-fleet-hygiene:sync` | Uploads a React design system to Claude Design versus fast-forwarding a fleet of repository checkouts. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `desktop` | builtin-command | `desktop-notification:setup` | /desktop moves the session to the Desktop app; ours checks the desktop-notification hook's prerequisites. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `doc` | bundled-skill | `docs-hygiene:setup` | Creates a document artifact versus configuring the docs-hygiene file-name skills. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `doc` | bundled-skill | `review:doc-drift-detector (agent)` | Creates a document artifact versus an agent that finds stale documentation in a repository. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `explain-usage` | bundled-skill | `education:explain` | Explains where this session's tokens went versus a plain-language explainer of any concept. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `goal` | builtin-command | `performance:goal` | /goal sets a session completion condition; ours constructs a measurable performance target. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `install` | builtin-command | `claude-ops:audit-install-state` | /install installs the Claude Code native build; ours audits what is in ~/.claude. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `install-github-app` | builtin-command | `github:audit` | Installs the Claude GitHub App versus a read-only audit of GitHub settings. The setup overlap is recorded against github:advise. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `loop` | bundled-skill | `source-control:babysit-loop` | Not an overlap: ours is the cycle body launched through /loop, and its description already names /loop as the launcher. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `loop` | bundled-skill | `work-items:work-loop` | Not an overlap: ours is the cycle body launched through /loop, and its description already names /loop as the launcher. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `loops` | builtin-command | `source-control:babysit-loop` | /loops lists, creates, and deletes scheduled loops; ours is a loop body, not a loop manager. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `loops` | builtin-command | `work-items:work-loop` | /loops lists, creates, and deletes scheduled loops; ours is a loop body, not a loop manager. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `mcp` | builtin-command | `mcp-tools:audit` | /mcp manages server connections and OAuth; ours audits MCP tool definition quality in source. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `mcp` | builtin-command | `mcp-tools:audit-posture` | /mcp manages server connections and OAuth; ours audits configured servers' supply-chain posture without connecting to any. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `memory` | builtin-command | `claude-memory:audit` | /memory opens CLAUDE.md files for editing; ours audits the instruction layer against a checklist. The auto-memory toggle overlap is recorded against claude-memory:stateless. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `memory_read` | builtin-tool | `claude-memory:audit` | memory_read reads a document from a session memory store; ours audits CLAUDE.md, rules, and auto-memory. Different memory. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.285 | 2026-09-29 |
| `output-style` | builtin-command | `animation:learn-style` | Shared word only: /output-style switches Claude Code's response style; learn-style studies an art style for the animation plugin. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.285 | 2026-09-29 |
| `plan` | builtin-command | `planning:plan-reviewer (agent)` | /plan enters plan mode; the agent stress-tests a written plan for /planning:plan. The plan-mode pair is recorded against planning:plan. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `plan` | builtin-command | `testing:plan` | /plan enters plan mode; ours writes a test plan for a change. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `plugin-types` | builtin-command | `code-metrics:audit-type-debt` | Writes TypeScript declarations for typing a hooks module versus measuring how much of a codebase is typed. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `pr` | bundled-skill | `review:pr-explainer` | Creates a pull request versus explaining an existing one. Shared PR vocabulary only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `pr` | bundled-skill | `source-control:babysit-prs` | Creates one pull request versus a loop that advances already-open ones. The creation pair is recorded against source-control:pull-request. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `rename` | builtin-command | `docs-hygiene:audit-file-names` | /rename renames the conversation; ours audits a docs tree's file names. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `rename` | builtin-command | `docs-hygiene:realign-file-names` | /rename renames the conversation; ours applies a file rename plan. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `rename` | builtin-command | `naming:name-it-better` | /rename renames the conversation; ours generates names for code and domain terms. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `resume` | builtin-command | `session-flow:continue-in-background` | /resume reopens a previous conversation; ours launches a new detached session to carry the current work. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `security-review` | plugin-backed-builtin | `review:code-reviewer (agent)` | The code-reviewer agent leaves security to security-reviewer by its own description. The security pair is recorded against review:security-reviewer. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `stop` | builtin-command | `session-flow:clean-stop` | /stop ends a background session; ours sweeps repositories for unpushed work before the machine goes away. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `update` | builtin-command | `firecrawl:update` | /update switches Claude Code to the latest version; ours drift-checks the firecrawl wrapper against its upstream. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `update` | builtin-command | `playbooks:update` | /update switches Claude Code to the latest version; ours drift-checks the playbooks plugin's vendored packs. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `update-config` | bundled-skill | `firecrawl:update` | Edits Claude Code settings.json versus drift-checking the firecrawl wrapper against its upstream. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `verify` | bundled-skill | `performance:verify` | Exercises a code change end to end versus re-deriving a performance measurement in a fresh context. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `worker` | builtin-agent | `discipline:script-the-deterministic-work` | The worker agent executes a delegated task; ours is a scripting discipline corrector. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.285 | 2026-09-29 |
| `worker` | builtin-agent | `session-flow:tidy-work` | Name overlap only ('work'): tidy-work is a user-only skill that tidies the gitignored .work memory tiers; the built-in worker agent executes delegated tasks. Different jobs, no routing. | 2.1.285 | 2026-09-30 |
| `worker` | builtin-agent | `work-items:work` | The worker agent executes a delegated task; ours picks and executes a tracker item end to end. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.285 | 2026-09-29 |
| `worker` | builtin-agent | `work-items:work-loop` | The worker agent executes a delegated task; ours drains a tracker backlog as a loop. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.285 | 2026-09-29 |
| `workflow-authoring` | bundled-skill | `playbooks:skill-authoring` | Reference for Workflow tool scripts versus SKILL.md authoring guidance. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `workflow-authoring` | bundled-skill | `songwriting:workflow` | Reference for Workflow tool scripts versus a songwriting situation router. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `workflows` | builtin-command | `session-flow:workflow` | /workflows browses Workflow tool runs; ours navigates staged engineering work. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |
| `workflows` | builtin-command | `songwriting:workflow` | /workflows browses Workflow tool runs; ours routes a songwriting session. Shared word only. Ruled 2026-09-29 by operator direction on the orchestrator's recommendation. | 2.1.284 | 2026-09-29 |

<!-- native-surfaces:end -->
