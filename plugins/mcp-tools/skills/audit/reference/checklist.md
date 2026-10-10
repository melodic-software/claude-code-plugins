# MCP Tool Audit Checklist

19 criteria (C1-C19) derived from three upstream authorities, cited so the current text governs. Do
not recap them here, read them at the source:

- [MCP specification 2026-07-28: Tools](https://modelcontextprotocol.io/specification/2026-07-28/server/tools)
  (Spec revision record below)
- [Define tools: best practices for tool definitions](https://platform.claude.com/docs/en/agents-and-tools/tool-use/define-tools#best-practices-for-tool-definitions)
  (correlate with [Anthropic: Writing effective tools for AI agents](https://www.anthropic.com/engineering/writing-tools-for-agents))
- [Claude Code: Connect Claude Code to tools via MCP](https://code.claude.com/docs/en/mcp). Claude-Code-specific client behavior: `_meta` annotations and result-size limits

**Client-behavior record.** C17 and C18 act on values this skill holds as its own settings. C17
treats 500,000 characters as the ceiling above which a declared `anthropic/maxResultSizeChars`
value no longer applies, and treats a tool returning image content as outside that annotation. C18
treats only the JSON boolean `true` as an effective `anthropic/requiresUserInteraction`, and grades
any other value FAIL because the consent prompt it was meant to force never fires. C19 treats a
tool's `anthropic/alwaysLoad: false` as a deliberate opt-out that keeps the tool deferred even when
the server's own config loads it upfront, honored only for the server sources the per-tool pointer
names.

- **Pointer**: for the result-size annotation, see
  <https://code.claude.com/docs/en/mcp#raise-the-limit-for-a-specific-tool> and
  <https://code.claude.com/docs/en/mcp#images-in-tool-results>; for the per-call approval
  annotation, see <https://code.claude.com/docs/en/mcp#require-approval-for-a-specific-tool>; for
  per-tool deferral and which server sources honor `false`, see
  <https://code.claude.com/docs/en/mcp#per-tool-alwaysload>; for the server-level field, see
  <https://code.claude.com/docs/en/mcp#exempt-a-server-from-deferral>.
- **As of**: 2026-10-10 (per-tool deferral); 2026-09-06 (the other values)
- **Recheck trigger**: the page moves any of these values, or changes which server sources honor a
  per-tool `false`, or a release note names MCP `_meta` annotations.

**Description length record.** C4 holds each tool description and each server `instructions` field
to a floor this skill chose; the number sits in the C4 row as this skill's own rule. C4 warns
rather than fails past that floor, because whether a given client cuts there is read at the
pointer, not decided here. C4 ignores the session-level override
`CLAUDE_CODE_MAX_MCP_DESCRIPTION_LENGTH`, which the server author does not control.

- **Pointer**: when grading C4 or revisiting its number, fetch
  <https://code.claude.com/docs/en/changelog> (versions 2.1.295 and 2.1.296) and
  <https://code.claude.com/docs/en/mcp#tool-search-for-mcp-server-authors> live; for the override,
  <https://code.claude.com/docs/en/env-vars#variables>.
- **Source conflict**: the mcp page
  (<https://code.claude.com/docs/en/mcp#tool-search-for-mcp-server-authors>) and the env-vars page
  (<https://code.claude.com/docs/en/env-vars#variables>) disagree with changelog 2.1.295 and
  2.1.296 (<https://code.claude.com/docs/en/changelog>) on the MCP description and instructions
  length limits.
- **As of**: 2026-10-10
- **Recheck trigger**: the mcp page changes its stated default or states a limit per load path, or
  a release note names MCP description or instructions truncation.

**Spec revision record.** The audit grades its SPEC-tagged criteria against the MCP revision Claude
Code negotiates by default. Moving to that revision changed no criterion here; tool rules the
revision added are not yet criteria.

- **Pointer**: when grading a SPEC-tagged criterion, fetch
  <https://modelcontextprotocol.io/specification/2026-07-28/server/tools> live; for which revision
  Claude Code negotiates, <https://code.claude.com/docs/en/mcp#mcp-client-runtimes>; for what the
  revision changed, <https://modelcontextprotocol.io/specification/2026-07-28/changelog>.
- **As of**: 2026-10-10
- **Recheck trigger**: a newer spec revision becomes the one Claude Code negotiates by default, or a
  release note names the MCP protocol revision.

## Authority tag (provenance) vs severity (impact)

Each criterion carries an **authority** tag naming where the requirement comes from, and a **severity**
naming how much a violation hurts. They are independent. A low-authority criterion can be high-impact.

| Authority | Meaning | Source |
|---|---|---|
| **SPEC-MUST** | The MCP spec mandates it (**MUST**) | MCP spec |
| **SPEC-SHOULD** | The MCP spec recommends it (**SHOULD**) | MCP spec |
| **SPEC-OPTIONAL** | The spec defines it as OPTIONAL, so a missing value is never a spec violation | MCP spec |
| **ANTHROPIC** | Anthropic tool-design guidance | The define-tools section above |
| **OPINION** | A design judgment with no upstream mandate (e.g. a client-specific limit or heuristic) | this skill. For C4 and C17-C19 the client-behavior facts are cited from the Claude Code page and changelog, which document that behavior rather than mandating the criterion |

Severity levels:

- **FAIL**. Likely to cause incorrect tool selection or a broken call. Fix before shipping.
- **WARN**. Degrades tool quality or LLM comprehension. Fix in the next improvement pass.
- **info**. An optimization opportunity. Address when convenient.

## 1. Description quality (C1-C5)

| # | Criterion | Authority | Severity | How to evaluate |
|---|-----------|-----------|----------|-----------------|
| C1 | **Has "what"**. The description states what the tool does | ANTHROPIC | FAIL | First sentence should clearly describe the action. Missing or generic ("handles X") fails |
| C2 | **Has "when"**. The description states when to use the tool | ANTHROPIC | WARN | Look for usage context: "Use this when...", "Call this before...", "Useful for...". Absent = warn |
| C3 | **Has "returns"**. The description states what the tool returns | ANTHROPIC | WARN | Look for return documentation: "Returns the board id and...", "Returns a list of...". Absent = warn |
| C4 | **Within the length floor**. A tool description, and a server `instructions` field, fits within the floor this skill holds (Description length record) | OPINION | WARN | Count characters, per tool description and once per server for the server `instructions` field. Over 2,048 characters warns: text past this floor may be cut before it reaches the model, depending on the client (read at the record's pointer). Critical details belong near the start, where truncation cannot reach them. The floor is this skill's rule built on client behavior, not a spec rule |
| C5 | **No implementation-detail leak**. No database types, API names, partition keys, or internal structure | ANTHROPIC | WARN | Prefer semantic names over technical identifiers. Scan for terms that belong to the implementation, not the domain |

## 2. Parameter quality (C6-C8)

| # | Criterion | Authority | Severity | How to evaluate |
|---|-----------|-----------|----------|-----------------|
| C6 | **Every parameter has a description** | ANTHROPIC | FAIL | Check each param. TS: `.describe()` on Zod schemas. Python: docstring param docs or annotation context. .NET: `[Description]`. Missing = fail, since an undescribed parameter blocks a correct call |
| C7 | **Descriptions guide to the right value, with a format example for non-obvious types** | ANTHROPIC | WARN | Value guidance ("Use 30 for short-term, 90 for long-term") plus examples for dates/URIs/hex/enums ("ISO 8601, e.g. 2025-01-15T10:00:00Z"). Bare type restatement ("the board id") = warn |
| C8 | **Optional parameters marked optional with documented defaults** | OPINION | info | Optional params should note they are optional and document the default: "Optional: max results (default: 50)". Missing default = info |

## 3. Naming (C9-C11)

| # | Criterion | Authority | Severity | How to evaluate |
|---|-----------|-----------|----------|-----------------|
| C9 | **Name charset and length valid**. 1-128 chars; only `A-Z a-z 0-9 _ - .`; no spaces or special characters | SPEC-SHOULD | FAIL | Graded against the spec's naming SHOULD (pointer above), with these limits as this check's settings. A name with spaces, punctuation, or over 128 chars can break selection |
| C10 | **Outcome-driven name; passes the "can you ___?" test** | OPINION | WARN | `complete_todo` (good) vs `update_todo_status` (bad). Pure CRUD names (`create_X`, `get_X`) for generic entities = warn. CRUD is acceptable for genuinely generic operations (boards, items). "Can you [tool_name]?" should sound natural |
| C11 | **Service-namespaced**. The name includes a service prefix when ambiguity is possible | ANTHROPIC | info | `miro_create_board` (good) vs `create_board` (ambiguous across servers). Flag a bare resource name where several servers could connect; weigh it against how many servers connect |

## 4. Annotations (C12-C14)

The spec defines tool annotations as OPTIONAL, so every criterion here is WARN or info, never FAIL.

When auditing SOURCE, accept each SDK's native spelling of these hints as satisfying the criterion, not only literal `readOnlyHint`/`destructiveHint`/`idempotentHint` keys. Native spellings include .NET `[McpServerTool(ReadOnly = true, Destructive = false, Idempotent = true)]` attribute properties and the Python SDK's `annotations=` argument. The SDK maps them to the wire-level annotations.

| # | Criterion | Authority | Severity | How to evaluate |
|---|-----------|-----------|----------|-----------------|
| C12 | **readOnlyHint set on read-only tools** | SPEC-OPTIONAL | WARN | Tools that only read (list, get, search, check) should declare `readOnlyHint: true`. Missing on a read-only tool = warn |
| C13 | **destructiveHint appropriate on destructive tools** | SPEC-OPTIONAL | WARN | This check takes the spec's default for `destructiveHint` as `true`. Verify a tool that deletes/removes/purges is genuinely destructive (default appropriate), or a non-destructive tool overrides to `false` |
| C14 | **idempotentHint set on idempotent tools** | SPEC-OPTIONAL | info | Tools safe to call repeatedly with the same args (set operations, upserts) should declare `idempotentHint: true`. Missing = info |

## 5. Granularity (C15)

| # | Criterion | Authority | Severity | How to evaluate |
|---|-----------|-----------|----------|-----------------|
| C15 | **Workflow-shaped consolidation**. A tool represents a complete outcome, not a raw API endpoint, and related operations are not split into too many fine-grained tools | ANTHROPIC | WARN | Flag one tool per raw API call where a workflow-shaped tool (`schedule_event`, `get_customer_context`) would carry the whole outcome. If achieving one obvious goal requires chaining several tools, granularity is too low; if several tools could be one tool with a mode parameter, it is too high. Generic composition (search then get details) is acceptable when intermediate results inform decisions |

## 6. Schema self-sufficiency (C16)

| # | Criterion | Authority | Severity | How to evaluate |
|---|-----------|-----------|----------|-----------------|
| C16 | **Callable from schema alone; input schema valid**. The tool description plus parameter descriptions let an LLM construct a valid call with zero system prompt, and the tool's input schema is valid | ANTHROPIC + SPEC-MUST | WARN (FAIL if the input schema is missing or invalid) | Graded against the spec's MUST: the wire-level `inputSchema` has to be a valid JSON Schema object (not `null`). When auditing SOURCE (not a live server), SDK-native schema forms count as valid, since the SDK converts them for the protocol: TypeScript Zod schemas / raw shapes (`inputSchema: { boardId: z.string() }`), Python type hints, .NET method signatures. FAIL only when the schema is missing, `null`, or malformed in its own idiom. Self-sufficiency: if you showed only this tool's schema to an LLM with no other context, could it make a valid call? Domain concepts referenced without explanation = warn |

## 7. Claude Code `_meta` annotations (C17-C19)

Claude-Code-specific per-tool annotations set in the tool's `tools/list` response `_meta` object,
documented in the Claude Code MCP page cited above. They are client behavior, not MCP-spec
requirements, so every one is authority OPINION. A missing annotation here is at most info (an
advisory that the server could benefit), and for C19 not a finding at all. Two defect shapes:

- **Declared but ineffective**. Claude Code caps or ignores the value (C17 above the 500,000-character
  ceiling or on an image-returning tool; C18 set to anything but the JSON boolean `true`). WARN
  generally, FAIL for `anthropic/requiresUserInteraction`, where a silently ignored value ships a
  consent gate that never fires.
- **Declared, honored, and unwarranted**. Claude Code applies the value exactly as asked, and that is
  the cost (C19 declared `true` where no turn needs the tool, or across many of a server's tools, spending
  session-start context deferral would have saved). WARN.

When auditing SOURCE, accept each SDK's native way of attaching `_meta` to a tool's `tools/list` entry,
not only a literal `_meta` key in source: the `meta=` dict argument on Python's `@mcp.tool`, the
`_meta` field of the config object passed to TypeScript's `server.registerTool`, and .NET's repeatable
`[McpMeta("<key>", <value>)]` attribute on the `[McpServerTool]` method. The SDK maps them to the
wire-level field. C18 turns on the value's JSON type, so read it in that language's own syntax. See
**meta-extraction** in [server-discovery.md](server-discovery.md).

| # | Criterion | Authority | Severity | How to evaluate |
|---|-----------|-----------|----------|-----------------|
| C17 | **`anthropic/maxResultSizeChars` on inherently-large-output tools**. A tool whose text results are inherently large (full schemas, file trees, whole-board dumps) declares its own result-size ceiling | OPINION | info (WARN if set ineffectively) | Missing on a large-output tool = info: the tool's large text results fall back to the client's default handling (Client-behavior record). Set above 500,000 (this check's ceiling; the excess never applies) or on a tool returning image content (outside the annotation, per the record) = WARN |
| C18 | **`anthropic/requiresUserInteraction` set, as JSON `true`, where per-call consent is the point**. A tool that exists to collect a person's go-ahead (granting access, accepting terms), so that approving it without a prompt would defeat its purpose, declares it | OPINION | info (FAIL if set to any value other than JSON `true`) | Missing on a consent-shaped tool = info. Declared with any value other than the JSON boolean `true` (e.g. the string `"true"`, `1`) = FAIL, because the intended consent gate silently never applies. How an honored annotation behaves in each permission mode is read at the Client-behavior record's pointer, not restated here |
| C19 | **`anthropic/alwaysLoad` reserved for genuinely always-needed tools**. `"anthropic/alwaysLoad": true` opts that one tool out of tool-search deferral | OPINION | info (WARN if over-declared) | Absence is never a finding. Deferral is the correct default, and "needed on every turn" is not inferable from source. Declared `true` on a tool with no every-turn case, or on many of a server's tools (defeating deferral, since each upfront tool spends context), = WARN. Declared `false` is never a finding: it keeps a heavy tool deferred when a user configures the whole server to load upfront, on the server sources the Client-behavior record's pointer names, so it is the opt-out to suggest for a large tool on a server whose docs recommend the server-level `alwaysLoad`. Its absence is not a finding either: make that suggestion in the fix guidance, unscored, never as an info count. That server-level config field itself is client configuration, outside this audit |

## Scoring

- **19 criteria** across 7 categories.
- Per-tool score: count of PASS / WARN / FAIL / info.
- Per-server score: those counts aggregated across the server's tools **plus** its server-level
  criterion outcomes (C4's per-server `instructions` clause), so nothing evaluated is dropped. `n/a`
  and `undetermined` arise only at server level; they are reported in the server-level row and never
  folded into a severity count.
- **Priority order for fixes:** FAIL first, then WARN on high-traffic tools, then info items.
