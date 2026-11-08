<!-- GENERATED from lib/issue-house-style.md by scripts/sync-shared-copies.sh. Do not edit this copy:
edit the canonical source, then rerun the script. -->

# Issue house style

A skill that files an issue, or changes an open issue's title or type, reads the house style of
the repository the issue lives in, right before the write.

1. **Find the doc.** When that repository is the current checkout, the doc is `issue-tracker.md`
   in its standards root: `docs/standards/`, unless `.claude/standards.yaml` at the git top level
   sets `standards_dir`. When the issue lives in another repository, use the default in step 3.
2. **Apply it.** Follow its "Filing an issue" and "Issue titles" sections. A field the calling
   skill leaves to triage stays with triage, whatever the doc lists. Name in the run's report any
   other part the filing path cannot set, never drop it silently.
3. **No doc: the portable default.** A plain descriptive title, the issue type set, and the parent
   issue and blocked-by edges when known.

The doc wins over any title rule a skill states. This file restates none of its rules: read the
doc on every run.
