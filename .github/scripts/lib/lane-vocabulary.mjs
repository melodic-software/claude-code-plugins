import { LANES_APP_LOGIN, OUTSIDE_ACTOR_LABEL, PR_VERIFY_FAILED_LABEL } from "../pr-merge/merge-holds.mjs";

export { LANES_APP_LOGIN, OUTSIDE_ACTOR_LABEL, PR_VERIFY_FAILED_LABEL };

export const ACTIONS_BOT_ID = 41898282;

export const AGENT_READY = "agent-ready";
export const READY = "status: ready";
export const NEEDS_DECISION = "needs-owner-decision";
export const ATTENDED = "attended";
export const HOST_RUN = "host-run";
export const DO_NOT_MERGE = "do-not-merge";
export const NEEDS_HUMAN = "needs-human";

export const REFINE_MARKER = "<!-- intake-triage refinement -->";

export const DISPATCH_HOLDS = Object.freeze([DO_NOT_MERGE, NEEDS_HUMAN]);
export const FEEDBACK_HOLDS = Object.freeze([DO_NOT_MERGE]);
export const SHARED_COPY_HOLDS = Object.freeze([DO_NOT_MERGE]);
export const ARM_HOLDS = Object.freeze([DO_NOT_MERGE, PR_VERIFY_FAILED_LABEL, OUTSIDE_ACTOR_LABEL]);
export const WIP_CAP_HOLDS = new Set([NEEDS_HUMAN, DO_NOT_MERGE]);
