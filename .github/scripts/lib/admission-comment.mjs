export const ADMIT_MARKER = "<!-- intake-triage admission -->";

export const refusalText = (reasons) =>
  `Not admitted to the issue lane: ${reasons}. Admission takes the issue once each of those is met, when intake triages it again (\`.github/actions/resolve-config/admission-rules.json\`).`;

export async function sayWhy(github, repository, base, comments, text, login) {
  const body = `${ADMIT_MARKER}\n${text}`;
  const own = comments.find((comment) => comment.user?.login === login && String(comment.body ?? "").startsWith(ADMIT_MARKER));
  if (!own) {
    await github("POST", `${base}/comments`, { body });
  } else if (own.body !== body) {
    await github("PATCH", `/repos/${repository}/issues/comments/${own.id}`, { body });
  }
}
