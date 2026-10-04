# Review instructions

Managed Code Review injects this file verbatim as the highest-priority
instruction block for every review agent. It does not expand `@` imports and
does not read a cited file into the prompt. It sees only the words printed
below (see "Depth"). A self-hosted or local review running the `review`
plugin reads this file too, and additionally follows its citations into the
`standards` repository for the full reasoned criterion behind each line.

Review in this organization is split into two mutually exclusive scopes,
so a finding belongs to exactly one scope and is never reported twice.
The **code-review lane** (`claude-review` or `pr-review`, and Managed Code Review)
reads this file and applies the code-review scope below. The **security
lane** (`claude-security-review` or `pr-review-security`) runs from its own security-only prompt
rather than reading this file; its scope section below records the same
split for every surface that does read it, so the code-review lane
knows what to leave to the security lane, and so a self-hosted or local
review (for example a `review`-plugin security agent) applies the right
section.

## Severity

This organization's criteria (`conventions/review/` in `standards`) resolve
to three severities: **Critical**, **Important**, **Suggestion**. On this
surface's three markers:

| SSOT severity | Managed marker |
| --- | --- |
| Critical | 🔴 Important |
| Important | 🔴 Important |
| Suggestion | 🟡 Nit |

🟣 Pre-existing is not an SSOT severity. It is this surface's own <!-- ai-slop-ignore: severity-marker vocabulary, load-bearing -->
detection-time judgment of whether a finding predates the diff, orthogonal
to the three-tier vocabulary above and not something a criterion assigns.

A finding tagged `blocking` is always 🔴 Important here, regardless of what
severity its underlying criterion would otherwise carry in context.
`blocking` is this file's own tag, not a severity a `conventions/review/`
criterion assigns.

## Depth

Managed Code Review cannot resolve a citation below: `@` imports are not
expanded and cited files are not read into the prompt. A self-hosted or
local review using the `review` plugin can follow one into the full
criterion, its severity nuance, and its sources. A citation is a path of the
form `conventions/review/<file>.md#<heading>`, resolved relative to wherever
the `standards` checkout root is available: this repository's own root when
`standards` reviews itself, or the `--add-dir` mount root everywhere else.

## Code-review lane scope

This lane owns every review dimension except security: correctness,
design, conventions, error handling, observability, tests, and
documentation. On a repository whose CI runs the security lane (a
`.github/workflows/claude-security-review*.yml` or
`.github/workflows/pr-review-security*.yml` workflow exists), it does
**not** report security findings, such as vulnerabilities, authorization
or tenancy gaps, credential exposure, or injection: every security
finding belongs exclusively to that lane and is omitted here even when a
hunk plainly contains one.
On a repository with no such workflow no security lane exists yet, and
suppressed findings would have no other reader: report security findings
under this lane too, applying the security-scope checks below.

Always check:

- A high-risk security action, such as authentication, an authorization
  failure, a privilege change, or sensitive-data access, has a
  corresponding audit-log
  entry (`conventions/review/observability.md#logging`). This is an
  observability completeness check on the logging seam; whether the action
  itself is safe is the security lane's question.
- A change that writes two or more related records, files, or state
  locations carries an atomicity mechanism spanning them: a transaction,
  an atomic rename, a constraint, or a compensation step. An
  interruption between steps must not leave state no code path expects
  (`conventions/review/error-handling.md#atomicity`).
- A GitHub Actions dependency bump takes one of two lanes. A non-major bump
  from `actions/*`, `github/*` or `anthropics/*` merges itself once
  `ci-status` passes; any other publisher, and any major, waits for a human
  to merge. A change that adds an action from another publisher says why no
  vendor action or `gh` or script step serves
  (`components/dependabot-policy/README.md#merge-lanes-for-github-actions-bumps`).

## Security lane scope

This lane reports **only** security findings: vulnerabilities, missing
authorization or tenant scoping, exposed secrets or credentials, injection,
and their direct enablers. Everything else is out of scope here and is
owned by the code-review lane; omit it. That includes style, design,
correctness with no security impact, and test coverage.

Always check:

- A handler or endpoint that receives an object id (a path segment, body
  field, or query parameter) checks the caller is authorized for that
  specific record, not only that the id is well-formed. Tagged `blocking`
  (`conventions/review/security.md#object-level-authorization`).
- A data-access path that reaches tenant-owned data carries an explicit
  tenant scope. Tagged `blocking`
  (`conventions/review/multi-tenancy.md#tenant-scoped-data-access`).
- No secret, token, or credential is added to tracked source or config.
  Tagged `blocking` (`conventions/review/security.md#secrets-and-credentials`).
- A query or process invocation built from external input is parameterized,
  never string-concatenated. Tagged `blocking`
  (`conventions/review/security.md#trust-boundaries-and-injection`).
