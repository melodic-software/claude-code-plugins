# Pipeline slots

Read when `apply` reaches step 4 of discovery, or when `check` reports slots. An autonomous agent
pipeline needs four things filled: a **runner** (where agent jobs run), a **git host**, a
**ticket tracker**, and an **observability platform**. Each slot is discovered first, then its
options are laid out, then the user picks and setup helps wire the pick. The skill holds no
preference: options are listed as classes in no ranked order, and any product named is a marked
example, never a recommendation or an instance list.

## The slots and where each is recorded

A slot is a view over discovery this skill or another plugin already owns. The slot step adds no
discovery of its own and no binding section: it reads the owner's record and hands setup to the
owner.

| Slot | Discovered by | Recorded in | Wired by |
|---|---|---|---|
| Runner | Discovery step 2, substrate availability | the binding's `substrate` keys | the [guardrail slice](guardrail-slice.md) for the isolation level an unattended run needs |
| Git host | Discovery step 1, the repository's remotes and the host CLI used for role homes | the `roles` values, which name repositories on that host | the host itself; setup advises |
| Ticket tracker | the work-items tracker binding (`<home>/work-items.yaml`), and the [capture slice](capture-slice.md) step 1 for the tracker class | the work-items binding, never this skill's binding | `/work-items:setup`, which the user runs; a tracker with no shipped adapter goes to `/work-items:onboard-adapter` |
| Observability | the [telemetry slice](../SKILL.md#telemetry-slice) step 1 | the binding's `telemetry` section | the telemetry slice |

The runner slot is the execution surface an agent job runs on today. It is not the
runner-execution home, which stays unborn under the [Runner note](../SKILL.md#runner-note): the
slot never records anything runner-specific beyond `substrate`.

## Option classes

Present every class that applies, each with what discovery found for it, and mark the classes the
user already has. Classes, not products:

- **Runner**: the local machine; the CI provider's hosted runners; self-operated runners; a hosted
  ephemeral executor; a VM or microVM. An unattended run on any of them needs the
  [isolation ladder](../../../reference/guardrails/isolation-ladder.md)'s unattended floor, so
  name each class's reachable level beside it, read through the guardrail slice, never assumed.
- **Git host**: a hosted forge; a self-hosted forge.
- **Ticket tracker**: the git host's built-in issues; a separate hosted tracker; a tracker kept as
  files in the repository. Which providers have shipped adapters is read live from
  `/work-items:setup`, never listed here.
- **Observability**: the file-artifact free default of the telemetry slice; an existing
  OTLP-compatible stack the org already runs; a self-run open-source stack; a hosted vendor.

When discovery finds a slot already filled, the default is to keep it. Offer a change only when the
user asks or the filled option cannot meet a requirement this run found (for example, a runner
class that cannot reach `L2` for an unattended lane).

## Live price research

Prices are looked up at run time and never stored. For each option the user is weighing that can
bill (a hosted plan, metered minutes or storage, a seat, a paid tier):

1. Fetch each vendor's own pricing page during the run with WebFetch, one fetch per vendor for a
   comparison too. Not `/discovery:research`: it writes its findings to disk.
2. Show what it says in the reply, with the page URL and the fetch date, beside the option.
3. With no web access or an unreadable page, say the price is unknown and was not looked up.
   Never state a price from memory or from an earlier run.

A price never enters the binding, a file, a commit, a pull request body or an eval: the run's
reply is the only place one appears, cited.

Paid options then follow [wiring vs advisor](../../../reference/wiring-vs-advisor.md): cost shown
first, explicit opt-in, and a declined opt-in falls back to the free option. Under
`budget_posture: free`, paid options are listed as advisory and never wired.

## Check

`check` prints one row per slot: the option found, the record it came from, and whether that
record is present. A slot with no record reports `not discovered`, never a guessed value.
