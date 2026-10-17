// The owner's batch ratification of an issue's admission: the marker line and
// the comment that carries it. No dependencies, so a script outside this
// action can import it without its node_modules.

// The marker, on a line of its own.
export const RATIFICATION_MARKER =
  /^<!-- admission: admitted when unblocked, owner batch ratification \d{4}-\d{2}-\d{2} -->$/m;

// The first comment that ratifies the issue, or undefined. `ratifiers` holds
// the ids of the listed humans; a lane never admits work on its own.
export const findRatification = (comments, ratifiers) =>
  comments.find(
    (comment) =>
      RATIFICATION_MARKER.test(comment.body ?? "") &&
      ratifiers.has(comment.user?.id) &&
      // Through a GitHub App, the text is that App's, not the owner's.
      comment.performed_via_github_app == null &&
      // An edit keeps the author, so edited text may be another account's.
      typeof comment.created_at === "string" &&
      comment.updated_at === comment.created_at,
  );
