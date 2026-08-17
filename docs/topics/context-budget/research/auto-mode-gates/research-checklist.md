# Coverage ledger — auto-mode-gates

**Corpus verdict: BOUNDED.** The question set is answered by (a) a finite set of pages on the
official Claude Code docs host, enumerated from an exhaustive surface, and (b) a finite set of local
repo artifacts plus the upstream release stream.

**Enumeration surface (exhaustive by construction):** `https://code.claude.com/docs/sitemap.xml`
(named by `https://code.claude.com/robots.txt`, fetched 2026-08-17) → 187 `/docs/en/` page URLs.
Local items enumerated by `ls` over the repo (Tier 0). Upstream releases enumerated via the
`anthropics/claude-code` release/changelog stream.

**Explicit narrowing.** 187 English pages is far more than this question set needs. The ledger
covers the pages whose titles/paths bear on permission modes, permission rules, hooks, skills
frontmatter, settings files, the `~/.claude` directory, the built-in commands named in the brief,
and the recency gate — plus the local artifacts and the release stream. **Cut and why:** the ~160
pages covering IDE integrations, gateways/self-hosted deployment, billing/analytics, memory,
output styles, MCP, and per-platform setup carry no permission-decision or hook-decision semantics
for this question set. Non-English locale duplicates of the same pages are cut as duplicates.
Anything from a cut page that turns out to matter is reported as a Gap rather than assumed absent.

**Second narrowing, recorded at Phase 3.** Four enumerated rows were cut rather than covered, each
for a stated reason, so the ledger reports a scoped answer rather than an unfinished one:

- **docs/en/agent-sdk/permissions** and **docs/en/agent-sdk/hooks** — cut. They restate the CLI model
  for SDK embedders. The CLI-side pages (rows 4 and 6) are the normative surface for the operator's
  question, which is about an interactive skill, and the SDK pages would corroborate from the same
  publishing pool rather than independently.
- **docs/en/changelog** and **docs/en/whats-new** — cut as duplicates of row 20. The upstream
  `CHANGELOG.md` was fetched this turn and is the deeper artifact of the same class; it settled the
  recency gate and supplied the v2.1.211 entry directly.

**One row could not be completed and is reported as a Gap, not as covered:** the maintainer's
long-form auto-mode writeups (`anthropic.com/engineering/claude-code-auto-mode` and
`claude.com/blog/auto-mode`), which the docs themselves link as the deep dive. Both were unreachable
after escalation — see the fetch log.

| # | Corpus item | Depth criterion | Done |
|---|-------------|-----------------|------|
| 1 | docs/en/permission-modes | Mode inventory table, auto-mode section, classifier decision order, protected-path rules, and "which mode a session starts in" all read end to end | [x] |
| 2 | docs/en/permissions | Rule syntax, decision precedence (deny/ask/allow), settings-file precedence, and the Read/Edit path-anchor section read end to end | [x] |
| 3 | docs/en/auto-mode-config | Every configurable key and each "what auto mode does/does not suspend" statement read end to end | [x] |
| 4 | docs/en/hooks | PreToolUse section, `permissionDecision` value set, precedence vs permission modes, and any statement about auto/bypassPermissions interaction read end to end | [x] |
| 5 | docs/en/hooks-guide | Any worked example of a PreToolUse deny/ask gate, and any statement about which modes hooks survive, read end to end | [x] |
| 6 | docs/en/settings | `permissions` key set, `defaultMode`, settings-file locations and precedence, and any note on protected settings read end to end | [x] |
| 7 | docs/en/skills | Frontmatter key inventory — specifically whether `disallowed-tools` exists and what `allowed-tools` grants/does not grant — read end to end | [x] |
| 8 | docs/en/tools-reference | AskUserQuestion entry read end to end: what it does, whether it is permission-gated, whether any mode auto-answers it | [x] |
| 9 | docs/en/security | Permission-system description and any statement about protected paths / self-modification read end to end | [x] |
| 10 | docs/en/security-guidance | Any guidance on tools that modify the user's own configuration read end to end | [x] |
| 11 | docs/en/sandboxing | Whether sandbox/filesystem rules treat `~/.claude` differently from project paths — relevant section read | [x] |
| 14 | docs/en/plugins-reference | What a plugin's own `settings.json` may contain, and the hooks a plugin may ship — relevant rows read | [x] |
| 15 | docs/en/commands | Built-in `/doctor` and `/config` entries read; whether either documents a confirmation step | [x] |
| 16 | docs/en/debug-your-config | `/doctor` behavior read end to end — does it write, and does it confirm | [x] |
| 17 | docs/en/claude-directory | Layout of `~/.claude` and any statement that it is a protected/special path, read end to end | [x] |
| 20 | Upstream release stream (`anthropics/claude-code` CHANGELOG.md / releases) | Latest release confirmed this turn; entries at/around v2.1.232 checked for permission-mode, hook-decision, or settings-protection changes — this is the recency-gate artifact | [x] |
| 21 | repo: `plugins/claude-config/skills/audit-permission-state` | The skill's own text read end to end; the specific "auto mode drops rules" wording located and its cited basis identified | [x] |
| 22 | repo: `docs/conventions/permission-rule-hygiene/README.md` | Read end to end and reconciled claim-by-claim against items 1-3 | [x] |
| 23 | repo: sibling skills that mutate settings.json (`claude-config:setup`, `update-config`) | Their confirmation posture read — what an existing settings-mutating skill in this ecosystem does before writing | [x] |
| 24 | docs/en/sub-agents (agent frontmatter) | Whether an agent/subagent frontmatter denylist (`disallowedTools`) exists and whether it is enforced independently of permission mode — relevant section read | [x] |
