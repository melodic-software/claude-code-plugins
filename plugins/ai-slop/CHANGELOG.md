# Changelog

## 0.2.0

- Integrated Cursor's `unslop` skill (cursor/plugins `pstack`, MIT, commit-pinned) as the
  catalog's second source, deduplicated against the Wikipedia inventory in an overlap map.
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
- `rule-inline-header-lists` gains the source's boundary refinement: a bold lead-in that ends in
  a period and is followed by new detail is reference-doc style, not a tell.

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
