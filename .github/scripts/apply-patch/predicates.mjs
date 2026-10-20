// The allow predicates a patch-rules.json row names. Each entry takes the
// run's context and returns a test of one changed path; apply-patch.mjs builds
// every test a row names before it applies anything, so a predicate that cannot
// run here throws before any write.

import { inThreadScope } from "../pr-unblock/thread-scope.mjs";

export const PREDICATES = {
  any: () => () => true,
  // A kept thread's path, or a file thread-scope.mjs places in its scope.
  "kept-threads": ({ keptThreads }) => {
    if (!(keptThreads instanceof Set) || keptThreads.size === 0) {
      throw new Error("allow kept-threads needs the run's kept thread paths");
    }
    return (path) => inThreadScope(path, keptThreads);
  },
  "merge-result": () => {
    throw new Error("allow merge-result is not supported by this apply-patch yet");
  },
};
