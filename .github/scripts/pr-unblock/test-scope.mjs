export const DECLARATION = /^(#|\/\/) test-scope: [A-Za-z0-9._@+/-]+$/;
export const SCOPE_PATH = /^[A-Za-z0-9._@+/-]+$/;

export function suiteComment(path) {
  const name = String(path).split("/").at(-1);
  if (/\.test\.m?js$/.test(name)) {
    return "//";
  }
  return /\.test\.sh$|\.Tests\.ps1$/.test(String(path)) || /^test_.*\.py$/.test(name) ? "#" : null;
}

const linesOf = (text) => String(text).split(/(?<=\n)/).filter((line) => line !== "");
const bare = (line) => line.replace(/\n$/, "").replace(/\r$/, "");

export function leadingBlock(text, comment) {
  const lines = linesOf(text);
  const pattern = new RegExp(`^${comment}[ \\t]*test-scope:(.*)$`);
  const declarations = [];
  let lastComment = -1;
  let end = lines.length;
  for (const [index, raw] of lines.entries()) {
    const line = bare(raw);
    if (index === 0 && line.startsWith("#!")) {
      continue;
    }
    if (!line.startsWith(comment) && !/^[ \t]*$/.test(line)) {
      end = index;
      break;
    }
    if (line.startsWith(comment)) {
      lastComment = index;
    }
    const match = pattern.exec(line);
    if (match) {
      declarations.push({ index, rest: match[1], globs: match[1].split(/[ \t]+/).filter(Boolean) });
    }
  }
  return { lines, end, lastComment, declarations };
}

export function declaredPaths(text, comment) {
  return leadingBlock(text, comment).declarations.flatMap((declaration) => declaration.globs);
}

const eolOf = (lines) => (lines[0]?.endsWith("\r\n") ? "\r\n" : "\n");

export function insertDeclarations(text, comment, paths) {
  const { lines, lastComment } = leadingBlock(text, comment);
  const at = lastComment >= 0 ? lastComment + 1 : bare(lines[0] ?? "").startsWith("#!") ? 1 : 0;
  if (at > 0 && !lines[at - 1].endsWith("\n")) {
    return null;
  }
  const eol = eolOf(lines);
  return [...lines.slice(0, at), ...paths.map((path) => `${comment} test-scope: ${path}${eol}`), ...lines.slice(at)].join("");
}

export function declarationRefusal(path, before, after) {
  const comment = suiteComment(path);
  if (comment === null) {
    return "not a suite whose test-scope lines the selector reads";
  }
  const [old, next] = [linesOf(before), linesOf(after)];
  const eol = eolOf(old);
  const inserted = [];
  let i = 0;
  for (const [j, line] of next.entries()) {
    if (i < old.length && line === old[i]) {
      i += 1;
    } else {
      inserted.push({ index: j, line });
    }
  }
  if (i < old.length) {
    return "the change removes or rewrites a line";
  }
  if (inserted.length === 0) {
    return "the change adds no line";
  }
  const added = [];
  for (const { index, line } of inserted) {
    const text = line.endsWith(eol) ? line.slice(0, -eol.length) : null;
    if (text === null || !DECLARATION.test(text) || !text.startsWith(`${comment} `)) {
      return `line ${index + 1} is not a ${comment} test-scope line ending as the file does`;
    }
    added.push({ index, path: text.slice(`${comment} test-scope: `.length) });
  }
  const [was, now] = [leadingBlock(before, comment), leadingBlock(after, comment)];
  if (added.some(({ index }) => index >= now.end) || now.declarations.length !== was.declarations.length + added.length) {
    return "an added line falls outside the leading comment block";
  }
  const declared = new Set(was.declarations.flatMap((declaration) => declaration.globs));
  const paths = added.map((entry) => entry.path);
  if (paths.some((entry) => declared.has(entry)) || new Set(paths).size !== paths.length) {
    return "an added line repeats a declared path";
  }
  return null;
}
