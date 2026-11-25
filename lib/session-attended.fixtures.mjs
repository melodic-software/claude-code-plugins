const real = (overrides) =>
  [
    "SESSION_ATTENDED_VAR=CLAUDE_CODE_SESSION_ATTENDED",
    "SESSION_ATTENDED_VALUE=1",
    "SESSION_ATTENDED_ENTRYPOINT_VAR=CLAUDE_CODE_ENTRYPOINT",
    "SESSION_ATTENDED_HEADLESS_ENTRYPOINTS=sdk-cli",
    "",
  ]
    .map((line) => overrides[line.split("=")[0]] ?? line)
    .join("\n");
const attendedCli = { CLAUDE_CODE_SESSION_ATTENDED: "1", CLAUDE_CODE_ENTRYPOINT: "cli" };
const custom = [
  "# GENERATED from lib/session-attended.env by scripts/sync-shared-copies.sh. Do not edit this copy:",
  "# edit the canonical source, then rerun the script.",
  "SESSION_ATTENDED_VAR=X_ATT",
  "SESSION_ATTENDED_VALUE=yes",
  "SESSION_ATTENDED_ENTRYPOINT_VAR=X_EP",
  'SESSION_ATTENDED_HEADLESS_ENTRYPOINTS="bot cron"',
  "",
].join("\n");

/**
 * The one behavior table lib/session-attended.sh and lib/session-attended.mjs both pass.
 * `env` is the whole environment the readers see. `data` absent means the real
 * lib/session-attended.env, null means no data file beside the readers, a string is its text.
 * @type {{ name: string, env: Record<string, string>, data?: string | null, attended: boolean }[]}
 */
export default [
  { name: "ATTENDED=1, ENTRYPOINT=cli", env: attendedCli, attended: true },
  { name: "ATTENDED=1, ENTRYPOINT=sdk-cli", env: { CLAUDE_CODE_SESSION_ATTENDED: "1", CLAUDE_CODE_ENTRYPOINT: "sdk-cli" }, attended: false },
  { name: "ATTENDED unset, ENTRYPOINT=cli", env: { CLAUDE_CODE_ENTRYPOINT: "cli" }, attended: false },
  { name: "ATTENDED=0, ENTRYPOINT=cli", env: { CLAUDE_CODE_SESSION_ATTENDED: "0", CLAUDE_CODE_ENTRYPOINT: "cli" }, attended: false },
  { name: "ATTENDED=true, ENTRYPOINT=cli", env: { CLAUDE_CODE_SESSION_ATTENDED: "true", CLAUDE_CODE_ENTRYPOINT: "cli" }, attended: false },
  { name: "ATTENDED=10, ENTRYPOINT=cli", env: { CLAUDE_CODE_SESSION_ATTENDED: "10", CLAUDE_CODE_ENTRYPOINT: "cli" }, attended: false },
  { name: "ATTENDED empty, ENTRYPOINT=cli", env: { CLAUDE_CODE_SESSION_ATTENDED: "", CLAUDE_CODE_ENTRYPOINT: "cli" }, attended: false },
  { name: "ATTENDED=1, ENTRYPOINT unset", env: { CLAUDE_CODE_SESSION_ATTENDED: "1" }, attended: true },
  { name: "ATTENDED=1, ENTRYPOINT empty", env: { CLAUDE_CODE_SESSION_ATTENDED: "1", CLAUDE_CODE_ENTRYPOINT: "" }, attended: true },
  { name: "ATTENDED=1, ENTRYPOINT=claude-desktop", env: { CLAUDE_CODE_SESSION_ATTENDED: "1", CLAUDE_CODE_ENTRYPOINT: "claude-desktop" }, attended: true },
  { name: "ATTENDED=1, ENTRYPOINT=sdk (a prefix of a headless value)", env: { CLAUDE_CODE_SESSION_ATTENDED: "1", CLAUDE_CODE_ENTRYPOINT: "sdk" }, attended: true },
  { name: "ATTENDED=0, ENTRYPOINT=sdk-cli (claude -p)", env: { CLAUDE_CODE_SESSION_ATTENDED: "0", CLAUDE_CODE_ENTRYPOINT: "sdk-cli" }, attended: false },
  { name: "both unset", env: {}, attended: false },
  { name: "data file missing", env: attendedCli, data: null, attended: false },
  { name: "data file empty", env: attendedCli, data: "", attended: false },
  { name: "data file with an empty attended variable name", env: attendedCli, data: real({ SESSION_ATTENDED_VAR: "SESSION_ATTENDED_VAR=" }), attended: false },
  { name: "data file with an empty entrypoint variable name", env: attendedCli, data: real({ SESSION_ATTENDED_ENTRYPOINT_VAR: "SESSION_ATTENDED_ENTRYPOINT_VAR=" }), attended: false },
  { name: "data file with an empty attended value, ATTENDED empty", env: { CLAUDE_CODE_SESSION_ATTENDED: "", CLAUDE_CODE_ENTRYPOINT: "cli" }, data: real({ SESSION_ATTENDED_VALUE: "SESSION_ATTENDED_VALUE=" }), attended: false },
  { name: "data file with an invalid attended variable name", env: { "X-Y": "1", CLAUDE_CODE_ENTRYPOINT: "cli" }, data: real({ SESSION_ATTENDED_VAR: "SESSION_ATTENDED_VAR=X-Y" }), attended: false },
  { name: "data file with an invalid entrypoint variable name", env: { CLAUDE_CODE_SESSION_ATTENDED: "1", "1EP": "cli" }, data: real({ SESSION_ATTENDED_ENTRYPOINT_VAR: "SESSION_ATTENDED_ENTRYPOINT_VAR=1EP" }), attended: false },
  { name: "custom data file with a header, its names and value", env: { X_ATT: "yes", X_EP: "cli" }, data: custom, attended: true },
  { name: "custom data file, second headless value", env: { X_ATT: "yes", X_EP: "cron" }, data: custom, attended: false },
  { name: "custom data file ignores the native names", env: attendedCli, data: custom, attended: false },
];
