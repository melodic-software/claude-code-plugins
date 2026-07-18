# RESEARCH — Runtime sandbox bar for autonomous runs (#245)

Task: vet/validate the proposed isolation-level ladder + autonomy floor for wayfind item #245.

## Summary

The originally proposed floor — per-command OS sandbox (L1) sufficient for agent-internal autonomous runs, ephemeral environment (L2) only for externally-triggered runs — is **falsified by the vendor primary**. Anthropic states the built-in sandboxed Bash tool "on its own constrains only Bash, so it is not sufficient for fully unattended runs in either mode" (MCP servers, hooks, and file tools run unconstrained on the host). The trigger-source axis is also wrong: untrusted content reaches agent-internal runs through repo files, dependencies, and fetched web content, not just external signals (lethal-trifecta framing; Copilot treats issue content as an injection vector and filters it). Correct floor: **whole-process OS-enforced boundary for ANY unattended run**, with kernel-separated environments for untrusted-repo / compliance-driven cases.

## Evidence table

| Claim | Sources (fetched this turn) | Tier | Confidence |
|---|---|---|---|
| Per-command Bash sandbox insufficient for fully unattended runs; MCP/hooks/file tools outside its boundary | code.claude.com/docs/en/sandbox-environments (verbatim) | 1 | HIGH |
| Unattended (`--dangerously-skip-permissions`/auto mode) requires container, VM, or whole-process sandbox runtime; auto-mode classifier is per-action control, not isolation | same page | 1 | HIGH |
| Untrusted repository work: dedicated VM or Anthropic-hosted web surface | same page ("Work on an untrusted repository" row) | 1 | HIGH |
| Built-in sandbox: macOS Seatbelt / Linux+WSL2 bubblewrap; native Windows unsupported (container/VM or WSL2 on Windows hosts); GA; credential deny (v2.1.187+) / mask (v2.1.199+); hostname-based proxy, no TLS inspection by default → domain-fronting exfil caveat, "not a complete isolation boundary" | code.claude.com/docs/en/sandboxing | 1 | HIGH |
| Whole-process wrap exists free without Docker: `@anthropic-ai/sandbox-runtime`, beta research preview, active (v0.0.65, pushed 2026-07-16) | sandbox-environments page + gh api anthropic-experimental/sandbox-runtime | 0/1 | HIGH |
| Issue-driven agents face prompt injection from issue/comment content; vendor mitigations = ephemeral isolated env + egress restriction + hidden-char filtering + human merge gate + scanning before PR completion | docs.github.com Copilot cloud agent risks-and-mitigations | 1 | HIGH |
| Untrusted-content leg includes any attacker-writable text the agent reads (issues, email, MCP results); mitigation = never combine private-data access + untrusted content + exfil channel | simonwillison.net lethal-trifecta (named authority) + langchain/Northflank/Modal 2026 posts (corroborators) | 2 (authority) | HIGH (concept) |
| CodeQL CLI barred on non-open-source codebases without GHAS/Code Security license (re-verifies #241 record) | docs.github.com + github/codeql-cli-binaries LICENSE.md (via GitHub-owned doc excerpts; direct LICENSE fetch not performed) | 1* | HIGH |
| Recency: claude-code v2.1.212 (2026-07-17, gh api); CodeQL CLI v2.26.1 (gh api) | gh api this turn | 0 | HIGH |

## Revised isolation ladder (tool-agnostic contract vocabulary)

| Level | Boundary | Qualifies for | Free-path instances (illustrative, not contract) |
|---|---|---|---|
| L0 | None beyond worktree + VCS perms (branch protection, scoped token) | attended interactive only | today's fleet state |
| L1 | Per-command OS sandbox (Bash-only; other tools/MCP/hooks on host) | attended ergonomics (fewer prompts); NOT an autonomy tier | Claude Code `/sandbox`, `codex --sandbox` |
| L2 | Whole-process OS-enforced boundary + default-deny egress + credential protection | minimum for ANY unattended run | sandbox-runtime wrap (beta, no Docker), devcontainer/custom container w/ default-deny firewall |
| L3 | Kernel-separated ephemeral environment (VM/microVM/hosted vendor surface) | untrusted repos; policy-required kernel separation | Claude Code on the web (plan-dependent), local hypervisor; microVM infra = cost, discuss-first |

Axes: attendance (attended vs unattended) × input provenance (who can write to what the agent reads). Trigger source dropped as an axis — it was a proxy for provenance and leaks (repo content is untrusted input in internal runs too).

Attached properties at L2+: default-deny egress + domain allowlist (hostname-only filtering caveat noted — domain fronting), credential deny/mask/short-lived scoped tokens, human merge gate (queue/audit side, #240/#243).

## Conflicts

None between primaries. Blog consensus aligned with Anthropic primary.

## Gaps

- CodeQL LICENSE.md not fetched directly (SERP-quoted GitHub-owned sources only) — non-load-bearing for #245.
- Cursor/other-harness whole-process isolation equivalents unverified — irrelevant to contract (instances are org-supplied), verify at guided-setup time per #241 pattern.

## Next-stage handoff

Settled: ladder vocabulary above; unattended floor = L2; L3 driver = input provenance/compliance; Windows fallback path; per-work-class assignment belongs to #243.
Open (user): adopt revised ladder + uniform L2 floor? L2-unavailable fallback posture (block autonomy vs degrade-with-flag)?
