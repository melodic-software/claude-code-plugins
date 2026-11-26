export const THREAD_ID = /^PRRT_[A-Za-z0-9_-]{1,100}$/;
export const NOTE_ID = /^VNOTE_[1-9][0-9]{0,2}$/;
const THREAD_TRAILER = "Lane-Thread: ";

export const threadTrailerLines = (ids) => ids.map((id) => `${THREAD_TRAILER}${id}`);

export const threadsNamed = (message) =>
  new Set(
    String(message ?? "")
      .split("\n")
      .map((line) => line.replace(/\r$/, ""))
      .filter((line) => line.startsWith(THREAD_TRAILER))
      .map((line) => line.slice(THREAD_TRAILER.length)),
  );

export function isProtectedPath(path) {
  return /^\.github\/workflows(\/|$)/i.test(String(path));
}

const INSTRUCTION_PATH =
  /(^|\/)(\.gitmodules|codeowners|settings[^/]*\.json|package(-lock)?\.json|requirements[^/]*\.txt)$/i;
export const isInstructionPath = (path) => INSTRUCTION_PATH.test(String(path));

const PLUGIN_DIR = /^plugins\/[^/]+\//;
const pluginOf = (path) => PLUGIN_DIR.exec(path)?.[0];
const EVAL_PATH = /^plugins\/[^/]+\/(skills\/[^/]+\/)?evals\//;
const TEST_FILE = /^(test_[^/]*\.py|[^/]*_test\.py|[^/]*\.(test|spec)\.[^/]+)$/;
const dirOf = (path) => path.slice(0, path.lastIndexOf("/") + 1);

const BAD_SEGMENT = /(^|\/)\.{0,2}(\/|$)/;
const PLAIN_PATH = /^[A-Za-z0-9_@+.-]+(\/[A-Za-z0-9_@+.-]+)*$/;
const isPlainPath = (path) => PLAIN_PATH.test(path) && !BAD_SEGMENT.test(path);

const CONTROL_PATH = /^\.github\/|(^|\/)(CLAUDE\.md|AGENTS\.md|\.mcp\.json|\.lsp\.json)$|(^|\/)\.claude(-plugin)?\//i;
const isControlPath = (path) => pluginOf(path) === undefined && CONTROL_PATH.test(path);

const prPathAllowed = (path) =>
  typeof path === "string" &&
  isPlainPath(path) &&
  !isProtectedPath(path) &&
  !isInstructionPath(path) &&
  !isControlPath(path);

export const prPathsOf = (files) =>
  [...new Set(files.flatMap((file) => [file?.filename, file?.previous_filename]).filter(prPathAllowed))].sort();

export const sharedCopyPairs = (text) =>
  String(text)
    .split("\n")
    .map((line) => line.split("#")[0].trim().split(/\s+/))
    .filter((fields) => fields.length === 2);

export const copyPathsOf = (files, pairs) => {
  const changed = new Set(files.map((file) => file?.filename));
  return [...new Set(pairs.filter(([canonical]) => changed.has(canonical)).map(([, copy]) => copy).filter(prPathAllowed))].sort();
};

export function namedInScope(path, threadPath) {
  const plugin = pluginOf(path);
  return (
    isPlainPath(path) &&
    plugin !== undefined &&
    plugin === pluginOf(String(threadPath)) &&
    !isProtectedPath(path) &&
    !isInstructionPath(path)
  );
}

export function inThreadScope(path, threadPaths, threads = [], { prPaths = new Set(), copyPaths = new Set(), added = false } = {}) {
  if (isProtectedPath(path) || !isPlainPath(path)) {
    return false;
  }
  if (threadPaths.has(path)) {
    return true;
  }
  if (!added && (prPaths.has(path) || copyPaths.has(path)) && prPathAllowed(path)) {
    return true;
  }
  if (threads.some((t) => Array.isArray(t?.named_paths) && t.named_paths.includes(path) && namedInScope(path, t.path))) {
    return true;
  }
  const kept = [...threadPaths];
  const plugin = pluginOf(path);
  if (
    plugin !== undefined &&
    !isInstructionPath(path) &&
    (EVAL_PATH.test(path) || [...kept, ...prPaths].some((p) => p.startsWith(plugin)))
  ) {
    return true;
  }
  const dir = dirOf(path);
  return TEST_FILE.test(path.slice(dir.length)) && kept.some((p) => dirOf(p) === dir);
}
