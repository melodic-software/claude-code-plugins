# Copies between repositories

Phase B's scan of what two or more repositories in scope copy from each other: the repository
altitude's "copied code or prose that must track its source" in
[coupling-model.md](coupling-model.md). It runs only when the target names two or more
repositories.

1. **Exclude what a mechanism owns.** Read each repository for a mechanism that already owns
   copies: a sync manifest that pushes files into other repositories, or a vendoring registry that
   lists each copied file and its source. Write the paths each declares, one per line, to a file
   with the Write tool: `owner/name:path` for one repository, a bare path for every one.
2. **Measure.** Run `cross-repo-dups.py` once, with every repository root, in the command SKILL.md
   phase B gives. It reads each repository at `origin/HEAD` (else `HEAD`) from its object store, so a dirty or
   stale working tree changes nothing, and prints:
   - an `exact` row per file blob tracked in two or more repositories;
   - a `diverged` row per file name whose content differs between repositories, with the lowest
     line similarity between variants; a high one is a copy that drifted;
   - `excluded` counts for managed copies, files whose header says they are generated, and
     fixture, vendor and snapshot paths, and empty files.

   The script's docstring has the full row format.
3. **Verify in phase C.** Each row is a candidate. Identical bytes can still encode different
   knowledge (a stock license header, a `.gitignore`): a row is a finding only when the copies
   must change together. A managed copy that differs from its source is a finding for the
   mechanism that owns it, not a new copy.
4. **Route.** A confirmed copy is a route-lane entry whose remediation is "Point, don't copy" in
   [remediations.md](remediations.md), ledgered and filed in the repository that holds the
   source. The copies change to point at it in their own repositories' pull requests.
