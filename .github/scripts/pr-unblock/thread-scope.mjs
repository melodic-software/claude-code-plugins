// Which paths an address-feedback fix may change, shared by the promote step
// of .github/workflows/pr-run-activity-write.yml (which imports a SHA-256
// pinned copy, so it imports nothing itself) and publish-feedback.mjs.

export function isProtectedPath(path) {
  return /^\.github(\/|$)/i.test(String(path));
}

const PLUGIN_DIR = /^plugins\/[^/]+\//;
// In the plugin directory but run or loaded as instructions by the harness or
// a shell, so out of the plugin-wide part: hooks, manifests, script or code
// files, and agent rules (CLAUDE.md, AGENTS.md, anything under .claude/).
const PLUGIN_CODE =
  /^plugins\/[^/]+\/(hooks|\.claude-plugin)\/|\.(sh|py|mjs|js|ts)$|(^|\/)(claude|agents)\.md$|(^|\/)\.claude\//i;
const TEST_FILE = /^(test_[^/]*\.py|[^/]*_test\.py|[^/]*\.(test|spec)\.[^/]+)$/;
const dirOf = (path) => path.slice(0, path.lastIndexOf("/") + 1);

// An empty, . or .. segment, so a leading or doubled / too.
const BAD_SEGMENT = /(^|\/)\.{0,2}(\/|$)/;

// A kept thread's own path, a file in the plugins/<p>/ directory a kept
// thread's path sits in that is not under hooks/, .claude-plugin/ or a
// .claude/ directory, not a CLAUDE.md or AGENTS.md, and not a .sh, .py, .mjs,
// .js or .ts file, or a test file in the same directory as a
// kept thread's path; never anything under .github/, and never a path that is
// not in normal form.
export function inThreadScope(path, threadPaths) {
  if (isProtectedPath(path) || BAD_SEGMENT.test(path)) {
    return false;
  }
  if (threadPaths.has(path)) {
    return true;
  }
  const kept = [...threadPaths];
  const plugin = PLUGIN_DIR.exec(path)?.[0];
  if (plugin !== undefined && !PLUGIN_CODE.test(path) && kept.some((p) => p.startsWith(plugin))) {
    return true;
  }
  const dir = dirOf(path);
  return TEST_FILE.test(path.slice(dir.length)) && kept.some((p) => dirOf(p) === dir);
}
