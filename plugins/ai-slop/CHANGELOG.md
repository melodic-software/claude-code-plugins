# Changelog

## 0.2.0

- Added a set of catalog entries inspired by
  [Cursor's `unslop` skill](https://github.com/cursor/plugins/blob/main/pstack/skills/unslop/SKILL.md),
  deduplicated against the Wikipedia inventory in an overlap map.
- Three new detector rules, calibrated against this marketplace's corpus: `rule-chatbot-artifacts`
  (chat-turn residue and sycophancy phrases; IMPORTANT in the severity crosswalk),
  `rule-filler-phrases` (`in order to`, `due to the fact that`, deletable note-phrases), and
  `rule-stacked-hedging` (`could potentially` and kin) — both SUGGESTION.
- Four new rubric tells: false ranges, colon crutches, abstract metaphor jargon (kept out of the
  script layer by calibration: "substrate" alone had 114 legitimate uses on the calibration
  corpus), and mechanism-free claims.
- New `reference/rewrite-guide.md` owns fix-time guidance: plain-speech rewrites, substitution
  guardrails (an em dash never becomes a parenthesis or en dash), voice guidance bounded by
  meaning preservation, and a closing self-audit pass. The `fix` flow reads it first.
- AI-vocabulary default list gains the plain-word trio `utilize`, `leverage`, `facilitate`
  (density-gated; measured quiet on the calibration corpus).
- `rule-inline-header-lists` records a boundary refinement as **calibration pre-work** for a
  post-V1 script rule: a bold lead-in that ends in a period and is followed by new detail is
  reference-doc style, not a tell. The entry stays `recorded-only`, so nothing runs it yet.
- Overlap map says "catalogued by" rather than "covered by", and names the rows whose entries are
  dormant; Name-dropping is recorded as deliberately out of scope for general prose, and generic
  conclusions as detected only in their formulaic half.
- `rule-chatbot-artifacts` gains "Found the smoking gun"; `rule-abstract-metaphor-jargon` and the
  rewrite guide gain `evacuate` -> "move out". Two narrowings that were silent are now recorded:
  the promotional word core deliberately omits travel-copy words with no technical base rate, and
  the shipped AI-vocabulary list is a deliberate narrowing of the era-union rather than the union
  itself (`vocab_add` restores the rest).
- **Findings file no longer emits a `tier:` frontmatter field**, and `--tier` is retired from
  `emit-findings.sh`. Both owner docs already said this producer omits it, and the flag defaulted
  to a hardcoded value describing no property of the run.
- `rule-filler-phrases` and `rule-stacked-hedging` carry their own Action strings instead of the
  generic judgment fallback.
- **Roster-agreement guard**: the suite now asserts all 15 rules' emitted tiers (was 2) and fails
  when `detect.sh`'s registry no longer matches the tabled set, so a rule added without a
  crosswalk row can no longer emit SUGGESTION by silent fall-through.
- **Test config isolation**: the suite pins `HOME` and `CLAUDE_PROJECT_DIR` to empty directories
  so fixtures grade against shipped defaults. Found by dogfooding — a consuming repo disabling a
  rule for its own house style turned nine unrelated cases red.
- Relay expectations narrowed to what is true: `rule-utm-params` is the one relay-applicable rule;
  every other rule is `/ai-slop:audit fix` work.

## 0.1.0

- Initial release: `audit` skill (read-only default, explicit `fix` action), `setup` skill,
  deterministic detector with the mechanical rule roster, judgment rubric, and the
  Signs-of-AI-writing catalog (revision-pinned, CC BY-SA 4.0).
- Hardened by the first dogfood run (pre-release, folded in): ignore markers must be
  well-formed comment markers, not prose mentions — a document that documents the markers no
  longer exempts itself, and a mid-file `ai-slop-ignore-file` declines the whole file instead
  of silently truncating the scan; declined files are named in output (`Declined:` rows with
  cause), not just counted; `emit-findings.sh` composes the findings file deterministically
  from detector output (the model resolves the destination and the contract gate; the script
  owns row assembly at repo scale), writing coverage-only files on zero findings and refusing
  non-detector input.
- Fix guidance: `rule-of-three` rewrites collapse toward the single strongest item unless
  every element is load-bearing.
