// contract.cjs: the supported surface for code outside this repository that
// loads the Claude lane logic at a pin (claude-code-plugins' eval handoff,
// replay parity and credential-chain tests). Load this module and nothing
// else; every other file here is internal and may change in any release.
//
// To load it, place every path in contract-files.txt (beside this file, one
// repository-relative path per line) under one directory with a
// package.json of {"type":"commonjs"}, then require this file from there.
// contract.test.cjs fails when an export or a required file drifts.
"use strict";

const { isCreditStop } = require("../report-lane-outcome/classify.cjs");
const { HANDOFF_REASONS, leg, next, start } = require("../select-model-credential/select.cjs");
const { SANDBOX_SETTINGS, cliArgs, handoffReason, judgeLeg, legEnv, linesToMessages } = require("./lane.cjs");

module.exports = {
  HANDOFF_REASONS,
  SANDBOX_SETTINGS,
  cliArgs,
  handoffReason,
  isCreditStop,
  judgeLeg,
  leg,
  legEnv,
  linesToMessages,
  next,
  start,
};
