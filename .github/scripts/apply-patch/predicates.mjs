// The allow predicates a patch-rules.json row names. Each entry takes the
// run's context and returns a test of one changed path; apply-patch.mjs builds
// every test a row names before it applies anything, so a predicate that cannot
// run here throws before any write.

import { inFixScope } from "../pr-unblock/dependency-classify.mjs";
import { inThreadScope } from "../pr-unblock/thread-scope.mjs";

export const PREDICATES = {
  any: () => () => true,
  // A kept thread's path, or a file thread-scope.mjs places in its scope,
  // its named_paths included: `keptThreads` is { paths, threads }.
  "kept-threads": ({ keptThreads }) => {
    if (!(keptThreads?.paths instanceof Set) || keptThreads.paths.size === 0 || !Array.isArray(keptThreads.threads)) {
      throw new Error("allow kept-threads needs the run's kept thread paths");
    }
    return (path) => inThreadScope(path, keptThreads.paths, keptThreads.threads);
  },
  // An npm or pip manifest or lock file outside .github/, in a directory of
  // its ecosystem among the base dependabot.yml's [ecosystem, directory]
  // pairs. No runner hands those on yet, so a row naming it refuses.
  "dependency-manifests": ({ dependabotConfig }) => {
    if (!Array.isArray(dependabotConfig) || dependabotConfig.length === 0) {
      throw new Error("allow dependency-manifests needs the base dependabot.yml's [ecosystem, directory] pairs");
    }
    return (path) => inFixScope(path, dependabotConfig);
  },
  "merge-result": () => {
    throw new Error("allow merge-result is not supported by this apply-patch yet");
  },
};
