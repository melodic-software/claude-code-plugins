// The kept-path hand-off. apply-patch.mjs withholds a patch's changes to a
// path the lane token may not push or the review job would load (a workflow,
// a settings file, an agent instruction file, a .gitattributes, a symbolic
// link, a gitlink, a backslash path, a rename into one), pushes the rest, and
// writes the withheld part as its own patch file, KEPT_PATCH_FILE, beside
// KEPT_MANIFEST_FILE: the commit it applies to, its SHA-256, its paths, the
// run, lane, activity and PR or issue. The run job
// uploads both as the keptArtifactName artifact; the kept-paths job posts the
// patch for people in one comment that KEPT_MARKER finds and edits in place.
// A job that applies the kept part trusts the artifact, its manifest and the
// SHA-256, never the comment text.

export const KEPT_MARKER = "<!-- lane-kept-paths -->";
export const KEPT_PATCH_FILE = "kept.diff";
export const KEPT_MANIFEST_FILE = "kept.json";
export const keptArtifactName = ({ lane, activity, attempt }) => `kept-paths-${lane}-${activity}-${attempt}`;

// GitHub refuses a comment body over 65536 characters.
const MAX_BODY = 65000;

// A fence of backticks longer than any run of them in the text.
const fenceFor = (text) => "`".repeat(Math.max(3, ...[...String(text).matchAll(/`+/g)].map(([run]) => run.length + 1)));

// The comment body: the marker, what the patch applies to, and the diff
// fenced for people, a binary hunk named, never shown, and the whole cut to
// fit one comment.
export function keptComment({ patch, sha256, headSha, runId, runUrl, paths }) {
  const shown = String(patch).replace(/^GIT binary patch\n[\s\S]*?(?=^diff --git |(?![\s\S]))/gm, "(binary, not shown)\n");
  const lines = [
    KEPT_MARKER,
    "**Pending an automated apply.** These paths are withheld from the lane's push, which carries the rest of its change if any, because the lane token may not push them or a review job would load them before review:",
    "",
    `${fenceFor(paths.join("\n"))}text`,
    ...paths,
    fenceFor(paths.join("\n")),
    "",
    `- head: \`${headSha}\``,
    `- kept patch SHA-256: \`${sha256}\``,
    `- run: [${runId}](${runUrl})`,
    "",
    "The job that applies it reads the run's artifact and checks its SHA-256; this text is for reading only.",
    "",
  ];
  const head = lines.join("\n");
  let body = shown;
  const cut = "\n(cut to fit one comment; the artifact holds the whole patch)\n";
  const room = MAX_BODY - head.length - 2 * fenceFor(body).length - 16;
  if (body.length > room) {
    body = body.slice(0, Math.max(0, room - cut.length)) + cut;
  }
  const fence = fenceFor(body);
  return `${head}${fence}diff\n${body.endsWith("\n") ? body : `${body}\n`}${fence}\n`;
}

// The paths a git diff names, each once: the b/ side of each diff --git line.
export const keptPaths = (patch) => [...new Set([...String(patch).matchAll(/^diff --git a\/.* b\/(.*)$/gm)].map(([, path]) => path))];
