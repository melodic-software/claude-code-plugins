---
topic: system-prompt-agents-styles
section: system-prompt-composition
abstract: What Claude Code injects into its own system prompt at startup, extracted from the shipped binary's own templates, and why the git block is a bounded rather than a scaling cost.
claims:
  - claim: "The startup system prompt contains an `<env>` block carrying working directory, git-repo flag, additional working directories, platform, shell, OS version, model identity and knowledge cutoff."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "Tier 0: template string extracted from @anthropic-ai/claude-code v2.1.232 bin/claude.exe, 2026-08-17"
        tier: 0
        pool: "shipped Claude Code binary"
      - url: "https://code.claude.com/docs/en/context-window"
        tier: 1
        pool: "Anthropic docs (code.claude.com)"
      - url: "https://code.claude.com/docs/en/cli-reference"
        tier: 1
        pool: "Anthropic docs (code.claude.com)"
  - claim: "Git branch, main branch, git user, status and recent commits load as a separate block at the very end of the system prompt, described in-prompt as a snapshot that does not update during the conversation."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "Tier 0: git-status block strings extracted from bin/claude.exe v2.1.232, 2026-08-17"
        tier: 0
        pool: "shipped Claude Code binary"
      - url: "https://code.claude.com/docs/en/context-window"
        tier: 1
        pool: "Anthropic docs (code.claude.com)"
      - url: "https://code.claude.com/docs/en/sub-agents"
        tier: 1
        pool: "Anthropic docs (code.claude.com)"
  - claim: "The git payload does not scale with repo size: `git status` output is truncated past 2k characters and recent commits are collected with a fixed `git log --oneline -n <N>`."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "Tier 0: truncation string and git argv extracted from bin/claude.exe v2.1.232, 2026-08-17"
        tier: 0
        pool: "shipped Claude Code binary"
      - url: "Tier 0: paired `/context` runs with and without includeGitInstructions, 2026-08-17"
        tier: 0
        pool: "local tool output"
      - url: "https://code.claude.com/docs/en/settings"
        tier: 1
        pool: "Anthropic docs (code.claude.com)"
  - claim: "CLAUDE.md is delivered as a user message after the system prompt, not as part of it, so it is a distinct payload from everything on this page."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/memory"
        tier: 1
        pool: "Anthropic docs (code.claude.com)"
      - url: "https://code.claude.com/docs/en/prompt-caching"
        tier: 1
        pool: "Anthropic docs (code.claude.com)"
      - url: "https://code.claude.com/docs/en/output-styles"
        tier: 1
        pool: "Anthropic docs (code.claude.com)"
produced_by: phase-1
---

# What Claude Code injects into its own system prompt

## Q1 — the documented and shipped contents

Two first-party surfaces agree, and one of them is the binary itself.

### The `<env>` block — extracted verbatim from the shipped template

Recovered from `@anthropic-ai/claude-code` v2.1.232 `bin/claude.exe` on 2026-08-17 (Tier 0). The
template, with its interpolations left as written:

```text
Here is useful information about the environment you are running in:
<env>
Working directory: ${cwd}
Is directory a git repo: ${Yes|No}
Additional working directories: ${list}      (present only when set)
Platform: ${process.platform}
${shell}
OS Version: ${osVersion}
${extra}
</env>
You are powered by the model named ${modelDisplayName}. The exact model ID is ${modelId}.

Assistant knowledge cutoff is ${cutoff}.
```

So **all four things named in the question are present**: OS/shell/cwd environment block, model
identity, knowledge cutoff, and — separately, below — git state.

A second, differently-shaped variant exists in the same binary (`# Environment` / "You have been
invoked in the following environment:") carrying `Primary working directory`, a git-worktree
warning, and availability/fast-mode sentences. Which surface uses which variant was **not
established** — see gaps.

### The git block — a separate block at the end

Also Tier 0 from the same binary. Its literal fragments:

```text
This is the git status at the start of the conversation. Note that this status is a snapshot in
time, and will not update during the conversation.
Current branch: …
Main branch (you will usually use this for PRs): …
Git user: …
Status:                       (or "(clean)")
Recent commits:
```

Collected via `git --no-optional-locks status --short`, `git --no-optional-locks log --oneline -n
<N>`, and `git config user.name`.

The docs place it the same way: *"Working directory, platform, shell, OS version, and whether this
is a git repo. Git branch, status, and recent commits load as a separate block at the very end of
the system prompt"* (<https://code.claude.com/docs/en/context-window>, fetched 2026-08-17).

### A context-management block?

**Not found as a system-prompt block.** The compaction and context machinery documented on
`context-window` and `prompt-caching` describes runtime behavior, and skill/plan-mode instructions
are explicitly stated to arrive *as conversation messages*, leaving the cached prefix intact
(<https://code.claude.com/docs/en/prompt-caching>, fetched 2026-08-17). Sources checked: the shipped
binary's prompt strings, `context-window`, `prompt-caching`, `how-claude-code-works`,
`cli-reference`, `output-styles`. Not checked: any non-public build, and the Agent SDK's
`claude_code` preset internals.

## Q4 — does the git information scale with the repo?

**No. It is a bounded cost, and the bound is in the binary.**

1. **`git status` is truncated.** The binary carries the literal
   `... (truncated because it exceeds 2k characters. If you need more information, run "git status"
   using` — so a repository with thousands of dirty files contributes the same ~2k-character
   ceiling as one with fifty.
2. **Commits are a fixed count.** The collection command is `git log --oneline -n <N>` with `N`
   compiled as an integer constant, not a string, so `strings` could not recover its value. **The
   count is fixed rather than repo-dependent; the specific value is unverified.** It does not scale
   with total commit count either way.
3. **Empirically it is small.** Toggling `includeGitInstructions: false` left the `/context`
   `System prompt` row unmoved at 5.1k — the git status snapshot for this repo is below the row's
   0.1k rounding. The 2.4k that toggle *does* save comes out of the Bash tool description (the
   commit/PR workflow instructions), not out of the status snapshot.

**Practical consequence for the skill:** git is not a variable an operator meaningfully tunes by
changing the repository. It is a small fixed block with a documented on/off switch
(`includeGitInstructions`, `CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS`), and the switch's real saving
lands in a different `/context` row than the one an auditor would watch.

## The boundary worth stating explicitly

`CLAUDE.md` is **not** part of this payload: *"CLAUDE.md content is delivered as a user message
after the system prompt, not as part of the system prompt itself"*
(<https://code.claude.com/docs/en/memory>, fetched 2026-08-17). The `prompt-caching` layer table
puts it in a separate "Project context" layer below the system prompt. A skill inventorying "the
system prompt" should not count it here, and the six sibling research runs presumably own it.
