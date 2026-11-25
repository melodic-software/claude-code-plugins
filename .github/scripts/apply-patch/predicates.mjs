// The allow predicates a patch-rules.json row names. Each entry takes the
// run's context and returns a test of one changed path; apply-patch.mjs builds
// every test a row names before it applies anything, so a predicate that cannot
// run here throws before any write.
import { inFixScope } from "../pr-unblock/dependency-classify.mjs";
import { inThreadScope } from "../pr-unblock/thread-scope.mjs";
import { suiteComment } from "../pr-unblock/test-scope.mjs";
import { segments } from "./protected-paths.mjs";

export const PREDICATES = {
  any: () => () => true,
  markdown: () => (path) => path.endsWith(".md"),
  // A kept thread's path, or a file thread-scope.mjs places in its scope,
  // its named_paths and the PR's own files and shared copies the patch does
  // not add included: `keptThreads` is { paths, threads, prPaths, copyPaths }.
  "kept-threads": ({ keptThreads }) => {
    if (!(keptThreads?.paths instanceof Set) || keptThreads.paths.size === 0 || !Array.isArray(keptThreads.threads)) {
      throw new Error("allow kept-threads needs the run's kept thread paths");
    }
    return (path, entry) =>
      inThreadScope(path, keptThreads.paths, keptThreads.threads, {
        prPaths: keptThreads.prPaths ?? new Set(),
        copyPaths: keptThreads.copyPaths ?? new Set(),
        added: entry === undefined || entry.status?.[0] === "A",
      });
  },
  // An npm or pip manifest or lock file outside .github/, in a directory of
  // its ecosystem among the base dependabot.yml's [ecosystem, directory]
  // pairs, which apply-patch.mjs reads from the trusted base copy.
  "dependency-manifests": ({ dependabotConfig }) => {
    if (!Array.isArray(dependabotConfig) || dependabotConfig.length === 0) {
      throw new Error("allow dependency-manifests needs the base dependabot.yml's [ecosystem, directory] pairs");
    }
    return (path) => inFixScope(path, dependabotConfig);
  },
  "cdn-pins": ({ cdnPins }) => {
    if (!(cdnPins instanceof Set) || cdnPins.size === 0) {
      throw new Error("allow cdn-pins needs the base pins.json");
    }
    return (path) => cdnPins.has(path);
  },
  // A copy the base-tip scripts/shared-copies.txt registers, which
  // apply-patch.mjs reads from the trusted base copy (sharedCopiesFrom).
  "shared-copies": ({ sharedCopies }) => {
    if (!(sharedCopies instanceof Set) || sharedCopies.size === 0) {
      throw new Error("allow shared-copies needs the base registry's copies");
    }
    return (path) => sharedCopies.has(path);
  },
  // A path the base merge left conflicted, which the patch resolves; the
  // merge's own changes from the base side never face the predicates.
  // `merge.unmerged` is a Set, read from the checkout's merge.
  "test-suites": () => (path) => suiteComment(path) !== null && segments(path)[0] !== ".github",
  "merge-result": ({ merge }) => {
    if (!(merge?.unmerged instanceof Set)) {
      throw new Error("allow merge-result needs the merge's conflicted paths");
    }
    return (path) => merge.unmerged.has(path);
  },
};
