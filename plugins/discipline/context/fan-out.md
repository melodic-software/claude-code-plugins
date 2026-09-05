# Fresh-context fan-out

Shared by the plugin's `-deep` tiers. Each one enumerates its own inventory
(the base skill says what counts as an item) and hands every item to a
fresh-context subagent; this file owns how that dispatch runs.

- **Blind subagents, or it is not fresh context.** Hand each subagent the item
  and the requirement, never the reasoning or assumption that produced it; an
  agent given that reasoning re-derives the same error.
- **Throttle in bounded waves.** A sustained wide fan-out trips server-side
  burst overload (529s) and loses agents mid-run, so cap concurrency to a
  modest wave (roughly a dozen or fewer at a time) and process the inventory
  wave by wave rather than launching one agent per item at once.
- **Retry the failed subset only.** If an agent errors or times out, retry that
  item once; on a second failure mark it unverifiable, an honest skip, never a
  false pass. Never blind-re-run the whole fan-out to recover a few stragglers.
