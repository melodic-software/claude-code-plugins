// Which paths an address-feedback fix may change, shared by the promote step
// of .github/workflows/pr-run-activity-write.yml (which imports a SHA-256
// pinned copy, so it imports nothing itself), publish-feedback.mjs,
// address-feedback.mjs and apply-ci-fix.mjs.

export function isProtectedPath(path) {
  return /^\.github(\/|$)/i.test(String(path));
}

// Run or loaded as instructions by the harness, git or GitHub: agent rules,
// MCP, language-server and submodule config, code owners, a .claude or
// .claude-plugin directory, and a plugin's hooks, monitors and bin, each
// matched as the whole segment.
const INSTRUCTION_PATH =
  /(^|\/)((claude|agents)\.md|\.mcp\.json|\.lsp\.json|\.gitmodules|codeowners)$|(^|\/)\.claude(-plugin)?(\/|$)|(^|\/)plugins\/[^/]+\/(hooks|monitors|bin)(\/|$)/i;
export const isInstructionPath = (path) => INSTRUCTION_PATH.test(String(path));

const PLUGIN_DIR = /^plugins\/[^/]+\//;
const pluginOf = (path) => PLUGIN_DIR.exec(path)?.[0];
// Script or code files, run by a shell or an interpreter, so out of the
// plugin-wide part of a thread's scope.
const CODE_FILE = /\.(sh|bash|zsh|ps1|py|mjs|cjs|js|ts|mts|cts)$/i;
const TEST_FILE = /^(test_[^/]*\.py|[^/]*_test\.py|[^/]*\.(test|spec)\.[^/]+)$/;
const dirOf = (path) => path.slice(0, path.lastIndexOf("/") + 1);

// An empty, . or .. segment, so a leading or doubled / too.
const BAD_SEGMENT = /(^|\/)\.{0,2}(\/|$)/;
// ASCII letters, digits and _@+.- in /-separated segments: no backslash,
// space, control or non-ASCII character.
const PLAIN_PATH = /^[A-Za-z0-9_@+.-]+(\/[A-Za-z0-9_@+.-]+)*$/;

// A path a trusted write-access fix request on a kept thread named may join
// that thread's scope: a plain path in normal form, in the same plugins/<p>/
// directory as the thread's own path, and neither under .github/ nor an
// instruction path.
export function namedInScope(path, threadPath) {
  const plugin = pluginOf(path);
  return (
    PLAIN_PATH.test(path) &&
    !BAD_SEGMENT.test(path) &&
    plugin !== undefined &&
    plugin === pluginOf(String(threadPath)) &&
    !isProtectedPath(path) &&
    !isInstructionPath(path)
  );
}

// A kept thread's own path, a file in the plugins/<p>/ directory a kept
// thread's path sits in that is no instruction path and no script or code
// file, a test file in the same directory as a kept thread's path,
// or a path in a kept thread's named_paths (in `threads`, each { path,
// named_paths }) that namedInScope allows for that thread; never anything
// under .github/, and never a path that is not plain and in normal form.
export function inThreadScope(path, threadPaths, threads = []) {
  if (isProtectedPath(path) || BAD_SEGMENT.test(path) || !PLAIN_PATH.test(path)) {
    return false;
  }
  if (threadPaths.has(path)) {
    return true;
  }
  if (threads.some((t) => Array.isArray(t?.named_paths) && t.named_paths.includes(path) && namedInScope(path, t.path))) {
    return true;
  }
  const kept = [...threadPaths];
  const plugin = pluginOf(path);
  if (plugin !== undefined && !CODE_FILE.test(path) && !isInstructionPath(path) && kept.some((p) => p.startsWith(plugin))) {
    return true;
  }
  const dir = dirOf(path);
  return TEST_FILE.test(path.slice(dir.length)) && kept.some((p) => dirOf(p) === dir);
}
