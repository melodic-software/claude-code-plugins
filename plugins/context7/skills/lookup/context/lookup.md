# Lookup workflow

Two-step library → docs pattern, query-writing guidance, result selection, common mistakes.

## Step 1: Resolve a library name to a Context7 library ID

```bash
# CLI
ctx7 library "<name>" "<query>"

# MCP
mcp__context7__resolve-library-id(libraryName: "<name>", query: "<query>")
```

- Use the **official library name** with proper punctuation: `"Next.js"` not `"nextjs"`, `"Customer.io"` not `"customerio"`, `"Three.js"` not `"threejs"`
- Always pass the `query` argument: it directly affects result ranking. Distill the user's intent into a focused library/topic query. That query disambiguates when multiple libraries share a name
- Queries are sent to Context7's backend. Never include secrets (API keys, passwords, credentials), personal data, proprietary code, pasted stack traces, or internal endpoints/identifiers. Send distilled library/topic terms only

## Result fields

The fields each result carries are listed in [Context7 CLI § Query Library Documentation](https://context7.com/docs/clients/cli#query-library-documentation).
How this skill reads them:

- **Library ID**: the `/org/project` identifier the next step passes
- **Code Snippets**: higher means better coverage
- **Source Reputation**: prefer High or Medium
- **Benchmark Score**: higher is better
- **Versions**: use a version-specific ID when the user specifies a version

## Selection process

1. Analyze the query to understand what library the user wants
2. Rank candidates by:
   - Name similarity to query (exact matches prioritized)
   - Description relevance
   - Code snippet count (coverage)
   - Source reputation (prefer High or Medium)
   - Benchmark score (higher is better)
3. If multiple good matches exist but one is clearly the most relevant, acknowledge the others and proceed with it
4. If no good matches exist, state this clearly and suggest a refined query
5. For ambiguous cases, where two or more candidates rank close and the query does not settle which one the user means, probe before asking: run the Step 2 docs query against the top two candidates (read-only; each query counts toward the 3-lookup limit in Common mistakes) and pick the one whose docs answer the question. In the reply, name the library ID you chose and the runner-up you rejected. When neither candidate's docs answer it, follow step 4. Ask the user only when both answer the question equally well, since the probe cannot settle that case

## Step 2: Query documentation

```bash
# CLI (Windows Git Bash requires MSYS_NO_PATHCONV=1 — see cli.md)
MSYS_NO_PATHCONV=1 ctx7 docs "<libraryId>" "<query>"

# MCP
mcp__context7__query-docs(libraryId: "/org/project", query: "<query>")
```

When you know the language the user writes in, run `ctx7 docs --help` once per session; pass `--language <name>` only if that output lists it, and omit it otherwise, so an older install still answers:

```bash
MSYS_NO_PATHCONV=1 ctx7 docs /websites/twilio "How to send an SMS" --language Ruby
```

- **Pointer**: when deciding whether `--language` exists and what it changes, read the installed
  CLI's `ctx7 docs --help` output live (the probe above).
- **Recheck trigger**: this plugin starts requiring a minimum `ctx7` version, which would let the
  probe go.

### Version-specific IDs

If the user mentions a specific version, use the version-specific ID:

```bash
# Latest indexed
MSYS_NO_PATHCONV=1 ctx7 docs /vercel/next.js "app router proxy"

# Version-specific (version format comes from the library result's Versions field)
MSYS_NO_PATHCONV=1 ctx7 docs /vercel/next.js/v14.3.0 "app router middleware"
```

## Writing good queries

Query quality directly affects results. Be specific and include relevant details.

| Quality | Example |
|---|---|
| Good | `"How to set up authentication with JWT in Express.js"` |
| Good | `"React useEffect cleanup function with async operations"` |
| Good | `"EF Core DbContext change tracking with QueryTrackingBehavior"` |
| Bad | `"auth"` |
| Bad | `"hooks"` |
| Bad | `"tracking"` |

Describe what to look up in the library's documentation, not the task to complete. Distill the user's question into a focused query: keep the details that describe the library problem, drop everything else. A `NullReferenceException` trace from change-tracking code becomes `"EF Core DbContext change tracking null reference"`. Vague one-word queries return generic results.

Keep each query to a **single concept**. When a prompt asks about several independent topics, split them and run a separate `docs` / `query-docs` lookup per topic. A combined query dilutes ranking and returns shallow results for every topic. Combine concepts in one query only when the question is about how they interact (e.g. `"Next.js proxy with NextAuth session validation"`).

## Output content types

Output contains two kinds of snippets:

- **Code snippets**: titled, with language-tagged code blocks. Primary value
- **Info snippets**: prose explanations with breadcrumb context. Secondary value

MCP returns more content per call than CLI at default settings; the measured ratio is in [mcp.md](mcp.md). If a CLI response feels thin, re-run via MCP or re-issue with a more targeted query.

## Quota / rate limit handling

If a command fails with `"Monthly quota reached"` or `"quota exceeded"`:

1. Inform the user their Context7 quota is exhausted
2. Confirm `CONTEXT7_API_KEY` is set in the environment, since an API key raises the limits (see [cli.md](cli.md))
3. If they cannot or choose not to authenticate further, answer from training knowledge and **clearly note it may be outdated**

Do not silently fall back to training data. Always tell the user why Context7 was unavailable.

## Common mistakes

- Library IDs require a `/` prefix: `/facebook/react` not `facebook/react`
- Always run `library` / `resolve-library-id` first. `ctx7 docs react "hooks"` fails without a valid ID
- Use descriptive queries, not single words
- Do not include secrets, personal data, proprietary code, stack traces, or internal identifiers in queries. Send distilled library/topic terms only
- Do not combine independent topics into one query. One concept per lookup
- Do not run more than **3 lookup commands per topic**. If you cannot find what you need in 3 attempts, fall back and tell the user
