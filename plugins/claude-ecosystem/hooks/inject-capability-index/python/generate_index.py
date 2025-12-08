#!/usr/bin/env python3
"""
generate_index.py - Generate capability index for Claude Code

Scans all installed plugins and extracts capability metadata:
- Skills: plugins/*/skills/*/SKILL.md
- Agents: plugins/*/agents/*.md
- Commands: plugins/*/commands/*.md
- Plugins: plugins/*/.claude-plugin/plugin.json

Outputs a token-efficient index for injection into Claude's context.

Usage:
    python generate_index.py [--detail minimal|standard|comprehensive] [--plugins-dir PATH]

Environment Variables:
    CLAUDE_HOOK_CAPABILITY_INDEX_DETAIL: minimal|standard|comprehensive (default: standard)
"""

import sys
import io
import os
import json
import argparse
from pathlib import Path
from typing import TypedDict, Optional

# Set UTF-8 encoding for stdout/stderr on all platforms (Windows fix)
if sys.stdout.encoding != 'utf-8':
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
if sys.stderr.encoding != 'utf-8':
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8')


def normalize_path(path_str: str) -> Path:
    """
    Normalize path string to handle MSYS-style paths on Windows.

    Converts paths like '/d/repos/...' to 'D:/repos/...' on Windows.

    Args:
        path_str: Path string that may be in MSYS format

    Returns:
        Normalized Path object
    """
    import re

    # Check for MSYS-style path (e.g., /d/repos/...)
    msys_match = re.match(r'^/([a-zA-Z])(/.*)?$', path_str)
    if msys_match and sys.platform == 'win32':
        drive = msys_match.group(1).upper()
        rest = msys_match.group(2) or ''
        path_str = f"{drive}:{rest}"

    return Path(path_str)

# Import local modules
script_dir = Path(__file__).parent
sys.path.insert(0, str(script_dir))
from frontmatter_parser import extract_frontmatter, extract_keywords_from_description, truncate_description


class Skill(TypedDict):
    name: str
    description: str
    short_desc: str
    keywords: list
    tools: str


class Agent(TypedDict):
    name: str
    description: str
    short_desc: str
    model: str
    tools: str


class Command(TypedDict):
    name: str
    description: str


class Plugin(TypedDict):
    name: str
    description: str
    skills: list
    agents: list
    commands: list


def find_plugins_dir() -> Optional[Path]:
    """
    Find the plugins directory by walking up from script location.

    Returns:
        Path to plugins directory, or None if not found
    """
    # Start from script directory and walk up
    current = Path(__file__).resolve().parent

    for _ in range(10):  # Max 10 levels up
        plugins_dir = current / 'plugins'
        if plugins_dir.is_dir():
            return plugins_dir

        parent = current.parent
        if parent == current:  # Reached root
            break
        current = parent

    return None


def scan_plugin(plugin_dir: Path) -> Optional[Plugin]:
    """
    Scan a single plugin directory and extract capabilities.

    Args:
        plugin_dir: Path to plugin directory (e.g., plugins/claude-ecosystem)

    Returns:
        Plugin dict with skills, agents, commands, or None if invalid
    """
    # Check for plugin.json
    plugin_json_paths = [
        plugin_dir / '.claude-plugin' / 'plugin.json',
        plugin_dir / 'plugin.json'
    ]

    plugin_info = None
    for pj_path in plugin_json_paths:
        if pj_path.exists():
            try:
                plugin_info = json.loads(pj_path.read_text(encoding='utf-8'))
                break
            except json.JSONDecodeError as e:
                print(f"Warning: Invalid JSON in {pj_path}: {e}", file=sys.stderr)
            except Exception as e:
                print(f"Warning: Could not read {pj_path}: {e}", file=sys.stderr)

    # Default plugin name to directory name
    plugin_name = plugin_info.get('name', plugin_dir.name) if plugin_info else plugin_dir.name
    plugin_desc = plugin_info.get('description', '') if plugin_info else ''

    # Scan skills
    skills = []
    skills_dir = plugin_dir / 'skills'
    if skills_dir.is_dir():
        for skill_dir in skills_dir.iterdir():
            if skill_dir.is_dir():
                skill_md = skill_dir / 'SKILL.md'
                if skill_md.exists():
                    frontmatter = extract_frontmatter(skill_md)
                    if frontmatter and frontmatter.get('name'):
                        desc = frontmatter.get('description', '')
                        skills.append(Skill(
                            name=frontmatter['name'],
                            description=desc,
                            short_desc=truncate_description(desc, 60),
                            keywords=extract_keywords_from_description(desc, 5),
                            tools=frontmatter.get('allowed-tools', '')
                        ))

    # Scan agents
    agents = []
    agents_dir = plugin_dir / 'agents'
    if agents_dir.is_dir():
        for agent_file in agents_dir.glob('*.md'):
            frontmatter = extract_frontmatter(agent_file)
            if frontmatter and frontmatter.get('name'):
                desc = frontmatter.get('description', '')
                agents.append(Agent(
                    name=frontmatter['name'],
                    description=desc,
                    short_desc=truncate_description(desc, 50),
                    model=frontmatter.get('model', 'sonnet'),
                    tools=frontmatter.get('tools', '')
                ))

    # Scan commands
    commands = []
    commands_dir = plugin_dir / 'commands'
    if commands_dir.is_dir():
        for cmd_file in commands_dir.glob('*.md'):
            frontmatter = extract_frontmatter(cmd_file)
            if frontmatter:
                # Command name is file stem, prefixed with /
                cmd_name = cmd_file.stem
                commands.append(Command(
                    name=cmd_name,
                    description=frontmatter.get('description', '')
                ))

    # Only return if plugin has any capabilities
    if skills or agents or commands:
        return Plugin(
            name=plugin_name,
            description=truncate_description(plugin_desc, 80),
            skills=sorted(skills, key=lambda x: x['name']),
            agents=sorted(agents, key=lambda x: x['name']),
            commands=sorted(commands, key=lambda x: x['name'])
        )

    return None


def scan_all_plugins(plugins_dir: Path) -> list:
    """
    Scan all plugins in the plugins directory.

    Args:
        plugins_dir: Path to plugins directory

    Returns:
        List of Plugin dicts
    """
    plugins = []

    if not plugins_dir.is_dir():
        return plugins

    for plugin_dir in sorted(plugins_dir.iterdir()):
        if plugin_dir.is_dir() and not plugin_dir.name.startswith('.'):
            plugin = scan_plugin(plugin_dir)
            if plugin:
                plugins.append(plugin)

    return plugins


def format_minimal(plugins: list) -> str:
    """
    Format index at minimal detail level (~1,500 tokens).
    Names + 1-line descriptions only.
    """
    lines = ['<capability-index>']

    # Counts
    total_skills = sum(len(p['skills']) for p in plugins)
    total_agents = sum(len(p['agents']) for p in plugins)
    total_commands = sum(len(p['commands']) for p in plugins)

    lines.append(f'CAPABILITIES ({total_skills} skills, {total_agents} agents, {total_commands} commands)')
    lines.append('')

    for plugin in plugins:
        if not (plugin['skills'] or plugin['agents']):
            continue

        lines.append(f"## {plugin['name']}")

        # Skills
        if plugin['skills']:
            for skill in plugin['skills']:
                lines.append(f"- {skill['name']}: {skill['short_desc']}")

        # Agents (key ones only)
        if plugin['agents']:
            for agent in plugin['agents']:
                lines.append(f"- {agent['name']} (agent): {agent['short_desc']}")

        lines.append('')

    lines.append('</capability-index>')
    return '\n'.join(lines)


def format_standard(plugins: list) -> str:
    """
    Format index at standard detail level (~2,200 tokens).
    Names + descriptions + keywords.
    """
    lines = ['<capability-index>']

    # Counts
    total_skills = sum(len(p['skills']) for p in plugins)
    total_agents = sum(len(p['agents']) for p in plugins)
    total_commands = sum(len(p['commands']) for p in plugins)

    lines.append(f'INSTALLED CAPABILITIES ({total_skills} skills, {total_agents} agents, {total_commands} commands across {len(plugins)} plugins)')
    lines.append('')

    for plugin in plugins:
        skill_count = len(plugin['skills'])
        agent_count = len(plugin['agents'])
        cmd_count = len(plugin['commands'])

        if not (skill_count or agent_count):
            continue

        lines.append(f"## {plugin['name']} ({skill_count} skills, {agent_count} agents)")

        # Skills with keywords
        if plugin['skills']:
            lines.append('Skills:')
            for skill in plugin['skills']:
                kw_str = ', '.join(skill['keywords'][:4]) if skill['keywords'] else ''
                if kw_str:
                    lines.append(f"- {skill['name']}: {skill['short_desc']} | KW: {kw_str}")
                else:
                    lines.append(f"- {skill['name']}: {skill['short_desc']}")

        # Agents with model
        if plugin['agents']:
            lines.append('Agents:')
            for agent in plugin['agents']:
                lines.append(f"- {agent['name']} ({agent['model']}): {agent['short_desc']}")

        # Commands (abbreviated list)
        if plugin['commands']:
            cmd_names = [f"/{c['name']}" for c in plugin['commands'][:8]]
            if len(plugin['commands']) > 8:
                cmd_names.append(f"+{len(plugin['commands']) - 8} more")
            lines.append(f"Commands: {', '.join(cmd_names)}")

        lines.append('')

    lines.append('</capability-index>')
    return '\n'.join(lines)


def format_comprehensive(plugins: list) -> str:
    """
    Format index at comprehensive detail level (~3,500 tokens).
    Full descriptions, all keywords, usage triggers.
    """
    lines = ['<capability-index>']

    # Counts
    total_skills = sum(len(p['skills']) for p in plugins)
    total_agents = sum(len(p['agents']) for p in plugins)
    total_commands = sum(len(p['commands']) for p in plugins)

    lines.append(f'COMPLETE CAPABILITY INDEX')
    lines.append(f'Statistics: {total_skills} skills, {total_agents} agents, {total_commands} commands across {len(plugins)} plugins')
    lines.append('')

    for plugin in plugins:
        skill_count = len(plugin['skills'])
        agent_count = len(plugin['agents'])
        cmd_count = len(plugin['commands'])

        if not (skill_count or agent_count or cmd_count):
            continue

        lines.append(f"## {plugin['name']}")
        if plugin['description']:
            lines.append(f"_{plugin['description']}_")
        lines.append('')

        # Skills with full detail
        if plugin['skills']:
            lines.append('### Skills')
            for skill in plugin['skills']:
                lines.append(f"**{skill['name']}**")
                # Full description (first ~150 chars)
                desc = skill['description'][:150] + '...' if len(skill['description']) > 150 else skill['description']
                lines.append(f"  {desc}")
                if skill['keywords']:
                    lines.append(f"  Keywords: {', '.join(skill['keywords'])}")
                if skill['tools']:
                    lines.append(f"  Tools: {skill['tools']}")
                lines.append('')

        # Agents with triggers
        if plugin['agents']:
            lines.append('### Agents')
            for agent in plugin['agents']:
                lines.append(f"**{agent['name']}** (model: {agent['model']})")
                desc = agent['description'][:120] + '...' if len(agent['description']) > 120 else agent['description']
                lines.append(f"  {desc}")
                if agent['tools']:
                    lines.append(f"  Tools: {agent['tools']}")
                lines.append('')

        # Commands with descriptions
        if plugin['commands']:
            lines.append('### Commands')
            for cmd in plugin['commands']:
                desc = cmd['description'][:60] + '...' if len(cmd['description']) > 60 else cmd['description']
                lines.append(f"- /{cmd['name']}: {desc}")
            lines.append('')

    # Quick reference table
    lines.append('## Quick Reference')
    lines.append('| Need | Use |')
    lines.append('|------|-----|')
    lines.append('| Claude docs | docs-management skill |')
    lines.append('| Known bugs | claude-code-issue-researcher agent |')
    lines.append('| Code review | code-reviewer agent |')
    lines.append('| Markdown lint | markdown-linting skill |')
    lines.append('| Gemini CLI | gemini-cli-docs skill |')
    lines.append('')

    lines.append('</capability-index>')
    return '\n'.join(lines)


def format_index(plugins: list, detail_level: str = 'standard') -> str:
    """
    Format capability index based on detail level.

    Args:
        plugins: List of Plugin dicts
        detail_level: 'minimal', 'standard', or 'comprehensive'

    Returns:
        Formatted index string
    """
    if detail_level == 'minimal':
        return format_minimal(plugins)
    elif detail_level == 'comprehensive':
        return format_comprehensive(plugins)
    else:
        return format_standard(plugins)


def estimate_tokens(text: str) -> int:
    """
    Estimate token count (rough approximation: chars / 4).

    Args:
        text: Text to estimate

    Returns:
        Estimated token count
    """
    return len(text) // 4


def main():
    parser = argparse.ArgumentParser(description='Generate capability index for Claude Code')
    parser.add_argument('--detail', choices=['minimal', 'standard', 'comprehensive'],
                        default=os.environ.get('CLAUDE_HOOK_CAPABILITY_INDEX_DETAIL', 'standard'),
                        help='Detail level (default: standard)')
    parser.add_argument('--plugins-dir', type=str, default=None,
                        help='Path to plugins directory')
    parser.add_argument('--output', choices=['json', 'text'], default='json',
                        help='Output format (default: json)')

    args = parser.parse_args()

    # Find plugins directory
    if args.plugins_dir is not None:
        plugins_dir = normalize_path(args.plugins_dir)
    else:
        plugins_dir = find_plugins_dir()

    if plugins_dir is None or not plugins_dir.is_dir():
        print(json.dumps({
            'error': 'Plugins directory not found',
            'index': '',
            'stats': {}
        }), file=sys.stderr)
        sys.exit(1)

    # Scan all plugins
    plugins = scan_all_plugins(plugins_dir)

    # Format index
    index_text = format_index(plugins, args.detail)
    token_estimate = estimate_tokens(index_text)

    # Output
    if args.output == 'text':
        print(index_text)
    else:
        result = {
            'index': index_text,
            'stats': {
                'plugins': len(plugins),
                'skills': sum(len(p['skills']) for p in plugins),
                'agents': sum(len(p['agents']) for p in plugins),
                'commands': sum(len(p['commands']) for p in plugins),
                'detail_level': args.detail,
                'estimated_tokens': token_estimate,
                'character_count': len(index_text)
            }
        }
        print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
