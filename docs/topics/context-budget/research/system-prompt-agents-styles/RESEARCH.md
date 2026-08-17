# RESEARCH — system prompt, custom agents, output styles

## Task restatement

Establish, for the three startup-context contributors the parent had no operator lever for — Claude
Code's own system prompt, custom agent definitions, and output styles — what each injects into the
always-loaded payload and whether a *supported* trim lever exists. Classify each as
OPERATOR-ADDRESSABLE or VENDOR WEIGHT. Every claim carries its source URL and fetch date. Output is
for the author of a skill that inventories and trims a session's fixed startup payload; six sibling
contributors already have their own research runs.

Named sub-questions: system-prompt contents (Q1), the flag/env-var checklist including
`--append-system-prompt`, `--system-prompt`, output styles as replacement, `--safe-mode` and
`CLAUDE_CODE_SIMPLE=1` (Q2), Anthropic's 80%-removal statement (Q3), whether git info scales with
the repo (Q4), what an agent contributes and whether it is description-only (Q5), per-agent
disablement (Q6), what an output style contributes and its token implication (Q7), how it is
enabled and whether plugin styles load unconditionally (Q8), and the classification (Q9).

## Headline

**The premise did not survive contact with the evidence: all three have documented operator
levers.** The system prompt has a clean reduce lever the brief did not list
(`CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT`, 5.1k → 1.8k measured) which is a **no-op on Opus 5** because
the reduction already shipped as that generation's default. Custom agents are description-only
(~120 tokens against a 5,139-token file) and the documented "disable" mechanism measurably does
**not** unload them. Output styles are the surprise: a custom one is **net negative** by ~1k,
because it drops Claude Code's built-in software-engineering instructions by default.
`CLAUDE_CODE_SIMPLE=1` is **not undocumented**.

## Sidecars

| Section | Abstract | File | Anchor |
|---|---|---|---|
| Classification | The deliverable — each of the three contributors classified as operator-addressable or vendor weight, with the split inside each one made explicit. | [`RESEARCH-classification.md`](RESEARCH-classification.md) | `#the-deliverable--classification` |
| System prompt: composition | What Claude Code injects into its own system prompt at startup, extracted from the shipped binary's own templates, and why the git block is a bounded rather than a scaling cost. | [`RESEARCH-system-prompt-composition.md`](RESEARCH-system-prompt-composition.md) | `#what-claude-code-injects-into-its-own-system-prompt` |
| System prompt: levers | Every candidate system-prompt lever checked one by one — which exist, which are documented, and which actually reduce rather than add or relocate. | [`RESEARCH-system-prompt-levers.md`](RESEARCH-system-prompt-levers.md) | `#is-there-a-supported-lever-that-reduces-the-system-prompt` |
| Custom agents | Custom agents contribute name plus description only — roughly 100-190 tokens each — and no supported setting unloads one short of removing the plugin or file that provides it. | [`RESEARCH-custom-agents.md`](RESEARCH-custom-agents.md) | `#custom-agents` |
| Output styles | An output style modifies the system prompt directly, and a custom one is net negative by default because it drops the built-in software-engineering instructions unless told to keep them. | [`RESEARCH-output-styles.md`](RESEARCH-output-styles.md) | `#output-styles` |
| Measurements | Tier-0 `/context` measurements of every candidate lever against a fixed baseline, showing which reduce the startup payload, which relocate it, and which do nothing. | [`RESEARCH-measurements.md`](RESEARCH-measurements.md) | `#measurements--tier-0-context-probes` |
| Gaps and unverified | The fetch log, the recency verdict, and every claim this run could not raise to HIGH — including the unreachable 80% blog post and the unrecovered git commit count. | [`RESEARCH-gaps-and-unverified.md`](RESEARCH-gaps-and-unverified.md) | `#gaps-unverified-claims-and-the-fetch-log` |

Coverage ledger: [`research-checklist.md`](research-checklist.md) — 22 rows, all marked.

## Answers at a glance

| # | Question | Answer |
|---|---|---|
| 1 | What is injected | `<env>` block (cwd, git-repo flag, extra dirs, platform, shell, OS version), model identity + knowledge cutoff, and a git block (branch, main branch, git user, status, recent commits) at the very end. No separate context-management block found. |
| 2 | Levers | `--append-system-prompt` **adds**; `--system-prompt` **replaces** (→12 tok); `--safe-mode` **does not touch it**; `CLAUDE_CODE_SIMPLE=1` reduces but guts the session and **is documented**; `CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT=1` **reduces cleanly**; `--exclude-dynamic-system-prompt-sections` **relocates, net zero**. |
| 3 | The 80% statement | Blog post unreachable (403 + egress block); figure is Tier 2. The change is first-party at changelog **v2.1.154**: lean prompt default for all models except Haiku, Sonnet, Opus 4.7 and earlier. Implies control only via `CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT` — already spent on Opus 5. |
| 4 | Git scaling | **No.** `git status` truncated at 2k chars; commits via fixed `git log --oneline -n <N>`. Bounded, with an on/off switch (`includeGitInstructions`). |
| 5 | Agent payload | **Name + description only.** 122 tokens charged vs a 5,139-token file (~1:42). 12 agents = 1.5k. |
| 6 | Per-agent disable | **No.** `Agent(<name>)` deny rules block invocation but **measurably leave the payload**. Only `--safe-mode` or disabling the whole plugin removes it. |
| 7 | Output style | Modifies the system prompt directly; **adds** its own text but **removes** the built-in coding instructions unless `keep-coding-instructions: true`. Measured **net −1.0k**. Docs cost only the additive half. No `/context` row of its own. |
| 8 | Enable/disable | `outputStyle` settings key or `/config`; `/output-style` **removed in v2.1.91**. Plugin styles are selectable, **not** unconditional — unless `force-for-plugin: true`, which applies automatically and overrides the user's setting. |
| 9 | Classification | System prompt: **OPERATOR-ADDRESSABLE above a ~2.8k vendor floor**. Custom agents: **addressable at authoring time only** (description length); effectively vendor weight for a consumer. Output styles: **fully OPERATOR-ADDRESSABLE**, and the only net-negative lever. |

## Next-stage handoff

**Settled — safe to build on:**

- The three levers that reduce, the two that do not, and the one that relocates, each with a measured delta.
- Agent payload is description-only; description length is the author's lever.
- Custom output styles are net negative by ~1k, with a named behavioral cost.
- Git payload is bounded, not repo-scaling.
- `/context` is not a reliable attribution map: `includeGitInstructions` savings land in `System tools`, and output styles have no row.
- Recency: current as of v2.1.233 (2026-08-14); probes ran on v2.1.232.

**Open decisions for the skill's author:**

- Whether to recommend the custom-output-style trick at all, given it trades away the built-in software-engineering instructions for ~1k of a 200k–1M window.
- Whether the skill should branch its advice on the session model, since `CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT` is worth ~3.3k on Sonnet 5 and nothing on Opus 5.
- Whether to report the agent payload at all, given it is ~0.15% of a 1M window and has no consumer-side lever.

**Do not build on:** the `--safe-mode` `System tools` increase (G4), the specific recent-commit count (G2), or the "80%" figure as a first-party number (G1). All three are enumerated in the gaps sidecar.
