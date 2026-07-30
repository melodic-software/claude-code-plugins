// Cursor-facing description rewrite.
//
// Claude plugin.json.description stays the Claude SSOT. Cursor marketplace
// entries and .cursor-plugin/plugin.json get a generated description that must
// not promise Claude-only runtime (userConfig prompts, Claude plugin hooks).
//
// Docs:
//   https://cursor.com/docs/reference/plugins#variables  (Plugins → Configure)
//   https://cursor.com/docs/reference/third-party-hooks  (Claude settings hooks ≠ plugin hooks.json)
//   https://code.claude.com/docs/en/plugins-reference   (userConfig, plugin hooks)

const CURSOR_CREDENTIAL_NOTE =
  "Configure the API credential in Cursor under Plugins -> Configure after install.";

const HOOKS_NOTE =
  " Cursor note: on-edit automation is a Claude Code plugin hook " +
  "(hooks/hooks.json). Cursor's documented Claude hook compatibility loads from " +
  ".claude/settings.json (third-party hooks), not this plugin's hooks.json; " +
  "this export ships an empty Cursor-native hooks stub. Skills and agents still load.";

/**
 * @param {string} claudeDescription
 * @param {{ hasClaudePluginHooks: boolean, hasCursorMcp: boolean }} flags
 */
export function cursorDescription(claudeDescription, flags) {
  let description = claudeDescription;

  description = description.replace(
    /Credential entered once through Claude Code's native masked userConfig prompt and stored in secure credential storage\.?/gi,
    CURSOR_CREDENTIAL_NOTE,
  );
  description = description.replace(
    /Claude Code's native masked userConfig prompt/gi,
    "Cursor Plugins -> Configure",
  );
  description = description.replace(
    /Stored by Claude Code in secure credential storage(?:,\s*never settings\.json)?\.?/gi,
    "Set in Cursor under Plugins -> Configure.",
  );

  if (flags.hasCursorMcp && !/Plugins -> Configure/i.test(description)) {
    description = ensureSentence(description) + ` ${CURSOR_CREDENTIAL_NOTE}`;
  }

  if (flags.hasClaudePluginHooks && !description.includes("Cursor note:")) {
    description = ensureSentence(description) + HOOKS_NOTE;
  }

  return description;
}

function ensureSentence(text) {
  const trimmed = text.replace(/\s+$/u, "");
  return trimmed.endsWith(".") ? trimmed : `${trimmed}.`;
}

export { CURSOR_CREDENTIAL_NOTE, HOOKS_NOTE };
