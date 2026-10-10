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
// A shell write is outside that claim. Recheck when a Claude Code changelog entry changes how a
// PreToolUse "ask" resolves in a headless run.
//
// Fail-open: on any internal error or unrecognized payload, exit 0 with no
// output — a broken checkpoint must not block unrelated writes. Kill switch:
// userConfig settings_write_ask_enabled, read via its hook-process mirror.
//
// Scope: the settings files Claude Code reads, and nothing else (hook-precision:
// false positives erode trust in the prompt, so a fixture named
// `.claude/settings.json` passes silently). Those are settings.json in the user
// settings directory ($CLAUDE_CONFIG_DIR, else ~/.claude); settings(.local).json
// in `.claude/` under the session's project directory or the payload cwd;
// settings.local.json at the main checkout's root (Claude Code keeps it there
// when a session starts in a subdirectory or a linked worktree); plus
// managed-settings.json and managed-settings.d/*.json in the managed system
// directory. Paths:
// https://code.claude.com/docs/en/settings and /docs/en/managed-settings, as of
// 2026-10-09; recheck when either page moves a settings path. The matcher sees
// file-editing tool calls only: a settings write through Bash/PowerShell, or one
// rendered into place by another program, never reaches this script, and the
// hook is deliberately not widened to the shell lane (#3864; README "Hook"
// records the decision).

import { execFileSync } from 'node:child_process';

const slash = (p) => String(p || '').replace(/\\/g, '/').replace(/\/+$/, '');
// Windows resolves through PROGRAMFILES, as lib/managed-scope.sh does, so a
// relocated Program Files directory still matches.
const MANAGED_DIRS = [
  '/Library/Application Support/ClaudeCode',
  '/etc/claude-code',
  `${slash(process.env.PROGRAMFILES) || 'C:/Program Files'}/ClaudeCode`,
];

// The root Claude Code keeps settings.local.json at: the main checkout's root,
// which is the cwd's toplevel except in a linked worktree.
function localSettingsRoot(cwd) {
  try {
    const [top, common] = execFileSync('git', ['-C', cwd, 'rev-parse', '--path-format=absolute',
      '--show-toplevel', '--git-common-dir'], {
      encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], timeout: 2000,
    }).split('\n').map(slash);
    return /\/\.git$/i.test(common) ? common.slice(0, -5) : top;
  } catch {
    return '';
  }
}

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
    const target = slash(payload.tool_input?.file_path || payload.tool_input?.notebook_path);
    if (!target) process.exit(0);

    // Case-insensitive: macOS (APFS/HFS+) and Windows (NTFS) resolve
    // `.claude/Settings.json` to the same file on disk, so a case-sensitive
    // match would let a differently-cased path bypass the checkpoint on
    // exactly the platforms it supports (security-review finding).
    const name = /\/(settings(\.local)?\.json|managed-settings(\.d\/[^/]+)?\.json)$/i.exec(target)?.[1];
    if (!name) process.exit(0);
    const dir = target.slice(0, -name.length - 1).toLowerCase();
    const isDir = (d) => d !== '' && dir === d.toLowerCase();

    const home = slash(process.env.HOME || process.env.USERPROFILE);
    const userDir = slash(process.env.CLAUDE_CONFIG_DIR) || (home && `${home}/.claude`);
    const userGlobal = /^settings\.json$/i.test(name) && isDir(userDir);

    let live = userGlobal;
    if (!live && /^managed/i.test(name)) {
      live = MANAGED_DIRS.some(isDir);
    } else if (!live) {
      const cwd = slash(payload.cwd);
      const atRoot = (r) => isDir(r && `${r}/.claude`);
      live = atRoot(slash(process.env.CLAUDE_PROJECT_DIR)) || atRoot(cwd)
        || (/local/i.test(name) && cwd !== '' && atRoot(localSettingsRoot(cwd)));
    }
    if (!live) process.exit(0);

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
