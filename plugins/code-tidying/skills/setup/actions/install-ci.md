# `apply install-ci`

The procedure behind the setup skill's `apply install-ci`. "The scan" is the
`comment-lint-ci-scan.py` command the skill body gives; [ci-systems.md](../reference/ci-systems.md)
holds what the step does in any system, where the script comes from, and how to read the
system's own documentation.

1. **Discover.** Run the scan and read its `systems`, `runners`, `tools`, `callers` and
   `decisions`. Then read the files it names: which pipelines and jobs run on a change, how they get
   `python3` and pygments (a setup step, an image, or a requirements or lock file they install
   counts, so a `missing-tool` decision is a lead, not a verdict), and how they get the change's
   head commit and target branch, including how deep the checkout fetches. Follow a job into the
   script or task-runner target it calls.
2. **Stop when it is there.** Stop and report it only for a `script` caller with no `drift` or
   `unreached-caller` against it, in a CI file or reached from one (`reached_by`), whose job you
   confirmed runs on a change. `unreached-caller`: a task-runner target holds the call but no CI
   file runs it, so the lint is not installed: propose the CI step that runs that target, or the
   script directly. `drift`: propose the corrected call in the same job. `recipe-caller`: propose
   replacing the hand-run recipe with the script call.
3. **Ask only what discovery leaves open**, one question at a time, recommendation first: which
   system (`several-systems`), which pipeline and job to extend (recommend one that already checks
   changes and already has `python3`), where the head and base come from when no job reads them,
   and where CI runs at all (`no-ci-system`: configured outside the repository, or none).
4. **Propose.** Draft the step for that system, in its format and the repository's conventions, as
   ci-systems.md "Matching the repository" says, from the system's documentation read now. Show the
   exact change and the file it goes in.
5. **Write only on the user's yes.** With no yes, or nobody to answer, print the proposal and write
   nothing. When the system's documentation could not be read, or the pipeline is configured outside
   the repository, print the step and where it goes instead of writing it.
6. **Verify.** Rerun the scan: the new call is a `script` caller with no `drift` or `unreached-caller`. Report the file as
   written but uncommitted, and that the step first runs on the next change; never report it as
   passing before it has run.
