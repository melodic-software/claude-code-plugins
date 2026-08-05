# MCP Tool Audit Checklist

19 criteria (C1-C19) derived from three upstream authorities, cited so the current text governs — do not
recap them here, read them at the source:

- [MCP specification 2025-11-25 — Tools](https://modelcontextprotocol.io/specification/2025-11-25/server/tools)
- [Anthropic — Writing effective tools for AI agents](https://www.anthropic.com/engineering/writing-tools-for-agents)
- [Claude Code — Connect Claude Code to tools via MCP](https://code.claude.com/docs/en/mcp) — Claude-Code-specific client behavior: `_meta` annotations and truncation limits

## Authority tag (provenance) vs severity (impact)

Each criterion carries an **authority** tag naming where the requirement comes from, and a **severity**
naming how much a violation hurts. They are independent — a low-authority criterion can be high-impact.

| Authority | Meaning | Source |
|---|---|---|
| **SPEC-MUST** | The MCP spec mandates it (**MUST**) | MCP spec |
| **SPEC-SHOULD** | The MCP spec recommends it (**SHOULD**) | MCP spec |
| **SPEC-OPTIONAL** | The spec defines it as OPTIONAL — a missing value is never a spec violation | MCP spec |
| **ANTHROPIC** | Anthropic tool-design engineering guidance | Anthropic article |
| **OPINION** | A design judgment with no upstream mandate (e.g. a client-specific limit or heuristic) | this skill — for C4 and C17-C19 the client-behavior facts are cited from the Claude Code page, which documents that behavior rather than mandating the criterion |

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
| C4 | **Within size budget** — Claude Code truncates tool descriptions and server instructions at 2KB each | OPINION | FAIL | Estimate character count — per tool description, and once per server for the server `instructions` field. Over ~2000 characters risks truncation; critical details belong near the start. This is a client limit, not a spec rule |
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

When auditing SOURCE, accept each SDK's native spelling of these hints as satisfying the criterion — e.g. .NET `[McpServerTool(ReadOnly = true, Destructive = false, Idempotent = true)]` attribute properties, FastMCP `annotations=` arguments — not only literal `readOnlyHint`/`destructiveHint`/`idempotentHint` keys; the SDK maps them to the wire-level annotations.

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
| C16 | **Callable from schema alone; input schema valid** — the tool description plus parameter descriptions let an LLM construct a valid call with zero system prompt, and the tool's input schema is valid | ANTHROPIC + SPEC-MUST | WARN (FAIL if the input schema is missing or invalid) | The spec requires the wire-level `inputSchema` to be a valid JSON Schema object (not `null`). When auditing SOURCE (not a live server), SDK-native schema forms count as valid — the SDK converts them for the protocol: TypeScript Zod schemas / raw shapes (`inputSchema: { boardId: z.string() }`), Python type hints (FastMCP), .NET method signatures. FAIL only when the schema is missing, `null`, or malformed in its own idiom. Self-sufficiency: if you showed only this tool's schema to an LLM with no other context, could it make a valid call? Domain concepts referenced without explanation = warn |

## 7. Claude Code `_meta` annotations (C17-C19)

Claude-Code-specific per-tool annotations set in the tool's `tools/list` response `_meta` object,
documented in the Claude Code MCP page cited above — client behavior, not MCP-spec requirements, so
every one is authority OPINION. A missing annotation here is at most info (an advisory that the server
could benefit), and for C19 not a finding at all. Two defect shapes:

- **Declared but ineffective** — Claude Code caps or ignores the value (C17 above the 500,000-character
  ceiling or on an image-returning tool; C18 set to anything but the JSON boolean `true`). WARN
  generally, FAIL for `anthropic/requiresUserInteraction`, where a silently ignored value ships a
  consent gate that never fires.
- **Declared, honored, and unwarranted** — Claude Code applies the value exactly as asked, and that is
  the cost (C19 declared where no turn needs the tool, or across many of a server's tools, spending
  session-start context deferral would have saved). WARN.

When auditing SOURCE, accept each SDK's native way of attaching `_meta` to a tool's `tools/list` entry
— the `meta=` dict argument on Python's `@mcp.tool`, the `_meta` field of the config object passed to
TypeScript's `server.registerTool`, .NET's repeatable `[McpMeta("<key>", <value>)]` attribute on the
`[McpServerTool]` method — not only a literal `_meta` key in source; the SDK maps them to the wire-level
field. C18 turns on the value's JSON type, so read it in that language's own syntax — see
**meta-extraction** in [server-discovery.md](server-discovery.md).

| # | Criterion | Authority | Severity | How to evaluate |
|---|-----------|-----------|----------|-----------------|
| C17 | **`anthropic/maxResultSizeChars` on inherently-large-output tools** — a tool whose text results are inherently large (full schemas, file trees, whole-board dumps) declares its own result-size ceiling | OPINION | info (WARN if set ineffectively) | Missing on a large-output tool = info: without it, results over the default threshold are persisted to disk and replaced with a file reference; with it, Claude Code raises that tool's threshold to the annotated value, up to a hard ceiling of 500,000 characters, independently of `MAX_MCP_OUTPUT_TOKENS`. Set above 500,000 (the excess never applies) or on a tool returning image content (the annotation only governs text; images stay subject to `MAX_MCP_OUTPUT_TOKENS`) = WARN |
| C18 | **`anthropic/requiresUserInteraction` set — as JSON `true` — where per-call consent is the point** — a tool whose permission prompt is itself the point (a consent or access-grant step where auto-approval would mean no human ever agreed) declares it | OPINION | info (FAIL if set to any value other than JSON `true`) | Missing on a consent-shaped tool = info. Declared with any value other than the JSON boolean `true` (e.g. the string `"true"`, `1`) = FAIL — Claude Code ignores every other value, so the intended consent gate silently never applies. When honored, Claude Code prompts on every call even in `acceptEdits`, `auto`, and `bypassPermissions` modes, offers no "don't ask again", and allow rules don't skip the prompt; `dontAsk` mode denies the call instead. Requires Claude Code v2.1.199+; earlier versions ignore the annotation and apply the standard permission flow |
| C19 | **`anthropic/alwaysLoad` reserved for genuinely always-needed tools** — `"anthropic/alwaysLoad": true` exempts that one tool from tool-search deferral so it loads into context at session start | OPINION | info (WARN if over-declared) | Absence is never a finding — deferral is the correct default, and "needed on every turn" is not inferable from source. Declared on a tool with no every-turn case, or on many of a server's tools (defeating deferral — each upfront tool consumes context), = WARN. The server-level `alwaysLoad: true` config field (Claude Code v2.1.121+) exempts a whole server; the per-tool `_meta` form has the same effect for that tool only |

## Scoring

- **19 criteria** across 7 categories.
- Per-tool score: count of PASS / WARN / FAIL.
- Per-server score: aggregate across all tools.
- **Priority order for fixes:** FAIL first, then WARN on high-traffic tools, then info items.
