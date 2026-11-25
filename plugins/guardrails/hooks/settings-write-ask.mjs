#!/usr/bin/env node

import { execFileSync } from 'node:child_process';

const slash = (p) => String(p || '').replace(/\\/g, '/').replace(/\/+$/, '');
const MANAGED_DIRS = [
  '/Library/Application Support/ClaudeCode',
  '/etc/claude-code',
  `${slash(process.env.PROGRAMFILES) || 'C:/Program Files'}/ClaudeCode`,
];

function localSettingsRoot(cwd) {
  try {
    const [top, common] = execFileSync('git', ['--no-pager', '-c', 'core.fsmonitor=false',
      '-c', 'core.hooksPath=/dev/null', '-C', cwd, 'rev-parse', '--path-format=absolute',
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
process.stdin.on('end', async () => {
  try {
    const payload = JSON.parse(raw);
    if ((process.env.CLAUDE_PLUGIN_OPTION_SETTINGS_WRITE_ASK_ENABLED || 'true') === 'false') {
      process.exit(0);
    }
    const tool = payload.tool_name || '';
    if (!['Write', 'Edit', 'NotebookEdit'].includes(tool)) process.exit(0);
    const target = slash(payload.tool_input?.file_path || payload.tool_input?.notebook_path);
    if (!target) process.exit(0);

    const name = /\/(settings(\.local)?\.json|managed-settings(\.d\/[^/]+)?\.json)$/i.exec(target)?.[1];
    if (!name) process.exit(0);
    const dir = target.slice(0, -name.length - 1).toLowerCase();
    const isDir = (d) => d !== '' && dir === d.toLowerCase();

    const home = slash(process.env.HOME || process.env.USERPROFILE);
    const userDir = slash(process.env.CLAUDE_CONFIG_DIR) || (home && `${home}/.claude`);
    const userGlobal = /^settings\.json$/i.test(name) && isDir(userDir);

    const cwd = slash(payload.cwd);
    const atRoot = (r) => isDir(r && `${r}/.claude`);
    const live = userGlobal || (/^managed/i.test(name)
      ? MANAGED_DIRS.some(isDir)
      : atRoot(slash(process.env.CLAUDE_PROJECT_DIR)) || atRoot(cwd)
        || (/local/i.test(name) && cwd !== '' && atRoot(localSettingsRoot(cwd))));
    if (!live) process.exit(0);

    const { sessionAttended } = await import('./session-attended.mjs')
      .catch(() => ({ sessionAttended: () => false }));
    const asks = sessionAttended(process.env) && process.env.GUARDRAILS_SESSION_UNWATCHED !== '1';
    const reason = 'guardrails: this edit changes settings for every future session. '
      + (!asks
        ? 'Nobody can answer a prompt in this session (unattended, or GUARDRAILS_SESSION_UNWATCHED=1), '
          + 'so it was refused. Do not retry it another way; report the change for a person to make.'
        : userGlobal
          ? 'Check the diff; /context-budget:audit fix never writes user-global settings, so this write is not from it.'
          : 'Check the diff; from /context-budget:audit fix, it should match the config you approved.');

    process.stdout.write(JSON.stringify({
      hookSpecificOutput: {
        hookEventName: 'PreToolUse',
        permissionDecision: asks ? 'ask' : 'deny',
        permissionDecisionReason: reason,
      },
    }));
    process.exit(0);
  } catch {
    process.exit(0);
  }
});
