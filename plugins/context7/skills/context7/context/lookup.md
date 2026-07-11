# Lookup workflow

Two-step library → docs pattern, query-writing guidance, result selection, common mistakes.

## Step 1: Resolve a library name to a Context7 library ID

```bash
# CLI
ctx7 library "<name>" "<query>"

# MCP
mcp__context7__resolve-library-id(libraryName: "<name>", query: "<query>")
```

- Use the **official library name** with proper punctuation — `"Next.js"` not `"nextjs"`, `"Customer.io"` not `"customerio"`, `"Three.js"` not `"threejs"`
- `query` argument is **required** and directly affects result ranking. Use the user's full intent as the query — disambiguates when multiple libraries share a name
- Do NOT include sensitive information (API keys, passwords, credentials, personal data) in queries — sent to Context7's backend

## Result fields

Each result includes:

- **Library ID** — Context7-compatible identifier (format: `/org/project`)
- **Title** — library or package name
- **Description** — short summary
- **Code Snippets** — number of available code examples (higher = better coverage)
- **Source Reputation** — `High` / `Medium` / `Low` / `Unknown` (prefer High/Medium)
- **Benchmark Score** — quality indicator, 100 is max (higher is better)
- **Versions** — list of versions if indexed. Use a version-specific ID when the user specifies a version

## Selection process

1. Analyze the query to understand what library the user wants
2. Rank candidates by:
   - Name similarity to query (exact matches prioritized)
   - Description relevance
   - Code snippet count (coverage)
   - Source reputation (prefer High or Medium)
   - Benchmark score (higher is better)
3. If multiple good matches exist, acknowledge this but proceed with the most relevant one
4. If no good matches exist, state this clearly and suggest a refined query
5. For ambiguous cases, ask the user before guessing

## Step 2: Query documentation

```bash
# CLI (Windows Git Bash requires MSYS_NO_PATHCONV=1 — see cli.md)
MSYS_NO_PATHCONV=1 ctx7 docs "<libraryId>" "<query>"

# MCP
mcp__context7__query-docs(libraryId: "/org/project", query: "<query>")
```

### Version-specific IDs

If the user mentions a specific version, use the version-specific ID:

```bash
# Latest indexed
MSYS_NO_PATHCONV=1 ctx7 docs /vercel/next.js "app router middleware"

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

Use the user's full question as the query when possible. Vague one-word queries return generic results.

## Output content types

Output contains two kinds of snippets:

- **Code snippets** — titled, with language-tagged code blocks. Primary value
- **Info snippets** — prose explanations with breadcrumb context. Secondary value

MCP returns ~1.8× more content per call than CLI at default settings. If a CLI response feels thin, re-run via MCP or re-issue with a more targeted query.

## Quota / rate limit handling

If a command fails with `"Monthly quota reached"` or `"quota exceeded"`:

1. Inform the user their Context7 quota is exhausted
2. Confirm `CONTEXT7_API_KEY` is set in the environment (higher limits come with an API key — see [cli.md](cli.md))
3. If they cannot or choose not to authenticate further, answer from training knowledge and **clearly note it may be outdated**

Do not silently fall back to training data. Always tell the user why Context7 was unavailable.

## Common mistakes

- Library IDs require a `/` prefix — `/facebook/react` not `facebook/react`
- Always run `library` / `resolve-library-id` first — `ctx7 docs react "hooks"` fails without a valid ID
- Use descriptive queries, not single words
- Do not include sensitive information in queries
- Do not run more than **3 lookup commands per question**. If you cannot find what you need in 3 attempts, fall back and tell the user
