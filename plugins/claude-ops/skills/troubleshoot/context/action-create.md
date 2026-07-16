# Action: `create`

**Usage:** `/troubleshoot create <type> "<title>" [--repo <repo>]`

Draft and file GitHub issue on `anthropics/claude-code` (or specified repo) using official template format. Supports bug reports and feature requests.

## Types

| Type | Label | Title prefix |
|------|-------|-------------|
| `bug` | `bug` | `[BUG]` |
| `feature` | `enhancement` | `[FEATURE]` |

## Flags

- **`--repo <repo>`**: target different repo (default: `anthropics/claude-code`)

## Mandatory gates (all must pass before drafting)

Gates mirror preflight checklists in Anthropic's issue templates. Every gate is hard requirement — if any fails, STOP and explain why.

**Gate 1: Fetch live template** — always fetch current template from GitHub. Never use cached content:

```bash
# Template filename varies per type — map explicitly, don't derive
#   bug     -> bug_report.yml
#   feature -> feature_request.yml
gh api repos/{repo}/contents/.github/ISSUE_TEMPLATE/{template_file} --jq '.content' | base64 -d
```

**Template file mapping** (type -> filename):

| Type | Template file |
|------|--------------|
| `bug` | `bug_report.yml` |
| `feature` | `feature_request.yml` |

If template can't be fetched (repo inaccessible, template renamed/removed), STOP and inform user. Template structure may change at any time — `context/issue-templates.md` is a reference snapshot, not source of truth.

**Gate 2: Version check** — verify user is on latest Claude Code version:

```bash
# Get installed version
claude --version 2>/dev/null

# Get latest published version
npm view @anthropic-ai/claude-code version 2>/dev/null
```

If not on latest, warn user — Anthropic requires this. Bug may already be fixed. Present both versions and ask whether to continue.

**Gate 3: Duplicate search** — search existing issues with similar title/keywords. Hard gate, not advisory:

```bash
# Open issues — exact and fuzzy match
gh search issues "<keywords>" --repo {repo} --state open --sort updated --limit 20 --json number,title,url,labels,updatedAt

# Recently closed — may already be fixed
gh search issues "<keywords>" --repo {repo} --state closed --sort updated --limit 10 --json number,title,url,labels,updatedAt
```

Present matches and ask user to confirm none cover the same issue. If match exists, suggest commenting on existing issue instead (`gh issue comment`). Only proceed on explicit "no duplicates" confirmation.

**Gate 4: Single-issue check** — confirm report covers exactly ONE bug or ONE feature request. If user's description contains multiple issues, ask them to split into separate reports.

**Gate 5: Correct template selection** — verify issue type matches content:

- Bug report: something that worked before or should work but doesn't
- Feature request: something new that doesn't exist yet
- If support question, point to Discord: `https://anthropic.com/discord`
- If model behavior (not Claude Code the tool), point to `model_behavior.yml` template

## Process (after all gates pass)

**Step 1: Gather information** — collect required fields from live template. Auto-detect what's possible:

| Field | Auto-detection |
|-------|---------------|
| Claude Code Version | `claude --version 2>/dev/null` |
| Operating System | Platform from session context |
| Terminal/Shell | Session environment |
| Platform | "Anthropic API" (default for this repo) |

For fields that can't be auto-detected, ask user. All fields marked `required: true` in live template must be filled.

**Step 2: Draft the issue body** — construct markdown body matching template's section headers. Parse live YAML template to get field labels, types, and options. Format rules:

- Each template field becomes a `### {Field Label}` section
- Checkboxes use `- [X]` for checked items
- Dropdown values must match an option from template exactly
- Code blocks use language fence specified in template's `render` attribute

**Step 3: Present draft for review** — show complete issue and ask for confirmation:

```markdown
## Issue Draft (review before filing)

**Repo:** {repo}
**Title:** {prefix} {title}
**Labels:** {label}

---

{formatted body}

---

**Gate status:** All 5 gates passed
**Actions:** File this issue? (yes / edit / cancel)
```

**Step 4: File the issue** (only on explicit "yes"):

```bash
gh issue create \
  --repo {repo} \
  --title "{prefix} {title}" \
  --label "{label}" \
  --body "$(cat <<'ISSUE_BODY'
{body}
ISSUE_BODY
)"
```

**Step 5: Post-creation** — after filing:

1. Add new issue to `registry.json` with full metadata
2. Present issue URL
3. If the bug has a workaround and the consumer project documents Claude Code quirks, suggest adding it there

## Safety

- **All 5 gates must pass** — no shortcuts, no skipping
- **Live template fetch is mandatory** — never rely on cached template structure
- **Draft review before filing** — never file without showing draft first
- **User must explicitly confirm** — `gh issue create` command requires "yes"
- **Registry auto-update** — newly created issues added to registry automatically

## Template reference

Snapshot of template fields and body format (offline reference only — always fetch live): `context/issue-templates.md`
