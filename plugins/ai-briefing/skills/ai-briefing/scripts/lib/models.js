// Single source for the Claude model the S3 synthesize + S4 categorize agents
// spawn via `claude -p`. Bump here to roll both stages together; a model change
// must never require editing two call sites.
export const BRIEFING_AGENT_MODEL = "claude-sonnet-4-6";
