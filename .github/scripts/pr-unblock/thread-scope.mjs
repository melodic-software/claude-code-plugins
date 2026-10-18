// Which paths an address-feedback fix may change, shared by the promote step
// of .github/workflows/pr-run-activity-write.yml (which imports a SHA-256
// pinned copy, so it imports nothing itself) and publish-feedback.mjs.

export function isProtectedPath(path) {
  return /^\.github(\/|$)/i.test(String(path));
}

const EVAL_CASE = /^plugins\/[^/]+\/evals\/[^/]+\//;
const TEST_FILE = /^(test_[^/]*\.py|[^/]*_test\.py|[^/]*\.(test|spec)\.[^/]+)$/;
const dirOf = (path) => path.slice(0, path.lastIndexOf("/") + 1);

// A kept thread's own path, any file in the plugins/<p>/evals/<case>/
// directory a kept thread's path sits in, or a test file in the same
// directory as a kept thread's path; never anything under .github/.
export function inThreadScope(path, threadPaths) {
  if (isProtectedPath(path)) {
    return false;
  }
  if (threadPaths.has(path)) {
    return true;
  }
  const kept = [...threadPaths];
  const evalCase = EVAL_CASE.exec(path)?.[0];
  if (evalCase !== undefined && kept.some((p) => p.startsWith(evalCase))) {
    return true;
  }
  const dir = dirOf(path);
  return TEST_FILE.test(path.slice(dir.length)) && kept.some((p) => dirOf(p) === dir);
}
