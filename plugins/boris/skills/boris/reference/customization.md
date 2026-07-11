# Customization (Sections 16–27)

Personalizing Claude Code — Part 3 (Feb 11, 2026).

---

## 16. Terminal Configuration

### Configure Your Terminal

Quick settings to make Claude Code feel right:

- **Theme:** `/config` to set light/dark mode
- **Notifications:** Enable notifications for iTerm2, or use a custom notifs hook
- **Newlines:** In IDE terminal, Apple Terminal, Warp, or Alacritty, `/terminal-setup` enables shift+enter for newlines (no need to type `\`)
- **Vim mode:** `/vim`

---

## 17. Effort Level

### Adjust Effort Level

`/model` picks your preferred effort level:

- **Low** — fewer tokens, faster responses
- **Medium** — balanced behavior
- **High** — more tokens, more intelligence

Boris uses High for everything.

---

## 18. Plugins

### Install Plugins, MCPs, and Skills

Plugins install LSPs (every major language), MCPs, skills, agents, custom hooks.

Install from the official Anthropic plugin marketplace, or create your own company marketplace. Check `settings.json` into your codebase to auto-add marketplaces for your team.

`/plugin` to get started.

---

## 19. Custom Agents

### Create Custom Agents

Drop `.md` files in `.claude/agents`. Each agent gets custom name, color, tool set, pre-allowed and pre-disallowed tools, permission mode, model.

**Little-known feature:** Set the default agent for the main conversation. Set `"agent"` in `settings.json` or use `--agent`.

`/agents` to get started.

---

## 20. Permissions Management

### Pre-Approve Common Permissions

Claude Code uses a sophisticated permission system: prompt injection detection, static analysis, sandboxing, human oversight.

Out of the box, we pre-approve a small set of safe commands. To pre-approve more, `/permissions` and add to allow and block lists. Check these into your team's `settings.json`.

**Wildcard syntax:** Full wildcard syntax supported. Try `"Bash(bun run *)"` or `"Edit(/docs/**)"`.

---

## 21. Sandboxing

### Enable Sandboxing

Opt into Claude Code's open source sandbox runtime to improve safety while reducing permission prompts.

`/sandbox` to enable. Sandboxing runs on your machine, supports file and network isolation.

**Modes:**

- Sandbox BashTool, with auto-allow
- Sandbox BashTool, with regular permissions
- No Sandbox

---

## 22. Status Line

### Add a Status Line

Custom status lines show below the composer. Show model, directory, remaining context, cost, anything else you want while working.

Everyone on the Claude Code team has a different statusline. `/statusline` to get started — Claude generates one based on your `.bashrc`/`.zshrc`.

---

## 23. Keybindings

### Customize Your Keybindings

Every key binding in Claude Code is customizable. `/keybindings` to re-map any key. Settings live reload so you see how it feels immediately.

Keybindings are stored in `~/.claude/keybindings.json`.

---

## 24. Hooks (Advanced)

### Set Up Hooks

Hooks deterministically hook into Claude's lifecycle. Use them to:

- Auto-route permission requests to Slack or Opus
- Nudge Claude to keep going at end of turn (can kick off an agent or use a prompt to decide whether Claude should keep going)
- Pre-process or post-process tool calls — e.g., add your own logging

Ask Claude to add a hook to get started.

---

## 25. Spinner Verbs

### Customize Your Spinner Verbs

Little things make CC feel personal. Ask Claude to customize spinner verbs — add or replace the default list with your own.

Check `settings.json` into source control to share verbs with your team.

---

## 26. Output Styles

### Use Output Styles

`/config` and set an output style to have Claude respond in a different tone or format.

- **Explanatory** — great when getting familiar with a new codebase; Claude explains frameworks and code patterns as it works
- **Learning** — Claude coaches you through code changes
- **Custom** — create your own to adjust Claude's voice your way

---

## 27. Customize Everything

### Customize All the Things

Claude Code works great out of the box. When you customize, check `settings.json` into git so your team benefits too.

Configure for codebase, sub-folder, yourself, or via enterprise-wide policies.

**By the numbers:** 37 settings, 84 env vars. Use `"env"` in `settings.json` to avoid wrapper scripts.
