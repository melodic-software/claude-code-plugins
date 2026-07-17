# Review instructions

Managed Code Review injects this file verbatim as the highest-priority
instruction block for every review agent. It does not expand `@` imports and
does not read a cited file into the prompt — it sees only the words printed
below (see "Depth"). A self-hosted or local review running the `review`
plugin reads this file too, and additionally follows its citations into the
`standards` repository for the full reasoned criterion behind each line.

## Severity

This organization's criteria (`conventions/review/` in `standards`) resolve
to three severities: **Critical**, **Important**, **Suggestion**. On this
surface's three markers:

| SSOT severity | Managed marker |
| --- | --- |
| Critical | 🔴 Important |
| Important | 🔴 Important |
| Suggestion | 🟡 Nit |

🟣 Pre-existing is not an SSOT severity — it is this surface's own
detection-time judgment of whether a finding predates the diff, orthogonal
to the three-tier vocabulary above and not something a criterion assigns.

A finding tagged `blocking` is always 🔴 Important here, regardless of what
severity its underlying criterion would otherwise carry in context.
Recognizing that a specific diff hunk matches a `blocking`-tagged criterion
is reviewer judgment, piloted rather than asserted reliable. `blocking` is
this file's own tag, not a severity a `conventions/review/` criterion
assigns — no criterion file currently carries one.

## Depth

Managed Code Review cannot resolve a citation below: `@` imports are not
expanded and cited files are not read into the prompt. A self-hosted or
local review using the `review` plugin can follow one — a path of the form
`conventions/review/<file>.md#<heading>`, resolved relative to wherever the
`standards` checkout root is available: this repository's own root when
`standards` reviews itself, or the `--add-dir` mount root everywhere else —
into the full criterion, its severity nuance, and its sources.

Each line below is written to survive losing that depth: either it is
already a complete, actionable check on its own and the citation is a bonus
a capable surface gets, or — where the check would be too easily
misapplied without the reasoning behind it — the reasoning is stated inline
rather than left solely behind the cite. Every line still cites its SSOT
criterion; a citation here never substitutes prose that isn't needed, per
`conventions/engineering/reference-dont-duplicate.md`.

## Always check

- A handler or endpoint that receives an object id (a path segment, body
  field, or query parameter) checks the caller is authorized for that
  specific record, not only that the id is well-formed — `blocking`
  (`conventions/review/security.md#object-level-authorization`).
- A data-access path that reaches tenant-owned data carries an explicit
  tenant scope — `blocking`
  (`conventions/review/multi-tenancy.md#tenant-scoped-data-access`).
- No secret, token, or credential is added to tracked source or config —
  `blocking` (`conventions/review/security.md#secrets-and-credentials`).
- A query or process invocation built from external input is parameterized,
  never string-concatenated — `blocking`
  (`conventions/review/security.md#trust-boundaries-and-injection`).
- A high-risk security action — authentication, an authorization failure, a
  privilege change, sensitive-data access — has a corresponding audit-log
  entry (`conventions/review/observability.md#logging`).

## Do not report

- Anything CI already enforces and that is not also tagged `blocking`
  above: lint, formatting, type errors, and whatever a stack overlay under
  `conventions/review/overlays/` names as its component's mechanical
  backstop. A CI backstop (for example a `gitleaks` lane) catches an
  instance mechanically; it does not make the `blocking` check itself
  skippable here.
- Generated files and lockfiles, except a `blocking` finding — a leaked
  secret in a lockfile or a supply-chain regression visible only there is
  still reportable; this rule only waives low-signal mechanical noise
  (formatting, regenerated diffs) in those files.

## Cap the nits

Report at most five Nits per review; note any beyond that as a count in the
summary instead of posting them inline.
