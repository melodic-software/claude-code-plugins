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
