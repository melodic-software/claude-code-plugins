import { inFixScope } from "../pr-unblock/dependency-classify.mjs";
import { inThreadScope } from "../pr-unblock/thread-scope.mjs";
import { suiteComment } from "../pr-unblock/test-scope.mjs";
import { segments } from "./protected-paths.mjs";

export const PREDICATES = {
  any: () => () => true,
  markdown: () => (path) => path.endsWith(".md"),
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
  "shared-copies": ({ sharedCopies }) => {
    if (!(sharedCopies instanceof Set) || sharedCopies.size === 0) {
      throw new Error("allow shared-copies needs the base registry's copies");
    }
    return (path) => sharedCopies.has(path);
  },
  "test-suites": () => (path) => suiteComment(path) !== null && segments(path)[0] !== ".github",
  "merge-result": ({ merge }) => {
    if (!(merge?.unmerged instanceof Set)) {
      throw new Error("allow merge-result needs the merge's conflicted paths");
    }
    return (path) => merge.unmerged.has(path);
  },
};
