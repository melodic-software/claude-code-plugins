// One marked comment per pull request: posted on the first run, edited in
// place on a re-run, and found only among GITHUB_TOKEN's own comments, by a
// body that opens with exactly `${marker}\n`. A person's comment that quotes
// the marker is not ours. github is a createGitHub client.

const AUTHOR = "github-actions[bot]";
const PAGE = 100;
const MAX_PAGES = 30;

// The marked comment on the pull request, or null. The client returns no Link
// header, so pages are read until one comes back short.
export async function ownComment({ github, repository, pull, marker }) {
  if (typeof marker !== "string" || marker === "" || /[\r\n]/.test(marker)) throw new Error("the marker is not one line");
  const head = `${marker}\n`;
  for (let page = 1; page <= MAX_PAGES; page++) {
    const comments = await github("GET", `/repos/${repository}/issues/${pull}/comments?per_page=${PAGE}&page=${page}`);
    if (!Array.isArray(comments)) throw new Error("the comment list is not a list");
    const own = comments.find((c) => c?.user?.login === AUTHOR && Number.isSafeInteger(c.id) && typeof c.body === "string" && c.body.startsWith(head));
    if (own) return own;
    if (comments.length < PAGE) return null;
  }
  throw new Error(`the pull request has more than ${PAGE * MAX_PAGES} comments`);
}

export async function upsert({ github, repository, pull, marker, body }) {
  const own = await ownComment({ github, repository, pull, marker });
  if (!own) {
    await github("POST", `/repos/${repository}/issues/${pull}/comments`, { body });
    return "posted";
  }
  if (own.body === body) return "left unchanged";
  await github("PATCH", `/repos/${repository}/issues/comments/${own.id}`, { body });
  return "edited";
}
