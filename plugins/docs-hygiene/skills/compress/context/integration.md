# Integration — composition contract

How `/compress` composes with sibling skills in this plugin and with a consuming repository's own workflows. Every citation below uses the `/skill-name <action>` public-surface form; nothing reaches into another skill's internals (paths, schemas, scripts, heading anchors).

## Composition table

| Surface | Direction | Contract |
|---|---|---|
| The consuming repo's markdown lint | `/compress` runs it | Post-edit verification. SKILL.md "Hard rules" requires `markdownlint-cli2` PASS on every ship, using the consuming repository's markdownlint config when present. If the consumer has a broader lint workflow, it may run after a `/compress` batch to surface the full report. Failure blocks ship per the `/compress` revert rule |
| A planning workflow (if the consumer has one) | calls `/compress` | Plan authoring. When a planning artifact grows ≥ 2000 words (or an exploration/research artifact beyond 1500 words), the author may invoke `/compress <path>` on the artifact before handing it off. Composition is plan-level; the consumer's workflow decides when |
| An instruction-audit workflow (if the consumer has one) | calls `/compress` | Always-loaded surface audit. When such an audit flags `CLAUDE.md` or rule-file size bloat AND empirical yield > 3%, the user may invoke `/compress --force <path>` to take the targeted sub-3% diff. `--force` is mandatory on always-loaded instruction paths — audit will SKIP-recommend without it |
| `/audit-encapsulation` | parallel concern | No invocation either direction. `/audit-encapsulation` detects external citations into skill-private surfaces; `/compress` edits the markdown targets it is given. The two skills do not interact at runtime |
| A pre-PR quality gate (if the consumer has one) | calls `/compress` | When a pre-PR check surfaces uncommitted `.md` files in the working tree, the user may invoke `/compress` (empty arg auto-detects) before PR prep. `/compress` does not auto-trigger from any gate; user-gated |

Boundaries with the other bundled siblings — `/audit-noise` (noise classification, not flavor) and `/extract-ssot` (content relocation across 3+ files, not flavor) — are defined in `../SKILL.md` "What this skill is NOT".

## Public-surface invocation forms

Citations from sibling skills or consumer workflows MUST use one of:

```text
/compress                         # empty-arg auto-detect over uncommitted .md
/compress <file.md>               # single-file default action
/compress <dir>                   # batch default action
/compress audit                   # empty-arg audit (read-only dry-run)
/compress audit <target>          # audit single file or dir
/compress --force <target>        # bypass <3%/0SL revert rule (user owns sub-3% diff)
/compress --keep-snapshot <target> # persist .orig.md to the plugin data directory
```

NEVER cite this skill's `context/` files, its scripts, or any heading anchor inside its `SKILL.md` from outside the skill. The `context/*.md` files are private implementation surface; `/compress`'s public contract is the action + arg + flag set above.

## Anti-patterns

| Don't | Do |
|---|---|
| `/compress` to compress code files (`.cs`, `.py`, `.sh`) | Out of scope per SKILL.md "When NOT to use"; code-comment compression is out of scope |
| Chain `/compress` + a separate markdown lint pass assuming `/compress` skipped lint | `/compress` runs `markdownlint-cli2` internally per Hard rules; a redundant lint invocation costs an extra pass with no signal |
| Pipe `/compress` output into an orchestrator expecting structured data | `/compress` summary is human-readable, not structured. No `--json` |
| `/compress` to summarize a conversation | That's the built-in `/compact`, different semantic (conversation summarization, not markdown content) |
| Bypass the semantic-diff dispatch with a `--no-verify`-style flag | No such flag exists. SKILL.md "Hard rules" makes dispatch mandatory for default action; `audit` is the read-only escape if dispatch cost is the concern |

## Composition with build/test front-ends

`/compress` does NOT compose with build or test workflows — those are code-correctness surfaces. Markdown content has no build or test gate beyond markdownlint, which `/compress` invokes directly. Within whatever pre-PR sequence the consuming repository runs, `/compress` is opportunistic before staging when uncommitted markdown exists, NOT a mandatory step.

## Cross-references

- `../SKILL.md` "Action router" — public-surface action set the composition table cites
- `../SKILL.md` "What this skill is NOT" — boundaries against lint front-ends, code review, `/audit-noise`, `/extract-ssot`
