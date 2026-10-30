// Intake admission's one comment per issue: the marker it opens with, the text
// of a refusal, and the write. Intake's admission (intake-triage/admit.mjs)
// and the issue lane's park route (work-resolve-issue/report-outcome.mjs,
// which runs from a copy of its own directory beside this lib) share it, so
// intake-reenter finds the comment whichever wrote it.

export const ADMIT_MARKER = "<!-- intake-triage admission -->";

// The admission comment's text for a refusal, after ADMIT_MARKER: each reason
// names what admission needs; only a security or intent reason asks a person.
export const refusalText = (reasons) =>
  `Not admitted to the issue lane: ${reasons}. Admission takes the issue once each of those is met, when intake triages it again (\`.github/actions/resolve-config/admission-rules.json\`).`;

// One comment by `login` (the lanes App) carrying ADMIT_MARKER, edited in
// place on a later run. `comments` are the issue's, as the REST API lists them.
export async function sayWhy(github, repository, base, comments, text, login) {
  const body = `${ADMIT_MARKER}\n${text}`;
  const own = comments.find((comment) => comment.user?.login === login && String(comment.body ?? "").startsWith(ADMIT_MARKER));
  if (own?.body === body) {
    return;
  }
  if (own) {
    await github("PATCH", `/repos/${repository}/issues/comments/${own.id}`, {
      body,
    });
  } else {
    await github("POST", `${base}/comments`, { body });
  }
}
