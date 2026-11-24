# Route vendors on a consensus of independent current benchmarks

- Status: accepted
- Date: 2026-11-23
- Related: [#18345](https://github.com/melodic-software/claude-code-plugins/pull/18345) and
  [#18395](https://github.com/melodic-software/claude-code-plugins/pull/18395) (the change; the
  plan contract is in #18395's body); owner interview, 2026-11-22 (Q6, Q13, Q15, Q18);
  [ADR 0045](0045-one-plugin-owns-workflow-and-model-routing-guidance.md) (multi-agent owns model
  routing); [ADR 0057](0057-share-a-user-scope-docs-cache-across-plugins.md) (the cache every
  benchmark page is read through)

## Context

Nearly all work defaulted to Claude, so Claude plan usage ran out while paid Codex and Gemini plans
went unused. No session could tell, for a given task, which vendor, model and effort fit best. Public
leaderboards disagree, change weekly and can be gamed, and a provider's own published results are
the least independent evidence there is. Whatever routing reads must stay current without a
repository edit, since a score written into a file is stale within weeks.

## Decision

1. **Extend `/multi-agent:route vendors` and `plugins/multi-agent/reference/vendors.md`; add no
   new routing surface** (Q6). ADR 0045 already makes multi-agent the one owner of model routing.
2. **Work leaves Claude only on a consensus** (Q15): every trusted source for the work type agrees
   (at least two independent leading sources), a pair is proven on this machine, a trial is on, or
   Claude cannot do the work (image generation). `vendor-decide` enforces the counting rules:
   - two boards from one publisher, or one task set on two sites, count as one source;
   - a score with no error range, a provider's own results and a new source only support;
   - a board that does not test a vendor's current models abstains for that vendor;
   - a page must be dated within six months.
3. **The registry holds pointers only** (`plugins/multi-agent/reference/benchmarks.json`: name,
   link, work type, publisher). Every score is read live through the shared docs cache, with
   Firecrawl only when a plain fetch fails, and no score, ranking or model name is written into a
   plugin file.
4. **Each tool's own skill decides between its MCP server and its CLI** (Q13); routing names that
   skill instead of ranking tools.
5. **Routing checks each harness for the tools and context window a task needs; installing and
   upgrading the CLIs stays in dotfiles** (Q18).

## Alternatives considered

- **(a) Trust one leaderboard.** The simplest, but one gamed or stale board would move all work.
  Not chosen: the owner's rule is "never one source" (Q15).
- **(b) Ship scores or rankings in the plugin.** Fast to read, but stale within weeks and
  consumer-specific. Not chosen.
- **(c) A new routing skill or plugin.** It would split model routing across two owners, against
  ADR 0045. Not chosen (Q6).
- **(d) Routing ranks MCP servers against CLIs.** It would duplicate each tool skill's own
  knowledge of its interfaces. Not chosen (Q13).

## Consequences

- With today's sources, few work types reach a consensus, so most work stays on Claude until
  trials prove a pair. Usage saving comes from trials and from work Claude cannot do.
- Adding a source is a registry row reviewed by pull request; its page is judged at read time.
- The mechanism is an experiment, switched off or removed if routed work does not hold up.

## Amendment (2026-11-24): route on the best error-ranged leading source plus trial results

This amends decision 2; it does not supersede it. In practice routing rests on the best leading
source with a stated error range, plus trial results on this machine. A consensus of two
independent sources is still used when it exists, but today's sources rarely provide one.

- Route fetches and reads only registry rows that can lead; support-only and provider-own rows
  stay in the registry as pointers, are listed unread, and are fetched only while trials are
  active, since their records seed trial candidates.
- The `vendors.tiebreak` setting, including the plan-usage step, is removed: a tie keeps the work
  on Claude unless one non-Claude vendor remains eligible.
- Promotion of a support-only row to permanent was removed in
  [#18809](https://github.com/melodic-software/claude-code-plugins/pull/18809).
