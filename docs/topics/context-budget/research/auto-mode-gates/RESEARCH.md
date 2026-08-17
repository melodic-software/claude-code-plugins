# RESEARCH — Claude Code auto mode and forcing a human approval gate on settings.json writes

## Task restatement

Establish whether a skill can force a genuine human approval gate that auto mode cannot auto-approve,
when the thing being mutated is the user's own `settings.json`. Commissioned by the author of a skill
that will offer to disable connectors, plugins, and bundled skills by editing `settings.json`, and
needs to know whether an un-bypassable gate is constructible before designing around one. Six
numbered questions; full depth, official-docs-first; reconcile against this repo's
`docs/conventions/permission-rule-hygiene/README.md`.

## Bottom line

**A gate that auto mode cannot auto-approve is constructible. An un-bypassable gate is not.**

- The strongest **skill-shippable** construct is a `PreToolUse` hook returning
  `permissionDecision: "ask"`. In auto mode it floors the decision at a prompt — the classifier may
  still deny, but cannot approve silently. Hard version floor: **v2.1.211**.
- The strongest construct overall is an operator-installed content-scoped `permissions.ask` rule,
  which holds in auto mode **and** in `bypassPermissions`. A plugin cannot ship it; the operator
  must add it.
- Neither survives `disableAllHooks`, a `PermissionRequest` hook returning `behavior: "allow"`, or
  (for the hook route) `bypassPermissions`, where the docs are silent.
- `AskUserQuestion` is **not** a gate and should not be used as one.
- `~/.claude/settings.json` is already privileged: it is a **protected path** *and* outside the
  working directory. In auto mode a write there is routed to the classifier — never rule-approved,
  but also **never guaranteed to reach a human**. Protected-path status alone does not give the
  operator what they want.

## Sidecar abstracts

| Section | Abstract |
|---|---|
| auto-mode-semantics | Auto mode is the built-in starting mode on Pro/Max/Team from v2.1.228 (v2.1.233 native Windows); a classifier reviews actions instead of the user, and on entry it drops four named classes of broad allow rule. |
| permission-mode-inventory | Six modes, resolved against the three action classes the brief names — and the decisive structural fact is that ~/.claude/settings.json is BOTH a protected path and outside the working directory, so it is never covered by the working-directory edit auto-approval in any mode. |
| forcing-a-human-gate | A skill CAN force a prompt auto mode cannot auto-approve — a PreToolUse hook returning "ask", shipped in the skill's own frontmatter — but no mechanism is un-bypassable, because bypassPermissions is undocumented for hook asks, dontAsk converts asks to denials, disableAllHooks removes hooks wholesale, and a PermissionRequest hook can answer the prompt on the user's behalf. |
| settings-mutation-safety | The bundled /doctor is the documented model — it reports findings first and applies fixes only after confirmation — while /config writes directly with no confirmation; and ~/.claude/settings.json is treated differently from project writes by two independent mechanisms plus an explicit self-escalation warning. |
| repo-reconciliation | The permission-rule-hygiene convention holds on every claim checked, with one correction (the auto-mode default is version-gated at v2.1.228/v2.1.233, not dated 2026-08-14) and one gap it does not yet cover (it reasons only about allow rules, never about forcing a prompt). |

## Section → file map

| Brief question | Section | File | Anchor |
|---|---|---|---|
| Q1 (what auto mode is, default since when), Q3 (the "drops" claim) | auto-mode-semantics | `RESEARCH-auto-mode-semantics.md` | `#q1--what-auto-mode-is-and-whether-it-is-the-default`, `#q3--the-repos-auto-mode-drops-some-rules-claim-the-official-basis` |
| Q2 (mode inventory vs. project / `~/.claude` / Bash) | permission-mode-inventory | `RESEARCH-permission-mode-inventory.md` | `#the-inventory` |
| Q4 (can a skill mandate confirmation) | forcing-a-human-gate | `RESEARCH-forcing-a-human-gate.md` | `#q4--can-a-skill-mandate-a-confirmation-no-permission-mode-can-bypass` |
| Q5 (guidance on settings mutation, `/doctor`, `/config`), Q6 (`~/.claude` vs project) | settings-mutation-safety | `RESEARCH-settings-mutation-safety.md` | `#q5--official-guidance-on-toolsskills-that-modify-the-users-own-settingsjson`, `#q6--are-claudesettingsjson-writes-treated-differently-from-project-writes` |
| Repo convention reconciliation + project fit | repo-reconciliation | `RESEARCH-repo-reconciliation.md` | `#reconciliation-with-docsconventionspermission-rule-hygienereadmemd` |

Coverage ledger: `research-checklist.md` (20 rows, all marked; gate exit 0).

## Fetch log

One entry per fetch per claim. Ladder rungs: 1 = deepest technical artifact, 2 = platform/API
reference, 3 = product docs, 4 = changelog/release notes, 5 = announcement, 6 = third-party.

| Claim | URL or command | Rung | Tool | Outcome |
|---|---|---|---|---|
| Auto mode is classifier-reviewed; is built-in default on Pro/Max/Team | `curl https://code.claude.com/docs/sitemap.xml` (enumeration surface) | — | Bash/curl | carries the corpus enumeration |
| Auto mode is classifier-reviewed; is built-in default | `https://code.claude.com/docs/en/permission-modes.md` | 2 | Bash/curl | carries the claim |
| Auto mode is classifier-reviewed; is built-in default | rung 1 (maintainer deep dive) `https://www.anthropic.com/engineering/claude-code-auto-mode` | 1 | WebFetch | unreachable after escalation — egress proxy `EGRESS_BLOCKED`; retried via `curl` on the sibling first-party artifact `https://claude.com/blog/auto-mode`, HTTP 403. Gap row below |
| Auto mode default, version floor | `https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md` | 4 | Bash/curl | fetched and searched — **2.1.233 (latest, confirmed this turn) — current** |
| Auto mode drops four allow-rule classes | `https://code.claude.com/docs/en/permission-modes` ("How the classifier evaluates actions") | 2 | Bash/curl | carries the claim |
| Auto mode drops four allow-rule classes | `https://code.claude.com/docs/en/auto-mode-config.md` | 2 | Bash/curl | carries the claim (independent restatement + `classifyAllShell`) |
| Auto mode drops four allow-rule classes | rung 1 for this claim class | 1 | — | does not exist — no deeper first-party artifact indexes rule-drop semantics; the docs host's own sitemap enumerates every page and the deepest is the reference page above |
| Repo's "drops" claim and its basis | `plugins/claude-config/skills/audit-permission-state/SKILL.md` | — | Read/Grep | carries the claim (Tier 0, local) |
| `.claude` is a protected path; per-mode outcomes | `https://code.claude.com/docs/en/permission-modes#protected-paths` | 2 | Bash/curl | carries the claim |
| Mode inventory; deny→ask→allow precedence | `https://code.claude.com/docs/en/permissions.md` | 2 | Bash/curl | carries the claim |
| `~/.claude` is outside working-directory auto-approval scope | `https://code.claude.com/docs/en/permissions#working-directories` | 2 | Bash/curl | carries the claim |
| Hook `"ask"` floors the decision at a prompt in auto mode | `https://code.claude.com/docs/en/hooks.md` (PreToolUse decision control) | 2 | Bash/curl | carries the claim |
| Hook `"ask"` floors the decision at a prompt in auto mode | `https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md` (2.1.211 entry) | 4 | Bash/curl | carries the claim — **2.1.233 (latest) — current** |
| Hook `"ask"` floors the decision at a prompt in auto mode | `https://code.claude.com/docs/en/permissions#extend-permissions-with-hooks` | 2 | Bash/curl | carries the claim |
| Hook `"ask"` floors the decision at a prompt in auto mode | WebSearch, `anthropics/claude-code` issue #52822 + practitioner writeups | 6 | WebSearch | fetched and searched, does not carry the claim — results restate the docs; no independent confirmation. Down-ranked per source-quality red flags |
| A skill/plugin can ship PreToolUse hooks | `https://code.claude.com/docs/en/hooks#hooks-in-skills-and-agents` | 2 | Bash/curl | carries the claim |
| A plugin can ship hooks but not permission rules | `https://code.claude.com/docs/en/plugins-reference.md` | 2 | Bash/curl | carries the claim |
| Plugin subagents excluded from `hooks` frontmatter | `https://code.claude.com/docs/en/sub-agents.md` | 2 | Bash/curl | carries the claim |
| `permissions.ask` always prompts in auto mode | `https://code.claude.com/docs/en/auto-mode-config#add-a-human-checkpoint` | 2 | Bash/curl | carries the claim |
| Ask rules still prompt in `bypassPermissions` | `https://code.claude.com/docs/en/permission-modes#skip-all-checks-with-bypasspermissions-mode` | 2 | Bash/curl | carries the claim |
| `AskUserQuestion` is not permission-gated; auto-continue timeout | `https://code.claude.com/docs/en/tools-reference.md` | 2 | Bash/curl | carries the claim |
| `askUserQuestionTimeout` default `"never"`, user-settable | `https://code.claude.com/docs/en/settings.md` | 2 | Bash/curl | carries the claim |
| `disallowed-tools` exists and removes tools | `https://code.claude.com/docs/en/skills.md` | 2 | Bash/curl | carries the claim |
| `PermissionRequest` hook can allow on the user's behalf (falsification) | `https://code.claude.com/docs/en/hooks#permissionrequest-decision-control` | 2 | Bash/curl | carries the claim |
| `disableAllHooks` removes non-managed hooks (falsification) | `https://code.claude.com/docs/en/hooks#disable-or-remove-hooks` | 2 | Bash/curl | carries the claim |
| `/doctor` confirms before changing anything | `https://code.claude.com/docs/en/commands.md` | 3 | Bash/curl | carries the claim |
| `/doctor` confirms before changing anything | `https://code.claude.com/docs/en/debug-your-config.md` | 3 | Bash/curl | carries the claim (independent restatement) |
| `~/.claude/settings.json` named as self-escalation vector | `https://code.claude.com/docs/en/sandboxing.md` | 2 | Bash/curl | carries the claim |
| No normative "skills must confirm before settings writes" rule | `https://code.claude.com/docs/en/security.md`, `.../security-guidance.md`, `.../skills.md`, `.../settings.md`, `.../plugins-reference.md` | 2–3 | Bash/curl | fetched and searched, does not carry the claim — grounds the reported absence |
| `~/.claude` layout and settings precedence | `https://code.claude.com/docs/en/claude-directory.md` | 3 | Bash/curl | carries the claim |
| Repo convention reconciliation | `docs/conventions/permission-rule-hygiene/README.md` | — | Read | carries the claim (Tier 0, local) |

## Conflicts

**C1 — "never auto-approved" vs. "routed to the classifier" for protected paths. Resolved; the
resolution is the operator's answer.** [permission-modes](https://code.claude.com/docs/en/permission-modes)
says protected-path writes are "never auto-approved except in `bypassPermissions`", while its own
table says auto mode **routes them to the classifier**, which can approve without prompting. These
reconcile once "auto-approved" is read as its term of art — *approved by a settings rule without
review* — rather than as *approved without a human*. **The classifier is review, but it is not
human review.** Anyone reading "never auto-approved" as "a human always sees it" will design the
wrong skill. Primary wins: the per-mode table is the operative statement.

**C2 — repo convention vs. current docs on the auto-mode default.** The convention quotes a dated
"Starting August 14, 2026" passage no longer present at its cited URL; the page now states a version
floor (v2.1.228 / v2.1.233 native Windows). Primary wins. Substance unchanged; the citation needs
refreshing. Detail in `RESEARCH-repo-reconciliation.md`.

## Gaps

1. **Does a PreToolUse hook's `"ask"` force a prompt in `bypassPermissions`?** **Unverified —
   documented silence, not a documented answer.** The docs state that explicit ask *rules* prompt in
   that mode and enumerate what else does (org-`ask` connectors, `requiresUserInteraction` MCP tools,
   the `rm -rf` circuit breaker); hook decisions are absent from that enumeration. Checked:
   permission-modes, permissions, hooks, auto-mode-config, sub-agents, and the upstream CHANGELOG
   (searched for hook/bypass interactions). Unchecked: `agent-sdk/hooks`, `agent-sdk/permissions`,
   the two unreachable maintainer writeups, and the upstream issue tracker beyond the single search.
   **Treat the hook gate as leaking under `bypassPermissions`.**
2. **Are *plugin skill* frontmatter hooks honored?** **Unverified.** Plugin *subagents* are
   explicitly excluded from `hooks` frontmatter "for security reasons"; no equivalent statement
   exists for plugin skills, and `hooks/hooks.json` is a documented plugin component. Checked:
   plugins-reference, hooks, skills, sub-agents. Unchecked: agent-sdk/plugins, plugin-dependencies.
   **Prefer `hooks/hooks.json` for a plugin-delivered gate** — documented and unambiguous.
3. **Rung-1 maintainer artifacts unreachable.** `anthropic.com/engineering/claude-code-auto-mode`
   (egress-proxy blocked) and `claude.com/blog/auto-mode` (HTTP 403), both linked by the docs as the
   deep dive on classifier layering. Escalation ladder walked: WebFetch → `curl` on the sibling
   first-party host → both failed; no headless-browser or scraping tool is connected this session.
   No claim here depends on them, but the classifier's internal layering is therefore sourced only
   at rung 2.
4. **Whether the auto-mode drop is *silent*** is this repo's field observation, not a documented
   property. Low stakes; flagged so it is not laundered into a sourced claim.
5. **No empirical verification was performed.** Every claim is documentary. Given this repo's own
   `audit-permission-state --oracle` precedent (spawning a real `claude -p` to corroborate drop
   predictions), an equivalent probe of the hook-`"ask"`-under-`bypassPermissions` question would
   convert Gap 1 from unverified to settled, and is the highest-value follow-up.

## Recency status

Upstream release stream fetched this turn: `anthropics/claude-code` `CHANGELOG.md`, **latest 2.1.233**.
The brief's reference point v2.1.232 is one release back and both are covered. No entry in 2.1.232 or
2.1.233 alters the classifier decision order, the auto-mode drop classes, the protected-path list, or
PreToolUse/PermissionRequest decision semantics. All doc pages fetched 2026-08-17, same day.
Topic class: very active project (14-day window) — satisfied. Verdict: **current**.

## Next-stage handoff

**Settled — safe to design on:**

- Auto mode is the built-in default on Pro/Max/Team in terminal and VS Code from v2.1.228 (v2.1.233
  native Windows); `-p`, the Agent SDK, Enterprise, and the non-Anthropic providers all start in
  Manual. A CI-invoked path is *not* in auto mode.
- `~/.claude/settings.json` is a protected path and outside the working directory. `permissions.allow`
  cannot pre-approve it. In auto mode it goes to the classifier, which may approve or deny with no
  human involved — **so the skill cannot rely on protected-path status to produce a confirmation.**
- A `PreToolUse` hook returning `"ask"` is the gate to build, floor **v2.1.211**. Attributed in the
  prompt as `[Plugin]`/`[Skill]` source. Ship it via `hooks/hooks.json`.
- Pair it with a documented operator-setup `permissions.ask` rule (`~/`- or `//`-anchored) — the only
  layer that also holds in `bypassPermissions`.
- Follow `/doctor`'s posture: report findings, show the diff, apply only after confirmation. Consider
  splitting a report-only skill from the mutating one, as `audit-permission-state` already does here.
- Expect classifier **denial** as a normal outcome: disabling connectors/plugins/skills is exactly the
  oversight-reducing change auto mode is trained to block. Handle denial as an ordinary path.

**Open decisions for the author:**

- Whether to ship the gate at all given Gap 1 — or to ship it and document the `bypassPermissions` /
  `disableAllHooks` boundary honestly. Recommended: ship and document.
- Whether to route plugin-disabling through the built-in `/plugin` UI, which already writes a
  `settings.local.json` override with its own confirmation, instead of editing files directly.
- Whether to run the empirical probe in Gap 5 before committing to the design.
