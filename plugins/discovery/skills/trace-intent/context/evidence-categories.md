# Evidence categories, and the seam for adding one

Categories are stable; the tools that serve them are not. That is the point of naming a category
rather than a vendor — a category survives a team switching trackers, and a vendor name in a skill
body is a hardcoded assumption about a consumer that will not hold.

## The three shipped categories

| Category | Resolves through | Reports as a gap when |
|---|---|---|
| Source control | `/discovery:explore git` when installed; otherwise the session's own history access | No repository resolves |
| Long-form documents | The consuming repo's own documentation tree, wherever it keeps one | No documentation surface is discoverable |
| Issue tracker | `/work-items:track` when the `work-items` plugin is installed — it owns the provider-neutral seam; otherwise whatever tracker interface the session has | No tracker resolves |

Vendors named anywhere in this file are illustrations of what a category can contain. None is a
requirement, a default, or a supported integration.

## Why only three

Four further categories carry real intent evidence — team chat, application observability, error
tracking, and product analytics. They are not shipped, and the reason is empirical rather than
principled: a sweep of this marketplace found no seam reaching any of them. Shipping them anyway
would emit four identical "unavailable" lines on every run in every repository forever, which is
noise wearing the costume of rigour.

A null result is a finding when it varies. A constant is not a finding.

## The extension seam

To add a category, a consuming repository supplies an adapter and the skill picks it up. An adapter
declares four things:

| Field | Meaning |
|---|---|
| `category` | Which kind of evidence this serves — one of the stable category names, or a new one |
| `resolves` | How the skill detects the tool is present this session |
| `query` | How to search it, in the vocabulary that tool actually uses |
| `cite` | How to form a citation a reader can follow back in under a minute |

Two rules bind an adapter:

1. **It reports its own absence.** An adapter that resolves to nothing emits a gap line. Silent
   skipping is the defect the whole coverage map exists to prevent.
2. **It names a category, not a product.** An adapter for one incident tool is an
   *application-observability* adapter that happens to speak that tool's query language, and the
   output cites the category. A reader should not have to know which vendor answered.

## If nobody ever writes one

Then this seam is dead weight and should be removed rather than defended. That is recorded as an
explicit assumption in the topic's contract, not left as an article of faith: an unwired seam earns
its place by being wired, and the next audit that finds it unused should delete it.
