#!/usr/bin/env node
// PreToolUse checkpoint: any Write/Edit/MultiEdit/NotebookEdit aimed at a Claude Code
// settings surface returns permissionDecision "ask", forcing a prompt even in
// auto mode (the classifier may still deny; it cannot silently approve).
//
// This is a CHECKPOINT, NOT A GUARANTEE — documented as such in the audit
// skill: a PermissionRequest hook can still allow the call, and
// disableAllHooks removes non-managed hooks. Empirically (v2.1.232, headless
// -p mode, Linux): the ask fires and blocks the call even under
// bypassPermissions, surfacing to the model as a tool error carrying the
// permissionDecisionReason — headless "ask" degrades to block-with-reason
// since nothing can prompt. Interactive bypassPermissions behavior remains
// unmeasured; do not extrapolate. The checkpoint's value is that the
// ordinary auto-mode path cannot rewrite settings silently while this
// plugin is enabled.
//
// Fail-open: on any internal error or unrecognized payload, exit 0 with no
// output — a broken checkpoint must not block unrelated writes. Kill switch:
// userConfig settings_write_ask_enabled, read via its hook-process mirror.
//
// Scope: settings.json / settings.local.json under a .claude directory (any
// depth — project or user-global), plus managed-settings.json. Nothing else
// matches, by design (hook-precision: false positives erode trust in the
// prompt).

let raw = '';
process.stdin.on('data', (d) => { raw += d; });
process.stdin.on('end', () => {
  try {
    const payload = JSON.parse(raw);
    if ((process.env.CLAUDE_PLUGIN_OPTION_SETTINGS_WRITE_ASK_ENABLED || 'true') === 'false') {
      process.exit(0);
    }
    const tool = payload.tool_name || '';
    if (!['Write', 'Edit', 'MultiEdit', 'NotebookEdit'].includes(tool)) process.exit(0);
    const target = String(
      payload.tool_input?.file_path || payload.tool_input?.notebook_path || '',
    ).replace(/\\/g, '/');
    if (!target) process.exit(0);

    // Case-insensitive: macOS (APFS/HFS+) and Windows (NTFS) resolve
    // `.claude/Settings.json` to the same file on disk, so a case-sensitive
    // match would let a differently-cased path bypass the checkpoint on
    // exactly the platforms it supports (security-review finding).
    const isSettings = /(^|\/)\.claude\/settings(\.local)?\.json$/i.test(target)
      || /(^|\/)managed-settings\.json$/i.test(target);
    if (!isSettings) process.exit(0);

    const home = String(process.env.HOME || process.env.USERPROFILE || '').replace(/\\/g, '/');
    const userGlobal = home !== ''
      && target.toLowerCase() === `${home}/.claude/settings.json`.toLowerCase();

    const reason = `${target} is a Claude Code settings surface. This prompt is the context-budget `
      + 'plugin\'s checkpoint: settings edits change every future session, so confirm the exact diff '
      + 'before it lands. If this write came from the /context-budget:audit fix path, the printed '
      + 'config and the measured delta should match what you approved'
      + (userGlobal ? '; note the audit itself never writes user-global settings — it prints them.' : '.');

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
