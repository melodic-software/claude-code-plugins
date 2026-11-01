# Integration: composition contract

How `/docs-hygiene:compress` composes with sibling skills and with a consuming repository's own workflows. Every citation uses the `/skill-name <action>` public-surface form; nothing reaches into another skill's internals (paths, schemas, scripts, heading anchors).

## Composition table

| Surface | Direction | Contract |
|---|---|---|
| The consuming repo's markdown lint | `/docs-hygiene:compress` runs it | Post-edit verification. SKILL.md "Hard rules" requires `markdownlint-cli2` PASS on every ship, using the consuming repository's markdownlint config when present; failure blocks ship per the revert rule. A broader consumer lint workflow may run after a batch to surface the full report |
| A planning workflow (if the consumer has one) | calls `/docs-hygiene:compress` | When a planning artifact grows ≥ 2000 words (or an exploration/research artifact beyond 1500 words), the author may invoke `/docs-hygiene:compress <path>` on it before handoff. The consumer's workflow decides when |
| An instruction-audit workflow (if the consumer has one) | calls `/docs-hygiene:compress` | When such an audit flags `CLAUDE.md` or rule-file size bloat AND empirical yield > 3%, the user may invoke `/docs-hygiene:compress --force <path>` to keep a targeted sub-3% diff. `--force` is required only to **keep** a sub-3% result; without it the run proceeds and auto-reverts (SOFT-BLOCK per SKILL.md; not a structural refuse) |
| `/docs-hygiene:audit-encapsulation` | parallel concern | No invocation either direction and no runtime interaction. `/docs-hygiene:audit-encapsulation` detects external citations into skill-private surfaces; `/docs-hygiene:compress` edits the markdown targets it is given |
| A pre-PR quality gate (if the consumer has one) | calls `/docs-hygiene:compress` | When a pre-PR check surfaces uncommitted `.md` files, the user may invoke `/docs-hygiene:compress` (empty arg auto-detects) before PR prep. It never auto-triggers from a gate; user-gated |

The other bundled siblings are `/docs-hygiene:audit-noise` (noise classification, not flavor) and `/docs-hygiene:extract-ssot` (content relocation at any multiplicity, not flavor; it rosters rule-of-one / -two / -three buckets, and only extraction into a NEW artifact waits for 3+ files). `../SKILL.md` "What this skill is NOT" defines both boundaries.

## Public-surface invocation forms

Citations from sibling skills or consumer workflows MUST use one of:

```text
/docs-hygiene:compress                         # empty-arg auto-detect over uncommitted .md
/docs-hygiene:compress <file.md>               # single-file default action
/docs-hygiene:compress <dir>                   # batch default action
/docs-hygiene:compress audit                   # empty-arg audit (read-only dry-run)
/docs-hygiene:compress audit <target>          # audit single file or dir
/docs-hygiene:compress --force <target>        # bypass <3%/0SL revert rule (user owns sub-3% diff)
/docs-hygiene:compress --keep-snapshot <target> # persist .orig.md to the plugin data directory
```

NEVER cite this skill's `context/` files, its scripts, or any heading anchor inside its `SKILL.md` from outside the skill: the `context/*.md` files are private implementation surface, and the public contract is the action + arg + flag set above.

## Anti-patterns

| Don't | Do |
|---|---|
| `/docs-hygiene:compress` to compress code files (`.cs`, `.py`, `.sh`) | Out of scope per SKILL.md "When NOT to use"; code-comment compression is out of scope |
| Chain `/docs-hygiene:compress` + a separate markdown lint pass assuming `/docs-hygiene:compress` skipped lint | `/docs-hygiene:compress` runs `markdownlint-cli2` internally per Hard rules; a redundant lint invocation costs an extra pass with no signal |
| Pipe `/docs-hygiene:compress` output into an orchestrator expecting structured data | `/docs-hygiene:compress` summary is human-readable, not structured. No `--json` |
| `/docs-hygiene:compress` to summarize a conversation | That's the built-in `/compact`, different semantic (conversation summarization, not markdown content) |
| Bypass the semantic-diff dispatch with a `--no-verify`-style flag | No such flag exists. SKILL.md "Hard rules" makes dispatch mandatory for default action; `audit` is the read-only escape if dispatch cost is the concern |

## Composition with build/test front-ends

`/docs-hygiene:compress` does NOT compose with build or test workflows: markdown has no build or test gate beyond markdownlint, which it invokes directly. In the consuming repository's pre-PR sequence it is opportunistic before staging when uncommitted markdown exists, NOT a mandatory step.

## Cross-references

- `../SKILL.md` "Action router": public-surface action set the composition table cites
- `../SKILL.md` "What this skill is NOT": boundaries against lint front-ends, code review, `/docs-hygiene:audit-noise`, `/docs-hygiene:extract-ssot`
