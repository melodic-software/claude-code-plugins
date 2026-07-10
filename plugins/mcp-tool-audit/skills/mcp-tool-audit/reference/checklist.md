# MCP Tool Audit Checklist

16 criteria (C1-C16) derived from two upstream authorities, cited so the current text governs — do not
recap them here, read them at the source:

- [MCP specification 2025-11-25 — Tools](https://modelcontextprotocol.io/specification/2025-11-25/server/tools)
- [Anthropic — Writing effective tools for AI agents](https://www.anthropic.com/engineering/writing-tools-for-agents)

## Authority tag (provenance) vs severity (impact)

Each criterion carries an **authority** tag naming where the requirement comes from, and a **severity**
naming how much a violation hurts. They are independent — a low-authority criterion can be high-impact.

| Authority | Meaning | Source |
|---|---|---|
| **SPEC-MUST** | The MCP spec mandates it (**MUST**) | MCP spec |
| **SPEC-SHOULD** | The MCP spec recommends it (**SHOULD**) | MCP spec |
| **SPEC-OPTIONAL** | The spec defines it as OPTIONAL — a missing value is never a spec violation | MCP spec |
| **ANTHROPIC** | Anthropic tool-design engineering guidance | Anthropic article |
| **OPINION** | A design judgment with no upstream mandate (e.g. a client-specific limit or heuristic) | this skill |

Severity levels:

- **FAIL** — likely to cause incorrect tool selection or a broken call. Fix before shipping.
- **WARN** — degrades tool quality or LLM comprehension. Fix in the next improvement pass.
- **info** — optimization opportunity. Address when convenient.

**Annotations are OPTIONAL in the spec — a missing annotation is WARN or info, never FAIL.**

## 1. Description quality (C1-C5)

| # | Criterion | Authority | Severity | How to evaluate |
|---|-----------|-----------|----------|-----------------|
| C1 | **Has "what"** — the description states what the tool does | ANTHROPIC | FAIL | First sentence should clearly describe the action. Missing or generic ("handles X") fails |
| C2 | **Has "when"** — the description states when to use the tool | ANTHROPIC | WARN | Look for usage context: "Use this when...", "Call this before...", "Useful for...". Absent = warn |
| C3 | **Has "returns"** — the description states what the tool returns | ANTHROPIC | WARN | Look for return documentation: "Returns the board id and...", "Returns a list of...". Absent = warn |
| C4 | **Within size budget** — the description fits a client truncation limit (~2KB in Claude Code) | OPINION | FAIL | Estimate character count. Descriptions over ~2000 characters risk truncation. This is a client limit, not a spec rule |
| C5 | **No implementation-detail leak** — no database types, API names, partition keys, or internal structure | ANTHROPIC | WARN | Prefer semantic names over technical identifiers. Scan for terms that belong to the implementation, not the domain |

## 2. Parameter quality (C6-C8)

| # | Criterion | Authority | Severity | How to evaluate |
|---|-----------|-----------|----------|-----------------|
| C6 | **Every parameter has a description** | ANTHROPIC | FAIL | Check each param. TS: `.describe()` on Zod schemas. Python: docstring param docs or annotation context. .NET: `[Description]`. Missing = fail — an undescribed parameter blocks a correct call |
| C7 | **Descriptions guide to the right value, with a format example for non-obvious types** | ANTHROPIC | WARN | Value guidance ("Use 30 for short-term, 90 for long-term") plus examples for dates/URIs/hex/enums ("ISO 8601, e.g. 2025-01-15T10:00:00Z"). Bare type restatement ("the board id") = warn |
| C8 | **Optional parameters marked optional with documented defaults** | OPINION | info | Optional params should note they are optional and document the default: "Optional: max results (default: 50)". Missing default = info |

## 3. Naming (C9-C11)

| # | Criterion | Authority | Severity | How to evaluate |
|---|-----------|-----------|----------|-----------------|
| C9 | **Name charset and length valid** — 1-128 chars; only `A-Z a-z 0-9 _ - .`; no spaces or special characters | SPEC-SHOULD | FAIL | The spec says tool names SHOULD meet these constraints. A name with spaces, punctuation, or over 128 chars can break selection |
| C10 | **Outcome-driven name; passes the "can you ___?" test** | OPINION | WARN | `complete_todo` (good) vs `update_todo_status` (bad). Pure CRUD names (`create_X`, `get_X`) for generic entities = warn. CRUD is acceptable for genuinely generic operations (boards, items). "Can you [tool_name]?" should sound natural |
| C11 | **Service-namespaced** — the name includes a service prefix when ambiguity is possible | ANTHROPIC | info | `miro_create_board` (good) vs `create_board` (ambiguous across servers). Anthropic recommends service/resource namespacing; evaluate against how many servers connect |

## 4. Annotations (C12-C14)

The spec defines tool annotations as OPTIONAL — so every criterion here is WARN or info, never FAIL.

| # | Criterion | Authority | Severity | How to evaluate |
|---|-----------|-----------|----------|-----------------|
| C12 | **readOnlyHint set on read-only tools** | SPEC-OPTIONAL | WARN | Tools that only read (list, get, search, check) should declare `readOnlyHint: true`. Missing on a read-only tool = warn. This enables parallel execution in Claude Code |
| C13 | **destructiveHint appropriate on destructive tools** | SPEC-OPTIONAL | WARN | The spec defaults `destructiveHint` to `true`. Verify a tool that deletes/removes/purges is genuinely destructive (default appropriate), or a non-destructive tool overrides to `false` |
| C14 | **idempotentHint set on idempotent tools** | SPEC-OPTIONAL | info | Tools safe to call repeatedly with the same args (set operations, upserts) should declare `idempotentHint: true`. Missing = info |

## 5. Granularity (C15)

| # | Criterion | Authority | Severity | How to evaluate |
|---|-----------|-----------|----------|-----------------|
| C15 | **Workflow-shaped consolidation** — a tool represents a complete outcome, not a raw API endpoint, and related operations are not split into too many fine-grained tools | ANTHROPIC | WARN | Anthropic recommends consolidating multiple operations (or API calls) into workflow-shaped tools (`schedule_event`, `get_customer_context`), **not** one tool per API call. If achieving one obvious goal requires chaining several tools, granularity is too low; if several tools could be one tool with a mode parameter, it is too high. Generic composition (search then get details) is acceptable when intermediate results inform decisions |

## 6. Schema self-sufficiency (C16)

| # | Criterion | Authority | Severity | How to evaluate |
|---|-----------|-----------|----------|-----------------|
| C16 | **Callable from schema alone; input schema valid** — the tool description plus parameter descriptions let an LLM construct a valid call with zero system prompt, and `inputSchema` is a valid non-null JSON Schema object | ANTHROPIC + SPEC-MUST | WARN (FAIL if `inputSchema` is missing or not a valid JSON Schema object) | The spec requires `inputSchema` to be a valid JSON Schema object (not `null`) — a violation is FAIL. Self-sufficiency: if you showed only this tool's schema to an LLM with no other context, could it make a valid call? Domain concepts referenced without explanation = warn |

## Scoring

- **16 criteria** across 6 categories.
- Per-tool score: count of PASS / WARN / FAIL.
- Per-server score: aggregate across all tools.
- **Priority order for fixes:** FAIL first, then WARN on high-traffic tools, then info items.
