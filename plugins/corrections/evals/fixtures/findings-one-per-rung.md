---
type: review-findings
date: 2026-01-01T00:00:00Z
branch: fixture
tier: medium
---

## Findings

| Rank | Tier | Confidence | Location | Surface(s) | Finding | Action |
|------|------|------------|----------|------------|---------|--------|
| 1 | SUGGESTION | high | src/Api/Ordering.cs:14 | code-reviewer | Field ordering and brace placement drift from the rest of the file. | Set the ordering and brace rules in `.editorconfig` and let the formatter apply them. |
| 2 | IMPORTANT | high | docs/onboarding.md:3 | ai-slop:audit | ai-slop/audit/rule-em-dash fired=1 excerpt=a dash character in prose | Rewrite the sentence without the character. |
| 3 | IMPORTANT | medium | src/Api/Clock.cs:41 | code-reviewer | Calls `DateTime.Now` directly instead of the injected clock abstraction, so the type is untestable. | Ban the API in a project analyzer and route callers through the clock. |
| 4 | CRITICAL | high | src/Api/Search.ts:88 | security-reviewer | Builds a query string by concatenation, so an attacker-controlled term reaches the engine unescaped. The union type `string \| null` hides the empty case. | Match the concatenation shape and parameterize the query. |
| 5 | IMPORTANT | high | src/Web/Startup.cs:20 | architecture-guardian | The web layer references the persistence assembly directly, inverting the declared dependency direction. | Assert the layer boundary and route through the application layer. |
| 6 | SUGGESTION | medium | .github/workflows/ci.yml:1 | doc-drift-detector | The generated cheat sheet was committed stale; nothing observes the regeneration at commit time. | Observe the generated-file freshness at commit time. |
| 7 | IMPORTANT | medium | src/Api/Ordering.cs:96 | code-reviewer | The retry loop's exit reasoning is hard to follow and the naming hides which branch is the success path. | Rework the loop so the success path reads first. |

## By dimension

### security

| Rank | Tier | Confidence | Location | Surface(s) | Finding | Action |
|------|------|------------|----------|------------|---------|--------|
| 4 | CRITICAL | high | src/Api/Search.ts:88 | security-reviewer | Builds a query string by concatenation, so an attacker-controlled term reaches the engine unescaped. The union type `string \| null` hides the empty case. | Match the concatenation shape and parameterize the query. |
| 5 | IMPORTANT | high | src/Web/Startup.cs:20 | architecture-guardian | The web layer references the persistence assembly directly, inverting the declared dependency direction. | Assert the layer boundary and route through the application layer. |
| 6 | SUGGESTION | medium | .github/workflows/ci.yml:1 | doc-drift-detector | The generated cheat sheet was committed stale; nothing observes the regeneration at commit time. | Observe the generated-file freshness at commit time. |

### docs

| Rank | Tier | Confidence | Location | Surface(s) | Finding | Action |
|------|------|------------|----------|------------|---------|--------|
| 1 | SUGGESTION | high | src/Api/Ordering.cs:14 | code-reviewer | Field ordering and brace placement drift from the rest of the file. | Set the ordering and brace rules in `.editorconfig` and let the formatter apply them. |
| 2 | IMPORTANT | high | docs/onboarding.md:3 | ai-slop:audit | ai-slop/audit/rule-em-dash fired=1 excerpt=a dash character in prose | Rewrite the sentence without the character. |
| 3 | IMPORTANT | medium | src/Api/Clock.cs:41 | code-reviewer | Calls `DateTime.Now` directly instead of the injected clock abstraction, so the type is untestable. | Ban the API in a project analyzer and route callers through the clock. |
| 7 | IMPORTANT | medium | src/Api/Ordering.cs:96 | code-reviewer | The retry loop's exit reasoning is hard to follow and the naming hides which branch is the success path. | Rework the loop so the success path reads first. |

## Unparsed

None.

## Surfaces

Ran: code-reviewer, security-reviewer, architecture-guardian, doc-drift-detector, ai-slop:audit. Returned no result: ci-log-auditor (no run to audit).
