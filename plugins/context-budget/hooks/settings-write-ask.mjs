#!/usr/bin/env node
// PreToolUse checkpoint: any Write/Edit/NotebookEdit aimed at a Claude Code settings
// surface returns permissionDecision "ask", forcing a prompt even in
// auto mode (the classifier may still deny; it cannot silently approve).
//
// This is a CHECKPOINT, NOT A GUARANTEE — documented as such in the audit
// skill: a PermissionRequest hook can still allow the call, and
// disableAllHooks removes non-managed hooks. Empirically (headless -p, Linux,
// Claude Code 2.1.263, re-read 2026-09-06): the ask fires and blocks in a
// headless run that skips permissions, under default, auto, and
// bypassPermissions, surfacing as a tool error carrying the
// permissionDecisionReason. Headless "ask" degrades to block-with-reason
// since nothing can prompt. Interactive behavior remains unmeasured; do not
// extrapolate. The checkpoint's value is that a matched file-editing tool
// cannot rewrite a settings file silently while this plugin is enabled.
// A shell write is outside that claim.
//
// Fail-open: on any internal error or unrecognized payload, exit 0 with no
// output — a broken checkpoint must not block unrelated writes. Kill switch:
// userConfig settings_write_ask_enabled, read via its hook-process mirror.
//
// Scope: settings.json / settings.local.json under a .claude directory (any
// depth — project or user-global), plus managed-settings.json. Nothing else
// matches, by design (hook-precision: false positives erode trust in the
// prompt). The matcher sees file-editing tool calls only: a settings write
// through Bash/PowerShell, or one rendered into place by another program,
// never reaches this script, and the hook is deliberately not widened to the
// shell lane (#3864; README "Hook" records the decision).

let raw = '';
process.stdin.on('data', (d) => { raw += d; });
process.stdin.on('end', () => {
  try {
    const payload = JSON.parse(raw);
    if ((process.env.CLAUDE_PLUGIN_OPTION_SETTINGS_WRITE_ASK_ENABLED || 'true') === 'false') {
      process.exit(0);
    }
    const tool = payload.tool_name || '';
    if (!['Write', 'Edit', 'NotebookEdit'].includes(tool)) process.exit(0);
    const target = String(
      payload.tool_input?.file_path || payload.tool_input?.notebook_path || '',
    ).replace(/\\/g, '/');
    if (!target) process.exit(0);

    // Case-insensitive: macOS (APFS/HFS+) and Windows (NTFS) resolve
    // `.claude/Settings.json` to the same file on disk, so a case-sensitive
    // match would let a differently-cased path bypass the checkpoint on
    // exactly the platforms it supports (security-review finding).
    const isSettings = /(^|\/)(\.claude\/settings(\.local)?|managed-settings)\.json$/i.test(target);
    if (!isSettings) process.exit(0);

    const home = String(process.env.HOME || process.env.USERPROFILE || '').replace(/\\/g, '/');
    const userGlobal = home !== ''
      && target.toLowerCase() === `${home}/.claude/settings.json`.toLowerCase();

    // The permission prompt already shows the target path.
    const reason = 'context-budget: this edit changes settings for every future session. Check the diff; '
      + (userGlobal
        ? '/context-budget:audit fix never writes user-global settings, so this write is not from it.'
        : 'from /context-budget:audit fix, it should match the config you approved.');

    process.stdout.write(JSON.stringify({
      hookSpecificOutput: {
        hookEventName: 'PreToolUse',
        permissionDecision: 'ask',
        permissionDecisionReason: reason,
      },
    }));
    process.exit(0);
  } catch {
    process.exit(0); // fail-open, by contract
  }
});
