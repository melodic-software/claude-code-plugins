# Recommendation basis: the contract this plugin applies

The plugin-shipped statement of the recommendation-basis convention. The full
convention, with its boundary and adopters, is
<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/recommendation-basis/README.md>.

- **Recommendation.** An option, verdict, default, or next step put to the
  user for a decision.
- **Grounding bar.** Local: read the affected code, config, or document and
  list its consumers and blast radius, including other repositories that use a
  shared artifact. External: current consensus across tiered sources (official
  docs, then authoritative articles and recognized experts, then community),
  with the date or version each reflects and any credible dissent named.
- **Consequential** means cross-repo, shared infrastructure, irreversible or
  costly to reverse, or security. A consequential recommendation must clear the
  bar; any other may rest on judgment if its label says so.
- **Three outcomes.** Every recommendation ends in exactly one:
  - **verified**: presented with `Basis: verified` plus what verified it (a
    `file:line`, tool output, or URL fetched this session);
  - **judgment**: presented with `Basis: judgment`; only for a
    recommendation that is not consequential;
  - **withheld**: a consequential recommendation that cannot be settled. It
    is not presented and carries no `Basis:` label; it is surfaced as an open
    question that names the evidence that would settle it.
- **Re-emit.** When evidence changes a pending recommendation, restate it as
  old → new → why, where new is a verified or judgment recommendation or the
  withheld open question; name the unchanged ones in one line.
